package matterjs

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

type listenNode struct {
	NodeID     json.RawMessage            `json:"node_id"`
	Attributes map[string]json.RawMessage `json:"attributes"`
}

type wireEvent struct {
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

func (c *Client) Listen(ctx context.Context, handler func(context.Context, matter.AttributeEvent) error) error {
	if handler == nil {
		return fmt.Errorf("matter event handler is required")
	}

	conn, _, err := websocket.Dial(ctx, c.url, nil)
	if err != nil {
		return fmt.Errorf("connect matter event stream: %w", err)
	}
	defer conn.CloseNow()

	var serverInfo map[string]any
	if err := wsjson.Read(ctx, conn, &serverInfo); err != nil {
		return fmt.Errorf("read matter server info: %w", err)
	}

	initialRaw, err := c.call(ctx, conn, "start_listening", map[string]any{})
	if err != nil {
		return fmt.Errorf("start matter event stream: %w", err)
	}
	if err := dispatchInitialAttributes(ctx, initialRaw, handler); err != nil {
		return err
	}

	for {
		var event wireEvent
		if err := wsjson.Read(ctx, conn, &event); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("read matter event: %w", err)
		}

		switch event.Event {
		case "attribute_updated":
			attribute, err := decodeAttributeEvent(event.Data, false)
			if err != nil {
				return fmt.Errorf("decode matter attribute event: %w", err)
			}
			if err := handler(ctx, attribute); err != nil {
				return fmt.Errorf("handle matter attribute event: %w", err)
			}
		case "node_added", "node_updated":
			if err := dispatchNodeAttributes(ctx, event.Data, false, handler); err != nil {
				return fmt.Errorf("handle %s event: %w", event.Event, err)
			}
		case "server_shutdown":
			return fmt.Errorf("matter server shutdown")
		}
	}
}

func dispatchInitialAttributes(ctx context.Context, raw json.RawMessage, handler func(context.Context, matter.AttributeEvent) error) error {
	var nodes []json.RawMessage
	if err := json.Unmarshal(raw, &nodes); err != nil {
		return fmt.Errorf("decode initial matter nodes: %w", err)
	}
	for _, node := range nodes {
		if err := dispatchNodeAttributes(ctx, node, true, handler); err != nil {
			return err
		}
	}
	return nil
}

func dispatchNodeAttributes(ctx context.Context, raw json.RawMessage, initial bool, handler func(context.Context, matter.AttributeEvent) error) error {
	var node listenNode
	if err := json.Unmarshal(raw, &node); err != nil {
		return fmt.Errorf("decode matter node: %w", err)
	}
	nodeID, err := nodeIDFromRaw(node.NodeID)
	if err != nil {
		return fmt.Errorf("decode matter node id: %w", err)
	}
	for path, rawValue := range node.Attributes {
		value, err := decodeJSONValue(rawValue)
		if err != nil {
			return fmt.Errorf("decode matter attribute %s: %w", path, err)
		}
		if err := handler(ctx, matter.AttributeEvent{
			NodeID:  matter.NodeID(nodeID),
			Path:    path,
			Value:   value,
			Initial: initial,
		}); err != nil {
			return fmt.Errorf("handle matter attribute: %w", err)
		}
	}
	return nil
}

func decodeAttributeEvent(raw json.RawMessage, initial bool) (matter.AttributeEvent, error) {
	var parts []json.RawMessage
	if err := json.Unmarshal(raw, &parts); err != nil {
		return matter.AttributeEvent{}, err
	}
	if len(parts) != 3 {
		return matter.AttributeEvent{}, fmt.Errorf("expected 3 event fields, got %d", len(parts))
	}

	nodeID, err := nodeIDFromRaw(parts[0])
	if err != nil {
		return matter.AttributeEvent{}, err
	}
	var path string
	if err := json.Unmarshal(parts[1], &path); err != nil {
		return matter.AttributeEvent{}, err
	}
	value, err := decodeJSONValue(parts[2])
	if err != nil {
		return matter.AttributeEvent{}, err
	}
	return matter.AttributeEvent{
		NodeID:  matter.NodeID(nodeID),
		Path:    path,
		Value:   value,
		Initial: initial,
	}, nil
}

func nodeIDFromRaw(raw json.RawMessage) (string, error) {
	value := bytes.TrimSpace(raw)
	if len(value) == 0 {
		return "", fmt.Errorf("node id empty")
	}
	if value[0] == '"' {
		var encoded string
		if err := json.Unmarshal(value, &encoded); err != nil {
			return "", err
		}
		encoded = strings.TrimSpace(encoded)
		if _, err := strconv.ParseUint(encoded, 10, 64); err != nil {
			return "", err
		}
		return encoded, nil
	}
	encoded := string(value)
	if _, err := strconv.ParseUint(encoded, 10, 64); err != nil {
		return "", err
	}
	return encoded, nil
}

func decodeJSONValue(raw json.RawMessage) (any, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, err
	}
	return value, nil
}
