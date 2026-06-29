package adminaccess

import (
	"testing"

	"gigme/backend/internal/config"
)

// TestNewResolverConfiguresManager verifies new resolver configures manager behavior.
func TestNewResolverConfiguresManager(t *testing.T) {
	cfg := &config.Config{
		AdminLogin:      "admin",
		AdminPassword:   "secret",
		AdminTGIDs:      map[int64]struct{}{1001: {}},
		ManagerLogin:    "PIVO",
		ManagerPassword: "VKUSNOE",
	}

	resolver := NewResolver(cfg)
	account, ok := resolver.Authenticate("PIVO", "VKUSNOE")
	if !ok {
		t.Fatalf("expected manager account to authenticate")
	}
	if !HasAnyPermission(account.Permissions, PermissionOrders, PermissionTransfers, PermissionScanner) {
		t.Fatalf("expected manager permissions to include operational tabs")
	}
	if HasPermission(account.Permissions, PermissionUsers) {
		t.Fatalf("manager must not receive full admin permissions")
	}

	telegramID, ok := resolver.ResolveTelegramID(account, nil)
	if !ok || telegramID >= 0 {
		t.Fatalf("expected synthetic manager telegram id, got %d ok=%v", telegramID, ok)
	}

	resolvedPermissions := resolver.PermissionsForTelegramID(telegramID)
	if !HasPermission(resolvedPermissions, PermissionScanner) {
		t.Fatalf("expected synthetic telegram id to resolve scanner permission")
	}
}

// TestManagerAccountSupportsPasswordOnlyLoginWithBoundTelegramIDs verifies manager password auth can use a synthetic session even when Telegram IDs are configured.
func TestManagerAccountSupportsPasswordOnlyLoginWithBoundTelegramIDs(t *testing.T) {
	cfg := &config.Config{
		ManagerLogin:    "manager",
		ManagerPassword: "secret",
		ManagerTGIDs: map[int64]struct{}{
			1001: {},
			1002: {},
		},
	}

	resolver := NewResolver(cfg)
	account, ok := resolver.Authenticate("manager", "secret")
	if !ok {
		t.Fatalf("expected manager account to authenticate")
	}

	telegramID, ok := resolver.ResolveTelegramID(account, nil)
	if !ok || telegramID >= 0 {
		t.Fatalf("expected password-only manager login to resolve synthetic id, got %d ok=%v", telegramID, ok)
	}

	permissions := resolver.PermissionsForTelegramID(telegramID)
	if !HasAnyPermission(permissions, PermissionOrders, PermissionTransfers, PermissionScanner) {
		t.Fatalf("expected synthetic manager id to keep operational permissions")
	}
}

// TestNewResolverKeepsFullAdminPermissions verifies full admin identifiers keep unrestricted access.
func TestNewResolverKeepsFullAdminPermissions(t *testing.T) {
	cfg := &config.Config{
		AdminLogin:    "admin",
		AdminPassword: "secret",
		AdminTGIDs:    map[int64]struct{}{653848276: {}},
	}

	resolver := NewResolver(cfg)
	permissions := resolver.PermissionsForTelegramID(653848276)
	if !HasPermission(permissions, PermissionUsers) {
		t.Fatalf("expected full admin permission set")
	}
	if !HasPermission(permissions, PermissionLanding) {
		t.Fatalf("expected landing permission for full admin")
	}
}
