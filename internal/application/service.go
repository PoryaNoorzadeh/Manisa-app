package application

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
	platformid "github.com/PoryaNoorzadeh/Manisa-app/internal/platform/id"
)

var ErrInvalidInput = errors.New("invalid input")

type Service struct {
	store domain.Store
}

func New(store domain.Store) *Service { return &Service{store: store} }

func (s *Service) CreateHome(ctx context.Context, name string) (domain.Home, error) {
	name = strings.TrimSpace(name)
	if name == "" { return domain.Home{}, ErrInvalidInput }
	id, err := platformid.New("home")
	if err != nil { return domain.Home{}, err }
	now := time.Now().UTC()
	home := domain.Home{ID: id, Name: name, CreatedAt: now, UpdatedAt: now}
	return home, s.store.CreateHome(ctx, home)
}

func (s *Service) ListHomes(ctx context.Context) ([]domain.Home, error) {
	return s.store.ListHomes(ctx)
}

func (s *Service) CreateRoom(ctx context.Context, homeID, name string) (domain.Room, error) {
	homeID, name = strings.TrimSpace(homeID), strings.TrimSpace(name)
	if homeID == "" || name == "" { return domain.Room{}, ErrInvalidInput }
	id, err := platformid.New("room")
	if err != nil { return domain.Room{}, err }
	now := time.Now().UTC()
	room := domain.Room{ID: id, HomeID: homeID, Name: name, CreatedAt: now, UpdatedAt: now}
	return room, s.store.CreateRoom(ctx, room)
}

func (s *Service) ListRooms(ctx context.Context, homeID string) ([]domain.Room, error) {
	if strings.TrimSpace(homeID) == "" { return nil, ErrInvalidInput }
	return s.store.ListRooms(ctx, homeID)
}

func (s *Service) CreateDevice(ctx context.Context, homeID, name, productType, transport string, roomID *string) (domain.Device, error) {
	homeID, name, productType, transport = strings.TrimSpace(homeID), strings.TrimSpace(name), strings.TrimSpace(productType), strings.TrimSpace(transport)
	if homeID == "" || name == "" || productType == "" || transport == "" { return domain.Device{}, ErrInvalidInput }
	if transport != domain.TransportMatterWiFi && transport != domain.TransportMatterThread { return domain.Device{}, ErrInvalidInput }
	id, err := platformid.New("device")
	if err != nil { return domain.Device{}, err }
	now := time.Now().UTC()
	device := domain.Device{ID: id, HomeID: homeID, RoomID: roomID, Name: name, ProductType: productType, Transport: transport, CreatedAt: now, UpdatedAt: now}
	return device, s.store.CreateDevice(ctx, device)
}

func (s *Service) ListDevices(ctx context.Context, homeID string) ([]domain.Device, error) {
	if strings.TrimSpace(homeID) == "" { return nil, ErrInvalidInput }
	return s.store.ListDevices(ctx, homeID)
}
