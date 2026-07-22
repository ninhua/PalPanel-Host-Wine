//go:build linux

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const preparedSaveManifest = ".atomic_save_update_manifest_world.json"

type preparedSaveTransaction struct {
	State   string              `json:"State"`
	Entries []preparedSaveEntry `json:"Entries"`
}

type preparedSaveEntry struct {
	RelativePath string `json:"RelativePath"`
	ExpectedSize int64  `json:"ExpectedSize"`
}

type checkedSaveEntry struct {
	target    string
	temporary string
	backup    string
	existed   bool
}

func (m Manager) preflightHostWineSaveGames(ctx context.Context) error {
	root := filepath.Join(m.cfg.ServerDirectory(), "Pal", "Saved", "SaveGames")
	if err := ensureAuthoritativeSaveRoot(root); err != nil {
		return err
	}
	if err := recoverPreparedSaveTransactions(root, filepath.Join(m.cfg.BackupsDir, "save-recovery")); err != nil {
		return err
	}
	if err := probeLinuxAtomicReplace(root); err != nil {
		return err
	}
	if err := probeWineAtomicReplace(ctx, m.cfg.WineBinary, m.cfg.WinePrefixDir, root); err != nil {
		return err
	}
	return nil
}

func ensureAuthoritativeSaveRoot(root string) error {
	info, err := os.Lstat(root)
	if os.IsNotExist(err) {
		if err := os.MkdirAll(root, 0o755); err != nil {
			return fmt.Errorf("create authoritative SaveGames directory: %w", err)
		}
		info, err = os.Lstat(root)
	}
	if err != nil {
		return fmt.Errorf("inspect authoritative SaveGames directory: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("authoritative SaveGames path must be a real directory, not a symlink or mount mirror: %s", root)
	}
	probe := filepath.Join(root, ".palpanel-permission-probe")
	if err := os.WriteFile(probe, []byte("ok"), 0o600); err != nil {
		return fmt.Errorf("SaveGames is not writable: %w", err)
	}
	if err := os.Remove(probe); err != nil {
		return fmt.Errorf("clean SaveGames permission probe: %w", err)
	}
	return nil
}

func recoverPreparedSaveTransactions(root, backupRoot string) error {
	var manifests []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return fmt.Errorf("SaveGames contains a symlink: %s", path)
		}
		if !entry.IsDir() && entry.Name() == preparedSaveManifest {
			manifests = append(manifests, path)
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("scan Prepared save transactions: %w", err)
	}
	for _, manifest := range manifests {
		if err := recoverPreparedSaveTransaction(root, manifest, backupRoot); err != nil {
			return err
		}
	}
	return nil
}

func recoverPreparedSaveTransaction(root, manifest, backupRoot string) error {
	body, err := os.ReadFile(manifest)
	if err != nil {
		return fmt.Errorf("read Prepared save manifest %s: %w", manifest, err)
	}
	var transaction preparedSaveTransaction
	if err := json.Unmarshal(body, &transaction); err != nil {
		return fmt.Errorf("parse Prepared save manifest %s: %w", manifest, err)
	}
	if transaction.State != "Prepared" || len(transaction.Entries) == 0 {
		return fmt.Errorf("invalid Prepared save manifest: %s", manifest)
	}
	world := filepath.Dir(manifest)
	stamp := time.Now().UTC().Format("20060102_150405.000000000")
	backupDir := filepath.Join(backupRoot, filepath.Base(world), stamp)
	checked := make([]checkedSaveEntry, 0, len(transaction.Entries))
	seen := make(map[string]struct{}, len(transaction.Entries))
	for _, entry := range transaction.Entries {
		relative, err := safeSaveRelativePath(entry.RelativePath)
		if err != nil || entry.ExpectedSize < 0 {
			return fmt.Errorf("invalid Prepared save entry in %s", manifest)
		}
		target := filepath.Join(world, relative)
		if _, exists := seen[target]; exists {
			return fmt.Errorf("duplicate Prepared save target in %s: %s", manifest, entry.RelativePath)
		}
		seen[target] = struct{}{}
		if err := ensurePathWithin(world, target); err != nil {
			return err
		}
		temporary := target + ".new_tmp"
		info, err := os.Lstat(temporary)
		if err != nil || !info.Mode().IsRegular() || info.Size() != entry.ExpectedSize {
			return fmt.Errorf("Prepared transaction is incomplete; refusing to replace save: %s", temporary)
		}
		checkedEntry := checkedSaveEntry{target: target, temporary: temporary, backup: filepath.Join(backupDir, relative)}
		if targetInfo, targetErr := os.Lstat(target); targetErr == nil {
			if !targetInfo.Mode().IsRegular() {
				return fmt.Errorf("Prepared target is not a regular file: %s", target)
			}
			checkedEntry.existed = true
		} else if !os.IsNotExist(targetErr) {
			return fmt.Errorf("inspect Prepared target %s: %w", target, targetErr)
		}
		checked = append(checked, checkedEntry)
	}
	for i := range checked {
		entry := &checked[i]
		if err := os.MkdirAll(filepath.Dir(entry.target), 0o755); err != nil {
			return err
		}
		if entry.existed {
			if err := copyRegularFile(entry.target, entry.backup); err != nil {
				return fmt.Errorf("back up save before Prepared recovery: %w", err)
			}
		}
	}
	for i, entry := range checked {
		if err := os.Rename(entry.temporary, entry.target); err != nil {
			rollbackPreparedEntries(checked[:i])
			return fmt.Errorf("atomically recover Prepared save %s: %w", entry.target, err)
		}
	}
	if err := os.Remove(manifest); err != nil {
		return fmt.Errorf("remove recovered Prepared manifest: %w", err)
	}
	for _, name := range []string{"world_save_temp", "world_save_bak"} {
		path := filepath.Join(world, name)
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink == 0 {
			_ = os.RemoveAll(path)
		}
	}
	return nil
}

func safeSaveRelativePath(value string) (string, error) {
	normalized := strings.ReplaceAll(strings.TrimSpace(value), "\\", "/")
	if normalized == "" || strings.Contains(normalized, ":") || strings.HasPrefix(normalized, "/") {
		return "", fmt.Errorf("unsafe relative path")
	}
	clean := filepath.Clean(filepath.FromSlash(normalized))
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("unsafe relative path")
	}
	return clean, nil
}

func ensurePathWithin(root, path string) error {
	relative, err := filepath.Rel(root, path)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("save path escapes world directory: %s", path)
	}
	current := root
	parts := strings.Split(relative, string(filepath.Separator))
	for _, part := range parts[:len(parts)-1] {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("save path traverses symlink: %s", current)
		}
	}
	return nil
}

func copyRegularFile(source, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	return output.Close()
}

func rollbackPreparedEntries(entries []checkedSaveEntry) {
	for i := len(entries) - 1; i >= 0; i-- {
		entry := entries[i]
		if entry.existed {
			_ = copyFileReplace(entry.backup, entry.target)
		} else {
			_ = os.Remove(entry.target)
		}
	}
}

func copyFileReplace(source, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	return output.Close()
}

func probeLinuxAtomicReplace(root string) error {
	destination := filepath.Join(root, ".palpanel-linux-replace-probe")
	replacement := destination + ".new"
	defer os.Remove(destination)
	defer os.Remove(replacement)
	if err := os.WriteFile(destination, []byte("old"), 0o600); err != nil {
		return fmt.Errorf("create Linux atomic replace destination: %w", err)
	}
	if err := os.WriteFile(replacement, []byte("new"), 0o600); err != nil {
		return fmt.Errorf("create Linux atomic replacement: %w", err)
	}
	if err := os.Rename(replacement, destination); err != nil {
		return fmt.Errorf("Linux atomic replacement is unsupported: %w", err)
	}
	body, err := os.ReadFile(destination)
	if err != nil || string(body) != "new" {
		return fmt.Errorf("Linux atomic replacement verification failed")
	}
	return nil
}

func probeWineAtomicReplace(ctx context.Context, wineBinary, winePrefix, root string) error {
	winePath, err := exec.LookPath(wineBinary)
	if err != nil {
		return fmt.Errorf("Host Wine binary %q not found for SaveGames probe: %w", wineBinary, err)
	}
	destination := filepath.Join(root, ".palpanel-wine-replace-probe")
	replacement := destination + ".new"
	batch := filepath.Join(root, ".palpanel-wine-replace-probe.cmd")
	defer os.Remove(destination)
	defer os.Remove(replacement)
	defer os.Remove(batch)
	destinationWin := hostWineWindowsPath(destination)
	replacementWin := hostWineWindowsPath(replacement)
	script := "@echo off\r\nsetlocal\r\nset \"DEST=" + destinationWin + "\"\r\nset \"NEXT=" + replacementWin + "\"\r\n" +
		"for /L %%I in (1,1,24) do (\r\n  >\"%NEXT%\" echo new-%%I\r\n  move /Y \"%NEXT%\" \"%DEST%\" >nul || exit /b 1\r\n)\r\n"
	if err := os.WriteFile(destination, []byte("old"), 0o600); err != nil {
		return err
	}
	if err := os.WriteFile(batch, []byte(script), 0o600); err != nil {
		return err
	}
	probeCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(probeCtx, winePath, "cmd.exe", "/d", "/c", hostWineWindowsPath(batch))
	cmd.Env = append(os.Environ(), "WINEPREFIX="+winePrefix, "WINEDEBUG=-all")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("Wine atomic replacement probe failed: %w: %s", err, strings.TrimSpace(string(out)))
	}
	body, err := os.ReadFile(destination)
	if err != nil || strings.TrimSpace(string(body)) != "new-24" {
		return fmt.Errorf("Wine atomic replacement verification failed")
	}
	return nil
}

func hostWineWindowsPath(path string) string {
	absolute, _ := filepath.Abs(path)
	return `Z:` + strings.ReplaceAll(absolute, "/", `\`)
}
