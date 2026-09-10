package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	HTTPAddr     string
	DatabasePath string
	MatterWSURL  string
	PairingCode  string
}

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:     getenv("MANISA_HTTP_ADDR", ":8080"),
		DatabasePath: getenv("MANISA_DB_PATH", "./data/manisa.db"),
		MatterWSURL:  getenv("MANISA_MATTER_WS_URL", "ws://127.0.0.1:5580/ws"),
		PairingCode:  strings.TrimSpace(os.Getenv("MANISA_PAIRING_CODE")),
	}
	if len(cfg.PairingCode) < 8 {
		return Config{}, fmt.Errorf("MANISA_PAIRING_CODE must be configured with at least 8 characters")
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
