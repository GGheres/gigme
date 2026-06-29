package handlers

import (
	"bytes"
	"database/sql"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
)

// UploadMedia handles upload media.
func (h *Handler) UploadMedia(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if h.s3 == nil {
		logger.Error("action", "action", "upload_media", "status", "s3_not_configured")
		writeError(w, http.StatusInternalServerError, "media not configured")
		return
	}

	// Multipart framing needs a small allowance in addition to the actual file.
	r.Body = http.MaxBytesReader(w, r.Body, maxMediaBytes+(1<<20))
	if err := r.ParseMultipartForm(maxMediaBytes + (1 << 20)); err != nil {
		logger.Warn("action", "action", "upload_media", "status", "invalid_multipart")
		writeError(w, http.StatusBadRequest, "invalid multipart data")
		return
	}
	if r.MultipartForm != nil {
		defer r.MultipartForm.RemoveAll()
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		logger.Warn("action", "action", "upload_media", "status", "file_required")
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()
	if header.Size <= 0 || header.Size > maxMediaBytes {
		logger.Warn("action", "action", "upload_media", "status", "file_too_large", "size_bytes", header.Size)
		writeError(w, http.StatusBadRequest, "file must be between 1 byte and 5 MB")
		return
	}

	buffer := make([]byte, 512)
	n, _ := io.ReadFull(file, buffer)
	buffer = buffer[:n]
	contentType, ok := detectAllowedImageContentType(buffer)
	if !ok {
		logger.Warn("action", "action", "upload_media", "status", "invalid_content_type", "declared_content_type", header.Header.Get("Content-Type"))
		writeError(w, http.StatusBadRequest, "invalid content type")
		return
	}

	var body io.Reader = file
	if len(buffer) > 0 {
		body = io.MultiReader(bytes.NewReader(buffer), file)
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	fileURL, err := h.s3.UploadObject(ctx, header.Filename, contentType, body, header.Size)
	if err != nil {
		logger.Error("action", "action", "upload_media", "status", "upload_failed", "error", err)
		writeError(w, http.StatusInternalServerError, "upload failed")
		return
	}

	logger.Info("action", "action", "upload_media", "status", "success", "file_name", header.Filename, "content_type", contentType, "size_bytes", header.Size)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"fileUrl": fileURL,
	})
}

// EventMedia handles event media.
func (h *Handler) EventMedia(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	idStr := chi.URLParam(r, "id")
	indexStr := chi.URLParam(r, "index")
	eventID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || eventID <= 0 {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	index, err := strconv.Atoi(indexStr)
	if err != nil || index < 0 {
		writeError(w, http.StatusBadRequest, "invalid index")
		return
	}
	accessKey := accessKeyFromRequest(r)

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	event, err := h.repo.GetEventByID(ctx, eventID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		logger.Error("action", "action", "event_media", "status", "db_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	if event.IsHidden {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	if event.IsPrivate && accessKey != event.AccessKey {
		writeError(w, http.StatusNotFound, "not found")
		return
	}

	media, err := h.repo.ListEventMedia(ctx, eventID)
	if err != nil {
		logger.Error("action", "action", "event_media", "status", "media_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "media error")
		return
	}
	if index >= len(media) {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	url := strings.TrimSpace(media[index])
	if url == "" || !(strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://")) {
		writeError(w, http.StatusNotFound, "not found")
		return
	}

	if h.s3 != nil {
		if key, ok := h.s3.KeyFromURL(url); ok {
			obj, err := h.s3.GetObject(ctx, key)
			if err == nil {
				defer obj.Body.Close()
				payload, readErr := readBoundedMedia(obj.Body)
				if readErr != nil {
					logger.Warn("action", "action", "event_media", "status", "invalid_s3_payload", "event_id", eventID, "error", readErr)
					writeError(w, http.StatusBadGateway, "invalid media payload")
					return
				}
				contentType, validImage := detectAllowedImageContentType(payload)
				if !validImage {
					writeError(w, http.StatusBadGateway, "invalid media type")
					return
				}
				if obj.CacheControl != nil {
					w.Header().Set("Cache-Control", *obj.CacheControl)
				} else {
					w.Header().Set("Cache-Control", "public, max-age=3600")
				}
				if obj.ETag != nil {
					w.Header().Set("ETag", *obj.ETag)
				}
				if obj.LastModified != nil {
					w.Header().Set("Last-Modified", obj.LastModified.UTC().Format(http.TimeFormat))
				}
				writeMediaPayload(w, contentType, payload)
				return
			}
			logger.Warn("action", "action", "event_media", "status", "s3_get_failed", "event_id", eventID, "error", err)
		}
	}

	parsedURL, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid url")
		return
	}
	if err := validateRemoteMediaURL(parsedURL.URL); err != nil {
		writeError(w, http.StatusBadRequest, "invalid media url")
		return
	}
	resp, err := safeMediaHTTPClient.Do(parsedURL)
	if err != nil {
		logger.Error("action", "action", "event_media", "status", "fetch_failed", "event_id", eventID, "error", err)
		writeError(w, http.StatusBadGateway, "fetch failed")
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		logger.Warn("action", "action", "event_media", "status", "upstream_status", "event_id", eventID, "code", resp.StatusCode)
		writeError(w, http.StatusBadGateway, "upstream error")
		return
	}

	payload, err := readBoundedMedia(resp.Body)
	if err != nil {
		logger.Warn("action", "action", "event_media", "status", "invalid_upstream_payload", "event_id", eventID, "error", err)
		writeError(w, http.StatusBadGateway, "invalid media payload")
		return
	}
	contentType, validImage := detectAllowedImageContentType(payload)
	if !validImage {
		writeError(w, http.StatusBadGateway, "invalid media type")
		return
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "" {
		w.Header().Set("Cache-Control", cc)
	} else {
		w.Header().Set("Cache-Control", "public, max-age=3600")
	}
	if etag := resp.Header.Get("ETag"); etag != "" {
		w.Header().Set("ETag", etag)
	}
	if lm := resp.Header.Get("Last-Modified"); lm != "" {
		w.Header().Set("Last-Modified", lm)
	}
	writeMediaPayload(w, contentType, payload)
}

// readBoundedMedia reads at most the supported image size and returns an error
// instead of forwarding a truncated or unbounded upstream response.
func readBoundedMedia(reader io.Reader) ([]byte, error) {
	payload, err := io.ReadAll(io.LimitReader(reader, maxMediaBytes+1))
	if err != nil {
		return nil, err
	}
	if len(payload) == 0 || int64(len(payload)) > maxMediaBytes {
		return nil, errors.New("media payload size is invalid")
	}
	return payload, nil
}

// detectAllowedImageContentType validates image bytes instead of trusting a
// client or upstream Content-Type header, which can be trivially spoofed.
func detectAllowedImageContentType(payload []byte) (string, bool) {
	contentType := strings.ToLower(strings.TrimSpace(
		strings.Split(http.DetectContentType(payload), ";")[0],
	))
	if len(payload) >= 12 &&
		bytes.Equal(payload[0:4], []byte("RIFF")) &&
		bytes.Equal(payload[8:12], []byte("WEBP")) {
		contentType = "image/webp"
	}
	switch contentType {
	case "image/jpeg", "image/png", "image/webp":
		return contentType, true
	default:
		return "", false
	}
}

// writeMediaPayload writes a validated image with nosniff and an exact content
// length so browsers cannot reinterpret attacker-controlled bytes as markup.
func writeMediaPayload(w http.ResponseWriter, contentType string, payload []byte) {
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(payload)
}
