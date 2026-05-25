package jobs

import (
	"context"
	"database/sql"
	"log/slog"
	"time"

	"github.com/SidGrip/php-mpos/backend/internal/config"
)

type Dependencies struct {
	Config config.Config
	DB     *sql.DB
	Logger *slog.Logger
}

type Worker struct {
	cfg    config.Config
	db     *sql.DB
	logger *slog.Logger
}

func NewWorker(deps Dependencies) *Worker {
	logger := deps.Logger
	if logger == nil {
		logger = slog.Default()
	}
	return &Worker{cfg: deps.Config, db: deps.DB, logger: logger}
}

func (w *Worker) Run(ctx context.Context) error {
	ticker := time.NewTicker(w.cfg.WorkerInterval)
	defer ticker.Stop()

	w.logger.Info("mpos worker started", "interval", w.cfg.WorkerInterval.String(), "databaseConfigured", w.db != nil)
	for {
		select {
		case <-ctx.Done():
			w.logger.Info("mpos worker stopped")
			return nil
		case <-ticker.C:
			w.logger.Debug("worker tick")
		}
	}
}
