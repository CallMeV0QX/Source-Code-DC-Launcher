package main

import (
	"context"
	"encoding/base64"
	"github.com/hashcott/ghostline/internal/steamdns"
	"testing"
)

func TestRecoveryTaskScriptParsesWithoutRegisteringTask(t *testing.T) {
	payload := base64.StdEncoding.EncodeToString([]byte(recoveryTaskScript))
	script := "$text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + payload + "')); $tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors); if($errors.Count -gt 0){exit 1}; 'ok'"
	output, err := steamdns.RunScript(context.Background(), script)
	if err != nil || string(output) != "ok" {
		t.Fatalf("task syntax: %v", err)
	}
}
