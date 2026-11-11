// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"context"
	"errors"
	"os"
)

var ErrJournalUntrusted = errors.New("dns-journal-untrusted")
var ErrJournalInvalid = errors.New("dns-journal-invalid")
var ErrJournalWrite = errors.New("dns-journal-write-failed")
var ErrJournalDelete = errors.New("dns-journal-delete-failed")
var ErrPolicyAccess = errors.New("dns-policy-access-denied")
var ErrPolicyTimeout = errors.New("dns-policy-timeout")
var ErrPolicyMissing = errors.New("dns-policy-missing")
var ErrPolicyQuery = errors.New("dns-policy-query-failed")
var ErrPolicyRemove = errors.New("dns-policy-remove-failed")
var ErrPolicyFlush = errors.New("dns-cache-flush-failed")
var ErrPolicyCleanup = errors.New("dns-cleanup-check-failed")
var ErrPolicyConfirmation = errors.New("dns-policy-confirmation-required")
var ErrRuntimeUntrusted = errors.New("dns-runtime-untrusted")

type OperationError struct {
	Stage string
	Err   error
}

func (e *OperationError) Error() string { return e.Stage + ": " + e.Err.Error() }
func (e *OperationError) Unwrap() error { return e.Err }
func Operation(stage string, err error) error {
	if err == nil {
		return nil
	}
	return &OperationError{Stage: stage, Err: err}
}
func FailureStage(err error) string {
	var operation *OperationError
	if errors.As(err, &operation) {
		return operation.Stage
	}
	return "dns"
}

// Never return raw PowerShell/OS messages over IPC. Specific causes take priority
// over the retained recovery ownership marker in errors.Join.
func FailureCode(err error) string {
	for _, item := range []error{ErrPolicyConflict, ErrJournalUntrusted, ErrJournalInvalid, ErrRuntimeUntrusted,
		ErrPolicyAccess, ErrPolicyTimeout, ErrPolicyMissing, ErrPolicyQuery, ErrPolicyRemove,
		ErrPolicyFlush, ErrPolicyCleanup, ErrPolicyConfirmation} {
		if errors.Is(err, item) {
			return item.Error()
		}
	}
	if errors.Is(err, os.ErrPermission) {
		return ErrPolicyAccess.Error()
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return ErrPolicyTimeout.Error()
	}
	for _, item := range []error{ErrJournalWrite, ErrJournalDelete, ErrListenerBusy} {
		if errors.Is(err, item) {
			return item.Error()
		}
	}
	// Wrapped policy failures must not be reduced to recovery-pending.
	for _, code := range []string{"dns-policy-unavailable", "dns-recovery-unavailable", "dns-guardian-unavailable", "dns-upstream-unavailable"} {
		if containsCode(err, code) {
			return code
		}
	}
	if errors.Is(err, ErrRecoveryPending) {
		return ErrRecoveryPending.Error()
	}
	return "dns-unavailable"
}
func containsCode(err error, code string) bool {
	if err == nil {
		return false
	}
	if err.Error() == code {
		return true
	}
	if children, ok := err.(interface{ Unwrap() []error }); ok {
		for _, child := range children.Unwrap() {
			if containsCode(child, code) {
				return true
			}
		}
	} else if child := errors.Unwrap(err); child != nil {
		return containsCode(child, code)
	}
	return false
}
