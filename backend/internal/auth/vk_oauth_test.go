package auth

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"
)

// TestGeneratePKCECodeVerifier verifies generate p k c e code verifier behavior.
func TestGeneratePKCECodeVerifier(t *testing.T) {
	verifier, err := GeneratePKCECodeVerifier(64)
	if err != nil {
		t.Fatalf("GeneratePKCECodeVerifier() error = %v", err)
	}
	if len(verifier) != 64 {
		t.Fatalf("len(verifier) = %d, want 64", len(verifier))
	}

	const allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	for _, r := range verifier {
		if !strings.ContainsRune(allowed, r) {
			t.Fatalf("verifier contains unsupported rune %q", r)
		}
	}
}

// TestBuildAndParseVKOAuthState verifies build and parse v k o auth state behavior.
func TestBuildAndParseVKOAuthState(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	state, err := BuildVKOAuthState(
		"secret",
		"abc123-verifier",
		"https://spacefestival.fun/space_app/auth",
		"/space_app/event/7",
		now,
	)
	if err != nil {
		t.Fatalf("BuildVKOAuthState() error = %v", err)
	}

	parsed, err := ParseVKOAuthState(state, "secret", now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("ParseVKOAuthState() error = %v", err)
	}
	if parsed.CodeVerifier != "abc123-verifier" {
		t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
	}
	if parsed.RedirectURI != "https://spacefestival.fun/space_app/auth" {
		t.Fatalf("RedirectURI = %q", parsed.RedirectURI)
	}
	if parsed.Next != "/space_app/event/7" {
		t.Fatalf("Next = %q", parsed.Next)
	}
}

// TestParseVKOAuthStateRejectsTamperedData verifies parse v k o auth state rejects tampered data behavior.
func TestParseVKOAuthStateRejectsTamperedData(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	state, err := BuildVKOAuthState(
		"secret",
		"abc123-verifier",
		"https://spacefestival.fun/space_app/auth",
		"/space_app",
		now,
	)
	if err != nil {
		t.Fatalf("BuildVKOAuthState() error = %v", err)
	}

	tampered := state + "x"
	if _, err := ParseVKOAuthState(tampered, "secret", now); err == nil {
		t.Fatal("expected ParseVKOAuthState() error for tampered token")
	}
}

// TestParseVKOAuthStateRejectsExpiredState verifies parse v k o auth state rejects expired state behavior.
func TestParseVKOAuthStateRejectsExpiredState(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	state, err := BuildVKOAuthState(
		"secret",
		"abc123-verifier",
		"https://spacefestival.fun/space_app/auth",
		"/space_app",
		now,
	)
	if err != nil {
		t.Fatalf("BuildVKOAuthState() error = %v", err)
	}

	if _, err := ParseVKOAuthState(state, "secret", now.Add(11*time.Minute)); err == nil {
		t.Fatal("expected ParseVKOAuthState() error for expired token")
	}
}

// TestParseVKOAuthStateAcceptsDoubleEncodedState verifies parse v k o auth state accepts double encoded state behavior.
func TestParseVKOAuthStateAcceptsDoubleEncodedState(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	state, err := BuildVKOAuthState(
		"secret",
		"abc123-verifier",
		"https://spacefestival.fun/space_app/auth",
		"/space_app",
		now,
	)
	if err != nil {
		t.Fatalf("BuildVKOAuthState() error = %v", err)
	}

	doubleEncoded := base64.RawURLEncoding.EncodeToString([]byte(state))
	parsed, err := ParseVKOAuthState(doubleEncoded, "secret", now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("ParseVKOAuthState() error = %v", err)
	}
	if parsed.CodeVerifier != "abc123-verifier" {
		t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
	}
}

// TestParseVKOAuthStateAcceptsLegacyRawSignatureBlob verifies parse v k o auth state accepts legacy raw signature blob behavior.
func TestParseVKOAuthStateAcceptsLegacyRawSignatureBlob(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	payload := vkOAuthStatePayload{
		CodeVerifier: "abc123-verifier",
		RedirectURI:  "https://spacefestival.fun/space_app/auth",
		Next:         "/space_app",
		ExpiresAt:    now.Add(10 * time.Minute).Unix(),
	}

	rawPayload, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("json.Marshal(payload) error = %v", err)
	}
	signatureRaw := signVKOAuthStateRaw("secret", rawPayload)
	legacyBytes := append(rawPayload, signatureRaw...)
	legacyState := base64.RawURLEncoding.EncodeToString(legacyBytes)

	parsed, err := ParseVKOAuthState(legacyState, "secret", now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("ParseVKOAuthState() error = %v", err)
	}
	if parsed.CodeVerifier != payload.CodeVerifier {
		t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
	}
	if parsed.RedirectURI != payload.RedirectURI {
		t.Fatalf("RedirectURI = %q", parsed.RedirectURI)
	}
	if parsed.Next != payload.Next {
		t.Fatalf("Next = %q", parsed.Next)
	}
}

// TestParseVKOAuthStateAcceptsLegacyRawSignatureBlobWithSeparator verifies parse v k o auth state accepts legacy raw signature blob with separator behavior.
func TestParseVKOAuthStateAcceptsLegacyRawSignatureBlobWithSeparator(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	payload := vkOAuthStatePayload{
		CodeVerifier: "abc123-verifier",
		RedirectURI:  "https://spacefestival.fun/space_app/auth",
		Next:         "/space_app",
		ExpiresAt:    now.Add(10 * time.Minute).Unix(),
	}

	rawPayload, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("json.Marshal(payload) error = %v", err)
	}
	signatureRaw := signVKOAuthStateRaw("secret", rawPayload)
	legacyBytes := append(append(rawPayload, byte('.')), signatureRaw...)
	legacyState := base64.RawURLEncoding.EncodeToString(legacyBytes)

	parsed, err := ParseVKOAuthState(legacyState, "secret", now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("ParseVKOAuthState() error = %v", err)
	}
	if parsed.CodeVerifier != payload.CodeVerifier {
		t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
	}
}

// TestParseVKOAuthStateLegacyRawSignatureWithDotAndBraceBytes verifies parse v k o auth state legacy raw signature with dot and brace bytes behavior.
func TestParseVKOAuthStateLegacyRawSignatureWithDotAndBraceBytes(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	const secret = "secret"

	for i := 0; i < 5000; i++ {
		payload := vkOAuthStatePayload{
			CodeVerifier: fmt.Sprintf("verifier-%d", i),
			RedirectURI:  "https://spacefestival.fun/space_app/auth",
			Next:         fmt.Sprintf("/space_app/%d", i),
			ExpiresAt:    now.Add(10 * time.Minute).Unix(),
		}

		rawPayload, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("json.Marshal(payload) error = %v", err)
		}

		signatureRaw := signVKOAuthStateRaw(secret, rawPayload)
		if bytes.IndexByte(signatureRaw, '.') < 0 ||
			bytes.IndexByte(signatureRaw, '}') < 0 {
			continue
		}

		legacyBytes := append(rawPayload, signatureRaw...)
		legacyState := base64.RawURLEncoding.EncodeToString(legacyBytes)

		parsed, err := ParseVKOAuthState(legacyState, secret, now.Add(2*time.Minute))
		if err != nil {
			t.Fatalf("ParseVKOAuthState() error = %v", err)
		}
		if parsed.CodeVerifier != payload.CodeVerifier {
			t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
		}
		if parsed.RedirectURI != payload.RedirectURI {
			t.Fatalf("RedirectURI = %q", parsed.RedirectURI)
		}
		if parsed.Next != payload.Next {
			t.Fatalf("Next = %q", parsed.Next)
		}
		return
	}

	t.Fatal("could not generate legacy signature containing both '.' and '}'")
}

// TestParseVKOAuthStateAcceptsVKRepackedLegacyState verifies parse v k o auth state accepts v k repacked legacy state behavior.
func TestParseVKOAuthStateAcceptsVKRepackedLegacyState(t *testing.T) {
	now := time.Date(2026, time.January, 2, 3, 4, 5, 0, time.UTC)
	const secret = "secret"

	payload := vkOAuthStatePayload{
		CodeVerifier: "abc123-verifier",
		RedirectURI:  "https://spacefestival.fun/space_app/auth",
		Next:         "/space_app",
		ExpiresAt:    now.Add(10 * time.Minute).Unix(),
	}

	rawPayload, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("json.Marshal(payload) error = %v", err)
	}

	encodedPayload := base64.RawURLEncoding.EncodeToString(rawPayload)
	signatureRaw := signVKOAuthStateRaw(secret, []byte(encodedPayload))
	legacyBytes := append(rawPayload, signatureRaw...)
	legacyState := base64.RawURLEncoding.EncodeToString(legacyBytes)

	parsed, err := ParseVKOAuthState(legacyState, secret, now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("ParseVKOAuthState() error = %v", err)
	}
	if parsed.CodeVerifier != payload.CodeVerifier {
		t.Fatalf("CodeVerifier = %q", parsed.CodeVerifier)
	}
	if parsed.RedirectURI != payload.RedirectURI {
		t.Fatalf("RedirectURI = %q", parsed.RedirectURI)
	}
	if parsed.Next != payload.Next {
		t.Fatalf("Next = %q", parsed.Next)
	}
}

// TestBuildPKCECodeChallenge verifies build p k c e code challenge behavior.
func TestBuildPKCECodeChallenge(t *testing.T) {
	const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	const expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

	if got := BuildPKCECodeChallenge(verifier); got != expected {
		t.Fatalf("BuildPKCECodeChallenge() = %q, want %q", got, expected)
	}
}
