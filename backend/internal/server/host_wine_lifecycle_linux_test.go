//go:build linux

package server

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHostWineLifecycleUsesDedicatedSessionAndRecoversStatus(t *testing.T) {
	manager, cleanup := newOperationsManager(t)
	defer cleanup()

	fakeWine := filepath.Join(t.TempDir(), "wine64")
	script := `#!/bin/bash
set -eu
if [[ "${1:-}" == "cmd.exe" ]]; then
  batch="${4#Z:}"
  batch="/${batch//\\//}"
  destination="$(sed -n 's/^set "DEST=\(.*\)"$/\1/p' "$batch")"
  destination="/${destination#Z:\\}"
  destination="${destination//\\//}"
  printf 'new-24\r\n' > "$destination"
  exit 0
fi
server_dir="$(dirname "$1")"
shipping="$server_dir/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe"
exec -a "$shipping" sleep 120
`
	if err := os.WriteFile(fakeWine, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	manager.cfg.WineBinary = fakeWine
	if err := os.MkdirAll(filepath.Dir(manager.cfg.PalServerShippingPath()), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manager.cfg.PalServerShippingPath(), []byte("fixture"), 0o644); err != nil {
		t.Fatal(err)
	}
	ctx := t.Context()
	if err := manager.SetRuntimeMode(ctx, RuntimeHostWine); err != nil {
		t.Fatal(err)
	}
	if err := manager.Start(ctx); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = manager.stopHostWine(t.Context()) })
	status, err := manager.Status(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !status.Container.Exists || status.Container.Status != "running" {
		t.Fatalf("status after start = %#v", status.Container)
	}
	record, ok, err := manager.loadHostWineProcess(ctx)
	if err != nil || !ok {
		t.Fatalf("load process identity = %#v, %v, %v", record, ok, err)
	}
	if record.PID <= 0 || record.ProcessGroupID <= 0 || record.StartTimeTicks == 0 {
		t.Fatalf("incomplete process identity: %#v", record)
	}
	if err := manager.Stop(ctx); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	status, err = manager.Status(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if status.Container.Exists || status.Container.Status != "missing" {
		t.Fatalf("status after stop = %#v", status.Container)
	}
}
