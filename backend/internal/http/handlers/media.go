package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
)

type presignRequest struct {
	FileName    string `json:"fileName"`
	ContentType string `json:"contentType"`
	SizeBytes   int64  `json:"sizeBytes"`
}

func (h *Handler) PresignMedia(w http.ResponseWriter, r *http.Request) {
	var req presignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	if req.FileName == "" || req.ContentType == "" || req.SizeBytes == 0 {
		writeError(w, http.StatusBadRequest, "missing fields")
		return
	}
	if req.SizeBytes > 5*1024*1024 {
		writeError(w, http.StatusBadRequest, "file too large")
		return
	}

	allowed := map[string]struct{}{
		"image/jpeg": {},
		"image/png":  {},
		"image/webp": {},
	}
	if _, ok := allowed[strings.ToLower(req.ContentType)]; !ok {
		writeError(w, http.StatusBadRequest, "invalid content type")
		return
	}

	if h.s3 == nil {
		writeError(w, http.StatusInternalServerError, "media not configured")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	uploadURL, fileURL, err := h.s3.PresignPutObject(ctx, req.FileName, req.ContentType)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "presign failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"uploadUrl": uploadURL,
		"fileUrl":   fileURL,
	})
}
