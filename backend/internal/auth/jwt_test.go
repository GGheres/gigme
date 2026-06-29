package auth

import (
	"testing"
	"time"
)

// TestSignAccessTokenUsesTwelveHourTTL verifies every standard authenticated session lasts twelve hours.
func TestSignAccessTokenUsesTwelveHourTTL(t *testing.T) {
	token, err := SignAccessToken("user-secret", 7, 7001, false, false)
	if err != nil {
		t.Fatalf("sign user token: %v", err)
	}

	claims, err := ParseAccessToken("user-secret", token)
	if err != nil {
		t.Fatalf("parse user token: %v", err)
	}
	assertTwelveHourTTL(t, claims)
}

// TestSignManagerAccessTokenUsesWorkShiftTTL verifies password-only manager sessions do not expire during a normal shift.
func TestSignManagerAccessTokenUsesWorkShiftTTL(t *testing.T) {
	token, err := SignManagerAccessTokenWithAdminPermissions(
		"manager-secret",
		42,
		-1001,
		[]string{"orders", "transfers", "scanner"},
	)
	if err != nil {
		t.Fatalf("sign manager token: %v", err)
	}

	claims, err := ParseAccessToken("manager-secret", token)
	if err != nil {
		t.Fatalf("parse manager token: %v", err)
	}
	if claims.IsAdmin {
		t.Fatal("manager token must remain scoped instead of becoming full admin")
	}
	assertTwelveHourTTL(t, claims)
	if len(claims.AdminPermissions) != 3 {
		t.Fatalf("expected scoped permissions, got %v", claims.AdminPermissions)
	}
}

// assertTwelveHourTTL validates the shared twelve-hour expiry with a small scheduling tolerance.
func assertTwelveHourTTL(t *testing.T, claims *AccessClaims) {
	t.Helper()
	if claims.ExpiresAt == nil {
		t.Fatal("expected token expiration")
	}
	remaining := time.Until(claims.ExpiresAt.Time)
	if remaining < 11*time.Hour+59*time.Minute || remaining > 12*time.Hour+time.Minute {
		t.Fatalf("unexpected token TTL: %s", remaining)
	}
}
