//go:build linux

package server

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type hostWineUsageSample struct {
	processTicks uint64
	totalTicks   uint64
	memoryBytes  uint64
}

func sampleHostWineProcessGroup(ctx context.Context, pgid int) (RuntimeMetrics, error) {
	first, err := readHostWineUsage(pgid)
	if err != nil {
		return RuntimeMetrics{}, err
	}
	timer := time.NewTimer(100 * time.Millisecond)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return RuntimeMetrics{}, ctx.Err()
	case <-timer.C:
	}
	second, err := readHostWineUsage(pgid)
	if err != nil {
		return RuntimeMetrics{}, err
	}
	metrics := RuntimeMetrics{MemoryBytes: second.memoryBytes}
	if second.processTicks < first.processTicks || second.totalTicks <= first.totalTicks {
		return metrics, nil
	}
	processDelta := second.processTicks - first.processTicks
	totalDelta := second.totalTicks - first.totalTicks
	if totalDelta > 0 {
		metrics.CPUPercent = float64(processDelta) / float64(totalDelta) * float64(runtime.NumCPU()) * 100
	}
	return metrics, nil
}

func readHostWineUsage(pgid int) (hostWineUsageSample, error) {
	stat, err := os.ReadFile("/proc/stat")
	if err != nil {
		return hostWineUsageSample{}, fmt.Errorf("read host CPU stat: %w", err)
	}
	totalTicks, err := parseHostCPUTicks(stat)
	if err != nil {
		return hostWineUsageSample{}, err
	}
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return hostWineUsageSample{}, err
	}
	sample := hostWineUsageSample{totalTicks: totalTicks}
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		group, err := syscall.Getpgid(pid)
		if err != nil || group != pgid {
			continue
		}
		raw, err := os.ReadFile("/proc/" + entry.Name() + "/stat")
		if err != nil {
			continue
		}
		cpuTicks, rssPages, err := parseProcUsage(raw)
		if err != nil {
			continue
		}
		sample.processTicks += cpuTicks
		if rssPages > 0 {
			sample.memoryBytes += uint64(rssPages) * uint64(os.Getpagesize())
		}
	}
	return sample, nil
}

func parseHostCPUTicks(stat []byte) (uint64, error) {
	line, _, _ := bytes.Cut(stat, []byte{'\n'})
	fields := strings.Fields(string(line))
	if len(fields) < 2 || fields[0] != "cpu" {
		return 0, fmt.Errorf("invalid /proc/stat CPU record")
	}
	var total uint64
	for _, field := range fields[1:] {
		value, err := strconv.ParseUint(field, 10, 64)
		if err != nil {
			return 0, fmt.Errorf("parse host CPU ticks: %w", err)
		}
		total += value
	}
	return total, nil
}

func parseProcUsage(stat []byte) (uint64, int64, error) {
	closeParen := bytes.LastIndexByte(stat, ')')
	if closeParen < 0 || closeParen+2 >= len(stat) {
		return 0, 0, fmt.Errorf("invalid /proc process stat record")
	}
	fields := strings.Fields(string(stat[closeParen+2:]))
	if len(fields) <= 21 {
		return 0, 0, fmt.Errorf("short /proc process stat record")
	}
	userTicks, err := strconv.ParseUint(fields[11], 10, 64)
	if err != nil {
		return 0, 0, err
	}
	systemTicks, err := strconv.ParseUint(fields[12], 10, 64)
	if err != nil {
		return 0, 0, err
	}
	rssPages, err := strconv.ParseInt(fields[21], 10, 64)
	if err != nil {
		return 0, 0, err
	}
	return userTicks + systemTicks, rssPages, nil
}
