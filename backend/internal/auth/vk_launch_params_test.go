package auth

import "testing"

// TestValidateVKLaunchParamsSuccess verifies validate v k launch params success behavior.
func TestValidateVKLaunchParamsSuccess(t *testing.T) {
	const (
		query  = "vk_user_id=494075&vk_app_id=6736218&vk_is_app_user=1&vk_are_notifications_enabled=1&vk_language=ru&vk_access_token_settings=&vk_platform=android&sign=htQFduJpLxz7ribXRZpDFUH-XEUhC9rBPTJkjUFEkRA"
		secret = "wvl68m4dR1UpLrVRli"
	)

	got, err := ValidateVKLaunchParams(query, secret)
	if err != nil {
		t.Fatalf("ValidateVKLaunchParams() error = %v", err)
	}
	if got.UserID != 494075 {
		t.Fatalf("UserID = %d, want %d", got.UserID, 494075)
	}
	if got.AppID != 6736218 {
		t.Fatalf("AppID = %d, want %d", got.AppID, 6736218)
	}
	if got.Platform != "android" {
		t.Fatalf("Platform = %q, want %q", got.Platform, "android")
	}
}

// TestValidateVKLaunchParamsInvalidSign verifies validate v k launch params invalid sign behavior.
func TestValidateVKLaunchParamsInvalidSign(t *testing.T) {
	const (
		query  = "vk_user_id=494075&vk_app_id=6736218&vk_platform=android&sign=invalid-sign"
		secret = "wvl68m4dR1UpLrVRli"
	)

	_, err := ValidateVKLaunchParams(query, secret)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

// TestValidateVKLaunchParamsEncodedValue verifies validate v k launch params encoded value behavior.
func TestValidateVKLaunchParamsEncodedValue(t *testing.T) {
	const (
		query  = "q=1&vk_user_id=111111&vk_app_id=111111&vk_is_app_user=1&vk_are_notifications_enabled=1&vk_language=ru&vk_access_token_settings=&vk_platform=andr%26oid&sign=f3d_AUYiYKEnG-pc9KpG_ZvHB8UEwS-ZeqwnIpgjqJE"
		secret = "AAAAAAAAAAAAAAAAAA"
	)

	got, err := ValidateVKLaunchParams(query, secret)
	if err != nil {
		t.Fatalf("ValidateVKLaunchParams() error = %v", err)
	}
	if got.UserID != 111111 {
		t.Fatalf("UserID = %d, want %d", got.UserID, 111111)
	}
	if got.AppID != 111111 {
		t.Fatalf("AppID = %d, want %d", got.AppID, 111111)
	}
	if got.Platform != "andr&oid" {
		t.Fatalf("Platform = %q, want %q", got.Platform, "andr&oid")
	}
}

// TestBuildVKMiniAppUsername verifies build v k mini app username behavior.
func TestBuildVKMiniAppUsername(t *testing.T) {
	if got := BuildVKMiniAppUsername(100); got != "vk100" {
		t.Fatalf("BuildVKMiniAppUsername(100) = %q", got)
	}
	if got := BuildVKMiniAppUsername(0); got != "vk_user" {
		t.Fatalf("BuildVKMiniAppUsername(0) = %q", got)
	}
}
