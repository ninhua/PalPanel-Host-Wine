//go:build linux

package server

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"palpanel/internal/docker"
)

const hostWineDiscoveryTimeout = 30 * time.Second
const hostWineStopTimeout = 20 * time.Second

func (m Manager) startHostWine(ctx context.Context, args []string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if !fileExists(m.cfg.PalServerExePath()) {
		return fmt.Errorf("PalServer.exe not found")
	}
	winePath, err := exec.LookPath(m.cfg.WineBinary)
	if err != nil {
		return fmt.Errorf("Host Wine binary %q not found: %w", m.cfg.WineBinary, err)
	}
	if err := os.MkdirAll(m.cfg.WinePrefixDir, 0o755); err != nil {
		return fmt.Errorf("create PalServer WINEPREFIX: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(m.cfg.ServerLogPath()), 0o755); err != nil {
		return err
	}
	logFile, err := newRollingLogWriter(m.cfg.ServerLogPath(), 20*1024*1024, 5)
	if err != nil {
		return err
	}
	cmdArgs := append([]string{m.cfg.PalServerExePath()}, args...)
	cmd := exec.Command(winePath, cmdArgs...)
	cmd.Dir = m.cfg.ServerDirectory()
	cmd.Env = append(os.Environ(), "WINEPREFIX="+m.cfg.WinePrefixDir, "WINEDEBUG=-all")
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if _, err := fmt.Fprintf(logFile, "%s [palpanel] starting PalServer with Host Wine\n", time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
		_ = logFile.Close()
		return err
	}
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		return fmt.Errorf("start Host Wine PalServer session: %w", err)
	}
	exited := make(chan error, 1)
	go func() {
		exited <- cmd.Wait()
		_ = logFile.Close()
	}()
	record, err := waitForHostWineShipping(ctx, cmd.Process.Pid, m.cfg.PalServerShippingPath(), m.cfg.WinePrefixDir, exited)
	if err != nil {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		return err
	}
	if err := m.persistHostWineProcess(context.Background(), record); err != nil {
		_ = syscall.Kill(-record.ProcessGroupID, syscall.SIGKILL)
		return fmt.Errorf("persist Host Wine process identity: %w", err)
	}
	return nil
}

func waitForHostWineShipping(ctx context.Context, pgid int, shippingPath, winePrefix string, exited <-chan error) (hostWineProcessRecord, error) {
	timer := time.NewTimer(hostWineDiscoveryTimeout)
	defer timer.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		record, found := findHostWineShippingProcess(pgid, shippingPath, winePrefix)
		if found {
			return record, nil
		}
		select {
		case <-ctx.Done():
			return hostWineProcessRecord{}, ctx.Err()
		case err := <-exited:
			return hostWineProcessRecord{}, fmt.Errorf("Host Wine launcher exited before Shipping process discovery: %v", err)
		case <-timer.C:
			return hostWineProcessRecord{}, fmt.Errorf("timed out discovering PalServer Shipping process in Wine session %d", pgid)
		case <-ticker.C:
		}
	}
}

func findHostWineShippingProcess(pgid int, shippingPath, winePrefix string) (hostWineProcessRecord, bool) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return hostWineProcessRecord{}, false
	}
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		candidateGroup, err := syscall.Getpgid(pid)
		if err != nil || candidateGroup != pgid {
			continue
		}
		record, err := inspectHostWineProcess(pid, shippingPath, winePrefix)
		if err == nil {
			return record, true
		}
	}
	return hostWineProcessRecord{}, false
}

func (m Manager) stopHostWine(ctx context.Context) error {
	record, ok, err := m.loadHostWineProcess(ctx)
	if err != nil || !ok {
		return err
	}
	running, err := verifyHostWineProcess(record)
	if err != nil {
		return err
	}
	if !running {
		return m.clearHostWineProcess(ctx)
	}
	if err := syscall.Kill(-record.ProcessGroupID, syscall.SIGTERM); err != nil && err != syscall.ESRCH {
		return fmt.Errorf("terminate Host Wine process group: %w", err)
	}
	deadline := time.NewTimer(hostWineStopTimeout)
	defer deadline.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		running, verifyErr := verifyHostWineProcess(record)
		if verifyErr != nil {
			return verifyErr
		}
		if !running {
			return m.clearHostWineProcess(ctx)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			if err := syscall.Kill(-record.ProcessGroupID, syscall.SIGKILL); err != nil && err != syscall.ESRCH {
				return fmt.Errorf("kill Host Wine process group: %w", err)
			}
			return m.clearHostWineProcess(context.Background())
		case <-ticker.C:
		}
	}
}

func (m Manager) hostWineStatus(ctx context.Context) (docker.ContainerStatus, error) {
	record, ok, err := m.loadHostWineProcess(ctx)
	if err != nil {
		return docker.ContainerStatus{Status: "error"}, err
	}
	if !ok {
		return docker.ContainerStatus{Status: "missing"}, nil
	}
	running, err := verifyHostWineProcess(record)
	if err != nil {
		return docker.ContainerStatus{Status: "error"}, err
	}
	if !running {
		if err := m.clearHostWineProcess(ctx); err != nil {
			log.Printf("clear stale Host Wine process identity: %v", err)
		}
		return docker.ContainerStatus{Status: "missing"}, nil
	}
	return docker.ContainerStatus{Exists: true, Status: "running"}, nil
}
