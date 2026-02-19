package auth

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
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

	trimmedState := strings.TrimSpace(state)
	if trimmedState == "" {
		return VKOAuthState{}, ErrInvalidVKOAuthState
	}

	if parsed, ok := parseVKOAuthStateCurrent(trimmedState, secret, now); ok {
		return parsed, nil
	}

	if parsed, ok := parseVKOAuthStateLegacy(trimmedState, secret, now); ok {
		return parsed, nil
	}

	unescaped, err := url.QueryUnescape(trimmedState)
	if err == nil {
		unescaped = strings.TrimSpace(unescaped)
		if unescaped != "" && unescaped != trimmedState {
			if parsed, ok := parseVKOAuthStateCurrent(unescaped, secret, now); ok {
				return parsed, nil
			}
			if parsed, ok := parseVKOAuthStateLegacy(unescaped, secret, now); ok {
				return parsed, nil
			}
		}
	}

	return VKOAuthState{}, ErrInvalidVKOAuthState
}

func parseVKOAuthStateCurrent(
	state string,
	secret string,
	now time.Time,
) (VKOAuthState, bool) {
	parts := strings.Split(strings.TrimSpace(state), ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return VKOAuthState{}, false
	}

	expected := signVKOAuthState(secret, parts[0])
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return VKOAuthState{}, false
	}

	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return VKOAuthState{}, false
	}

	parsed, ok := parseVKOAuthPayload(payloadBytes, now)
	if !ok {
		return VKOAuthState{}, false
	}
	return parsed, true
}

func parseVKOAuthStateLegacy(
	state string,
	secret string,
	now time.Time,
) (VKOAuthState, bool) {
	decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(state))
	if err != nil || len(decoded) == 0 {
		return VKOAuthState{}, false
	}

	if parsed, ok := parseVKOAuthStateCurrent(string(decoded), secret, now); ok {
		return parsed, true
	}

	// Legacy format: base64url(payload_json + "." + raw_hmac_sha256(payload_json)).
	payloadEnd := bytes.LastIndexByte(decoded, '}')
	if payloadEnd <= 0 || payloadEnd+2 > len(decoded) || decoded[payloadEnd+1] != '.' {
		return VKOAuthState{}, false
	}

	payloadBytes := decoded[:payloadEnd+1]
	signatureRaw := decoded[payloadEnd+2:]
	if len(signatureRaw) == 0 {
		return VKOAuthState{}, false
	}

	expectedRaw := signVKOAuthStateRaw(secret, payloadBytes)
	if !hmac.Equal(expectedRaw, signatureRaw) {
		return VKOAuthState{}, false
	}

	parsed, ok := parseVKOAuthPayload(payloadBytes, now)
	if !ok {
		return VKOAuthState{}, false
	}
	return parsed, true
}

func parseVKOAuthPayload(payloadBytes []byte, now time.Time) (VKOAuthState, bool) {
	var payload vkOAuthStatePayload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		return VKOAuthState{}, false
	}

	codeVerifier := strings.TrimSpace(payload.CodeVerifier)
	redirectURI := strings.TrimSpace(payload.RedirectURI)
	next := strings.TrimSpace(payload.Next)
	if codeVerifier == "" || redirectURI == "" || payload.ExpiresAt <= 0 {
		return VKOAuthState{}, false
	}

	expiresAt := time.Unix(payload.ExpiresAt, 0).UTC()
	if !expiresAt.After(now.UTC()) {
		return VKOAuthState{}, false
	}

	return VKOAuthState{
		CodeVerifier: codeVerifier,
		RedirectURI:  redirectURI,
		Next:         next,
		ExpiresAt:    expiresAt,
	}, true
}

func signVKOAuthState(secret string, encodedPayload string) string {
	return base64.RawURLEncoding.EncodeToString(signVKOAuthStateRaw(secret, []byte(encodedPayload)))
}

func signVKOAuthStateRaw(secret string, payload []byte) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write(payload)
	return mac.Sum(nil)
}
