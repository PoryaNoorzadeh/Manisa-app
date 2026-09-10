package config

import "os"

type Config struct {
	HTTPAddr     string
	DatabasePath string
}

func Load() Config {
	return Config{
		HTTPAddr:     getenv("MANISA_HTTP_ADDR", ":8080"),
		DatabasePath: getenv("MANISA_DB_PATH", "./data/manisa.db"),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
