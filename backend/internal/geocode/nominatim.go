package geocode

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const defaultEndpoint = "https://nominatim.openstreetmap.org/search"
const defaultUserAgent = "GigmeAdminGeocoder/1.0"

// Config represents config.
type Config struct {
	Endpoint string
	Timeout  time.Duration
}

// Client represents client.
type Client struct {
	endpoint string
	client   *http.Client
}

// Result represents result.
type Result struct {
	DisplayName string  `json:"displayName"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
}

// nominatimItem represents nominatim item.
type nominatimItem struct {
	DisplayName string `json:"display_name"`
	Lat         string `json:"lat"`
	Lon         string `json:"lon"`
}

// NewClient creates client.
func NewClient(cfg Config) *Client {
	endpoint := strings.TrimSpace(cfg.Endpoint)
	if endpoint == "" {
		endpoint = defaultEndpoint
	}
	timeout := cfg.Timeout
	if timeout <= 0 {
		timeout = 6 * time.Second
	}
	return &Client{
		endpoint: endpoint,
		client: &http.Client{
			Timeout: timeout,
		},
	}
}

// Search handles internal search behavior.
func (c *Client) Search(ctx context.Context, query string, limit int) ([]Result, error) {
	if c == nil {
		return nil, fmt.Errorf("geocoder is not configured")
	}
	q := strings.TrimSpace(query)
	if q == "" {
		return nil, fmt.Errorf("query is empty")
	}
	if limit <= 0 {
		limit = 1
	}
	if limit > 5 {
		limit = 5
	}

	values := url.Values{}
	values.Set("q", q)
	values.Set("format", "jsonv2")
	values.Set("limit", strconv.Itoa(limit))
	values.Set("addressdetails", "1")
	values.Set("accept-language", "en,ru")

	reqURL := c.endpoint + "?" + values.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", defaultUserAgent)
	req.Header.Set("Accept", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf("geocoder status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var payload []nominatimItem
	if err := json.NewDecoder(io.LimitReader(resp.Body, 2<<20)).Decode(&payload); err != nil {
		return nil, err
	}

	out := make([]Result, 0, len(payload))
	for _, item := range payload {
		lat, err := strconv.ParseFloat(strings.TrimSpace(item.Lat), 64)
		if err != nil {
			continue
		}
		lng, err := strconv.ParseFloat(strings.TrimSpace(item.Lon), 64)
		if err != nil {
			continue
		}
		out = append(out, Result{
			DisplayName: strings.TrimSpace(item.DisplayName),
			Lat:         lat,
			Lng:         lng,
		})
	}
	return out, nil
}
