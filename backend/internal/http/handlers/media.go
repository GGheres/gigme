package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
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
