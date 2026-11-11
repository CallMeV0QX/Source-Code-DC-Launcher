package main

import (
	"github.com/hashcott/ghostline/internal/dpi"
	"github.com/hashcott/ghostline/internal/dpi/zapret2"
	"strings"
	"testing"
)

func TestAllBundledProfilesRemainSteamScopedTCPOnly(t *testing.T) {
	engine := zapret2.New(bundledStrategies)
	for _, profile := range bundledStrategies().Zapret2 {
		args, err := engine.Args(dpi.Plan{Strategy: profile.ID, Scope: dpi.ScopeBlacklist, Blacklist: "blacklist.txt"})
		if err != nil {
			t.Fatal(err)
		}
		scope := 0
		for _, arg := range args {
			if arg == "--hostlist=blacklist.txt" {
				scope++
			}
			if strings.Contains(arg, "udp") || strings.Contains(arg, "auto=") || strings.Contains(arg, "luaexec") {
				t.Fatalf("unexpected broadening: %s", arg)
			}
		}
		if scope != 1 {
			t.Fatalf("profile %s has no exact scope", profile.ID)
		}
	}
}
func TestPipeNamesRejectPathsAndForeignPrefixes(t *testing.T) {
	for _, name := range []string{"DCGamingSteamDpi-0123456789ABCDEF0123456789ABCDEF", "NestGSteamDpi-0123456789ABCDEF0123456789ABCDEF", "DCGamingSteamDpi-../../other", "foreign-0123456789ABCDEF0123456789ABCDEF", "DCGamingSteamDpi-0123"} {
		expected := name == "DCGamingSteamDpi-0123456789ABCDEF0123456789ABCDEF"
		if pipePattern.MatchString(name) != expected {
			t.Fatal(name)
		}
	}
}
