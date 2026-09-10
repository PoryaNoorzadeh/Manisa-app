package config

import "os"

type Config struct {
	HTTPAddr     string
	DatabasePath string
	MatterWSURL  string
}

func Load() Config {
	return Config{
		HTTPAddr:     getenv("MANISA_HTTP_ADDR", ":8080"),
		DatabasePath: getenv("MANISA_DB_PATH", "./data/manisa.db"),
		MatterWSURL:  getenv("MANISA_MATTER_WS_URL", "ws://127.0.0.1:5580/ws"),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
