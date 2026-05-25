package auth

import (
	"net/http"
	"net/url"
	"strings"
)

func SameOriginGuard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isSafeMethod(r.Method) {
			next.ServeHTTP(w, r)
			return
		}

		if strings.EqualFold(r.Header.Get("Sec-Fetch-Site"), "cross-site") {
			http.Error(w, "cross-origin request rejected", http.StatusForbidden)
			return
		}

		if origin := r.Header.Get("Origin"); origin != "" && !sameHost(origin, r.Host) {
			http.Error(w, "origin rejected", http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func isSafeMethod(method string) bool {
	return method == http.MethodGet || method == http.MethodHead || method == http.MethodOptions
}

func sameHost(rawOrigin, host string) bool {
	origin, err := url.Parse(rawOrigin)
	if err != nil {
		return false
	}
	return strings.EqualFold(origin.Host, host)
}
