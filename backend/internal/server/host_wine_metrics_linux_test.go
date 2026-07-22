//go:build linux

package server

import (
	"fmt"
	"testing"
)

func TestParseProcUsage(t *testing.T) {
	fields := make([]any, 0, 52)
	fields = append(fields, 42, "(Pal Server)", "S")
	for field := 4; field <= 52; field++ {
		value := field
		switch field {
		case 14:
			value = 100
		case 15:
			value = 25
		case 24:
			value = 2048
		}
		fields = append(fields, value)
	}
	cpu, rss, err := parseProcUsage([]byte(fmt.Sprintln(fields...)))
	if err != nil {
		t.Fatal(err)
	}
	if cpu != 125 || rss != 2048 {
		t.Fatalf("usage = cpu %d rss %d", cpu, rss)
	}
}

func TestParseHostCPUTicks(t *testing.T) {
	got, err := parseHostCPUTicks([]byte("cpu  1 2 3 4 5 6 7 8 9 10\ncpu0 1 2\n"))
	if err != nil {
		t.Fatal(err)
	}
	if got != 55 {
		t.Fatalf("ticks = %d, want 55", got)
	}
}
