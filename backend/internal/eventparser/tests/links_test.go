package tests

import (
	"reflect"
	"testing"

	"gigme/backend/internal/eventparser/extract"
)

func TestExtractLinksDedup(t *testing.T) {
	text := "Visit https://example.com/a and https://example.com/a plus https://example.org/b."
	got := extract.ExtractLinks(text)
	want := []string{"https://example.com/a", "https://example.org/b"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected links: got=%v want=%v", got, want)
	}
}
