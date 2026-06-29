package integrations

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/url"
	"path"
	"regexp"
	"strings"
	"time"

	"gigme/backend/internal/config"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// S3Client represents s3 client.
type S3Client struct {
	bucket         string
	endpoint       string
	publicEndpoint string
	client         *s3.Client
}

var unsafeObjectKeyCharacters = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

// NewS3 creates s3.
func NewS3(ctx context.Context, cfg config.S3Config) (*S3Client, error) {
	if cfg.Bucket == "" {
		return nil, fmt.Errorf("S3_BUCKET is required")
	}

	region := cfg.Region
	if region == "" {
		region = "us-east-1"
	}

	endpoint := normalizeEndpoint(cfg.Endpoint, cfg.UseSSL)
	publicEndpoint := normalizeEndpoint(cfg.PublicEndpoint, cfg.UseSSL)
	if publicEndpoint == "" {
		publicEndpoint = endpoint
	}

	options := s3.Options{
		Region:       region,
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
		UsePathStyle: true,
	}
	if endpoint != "" {
		options.BaseEndpoint = aws.String(endpoint)
	}

	client := s3.New(options)

	return &S3Client{
		bucket:         cfg.Bucket,
		endpoint:       endpoint,
		publicEndpoint: publicEndpoint,
		client:         client,
	}, nil
}

// GetObject returns object.
func (s *S3Client) GetObject(ctx context.Context, key string) (*s3.GetObjectOutput, error) {
	input := &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}
	return s.client.GetObject(ctx, input)
}

// UploadObject handles upload object.
func (s *S3Client) UploadObject(ctx context.Context, fileName, contentType string, body io.Reader, size int64) (string, error) {
	key := buildObjectKey(fileName)
	var readSeeker io.ReadSeeker
	if rs, ok := body.(io.ReadSeeker); ok {
		readSeeker = rs
	} else {
		data, err := io.ReadAll(body)
		if err != nil {
			return "", err
		}
		readSeeker = bytes.NewReader(data)
		if size <= 0 {
			size = int64(len(data))
		}
	}
	input := &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        readSeeker,
		ContentType: aws.String(contentType),
	}
	if size > 0 {
		input.ContentLength = aws.Int64(size)
	}
	if _, err := s.client.PutObject(ctx, input); err != nil {
		return "", err
	}
	return s.publicURLForKey(key), nil
}

// publicURLForKey handles public u r l for key.
func (s *S3Client) publicURLForKey(key string) string {
	if s.publicEndpoint == "" {
		return fmt.Sprintf("https://%s.s3.amazonaws.com/%s", s.bucket, key)
	}

	endpoint := s.publicEndpoint
	if !strings.HasPrefix(endpoint, "http") {
		endpoint = "https://" + endpoint
	}
	u, err := url.Parse(endpoint)
	if err != nil {
		return fmt.Sprintf("%s/%s/%s", endpoint, s.bucket, key)
	}
	u.Path = path.Join(u.Path, s.bucket, key)
	return u.String()
}

// KeyFromURL handles key from u r l.
func (s *S3Client) KeyFromURL(rawURL string) (string, bool) {
	if s == nil || s.bucket == "" {
		return "", false
	}
	u, err := url.Parse(rawURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return "", false
	}
	host := strings.ToLower(strings.TrimSpace(u.Hostname()))
	if host == "" || !s.isConfiguredObjectHost(host) {
		return "", false
	}
	pathPart := u.Path
	if pathPart == "" {
		return "", false
	}
	needle := "/" + s.bucket + "/"
	if strings.HasPrefix(pathPart, needle) {
		key := strings.TrimPrefix(pathPart[len(needle):], "/")
		if key != "" {
			return key, true
		}
	}
	if strings.HasPrefix(host, strings.ToLower(s.bucket)+".") {
		key := strings.TrimPrefix(pathPart, "/")
		if key != "" {
			return key, true
		}
	}
	return "", false
}

// isConfiguredObjectHost reports whether a media URL belongs to the configured
// object store. Requiring an exact configured host prevents attacker-controlled
// URLs with a matching bucket path from being treated as trusted S3 objects.
func (s *S3Client) isConfiguredObjectHost(host string) bool {
	for _, rawEndpoint := range []string{s.endpoint, s.publicEndpoint} {
		endpoint, err := url.Parse(rawEndpoint)
		if err == nil && strings.EqualFold(endpoint.Hostname(), host) {
			return true
		}
	}
	return strings.EqualFold(host, s.bucket+".s3.amazonaws.com")
}

// buildObjectKey builds object key.
func buildObjectKey(fileName string) string {
	safeName := path.Base(strings.TrimSpace(fileName))
	safeName = unsafeObjectKeyCharacters.ReplaceAllString(safeName, "-")
	safeName = strings.Trim(safeName, ".-")
	if safeName == "" {
		safeName = "upload"
	}
	now := time.Now().UTC()
	return fmt.Sprintf("events/%d/%02d/%02d/%d-%s", now.Year(), now.Month(), now.Day(), now.UnixNano(), safeName)
}

// normalizeEndpoint normalizes endpoint.
func normalizeEndpoint(endpoint string, useSSL bool) string {
	if endpoint == "" {
		return ""
	}
	if strings.HasPrefix(endpoint, "http") {
		return endpoint
	}
	scheme := "https"
	if !useSSL {
		scheme = "http"
	}
	return scheme + "://" + endpoint
}
