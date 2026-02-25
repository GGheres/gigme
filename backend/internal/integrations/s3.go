package integrations

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/url"
	"path"
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
	presign        *s3.PresignClient
	publicPresign  *s3.PresignClient
}

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
	presign := s3.NewPresignClient(client)
	publicPresign := presign
	if publicEndpoint != "" && publicEndpoint != endpoint {
		publicOptions := options
		publicOptions.BaseEndpoint = aws.String(publicEndpoint)
		publicClient := s3.New(publicOptions)
		publicPresign = s3.NewPresignClient(publicClient)
	}

	return &S3Client{
		bucket:         cfg.Bucket,
		endpoint:       endpoint,
		publicEndpoint: publicEndpoint,
		client:         client,
		presign:        presign,
		publicPresign:  publicPresign,
	}, nil
}

// PresignPutObject handles presign put object.
func (s *S3Client) PresignPutObject(ctx context.Context, fileName, contentType string) (string, string, error) {
	key := buildObjectKey(fileName)
	input := &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		ContentType: aws.String(contentType),
	}

	resp, err := s.publicPresign.PresignPutObject(ctx, input, func(opts *s3.PresignOptions) {
		opts.Expires = 15 * time.Minute
	})
	if err != nil {
		return "", "", err
	}

	return resp.URL, s.publicURLForKey(key), nil
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
	if err != nil {
		return "", false
	}
	pathPart := u.Path
	if pathPart == "" {
		return "", false
	}
	needle := "/" + s.bucket + "/"
	if idx := strings.Index(pathPart, needle); idx >= 0 {
		key := strings.TrimPrefix(pathPart[idx+len(needle):], "/")
		if key != "" {
			return key, true
		}
	}
	if host := u.Hostname(); strings.HasPrefix(host, s.bucket+".") {
		key := strings.TrimPrefix(pathPart, "/")
		if key != "" {
			return key, true
		}
	}
	return "", false
}

// buildObjectKey builds object key.
func buildObjectKey(fileName string) string {
	safeName := strings.ReplaceAll(fileName, " ", "-")
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
