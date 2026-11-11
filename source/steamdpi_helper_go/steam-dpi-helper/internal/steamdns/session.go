// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"regexp"
	"sort"
	"strings"
	"sync"
)

var ErrPolicyConflict = errors.New("dns-policy-conflict")
var ErrRecoveryPending = errors.New("dns-recovery-pending")
var ErrListenerBusy = errors.New("dns-listener-busy")
var tagPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)

type Rule struct {
	Name       string   `json:"name"`
	Comment    string   `json:"comment"`
	Namespaces []string `json:"namespaces"`
	Servers    []string `json:"servers"`
	Effective  bool     `json:"effective"`
}
type Journal struct {
	Version       int    `json:"version"`
	Tag           string `json:"tag"`
	RuleName      string `json:"ruleName"`
	ParentPID     uint32 `json:"parentPid"`
	ParentCreated uint64 `json:"parentCreated"`
}
type JournalStore interface {
	Read() (*Journal, error)
	Write(*Journal) error
	Delete() error
}
type Policy interface {
	Read(context.Context) ([]Rule, error)
	Apply(context.Context, string) (string, error)
	Remove(context.Context, *Journal) error
	Verify(context.Context, *Journal) error
	Refresh(context.Context, *Journal) error
}
type Listener interface {
	Healthy() bool
	Close()
}
type Session struct {
	mu              sync.Mutex
	store           JournalStore
	policy          Policy
	startListener   func() (Listener, error)
	prepareRecovery func(context.Context, *Journal) error
	journal         *Journal
	listener        Listener
	parentPID       uint32
	parentCreated   uint64
	ready           bool
	recoveryPending bool
}

func NewSession(store JournalStore, policy Policy, listener func() (Listener, error), recovery func(context.Context, *Journal) error, pid uint32, created uint64) *Session {
	return &Session{store: store, policy: policy, startListener: listener, prepareRecovery: recovery, parentPID: pid, parentCreated: created}
}

func overlaps(namespace, domain string) bool {
	name := strings.TrimPrefix(strings.ToLower(strings.TrimSuffix(namespace, ".")), ".")
	return name == "" || name == domain || strings.HasSuffix(domain, "."+name) || strings.HasSuffix(name, "."+domain)
}
func EqualNamespaces(actual []string) bool {
	left, right := append([]string(nil), actual...), Namespaces()
	sort.Strings(left)
	sort.Strings(right)
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
func ValidJournal(journal *Journal) bool {
	return journal != nil && journal.Version == 2 && tagPattern.MatchString(journal.Tag) && journal.ParentPID != 0 && journal.ParentCreated != 0 &&
		(journal.RuleName == "" || regexp.MustCompile(`^\{[a-fA-F0-9-]{36}\}$`).MatchString(journal.RuleName))
}

// Recovery deletes only our exact tagged rule. A modified rule is a conflict,
// not permission to restore an old snapshot over another application's policy.
func Recover(ctx context.Context, store JournalStore, policy Policy, expectedTag string) error {
	return recoverJournal(ctx, store, policy, expectedTag, nil)
}
func recoverJournal(ctx context.Context, store JournalStore, policy Policy, expectedTag string, fallback *Journal) error {
	journal, err := store.Read()
	if err != nil {
		return Operation("journal-read", err)
	}
	if journal == nil {
		journal = fallback
	}
	if journal == nil {
		return nil
	}
	if fallback != nil && journal.Tag != fallback.Tag {
		return Operation("journal-read", ErrPolicyConflict)
	}
	if !ValidJournal(journal) {
		return Operation("journal-read", ErrJournalInvalid)
	}
	if expectedTag != "" && journal.Tag != expectedTag {
		return nil
	}
	if err := policy.Remove(ctx, journal); err != nil {
		return Operation("policy-remove", errors.Join(ErrRecoveryPending, err))
	}
	if err := store.Delete(); err != nil {
		return Operation("journal-delete", errors.Join(ErrRecoveryPending, ErrJournalDelete, err))
	}
	return nil
}

func (s *Session) Start(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.listener != nil {
		if !s.listener.Healthy() {
			return ErrRecoveryPending
		}
		if err := s.policy.Verify(ctx, s.journal); err != nil {
			s.ready = false
			return Operation("policy-verify", err)
		}
		s.ready = true
		return nil
	}
	if err := Recover(ctx, s.store, s.policy, ""); err != nil {
		s.recoveryPending = true
		return err
	}
	s.recoveryPending = false
	rules, err := s.policy.Read(ctx)
	if err != nil {
		return Operation("policy-read", err)
	}
	for _, rule := range rules {
		for _, namespace := range rule.Namespaces {
			for _, domain := range Domains {
				if overlaps(namespace, domain) {
					return ErrPolicyConflict
				}
			}
		}
	}
	listener, err := s.startListener()
	if err != nil {
		return err
	}
	s.listener = listener
	var nonce [16]byte
	if _, err = rand.Read(nonce[:]); err != nil {
		listener.Close()
		s.listener = nil
		return err
	}
	s.journal = &Journal{Version: 2, Tag: hex.EncodeToString(nonce[:]), ParentPID: s.parentPID, ParentCreated: s.parentCreated}
	if err = s.store.Write(s.journal); err != nil {
		listener.Close()
		s.listener = nil
		s.journal = nil
		return Operation("journal-write", errors.Join(ErrJournalWrite, err))
	}
	if err = Operation("guardian-prepare", s.prepareRecovery(ctx, s.journal)); err == nil {
		s.journal.RuleName, err = s.policy.Apply(ctx, s.journal.Tag)
		err = Operation("policy-apply", err)
		if err == nil {
			err = Operation("journal-write", s.store.Write(s.journal))
		}
		if err == nil {
			err = Operation("policy-verify", s.policy.Verify(ctx, s.journal))
		}
	}
	if err != nil {
		// Cleanup gets its own lifetime when startup was cancelled.
		cleanup, cancel := cleanupContext()
		defer cancel()
		if restoreErr := recoverJournal(cleanup, s.store, s.policy, s.journal.Tag, s.journal); restoreErr != nil {
			s.recoveryPending = true
			// The failed cleanup cause is the actionable one for the next explicit Stop.
			return errors.Join(restoreErr, err)
		}
		listener.Close()
		s.listener = nil
		s.journal = nil
		return err
	}
	s.ready = true
	return nil
}

func (s *Session) Stop(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := recoverJournal(ctx, s.store, s.policy, "", s.journal); err != nil {
		s.ready = false
		s.recoveryPending = true
		return err
	}
	if s.listener != nil {
		s.listener.Close()
	}
	s.listener = nil
	s.journal = nil
	s.ready = false
	s.recoveryPending = false
	return nil
}
func (s *Session) State() (active, ready bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.listener != nil || s.recoveryPending, s.ready && s.listener != nil && s.listener.Healthy()
}
func (s *Session) RecoveryPending() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.recoveryPending
}
func (s *Session) Check(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.listener == nil {
		return nil
	}
	if !s.listener.Healthy() {
		s.ready = false
		return ErrRecoveryPending
	}
	if err := s.policy.Verify(ctx, s.journal); err != nil {
		s.ready = false
		return Operation("policy-verify", err)
	}
	s.ready = true
	return nil
}

func (s *Session) Refresh(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.listener == nil || !s.listener.Healthy() {
		s.ready = false
		return ErrRecoveryPending
	}
	if err := s.policy.Refresh(ctx, s.journal); err != nil {
		s.ready = false
		return Operation("policy-refresh", err)
	}
	s.ready = true
	return nil
}
