package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"gigme/backend/internal/integrations"
)

type telegramUpdate struct {
	Message *telegramMessage `json:"message"`
}

type telegramMessage struct {
	MessageID int          `json:"message_id"`
	Text      string       `json:"text"`
	Chat      telegramChat `json:"chat"`
}

type telegramChat struct {
	ID int64 `json:"id"`
}

func (h *Handler) TelegramWebhook(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var update telegramUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if update.Message == nil || update.Message.Chat.ID == 0 {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	text := strings.TrimSpace(update.Message.Text)
	fields := strings.Fields(text)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "/start") {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	webAppURL := strings.TrimSpace(h.cfg.BaseURL)
	if webAppURL == "" {
		logger.Warn("action", "action", "telegram_webhook", "status", "missing_base_url")
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	markup := &integrations.ReplyMarkup{
		InlineKeyboard: [][]integrations.InlineKeyboardButton{{
			{
				Text:   "Открыть Gigme",
				WebApp: &integrations.WebAppInfo{URL: webAppURL},
			},
		}},
	}

	if err := h.telegram.SendMessageWithMarkup(update.Message.Chat.ID, "Нажмите кнопку, чтобы открыть приложение", markup); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "send_failed", "error", err)

	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
