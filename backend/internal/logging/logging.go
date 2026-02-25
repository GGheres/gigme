package logging

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"gigme/backend/internal/config"
)

// Cleanup represents cleanup.
type Cleanup func() error

// New creates the requested data.
func New(cfg config.LoggingConfig) (*slog.Logger, Cleanup, error) {
	level := parseLevel(cfg.Level)
	handlerOptions := &slog.HandlerOptions{
		Level:     level,
		AddSource: true,
	}

	writers := []io.Writer{os.Stdout}
	var file *os.File
	if cfg.File != "" {
		dir := filepath.Dir(cfg.File)
		if dir != "." {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return nil, nil, err
			}
		}
		f, err := os.OpenFile(cfg.File, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return nil, nil, err
		}
		file = f
		writers = append(writers, file)
	}

	multi := io.MultiWriter(writers...)
	var handler slog.Handler
	switch strings.ToLower(cfg.Format) {
	case "json":
		handler = slog.NewJSONHandler(multi, handlerOptions)
	default:
		handler = slog.NewTextHandler(multi, handlerOptions)
	}

	logger := slog.New(handler)
	cleanup := func() error {
		if file != nil {
			return file.Close()
		}
		return nil
	}
	return logger, cleanup, nil
}

// parseLevel parses level.
func parseLevel(value string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
