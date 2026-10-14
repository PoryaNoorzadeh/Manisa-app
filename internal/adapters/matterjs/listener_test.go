package matterjs

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

func TestListenSeedsInitialStateAndStreamsUpdates(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			t.Errorf("accept websocket: %v", err)
			return
		}
		defer conn.CloseNow()
		ctx := r.Context()

		if err := wsjson.Write(ctx, conn, map[string]any{"schema_version": 13}); err != nil {
			return
		}
		var request wireRequest
		if err := wsjson.Read(ctx, conn, &request); err != nil {
			return
		}
		if request.Command != "start_listening" {
			t.Errorf("expected start_listening, got %s", request.Command)
			return
		}
		if err := wsjson.Write(ctx, conn, map[string]any{
			"message_id": request.MessageID,
			"result": []any{
				map[string]any{
					"node_id":    42,
					"attributes": map[string]any{"1/6/0": false},
				},
			},
		}); err != nil {
			return
		}
		_ = wsjson.Write(ctx, conn, map[string]any{
			"event": "attribute_updated",
			"data":  []any{42, "1/6/0", true},
		})
		<-ctx.Done()
	}))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
	client := New(wsURL)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	events := make(chan matter.AttributeEvent, 2)
	errCh := make(chan error, 1)
	go func() {
		errCh <- client.Listen(ctx, func(_ context.Context, event matter.AttributeEvent) error {
			events <- event
			return nil
		})
	}()

	first := <-events
	second := <-events
	if !first.Initial || first.NodeID != "42" || first.Path != "1/6/0" || first.Value != false {
		t.Fatalf("unexpected initial event: %#v", first)
	}
	if second.Initial || second.NodeID != "42" || second.Path != "1/6/0" || second.Value != true {
		t.Fatalf("unexpected update event: %#v", second)
	}

	cancel()
	select {
	case <-errCh:
	case <-time.After(time.Second):
		t.Fatal("listener did not stop after context cancellation")
	}
}
