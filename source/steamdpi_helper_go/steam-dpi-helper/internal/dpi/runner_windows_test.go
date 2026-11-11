package dpi

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Only a disposable test child is launched. No elevation or driver is used.
func TestWindowsRunnerResumesAndStopsOwnedChild(t *testing.T) {
	ready := filepath.Join(t.TempDir(), "ready")
	t.Setenv("NESTG_DPI_RUNNER_TEST_READY", ready)
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	process, err := NewWindowsRunner().Start(executable, []string{"-test.run=^TestWindowsRunnerChild$"}, filepath.Dir(ready))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if !process.Exited() {
			_ = process.Kill()
		}
	})
	for deadline := time.Now().Add(5 * time.Second); ; time.Sleep(20 * time.Millisecond) {
		if bytes, err := os.ReadFile(ready); err == nil && string(bytes) == "started" {
			break
		}
		if process.Exited() || time.Now().After(deadline) {
			t.Fatal("owned child was not resumed")
		}
	}
	if err := process.Kill(); err != nil {
		t.Fatal(err)
	}
	if !process.Exited() {
		t.Fatal("owned child did not exit")
	}
}

func TestWindowsRunnerChild(t *testing.T) {
	ready := os.Getenv("NESTG_DPI_RUNNER_TEST_READY")
	if ready == "" {
		return
	}
	if err := os.WriteFile(ready, []byte("started"), 0600); err != nil {
		t.Fatal(err)
	}
	for {
		time.Sleep(time.Hour)
	}
}
