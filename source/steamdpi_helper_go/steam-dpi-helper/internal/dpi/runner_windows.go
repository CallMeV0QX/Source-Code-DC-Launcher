package dpi

import (
	"log/slog"
	"os/exec"
	"sync"
	"sync/atomic"
	"time"

	"github.com/hashcott/ghostline/internal/winutil"
	"golang.org/x/sys/windows"
)

type winProc struct {
	cmd      *exec.Cmd
	job      *winutil.Job
	jobClose sync.Once
	exited   atomic.Bool
	killed   atomic.Bool
}

func (p *winProc) PID() int     { return p.cmd.Process.Pid }
func (p *winProc) Exited() bool { return p.exited.Load() }
func (p *winProc) Kill() error {
	p.killed.Store(true)
	err := p.cmd.Process.Kill()
	p.jobClose.Do(func() {
		if cerr := p.job.Close(); cerr != nil {
			slog.Warn("dpi: close engine job object failed", "err", cerr, "pid", p.PID())
		}
	})
	// Report completion only after our child has actually exited.
	for deadline := time.Now().Add(3 * time.Second); !p.exited.Load() && time.Now().Before(deadline); {
		time.Sleep(20 * time.Millisecond)
	}
	return err
}

type winRunner struct{}

// NewWindowsRunner starts hidden processes bound to a kill-on-close job, so
// GoodbyeDPI dies with Ghostline.
func NewWindowsRunner() Runner { return winRunner{} }

func (winRunner) Start(exe string, args []string, dir string) (Process, error) {
	job, err := winutil.NewKillOnCloseJob()
	if err != nil {
		return nil, err
	}
	cmd := winutil.HiddenCmd(exe, args, dir)
	// Suspend before the engine can install any packet filter. Assignment
	// failure is terminal; an unowned engine must never continue running.
	cmd.SysProcAttr.CreationFlags |= windows.CREATE_SUSPENDED
	if err := cmd.Start(); err != nil {
		_ = job.Close()
		return nil, err
	}
	pid := cmd.Process.Pid
	p := &winProc{cmd: cmd, job: job}
	if err = job.Assign(cmd.Process); err == nil {
		err = winutil.ResumeProcess(uint32(pid))
	}
	if err != nil {
		_ = cmd.Process.Kill()
		_ = job.Close()
		_ = cmd.Wait()
		return nil, err
	}
	go func() {
		err := cmd.Wait()
		// Natural exit must also close the job, releasing owned descendants.
		// Kill and Wait can race; only one closes the retained handle.
		p.jobClose.Do(func() { _ = job.Close() })
		p.exited.Store(true)
		if p.killed.Load() {
			slog.Info("dpi: engine process stopped", "pid", pid, "exe", exe)
		} else {
			// Includes the exit status: why the engine died on its own.
			slog.Warn("dpi: engine process exited", "err", err, "pid", pid, "exe", exe)
		}
	}()
	return p, nil
}

type winServices struct{}

// NewWindowsServices controls services through the SCM.
func NewWindowsServices() Services { return winServices{} }

func (winServices) Find(prefix string) ([]string, error) { return winutil.FindServices(prefix) }
func (winServices) Running(name string) (bool, error)    { return winutil.ServiceRunning(name) }
func (winServices) Active(name string) (bool, error)     { return winutil.ServiceActive(name) }
func (winServices) Stop(name string) error               { return winutil.StopService(name, 5*time.Second) }
func (winServices) Delete(name string) error             { return winutil.DeleteService(name) }
