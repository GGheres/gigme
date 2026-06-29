package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const accessTokenTTL = 12 * time.Hour
const managerAccessTokenTTL = 12 * time.Hour

// AccessClaims represents access claims.
type AccessClaims struct {
	UserID           int64    `json:"uid"`
	TelegramID       int64    `json:"tgid"`
	IsNew            bool     `json:"new,omitempty"`
	IsAdmin          bool     `json:"admin,omitempty"`
	AdminPermissions []string `json:"admin_permissions,omitempty"`
	jwt.RegisteredClaims
}

// SignAccessToken signs access token.
func SignAccessToken(secret string, userID int64, telegramID int64, isNew bool, isAdmin bool) (string, error) {
	return SignAccessTokenWithAdminPermissions(secret, userID, telegramID, isNew, isAdmin, nil)
}

// SignAccessTokenWithAdminPermissions signs access token with scoped admin permissions.
func SignAccessTokenWithAdminPermissions(
	secret string,
	userID int64,
	telegramID int64,
	isNew bool,
	isAdmin bool,
	adminPermissions []string,
) (string, error) {
	return signAccessTokenWithTTL(
		secret,
		userID,
		telegramID,
		isNew,
		isAdmin,
		adminPermissions,
		accessTokenTTL,
	)
}

// SignManagerAccessTokenWithAdminPermissions signs a scoped manager session that remains valid for one work shift.
// Manager APK users authenticate with a password and cannot silently renew through Telegram, so this dedicated TTL
// prevents an active orders/transfers/scanner session from expiring every fifteen minutes.
func SignManagerAccessTokenWithAdminPermissions(
	secret string,
	userID int64,
	telegramID int64,
	adminPermissions []string,
) (string, error) {
	return signAccessTokenWithTTL(
		secret,
		userID,
		telegramID,
		false,
		false,
		adminPermissions,
		managerAccessTokenTTL,
	)
}

// signAccessTokenWithTTL creates the common JWT payload while keeping each authentication flow's lifetime explicit.
func signAccessTokenWithTTL(
	secret string,
	userID int64,
	telegramID int64,
	isNew bool,
	isAdmin bool,
	adminPermissions []string,
	ttl time.Duration,
) (string, error) {
	claims := AccessClaims{
		UserID:           userID,
		TelegramID:       telegramID,
		IsNew:            isNew,
		IsAdmin:          isAdmin,
		AdminPermissions: append([]string(nil), adminPermissions...),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Subject:   "user",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// ParseAccessToken parses access token.
func ParseAccessToken(secret string, tokenString string) (*AccessClaims, error) {
	parsed, err := jwt.ParseWithClaims(tokenString, &AccessClaims{}, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(secret), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*AccessClaims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
