package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

type TelegramUser struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	PhotoURL  string `json:"photo_url"`
}

func ValidateInitData(initData string, botToken string, maxAge time.Duration) (TelegramUser, map[string]string, error) {
	parsed, err := url.ParseQuery(initData)
	if err != nil {
		return TelegramUser{}, nil, fmt.Errorf("parse initData: %w", err)
	}

	hash := parsed.Get("hash")
	if hash == "" {
		return TelegramUser{}, nil, errors.New("missing hash")
	}
	parsed.Del("hash")

	dataCheckString := buildDataCheckString(parsed)
	secretKey := buildSecretKey(botToken)
	calcHash := computeHMAC(secretKey, dataCheckString)
	hashBytes, err := hex.DecodeString(hash)
	if err != nil {
		return TelegramUser{}, nil, errors.New("invalid hash encoding")
	}
	calcBytes, err := hex.DecodeString(calcHash)
	if err != nil {
		return TelegramUser{}, nil, errors.New("invalid hash encoding")
	}
	if !hmac.Equal(calcBytes, hashBytes) {
		return TelegramUser{}, nil, errors.New("invalid hash")
	}

	if maxAge > 0 {
		if authDateStr := parsed.Get("auth_date"); authDateStr != "" {
			sec, err := strconv.ParseInt(authDateStr, 10, 64)
			if err == nil {
				authTime := time.Unix(sec, 0)
				if time.Since(authTime) > maxAge {
					return TelegramUser{}, nil, errors.New("auth_date expired")
				}
			}
		}
	}

	user, err := parseUser(parsed.Get("user"))
	if err != nil {
		return TelegramUser{}, nil, fmt.Errorf("parse user: %w", err)
	}

	flat := make(map[string]string)
	for key, values := range parsed {
		if len(values) > 0 {
			flat[key] = values[0]
		}
	}
	return user, flat, nil
}

func buildDataCheckString(values url.Values) string {
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, key+"="+values.Get(key))
	}
	return strings.Join(parts, "\n")
}

func buildSecretKey(botToken string) []byte {
	h := hmac.New(sha256.New, []byte("WebAppData"))
	h.Write([]byte(botToken))
	return h.Sum(nil)
}

func computeHMAC(secret []byte, data string) string {
	h := hmac.New(sha256.New, secret)
	h.Write([]byte(data))
	return hex.EncodeToString(h.Sum(nil))
}

func parseUser(raw string) (TelegramUser, error) {
	if raw == "" {
		return TelegramUser{}, errors.New("missing user")
	}
	var user TelegramUser
	if err := json.Unmarshal([]byte(raw), &user); err != nil {
		return TelegramUser{}, err
	}
	if user.ID == 0 {
		return TelegramUser{}, errors.New("invalid user")
	}
	return user, nil
}
