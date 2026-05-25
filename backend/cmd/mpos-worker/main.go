package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/SidGrip/php-mpos/backend/internal/config"
	store "github.com/SidGrip/php-mpos/backend/internal/db"
	"github.com/SidGrip/php-mpos/backend/internal/jobs"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.Load()
	if err != nil {
		logger.Error("load config", "error", err)
		os.Exit(1)
	}

	db, err := store.Open(context.Background(), cfg.DatabaseDSN)
	if err != nil {
		logger.Error("open database", "error", err)
		os.Exit(1)
	}
	if db != nil {
		defer db.Close()
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	worker := jobs.NewWorker(jobs.Dependencies{
		Config: cfg,
		DB:     db,
		Logger: logger,
	})
	if err := worker.Run(ctx); err != nil {
		logger.Error("worker stopped with error", "error", err)
		os.Exit(1)
	}
}
