package mods

import (
	"context"
	"time"

	"palpanel/internal/appconfig"
	"palpanel/internal/downloadclient"
)

// safeDownloader adapts the shared hardened client to the Mod importer. GitHub
// URLs use the configured proxy chain; other public HTTPS URLs remain direct.
type safeDownloader struct {
	client interface {
		Download(context.Context, downloadclient.Request) (downloadclient.Result, error)
	}
}

func newSafeDownloader(cfg appconfig.Config) *safeDownloader {
	return &safeDownloader{client: downloadclient.New(downloadclient.Config{
		ProxyBases: cfg.GitHubProxyBases,
		CacheDir:   cfg.DownloadCacheDir,
		Timeout:    time.Duration(cfg.DownloadTimeoutSeconds) * time.Second,
		Retries:    cfg.DownloadRetries,
	})}
}

func (downloader *safeDownloader) Download(ctx context.Context, rawURL, destination string, limit int64, cache bool, validate func(string) error) (int64, error) {
	cacheKey := ""
	if cache {
		cacheKey = rawURL
	}
	result, err := downloader.client.Download(ctx, downloadclient.Request{
		URL:         rawURL,
		Destination: destination,
		MaxBytes:    limit,
		CacheKey:    cacheKey,
		Validate:    validate,
	})
	if err != nil {
		return 0, err
	}
	return result.Size, nil
}
