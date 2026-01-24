package integrations

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type TelegramClient struct {
	token  string
	client *http.Client
}

type WebAppInfo struct {
	URL string `json:"url"`
}

type InlineKeyboardButton struct {
	Text   string      `json:"text"`
	URL    string      `json:"url,omitempty"`
	WebApp *WebAppInfo `json:"web_app,omitempty"`
}

type ReplyMarkup struct {
	InlineKeyboard [][]InlineKeyboardButton `json:"inline_keyboard"`
}

func NewTelegramClient(token string) *TelegramClient {
	return &TelegramClient{
		token:  token,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

func (t *TelegramClient) SendMessage(chatID int64, text string) error {
	return t.SendMessageWithMarkup(chatID, text, nil)
}

func (t *TelegramClient) SendMessageWithMarkup(chatID int64, text string, markup *ReplyMarkup) error {
	payload := map[string]interface{}{
		"chat_id": chatID,
		"text":    text,
	}
	if markup != nil {
		payload["reply_markup"] = markup
	}
	return t.post("sendMessage", payload)
}

func (t *TelegramClient) SendPhotoWithMarkup(chatID int64, photoURL, caption string, markup *ReplyMarkup) error {
	payload := map[string]interface{}{
		"chat_id": chatID,
		"photo":   photoURL,
	}
	if caption != "" {
		payload["caption"] = caption
	}
	if markup != nil {
		payload["reply_markup"] = markup
	}
	return t.post("sendPhoto", payload)
}

func (t *TelegramClient) post(method string, payload map[string]interface{}) error {
	body, _ := json.Marshal(payload)
	url := fmt.Sprintf("https://api.telegram.org/bot%s/%s", t.token, method)
	resp, err := t.client.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("telegram %s status %d", method, resp.StatusCode)
	}
	return nil
}
