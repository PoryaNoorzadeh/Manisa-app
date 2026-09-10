package matterjs

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

func TestCommissionWiFiDevice(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			t.Errorf("accept websocket: %v", err)
			return
		}
		defer conn.CloseNow()
		ctx := context.Background()

		if err := wsjson.Write(ctx, conn, map[string]any{
			"fabric_id": 1, "schema_version": 13, "sdk_version": "test",
		}); err != nil {
			t.Errorf("write server info: %v", err)
			return
		}

		var setCreds wireRequest
		if err := wsjson.Read(ctx, conn, &setCreds); err != nil {
			t.Errorf("read wifi credentials: %v", err)
			return
		}
		if setCreds.Command != "set_wifi_credentials" {
			t.Errorf("expected set_wifi_credentials, got %s", setCreds.Command)
			return
		}
		if err := wsjson.Write(ctx, conn, map[string]any{"message_id": setCreds.MessageID, "result": map[string]any{}}); err != nil {
			t.Errorf("respond wifi credentials: %v", err)
			return
		}

		var commission wireRequest
		if err := wsjson.Read(ctx, conn, &commission); err != nil {
			t.Errorf("read commission: %v", err)
			return
		}
		if commission.Command != "commission_with_code" {
			t.Errorf("expected commission_with_code, got %s", commission.Command)
			return
		}
		if err := wsjson.Write(ctx, conn, map[string]any{
			"message_id": commission.MessageID,
			"result":     map[string]any{"node_id": 42},
		}); err != nil {
			t.Errorf("respond commission: %v", err)
		}
	}))
	defer server.Close()

	client := New("ws" + strings.TrimPrefix(server.URL, "http"))
	result, err := client.Commission(context.Background(), matter.CommissionRequest{
		SetupPayload: "MT:TEST",
		WiFiSSID:     "ManisaLab",
		WiFiPassword: "secret",
	})
	if err != nil {
		t.Fatalf("commission: %v", err)
	}
	if result.NodeID != "42" {
		t.Fatalf("expected node 42, got %s", result.NodeID)
	}
}

func TestExecuteCommand(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			t.Errorf("accept websocket: %v", err)
			return
		}
		defer conn.CloseNow()
		ctx := context.Background()
		_ = wsjson.Write(ctx, conn, map[string]any{"fabric_id": 1, "schema_version": 13})

		var req wireRequest
		if err := wsjson.Read(ctx, conn, &req); err != nil {
			t.Errorf("read command: %v", err)
			return
		}
		if req.Command != "device_command" {
			t.Errorf("expected device_command, got %s", req.Command)
			return
		}
		_ = wsjson.Write(ctx, conn, map[string]any{"message_id": req.MessageID, "result": nil})
	}))
	defer server.Close()

	client := New("ws" + strings.TrimPrefix(server.URL, "http"))
	if err := client.Execute(context.Background(), "42", matter.Command{
		Endpoint:  1,
		ClusterID: 6,
		Name:      "on",
	}); err != nil {
		t.Fatalf("execute: %v", err)
	}
}
