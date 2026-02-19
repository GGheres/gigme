package auth

import "testing"

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

func TestBuildVKMiniAppUsername(t *testing.T) {
	if got := BuildVKMiniAppUsername(100); got != "vk100" {
		t.Fatalf("BuildVKMiniAppUsername(100) = %q", got)
	}
	if got := BuildVKMiniAppUsername(0); got != "vk_user" {
		t.Fatalf("BuildVKMiniAppUsername(0) = %q", got)
	}
}
