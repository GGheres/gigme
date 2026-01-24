package integrations

import (
	"context"
	"fmt"
	"net/url"
	"path"
	"strings"
	"time"

	"gigme/backend/internal/config"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type S3Client struct {
	bucket   string
	endpoint string
	client   *s3.Client
	presign  *s3.PresignClient
}

func NewS3(ctx context.Context, cfg config.S3Config) (*S3Client, error) {
	if cfg.Bucket == "" {
		return nil, fmt.Errorf("S3_BUCKET is required")
	}

	region := cfg.Region
	if region == "" {
		region = "us-east-1"
	}

	endpoint := cfg.Endpoint
	if endpoint != "" {
		if !strings.HasPrefix(endpoint, "http") {
			scheme := "https"
			if !cfg.UseSSL {
				scheme = "http"
			}
			endpoint = scheme + "://" + endpoint
		}
	}

	options := s3.Options{
		Region:      region,
		Credentials: credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
		UsePathStyle:     true,
	}
	if endpoint != "" {
		options.BaseEndpoint = aws.String(endpoint)
	}

	client := s3.New(options)

	return &S3Client{
		bucket:   cfg.Bucket,
		endpoint: endpoint,
		client:   client,
		presign:  s3.NewPresignClient(client),
	}, nil
}

func (s *S3Client) PresignPutObject(ctx context.Context, fileName, contentType string) (string, string, error) {
	key := buildObjectKey(fileName)
	input := &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		ContentType: aws.String(contentType),
	}

	resp, err := s.presign.PresignPutObject(ctx, input, func(opts *s3.PresignOptions) {
		opts.Expires = 15 * time.Minute
	})
	if err != nil {
		return "", "", err
	}

	return resp.URL, s.publicURLForKey(key), nil
}

func (s *S3Client) publicURLForKey(key string) string {
	if s.endpoint == "" {
		return fmt.Sprintf("https://%s.s3.amazonaws.com/%s", s.bucket, key)
	}

	endpoint := s.endpoint
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

func buildObjectKey(fileName string) string {
	safeName := strings.ReplaceAll(fileName, " ", "-")
	now := time.Now().UTC()
	return fmt.Sprintf("events/%d/%02d/%02d/%d-%s", now.Year(), now.Month(), now.Day(), now.UnixNano(), safeName)
}
