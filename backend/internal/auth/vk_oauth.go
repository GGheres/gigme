package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var ErrInvalidVKOAuthState = errors.New("invalid vk oauth state")

const vkOAuthStateTTL = 10 * time.Minute

type VKOAuthState struct {
	CodeVerifier string
	RedirectURI  string
	Next         string
	ExpiresAt    time.Time
}

type vkOAuthStatePayload struct {
	CodeVerifier string `json:"v"`
	RedirectURI  string `json:"r"`
	Next         string `json:"n,omitempty"`
	ExpiresAt    int64  `json:"e"`
}

func GeneratePKCECodeVerifier(length int) (string, error) {
	if length < 43 || length > 128 {
		return "", fmt.Errorf("invalid PKCE verifier length: %d", length)
	}

	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	raw := make([]byte, length)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}

	out := make([]byte, length)
	for i, b := range raw {
		out[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(out), nil
}

func BuildPKCECodeChallenge(codeVerifier string) string {
	sum := sha256.Sum256([]byte(codeVerifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func BuildVKOAuthState(
	secret string,
	codeVerifier string,
	redirectURI string,
	next string,
	now time.Time,
) (string, error) {
	if strings.TrimSpace(secret) == "" {
		return "", errors.New("vk oauth secret is empty")
	}
	if strings.TrimSpace(codeVerifier) == "" || strings.TrimSpace(redirectURI) == "" {
		return "", ErrInvalidVKOAuthState
	}

	payload := vkOAuthStatePayload{
		CodeVerifier: strings.TrimSpace(codeVerifier),
		RedirectURI:  strings.TrimSpace(redirectURI),
		Next:         strings.TrimSpace(next),
		ExpiresAt:    now.UTC().Add(vkOAuthStateTTL).Unix(),
	}
	rawPayload, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	encodedPayload := base64.RawURLEncoding.EncodeToString(rawPayload)
	signature := signVKOAuthState(secret, encodedPayload)
	return encodedPayload + "." + signature, nil
}

func ParseVKOAuthState(
	state string,
	secret string,
	now time.Time,
) (VKOAuthState, error) {
	if strings.TrimSpace(secret) == "" {
		return VKOAuthState{}, errors.New("vk oauth secret is empty")
	}

	parts := strings.Split(strings.TrimSpace(state), ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	expected := signVKOAuthState(secret, parts[0])
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	var payload vkOAuthStatePayload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	if payload.CodeVerifier == "" || payload.RedirectURI == "" || payload.ExpiresAt <= 0 {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	expiresAt := time.Unix(payload.ExpiresAt, 0).UTC()
	if !expiresAt.After(now.UTC()) {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	return VKOAuthState{
		CodeVerifier: payload.CodeVerifier,
		RedirectURI:  payload.RedirectURI,
		Next:         payload.Next,
		ExpiresAt:    expiresAt,
	}, nil
}

func signVKOAuthState(secret string, encodedPayload string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(encodedPayload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
