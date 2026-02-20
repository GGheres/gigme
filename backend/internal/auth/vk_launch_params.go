package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

var ErrInvalidVKLaunchParams = errors.New("invalid vk launch params")

type VKLaunchParams struct {
	UserID   int64
	AppID    int64
	Platform string
}

func ValidateVKLaunchParams(querySearch string, secretKey string) (VKLaunchParams, error) {
	raw := strings.TrimSpace(querySearch)
	if raw == "" {
		return VKLaunchParams{}, invalidVKLaunchParams("empty launch params")
	}

	searchIndex := strings.Index(raw, "?")
	if searchIndex >= 0 {
		raw = raw[searchIndex+1:]
	}
	raw = strings.TrimLeft(raw, "?")
	if raw == "" {
		return VKLaunchParams{}, invalidVKLaunchParams("empty query string")
	}

	parsed, err := url.ParseQuery(raw)
	if err != nil {
		return VKLaunchParams{}, invalidVKLaunchParams("malformed query string")
	}

	sign := strings.TrimSpace(parsed.Get("sign"))
	if sign == "" {
		return VKLaunchParams{}, invalidVKLaunchParams("missing sign")
	}

	vkParams := collectVKLaunchSignParams(parsed)
	if len(vkParams) == 0 {
		return VKLaunchParams{}, invalidVKLaunchParams("missing vk_* params")
	}

	calculated := calculateVKLaunchSign(vkParams, secretKey)
	if !hmac.Equal([]byte(calculated), []byte(sign)) {
		return VKLaunchParams{}, invalidVKLaunchParams("sign mismatch")
	}

	userID, err := strconv.ParseInt(strings.TrimSpace(parsed.Get("vk_user_id")), 10, 64)
	if err != nil || userID <= 0 {
		return VKLaunchParams{}, invalidVKLaunchParams("invalid vk_user_id")
	}

	appID, err := strconv.ParseInt(strings.TrimSpace(parsed.Get("vk_app_id")), 10, 64)
	if err != nil || appID <= 0 {
		return VKLaunchParams{}, invalidVKLaunchParams("invalid vk_app_id")
	}

	return VKLaunchParams{
		UserID:   userID,
		AppID:    appID,
		Platform: strings.TrimSpace(parsed.Get("vk_platform")),
	}, nil
}

func collectVKLaunchSignParams(parsed url.Values) url.Values {
	out := make(url.Values)
	for key, values := range parsed {
		if !strings.HasPrefix(key, "vk_") {
			continue
		}
		for _, value := range values {
			out.Add(key, value)
		}
	}
	return out
}

func calculateVKLaunchSign(params url.Values, secretKey string) string {
	mac := hmac.New(sha256.New, []byte(secretKey))
	_, _ = mac.Write([]byte(params.Encode()))
	hash := base64.URLEncoding.EncodeToString(mac.Sum(nil))
	hash = strings.ReplaceAll(hash, "+", "-")
	hash = strings.ReplaceAll(hash, "/", "_")
	return strings.TrimRight(hash, "=")
}

func invalidVKLaunchParams(reason string) error {
	if strings.TrimSpace(reason) == "" {
		return ErrInvalidVKLaunchParams
	}
	return fmt.Errorf("%w: %s", ErrInvalidVKLaunchParams, reason)
}

func BuildVKMiniAppUsername(viewerID int64) string {
	if viewerID <= 0 {
		return "vk_user"
	}
	return fmt.Sprintf("vk%d", viewerID)
}
