package application

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/capability"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	platformid "github.com/PoryaNoorzadeh/Manisa-app/internal/platform/id"
)

var (
	ErrInvalidInput          = errors.New("invalid input")
	ErrMatterUnavailable     = errors.New("matter controller unavailable")
	ErrUnsupportedCapability = errors.New("unsupported capability")
)

type Service struct {
	store  domain.Store
	matter matter.Controller
}

func New(store domain.Store, matterController ...matter.Controller) *Service {
	var controller matter.Controller
	if len(matterController) > 0 {
		controller = matterController[0]
	}
	return &Service{store: store, matter: controller}
}

func (s *Service) CreateHome(ctx context.Context, name string) (domain.Home, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return domain.Home{}, ErrInvalidInput
	}
	id, err := platformid.New("home")
	if err != nil {
		return domain.Home{}, err
	}
	now := time.Now().UTC()
	home := domain.Home{ID: id, Name: name, CreatedAt: now, UpdatedAt: now}
	return home, s.store.CreateHome(ctx, home)
}

func (s *Service) ListHomes(ctx context.Context) ([]domain.Home, error) {
	return s.store.ListHomes(ctx)
}

func (s *Service) CreateRoom(ctx context.Context, homeID, name string) (domain.Room, error) {
	homeID, name = strings.TrimSpace(homeID), strings.TrimSpace(name)
	if homeID == "" || name == "" {
		return domain.Room{}, ErrInvalidInput
	}
	id, err := platformid.New("room")
	if err != nil {
		return domain.Room{}, err
	}
	now := time.Now().UTC()
	room := domain.Room{ID: id, HomeID: homeID, Name: name, CreatedAt: now, UpdatedAt: now}
	return room, s.store.CreateRoom(ctx, room)
}

func (s *Service) ListRooms(ctx context.Context, homeID string) ([]domain.Room, error) {
	if strings.TrimSpace(homeID) == "" {
		return nil, ErrInvalidInput
	}
	return s.store.ListRooms(ctx, homeID)
}

func (s *Service) CreateDevice(ctx context.Context, homeID, name, productType, transport string, roomID *string) (domain.Device, error) {
	homeID, name, productType, transport = strings.TrimSpace(homeID), strings.TrimSpace(name), strings.TrimSpace(productType), strings.TrimSpace(transport)
	if homeID == "" || name == "" || productType == "" || transport == "" {
		return domain.Device{}, ErrInvalidInput
	}
	if _, ok := capability.Get(productType); !ok {
		return domain.Device{}, ErrInvalidInput
	}
	if transport != domain.TransportMatterWiFi && transport != domain.TransportMatterThread {
		return domain.Device{}, ErrInvalidInput
	}
	id, err := platformid.New("device")
	if err != nil {
		return domain.Device{}, err
	}
	now := time.Now().UTC()
	device := domain.Device{ID: id, HomeID: homeID, RoomID: roomID, Name: name, ProductType: productType, Transport: transport, CreatedAt: now, UpdatedAt: now}
	return device, s.store.CreateDevice(ctx, device)
}

func (s *Service) ListDevices(ctx context.Context, homeID string) ([]domain.Device, error) {
	if strings.TrimSpace(homeID) == "" {
		return nil, ErrInvalidInput
	}
	return s.store.ListDevices(ctx, homeID)
}

func (s *Service) ListDeviceTypes() []domain.DeviceDescriptor {
	return capability.List()
}

func (s *Service) DeviceDescriptor(ctx context.Context, deviceID string) (domain.DeviceDescriptor, error) {
	device, err := s.store.GetDevice(ctx, strings.TrimSpace(deviceID))
	if err != nil {
		return domain.DeviceDescriptor{}, err
	}
	descriptor, ok := capability.Get(device.ProductType)
	if !ok {
		return domain.DeviceDescriptor{}, ErrUnsupportedCapability
	}
	return descriptor, nil
}

func (s *Service) CommissionMatterDevice(ctx context.Context, homeID, name, productType, transport string, roomID *string, request matter.CommissionRequest) (domain.Device, error) {
	if s.matter == nil {
		return domain.Device{}, ErrMatterUnavailable
	}
	if _, ok := capability.Get(productType); !ok {
		return domain.Device{}, ErrInvalidInput
	}
	result, err := s.matter.Commission(ctx, request)
	if err != nil {
		return domain.Device{}, err
	}

	device, err := s.CreateDevice(ctx, homeID, name, productType, transport, roomID)
	if err != nil {
		_ = s.matter.RemoveNode(context.WithoutCancel(ctx), result.NodeID)
		return domain.Device{}, err
	}

	nodeID := string(result.NodeID)
	if err := s.store.BindDeviceExternalNode(ctx, device.ID, nodeID); err != nil {
		_ = s.matter.RemoveNode(context.WithoutCancel(ctx), result.NodeID)
		return domain.Device{}, err
	}
	device.ExternalNodeID = &nodeID
	return device, nil
}

func (s *Service) ExecuteDeviceCommand(ctx context.Context, deviceID string, command matter.Command) error {
	if s.matter == nil {
		return ErrMatterUnavailable
	}
	device, err := s.store.GetDevice(ctx, strings.TrimSpace(deviceID))
	if err != nil {
		return err
	}
	if device.ExternalNodeID == nil || *device.ExternalNodeID == "" {
		return ErrInvalidInput
	}
	if !capability.Supports(device.ProductType, command.Endpoint, command.Capability) {
		return ErrUnsupportedCapability
	}
	return s.matter.Execute(ctx, matter.NodeID(*device.ExternalNodeID), command)
}
