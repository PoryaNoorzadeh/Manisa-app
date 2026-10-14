package matterjs

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

var ErrServer = errors.New("matter server error")

type Client struct {
	url     string
	nextID  atomic.Uint64
	timeout time.Duration
}

type wireRequest struct {
	MessageID string `json:"message_id"`
	Command   string `json:"command"`
	Args      any    `json:"args,omitempty"`
}

type wireResponse struct {
	MessageID string          `json:"message_id"`
	Result    json.RawMessage `json:"result"`
	ErrorCode *int            `json:"error_code,omitempty"`
	Details   string          `json:"details,omitempty"`
}

func New(url string) *Client {
	return &Client{url: strings.TrimSpace(url), timeout: 60 * time.Second}
}

func (c *Client) Commission(ctx context.Context, req matter.CommissionRequest) (matter.CommissionResult, error) {
	if strings.TrimSpace(req.SetupPayload) == "" {
		return matter.CommissionResult{}, fmt.Errorf("setup payload is required")
	}

	var result json.RawMessage
	err := c.withConnection(ctx, func(ctx context.Context, conn *websocket.Conn) error {
		if req.WiFiSSID != "" {
			if _, err := c.call(ctx, conn, "set_wifi_credentials", map[string]any{
				"ssid":        req.WiFiSSID,
				"credentials": req.WiFiPassword,
			}); err != nil {
				return fmt.Errorf("set wifi credentials: %w", err)
			}
		}
		if req.ThreadDataset != "" {
			if _, err := c.call(ctx, conn, "set_thread_dataset", map[string]any{
				"dataset": req.ThreadDataset,
			}); err != nil {
				return fmt.Errorf("set thread dataset: %w", err)
			}
		}

		args := map[string]any{"code": req.SetupPayload}
		if req.NetworkOnly {
			args["network_only"] = true
		}
		var err error
		result, err = c.call(ctx, conn, "commission_with_code", args)
		return err
	})
	if err != nil {
		return matter.CommissionResult{}, err
	}

	nodeID, err := nodeIDFromResult(result)
	if err != nil {
		return matter.CommissionResult{}, fmt.Errorf("decode commissioned node: %w", err)
	}
	return matter.CommissionResult{NodeID: matter.NodeID(nodeID)}, nil
}

func (c *Client) RemoveNode(ctx context.Context, nodeID matter.NodeID) error {
	id, err := parseNodeID(nodeID)
	if err != nil {
		return err
	}
	return c.withConnection(ctx, func(ctx context.Context, conn *websocket.Conn) error {
		_, err := c.call(ctx, conn, "remove_node", map[string]any{"node_id": id})
		return err
	})
}

func (c *Client) Execute(ctx context.Context, nodeID matter.NodeID, command matter.Command) error {
	id, err := parseNodeID(nodeID)
	if err != nil {
		return err
	}
	if command.Endpoint == 0 || command.ClusterID == 0 || strings.TrimSpace(command.Name) == "" {
		return fmt.Errorf("invalid matter command")
	}
	payload := command.Payload
	if payload == nil {
		payload = map[string]any{}
	}
	return c.withConnection(ctx, func(ctx context.Context, conn *websocket.Conn) error {
		_, err := c.call(ctx, conn, "device_command", map[string]any{
			"node_id":       id,
			"endpoint_id":   command.Endpoint,
			"cluster_id":    command.ClusterID,
			"command_name":  command.Name,
			"payload":       payload,
			"response_type": nil,
		})
		return err
	})
}

func (c *Client) withConnection(parent context.Context, fn func(context.Context, *websocket.Conn) error) error {
	ctx := parent
	var cancel context.CancelFunc
	if _, ok := parent.Deadline(); !ok && c.timeout > 0 {
		ctx, cancel = context.WithTimeout(parent, c.timeout)
		defer cancel()
	}

	conn, _, err := websocket.Dial(ctx, c.url, nil)
	if err != nil {
		return fmt.Errorf("connect matter server: %w", err)
	}
	defer conn.CloseNow()

	var serverInfo map[string]any
	if err := wsjson.Read(ctx, conn, &serverInfo); err != nil {
		return fmt.Errorf("read matter server info: %w", err)
	}

	if err := fn(ctx, conn); err != nil {
		return err
	}
	_ = conn.Close(websocket.StatusNormalClosure, "")
	return nil
}

func (c *Client) call(ctx context.Context, conn *websocket.Conn, command string, args any) (json.RawMessage, error) {
	messageID := strconv.FormatUint(c.nextID.Add(1), 10)
	if err := wsjson.Write(ctx, conn, wireRequest{MessageID: messageID, Command: command, Args: args}); err != nil {
		return nil, fmt.Errorf("write %s request: %w", command, err)
	}

	for {
		var response wireResponse
		if err := wsjson.Read(ctx, conn, &response); err != nil {
			return nil, fmt.Errorf("read %s response: %w", command, err)
		}
		if response.MessageID != messageID {
			continue
		}
		if response.ErrorCode != nil {
			return nil, fmt.Errorf("%w: command=%s code=%d details=%s", ErrServer, command, *response.ErrorCode, response.Details)
		}
		return response.Result, nil
	}
}

func parseNodeID(nodeID matter.NodeID) (uint64, error) {
	value := strings.TrimSpace(string(nodeID))
	id, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid matter node id %q: %w", value, err)
	}
	return id, nil
}

func nodeIDFromResult(raw json.RawMessage) (string, error) {
	var object map[string]json.RawMessage
	if err := json.Unmarshal(raw, &object); err != nil {
		return "", err
	}
	value, ok := object["node_id"]
	if !ok {
		return "", fmt.Errorf("node_id missing")
	}
	value = bytes.TrimSpace(value)
	if len(value) == 0 {
		return "", fmt.Errorf("node_id empty")
	}
	if value[0] == '"' {
		var s string
		if err := json.Unmarshal(value, &s); err != nil {
			return "", err
		}
		if _, err := strconv.ParseUint(s, 10, 64); err != nil {
			return "", err
		}
		return s, nil
	}
	if _, err := strconv.ParseUint(string(value), 10, 64); err != nil {
		return "", err
	}
	return string(value), nil
}
