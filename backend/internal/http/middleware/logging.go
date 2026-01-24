package middleware

import (
	"log/slog"
	"net/http"
	"time"

	chimw "github.com/go-chi/chi/v5/middleware"
)

func RequestLogger(logger *slog.Logger) func(http.Handler) http.Handler {
	if logger == nil {
		logger = slog.Default()
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)

			next.ServeHTTP(ww, r)

			attrs := []any{
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"bytes", ww.BytesWritten(),
				"duration_ms", time.Since(start).Milliseconds(),
			}

			if r.URL.RawQuery != "" {
				attrs = append(attrs, "query", r.URL.RawQuery)
			}
			if reqID := chimw.GetReqID(r.Context()); reqID != "" {
				attrs = append(attrs, "request_id", reqID)
			}
			if userID, ok := UserIDFromContext(r.Context()); ok {
				attrs = append(attrs, "user_id", userID)
			}
			if tgID, ok := TelegramIDFromContext(r.Context()); ok {
				attrs = append(attrs, "telegram_id", tgID)
			}
			if ip := r.RemoteAddr; ip != "" {
				attrs = append(attrs, "ip", ip)
			}
			if ua := r.UserAgent(); ua != "" {
				attrs = append(attrs, "user_agent", ua)
			}

			switch {
			case ww.Status() >= 500:
				logger.Error("http_request", attrs...)
			case ww.Status() >= 400:
				logger.Warn("http_request", attrs...)
			default:
				logger.Info("http_request", attrs...)
			}
		})
	}
}
