package config

import (
	"os"
	"time"

	"github.com/SidGrip/php-mpos/backend/internal/domain"
)

type Config struct {
	HTTPAddr       string
	DatabaseDSN    string
	SessionCookie  string
	WorkerInterval time.Duration
	Slots          []domain.CoinSlot
}

func Load() (Config, error) {
	return Config{
		HTTPAddr:       env("MPOS_GO_HTTP_ADDR", ":8080"),
		DatabaseDSN:    os.Getenv("MPOS_GO_DATABASE_DSN"),
		SessionCookie:  env("MPOS_GO_SESSION_COOKIE", "__Host-session"),
		WorkerInterval: durationEnv("MPOS_GO_WORKER_INTERVAL", 30*time.Second),
		Slots:          domain.DefaultSlots(),
	}, nil
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func durationEnv(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}
