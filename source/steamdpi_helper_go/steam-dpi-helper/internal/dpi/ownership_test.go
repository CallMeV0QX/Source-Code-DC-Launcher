package dpi

import (
	"context"
	"errors"
	"io/fs"
	"testing"
	"testing/fstest"
	"time"
)

type fixtureProcess struct{ killed, killFails bool }

func (p *fixtureProcess) PID() int     { return 42 }
func (p *fixtureProcess) Exited() bool { return p.killed }
func (p *fixtureProcess) Kill() error {
	if p.killFails {
		return errors.New("owned child did not exit")
	}
	p.killed = true
	return nil
}

type fixtureRunner struct {
	process *fixtureProcess
	started bool
}

func (r *fixtureRunner) Start(string, []string, string) (Process, error) {
	r.started = true
	return r.process, nil
}

type fixtureServices struct {
	foreign bool
	unknown bool
	mutated bool
}

func (s *fixtureServices) Find(string) ([]string, error) {
	if s.unknown {
		return nil, errors.New("denied")
	}
	return []string{"WinDivert"}, nil
}
func (s *fixtureServices) Running(string) (bool, error) { return true, nil }
func (s *fixtureServices) Active(string) (bool, error)  { return s.foreign, nil }
func (s *fixtureServices) Stop(string) error            { s.mutated = true; return nil }
func (s *fixtureServices) Delete(string) error          { s.mutated = true; return nil }

type fixtureEngine struct{}

func (fixtureEngine) ID() string { return "fixture" }
func (fixtureEngine) Files() map[string]string {
	return map[string]string{"fixture.exe": hashOf([]byte("never execute"))}
}
func (fixtureEngine) Exe() string                 { return "fixture.exe" }
func (fixtureEngine) Args(Plan) ([]string, error) { return nil, nil }
func (fixtureEngine) Strategies() []Strategy      { return nil }
func (fixtureEngine) ValidateCustom(string) error { return nil }
func (fixtureEngine) HotReloadsLists() bool       { return false }
func fixtureManager(t *testing.T, s *fixtureServices, sleep func(time.Duration)) (*Manager, *fixtureRunner) {
	r := &fixtureRunner{process: &fixtureProcess{}}
	var files fs.FS = fstest.MapFS{"fixture.exe": &fstest.MapFile{Data: []byte("never execute")}}
	return NewManager(t.TempDir(), []Installed{{Engine: fixtureEngine{}, Assets: files}}, r, s, sleep), r
}
func TestForeignAndUnknownDriverNeverStartsOrMutatesServices(t *testing.T) {
	for _, s := range []*fixtureServices{{foreign: true}, {unknown: true}} {
		m, r := fixtureManager(t, s, func(time.Duration) {})
		_, err := m.Start(context.Background(), "fixture", Plan{})
		if !errors.Is(err, ErrDriverInUse) || r.started || s.mutated {
			t.Fatal("foreign driver was touched")
		}
	}
}
func TestStopOnlyKillsOwnedEngine(t *testing.T) {
	s := &fixtureServices{}
	m, r := fixtureManager(t, s, func(time.Duration) {})
	if _, err := m.Start(context.Background(), "fixture", Plan{}); err != nil {
		t.Fatal(err)
	}
	if err := m.Stop(); err != nil {
		t.Fatal(err)
	}
	if !r.process.killed || s.mutated {
		t.Fatal("ownership violated")
	}
}
func TestCancellationDuringStartKillsOwnedProcess(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	s := &fixtureServices{}
	m, r := fixtureManager(t, s, func(time.Duration) { cancel() })
	_, err := m.Start(ctx, "fixture", Plan{})
	if !errors.Is(err, context.Canceled) || !r.process.killed || s.mutated {
		t.Fatal("cancelled engine escaped")
	}
}

func TestUnconfirmedStartupCleanupRetainsOwnedProcessForRetry(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	s := &fixtureServices{}
	m, r := fixtureManager(t, s, func(time.Duration) { cancel() })
	r.process.killFails = true
	_, err := m.Start(ctx, "fixture", Plan{})
	if !errors.Is(err, context.Canceled) || !m.Running() || m.PID() != 42 {
		t.Fatal("unconfirmed child ownership was lost")
	}
	if m.Stop() == nil || !m.Running() {
		t.Fatal("unconfirmed stop was reported as successful")
	}
	r.process.killFails = false
	if m.Stop() != nil || m.Running() || s.mutated {
		t.Fatal("owned cleanup retry failed")
	}
}
