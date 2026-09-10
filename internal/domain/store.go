package domain

import (
	"context"
	"errors"
)

var ErrNotFound = errors.New("not found")

type Store interface {
	CreateHome(ctx context.Context, home Home) error
	ListHomes(ctx context.Context) ([]Home, error)
	CreateRoom(ctx context.Context, room Room) error
	ListRooms(ctx context.Context, homeID string) ([]Room, error)
	CreateDevice(ctx context.Context, device Device) error
	GetDevice(ctx context.Context, deviceID string) (Device, error)
	GetDeviceByExternalNodeID(ctx context.Context, externalNodeID string) (Device, error)
	ListDevices(ctx context.Context, homeID string) ([]Device, error)
	UpsertDeviceState(ctx context.Context, state DeviceState) error
	ListDeviceStates(ctx context.Context, deviceID string) ([]DeviceState, error)
}
