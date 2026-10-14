package capability

import (
	"encoding/json"
	"math"
	"testing"
)

func TestFromMatterAttribute(t *testing.T) {
	tests := []struct {
		name        string
		productType string
		path        string
		value       any
		capability  string
		want        any
	}{
		{name: "switch", productType: "switch_1gang", path: "1/6/0", value: true, capability: OnOff, want: true},
		{name: "dimmer", productType: "dimmer_1gang", path: "1/8/0", value: json.Number("127"), capability: Level, want: 50},
		{name: "temperature", productType: "climate_sensor", path: "1/1026/0", value: json.Number("2345"), capability: Temperature, want: 23.45},
		{name: "humidity", productType: "climate_sensor", path: "1/1029/0", value: json.Number("5123"), capability: Humidity, want: 51.23},
		{name: "motion", productType: "motion_sensor", path: "1/1030/0", value: json.Number("1"), capability: Motion, want: true},
		{name: "contact", productType: "contact_sensor", path: "1/69/0", value: false, capability: Contact, want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mapping, ok := FromMatterAttribute(tt.productType, tt.path, tt.value)
			if !ok {
				t.Fatal("expected mapping")
			}
			if mapping.Capability != tt.capability {
				t.Fatalf("expected capability %s, got %s", tt.capability, mapping.Capability)
			}
			switch want := tt.want.(type) {
			case float64:
				got, ok := mapping.Value.(float64)
				if !ok || math.Abs(got-want) > 0.0001 {
					t.Fatalf("expected %v, got %#v", want, mapping.Value)
				}
			default:
				if mapping.Value != want {
					t.Fatalf("expected %#v, got %#v", want, mapping.Value)
				}
			}
		})
	}
}

func TestFromMatterAttributeRejectsCapabilityNotInProduct(t *testing.T) {
	if _, ok := FromMatterAttribute("motion_sensor", "1/6/0", true); ok {
		t.Fatal("motion sensor must not expose on_off state")
	}
}
