package capability

import (
	"fmt"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
)

const (
	OnOff       = "on_off"
	Level       = "level"
	Temperature = "temperature"
	Humidity    = "humidity"
	Motion      = "motion"
	Contact     = "contact"
	Power       = "power"
	Energy      = "energy"
)

var catalog = map[string]domain.DeviceDescriptor{
	"switch_1gang": switchDescriptor("switch_1gang", "Manisa 1-Gang Touch Switch", 1),
	"switch_2gang": switchDescriptor("switch_2gang", "Manisa 2-Gang Touch Switch", 2),
	"switch_3gang": switchDescriptor("switch_3gang", "Manisa 3-Gang Touch Switch", 3),
	"dimmer_1gang": {
		ProductType: "dimmer_1gang",
		DisplayName: "Manisa Touch Dimmer",
		Category:    "dimmer",
		Endpoints: []domain.EndpointDescriptor{{
			ID:   1,
			Name: "Channel 1",
			Capabilities: []domain.CapabilityDescriptor{
				{ID: OnOff, Readable: true, Writable: true},
				{ID: Level, Readable: true, Writable: true, Metadata: map[string]any{"min": 0, "max": 100}},
			},
		}},
	},
	"socket": {
		ProductType: "socket",
		DisplayName: "Manisa Smart Socket",
		Category:    "socket",
		Endpoints: []domain.EndpointDescriptor{{
			ID:   1,
			Name: "Outlet",
			Capabilities: []domain.CapabilityDescriptor{
				{ID: OnOff, Readable: true, Writable: true},
				{ID: Power, Readable: true, Writable: false, Metadata: map[string]any{"unit": "W"}},
				{ID: Energy, Readable: true, Writable: false, Metadata: map[string]any{"unit": "Wh"}},
			},
		}},
	},
	"climate_sensor": {
		ProductType: "climate_sensor",
		DisplayName: "Manisa Climate Sensor",
		Category:    "sensor",
		Endpoints: []domain.EndpointDescriptor{{
			ID:   1,
			Name: "Environment",
			Capabilities: []domain.CapabilityDescriptor{
				{ID: Temperature, Readable: true, Writable: false, Metadata: map[string]any{"unit": "C"}},
				{ID: Humidity, Readable: true, Writable: false, Metadata: map[string]any{"unit": "%"}},
			},
		}},
	},
	"motion_sensor": {
		ProductType: "motion_sensor",
		DisplayName: "Manisa Motion Sensor",
		Category:    "sensor",
		Endpoints: []domain.EndpointDescriptor{{
			ID:           1,
			Name:         "Motion",
			Capabilities: []domain.CapabilityDescriptor{{ID: Motion, Readable: true, Writable: false}},
		}},
	},
	"contact_sensor": {
		ProductType: "contact_sensor",
		DisplayName: "Manisa Door/Window Sensor",
		Category:    "sensor",
		Endpoints: []domain.EndpointDescriptor{{
			ID:           1,
			Name:         "Contact",
			Capabilities: []domain.CapabilityDescriptor{{ID: Contact, Readable: true, Writable: false}},
		}},
	},
}

func switchDescriptor(productType, displayName string, gangs int) domain.DeviceDescriptor {
	endpoints := make([]domain.EndpointDescriptor, 0, gangs)
	for i := 1; i <= gangs; i++ {
		endpoints = append(endpoints, domain.EndpointDescriptor{
			ID:           uint16(i),
			Name:         fmt.Sprintf("Channel %d", i),
			Capabilities: []domain.CapabilityDescriptor{{ID: OnOff, Readable: true, Writable: true}},
		})
	}
	return domain.DeviceDescriptor{
		ProductType: productType,
		DisplayName: displayName,
		Category:    "switch",
		Endpoints:   endpoints,
	}
}

func Get(productType string) (domain.DeviceDescriptor, bool) {
	descriptor, ok := catalog[productType]
	return descriptor, ok
}

func List() []domain.DeviceDescriptor {
	result := make([]domain.DeviceDescriptor, 0, len(catalog))
	for _, descriptor := range catalog {
		result = append(result, descriptor)
	}
	return result
}

func Supports(productType string, endpoint uint16, capabilityID string) bool {
	descriptor, ok := Get(productType)
	if !ok {
		return false
	}
	for _, ep := range descriptor.Endpoints {
		if ep.ID != endpoint {
			continue
		}
		for _, capability := range ep.Capabilities {
			if capability.ID == capabilityID {
				return true
			}
		}
	}
	return false
}
