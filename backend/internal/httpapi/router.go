package httpapi

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/SidGrip/php-mpos/backend/internal/auth"
	"github.com/SidGrip/php-mpos/backend/internal/config"
)

type Dependencies struct {
	Config config.Config
	DB     *sql.DB
	Logger *slog.Logger
}

type Server struct {
	cfg     config.Config
	db      *sql.DB
	logger  *slog.Logger
	started time.Time
}

func New(deps Dependencies) *Server {
	logger := deps.Logger
	if logger == nil {
		logger = slog.Default()
	}
	return &Server{
		cfg:     deps.Config,
		db:      deps.DB,
		logger:  logger,
		started: time.Now(),
	}
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(auth.SameOriginGuard)

	r.Get("/healthz", s.health)
	r.Get("/readyz", s.ready)

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/session", s.session)
		r.Get("/me", s.me)
		r.Get("/pools", s.pools)
		r.Get("/pools/{poolID}/stats", planned("pool stats parity endpoint"))
		r.Get("/pools/{poolID}/blocks", planned("pool blocks parity endpoint"))
		r.Get("/pools/{poolID}/payments", planned("pool payments parity endpoint"))
		r.Get("/miners/{address}/dashboard", planned("miner dashboard parity endpoint"))
		r.Get("/miners/{address}/workers", planned("miner workers parity endpoint"))
		r.Route("/admin", func(r chi.Router) {
			r.Get("/users", planned("admin users endpoint"))
			r.Get("/workers", planned("admin workers endpoint"))
			r.Get("/payouts", planned("admin payouts endpoint"))
			r.Get("/jobs", planned("admin jobs endpoint"))
			r.Get("/audit", planned("admin audit endpoint"))
		})
	})

	return r
}
