package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store { return &Store{db: db} }

func (s *Store) CreateHome(ctx context.Context, home domain.Home) error {
	_, err := s.db.ExecContext(
		ctx,
		`INSERT INTO homes(id,name,created_at,updated_at) VALUES(?,?,?,?)`,
		home.ID,
		home.Name,
		home.CreatedAt.UTC().Format(time.RFC3339Nano),
		home.UpdatedAt.UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return fmt.Errorf("create home: %w", err)
	}
	return nil
}

func (s *Store) ListHomes(ctx context.Context) ([]domain.Home, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,name,created_at,updated_at FROM homes ORDER BY created_at`)
	if err != nil {
		return nil, fmt.Errorf("list homes: %w", err)
	}
	defer rows.Close()

	var out []domain.Home
	for rows.Next() {
		var h domain.Home
		var created, updated string
		if err := rows.Scan(&h.ID, &h.Name, &created, &updated); err != nil {
			return nil, err
		}
		h.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
		h.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
		out = append(out, h)
	}
	return out, rows.Err()
}

func (s *Store) CreateRoom(ctx context.Context, room domain.Room) error {
	_, err := s.db.ExecContext(
		ctx,
		`INSERT INTO rooms(id,home_id,name,created_at,updated_at) VALUES(?,?,?,?,?)`,
		room.ID,
		room.HomeID,
		room.Name,
		room.CreatedAt.UTC().Format(time.RFC3339Nano),
		room.UpdatedAt.UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return fmt.Errorf("create room: %w", err)
	}
	return nil
}

func (s *Store) ListRooms(ctx context.Context, homeID string) ([]domain.Room, error) {
	rows, err := s.db.QueryContext(
		ctx,
		`SELECT id,home_id,name,created_at,updated_at FROM rooms WHERE home_id=? ORDER BY created_at`,
		homeID,
	)
	if err != nil {
		return nil, fmt.Errorf("list rooms: %w", err)
	}
	defer rows.Close()

	var out []domain.Room
	for rows.Next() {
		var r domain.Room
		var created, updated string
		if err := rows.Scan(&r.ID, &r.HomeID, &r.Name, &created, &updated); err != nil {
			return nil, err
		}
		r.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
		r.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) CreateDevice(ctx context.Context, device domain.Device) error {
	_, err := s.db.ExecContext(
		ctx,
		`INSERT INTO devices(id,home_id,room_id,name,product_type,transport,external_node_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)`,
		device.ID,
		device.HomeID,
		device.RoomID,
		device.Name,
		device.ProductType,
		device.Transport,
		device.ExternalNodeID,
		device.CreatedAt.UTC().Format(time.RFC3339Nano),
		device.UpdatedAt.UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return fmt.Errorf("create device: %w", err)
	}
	return nil
}

func (s *Store) GetDevice(ctx context.Context, deviceID string) (domain.Device, error) {
	row := s.db.QueryRowContext(
		ctx,
		`SELECT id,home_id,room_id,name,product_type,transport,external_node_id,created_at,updated_at FROM devices WHERE id=?`,
		deviceID,
	)
	device, err := scanDevice(row.Scan)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Device{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Device{}, fmt.Errorf("get device: %w", err)
	}
	return device, nil
}

func (s *Store) ListDevices(ctx context.Context, homeID string) ([]domain.Device, error) {
	rows, err := s.db.QueryContext(
		ctx,
		`SELECT id,home_id,room_id,name,product_type,transport,external_node_id,created_at,updated_at FROM devices WHERE home_id=? ORDER BY created_at`,
		homeID,
	)
	if err != nil {
		return nil, fmt.Errorf("list devices: %w", err)
	}
	defer rows.Close()

	var out []domain.Device
	for rows.Next() {
		device, err := scanDevice(rows.Scan)
		if err != nil {
			return nil, err
		}
		out = append(out, device)
	}
	return out, rows.Err()
}

type scanFunc func(dest ...any) error

func scanDevice(scan scanFunc) (domain.Device, error) {
	var d domain.Device
	var roomID, nodeID sql.NullString
	var created, updated string
	if err := scan(&d.ID, &d.HomeID, &roomID, &d.Name, &d.ProductType, &d.Transport, &nodeID, &created, &updated); err != nil {
		return domain.Device{}, err
	}
	if roomID.Valid {
		d.RoomID = &roomID.String
	}
	if nodeID.Valid {
		d.ExternalNodeID = &nodeID.String
	}
	d.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
	d.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
	return d, nil
}
