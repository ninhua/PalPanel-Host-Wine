//go:build linux

package server

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

func inspectHostWineProcess(pid int, shippingPath, winePrefix string) (hostWineProcessRecord, error) {
	if pid <= 0 {
		return hostWineProcessRecord{}, fmt.Errorf("invalid PalServer PID %d", pid)
	}
	procDir := filepath.Join("/proc", strconv.Itoa(pid))
	stat, err := os.ReadFile(filepath.Join(procDir, "stat"))
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("read PalServer process stat: %w", err)
	}
	if procStatExited(stat) {
		return hostWineProcessRecord{}, fmt.Errorf("PalServer process exited: %w", os.ErrNotExist)
	}
	startTicks, err := parseProcStartTime(stat)
	if err != nil {
		return hostWineProcessRecord{}, err
	}
	pgid, err := syscall.Getpgid(pid)
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("read PalServer process group: %w", err)
	}
	cmdline, err := os.ReadFile(filepath.Join(procDir, "cmdline"))
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("read PalServer command line: %w", err)
	}
	shippingPath, err = filepath.Abs(shippingPath)
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("resolve PalServer Shipping path: %w", err)
	}
	if !nulListContainsPath(cmdline, shippingPath) {
		if currentStat, statErr := os.ReadFile(filepath.Join(procDir, "stat")); os.IsNotExist(statErr) || (statErr == nil && procStatExited(currentStat)) {
			return hostWineProcessRecord{}, fmt.Errorf("PalServer process exited during identity verification: %w", os.ErrNotExist)
		}
		return hostWineProcessRecord{}, fmt.Errorf("PID %d command line does not contain expected PalServer Shipping path", pid)
	}
	winePrefix, err = filepath.Abs(winePrefix)
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("resolve WINEPREFIX: %w", err)
	}
	environ, err := os.ReadFile(filepath.Join(procDir, "environ"))
	if err != nil {
		return hostWineProcessRecord{}, fmt.Errorf("read PalServer environment: %w", err)
	}
	if !nulEnvironmentPathEquals(environ, "WINEPREFIX", winePrefix) {
		return hostWineProcessRecord{}, fmt.Errorf("PID %d WINEPREFIX does not match the PalServer prefix", pid)
	}
	return hostWineProcessRecord{PID: pid, ProcessGroupID: pgid, StartTimeTicks: startTicks, ShippingPath: shippingPath, WinePrefix: winePrefix}, nil
}

func procStatExited(stat []byte) bool {
	closeParen := bytes.LastIndexByte(stat, ')')
	if closeParen < 0 || closeParen+2 >= len(stat) {
		return false
	}
	fields := strings.Fields(string(stat[closeParen+2:]))
	return len(fields) > 0 && (fields[0] == "Z" || fields[0] == "X" || fields[0] == "x")
}

func verifyHostWineProcess(record hostWineProcessRecord) (bool, error) {
	current, err := inspectHostWineProcess(record.PID, record.ShippingPath, record.WinePrefix)
	if err != nil {
		if os.IsNotExist(rootCause(err)) {
			return false, nil
		}
		return false, err
	}
	return current.ProcessGroupID == record.ProcessGroupID && current.StartTimeTicks == record.StartTimeTicks, nil
}

func parseProcStartTime(stat []byte) (uint64, error) {
	closeParen := bytes.LastIndexByte(stat, ')')
	if closeParen < 0 || closeParen+2 >= len(stat) {
		return 0, fmt.Errorf("invalid /proc stat record")
	}
	fields := strings.Fields(string(stat[closeParen+2:]))
	// The suffix starts at field 3 (state); process start time is field 22.
	if len(fields) <= 19 {
		return 0, fmt.Errorf("/proc stat record has %d fields after comm", len(fields))
	}
	value, err := strconv.ParseUint(fields[19], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse PalServer process start time: %w", err)
	}
	return value, nil
}

func nulListContainsPath(raw []byte, expected string) bool {
	for _, value := range bytes.Split(raw, []byte{0}) {
		if valuePathEquals(string(value), expected) || winePathEquals(string(value), expected) {
			return true
		}
	}
	return false
}

func winePathEquals(value, expected string) bool {
	value = strings.ReplaceAll(strings.TrimSpace(value), `\`, "/")
	if len(value) < 3 || value[1] != ':' || value[2] != '/' {
		return false
	}
	// Wine's default Z: drive maps to the Unix root. Compare the complete
	// normalized argument; never accept a basename or substring match.
	if !strings.EqualFold(value[:2], "z:") {
		return false
	}
	resolved, err := filepath.Abs("/" + strings.TrimLeft(value[3:], "/"))
	return err == nil && filepath.Clean(resolved) == filepath.Clean(expected)
}

func nulEnvironmentPathEquals(raw []byte, key, expected string) bool {
	prefix := key + "="
	for _, value := range bytes.Split(raw, []byte{0}) {
		entry := string(value)
		if strings.HasPrefix(entry, prefix) && valuePathEquals(strings.TrimPrefix(entry, prefix), expected) {
			return true
		}
	}
	return false
}

func valuePathEquals(value, expected string) bool {
	resolved, err := filepath.Abs(value)
	return err == nil && filepath.Clean(resolved) == filepath.Clean(expected)
}

func rootCause(err error) error {
	for {
		unwrapped, ok := err.(interface{ Unwrap() error })
		if !ok || unwrapped.Unwrap() == nil {
			return err
		}
		err = unwrapped.Unwrap()
	}
}
