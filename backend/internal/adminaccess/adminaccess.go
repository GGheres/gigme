package adminaccess

import (
	"hash/fnv"
	"strings"

	"gigme/backend/internal/config"

	"golang.org/x/crypto/bcrypt"
)

const (
	PermissionUsers       = "users"
	PermissionBroadcasts  = "broadcasts"
	PermissionParser      = "parser"
	PermissionBotMessages = "bot_messages"
	PermissionOrders      = "orders"
	PermissionTransfers   = "transfers"
	PermissionScanner     = "scanner"
	PermissionProducts    = "products"
	PermissionPromos      = "promos"
	PermissionStats       = "stats"
	PermissionLanding     = "landing"
	PermissionEvents      = "events"
)

var allPermissions = []string{
	PermissionUsers,
	PermissionBroadcasts,
	PermissionParser,
	PermissionBotMessages,
	PermissionOrders,
	PermissionTransfers,
	PermissionScanner,
	PermissionProducts,
	PermissionPromos,
	PermissionStats,
	PermissionLanding,
	PermissionEvents,
}

var managerPermissions = []string{
	PermissionOrders,
	PermissionTransfers,
	PermissionScanner,
}

// Account represents one admin-facing account with scoped permissions.
type Account struct {
	Login               string
	Password            string
	PasswordHash        string
	TelegramIDs         map[int64]struct{}
	SyntheticTelegramID int64
	Permissions         []string
}

// Resolver resolves admin accounts and permission scopes from config.
type Resolver struct {
	accountsByLogin         map[string]Account
	permissionsByTelegramID map[int64][]string
}

// NewResolver creates the requested admin access resolver.
func NewResolver(cfg *config.Config) *Resolver {
	resolver := &Resolver{
		accountsByLogin:         make(map[string]Account),
		permissionsByTelegramID: make(map[int64][]string),
	}
	if cfg == nil {
		return resolver
	}

	resolver.addAccount(Account{
		Login:        strings.TrimSpace(cfg.AdminLogin),
		Password:     cfg.AdminPassword,
		PasswordHash: strings.TrimSpace(cfg.AdminPassHash),
		TelegramIDs:  cloneIDSet(cfg.AdminTGIDs),
		Permissions:  AllPermissions(),
	})

	managerLogin := strings.TrimSpace(cfg.ManagerLogin)
	managerAccount := Account{
		Login:        managerLogin,
		Password:     cfg.ManagerPassword,
		PasswordHash: strings.TrimSpace(cfg.ManagerPassHash),
		TelegramIDs:  cloneIDSet(cfg.ManagerTGIDs),
		Permissions:  ManagerPermissions(),
	}
	if managerLogin != "" && len(managerAccount.TelegramIDs) == 0 {
		managerAccount.SyntheticTelegramID = syntheticTelegramID(managerLogin)
	}
	resolver.addAccount(managerAccount)

	return resolver
}

// AllPermissions returns a copy of the full admin permission set.
func AllPermissions() []string {
	return append([]string(nil), allPermissions...)
}

// ManagerPermissions returns a copy of the manager permission set.
func ManagerPermissions() []string {
	return append([]string(nil), managerPermissions...)
}

// HasAccounts reports whether at least one admin-facing account is configured.
func (r *Resolver) HasAccounts() bool {
	return r != nil && len(r.accountsByLogin) > 0
}

// Authenticate handles account authentication by login and password.
func (r *Resolver) Authenticate(username, password string) (Account, bool) {
	if r == nil {
		return Account{}, false
	}
	account, ok := r.accountsByLogin[strings.ToLower(strings.TrimSpace(username))]
	if !ok {
		return Account{}, false
	}
	if !passwordMatches(account, password) {
		return Account{}, false
	}
	return account, true
}

// ResolveTelegramID resolves the effective Telegram identifier for the account.
func (r *Resolver) ResolveTelegramID(account Account, requested *int64) (int64, bool) {
	if requested != nil && *requested > 0 {
		if len(account.TelegramIDs) == 0 {
			return 0, false
		}
		if _, ok := account.TelegramIDs[*requested]; ok {
			return *requested, true
		}
		return 0, false
	}
	if len(account.TelegramIDs) == 1 {
		for id := range account.TelegramIDs {
			return id, true
		}
	}
	if account.SyntheticTelegramID != 0 {
		return account.SyntheticTelegramID, true
	}
	return 0, false
}

// PermissionsForTelegramID returns the configured permissions for the identifier.
func (r *Resolver) PermissionsForTelegramID(telegramID int64) []string {
	if r == nil || telegramID == 0 {
		return nil
	}
	permissions, ok := r.permissionsByTelegramID[telegramID]
	if !ok {
		return nil
	}
	return append([]string(nil), permissions...)
}

// HasPermission reports whether the permission is present.
func HasPermission(permissions []string, permission string) bool {
	target := strings.TrimSpace(permission)
	if target == "" {
		return false
	}
	for _, item := range permissions {
		if strings.EqualFold(strings.TrimSpace(item), target) {
			return true
		}
	}
	return false
}

// HasAnyPermission reports whether any requested permission is present.
func HasAnyPermission(permissions []string, requested ...string) bool {
	for _, permission := range requested {
		if HasPermission(permissions, permission) {
			return true
		}
	}
	return false
}

// HasPanelAccess reports whether at least one admin permission is present.
func HasPanelAccess(permissions []string) bool {
	return len(permissions) > 0
}

// addAccount stores account data and reverse permission lookups.
func (r *Resolver) addAccount(account Account) {
	if r == nil {
		return
	}
	login := strings.ToLower(strings.TrimSpace(account.Login))
	if login == "" || (strings.TrimSpace(account.Password) == "" && strings.TrimSpace(account.PasswordHash) == "") {
		return
	}
	account.Permissions = uniquePermissions(account.Permissions)
	r.accountsByLogin[login] = account
	for id := range account.TelegramIDs {
		if id == 0 {
			continue
		}
		r.permissionsByTelegramID[id] = append([]string(nil), account.Permissions...)
	}
	if account.SyntheticTelegramID != 0 {
		r.permissionsByTelegramID[account.SyntheticTelegramID] = append([]string(nil), account.Permissions...)
	}
}

// cloneIDSet creates a defensive copy of the identifier set.
func cloneIDSet(source map[int64]struct{}) map[int64]struct{} {
	if len(source) == 0 {
		return nil
	}
	clone := make(map[int64]struct{}, len(source))
	for id := range source {
		if id == 0 {
			continue
		}
		clone[id] = struct{}{}
	}
	if len(clone) == 0 {
		return nil
	}
	return clone
}

// passwordMatches reports whether password matches the configured account secret.
func passwordMatches(account Account, password string) bool {
	if account.PasswordHash != "" {
		return bcrypt.CompareHashAndPassword([]byte(account.PasswordHash), []byte(password)) == nil
	}
	return password == account.Password
}

// syntheticTelegramID derives a stable synthetic identifier for accounts without Telegram binding.
func syntheticTelegramID(login string) int64 {
	normalized := strings.ToLower(strings.TrimSpace(login))
	if normalized == "" {
		return 0
	}
	hasher := fnv.New64a()
	_, _ = hasher.Write([]byte(normalized))
	value := int64(hasher.Sum64())
	if value < 0 {
		return value
	}
	return -value
}

// uniquePermissions normalizes and deduplicates permissions.
func uniquePermissions(permissions []string) []string {
	if len(permissions) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(permissions))
	out := make([]string, 0, len(permissions))
	for _, permission := range permissions {
		normalized := strings.ToLower(strings.TrimSpace(permission))
		if normalized == "" {
			continue
		}
		if _, ok := seen[normalized]; ok {
			continue
		}
		seen[normalized] = struct{}{}
		out = append(out, normalized)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
