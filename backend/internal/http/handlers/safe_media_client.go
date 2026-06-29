package handlers

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const maxMediaBytes int64 = 5 * 1024 * 1024

var safeMediaHTTPClient = newSafeMediaHTTPClient()

// newSafeMediaHTTPClient builds the only HTTP client used for remote event
// media. Its dialer validates every resolved address, so DNS rebinding and
// redirects cannot reach loopback, private, or link-local services.
func newSafeMediaHTTPClient() *http.Client {
	transport := &http.Transport{
		DialContext:            safeMediaDialContext,
		ForceAttemptHTTP2:      true,
		MaxIdleConns:           20,
		MaxIdleConnsPerHost:    2,
		IdleConnTimeout:        30 * time.Second,
		TLSHandshakeTimeout:    3 * time.Second,
		ResponseHeaderTimeout:  4 * time.Second,
		MaxResponseHeaderBytes: 64 * 1024,
		ExpectContinueTimeout:  time.Second,
	}
	return &http.Client{
		Timeout:   5 * time.Second,
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 3 {
				return fmt.Errorf("too many media redirects")
			}
			return validateRemoteMediaURL(req.URL)
		},
	}
}

// safeMediaDialContext resolves the requested host and dials only globally
// routable addresses. If DNS returns any prohibited address, the whole host is
// rejected instead of selecting a potentially attacker-controlled alternative.
func safeMediaDialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, fmt.Errorf("invalid media address: %w", err)
	}
	addresses, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, fmt.Errorf("resolve media host: %w", err)
	}
	if len(addresses) == 0 {
		return nil, fmt.Errorf("media host has no addresses")
	}
	for _, address := range addresses {
		if isDisallowedOutboundIP(address.IP) {
			return nil, fmt.Errorf("media host resolves to a prohibited address")
		}
	}

	dialer := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 30 * time.Second}
	var lastErr error
	for _, resolved := range addresses {
		connection, dialErr := dialer.DialContext(
			ctx,
			network,
			net.JoinHostPort(resolved.IP.String(), port),
		)
		if dialErr == nil {
			return connection, nil
		}
		lastErr = dialErr
	}
	return nil, fmt.Errorf("dial media host: %w", lastErr)
}

// validateRemoteMediaURL accepts only ordinary HTTP(S) URLs without embedded
// credentials. Address safety is enforced later by safeMediaDialContext.
func validateRemoteMediaURL(target *url.URL) error {
	if target == nil {
		return fmt.Errorf("media url is required")
	}
	if target.Scheme != "http" && target.Scheme != "https" {
		return fmt.Errorf("unsupported media url scheme")
	}
	if strings.TrimSpace(target.Hostname()) == "" {
		return fmt.Errorf("media url host is required")
	}
	if target.User != nil {
		return fmt.Errorf("media url credentials are not allowed")
	}
	return nil
}

// isDisallowedOutboundIP reports whether an address is unsafe for a
// server-side fetch. Private, loopback, link-local, multicast, and unspecified
// ranges are never valid event-media origins.
func isDisallowedOutboundIP(ip net.IP) bool {
	return ip == nil ||
		!ip.IsGlobalUnicast() ||
		ip.IsPrivate() ||
		ip.IsLoopback() ||
		ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() ||
		ip.IsUnspecified() ||
		ip.IsMulticast()
}
