package handlers

import (
	"bytes"
	"net"
	"net/url"
	"testing"
)

// TestIsDisallowedOutboundIP verifies that server-side media fetches cannot
// reach local infrastructure while ordinary public addresses remain usable.
func TestIsDisallowedOutboundIP(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		address    string
		disallowed bool
	}{
		{name: "loopback", address: "127.0.0.1", disallowed: true},
		{name: "private", address: "10.20.30.40", disallowed: true},
		{name: "link local metadata", address: "169.254.169.254", disallowed: true},
		{name: "ipv6 loopback", address: "::1", disallowed: true},
		{name: "ipv6 private", address: "fd00::1", disallowed: true},
		{name: "public ipv4", address: "8.8.8.8", disallowed: false},
		{name: "public ipv6", address: "2606:4700:4700::1111", disallowed: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if actual := isDisallowedOutboundIP(net.ParseIP(test.address)); actual != test.disallowed {
				t.Fatalf("isDisallowedOutboundIP(%q) = %v, want %v", test.address, actual, test.disallowed)
			}
		})
	}
}

// TestValidateRemoteMediaURL verifies that only credential-free HTTP(S) URLs
// can reach the protected outbound transport.
func TestValidateRemoteMediaURL(t *testing.T) {
	t.Parallel()
	valid, _ := url.Parse("https://cdn.example.com/image.png")
	if err := validateRemoteMediaURL(valid); err != nil {
		t.Fatalf("expected public HTTPS URL to be accepted: %v", err)
	}
	for _, raw := range []string{
		"file:///etc/passwd",
		"https://user:password@example.com/image.png",
		"https:///missing-host.png",
	} {
		target, _ := url.Parse(raw)
		if err := validateRemoteMediaURL(target); err == nil {
			t.Fatalf("expected %q to be rejected", raw)
		}
	}
}

// TestReadBoundedMedia verifies that empty and oversized upstream bodies are
// rejected before any response bytes are sent to the client.
func TestReadBoundedMedia(t *testing.T) {
	t.Parallel()
	if _, err := readBoundedMedia(bytes.NewReader(nil)); err == nil {
		t.Fatal("expected empty media to be rejected")
	}
	oversized := bytes.Repeat([]byte{1}, int(maxMediaBytes)+1)
	if _, err := readBoundedMedia(bytes.NewReader(oversized)); err == nil {
		t.Fatal("expected oversized media to be rejected")
	}
	valid := []byte{0xFF, 0xD8, 0xFF, 0xDB}
	payload, err := readBoundedMedia(bytes.NewReader(valid))
	if err != nil || !bytes.Equal(payload, valid) {
		t.Fatalf("expected bounded media to be returned, payload=%v err=%v", payload, err)
	}
}

// TestDetectAllowedImageContentType verifies byte-level type validation for
// every image format supported by the upload contract.
func TestDetectAllowedImageContentType(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		payload  []byte
		expected string
	}{
		{name: "jpeg", payload: []byte{0xFF, 0xD8, 0xFF, 0xDB, 0, 0}, expected: "image/jpeg"},
		{name: "png", payload: []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, expected: "image/png"},
		{name: "webp", payload: []byte("RIFF0000WEBPVP8 "), expected: "image/webp"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			actual, ok := detectAllowedImageContentType(test.payload)
			if !ok || actual != test.expected {
				t.Fatalf("detectAllowedImageContentType() = %q, %v; want %q, true", actual, ok, test.expected)
			}
		})
	}
	if _, ok := detectAllowedImageContentType([]byte("<script>alert(1)</script>")); ok {
		t.Fatal("expected active content to be rejected")
	}
}
