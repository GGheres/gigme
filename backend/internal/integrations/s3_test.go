package integrations

import (
	"strings"
	"testing"
)

// TestS3ClientKeyFromURL verifies that only configured object-store hosts can
// produce trusted keys, even when an attacker copies the expected bucket path.
func TestS3ClientKeyFromURL(t *testing.T) {
	t.Parallel()
	client := &S3Client{
		bucket:         "gigme",
		endpoint:       "http://minio:9000",
		publicEndpoint: "https://media.example.com",
	}
	tests := []struct {
		name     string
		url      string
		expected string
		valid    bool
	}{
		{name: "public path style", url: "https://media.example.com/gigme/events/image.png", expected: "events/image.png", valid: true},
		{name: "internal path style", url: "http://minio:9000/gigme/events/image.png", expected: "events/image.png", valid: true},
		{name: "aws virtual host", url: "https://gigme.s3.amazonaws.com/events/image.png", expected: "events/image.png", valid: true},
		{name: "attacker matching path", url: "http://169.254.169.254/gigme/events/image.png", valid: false},
		{name: "wrong bucket", url: "https://media.example.com/other/events/image.png", valid: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			actual, valid := client.KeyFromURL(test.url)
			if valid != test.valid || actual != test.expected {
				t.Fatalf("KeyFromURL(%q) = %q, %v; want %q, %v", test.url, actual, valid, test.expected, test.valid)
			}
		})
	}
}

// TestBuildObjectKeySanitizesFileName verifies that user-controlled path and
// separator characters cannot shape the generated S3 object hierarchy.
func TestBuildObjectKeySanitizesFileName(t *testing.T) {
	t.Parallel()
	key := buildObjectKey("../../my unsafe/image<script>.png")
	if strings.Contains(key, "..") || strings.Contains(key, "<") || strings.Contains(key, ">") {
		t.Fatalf("buildObjectKey returned unsafe key %q", key)
	}
	if !strings.HasSuffix(key, "image-script-.png") {
		t.Fatalf("buildObjectKey returned unexpected filename %q", key)
	}
}
