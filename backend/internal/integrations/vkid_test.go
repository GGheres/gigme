package integrations

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

// TestVKIDExchangeCodeUsesQueryParamsAndCodeBody verifies v k i d exchange code uses query params and code body behavior.
func TestVKIDExchangeCodeUsesQueryParamsAndCodeBody(t *testing.T) {
	t.Parallel()

	var gotMethod string
	var gotPath string
	var gotQuery url.Values
	var gotBody url.Values

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Helper()

		gotMethod = r.Method
		gotPath = r.URL.Path
		gotQuery = r.URL.Query()

		rawBody, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("ReadAll(r.Body) error = %v", err)
		}
		gotBody, err = url.ParseQuery(string(rawBody))
		if err != nil {
			t.Fatalf("url.ParseQuery(body) error = %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"access_token":"token-1",
			"refresh_token":"refresh-1",
			"id_token":"id-token-1",
			"expires_in":600,
			"user_id":"42",
			"scope":"phone"
		}`))
	}))
	defer server.Close()

	client := NewVKIDClient("123456")
	client.baseURL = server.URL
	client.client = server.Client()

	token, err := client.ExchangeCode(
		context.Background(),
		"vk2.a.sample-code",
		"sample_verifier",
		"sample_device",
		"https://spacefestival.fun/space_app/auth",
		"signed.state.token",
	)
	if err != nil {
		t.Fatalf("ExchangeCode() error = %v", err)
	}

	if gotMethod != http.MethodPost {
		t.Fatalf("method = %q, want %q", gotMethod, http.MethodPost)
	}
	if gotPath != "/oauth2/auth" {
		t.Fatalf("path = %q, want %q", gotPath, "/oauth2/auth")
	}

	expectedQuery := map[string]string{
		"grant_type":    "authorization_code",
		"client_id":     "123456",
		"code_verifier": "sample_verifier",
		"device_id":     "sample_device",
		"redirect_uri":  "https://spacefestival.fun/space_app/auth",
		"state":         "signed.state.token",
	}
	for key, want := range expectedQuery {
		if got := gotQuery.Get(key); got != want {
			t.Fatalf("query[%q] = %q, want %q", key, got, want)
		}
	}

	if got := gotBody.Get("code"); got != "vk2.a.sample-code" {
		t.Fatalf("body[code] = %q, want %q", got, "vk2.a.sample-code")
	}
	if gotBody.Get("state") != "" {
		t.Fatalf("body[state] = %q, want empty", gotBody.Get("state"))
	}

	if token.AccessToken != "token-1" {
		t.Fatalf("token.AccessToken = %q, want %q", token.AccessToken, "token-1")
	}
	if token.UserID != 42 {
		t.Fatalf("token.UserID = %d, want %d", token.UserID, 42)
	}
}

// TestVKIDGetUserInfoUsesClientIDQuery verifies v k i d get user info uses client i d query behavior.
func TestVKIDGetUserInfoUsesClientIDQuery(t *testing.T) {
	t.Parallel()

	var gotPath string
	var gotQuery url.Values
	var gotBody url.Values

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Helper()

		gotPath = r.URL.Path
		gotQuery = r.URL.Query()

		rawBody, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("ReadAll(r.Body) error = %v", err)
		}
		gotBody, err = url.ParseQuery(string(rawBody))
		if err != nil {
			t.Fatalf("url.ParseQuery(body) error = %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"user": {
				"user_id": "42",
				"first_name": "VK",
				"last_name": "User",
				"avatar": "https://cdn.vk.test/u.png"
			}
		}`))
	}))
	defer server.Close()

	client := NewVKIDClient("7890")
	client.baseURL = server.URL
	client.client = server.Client()

	userInfo, err := client.GetUserInfo(context.Background(), "access-token-1")
	if err != nil {
		t.Fatalf("GetUserInfo() error = %v", err)
	}

	if gotPath != "/oauth2/user_info" {
		t.Fatalf("path = %q, want %q", gotPath, "/oauth2/user_info")
	}
	if got := gotQuery.Get("client_id"); got != "7890" {
		t.Fatalf("query[client_id] = %q, want %q", got, "7890")
	}
	if got := gotBody.Get("access_token"); got != "access-token-1" {
		t.Fatalf("body[access_token] = %q, want %q", got, "access-token-1")
	}

	if userInfo.UserID != 42 {
		t.Fatalf("userInfo.UserID = %d, want %d", userInfo.UserID, 42)
	}
	if userInfo.FirstName != "VK" {
		t.Fatalf("userInfo.FirstName = %q, want %q", userInfo.FirstName, "VK")
	}
}
