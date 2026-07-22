package downloadclient

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

type publicResolver struct{}

func (publicResolver) LookupIPAddr(context.Context, string) ([]net.IPAddr, error) {
	return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}, nil
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) { return fn(request) }

func testClient(t *testing.T, handler roundTripFunc) *Client {
	t.Helper()
	client := New(Config{
		ProxyBases: []string{"https://v4.gh-proxy.org", "https://cdn.gh-proxy.org"},
		CacheDir:   t.TempDir(),
		Timeout:    time.Second,
		Retries:    1,
	})
	client.resolver = publicResolver{}
	client.http = &http.Client{Transport: handler, Timeout: time.Second, CheckRedirect: client.checkRedirect}
	return client
}

func response(status int, body string) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header), ContentLength: int64(len(body))}
}

func TestDownloadUsesProxyFallbackThenOriginal(t *testing.T) {
	var called []string
	client := testClient(t, func(request *http.Request) (*http.Response, error) {
		called = append(called, request.URL.String())
		if strings.HasPrefix(request.URL.Host, "v4.") || strings.HasPrefix(request.URL.Host, "cdn.") {
			return response(http.StatusBadGateway, "proxy failed"), nil
		}
		return response(http.StatusOK, "payload"), nil
	})
	destination := filepath.Join(t.TempDir(), "asset.bin")
	result, err := client.Download(context.Background(), Request{URL: "https://github.com/owner/repo/releases/download/v1/a.zip", Destination: destination, MaxBytes: 1024})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"https://v4.gh-proxy.org/https://github.com/owner/repo/releases/download/v1/a.zip",
		"https://cdn.gh-proxy.org/https://github.com/owner/repo/releases/download/v1/a.zip",
		"https://github.com/owner/repo/releases/download/v1/a.zip",
	}
	if !reflect.DeepEqual(called, want) {
		t.Fatalf("calls = %#v, want %#v", called, want)
	}
	if result.SourceURL != want[2] {
		t.Fatalf("source = %q", result.SourceURL)
	}
}

func TestDownloadPrimaryProxySuccess(t *testing.T) {
	called := 0
	client := testClient(t, func(request *http.Request) (*http.Response, error) {
		called++
		return response(http.StatusOK, "payload"), nil
	})
	_, err := client.Download(context.Background(), Request{URL: "https://api.github.com/repos/o/r/releases", Destination: filepath.Join(t.TempDir(), "metadata.json"), MaxBytes: 1024})
	if err != nil {
		t.Fatal(err)
	}
	if called != 1 {
		t.Fatalf("calls = %d, want 1", called)
	}
}

func TestNonGitHubURLIsNeverProxied(t *testing.T) {
	var called string
	client := testClient(t, func(request *http.Request) (*http.Response, error) {
		called = request.URL.String()
		return response(http.StatusOK, "steam"), nil
	})
	original := "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
	_, err := client.Download(context.Background(), Request{URL: original, Destination: filepath.Join(t.TempDir(), "steamcmd.zip"), MaxBytes: 1024})
	if err != nil {
		t.Fatal(err)
	}
	if called != original {
		t.Fatalf("called %q", called)
	}
}

func TestAllSourcesReturnStructuredErrorAndRemovePart(t *testing.T) {
	client := testClient(t, func(request *http.Request) (*http.Response, error) {
		return response(http.StatusServiceUnavailable, "no"), nil
	})
	destination := filepath.Join(t.TempDir(), "asset")
	_, err := client.Download(context.Background(), Request{URL: "https://github.com/o/r/a", Destination: destination, MaxBytes: 1024})
	structured, ok := err.(*Error)
	if !ok || len(structured.Attempts) != 3 {
		t.Fatalf("error = %#v", err)
	}
	if _, err := os.Stat(destination + ".part"); !os.IsNotExist(err) {
		t.Fatalf("partial file remains: %v", err)
	}
}

func TestInvalidCacheIsRemovedAndDownloadedAgain(t *testing.T) {
	payload := "correct"
	sum := sha256.Sum256([]byte(payload))
	client := testClient(t, func(request *http.Request) (*http.Response, error) {
		return response(http.StatusOK, payload), nil
	})
	request := Request{URL: "https://github.com/o/r/a", Destination: filepath.Join(t.TempDir(), "asset"), CacheKey: "asset-v1", MaxBytes: 1024, SHA256: hex.EncodeToString(sum[:])}
	cache := client.cachePath(request)
	if err := os.WriteFile(cache, []byte("corrupt"), 0o600); err != nil {
		t.Fatal(err)
	}
	result, err := client.Download(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	if result.Cached {
		t.Fatal("corrupt cache was used")
	}
	data, err := os.ReadFile(cache)
	if err != nil || string(data) != payload {
		t.Fatalf("cache = %q, err = %v", data, err)
	}
}

func TestContentAndSizeFailuresCleanPart(t *testing.T) {
	for _, tc := range []struct {
		name     string
		body     string
		maxBytes int64
		validate func(string) error
	}{
		{name: "oversized", body: "too-large", maxBytes: 3},
		{name: "html instead of zip", body: "<html>error</html>", maxBytes: 1024, validate: ValidateZIP},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := testClient(t, func(request *http.Request) (*http.Response, error) { return response(http.StatusOK, tc.body), nil })
			destination := filepath.Join(t.TempDir(), "asset")
			_, err := client.Download(context.Background(), Request{URL: "https://example.com/a", Destination: destination, MaxBytes: tc.maxBytes, Validate: tc.validate})
			if err == nil {
				t.Fatal("expected failure")
			}
			if _, err := os.Stat(destination + ".part"); !os.IsNotExist(err) {
				t.Fatalf("partial file remains: %v", err)
			}
		})
	}
}

func TestRedirectSecurityRejectsPrivateAndCredentials(t *testing.T) {
	client := New(Config{})
	private, _ := url.Parse("https://127.0.0.1/secret")
	if err := client.checkRedirect(&http.Request{URL: private}, nil); err == nil {
		t.Fatal("private redirect accepted")
	}
	credentials, _ := url.Parse("https://user:pass@example.com/secret")
	if err := client.checkRedirect(&http.Request{URL: credentials}, nil); err == nil {
		t.Fatal("credential redirect accepted")
	}
}

func TestValidateZIPRejectsTraversal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "unsafe.zip")
	var buffer bytes.Buffer
	archive := zip.NewWriter(&buffer)
	entry, err := archive.Create("../escape")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = entry.Write([]byte("bad"))
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buffer.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ValidateZIP(path); err == nil {
		t.Fatal("unsafe path accepted")
	}
}
