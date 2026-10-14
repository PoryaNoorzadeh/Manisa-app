package domain

import "time"

type Home struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type Room struct {
	ID        string    `json:"id"`
	HomeID    string    `json:"homeId"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type Device struct {
	ID             string    `json:"id"`
	HomeID         string    `json:"homeId"`
	RoomID         *string   `json:"roomId,omitempty"`
	Name           string    `json:"name"`
	ProductType    string    `json:"productType"`
	Transport      string    `json:"transport"`
	ExternalNodeID *string   `json:"externalNodeId,omitempty"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

type DeviceState struct {
	DeviceID   string    `json:"deviceId"`
	Endpoint   uint16    `json:"endpoint"`
	Capability string    `json:"capability"`
	Value      any       `json:"value"`
	Source     string    `json:"source"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

type LocalClient struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	TokenHash string    `json:"-"`
	CreatedAt time.Time `json:"createdAt"`
	LastUsed  time.Time `json:"lastUsed"`
}

type RealtimeEvent struct {
	Sequence   uint64    `json:"sequence"`
	Type       string    `json:"type"`
	DeviceID   string    `json:"deviceId,omitempty"`
	Endpoint   uint16    `json:"endpoint,omitempty"`
	Capability string    `json:"capability,omitempty"`
	Value      any       `json:"value,omitempty"`
	Source     string    `json:"source,omitempty"`
	Initial    bool      `json:"initial,omitempty"`
	Timestamp  time.Time `json:"timestamp"`
}

type CapabilityDescriptor struct {
	ID       string         `json:"id"`
	Readable bool           `json:"readable"`
	Writable bool           `json:"writable"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

type EndpointDescriptor struct {
	ID           uint16                 `json:"id"`
	Name         string                 `json:"name"`
	Capabilities []CapabilityDescriptor `json:"capabilities"`
}

type DeviceDescriptor struct {
	ProductType string               `json:"productType"`
	DisplayName string               `json:"displayName"`
	Category    string               `json:"category"`
	Endpoints   []EndpointDescriptor `json:"endpoints"`
}

const (
	TransportMatterWiFi   = "matter_wifi"
	TransportMatterThread = "matter_thread"
)
