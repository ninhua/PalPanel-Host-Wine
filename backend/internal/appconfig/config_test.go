package appconfig

import (
	"encoding/hex"
	"os"
	"testing"
)

func TestLoadRequiresAuthenticationByDefault(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if !cfg.RequireAuth {
		t.Fatal("expected authentication to be enabled by default")
	}
}

func TestLoadUsesOrderedGitHubDownloadFallbacks(t *testing.T) {
	t.Setenv("PALPANEL_GITHUB_PROXY_BASES", "")
	t.Setenv("PALPANEL_DOWNLOAD_TIMEOUT_SECONDS", "")
	t.Setenv("PALPANEL_DOWNLOAD_RETRIES", "")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.GitHubProxyBases) != 2 || cfg.GitHubProxyBases[0] != "https://v4.gh-proxy.org" || cfg.GitHubProxyBases[1] != "https://cdn.gh-proxy.org" {
		t.Fatalf("GitHubProxyBases = %#v", cfg.GitHubProxyBases)
	}
	if cfg.DownloadTimeoutSeconds != DefaultDownloadTimeoutSeconds || cfg.DownloadRetries != DefaultDownloadRetries {
		t.Fatalf("download policy = timeout %d, retries %d", cfg.DownloadTimeoutSeconds, cfg.DownloadRetries)
	}
}

func TestLoadRejectsUnsafeGitHubProxy(t *testing.T) {
	t.Setenv("PALPANEL_GITHUB_PROXY_BASES", "http://127.0.0.1:8080,https://cdn.example")
	if _, err := Load(); err == nil {
		t.Fatal("unsafe GitHub proxy was accepted")
	}
}

func TestLoadConfiguresPalDefenderReleaseSource(t *testing.T) {
	t.Setenv("PALPANEL_PALDEFENDER_RELEASE_API_BASE_URL", "https://releases.example/paldefender/")
	t.Setenv("PALPANEL_PALDEFENDER_DOWNLOAD_MAX_MB", "96")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.PalDefenderReleaseAPIBaseURL != "https://releases.example/paldefender" || cfg.PalDefenderDownloadMaxBytes != 96<<20 {
		t.Fatalf("PalDefender release config = %q, %d", cfg.PalDefenderReleaseAPIBaseURL, cfg.PalDefenderDownloadMaxBytes)
	}
}

func TestLoadSelectsExperimentalPalworldUE4SSChannel(t *testing.T) {
	t.Setenv("PALPANEL_UE4SS_RELEASE_CHANNEL", "experimental-palworld")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.UE4SSReleaseChannel != "experimental-palworld" || cfg.UE4SSExperimentalURL != DefaultUE4SSExperimentalURL || cfg.UE4SSExperimentalSHA256 != DefaultUE4SSExperimentalSHA256 {
		t.Fatalf("experimental UE4SS config = channel %q, URL %q, SHA %q", cfg.UE4SSReleaseChannel, cfg.UE4SSExperimentalURL, cfg.UE4SSExperimentalSHA256)
	}
}

func TestLoadAllowsExplicitDevNoAuth(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("STEAM_WEB_API_KEY", "steam-key")
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("PALPANEL_DATA_DIR", cwd)
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.RequireAuth {
		t.Fatal("expected auth to be disabled")
	}
	if cfg.SteamWebAPIKey != "steam-key" {
		t.Fatalf("SteamWebAPIKey = %q", cfg.SteamWebAPIKey)
	}
	if cfg.SteamWebAPIKeySource != "environment" {
		t.Fatalf("SteamWebAPIKeySource = %q", cfg.SteamWebAPIKeySource)
	}
	if cfg.WorkshopAppID != "1623730" {
		t.Fatalf("WorkshopAppID = %q", cfg.WorkshopAppID)
	}
	if cfg.PalDefenderRESTBaseURL != "http://127.0.0.1:17993" {
		t.Fatalf("PalDefenderRESTBaseURL = %q", cfg.PalDefenderRESTBaseURL)
	}
	if cfg.PalDefenderRESTPort != 17993 {
		t.Fatalf("PalDefenderRESTPort = %d", cfg.PalDefenderRESTPort)
	}
	if cfg.RCONPort != DefaultRCONPort {
		t.Fatalf("RCONPort = %d", cfg.RCONPort)
	}
	if cfg.EffectiveRCONHost() != "127.0.0.1" {
		t.Fatalf("RCONHost = %q", cfg.EffectiveRCONHost())
	}
}

func TestLoadAllowsContainerRCONHost(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("PALPANEL_RCON_HOST", "palworld-server")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.EffectiveRCONHost() != "palworld-server" {
		t.Fatalf("RCONHost = %q", cfg.EffectiveRCONHost())
	}
}

func TestLoadUsesPalDefenderRESTOverrides(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("PALPANEL_PALDEFENDER_REST_BASE_URL", "http://10.0.0.4:28080/")
	t.Setenv("PALPANEL_PALDEFENDER_REST_PORT", "28080")
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("PALPANEL_DATA_DIR", cwd)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.PalDefenderRESTBaseURL != "http://10.0.0.4:28080/" {
		t.Fatalf("PalDefenderRESTBaseURL = %q", cfg.PalDefenderRESTBaseURL)
	}
	if cfg.EffectivePalDefenderRESTBaseURL() != "http://10.0.0.4:28080" {
		t.Fatalf("EffectivePalDefenderRESTBaseURL = %q", cfg.EffectivePalDefenderRESTBaseURL())
	}
	if cfg.PalDefenderRESTPort != 28080 {
		t.Fatalf("PalDefenderRESTPort = %d", cfg.PalDefenderRESTPort)
	}
}

func TestLoadDerivesPalworldRESTURLFromConfiguredPort(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("PALPANEL_REST_PORT", "18212")
	t.Setenv("PALWORLD_REST_BASE_URL", "")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.RESTPort != 18212 || cfg.PalworldRESTBaseURL != "http://127.0.0.1:18212/v1/api" {
		t.Fatalf("REST configuration = port %d, base URL %q", cfg.RESTPort, cfg.PalworldRESTBaseURL)
	}
}

func TestLoadUsesBundledSteamWebAPIKeyWhenEnvUnset(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("STEAM_WEB_API_KEY", "")
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("PALPANEL_DATA_DIR", cwd)
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.SteamWebAPIKeySource != "bundled" || cfg.SteamWebAPIKeySourceName() != "bundled" {
		t.Fatalf("SteamWebAPIKeySource = %q", cfg.SteamWebAPIKeySource)
	}
	if !cfg.SteamWebAPIKeyConfigured() || len(cfg.EffectiveSteamWebAPIKey()) != 32 {
		t.Fatal("bundled Steam Web API key should be configured")
	}
	if _, err := hex.DecodeString(cfg.EffectiveSteamWebAPIKey()); err != nil {
		t.Fatalf("bundled Steam Web API key is not hexadecimal: %v", err)
	}
}

func TestLoadUsesProductionNetworkAndProviderDefaults(t *testing.T) {
	t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
	t.Setenv("PALPANEL_LISTEN_ADDR", "")
	t.Setenv("PALPANEL_STEAM_API_BASE_URL", "")
	t.Setenv("PALPANEL_STEAM_API_TIMEOUT_SECONDS", "")
	t.Setenv("PALPANEL_AI_TRANSLATION_TIMEOUT_SECONDS", "")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ListenAddr != "127.0.0.1:8080" {
		t.Fatalf("ListenAddr = %q", cfg.ListenAddr)
	}
	if cfg.SteamAPIBaseURL != DefaultSteamAPIBaseURL || cfg.SteamAPITimeoutSeconds != 15 {
		t.Fatalf("Steam defaults = %q, %d", cfg.SteamAPIBaseURL, cfg.SteamAPITimeoutSeconds)
	}
	if cfg.AITranslationTimeoutSeconds != 90 {
		t.Fatalf("AITranslationTimeoutSeconds = %d", cfg.AITranslationTimeoutSeconds)
	}
	if cfg.MonitorRetentionDays != DefaultMonitorRetentionDays {
		t.Fatalf("MonitorRetentionDays = %d", cfg.MonitorRetentionDays)
	}
}

func TestLoadRejectsInvalidScalarConfiguration(t *testing.T) {
	tests := map[string]string{
		"PALPANEL_REQUIRE_AUTH":                   "sometimes",
		"PALPANEL_STEAM_API_TIMEOUT_SECONDS":      "soon",
		"PALPANEL_AI_TRANSLATION_TIMEOUT_SECONDS": "0",
		"PALPANEL_RCON_PORT":                      "70000",
		"PALPANEL_LISTEN_ADDR":                    "127.0.0.1:not-a-port",
		"PALPANEL_MONITOR_RETENTION_DAYS":         "-1",
		"PALPANEL_RCON_HOST":                      "bad host:25575",
	}
	for name, value := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("PALPANEL_REQUIRE_AUTH", "false")
			t.Setenv(name, value)
			if _, err := Load(); err == nil {
				t.Fatalf("expected %s=%q to fail", name, value)
			}
		})
	}
}
