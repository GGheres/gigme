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

func NewTelegramClient(token string) *TelegramClient {
	return &TelegramClient{
		token: token,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

func (t *TelegramClient) SendMessage(chatID int64, text string) error {
	payload := map[string]interface{}{
		"chat_id": chatID,
		"text":    text,
	}
	body, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", t.token)
	resp, err := t.client.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("telegram sendMessage status %d", resp.StatusCode)
	}
	return nil
}
