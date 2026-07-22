//go:build linux

package server

import (
	"fmt"
	"testing"
)

func TestParseProcStartTimeHandlesSpacesAndParenthesesInComm(t *testing.T) {
	fields := make([]any, 0, 52)
	fields = append(fields, 123, "(Pal Server (Wine))", "S")
	for field := 4; field <= 52; field++ {
		value := field
		if field == 22 {
			value = 987654
		}
		fields = append(fields, value)
	}
	stat := []byte(fmt.Sprintln(fields...))
	start, err := parseProcStartTime(stat)
	if err != nil {
		t.Fatal(err)
	}
	if start != 987654 {
		t.Fatalf("start time = %d, want 987654", start)
	}
}

func TestNULIdentityFieldsRequireExactPaths(t *testing.T) {
	if !nulListContainsPath([]byte("wine64\x00/opt/pal/PalServer-Win64-Shipping.exe\x00"), "/opt/pal/PalServer-Win64-Shipping.exe") {
		t.Fatal("expected Shipping path match")
	}
	if nulListContainsPath([]byte("/opt/pal/PalServer-Win64-Shipping.exe.old\x00"), "/opt/pal/PalServer-Win64-Shipping.exe") {
		t.Fatal("unexpected partial Shipping path match")
	}
	if !nulEnvironmentPathEquals([]byte("HOME=/srv\x00WINEPREFIX=/srv/pal/wine\x00"), "WINEPREFIX", "/srv/pal/wine") {
		t.Fatal("expected WINEPREFIX match")
	}
}
