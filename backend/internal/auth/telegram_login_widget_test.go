package auth

import (
	"crypto/sha256"
	"net/url"
	"strconv"
	"testing"
	"time"
)

func TestValidateLoginWidgetPayload_Success(t *testing.T) {
	botToken := "123456:bot_token"
	now := time.Now().Unix()

	values := url.Values{}
	values.Set("id", "777")
	values.Set("first_name", "John")
	values.Set("last_name", "Doe")
	values.Set("username", "john_doe")
	values.Set("photo_url", "https://example.com/u.jpg")
	values.Set("allows_write_to_pm", "true")
	values.Set("auth_date", strconv.FormatInt(now, 10))
	dataCheckString := buildDataCheckString(values)
	secret := sha256.Sum256([]byte(botToken))

	user, err := ValidateLoginWidgetPayload(
		LoginWidgetPayload{
			ID:        777,
			FirstName: "John",
			LastName:  "Doe",
			Username:  "john_doe",
			PhotoURL:  "https://example.com/u.jpg",
			AuthDate:  now,
			Hash:      computeHMAC(secret[:], dataCheckString),
			AdditionalFields: map[string]string{
				"allows_write_to_pm": "true",
			},
		},
		botToken,
		time.Hour,
	)
	if err != nil {
		t.Fatalf("validate failed: %v", err)
	}
	if user.ID != 777 {
		t.Fatalf("unexpected user id: %d", user.ID)
	}
	if user.Username != "john_doe" {
		t.Fatalf("unexpected username: %s", user.Username)
	}
}

func TestBuildWebAppInitData_RoundTripValidate(t *testing.T) {
	botToken := "123456:bot_token"
	now := time.Now().UTC()
	input := TelegramUser{
		ID:        999,
		Username:  "tester",
		FirstName: "Test",
		LastName:  "User",
		PhotoURL:  "https://example.com/pic.png",
	}

	initData, err := BuildWebAppInitData(input, botToken, now)
	if err != nil {
		t.Fatalf("BuildWebAppInitData failed: %v", err)
	}

	got, _, err := ValidateInitData(initData, botToken, time.Hour)
	if err != nil {
		t.Fatalf("ValidateInitData failed: %v", err)
	}
	if got.ID != input.ID {
		t.Fatalf("id mismatch: got=%d want=%d", got.ID, input.ID)
	}
	if got.Username != input.Username {
		t.Fatalf("username mismatch: got=%s want=%s", got.Username, input.Username)
	}
}
