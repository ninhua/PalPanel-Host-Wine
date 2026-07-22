//go:build linux

package steamcmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"palpanel/internal/appconfig"
)

func TestSteamCMDCommandRunnerUsesIndependentWinePrefix(t *testing.T) {
	root := t.TempDir()
	fakeWine := filepath.Join(root, "wine64")
	if err := os.WriteFile(fakeWine, []byte("#!/bin/sh\nprintf '%s|%s\\n' \"$WINEPREFIX\" \"$*\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := appconfig.Config{
		DataDir:               filepath.Join(root, "data"),
		WineBinary:            fakeWine,
		SteamCMDWinePrefixDir: filepath.Join(root, "wineprefix-steamcmd"),
	}
	runner := steamCMDCommandRunner(cfg, "linux")
	out, err := runner(t.Context(), filepath.Join(root, "steamcmd.exe"), root, "+login", "anonymous", "+quit")
	if err != nil {
		t.Fatal(err)
	}
	text := string(out)
	if !strings.Contains(text, cfg.SteamCMDWinePrefixDir+"|") || !strings.Contains(text, "+login anonymous +quit") {
		t.Fatalf("Wine invocation = %q", text)
	}
}
