package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
)

func (s *Store) CreateLocalClient(ctx context.Context, client domain.LocalClient) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO local_clients(id,name,token_hash,created_at,last_used) VALUES(?,?,?,?,?)`,
		client.ID, client.Name, client.TokenHash,
		client.CreatedAt.UTC().Format(time.RFC3339Nano), client.LastUsed.UTC().Format(time.RFC3339Nano))
	if err != nil {
		return fmt.Errorf("create local client: %w", err)
	}
	return nil
}

func (s *Store) GetLocalClientByTokenHash(ctx context.Context, tokenHash string) (domain.LocalClient, error) {
	var client domain.LocalClient
	var created, lastUsed string
	err := s.db.QueryRowContext(ctx, `SELECT id,name,token_hash,created_at,last_used FROM local_clients WHERE token_hash=?`, tokenHash).
		Scan(&client.ID, &client.Name, &client.TokenHash, &created, &lastUsed)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.LocalClient{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.LocalClient{}, fmt.Errorf("get local client: %w", err)
	}
	client.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
	client.LastUsed, _ = time.Parse(time.RFC3339Nano, lastUsed)
	return client, nil
}

func (s *Store) TouchLocalClient(ctx context.Context, clientID string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE local_clients SET last_used=? WHERE id=?`, time.Now().UTC().Format(time.RFC3339Nano), clientID)
	return err
}
