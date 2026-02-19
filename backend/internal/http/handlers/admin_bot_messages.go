package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"gigme/backend/internal/models"
)

const maxAdminBotReplyRunes = 4096

type adminBotMessagesResponse struct {
	Items []models.AdminBotMessage `json:"items"`
	Total int                      `json:"total"`
}

type adminBotReplyRequest struct {
	ChatID int64  `json:"chatId"`
	Text   string `json:"text"`
}

func (h *Handler) ListAdminBotMessages(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_bot_messages"); !ok {
		return
	}

	limit := parseIntQuery(r, "limit", 100)
	offset := parseIntQuery(r, "offset", 0)
	chatID, err := parseChatIDQuery(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid chat_id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	items, total, err := h.repo.ListAdminBotMessages(ctx, chatID, limit, offset)
	if err != nil {
		logger.Error("action", "action", "admin_list_bot_messages", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, adminBotMessagesResponse{Items: items, Total: total})
}

func (h *Handler) ReplyAdminBotMessage(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	adminTelegramID, ok := h.requireAdmin(logger, w, r, "admin_reply_bot_message")
	if !ok {
		return
	}
	if h.telegram == nil {
		writeError(w, http.StatusServiceUnavailable, "telegram is unavailable")
		return
	}

	var req adminBotReplyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	text := strings.TrimSpace(req.Text)
	if req.ChatID <= 0 {
		writeError(w, http.StatusBadRequest, "chatId is required")
		return
	}
	if text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}
	if utf8.RuneCountInString(text) > maxAdminBotReplyRunes {
		writeError(w, http.StatusBadRequest, "text is too long")
		return
	}

	if err := h.telegram.SendMessage(req.ChatID, text); err != nil {
		logger.Warn(
			"action", "action", "admin_reply_bot_message",
			"status", "telegram_send_failed",
			"chat_id", req.ChatID,
			"admin_telegram_id", adminTelegramID,
			"error", err,
		)
		writeError(w, http.StatusBadGateway, "telegram send failed")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.StoreAdminBotOutgoingMessage(ctx, req.ChatID, adminTelegramID, text); err != nil {
		logger.Warn(
			"action", "action", "admin_reply_bot_message",
			"status", "db_insert_failed",
			"chat_id", req.ChatID,
			"admin_telegram_id", adminTelegramID,
			"error", err,
		)
	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func parseChatIDQuery(r *http.Request) (*int64, error) {
	raw := strings.TrimSpace(r.URL.Query().Get("chat_id"))
	if raw == "" {
		raw = strings.TrimSpace(r.URL.Query().Get("chatId"))
	}
	if raw == "" {
		return nil, nil
	}
	parsed, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || parsed <= 0 {
		return nil, strconv.ErrSyntax
	}
	return &parsed, nil
}
