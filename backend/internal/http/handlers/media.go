package handlers

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
)

type presignRequest struct {
	FileName    string `json:"fileName"`
	ContentType string `json:"contentType"`
	SizeBytes   int64  `json:"sizeBytes"`
}

func (h *Handler) PresignMedia(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req presignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "presign_media", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	if req.FileName == "" || req.ContentType == "" || req.SizeBytes == 0 {
		logger.Warn("action", "action", "presign_media", "status", "missing_fields")
		writeError(w, http.StatusBadRequest, "missing fields")
		return
	}
	if req.SizeBytes > 5*1024*1024 {
		logger.Warn("action", "action", "presign_media", "status", "file_too_large", "size_bytes", req.SizeBytes)
		writeError(w, http.StatusBadRequest, "file too large")
		return
	}

	allowed := map[string]struct{}{
		"image/jpeg": {},
		"image/png":  {},
		"image/webp": {},
		"image/heic": {},
		"image/heif": {},
	}
	if _, ok := allowed[strings.ToLower(req.ContentType)]; !ok {
		logger.Warn("action", "action", "presign_media", "status", "invalid_content_type", "content_type", req.ContentType)
		writeError(w, http.StatusBadRequest, "invalid content type")
		return
	}

	if h.s3 == nil {
		logger.Error("action", "action", "presign_media", "status", "s3_not_configured")
		writeError(w, http.StatusInternalServerError, "media not configured")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	uploadURL, fileURL, err := h.s3.PresignPutObject(ctx, req.FileName, req.ContentType)
	if err != nil {
		logger.Error("action", "action", "presign_media", "status", "presign_failed", "error", err)
		writeError(w, http.StatusInternalServerError, "presign failed")
		return
	}

	logger.Info("action", "action", "presign_media", "status", "success", "file_name", req.FileName, "content_type", req.ContentType, "size_bytes", req.SizeBytes)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"uploadUrl": uploadURL,
		"fileUrl":   fileURL,
	})
}

func (h *Handler) UploadMedia(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if h.s3 == nil {
		logger.Error("action", "action", "upload_media", "status", "s3_not_configured")
		writeError(w, http.StatusInternalServerError, "media not configured")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 5*1024*1024)
	if err := r.ParseMultipartForm(5 * 1024 * 1024); err != nil {
		logger.Warn("action", "action", "upload_media", "status", "invalid_multipart")
		writeError(w, http.StatusBadRequest, "invalid multipart data")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		logger.Warn("action", "action", "upload_media", "status", "file_required")
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	buffer := make([]byte, 512)
	n, _ := io.ReadFull(file, buffer)
	buffer = buffer[:n]
	if contentType == "" {
		contentType = http.DetectContentType(buffer)
	}

	allowed := map[string]struct{}{
		"image/jpeg": {},
		"image/png":  {},
		"image/webp": {},
		"image/heic": {},
		"image/heif": {},
	}
	if _, ok := allowed[strings.ToLower(contentType)]; !ok {
		logger.Warn("action", "action", "upload_media", "status", "invalid_content_type", "content_type", contentType)
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
				if obj.ContentType != nil {
					w.Header().Set("Content-Type", *obj.ContentType)
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
				w.WriteHeader(http.StatusOK)
				_, _ = io.Copy(w, obj.Body)
				return
			}
			logger.Warn("action", "action", "event_media", "status", "s3_get_failed", "event_id", eventID, "error", err)
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid url")
		return
	}
	resp, err := http.DefaultClient.Do(req)
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

	if ct := resp.Header.Get("Content-Type"); ct != "" {
		w.Header().Set("Content-Type", ct)
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
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, resp.Body)
}
