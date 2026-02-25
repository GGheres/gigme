package integrations

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// TelegramClient represents telegram client.
type TelegramClient struct {
	token  string
	client *http.Client
}

// WebAppInfo represents web app info.
type WebAppInfo struct {
	URL string `json:"url"`
}

// InlineKeyboardButton represents inline keyboard button.
type InlineKeyboardButton struct {
	Text         string          `json:"text"`
	URL          string          `json:"url,omitempty"`
	WebApp       *WebAppInfo     `json:"web_app,omitempty"`
	CallbackData string          `json:"callback_data,omitempty"`
	CopyText     *CopyTextButton `json:"copy_text,omitempty"`
}

// CopyTextButton represents copy text button.
type CopyTextButton struct {
	Text string `json:"text"`
}

// ReplyMarkup represents reply markup.
type ReplyMarkup struct {
	InlineKeyboard [][]InlineKeyboardButton `json:"inline_keyboard"`
}

// NewTelegramClient creates telegram client.
func NewTelegramClient(token string) *TelegramClient {
	return &TelegramClient{
		token:  token,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

// SendMessage handles send message.
func (t *TelegramClient) SendMessage(chatID int64, text string) error {
	return t.SendMessageWithMarkup(chatID, text, nil)
}

// SendMessageWithMarkup handles send message with markup.
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

// SendPhotoWithMarkup handles send photo with markup.
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

// SendPhotoBytes handles send photo bytes.
func (t *TelegramClient) SendPhotoBytes(chatID int64, filename string, photo []byte, caption string, markup *ReplyMarkup) error {
	if len(photo) == 0 {
		return fmt.Errorf("photo is empty")
	}
	if filename == "" {
		filename = "ticket.png"
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if err := writer.WriteField("chat_id", strconv.FormatInt(chatID, 10)); err != nil {
		return err
	}
	if caption != "" {
		if err := writer.WriteField("caption", caption); err != nil {
			return err
		}
	}
	if markup != nil {
		markupJSON, err := json.Marshal(markup)
		if err != nil {
			return err
		}
		if err := writer.WriteField("reply_markup", string(markupJSON)); err != nil {
			return err
		}
	}
	fileWriter, err := writer.CreateFormFile("photo", filename)
	if err != nil {
		return err
	}
	if _, err := fileWriter.Write(photo); err != nil {
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendPhoto", t.token)
	req, err := http.NewRequest(http.MethodPost, url, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := t.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("telegram sendPhoto status %d", resp.StatusCode)
	}
	return nil
}

// AnswerCallbackQuery handles answer callback query.
func (t *TelegramClient) AnswerCallbackQuery(callbackQueryID string, text string) error {
	callbackQueryID = strings.TrimSpace(callbackQueryID)
	if callbackQueryID == "" {
		return nil
	}

	payload := map[string]interface{}{
		"callback_query_id": callbackQueryID,
	}
	if strings.TrimSpace(text) != "" {
		payload["text"] = strings.TrimSpace(text)
	}
	return t.post("answerCallbackQuery", payload)
}

// post handles internal post behavior.
func (t *TelegramClient) post(method string, payload map[string]interface{}) error {
	body, _ := json.Marshal(payload)
	url := fmt.Sprintf("https://api.telegram.org/bot%s/%s", t.token, method)
	resp, err := t.client.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("telegram %s status %d", method, resp.StatusCode)
	}
	return nil
}
