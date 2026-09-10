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
	ID             string     `json:"id"`
	HomeID         string     `json:"homeId"`
	RoomID         *string    `json:"roomId,omitempty"`
	Name           string     `json:"name"`
	ProductType    string     `json:"productType"`
	Transport      string     `json:"transport"`
	ExternalNodeID *string    `json:"externalNodeId,omitempty"`
	CreatedAt      time.Time  `json:"createdAt"`
	UpdatedAt      time.Time  `json:"updatedAt"`
}

const (
	TransportMatterWiFi   = "matter_wifi"
	TransportMatterThread = "matter_thread"
)
