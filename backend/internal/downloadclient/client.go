package downloadclient

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const maxRedirects = 5

type Config struct {
	ProxyBases []string
	CacheDir   string
	Timeout    time.Duration
	Retries    int
}

type Request struct {
	URL         string
	Destination string
	SHA256      string
	MaxBytes    int64
	CacheKey    string
	Validate    func(string) error
}

type Result struct {
	SourceURL string
	SHA256    string
	Size      int64
	Cached    bool
}

type Attempt struct {
	URL  string
	Kind string
	Err  error
}

type Error struct {
	Attempts []Attempt
}

func (err *Error) Error() string {
	parts := make([]string, 0, len(err.Attempts))
	for _, attempt := range err.Attempts {
		parts = append(parts, fmt.Sprintf("%s (%s): %v", attempt.URL, attempt.Kind, attempt.Err))
	}
	return "all download sources failed: " + strings.Join(parts, "; ")
}

type resolver interface {
	LookupIPAddr(context.Context, string) ([]net.IPAddr, error)
}

type Client struct {
	cfg      Config
	resolver resolver
	http     *http.Client
}

func New(cfg Config) *Client {
	if cfg.Timeout <= 0 {
		cfg.Timeout = 5 * time.Minute
	}
	if cfg.Retries < 1 {
		cfg.Retries = 1
	}
	client := &Client{cfg: cfg, resolver: net.DefaultResolver}
	transport := &http.Transport{
		Proxy:                 nil,
		ForceAttemptHTTP2:     false,
		MaxIdleConns:          8,
		IdleConnTimeout:       30 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
		TLSNextProto:          map[string]func(string, *tls.Conn) http.RoundTripper{},
	}
	transport.DialContext = client.dialContext
	client.http = &http.Client{Transport: transport, Timeout: cfg.Timeout, CheckRedirect: client.checkRedirect}
	return client
}

func (client *Client) Download(ctx context.Context, request Request) (Result, error) {
	if err := validateRequest(request); err != nil {
		return Result{}, err
	}
	if result, ok := client.restoreCache(request); ok {
		return result, nil
	}
	var attempts []Attempt
	for _, candidate := range candidateURLs(request.URL, client.cfg.ProxyBases) {
		for retry := 0; retry < client.cfg.Retries; retry++ {
			result, err := client.downloadOnce(ctx, candidate, request)
			if err == nil {
				client.storeCache(request, result)
				return result, nil
			}
			attempts = append(attempts, Attempt{URL: candidate, Kind: classify(err), Err: err})
			if ctx.Err() != nil {
				return Result{}, ctx.Err()
			}
		}
	}
	return Result{}, &Error{Attempts: attempts}
}

func validateRequest(request Request) error {
	parsed, err := url.Parse(strings.TrimSpace(request.URL))
	if err != nil || !strings.EqualFold(parsed.Scheme, "https") || parsed.Hostname() == "" || parsed.User != nil {
		return errors.New("download URL must be public HTTPS without credentials")
	}
	if strings.TrimSpace(request.Destination) == "" || request.MaxBytes <= 0 {
		return errors.New("download destination and positive size limit are required")
	}
	if digest := strings.TrimSpace(request.SHA256); digest != "" {
		if len(digest) != 64 {
			return errors.New("SHA-256 must contain 64 hexadecimal characters")
		}
		if _, err := hex.DecodeString(digest); err != nil {
			return errors.New("SHA-256 must contain 64 hexadecimal characters")
		}
	}
	return nil
}

func candidateURLs(original string, proxyBases []string) []string {
	parsed, err := url.Parse(strings.TrimSpace(original))
	if err != nil || !isGitHubHost(parsed.Hostname()) {
		return []string{original}
	}
	result := make([]string, 0, len(proxyBases)+1)
	for _, base := range proxyBases {
		base = strings.TrimRight(strings.TrimSpace(base), "/")
		if base != "" {
			result = append(result, base+"/"+original)
		}
	}
	return append(result, original)
}

func isGitHubHost(host string) bool {
	host = strings.ToLower(strings.TrimSpace(host))
	return host == "github.com" || host == "api.github.com" || host == "raw.githubusercontent.com" || strings.HasSuffix(host, ".githubusercontent.com")
}

type downloadFailure struct {
	kind string
	err  error
}

func (failure downloadFailure) Error() string { return failure.err.Error() }
func (failure downloadFailure) Unwrap() error { return failure.err }
func classify(err error) string {
	var failure downloadFailure
	if errors.As(err, &failure) {
		return failure.kind
	}
	return "network"
}

func (client *Client) downloadOnce(ctx context.Context, source string, request Request) (Result, error) {
	parsed, err := url.Parse(source)
	if err != nil {
		return Result{}, downloadFailure{"request", err}
	}
	if err := client.validateURL(ctx, parsed); err != nil {
		return Result{}, downloadFailure{"security", err}
	}
	if err := os.MkdirAll(filepath.Dir(request.Destination), 0o755); err != nil {
		return Result{}, downloadFailure{"filesystem", err}
	}
	part := request.Destination + ".part"
	_ = os.Remove(part)
	file, err := os.OpenFile(part, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return Result{}, downloadFailure{"filesystem", err}
	}
	complete := false
	defer func() {
		_ = file.Close()
		if !complete {
			_ = os.Remove(part)
		}
	}()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
	if err != nil {
		return Result{}, downloadFailure{"request", err}
	}
	req.Header.Set("User-Agent", "PalPanel-DownloadClient/1")
	resp, err := client.http.Do(req)
	if err != nil {
		return Result{}, downloadFailure{"network", err}
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Result{}, downloadFailure{"http", fmt.Errorf("HTTP %d", resp.StatusCode)}
	}
	if resp.ContentLength > request.MaxBytes {
		return Result{}, downloadFailure{"size", fmt.Errorf("Content-Length exceeds %d bytes", request.MaxBytes)}
	}
	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(file, hasher), io.LimitReader(resp.Body, request.MaxBytes+1))
	if err != nil {
		return Result{}, downloadFailure{"network", err}
	}
	if written > request.MaxBytes {
		return Result{}, downloadFailure{"size", fmt.Errorf("download exceeds %d bytes", request.MaxBytes)}
	}
	digest := hex.EncodeToString(hasher.Sum(nil))
	if request.SHA256 != "" && !strings.EqualFold(digest, request.SHA256) {
		return Result{}, downloadFailure{"checksum", errors.New("SHA-256 mismatch")}
	}
	if err := file.Sync(); err != nil {
		return Result{}, downloadFailure{"filesystem", err}
	}
	if err := file.Close(); err != nil {
		return Result{}, downloadFailure{"filesystem", err}
	}
	if request.Validate != nil {
		if err := request.Validate(part); err != nil {
			return Result{}, downloadFailure{"content", err}
		}
	}
	_ = os.Remove(request.Destination)
	if err := os.Rename(part, request.Destination); err != nil {
		return Result{}, downloadFailure{"filesystem", err}
	}
	complete = true
	return Result{SourceURL: source, SHA256: digest, Size: written}, nil
}

func (client *Client) cachePath(request Request) string {
	if strings.TrimSpace(client.cfg.CacheDir) == "" {
		return ""
	}
	key := strings.TrimSpace(request.CacheKey)
	if key == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(key))
	return filepath.Join(client.cfg.CacheDir, hex.EncodeToString(sum[:]))
}

func (client *Client) restoreCache(request Request) (Result, bool) {
	cache := client.cachePath(request)
	if cache == "" {
		return Result{}, false
	}
	result, err := verifyFile(cache, request)
	if err != nil {
		_ = os.Remove(cache)
		return Result{}, false
	}
	if err := copyAtomic(cache, request.Destination); err != nil {
		return Result{}, false
	}
	result.SourceURL = "cache"
	result.Cached = true
	return result, true
}

func (client *Client) storeCache(request Request, result Result) {
	cache := client.cachePath(request)
	if cache == "" {
		return
	}
	_ = os.MkdirAll(filepath.Dir(cache), 0o700)
	_ = copyAtomic(request.Destination, cache)
}

func verifyFile(path string, request Request) (Result, error) {
	file, err := os.Open(path)
	if err != nil {
		return Result{}, err
	}
	hasher := sha256.New()
	size, err := io.Copy(hasher, io.LimitReader(file, request.MaxBytes+1))
	closeErr := file.Close()
	if err != nil {
		return Result{}, err
	}
	if closeErr != nil {
		return Result{}, closeErr
	}
	if size > request.MaxBytes {
		return Result{}, errors.New("cached file exceeds size limit")
	}
	digest := hex.EncodeToString(hasher.Sum(nil))
	if request.SHA256 != "" && !strings.EqualFold(digest, request.SHA256) {
		return Result{}, errors.New("cached SHA-256 mismatch")
	}
	if request.Validate != nil {
		if err := request.Validate(path); err != nil {
			return Result{}, err
		}
	}
	return Result{SHA256: digest, Size: size}, nil
}

func copyAtomic(source, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	part := destination + ".part"
	_ = os.Remove(part)
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	out, err := os.OpenFile(part, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		_ = in.Close()
		return err
	}
	_, copyErr := io.Copy(out, in)
	if copyErr == nil {
		copyErr = out.Sync()
	}
	closeOutErr := out.Close()
	closeInErr := in.Close()
	if copyErr != nil || closeOutErr != nil || closeInErr != nil {
		_ = os.Remove(part)
		return errors.Join(copyErr, closeOutErr, closeInErr)
	}
	_ = os.Remove(destination)
	return os.Rename(part, destination)
}

func ValidateZIP(path string) error {
	archive, err := zip.OpenReader(path)
	if err != nil {
		return fmt.Errorf("invalid ZIP archive: %w", err)
	}
	defer archive.Close()
	foundFile := false
	for _, entry := range archive.File {
		if err := validateArchivePath(entry.Name); err != nil {
			return err
		}
		if entry.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("ZIP archive contains a symbolic link: %s", entry.Name)
		}
		if !entry.FileInfo().IsDir() {
			foundFile = true
		}
	}
	if foundFile {
		return nil
	}
	return errors.New("ZIP archive contains no files")
}

func ValidateTarGzip(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	gz, err := gzip.NewReader(file)
	if err != nil {
		return fmt.Errorf("invalid gzip archive: %w", err)
	}
	defer gz.Close()
	reader := tar.NewReader(gz)
	foundFile := false
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("invalid tar archive: %w", err)
		}
		if err := validateArchivePath(header.Name); err != nil {
			return err
		}
		switch header.Typeflag {
		case tar.TypeReg, tar.TypeRegA:
			foundFile = true
		case tar.TypeDir:
		default:
			return fmt.Errorf("tar archive contains unsupported link or special entry: %s", header.Name)
		}
	}
	if !foundFile {
		return errors.New("tar archive contains no files")
	}
	return nil
}

func validateArchivePath(name string) error {
	cleaned := filepath.ToSlash(filepath.Clean(strings.TrimSpace(name)))
	if cleaned == "." || strings.HasPrefix(cleaned, "../") || cleaned == ".." || strings.HasPrefix(cleaned, "/") || filepath.IsAbs(name) {
		return fmt.Errorf("archive contains an unsafe path: %s", name)
	}
	return nil
}

func (client *Client) checkRedirect(request *http.Request, previous []*http.Request) error {
	if len(previous) >= maxRedirects {
		return errors.New("too many redirects")
	}
	return client.validateURL(request.Context(), request.URL)
}

func (client *Client) validateURL(ctx context.Context, parsed *url.URL) error {
	if parsed == nil || !strings.EqualFold(parsed.Scheme, "https") || parsed.User != nil || parsed.Hostname() == "" {
		return errors.New("redirect target must be public HTTPS without credentials")
	}
	if port := parsed.Port(); port != "" {
		value, err := strconv.Atoi(port)
		if err != nil || value < 1 || value > 65535 {
			return errors.New("download URL has an invalid port")
		}
	}
	addresses, err := client.lookup(ctx, parsed.Hostname())
	if err != nil {
		return err
	}
	for _, address := range addresses {
		if !publicAddress(address) {
			return fmt.Errorf("download host resolves to a non-public address: %s", address)
		}
	}
	return nil
}

func (client *Client) lookup(ctx context.Context, host string) ([]netip.Addr, error) {
	if address, err := netip.ParseAddr(host); err == nil {
		return []netip.Addr{address.Unmap()}, nil
	}
	items, err := client.resolver.LookupIPAddr(ctx, host)
	if err != nil || len(items) == 0 {
		return nil, errors.New("download host did not resolve")
	}
	result := make([]netip.Addr, 0, len(items))
	for _, item := range items {
		address, ok := netip.AddrFromSlice(item.IP)
		if !ok {
			return nil, errors.New("download host returned an invalid address")
		}
		result = append(result, address.Unmap())
	}
	return result, nil
}

func (client *Client) dialContext(ctx context.Context, _, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	addresses, err := client.lookup(ctx, host)
	if err != nil {
		return nil, err
	}
	dialer := net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}
	var last error
	for _, resolved := range addresses {
		if !publicAddress(resolved) {
			return nil, fmt.Errorf("download host resolves to a non-public address: %s", resolved)
		}
		connection, dialErr := dialer.DialContext(ctx, "tcp4", net.JoinHostPort(resolved.String(), port))
		if dialErr == nil {
			return connection, nil
		}
		last = dialErr
	}
	return nil, last
}

var reservedNetworks = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"), netip.MustParsePrefix("100.64.0.0/10"), netip.MustParsePrefix("192.0.0.0/24"),
	netip.MustParsePrefix("192.0.2.0/24"), netip.MustParsePrefix("198.18.0.0/15"), netip.MustParsePrefix("198.51.100.0/24"),
	netip.MustParsePrefix("203.0.113.0/24"), netip.MustParsePrefix("240.0.0.0/4"), netip.MustParsePrefix("64:ff9b::/96"),
	netip.MustParsePrefix("64:ff9b:1::/48"), netip.MustParsePrefix("100::/64"), netip.MustParsePrefix("2001::/23"),
	netip.MustParsePrefix("2001:db8::/32"), netip.MustParsePrefix("2002::/16"), netip.MustParsePrefix("3fff::/20"), netip.MustParsePrefix("5f00::/16"),
}

func publicAddress(address netip.Addr) bool {
	address = address.Unmap()
	if !address.IsValid() || !address.IsGlobalUnicast() || address.IsLoopback() || address.IsPrivate() || address.IsLinkLocalUnicast() || address.IsMulticast() {
		return false
	}
	for _, network := range reservedNetworks {
		if network.Contains(address) {
			return false
		}
	}
	return true
}
