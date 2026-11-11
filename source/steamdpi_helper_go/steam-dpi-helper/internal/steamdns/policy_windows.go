// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf16"

	"github.com/hashcott/ghostline/internal/winutil"

	"golang.org/x/sys/windows"
)

type WindowsPolicy struct{}
type policyResult struct {
	Code  string `json:"code"`
	Name  string `json:"name"`
	Rules []Rule `json:"rules"`
}

const policyScript = `
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$failureCode='dns-policy-unavailable'
try {
 if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw 'restricted' }
 $p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
 $failureCode='dns-policy-query-failed'
 $configured=@(Get-DnsClientNrptRule -ErrorAction Stop)
 $failureCode='dns-policy-unavailable'
 if ($p.operation -eq 'read') {
  $rules=@()
  foreach($r in $configured){$rules+=@{name=$r.Name;comment=$r.Comment;namespaces=@($r.Namespace);servers=@(($r.NameServers -join ',') -split '[,; ]+' | Where-Object {$_});effective=$false}}
  foreach($r in @(Get-DnsClientNrptPolicy -Effective -ErrorAction Stop)){$rules+=@{name='';comment='';namespaces=@($r.Namespace);servers=@(($r.NameServers -join ',') -split '[,; ]+' | Where-Object {$_});effective=$true}}
  @{code='ok';rules=@($rules)} | ConvertTo-Json -Depth 5 -Compress
 } elseif($p.operation -eq 'apply') {
  $r=Add-DnsClientNrptRule -Namespace @($p.namespaces) -NameServers '127.0.0.1' -DisplayName 'DCGaming Steam DNS v2' -Comment ('DCGamingSteamDns:'+ $p.tag) -PassThru -ErrorAction Stop
  Clear-DnsClientCache -ErrorAction Stop
  @{code='ok';name=$r.Name} | ConvertTo-Json -Compress
 } elseif($p.operation -eq 'remove' -or $p.operation -eq 'verify' -or $p.operation -eq 'refresh') {
  $tag='DCGamingSteamDns:'+$p.tag
  $matches=@($configured | Where-Object {$_.Comment -eq $tag -or ($p.ruleName -and $_.Name -eq $p.ruleName)})
  foreach($r in $matches){
   $names=@($r.Namespace | Sort-Object)
   $expected=@($p.namespaces | Sort-Object)
   $servers=@(($r.NameServers -join ',') -split '[,; ]+' | Where-Object {$_})
   if($r.Comment -ne $tag -or $names.Count -ne $expected.Count -or (Compare-Object $names $expected) -or $servers.Count -ne 1 -or $servers[0] -ne '127.0.0.1'){throw 'ownership-conflict'}
  }
  if($p.operation -eq 'remove'){
   $failureCode='dns-policy-remove-failed'
   # Force suppresses the NRPT provider's own confirmation in NonInteractive mode;
   # Confirm:false alone only controls the common ShouldProcess prompt.
   # Ownership validation above remains mandatory before invoking this command.
   foreach($r in $matches){Remove-DnsClientNrptRule -Name $r.Name -Force -Confirm:$false -ErrorAction Stop}
   # Also flush on a retry after Remove succeeded but cache flush/journal deletion failed.
   $failureCode='dns-cache-flush-failed'
   Clear-DnsClientCache -ErrorAction Stop
   $failureCode='dns-cleanup-check-failed'
   if(@(Get-DnsClientNrptRule -ErrorAction Stop | Where-Object {$_.Comment -eq $tag -or ($p.ruleName -and $_.Name -eq $p.ruleName)}).Count -ne 0){throw 'cleanup-pending'}
  }else{
   if($matches.Count -ne 1){throw 'policy-missing'}
   $effective=@(Get-DnsClientNrptPolicy -Effective -ErrorAction Stop)
   foreach($name in @($p.namespaces)){
    $matching=@($effective | Where-Object {@($_.Namespace) -contains $name})
    if($matching.Count -ne 1){throw 'policy-ineffective'}
    $servers=@(($matching[0].NameServers -join ',') -split '[,; ]+' | Where-Object {$_})
    if($servers.Count -ne 1 -or $servers[0] -ne '127.0.0.1'){throw 'policy-ineffective'}
   }
   if($p.operation -eq 'refresh'){Clear-DnsClientCache -ErrorAction Stop}
  }
  @{code='ok'} | ConvertTo-Json -Compress
 }else{throw 'operation'}
} catch {
 $code=$failureCode
 if($_.Exception.Message -match 'ownership-conflict|policy-ineffective'){$code='dns-policy-conflict'}
 elseif($_.Exception.Message -eq 'policy-missing'){$code='dns-policy-missing'}
 elseif($_.Exception -is [UnauthorizedAccessException] -or $_.CategoryInfo.Category -in @('PermissionDenied','SecurityError')){$code='dns-policy-access-denied'}
 elseif($failureCode -eq 'dns-policy-remove-failed' -and ($_.FullyQualifiedErrorId -match '^PSInvalidOperationException(,|$)' -or $_.Exception.Message -match 'NonInteractive|Read and Prompt')){$code='dns-policy-confirmation-required'}
 @{code=$code} | ConvertTo-Json -Compress
 exit 1
}
`

func encodedScript(script string) string {
	units := utf16.Encode([]rune(script))
	bytes := make([]byte, len(units)*2)
	for index, unit := range units {
		binary.LittleEndian.PutUint16(bytes[index*2:], unit)
	}
	return base64.StdEncoding.EncodeToString(bytes)
}

type limitedOutput struct{ bytes.Buffer }

func (b *limitedOutput) Write(data []byte) (int, error) {
	if b.Len()+len(data) > 65536 {
		return 0, errors.New("policy output limit")
	}
	return b.Buffer.Write(data)
}

// Fixed embedded operations only; no arbitrary script, executable, namespace
// or remote PowerShell session is accepted over the launcher's pipe.
func RunScript(ctx context.Context, script string) ([]byte, error) {
	directory, err := windows.GetSystemDirectory()
	if err != nil {
		return nil, err
	}
	deadline, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	modulePath := filepath.Join(directory, "WindowsPowerShell", "v1.0", "Modules")
	// Windows PowerShell may prepend default module directories at startup;
	// reset the path inside the fixed script before any cmdlet auto-import.
	prologue := "$env:PSModulePath=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + base64.StdEncoding.EncodeToString([]byte(modulePath)) + "'));\n"
	cmd := exec.CommandContext(deadline, filepath.Join(directory, "WindowsPowerShell", "v1.0", "powershell.exe"), "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encodedScript(prologue+script))
	// Elevated PowerShell must not auto-import a user-planted DnsClient or
	// ScheduledTasks module, or inherit a CLR profiler/startup hook.
	for _, entry := range os.Environ() {
		key := strings.ToUpper(strings.SplitN(entry, "=", 2)[0])
		if key == "PSMODULEPATH" || key == "PSEXECUTIONPOLICYPREFERENCE" || strings.HasPrefix(key, "COR_") || strings.HasPrefix(key, "CORECLR_") || strings.HasPrefix(key, "COMPLUS_") || strings.HasPrefix(key, "DOTNET_") {
			continue
		}
		cmd.Env = append(cmd.Env, entry)
	}
	cmd.Env = append(cmd.Env, "PSModulePath="+modulePath)
	cmd.WaitDelay = 2 * time.Second
	cmd.SysProcAttr = &windows.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
	// A helper killed midway through Add/Remove must not leave an unowned
	// PowerShell process applying policy after the guardian starts recovery.
	job, err := winutil.NewKillOnCloseJob()
	if err != nil {
		return nil, err
	}
	defer job.Close()
	cmd.SysProcAttr.CreationFlags |= windows.CREATE_SUSPENDED
	var output limitedOutput
	cmd.Stdout = &output
	cmd.Stderr = io.Discard
	if err = cmd.Start(); err != nil {
		return nil, err
	}
	if err = job.Assign(cmd.Process); err == nil {
		err = winutil.ResumeProcess(uint32(cmd.Process.Pid))
	}
	if err != nil {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		return nil, err
	}
	err = cmd.Wait()
	if deadline.Err() != nil {
		return bytes.TrimSpace(output.Bytes()), deadline.Err()
	}
	return bytes.TrimSpace(output.Bytes()), err
}
func runPolicy(ctx context.Context, operation string, journal *Journal) (policyResult, error) {
	payload := map[string]any{"operation": operation, "namespaces": Namespaces()}
	if journal != nil {
		if !ValidJournal(journal) {
			return policyResult{}, ErrRecoveryPending
		}
		payload["tag"] = journal.Tag
		payload["ruleName"] = journal.RuleName
	}
	data, _ := json.Marshal(payload)
	script := bytes.ReplaceAll([]byte(policyScript), []byte("__PAYLOAD__"), []byte(base64.StdEncoding.EncodeToString(data)))
	output, runErr := RunScript(ctx, string(script))
	var result policyResult
	if errors.Is(runErr, context.DeadlineExceeded) || errors.Is(runErr, context.Canceled) || ctx.Err() != nil {
		return result, ErrPolicyTimeout
	}
	if json.Unmarshal(output, &result) != nil {
		return result, errors.New("dns-policy-unavailable")
	}
	for _, failure := range []error{ErrPolicyConflict, ErrPolicyAccess, ErrPolicyMissing,
		ErrPolicyQuery, ErrPolicyRemove, ErrPolicyFlush, ErrPolicyCleanup, ErrPolicyConfirmation} {
		if result.Code == failure.Error() {
			return result, failure
		}
	}
	if result.Code != "ok" || runErr != nil {
		return result, errors.New("dns-policy-unavailable")
	}
	return result, nil
}
func (WindowsPolicy) Read(ctx context.Context) ([]Rule, error) {
	result, err := runPolicy(ctx, "read", nil)
	return result.Rules, err
}
func (WindowsPolicy) Apply(ctx context.Context, tag string) (string, error) {
	result, err := runPolicy(ctx, "apply", &Journal{Version: 2, Tag: tag, ParentPID: 1, ParentCreated: 1})
	return result.Name, err
}
func (WindowsPolicy) Remove(ctx context.Context, journal *Journal) error {
	_, err := runPolicy(ctx, "remove", journal)
	return err
}
func (WindowsPolicy) Verify(ctx context.Context, journal *Journal) error {
	_, err := runPolicy(ctx, "verify", journal)
	return err
}

func (WindowsPolicy) Refresh(ctx context.Context, journal *Journal) error {
	_, err := runPolicy(ctx, "refresh", journal)
	return err
}
