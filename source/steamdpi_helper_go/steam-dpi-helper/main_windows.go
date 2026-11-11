// DCGaming Steam DPI helper. SPDX-License-Identifier: GPL-3.0-only
// Derived from Ghostline b1ca3f3208f9a41cd888d69b8ff8bcfa8e22c28c.
// DNS/DPI integration ported from NestG; DC Gaming uses independent runtime identities.
package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
	"unsafe"

	runtimeAssets "github.com/hashcott/ghostline/assets"
	"github.com/hashcott/ghostline/internal/dpi"
	"github.com/hashcott/ghostline/internal/dpi/zapret2"
	"github.com/hashcott/ghostline/internal/dpi/zapret2/strategies"
	"github.com/hashcott/ghostline/internal/steamdns"
	"github.com/hashcott/ghostline/internal/winutil"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc/mgr"
)

const upstreamCommit = "b1ca3f3208f9a41cd888d69b8ff8bcfa8e22c28c"
const steamHosts = "steampowered.com\nsteamcommunity.com\nsteamstatic.com\nsteamusercontent.com\nsteamcontent.com\nsteamgames.com\nsteamserver.net\nsteamcdn-a.akamaihd.net\n"

var pipePattern = regexp.MustCompile(`^DCGamingSteamDpi-[A-F0-9]{32}$`)
var kernel = windows.NewLazySystemDLL("kernel32.dll")
var serverPID = kernel.NewProc("GetNamedPipeServerProcessId")

type request struct {
	ID      string `json:"id"`
	Command string `json:"command"`
	Profile string `json:"profile,omitempty"`
}
type response struct {
	Version         int    `json:"version"`
	ID              string `json:"id"`
	Code            string `json:"code"`
	Running         bool   `json:"running"`
	PID             int    `json:"pid"`
	DNSReady        bool   `json:"dnsReady"`
	DPIRunning      bool   `json:"dpiRunning"`
	RecoveryPending bool   `json:"recoveryPending"`
	Stage           string `json:"stage,omitempty"`
	Cause           string `json:"cause,omitempty"`
}

func main() {
	if err := run(); err != nil {
		os.Exit(1)
	}
}
func run() error {
	pipe := flag.String("pipe", "", "private launcher pipe")
	parent := flag.Uint("parent", 0, "launcher PID")
	created := flag.Uint64("created", 0, "launcher Windows creation time")
	selfTest := flag.Bool("self-test", false, "verify embedded runtime only; no OS mutation")
	recover := flag.Bool("recover-dns", false, "restore only journaled DCGaming DNS policies")
	guardian := flag.Bool("dns-guardian", false, "watch a verified helper DNS transaction")
	tag := flag.String("tag", "", "protected DNS transaction tag")
	flag.Parse()
	if *selfTest {
		if *recover || *guardian || *pipe != "" || *parent != 0 || *created != 0 || *tag != "" || flag.NArg() != 0 {
			return errors.New("invalid self test")
		}
		return verifyEmbedded()
	}
	if *recover {
		if *guardian || *pipe != "" || *parent != 0 || *created != 0 || *tag != "" || flag.NArg() != 0 {
			return errors.New("invalid recovery")
		}
		return recoverDNS("")
	}
	if *guardian {
		if *pipe != "" || *parent == 0 || *parent > 0xffffffff || *created == 0 || flag.NArg() != 0 {
			return errors.New("invalid guardian")
		}
		return runDNSGuardian(uint32(*parent), *created, *tag)
	}
	if *tag != "" {
		return errors.New("invalid session tag")
	}
	if flag.NArg() != 0 || !pipePattern.MatchString(*pipe) || *parent == 0 || *parent > 0xffffffff || *created == 0 {
		return errors.New("invalid session")
	}
	if !winutil.IsAdmin() {
		return errors.New("elevation required")
	}
	parentHandle, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, uint32(*parent))
	if err != nil {
		return err
	}
	defer windows.CloseHandle(parentHandle)
	if !sameParent(parentHandle, *created) {
		return errors.New("parent identity mismatch")
	}
	name, _ := windows.UTF16PtrFromString(`\\.\pipe\` + *pipe)
	var handle windows.Handle
	for end := time.Now().Add(10 * time.Second); time.Now().Before(end); time.Sleep(100 * time.Millisecond) {
		handle, err = windows.CreateFile(name, windows.GENERIC_READ|windows.GENERIC_WRITE, 0, nil, windows.OPEN_EXISTING, 0, 0)
		if err == nil {
			break
		}
	}
	if err != nil {
		return err
	}
	file := os.NewFile(uintptr(handle), "launcher-pipe")
	defer file.Close()
	var actual uint32
	ok, _, _ := serverPID.Call(uintptr(handle), uintptr(unsafe.Pointer(&actual)))
	if ok == 0 || actual != uint32(*parent) || !sameParent(parentHandle, *created) {
		return errors.New("untrusted pipe server")
	}
	sd, err := windows.SecurityDescriptorFromString(winutil.AdminOnlySDDL)
	if err != nil {
		return err
	}
	sa := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: sd}
	mutexName, _ := windows.UTF16PtrFromString(`Global\DCGamingSteamDpiHelper.v1`)
	mutex, err := windows.CreateMutex(&sa, true, mutexName)
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		if mutex != 0 {
			windows.CloseHandle(mutex)
		}
		_ = json.NewEncoder(file).Encode(response{Version: 2, Code: "busy"})
		return err
	}
	if err != nil {
		return err
	}
	defer windows.CloseHandle(mutex)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		ticker := time.NewTicker(500 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if !sameParent(parentHandle, *created) {
					cancel()
					_ = file.Close()
					return
				}
			}
		}
	}()
	encoder := json.NewEncoder(file)
	if err = encoder.Encode(response{Version: 2, Code: "ready", PID: os.Getpid()}); err != nil {
		return err
	}
	var manager *dpi.Manager
	var dns *dnsRuntime
	// A fresh helper may inherit an orphan journal. Until recovery succeeds,
	// even a failure before creating dnsRuntime cannot claim support is off.
	_, journalErr := os.Lstat(filepath.Join(dnsDirectory(), "session.json"))
	recoveryPending := !errors.Is(journalErr, os.ErrNotExist)
	defer func() {
		if dns != nil {
			cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			_ = dns.session.Stop(cleanup)
		}
		if manager != nil {
			_ = manager.Stop()
		}
	}()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 1024), 4096)
	for scanner.Scan() {
		var q request
		decoder := json.NewDecoder(strings.NewReader(scanner.Text()))
		decoder.DisallowUnknownFields()
		if decoder.Decode(&q) != nil || len(q.ID) != 32 || (q.Command != "start" && q.Command != "status" && q.Command != "stop" && q.Command != "exit") {
			return errors.New("invalid command")
		}
		var tail any
		if decoder.Decode(&tail) != io.EOF {
			return errors.New("trailing command data")
		}
		r := response{Version: 2, ID: q.ID, Code: "ok"}
		switch q.Command {
		case "start":
			if q.Profile != "dns-only" && q.Profile != "z-split" && q.Profile != "z-disorder" && q.Profile != "z-fake" {
				r.Code = "invalid-profile"
				break
			}
			if dns == nil {
				dns, err = newDNSRuntime()
				if err != nil {
					setDNSFailure(&r, steamdns.Operation("runtime-prepare", err))
					break
				}
			}
			if _, ready := dns.session.State(); ready && q.Profile == "dns-only" {
				dns.resolver.Clear()
				if err = dns.session.Refresh(ctx); err != nil {
					setDNSFailure(&r, err)
					break
				}
			}
			if err = dns.session.Start(ctx); err != nil {
				setDNSFailure(&r, err)
				break
			}
			if q.Profile == "dns-only" {
				if manager != nil && manager.Stop() != nil {
					r.Code = "stop-failed"
				}
				break
			}
			if manager == nil {
				var directory string
				directory, err = secureRuntime()
				if err != nil {
					r.Code = "runtime-unavailable"
					break
				}
				engine := zapret2.New(bundledStrategies)
				manager = dpi.NewManager(directory, []dpi.Installed{{Engine: engine, Assets: runtimeAssets.FS}}, pinnedRunner{}, compatibleServices{directory: directory}, time.Sleep)
			}
			list := filepath.Join(managerDirectory(), "steam-hosts.txt")
			if err = os.WriteFile(list, []byte(steamHosts), 0600); err != nil {
				r.Code = "runtime-unavailable"
				break
			}
			if _, err = manager.Start(ctx, "zapret2", dpi.Plan{Strategy: q.Profile, Scope: dpi.ScopeBlacklist, Blacklist: list}); err != nil {
				r.Code = errorCode(err)
			}
		case "stop", "exit":
			if manager != nil {
				if manager.Stop() != nil {
					r.Code = "stop-failed"
				}
			}
			if dns != nil {
				cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
				stopErr := dns.session.Stop(cleanup)
				cancel()
				if stopErr != nil {
					setDNSFailure(&r, stopErr)
				}
			} else {
				cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
				stopErr := recoverDNSJournal(cleanup)
				cancel()
				recoveryPending = stopErr != nil
				if stopErr != nil {
					setDNSFailure(&r, stopErr)
				}
			}
		case "status":
			if dns != nil {
				checkCtx, cancel := context.WithTimeout(context.Background(), 16*time.Second)
				checkErr := dns.session.Check(checkCtx)
				cancel()
				if checkErr != nil {
					setDNSFailure(&r, checkErr)
				}
			} else if recoveryPending {
				r.Code = "dns-recovery-pending"
				r.Stage = "journal-recovery"
			}
		}
		if manager != nil {
			r.DPIRunning = manager.Running()
			if r.DPIRunning {
				r.PID = manager.PID()
			}
		}
		if dns != nil {
			active, ready := dns.session.State()
			r.Running = active || r.DPIRunning
			r.DNSReady = ready
			r.RecoveryPending = dns.session.RecoveryPending()
		} else {
			r.Running = r.DPIRunning || recoveryPending
			r.RecoveryPending = recoveryPending
		}
		if err = encoder.Encode(r); err != nil {
			return err
		}
		if q.Command == "exit" && !r.Running {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
	}
	return scanner.Err()
}
func setDNSFailure(reply *response, err error) {
	reply.Code = dnsErrorCode(err)
	reply.Cause = reply.Code
	reply.Stage = steamdns.FailureStage(err)
}
func sameParent(h windows.Handle, want uint64) bool {
	var c, e, k, u windows.Filetime
	var exit uint32
	if windows.GetExitCodeProcess(h, &exit) != nil || exit != 259 || windows.GetProcessTimes(h, &c, &e, &k, &u) != nil {
		return false
	}
	return uint64(c.HighDateTime)<<32|uint64(c.LowDateTime) == want
}
func bundledStrategies() strategies.List {
	return strategies.List{Zapret2: []strategies.Strategy{
		{ID: "z-split", TCP: []string{"--lua-desync=multisplit:pos=1,midsld"}},
		{ID: "z-disorder", TCP: []string{"--lua-desync=multidisorder:pos=1,midsld"}},
		// TCP only. UDP/QUIC and all-host autodetection are deliberately absent.
		{ID: "z-fake", TCP: []string{"--lua-desync=fake:blob=fake_default_tls:badsum", "--lua-desync=multidisorder:pos=1,midsld"}},
	}}
}
func verifyEmbedded() error {
	for name, want := range zapret2.Pinned {
		b, err := runtimeAssets.FS.ReadFile(name)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		if hex.EncodeToString(sum[:]) != want {
			return errors.New("embedded hash mismatch")
		}
	}
	return nil
}
func managerDirectory() string {
	base, _ := windows.KnownFolderPath(windows.FOLDERID_ProgramData, 0)
	return filepath.Join(base, "DCGamingSteamDpiRuntime", upstreamCommit)
}
func secureRuntime() (string, error) {
	if err := verifyEmbedded(); err != nil {
		return "", err
	}
	base, err := windows.KnownFolderPath(windows.FOLDERID_ProgramData, 0)
	if err != nil {
		return "", err
	}
	current := base
	for _, part := range []string{"DCGamingSteamDpiRuntime", upstreamCommit, "zapret2", "lua"} {
		current = filepath.Join(current, part)
		if _, err := os.Lstat(current); err == nil {
			if !safeOwnedDirectory(current) {
				return "", steamdns.ErrRuntimeUntrusted
			}
		} else if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
		if err := winutil.SecureDir(current); err != nil {
			return "", err
		}
		if !safeOwnedDirectory(current) {
			return "", steamdns.ErrRuntimeUntrusted
		}
	}
	return managerDirectory(), nil
}
func safeOwnedDirectory(p string) bool {
	name, err := windows.UTF16PtrFromString(p)
	if err != nil {
		return false
	}
	attrs, err := windows.GetFileAttributes(name)
	if err != nil || attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 || attrs&windows.FILE_ATTRIBUTE_DIRECTORY == 0 {
		return false
	}
	owned, err := winutil.OwnedByAdmins(p)
	return err == nil && owned
}
func errorCode(err error) string {
	switch {
	case errors.Is(err, dpi.ErrDriverInUse):
		return "driver-in-use"
	case errors.Is(err, dpi.ErrBlockedByAV):
		return "engine-blocked"
	case errors.Is(err, dpi.ErrHashMismatch):
		return "hash-mismatch"
	case errors.Is(err, context.Canceled):
		return "cancelled"
	default:
		return "start-failed"
	}
}

// Retain shared WinDivert services. A compatible already-loaded driver is
// reusable only when its image is our protected, hash-pinned runtime file.
type compatibleServices struct{ directory string }

func (s compatibleServices) Find(prefix string) ([]string, error) {
	return winutil.FindServices(prefix)
}
func (s compatibleServices) Running(name string) (bool, error) { return winutil.ServiceRunning(name) }
func (s compatibleServices) Active(name string) (bool, error) {
	active, err := winutil.ServiceActive(name)
	if err != nil || !active {
		return active, err
	}
	m, err := mgr.Connect()
	if err != nil {
		return true, err
	}
	defer m.Disconnect()
	svc, err := m.OpenService(name)
	if err != nil {
		return true, err
	}
	defer svc.Close()
	cfg, err := svc.Config()
	if err != nil {
		return true, err
	}
	expected := filepath.Join(s.directory, "zapret2", "WinDivert64.sys")
	actual := strings.Trim(cfg.BinaryPathName, "\"")
	if strings.HasPrefix(actual, `\??\`) {
		actual = strings.TrimPrefix(actual, `\??\`)
	}
	if !strings.EqualFold(actual, expected) {
		return true, nil
	}
	bytes, err := os.ReadFile(expected)
	if err != nil {
		return true, err
	}
	sum := sha256.Sum256(bytes)
	return hex.EncodeToString(sum[:]) != zapret2.Pinned["WinDivert64.sys"], nil
}
func (s compatibleServices) Stop(string) error { return fmt.Errorf("shared driver mutation forbidden") }
func (s compatibleServices) Delete(string) error {
	return fmt.Errorf("shared driver mutation forbidden")
}

// Keep native/Lua inputs closed to writes for the engine's lifetime.
type pinnedRunner struct{}
type pinnedProcess struct {
	dpi.Process
	files []*os.File
	once  sync.Once
}

func (p *pinnedProcess) release() {
	p.once.Do(func() {
		for _, f := range p.files {
			_ = f.Close()
		}
	})
}
func (p *pinnedProcess) Exited() bool {
	exited := p.Process.Exited()
	if exited {
		p.release()
	}
	return exited
}
func (p *pinnedProcess) Kill() error {
	err := p.Process.Kill()
	if p.Process.Exited() {
		p.release()
	}
	return err
}
func (pinnedRunner) Start(executable string, args []string, directory string) (dpi.Process, error) {
	var leases []*os.File
	release := func() {
		for _, f := range leases {
			_ = f.Close()
		}
	}
	expected := map[string]string{}
	for name, hash := range zapret2.Pinned {
		expected[name] = hash
	}
	sum := sha256.Sum256([]byte(steamHosts))
	expected["blacklist.txt"] = hex.EncodeToString(sum[:])
	for name, want := range expected {
		path := filepath.Join(directory, filepath.FromSlash(name))
		utf16, err := windows.UTF16PtrFromString(path)
		if err != nil {
			release()
			return nil, err
		}
		attrs, err := windows.GetFileAttributes(utf16)
		if err != nil || attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			release()
			return nil, errors.New("untrusted runtime file")
		}
		handle, err := windows.CreateFile(utf16, windows.GENERIC_READ, windows.FILE_SHARE_READ, nil, windows.OPEN_EXISTING, windows.FILE_FLAG_OPEN_REPARSE_POINT, 0)
		if err != nil {
			release()
			return nil, err
		}
		file := os.NewFile(uintptr(handle), name)
		leases = append(leases, file)
		hash := sha256.New()
		if _, err = io.Copy(hash, file); err != nil || hex.EncodeToString(hash.Sum(nil)) != want {
			release()
			return nil, dpi.ErrHashMismatch
		}
	}
	process, err := dpi.NewWindowsRunner().Start(executable, args, directory)
	if err != nil {
		release()
		return nil, err
	}
	return &pinnedProcess{Process: process, files: leases}, nil
}
