package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
	platformid "github.com/PoryaNoorzadeh/Manisa-app/internal/platform/id"
)

var ErrUnauthorized = errors.New("unauthorized")

type Service struct {
	store       domain.Store
	pairingCode string
}

func New(store domain.Store, pairingCode string) *Service {
	return &Service{store: store, pairingCode: pairingCode}
}

func (s *Service) Pair(ctx context.Context, code, clientName string) (domain.LocalClient, string, error) {
	code = strings.TrimSpace(code)
	clientName = strings.TrimSpace(clientName)
	if clientName == "" || subtle.ConstantTimeCompare([]byte(code), []byte(s.pairingCode)) != 1 {
		return domain.LocalClient{}, "", ErrUnauthorized
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return domain.LocalClient{}, "", err
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	id, err := platformid.New("client")
	if err != nil {
		return domain.LocalClient{}, "", err
	}
	now := time.Now().UTC()
	client := domain.LocalClient{ID: id, Name: clientName, TokenHash: hashToken(token), CreatedAt: now, LastUsed: now}
	if err := s.store.CreateLocalClient(ctx, client); err != nil {
		return domain.LocalClient{}, "", err
	}
	return client, token, nil
}

func (s *Service) Authenticate(ctx context.Context, token string) (domain.LocalClient, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return domain.LocalClient{}, ErrUnauthorized
	}
	client, err := s.store.GetLocalClientByTokenHash(ctx, hashToken(token))
	if err != nil {
		return domain.LocalClient{}, ErrUnauthorized
	}
	_ = s.store.TouchLocalClient(ctx, client.ID)
	return client, nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
