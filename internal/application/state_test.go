package application_test

import (
	"context"
	"testing"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

type stateTestMatterController struct {
	nodeID matter.NodeID
}

func (f *stateTestMatterController) Commission(context.Context, matter.CommissionRequest) (matter.CommissionResult, error) {
	return matter.CommissionResult{NodeID: f.nodeID}, nil
}

func (f *stateTestMatterController) RemoveNode(context.Context, matter.NodeID) error { return nil }

func (f *stateTestMatterController) Execute(context.Context, matter.NodeID, matter.Command) error {
	return nil
}

func TestMatterAttributePersistsAndPublishesCanonicalState(t *testing.T) {
	ctx := context.Background()
	db, err := sqlite.Open(t.TempDir() + "/manisa.db")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	controller := &stateTestMatterController{nodeID: "42"}
	app := application.New(sqlite.NewStore(db), controller)
	home, err := app.CreateHome(ctx, "Lab")
	if err != nil {
		t.Fatal(err)
	}
	device, err := app.CommissionDevice(ctx, application.CommissionDeviceInput{
		HomeID:       home.ID,
		Name:         "Switch",
		ProductType:  "switch_1gang",
		Transport:    "matter_wifi",
		SetupPayload: "MT:TEST",
		WiFiSSID:     "ManisaLab",
	})
	if err != nil {
		t.Fatal(err)
	}

	events, unsubscribe := app.SubscribeEvents(4)
	defer unsubscribe()
	if err := app.ApplyMatterAttribute(ctx, matter.AttributeEvent{
		NodeID: "42",
		Path:   "1/6/0",
		Value:  true,
	}); err != nil {
		t.Fatal(err)
	}

	states, err := app.DeviceStates(ctx, device.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(states) != 1 || states[0].Capability != "on_off" || states[0].Value != true {
		t.Fatalf("unexpected states: %#v", states)
	}

	select {
	case event := <-events:
		if event.Type != "device.state_changed" || event.DeviceID != device.ID || event.Capability != "on_off" || event.Value != true {
			t.Fatalf("unexpected realtime event: %#v", event)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for realtime event")
	}
}
