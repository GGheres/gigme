package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type LoginWidgetPayload struct {
	ID               int64
	FirstName        string
	LastName         string
	Username         string
	PhotoURL         string
	AuthDate         int64
	Hash             string
	AdditionalFields map[string]string
}

func ValidateLoginWidgetPayload(payload LoginWidgetPayload, botToken string, maxAge time.Duration) (TelegramUser, error) {
	if payload.ID <= 0 {
		return TelegramUser{}, errors.New("invalid user id")
	}
	if payload.AuthDate <= 0 {
		return TelegramUser{}, errors.New("invalid auth_date")
	}
	if payload.Hash == "" {
		return TelegramUser{}, errors.New("missing hash")
	}

	values := url.Values{}
	values.Set("id", strconv.FormatInt(payload.ID, 10))
	values.Set("auth_date", strconv.FormatInt(payload.AuthDate, 10))
	if payload.FirstName != "" {
		values.Set("first_name", payload.FirstName)
	}
	if payload.LastName != "" {
		values.Set("last_name", payload.LastName)
	}
	if payload.Username != "" {
		values.Set("username", payload.Username)
	}
	if payload.PhotoURL != "" {
		values.Set("photo_url", payload.PhotoURL)
	}
	for rawKey, rawValue := range payload.AdditionalFields {
		key := strings.TrimSpace(rawKey)
		if key == "" {
			continue
		}
		switch strings.ToLower(key) {
		case "id", "first_name", "last_name", "username", "photo_url", "auth_date", "hash":
			continue
		}
		values.Set(key, rawValue)
	}

	dataCheckString := buildDataCheckString(values)
	secret := sha256.Sum256([]byte(botToken))
	calcHash := computeHMAC(secret[:], dataCheckString)
	hashBytes, err := hex.DecodeString(payload.Hash)
	if err != nil {
		return TelegramUser{}, errors.New("invalid hash encoding")
	}
	calcBytes, err := hex.DecodeString(calcHash)
	if err != nil {
		return TelegramUser{}, errors.New("invalid hash encoding")
	}
	if !hmac.Equal(calcBytes, hashBytes) {
		return TelegramUser{}, errors.New("invalid hash")
	}

	if maxAge > 0 {
		authTime := time.Unix(payload.AuthDate, 0)
		if time.Since(authTime) > maxAge {
			return TelegramUser{}, errors.New("auth_date expired")
		}
	}

	return TelegramUser{
		ID:        payload.ID,
		Username:  payload.Username,
		FirstName: payload.FirstName,
		LastName:  payload.LastName,
		PhotoURL:  payload.PhotoURL,
	}, nil
}

func BuildWebAppInitData(user TelegramUser, botToken string, authDate time.Time) (string, error) {
	if user.ID <= 0 {
		return "", errors.New("invalid user")
	}
	if authDate.IsZero() {
		authDate = time.Now().UTC()
	}

	rawUser, err := json.Marshal(user)
	if err != nil {
		return "", err
	}

	values := url.Values{}
	values.Set("auth_date", strconv.FormatInt(authDate.Unix(), 10))
	values.Set("user", string(rawUser))

	secretKey := buildSecretKey(botToken)
	dataCheckString := buildDataCheckString(values)
	values.Set("hash", computeHMAC(secretKey, dataCheckString))
	return values.Encode(), nil
}
