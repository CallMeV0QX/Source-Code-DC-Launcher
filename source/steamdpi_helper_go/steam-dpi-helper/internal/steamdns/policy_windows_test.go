package steamdns

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"golang.org/x/sys/windows"
	"path/filepath"
	"strings"
	"testing"
)

func TestEmbeddedNRPTScriptParsesWithoutExecutingIt(t *testing.T) {
	payload := base64.StdEncoding.EncodeToString([]byte(policyScript))
	script := "$text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + payload + "')); $tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors); if($errors.Count -gt 0){exit 1}; 'ok'"
	output, err := RunScript(context.Background(), script)
	if err != nil || string(output) != "ok" {
		t.Fatalf("policy syntax: %v", err)
	}
}

func TestProductionPolicyRemovalWithStubCmdletsPreservesForeignRulesAndFlushesRetry(t *testing.T) {
	for _, fixture := range []struct{ name, mode, want string }{
		{"owned", "owned", "ok"}, {"retry-after-remove", "missing", "ok"},
		{"modified", "modified", "dns-policy-conflict"}, {"access-denied", "denied", "dns-policy-access-denied"},
		{"query-error", "query-error", "dns-policy-query-failed"},
		{"remove-error", "remove-error", "dns-policy-remove-failed"},
		{"cache-error", "cache-error", "dns-cache-flush-failed"},
		{"verification-error", "verification-error", "dns-cleanup-check-failed"},
		{"rule-remains", "rule-remains", "dns-cleanup-check-failed"},
		{"unexpected-confirmation", "unexpected-confirmation", "dns-policy-confirmation-required"},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			payload, _ := json.Marshal(map[string]any{"operation": "remove", "tag": "00000000000000000000000000000000",
				"ruleName": "{12345678-1234-1234-1234-123456789012}", "namespaces": Namespaces()})
			prefix := `
$script:payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__DATA__')) | ConvertFrom-Json
$script:mode='__MODE__';$script:flushed=0;$script:queries=0
$script:rules=@([pscustomobject]@{Name='foreign';Comment='other';Namespace=@('.other.example');NameServers='9.9.9.9'})
if($script:mode -ne 'missing'){
 $servers=if($script:mode -eq 'modified'){'9.9.9.9'}else{'127.0.0.1'}
 $script:rules+=([pscustomobject]@{Name=$script:payload.ruleName;Comment=('DCGamingSteamDns:'+$script:payload.tag);Namespace=@($script:payload.namespaces);NameServers=$servers})
}
function Get-DnsClientNrptRule {
 $script:queries++
 if($script:mode -eq 'query-error'){throw 'fixture read failure'}
 if($script:mode -eq 'verification-error' -and $script:queries -gt 1){throw 'fixture verification failure'}
 $script:rules
}
function Remove-DnsClientNrptRule {
 [CmdletBinding(SupportsShouldProcess=$true)]
 param([string]$Name,[switch]$Force)
 if($Name -eq 'foreign'){throw 'test-foreign-removal'}
 if($script:mode -eq 'modified'){throw 'test-modified-removal'}
 if($script:mode -eq 'denied'){throw [UnauthorizedAccessException]::new('fixture denied')}
 if($script:mode -eq 'remove-error'){throw 'fixture removal failure'}
 # Confirm:false does not suppress a provider's independent confirmation.
 if(-not $Force -or $script:mode -eq 'unexpected-confirmation'){
  if(-not $PSCmdlet.ShouldContinue('Remove fixture NRPT rule?','Confirm')){return}
 }
 if($script:mode -eq 'rule-remains'){return}
 $script:rules=@($script:rules | Where-Object {$_.Name -ne $Name})
}
function Clear-DnsClientCache {
 if($script:mode -eq 'cache-error'){throw 'fixture cache flush failure'}
 if($script:mode -eq 'rule-remains'){return}
 if($script:rules.Count -ne 1 -or $script:rules[0].Name -ne 'foreign'){throw 'test-rules-remain'}
 $script:flushed++
}
`
			prefix = strings.ReplaceAll(strings.ReplaceAll(prefix, "__DATA__", base64.StdEncoding.EncodeToString(payload)), "__MODE__", fixture.mode)
			script := prefix + strings.ReplaceAll(policyScript, "__PAYLOAD__", base64.StdEncoding.EncodeToString(payload))
			if fixture.want == "ok" {
				script += "\nif($script:flushed -ne 1){throw 'test-cache-not-flushed'}"
			}
			output, err := RunScript(context.Background(), script)
			var result policyResult
			if json.Unmarshal(output, &result) != nil || result.Code != fixture.want || (fixture.want == "ok" && err != nil) {
				t.Fatalf("policy result: code=%s err=%v output=%s", result.Code, err, output)
			}
		})
	}
}

func TestCancelledPolicyVerificationReturnsTimeoutWithoutReadingWindowsPolicy(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := runPolicy(ctx, "verify", &Journal{Version: 2, Tag: "00000000000000000000000000000000", ParentPID: 1, ParentCreated: 1})
	if !errors.Is(err, ErrPolicyTimeout) {
		t.Fatal(err)
	}
}

func TestElevatedOperationsExcludeUserModuleSearchPaths(t *testing.T) {
	t.Setenv("PSModulePath", `C:\Users\Public\untrusted`)
	directory, err := windows.GetSystemDirectory()
	if err != nil {
		t.Fatal(err)
	}
	output, err := RunScript(context.Background(), "[Console]::Write($env:PSModulePath)")
	if err != nil || string(output) != filepath.Join(directory, "WindowsPowerShell", "v1.0", "Modules") {
		t.Fatal("untrusted module search path inherited")
	}
}
