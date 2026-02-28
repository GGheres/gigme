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

// VKOAuthState represents v k o auth state.
type VKOAuthState struct {
	CodeVerifier string
	RedirectURI  string
	Next         string
	ExpiresAt    time.Time
}

// vkOAuthStatePayload represents vk o auth state payload.
type vkOAuthStatePayload struct {
	CodeVerifier string `json:"v"`
	RedirectURI  string `json:"r"`
	Next         string `json:"n,omitempty"`
	ExpiresAt    int64  `json:"e"`
}

// GeneratePKCECodeVerifier handles generate p k c e code verifier.
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

// BuildPKCECodeChallenge builds p k c e code challenge.
func BuildPKCECodeChallenge(codeVerifier string) string {
	sum := sha256.Sum256([]byte(codeVerifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// BuildVKOAuthState builds v k o auth state.
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

// ParseVKOAuthState parses v k o auth state.
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

	for _, candidate := range collectVKOAuthStateCandidates(trimmedState) {
		if parsed, ok := parseVKOAuthStateCandidate(candidate, secret, now); ok {
			return parsed, nil
		}
	}

	return VKOAuthState{}, ErrInvalidVKOAuthState
}

// parseVKOAuthStateCandidate parses v k o auth state candidate.
func parseVKOAuthStateCandidate(state string, secret string, now time.Time) (VKOAuthState, bool) {
	if parsed, ok := parseVKOAuthStateCurrent(state, secret, now); ok {
		return parsed, true
	}
	if parsed, ok := parseVKOAuthStateLegacy(state, secret, now); ok {
		return parsed, true
	}
	return VKOAuthState{}, false
}

// collectVKOAuthStateCandidates handles collect v k o auth state candidates.
func collectVKOAuthStateCandidates(state string) []string {
	queue := []string{strings.TrimSpace(state)}
	seen := make(map[string]struct{}, 8)
	out := make([]string, 0, 8)

	for len(queue) > 0 {
		candidate := strings.TrimSpace(queue[0])
		queue = queue[1:]
		if candidate == "" {
			continue
		}
		if _, ok := seen[candidate]; ok {
			continue
		}
		seen[candidate] = struct{}{}
		out = append(out, candidate)

		unquoted := trimWrappingQuotes(candidate)
		if unquoted != "" && unquoted != candidate {
			queue = append(queue, unquoted)
		}

		if unescaped, err := url.QueryUnescape(candidate); err == nil {
			unescaped = strings.TrimSpace(unescaped)
			if unescaped != "" && unescaped != candidate {
				queue = append(queue, unescaped)
			}
		}

		if unescaped, err := url.PathUnescape(candidate); err == nil {
			unescaped = strings.TrimSpace(unescaped)
			if unescaped != "" && unescaped != candidate {
				queue = append(queue, unescaped)
			}
		}

		if strings.Contains(candidate, " ") {
			withPlus := strings.ReplaceAll(candidate, " ", "+")
			if withPlus != candidate {
				queue = append(queue, withPlus)
			}
		}
	}

	return out
}

// trimWrappingQuotes trims wrapping quotes from value.
func trimWrappingQuotes(value string) string {
	trimmed := strings.TrimSpace(value)
	for len(trimmed) >= 2 {
		first := trimmed[0]
		last := trimmed[len(trimmed)-1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			trimmed = strings.TrimSpace(trimmed[1 : len(trimmed)-1])
			continue
		}
		break
	}
	return trimmed
}

// parseVKOAuthStateCurrent parses v k o auth state current.
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

// parseVKOAuthStateLegacy parses v k o auth state legacy.
func parseVKOAuthStateLegacy(
	state string,
	secret string,
	now time.Time,
) (VKOAuthState, bool) {
	decoded, ok := decodeVKOAuthStateBase64(state)
	if !ok || len(decoded) == 0 {
		return VKOAuthState{}, false
	}

	if parsed, ok := parseVKOAuthStateCurrent(string(decoded), secret, now); ok {
		return parsed, true
	}

	// Legacy format: base64url(payload_json + "." + raw_hmac_sha256(payload_json)).
	// In practice VK may repack state as base64url(payload_json + raw_signature)
	// without explicit separator. Keep compatibility with optional "." separator.
	// Do not search for '}' by byte value because raw signature is arbitrary binary.
	decoder := json.NewDecoder(bytes.NewReader(decoded))
	var rawPayloadMessage json.RawMessage
	if err := decoder.Decode(&rawPayloadMessage); err != nil {
		return VKOAuthState{}, false
	}

	payloadEnd := int(decoder.InputOffset())
	if payloadEnd <= 0 || payloadEnd >= len(decoded) {
		return VKOAuthState{}, false
	}

	payloadBytes := decoded[:payloadEnd]
	signatures := [][]byte{decoded[payloadEnd:]}
	if decoded[payloadEnd] == '.' && payloadEnd+1 < len(decoded) {
		signatures = append(signatures, decoded[payloadEnd+1:])
	}

	verified := false
	for _, signatureRaw := range signatures {
		if len(signatureRaw) == 0 {
			continue
		}

		expectedRaw := signVKOAuthStateRaw(secret, payloadBytes)
		if hmac.Equal(expectedRaw, signatureRaw) {
			verified = true
			break
		}

		// VK code_v2 may return repacked signature over base64url(payload_json).
		encodedPayload := base64.RawURLEncoding.EncodeToString(payloadBytes)
		repackedExpectedRaw := signVKOAuthStateRaw(secret, []byte(encodedPayload))
		if hmac.Equal(repackedExpectedRaw, signatureRaw) {
			verified = true
			break
		}
	}
	if !verified {
		return VKOAuthState{}, false
	}

	parsed, ok := parseVKOAuthPayload(payloadBytes, now)
	if !ok {
		return VKOAuthState{}, false
	}
	return parsed, true
}

// decodeVKOAuthStateBase64 decodes vk oauth state base64.
func decodeVKOAuthStateBase64(state string) ([]byte, bool) {
	trimmedState := strings.TrimSpace(state)
	if trimmedState == "" {
		return nil, false
	}

	encodings := []*base64.Encoding{
		base64.RawURLEncoding,
		base64.URLEncoding,
		base64.RawStdEncoding,
		base64.StdEncoding,
	}
	for _, encoding := range encodings {
		decoded, err := encoding.DecodeString(trimmedState)
		if err == nil && len(decoded) > 0 {
			return decoded, true
		}
	}
	return nil, false
}

// parseVKOAuthPayload parses v k o auth payload.
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

// signVKOAuthState signs v k o auth state.
func signVKOAuthState(secret string, encodedPayload string) string {
	return base64.RawURLEncoding.EncodeToString(signVKOAuthStateRaw(secret, []byte(encodedPayload)))
}

// signVKOAuthStateRaw signs v k o auth state raw.
func signVKOAuthStateRaw(secret string, payload []byte) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write(payload)
	return mac.Sum(nil)
}
