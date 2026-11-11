// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unsafe"

	"github.com/hashcott/ghostline/internal/steamdns"
	"github.com/hashcott/ghostline/internal/winutil"
	"golang.org/x/sys/windows"
)

type dnsJournalStore struct{ directory string }

func (s dnsJournalStore) path() string { return filepath.Join(s.directory, "session.json") }
func openDNSJournal(path string) (*os.File, error) {
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	// Guardian reads must not block atomic journal replacement/removal on Windows.
	// Validate the same opened file instead of checking one path and reading another.
	handle, err := windows.CreateFile(name, windows.GENERIC_READ|windows.READ_CONTROL,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE, nil,
		windows.OPEN_EXISTING, windows.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		return nil, err
	}
	return os.NewFile(uintptr(handle), path), nil
}
func (s dnsJournalStore) Read() (*steamdns.Journal, error) {
	file, err := openDNSJournal(s.path())
	if errors.Is(err, windows.ERROR_FILE_NOT_FOUND) || errors.Is(err, windows.ERROR_PATH_NOT_FOUND) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer file.Close()
	handle := windows.Handle(file.Fd())
	var info windows.ByHandleFileInformation
	if windows.GetFileInformationByHandle(handle, &info) != nil ||
		info.FileAttributes&(windows.FILE_ATTRIBUTE_REPARSE_POINT|windows.FILE_ATTRIBUTE_DIRECTORY) != 0 ||
		info.FileSizeHigh != 0 || info.FileSizeLow > 4096 {
		return nil, steamdns.ErrJournalUntrusted
	}
	sd, err := windows.GetSecurityInfo(handle, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION)
	if err != nil {
		return nil, err
	}
	owner, _, err := sd.Owner()
	if err != nil {
		return nil, err
	}
	trusted := false
	for _, kind := range []windows.WELL_KNOWN_SID_TYPE{windows.WinBuiltinAdministratorsSid, windows.WinLocalSystemSid} {
		sid, sidErr := windows.CreateWellKnownSid(kind)
		if sidErr == nil && owner.Equals(sid) {
			trusted = true
		}
	}
	if !trusted {
		return nil, steamdns.ErrJournalUntrusted
	}
	bytes, err := io.ReadAll(io.LimitReader(file, 4097))
	if err != nil {
		return nil, err
	}
	var journal steamdns.Journal
	if len(bytes) > 4096 || json.Unmarshal(bytes, &journal) != nil || !steamdns.ValidJournal(&journal) {
		return nil, steamdns.ErrJournalInvalid
	}
	return &journal, nil
}
func (s dnsJournalStore) Write(journal *steamdns.Journal) error {
	if !steamdns.ValidJournal(journal) || !safeOwnedDirectory(s.directory) {
		return steamdns.ErrRecoveryPending
	}
	bytes, err := json.Marshal(journal)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(s.directory, "session-*.tmp")
	if err != nil {
		return err
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	if err = secureDNSFile(temporary); err != nil {
		file.Close()
		return err
	}
	if _, err = file.Write(bytes); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	from, _ := windows.UTF16PtrFromString(temporary)
	to, _ := windows.UTF16PtrFromString(s.path())
	return replaceDNSFile(from, to)
}

// Windows can reject replacement while a previous guardian briefly holds the
// target. Retry only sharing/access errors; don't change ACLs or delete the target.
func replaceDNSFile(from, to *uint16) error {
	var err error
	for attempt := 0; attempt < 40; attempt++ {
		err = windows.MoveFileEx(from, to, windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH)
		if err == nil {
			return nil
		}
		if !errors.Is(err, windows.ERROR_SHARING_VIOLATION) && !errors.Is(err, windows.ERROR_ACCESS_DENIED) {
			return err
		}
		time.Sleep(50 * time.Millisecond)
	}
	return err
}
func (s dnsJournalStore) Delete() error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		err = os.Remove(s.path())
		if err == nil || errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if !errors.Is(err, windows.ERROR_SHARING_VIOLATION) && !errors.Is(err, windows.ERROR_ACCESS_DENIED) {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	return err
}

func dnsDirectory() string { return filepath.Join(managerDirectory(), "dns") }
func dnsStore() (dnsJournalStore, error) {
	directory := dnsDirectory()
	if !safeOwnedDirectory(managerDirectory()) {
		return dnsJournalStore{}, steamdns.ErrRuntimeUntrusted
	}
	if _, err := os.Lstat(directory); err == nil && !safeOwnedDirectory(directory) {
		return dnsJournalStore{}, steamdns.ErrRuntimeUntrusted
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return dnsJournalStore{}, err
	}
	if err := winutil.SecureDir(directory); err != nil {
		return dnsJournalStore{}, err
	}
	if !safeOwnedDirectory(directory) {
		return dnsJournalStore{}, steamdns.ErrRuntimeUntrusted
	}
	return dnsJournalStore{directory}, nil
}

type dnsRuntime struct {
	session  *steamdns.Session
	resolver *steamdns.Resolver
}

func newDNSRuntime() (*dnsRuntime, error) {
	if _, err := secureRuntime(); err != nil {
		return nil, err
	}
	store, err := dnsStore()
	if err != nil {
		return nil, err
	}
	pid := uint32(os.Getpid())
	handle, err := windows.GetCurrentProcess()
	if err != nil {
		return nil, err
	}
	created, err := creationTime(handle)
	if err != nil {
		return nil, err
	}
	resolver := steamdns.NewResolver()
	session := steamdns.NewSession(store, steamdns.WindowsPolicy{}, func() (steamdns.Listener, error) {
		resolver.Clear()
		deadline, cancel := context.WithTimeout(context.Background(), 11*time.Second)
		defer cancel()
		if err := resolver.Check(deadline); err != nil {
			return nil, err
		}
		listener, err := steamdns.StartRelay(resolver, "127.0.0.1:53")
		if err != nil {
			return nil, errors.Join(steamdns.ErrListenerBusy, err)
		}
		return listener, nil
	},
		func(ctx context.Context, journal *steamdns.Journal) error {
			return prepareDNSRecovery(ctx, store, journal)
		}, pid, created)
	return &dnsRuntime{session, resolver}, nil
}
func creationTime(handle windows.Handle) (uint64, error) {
	var c, e, k, u windows.Filetime
	if err := windows.GetProcessTimes(handle, &c, &e, &k, &u); err != nil {
		return 0, err
	}
	return uint64(c.HighDateTime)<<32 | uint64(c.LowDateTime), nil
}

const recoveryTaskScript = `
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
try{
 $p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
 $name='DCGamingSteamDnsRecovery.v2'
 $description='DCGaming Steam DNS recovery v2; owned policy cleanup only.'
 $existing=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
 if($existing){
  $classes=@($existing.Triggers | ForEach-Object {$_.CimClass.CimClassName})
  if(@($existing.Actions).Count -ne 1 -or $existing.Actions[0].Execute -ne $p.path -or $existing.Actions[0].Arguments -ne '--recover-dns' -or $existing.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or $existing.Description -ne $description -or $classes.Count -ne 2 -or $classes -notcontains 'MSFT_TaskBootTrigger' -or $classes -notcontains 'MSFT_TaskLogonTrigger' -or -not $existing.Settings.Enabled){throw 'foreign-task'}
 }else{
  $action=New-ScheduledTaskAction -Execute $p.path -Argument '--recover-dns'
  $triggers=@((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -AtLogOn))
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName $name -TaskPath '\' -Description $description -Action $action -Trigger $triggers -Settings $settings -User 'SYSTEM' -RunLevel Highest -ErrorAction Stop | Out-Null
 }
 @{code='ok'} | ConvertTo-Json -Compress
}catch{@{code='dns-recovery-unavailable'} | ConvertTo-Json -Compress;exit 1}
`

func prepareDNSRecovery(ctx context.Context, store dnsJournalStore, journal *steamdns.Journal) error {
	path, err := protectedRecoveryExecutable(store.directory)
	if err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]string{"path": path})
	output, err := steamdns.RunScript(ctx, strings.ReplaceAll(recoveryTaskScript, "__PAYLOAD__", base64.StdEncoding.EncodeToString(payload)))
	var result struct {
		Code string `json:"code"`
	}
	if err != nil || json.Unmarshal(output, &result) != nil || result.Code != "ok" {
		return errors.New("dns-recovery-unavailable")
	}
	sd, err := windows.SecurityDescriptorFromString(winutil.AdminOnlySDDL)
	if err != nil {
		return err
	}
	sa := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: sd}
	name, _ := windows.UTF16PtrFromString("Global\\DCGamingSteamDnsGuardReady-" + journal.Tag)
	event, err := windows.CreateEvent(&sa, 1, 0, name)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(event)
	command := exec.Command(path, "--dns-guardian", "--parent", strconv.FormatUint(uint64(journal.ParentPID), 10), "--created", strconv.FormatUint(journal.ParentCreated, 10), "--tag", journal.Tag)
	command.SysProcAttr = &windows.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err = command.Start(); err != nil {
		return err
	}
	go func() { _ = command.Wait() }()
	wait, err := windows.WaitForSingleObject(event, 5000)
	if err != nil || wait != windows.WAIT_OBJECT_0 {
		return errors.New("dns-guardian-unavailable")
	}
	return ctx.Err()
}

func protectedRecoveryExecutable(directory string) (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	bytes, err := os.ReadFile(executable)
	if err != nil {
		return "", err
	}
	path := filepath.Join(directory, "recovery.exe")
	want := sha256.Sum256(bytes)
	if info, err := os.Lstat(path); err == nil {
		name, _ := windows.UTF16PtrFromString(path)
		attrs, err := windows.GetFileAttributes(name)
		owned, ownErr := winutil.OwnedByAdmins(path)
		if err != nil || ownErr != nil || !owned || attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 || !info.Mode().IsRegular() {
			return "", errors.New("untrusted recovery executable")
		}
		if current, err := os.ReadFile(path); err == nil && sha256.Sum256(current) == want {
			return path, nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	file, err := os.CreateTemp(directory, "recovery-*.tmp")
	if err != nil {
		return "", err
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	if err = secureDNSFile(temporary); err != nil {
		file.Close()
		return "", err
	}
	if _, err = file.Write(bytes); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return "", err
	}
	if closeErr != nil {
		return "", closeErr
	}
	from, _ := windows.UTF16PtrFromString(temporary)
	to, _ := windows.UTF16PtrFromString(path)
	if err = replaceDNSFile(from, to); err != nil {
		return "", err
	}
	return path, nil
}

func runDNSGuardian(parent uint32, created uint64, tag string) error {
	if !winutil.IsAdmin() || !steamdns.ValidJournal(&steamdns.Journal{Version: 2, Tag: tag, ParentPID: parent, ParentCreated: created}) {
		return errors.New("invalid guardian")
	}
	store := dnsJournalStore{dnsDirectory()}
	if !safeOwnedDirectory(store.directory) {
		return steamdns.ErrRuntimeUntrusted
	}
	journal, err := store.Read()
	if err != nil || journal == nil || journal.Tag != tag || journal.ParentPID != parent || journal.ParentCreated != created {
		return steamdns.ErrRecoveryPending
	}
	handle, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, parent)
	if err != nil {
		return recoverDNS(tag)
	}
	defer windows.CloseHandle(handle)
	if !sameParent(handle, created) {
		return recoverDNS(tag)
	}
	name, _ := windows.UTF16PtrFromString("Global\\DCGamingSteamDnsGuardReady-" + tag)
	event, err := windows.OpenEvent(windows.EVENT_MODIFY_STATE, false, name)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(event)
	if err = windows.SetEvent(event); err != nil {
		return err
	}
	for {
		if !sameParent(handle, created) {
			return recoverDNS(tag)
		}
		current, err := store.Read()
		if err == nil && (current == nil || current.Tag != tag) {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func recoverDNS(tag string) error {
	if !winutil.IsAdmin() {
		return errors.New("elevation required")
	}
	store := dnsJournalStore{dnsDirectory()}
	if _, err := os.Lstat(store.directory); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if !safeOwnedDirectory(store.directory) {
		return steamdns.ErrRecoveryPending
	}
	// A running helper owns cleanup. A late old guardian cannot remove the
	// next session's rule: both mutex and journal tag are checked.
	sd, err := windows.SecurityDescriptorFromString(winutil.AdminOnlySDDL)
	if err != nil {
		return err
	}
	sa := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: sd}
	name, _ := windows.UTF16PtrFromString(`Global\DCGamingSteamDpiHelper.v1`)
	mutex, err := windows.CreateMutex(&sa, true, name)
	if mutex != 0 {
		defer windows.CloseHandle(mutex)
	}
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return nil
	}
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	return steamdns.Recover(ctx, store, steamdns.WindowsPolicy{}, tag)
}

func dnsErrorCode(err error) string {
	return steamdns.FailureCode(err)
}

// The authenticated normal helper already holds the global mutex. Explicit
// Stop can recover a previous crashed session without creating a new relay.
func recoverDNSJournal(ctx context.Context) error {
	store := dnsJournalStore{dnsDirectory()}
	if _, err := os.Lstat(store.directory); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if !safeOwnedDirectory(store.directory) {
		return steamdns.Operation("journal-directory", steamdns.ErrRuntimeUntrusted)
	}
	return steamdns.Recover(ctx, store, steamdns.WindowsPolicy{}, "")
}

// New files need an explicit admin owner as well as the protected parent DACL;
// an elevated token's default owner is not assumed to be Administrators.
func secureDNSFile(path string) error {
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	handle, err := windows.CreateFile(name, windows.READ_CONTROL|windows.WRITE_DAC|windows.WRITE_OWNER|windows.FILE_READ_ATTRIBUTES,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, windows.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(handle)
	var info windows.ByHandleFileInformation
	if err = windows.GetFileInformationByHandle(handle, &info); err != nil {
		return err
	}
	if info.FileAttributes&(windows.FILE_ATTRIBUTE_REPARSE_POINT|windows.FILE_ATTRIBUTE_DIRECTORY) != 0 {
		return errors.New("untrusted DNS file")
	}
	sd, err := windows.SecurityDescriptorFromString("O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)")
	if err != nil {
		return err
	}
	dacl, _, err := sd.DACL()
	if err != nil {
		return err
	}
	owner, _, err := sd.Owner()
	if err != nil {
		return err
	}
	return windows.SetSecurityInfo(handle, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION|windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, owner, nil, dacl, nil)
}
