package domain

import "context"

type Store interface {
	CreateHome(ctx context.Context, home Home) error
	ListHomes(ctx context.Context) ([]Home, error)
	CreateRoom(ctx context.Context, room Room) error
	ListRooms(ctx context.Context, homeID string) ([]Room, error)
	CreateDevice(ctx context.Context, device Device) error
	ListDevices(ctx context.Context, homeID string) ([]Device, error)
}
