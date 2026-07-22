//go:build linux

package server

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRecoverPreparedSaveTransactionBacksUpAndReplaces(t *testing.T) {
	root := t.TempDir()
	world := filepath.Join(root, "0", "world")
	backupRoot := filepath.Join(t.TempDir(), "backups")
	target := filepath.Join(world, "Players", "player.sav")
	writeSaveFixture(t, target, "old")
	writeSaveFixture(t, target+".new_tmp", "replacement")
	writePreparedManifest(t, world, preparedSaveTransaction{
		State: "Prepared",
		Entries: []preparedSaveEntry{{
			RelativePath: filepath.Join("Players", "player.sav"),
			ExpectedSize: int64(len("replacement")),
		}},
	})

	if err := recoverPreparedSaveTransactions(root, backupRoot); err != nil {
		t.Fatal(err)
	}
	assertSaveBody(t, target, "replacement")
	if _, err := os.Stat(filepath.Join(world, preparedSaveManifest)); !os.IsNotExist(err) {
		t.Fatalf("manifest remains after recovery: %v", err)
	}
	backups, err := filepath.Glob(filepath.Join(backupRoot, "world", "*", "Players", "player.sav"))
	if err != nil || len(backups) != 1 {
		t.Fatalf("recovery backups = %v, %v", backups, err)
	}
	assertSaveBody(t, backups[0], "old")
}

func TestRecoverPreparedSaveTransactionRejectsIncompleteTemporary(t *testing.T) {
	root := t.TempDir()
	world := filepath.Join(root, "0", "world")
	target := filepath.Join(world, "Level.sav")
	writeSaveFixture(t, target, "old")
	writeSaveFixture(t, target+".new_tmp", "short")
	writePreparedManifest(t, world, preparedSaveTransaction{
		State:   "Prepared",
		Entries: []preparedSaveEntry{{RelativePath: "Level.sav", ExpectedSize: 100}},
	})

	if err := recoverPreparedSaveTransactions(root, filepath.Join(t.TempDir(), "backups")); err == nil {
		t.Fatal("expected incomplete Prepared transaction to be rejected")
	}
	assertSaveBody(t, target, "old")
}

func TestRecoverPreparedSaveTransactionRejectsPathEscape(t *testing.T) {
	root := t.TempDir()
	world := filepath.Join(root, "0", "world")
	writeSaveFixture(t, filepath.Join(root, "escape.sav.new_tmp"), "bad")
	writePreparedManifest(t, world, preparedSaveTransaction{
		State:   "Prepared",
		Entries: []preparedSaveEntry{{RelativePath: "../../escape.sav", ExpectedSize: 3}},
	})

	if err := recoverPreparedSaveTransactions(root, filepath.Join(t.TempDir(), "backups")); err == nil {
		t.Fatal("expected escaping Prepared path to be rejected")
	}
}

func TestProbeLinuxAtomicReplace(t *testing.T) {
	root := t.TempDir()
	if err := probeLinuxAtomicReplace(root); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".palpanel-linux-replace-probe", ".palpanel-linux-replace-probe.new"} {
		if _, err := os.Stat(filepath.Join(root, name)); !os.IsNotExist(err) {
			t.Fatalf("probe artifact remains: %s", name)
		}
	}
}

func TestEnsureAuthoritativeSaveRootRejectsSymlink(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	if err := os.Mkdir(target, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "SaveGames")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := ensureAuthoritativeSaveRoot(link); err == nil {
		t.Fatal("expected SaveGames symlink to be rejected")
	}
}

func writePreparedManifest(t *testing.T, world string, transaction preparedSaveTransaction) {
	t.Helper()
	if err := os.MkdirAll(world, 0o755); err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(transaction)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(world, preparedSaveManifest), body, 0o600); err != nil {
		t.Fatal(err)
	}
}

func writeSaveFixture(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

func assertSaveBody(t *testing.T, path, expected string) {
	t.Helper()
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != expected {
		t.Fatalf("%s = %q, want %q", path, body, expected)
	}
}
