package server

import "testing"

func TestRuntimeModeSupportIncludesHostWine(t *testing.T) {
	t.Parallel()

	for _, mode := range []string{RuntimeWineDocker, RuntimeWindowsSteamCMD, RuntimeHostWine} {
		if !IsRuntimeModeSupported(mode) {
			t.Fatalf("expected runtime mode %q to be supported", mode)
		}
	}
	if !IsRuntimeModeSupported(" host_wine ") {
		t.Fatal("expected runtime mode whitespace to be normalized")
	}
	for _, mode := range []string{"", "docker", "host-wine", "HOST_WINE"} {
		if IsRuntimeModeSupported(mode) {
			t.Fatalf("expected runtime mode %q to be rejected", mode)
		}
	}
}
