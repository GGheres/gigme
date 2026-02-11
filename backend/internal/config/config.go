package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Env           string
	HTTPAddr      string
	DatabaseURL   string
	RedisURL      string
	JWTSecret     string
	HMACSecret    string
	TelegramToken string
	TelegramUser  string
	BaseURL       string
	APIPublicURL  string
	PhoneNumber   string
	USDTWallet    string
	USDTNetwork   string
	USDTMemo      string
	PaymentQRData string
	AdminTGIDs    map[int64]struct{}
	AdminLogin    string
	AdminPassword string
	AdminPassHash string
	Tochka        TochkaConfig
	S3            S3Config
	Logging       LoggingConfig
}

type TochkaConfig struct {
	ClientID     string
	ClientSecret string
	CustomerCode string
	MerchantID   string
	AccountID    string
	Scope        string
	TokenURL     string
	BaseURL      string
	RedirectURL  string
}

type S3Config struct {
	Endpoint       string
	PublicEndpoint string
	Bucket         string
	AccessKey      string
	SecretKey      string
	Region         string
	UseSSL         bool
}

type LoggingConfig struct {
	Level  string
	Format string
	File   string
}

func Load() (*Config, error) {
	hmacSecret := strings.TrimSpace(os.Getenv("HMAC_SECRET"))
	if hmacSecret == "" {
		hmacSecret = strings.TrimSpace(os.Getenv("TICKET_HMAC_SECRET"))
	}
	cfg := &Config{
		Env:           getenv("APP_ENV", "dev"),
		HTTPAddr:      getenv("HTTP_ADDR", ":8080"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		RedisURL:      os.Getenv("REDIS_URL"),
		JWTSecret:     os.Getenv("JWT_SECRET"),
		HMACSecret:    hmacSecret,
		TelegramToken: os.Getenv("TELEGRAM_BOT_TOKEN"),
		TelegramUser:  os.Getenv("TELEGRAM_BOT_USERNAME"),
		BaseURL:       getenv("BASE_URL", ""),
		APIPublicURL:  getenv("API_PUBLIC_URL", ""),
		PhoneNumber:   getenv("PHONE_NUMBER", ""),
		USDTWallet:    getenv("USDT_WALLET", ""),
		USDTNetwork:   getenv("USDT_NETWORK", "TRC20"),
		USDTMemo:      getenv("USDT_MEMO", ""),
		PaymentQRData: getenv("PAYMENT_QR_DATA", ""),
		AdminLogin:    getenv("ADMIN_LOGIN", ""),
		AdminPassword: os.Getenv("ADMIN_PASSWORD"),
		AdminPassHash: os.Getenv("ADMIN_PASSWORD_HASH"),
		Tochka: TochkaConfig{
			ClientID:     strings.TrimSpace(os.Getenv("TOCHKA_CLIENT_ID")),
			ClientSecret: strings.TrimSpace(os.Getenv("TOCHKA_CLIENT_SECRET")),
			CustomerCode: strings.TrimSpace(os.Getenv("TOCHKA_CUSTOMER_CODE")),
			MerchantID:   strings.TrimSpace(os.Getenv("TOCHKA_MERCHANT_ID")),
			AccountID:    strings.TrimSpace(os.Getenv("TOCHKA_ACCOUNT_ID")),
			Scope:        strings.TrimSpace(getenv("TOCHKA_SCOPE", "sbp")),
			TokenURL:     strings.TrimSpace(getenv("TOCHKA_TOKEN_URL", "https://enter.tochka.com/connect/token")),
			BaseURL:      strings.TrimSpace(getenv("TOCHKA_API_BASE_URL", "https://enter.tochka.com/uapi")),
			RedirectURL:  strings.TrimSpace(os.Getenv("TOCHKA_REDIRECT_URL")),
		},
		S3: S3Config{
			Endpoint:       os.Getenv("S3_ENDPOINT"),
			PublicEndpoint: os.Getenv("S3_PUBLIC_ENDPOINT"),
			Bucket:         os.Getenv("S3_BUCKET"),
			AccessKey:      os.Getenv("S3_ACCESS_KEY"),
			SecretKey:      os.Getenv("S3_SECRET_KEY"),
			Region:         getenv("S3_REGION", "us-east-1"),
			UseSSL:         getenvBool("S3_USE_SSL", true),
		},
		AdminTGIDs: parseIDSet(os.Getenv("ADMIN_TELEGRAM_IDS")),
		Logging: LoggingConfig{
			Level:  getenv("LOG_LEVEL", "info"),
			Format: getenv("LOG_FORMAT", "text"),
			File:   os.Getenv("LOG_FILE"),
		},
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if cfg.HMACSecret == "" {
		cfg.HMACSecret = cfg.JWTSecret
	}
	if cfg.TelegramToken == "" {
		return nil, fmt.Errorf("TELEGRAM_BOT_TOKEN is required")
	}

	return cfg, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getenvBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	parsed, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return parsed
}

func parseIDSet(val string) map[int64]struct{} {
	set := make(map[int64]struct{})
	for _, part := range strings.Split(val, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		id, err := strconv.ParseInt(part, 10, 64)
		if err != nil {
			continue
		}
		set[id] = struct{}{}
	}
	return set
}
