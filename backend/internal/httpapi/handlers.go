package httpapi

import (
	"net/http"
	"time"

	"github.com/SidGrip/php-mpos/backend/internal/auth"
)

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
		"uptime": time.Since(s.started).String(),
	})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":             "ok",
		"databaseConfigured": s.db != nil,
	})
}

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, auth.AnonymousSession())
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, auth.AnonymousSession())
}

func (s *Server) pools(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"slots": s.cfg.Slots,
	})
}

func planned(message string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusNotImplemented, map[string]any{
			"status":  "planned",
			"message": message,
		})
	}
}
