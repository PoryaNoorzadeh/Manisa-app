package application

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/capability"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	platformid "github.com/PoryaNoorzadeh/Manisa-app/internal/platform/id"
)

var (
	ErrInvalidInput          = errors.New("invalid input")
	ErrDeviceNotCommissioned = errors.New("device is not commissioned")
	ErrUnsupportedCapability = errors.New("unsupported capability")
)

type Service struct {
	store  domain.Store
	matter matter.Controller
}

type CommissionDeviceInput struct {
	HomeID        string
	RoomID        *string
	Name          string
	ProductType   string
	Transport     string
	SetupPayload  string
	WiFiSSID      string
	WiFiPassword  string
	ThreadDataset string
	NetworkOnly   bool
}

type DeviceCommandInput struct {
	Endpoint   uint16
	Capability string
	Action     string
	Params     map[string]any
}

func New(store domain.Store, matterController matter.Controller) *Service {
	return &Service{store: store, matter: matterController}
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
	return s.createDevice(ctx, homeID, name, productType, transport, roomID, nil)
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
	deviceID = strings.TrimSpace(deviceID)
	if deviceID == "" {
		return domain.DeviceDescriptor{}, ErrInvalidInput
	}
	device, err := s.store.GetDevice(ctx, deviceID)
	if err != nil {
		return domain.DeviceDescriptor{}, err
	}
	descriptor, ok := capability.Get(device.ProductType)
	if !ok {
		return domain.DeviceDescriptor{}, ErrUnsupportedCapability
	}
	return descriptor, nil
}

func (s *Service) CommissionDevice(ctx context.Context, input CommissionDeviceInput) (domain.Device, error) {
	if s.matter == nil {
		return domain.Device{}, fmt.Errorf("matter controller unavailable")
	}
	input.HomeID = strings.TrimSpace(input.HomeID)
	input.Name = strings.TrimSpace(input.Name)
	input.ProductType = strings.TrimSpace(input.ProductType)
	input.Transport = strings.TrimSpace(input.Transport)
	input.SetupPayload = strings.TrimSpace(input.SetupPayload)
	if input.HomeID == "" || input.Name == "" || input.ProductType == "" || input.SetupPayload == "" {
		return domain.Device{}, ErrInvalidInput
	}
	if _, ok := capability.Get(input.ProductType); !ok {
		return domain.Device{}, ErrInvalidInput
	}
	if input.Transport != domain.TransportMatterWiFi && input.Transport != domain.TransportMatterThread {
		return domain.Device{}, ErrInvalidInput
	}
	if input.Transport == domain.TransportMatterWiFi && input.WiFiSSID == "" && !input.NetworkOnly {
		return domain.Device{}, ErrInvalidInput
	}
	if input.Transport == domain.TransportMatterThread && input.ThreadDataset == "" && !input.NetworkOnly {
		return domain.Device{}, ErrInvalidInput
	}

	result, err := s.matter.Commission(ctx, matter.CommissionRequest{
		SetupPayload:  input.SetupPayload,
		WiFiSSID:      input.WiFiSSID,
		WiFiPassword:  input.WiFiPassword,
		ThreadDataset: input.ThreadDataset,
		NetworkOnly:   input.NetworkOnly,
	})
	if err != nil {
		return domain.Device{}, fmt.Errorf("commission matter device: %w", err)
	}

	nodeID := string(result.NodeID)
	device, err := s.createDevice(ctx, input.HomeID, input.Name, input.ProductType, input.Transport, input.RoomID, &nodeID)
	if err != nil {
		rollbackCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = s.matter.RemoveNode(rollbackCtx, result.NodeID)
		return domain.Device{}, fmt.Errorf("register commissioned device: %w", err)
	}
	return device, nil
}

func (s *Service) ExecuteDeviceCommand(ctx context.Context, deviceID string, input DeviceCommandInput) error {
	deviceID = strings.TrimSpace(deviceID)
	input.Capability = strings.TrimSpace(input.Capability)
	input.Action = strings.TrimSpace(input.Action)
	if deviceID == "" || input.Endpoint == 0 || input.Capability == "" || input.Action == "" {
		return ErrInvalidInput
	}
	if s.matter == nil {
		return fmt.Errorf("matter controller unavailable")
	}
	device, err := s.store.GetDevice(ctx, deviceID)
	if err != nil {
		return err
	}
	if device.ExternalNodeID == nil || strings.TrimSpace(*device.ExternalNodeID) == "" {
		return ErrDeviceNotCommissioned
	}
	if !capability.Supports(device.ProductType, input.Endpoint, input.Capability) {
		return ErrUnsupportedCapability
	}
	command, err := mapDeviceCommand(input)
	if err != nil {
		return err
	}
	if err := s.matter.Execute(ctx, matter.NodeID(*device.ExternalNodeID), command); err != nil {
		return fmt.Errorf("execute matter command: %w", err)
	}
	return nil
}

func (s *Service) createDevice(ctx context.Context, homeID, name, productType, transport string, roomID *string, externalNodeID *string) (domain.Device, error) {
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
	device := domain.Device{
		ID:             id,
		HomeID:         homeID,
		RoomID:         roomID,
		Name:           name,
		ProductType:    productType,
		Transport:      transport,
		ExternalNodeID: externalNodeID,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	return device, s.store.CreateDevice(ctx, device)
}

func mapDeviceCommand(input DeviceCommandInput) (matter.Command, error) {
	payload := input.Params
	if payload == nil {
		payload = map[string]any{}
	}
	switch input.Capability {
	case capability.OnOff:
		switch input.Action {
		case "on", "off", "toggle":
			return matter.Command{Endpoint: input.Endpoint, ClusterID: 6, Name: input.Action, Payload: payload}, nil
		default:
			return matter.Command{}, ErrUnsupportedCapability
		}
	case capability.Level:
		if input.Action != "set_level" {
			return matter.Command{}, ErrUnsupportedCapability
		}
		percent, ok := numericParam(payload, "level")
		if !ok || percent < 0 || percent > 100 {
			return matter.Command{}, ErrInvalidInput
		}
		matterLevel := int(percent * 254 / 100)
		return matter.Command{
			Endpoint:  input.Endpoint,
			ClusterID: 8,
			Name:      "moveToLevelWithOnOff",
			Payload:   map[string]any{"level": matterLevel},
		}, nil
	default:
		return matter.Command{}, ErrUnsupportedCapability
	}
}

func numericParam(params map[string]any, key string) (float64, bool) {
	value, ok := params[key]
	if !ok {
		return 0, false
	}
	switch v := value.(type) {
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	case int32:
		return float64(v), true
	default:
		return 0, false
	}
}
