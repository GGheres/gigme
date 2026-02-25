package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const accessTokenTTL = 15 * time.Minute

// AccessClaims represents access claims.
type AccessClaims struct {
	UserID     int64 `json:"uid"`
	TelegramID int64 `json:"tgid"`
	IsNew      bool  `json:"new,omitempty"`
	IsAdmin    bool  `json:"admin,omitempty"`
	jwt.RegisteredClaims
}

// SignAccessToken signs access token.
func SignAccessToken(secret string, userID int64, telegramID int64, isNew bool, isAdmin bool) (string, error) {
	claims := AccessClaims{
		UserID:     userID,
		TelegramID: telegramID,
		IsNew:      isNew,
		IsAdmin:    isAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(accessTokenTTL)),
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
