package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
)

var ErrInvalidVKLaunchParams = errors.New("invalid vk launch params")

type VKLaunchParams struct {
	UserID   int64
	AppID    int64
	Platform string
}

type vkLaunchPair struct {
	key   string
	value string
}

func ValidateVKLaunchParams(querySearch string, secretKey string) (VKLaunchParams, error) {
	raw := strings.TrimSpace(querySearch)
	if raw == "" {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	searchIndex := strings.Index(raw, "?")
	if searchIndex >= 0 {
		raw = raw[searchIndex+1:]
	}
	raw = strings.TrimLeft(raw, "?")
	if raw == "" {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	sign, pairs := extractVKLaunchSignAndPairs(raw)
	if sign == "" || len(pairs) == 0 {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	decodedSign, err := url.QueryUnescape(sign)
	if err == nil {
		sign = decodedSign
	}

	calculated := calculateVKLaunchSign(pairs, secretKey)
	if !hmac.Equal([]byte(calculated), []byte(sign)) {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	parsed, err := url.ParseQuery(raw)
	if err != nil {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	userID, err := strconv.ParseInt(strings.TrimSpace(parsed.Get("vk_user_id")), 10, 64)
	if err != nil || userID <= 0 {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	appID, err := strconv.ParseInt(strings.TrimSpace(parsed.Get("vk_app_id")), 10, 64)
	if err != nil || appID <= 0 {
		return VKLaunchParams{}, ErrInvalidVKLaunchParams
	}

	return VKLaunchParams{
		UserID:   userID,
		AppID:    appID,
		Platform: strings.TrimSpace(parsed.Get("vk_platform")),
	}, nil
}

func extractVKLaunchSignAndPairs(rawQuery string) (string, []vkLaunchPair) {
	sign := ""
	pairs := make([]vkLaunchPair, 0)

	for _, part := range strings.Split(rawQuery, "&") {
		if part == "" {
			continue
		}
		pieces := strings.SplitN(part, "=", 2)
		key := pieces[0]
		if key == "" {
			continue
		}

		value := ""
		if len(pieces) > 1 {
			value = pieces[1]
		}

		if strings.HasPrefix(key, "vk_") {
			pairs = append(pairs, vkLaunchPair{key: key, value: value})
			continue
		}
		if key == "sign" {
			sign = value
		}
	}

	sort.SliceStable(pairs, func(i, j int) bool {
		return pairs[i].key < pairs[j].key
	})
	return sign, pairs
}

func calculateVKLaunchSign(params []vkLaunchPair, secretKey string) string {
	var builder strings.Builder
	for i, pair := range params {
		if i > 0 {
			builder.WriteByte('&')
		}
		builder.WriteString(pair.key)
		builder.WriteByte('=')
		builder.WriteString(url.PathEscape(pair.value))
	}

	mac := hmac.New(sha256.New, []byte(secretKey))
	_, _ = mac.Write([]byte(builder.String()))
	hash := base64.URLEncoding.EncodeToString(mac.Sum(nil))
	hash = strings.ReplaceAll(hash, "+", "-")
	hash = strings.ReplaceAll(hash, "/", "_")
	return strings.TrimRight(hash, "=")
}

func BuildVKMiniAppUsername(viewerID int64) string {
	if viewerID <= 0 {
		return "vk_user"
	}
	return fmt.Sprintf("vk%d", viewerID)
}
