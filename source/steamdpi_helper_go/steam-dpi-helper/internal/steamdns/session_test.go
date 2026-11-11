package steamdns

import (
	"context"
	"errors"
	"testing"
)

type memoryJournal struct {
	journal     *Journal
	writes      int
	failWrite   int
	deleteError error
}

func (s *memoryJournal) Read() (*Journal, error) {
	if s.journal == nil {
		return nil, nil
	}
	copy := *s.journal
	return &copy, nil
}
func (s *memoryJournal) Write(j *Journal) error {
	s.writes++
	if s.writes == s.failWrite {
		return errors.New("disk")
	}
	copy := *j
	s.journal = &copy
	return nil
}
func (s *memoryJournal) Delete() error {
	if s.deleteError != nil {
		return s.deleteError
	}
	s.journal = nil
	return nil
}

type fakeListener struct{ closed bool }

func (l *fakeListener) Healthy() bool { return !l.closed }
func (l *fakeListener) Close()        { l.closed = true }

type fakePolicy struct {
	rules                                []Rule
	applyCalls, removeCalls              int
	applyError, removeError, verifyError error
}

func (p *fakePolicy) Read(context.Context) ([]Rule, error) { return p.rules, nil }
func (p *fakePolicy) Apply(_ context.Context, tag string) (string, error) {
	p.applyCalls++
	name := "{12345678-1234-1234-1234-123456789012}"
	p.rules = append(p.rules, Rule{Name: name, Comment: "DCGamingSteamDns:" + tag, Namespaces: Namespaces(), Servers: []string{"127.0.0.1"}})
	return name, p.applyError
}
func (p *fakePolicy) Remove(_ context.Context, j *Journal) error {
	p.removeCalls++
	if p.removeError != nil {
		return p.removeError
	}
	var keep []Rule
	for _, rule := range p.rules {
		if rule.Comment == "DCGamingSteamDns:"+j.Tag || j.RuleName != "" && rule.Name == j.RuleName {
			if !EqualNamespaces(rule.Namespaces) || len(rule.Servers) != 1 || rule.Servers[0] != "127.0.0.1" || rule.Comment != "DCGamingSteamDns:"+j.Tag {
				return ErrPolicyConflict
			}
		} else {
			keep = append(keep, rule)
		}
	}
	p.rules = keep
	return nil
}
func (p *fakePolicy) Verify(context.Context, *Journal) error  { return p.verifyError }
func (p *fakePolicy) Refresh(context.Context, *Journal) error { return p.verifyError }
func makeSession(store *memoryJournal, policy *fakePolicy, listener *fakeListener, recoveryError error) *Session {
	return NewSession(store, policy, func() (Listener, error) { return listener, nil }, func(context.Context, *Journal) error { return recoveryError }, 123, 456)
}

func TestSessionAddsOnlyOwnedSteamPolicyAndRestoresForeignPolicy(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{rules: []Rule{{Name: "foreign", Namespaces: []string{".nestg.cloud"}, Servers: []string{"192.168.0.1"}}}}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	active, ready := s.State()
	if !active || !ready || len(policy.rules) != 2 {
		t.Fatal("not active")
	}
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !listener.closed || store.journal != nil || len(policy.rules) != 1 || policy.rules[0].Name != "foreign" {
		t.Fatal("foreign state altered")
	}
}
func TestConflictingUserAndGroupPolicyNeverChangesDNS(t *testing.T) {
	for _, name := range []string{".", ".com", ".steampowered.com", "store.steampowered.com"} {
		store, policy, listener := &memoryJournal{}, &fakePolicy{rules: []Rule{{Namespaces: []string{name}, Servers: []string{"1.2.3.4"}}}}, &fakeListener{}
		s := makeSession(store, policy, listener, nil)
		if !errors.Is(s.Start(context.Background()), ErrPolicyConflict) || policy.applyCalls != 0 || store.journal != nil {
			t.Fatal(name)
		}
	}
}
func TestGuardianFailurePreventsPolicyApplication(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, errors.New("guardian"))
	if s.Start(context.Background()) == nil || policy.applyCalls != 0 || store.journal != nil || !listener.closed {
		t.Fatal("unprotected policy applied")
	}
}
func TestFailureBetweenApplyingPolicyAndSavingRuleIDRecoversByTag(t *testing.T) {
	store, policy, listener := &memoryJournal{failWrite: 2}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if s.Start(context.Background()) == nil || len(policy.rules) != 0 || store.journal != nil || !listener.closed {
		t.Fatal("orphan policy remained")
	}
}
func TestUnconfirmedCleanupRetainsListenerAndCanBeRetried(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{applyError: errors.New("partial apply"), removeError: errors.New("busy")}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if s.Start(context.Background()) == nil {
		t.Fatal("startup unexpectedly passed")
	}
	active, ready := s.State()
	if !active || ready || listener.closed || store.journal == nil {
		t.Fatal("lost cleanup ownership")
	}
	policy.removeError = nil
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	active, _ = s.State()
	if active || !listener.closed {
		t.Fatal("retry did not stop")
	}
}
func TestModifiedOwnedRuleIsPreservedInsteadOfOverwritten(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	policy.rules[0].Servers = []string{"9.9.9.9"}
	if s.Stop(context.Background()) == nil || listener.closed || store.journal == nil || policy.rules[0].Servers[0] != "9.9.9.9" {
		t.Fatal("user modification overwritten")
	}
}
func TestLateGuardianCannotRecoverNewSession(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := Recover(context.Background(), store, policy, "00000000000000000000000000000000"); err != nil {
		t.Fatal(err)
	}
	if store.journal == nil || len(policy.rules) != 1 || policy.removeCalls != 0 {
		t.Fatal("late guardian changed new session")
	}
}
func TestPreviousCrashRecoveryFailureRemainsPendingWithoutListener(t *testing.T) {
	store := &memoryJournal{journal: &Journal{Version: 2, Tag: "00000000000000000000000000000000", ParentPID: 123, ParentCreated: 456}}
	policy, listener := &fakePolicy{removeError: errors.New("policy unavailable")}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if s.Start(context.Background()) == nil {
		t.Fatal("recovery unexpectedly passed")
	}
	active, ready := s.State()
	if !active || ready || policy.applyCalls != 0 {
		t.Fatal("unconfirmed recovery reported off or applied new rule")
	}
	policy.removeError = nil
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	active, ready = s.State()
	if active || ready || store.journal != nil {
		t.Fatal("explicit retry did not clear recovery state")
	}
}

func TestTransientVerificationFailureCanRecoverWithoutRestartingRelay(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	policy.verifyError = ErrPolicyTimeout
	if err := s.Check(context.Background()); !errors.Is(err, ErrPolicyTimeout) {
		t.Fatal(err)
	}
	_, ready := s.State()
	if ready {
		t.Fatal("failed verification was reported ready")
	}
	policy.verifyError = nil
	if err := s.Start(context.Background()); err != nil {
		t.Fatal("transient error poisoned session:", err)
	}
	_, ready = s.State()
	if !ready || policy.applyCalls != 1 || listener.closed {
		t.Fatal("valid existing relay was not reused")
	}
}

func TestJournalDeletionFailureRetainsCauseAndRetryFinishesAfterRuleWasRemoved(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	store.deleteError = errors.New("temporary disk failure")
	err := s.Stop(context.Background())
	if FailureCode(err) != "dns-journal-delete-failed" || FailureStage(err) != "journal-delete" {
		t.Fatal(err)
	}
	if len(policy.rules) != 0 || store.journal == nil || listener.closed || !s.RecoveryPending() {
		t.Fatal("unconfirmed cleanup lost ownership")
	}
	store.deleteError = nil
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	active, _ := s.State()
	if active || !listener.closed || store.journal != nil || s.RecoveryPending() {
		t.Fatal("retry did not finish")
	}
}

func TestLostJournalUsesOnlyTheCurrentSessionsTrustedRule(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	store.journal = nil
	policy.rules = append(policy.rules, Rule{Name: "foreign", Namespaces: []string{".other.example"}, Servers: []string{"9.9.9.9"}})
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(policy.rules) != 1 || policy.rules[0].Name != "foreign" || !listener.closed {
		t.Fatal("lost journal left an owned rule or removed another rule")
	}
}

func TestChangedJournalTagCannotAuthorizeCleanupOfAnotherSession(t *testing.T) {
	store, policy, listener := &memoryJournal{}, &fakePolicy{}, &fakeListener{}
	s := makeSession(store, policy, listener, nil)
	if err := s.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	store.journal.Tag = "00000000000000000000000000000000"
	if err := s.Stop(context.Background()); !errors.Is(err, ErrPolicyConflict) {
		t.Fatal(err)
	}
	if policy.removeCalls != 0 || listener.closed {
		t.Fatal("changed journal was used for cleanup")
	}
}

func TestCleanupPreservesUnderlyingPolicyErrorInsteadOfMaskingIt(t *testing.T) {
	for _, failure := range []error{ErrPolicyAccess, ErrPolicyQuery, ErrPolicyRemove, ErrPolicyFlush, ErrPolicyCleanup, ErrPolicyConfirmation} {
		t.Run(failure.Error(), func(t *testing.T) {
			store := &memoryJournal{journal: &Journal{Version: 2, Tag: "00000000000000000000000000000000", ParentPID: 1, ParentCreated: 1}}
			policy := &fakePolicy{removeError: failure}
			err := Recover(context.Background(), store, policy, "")
			if !errors.Is(err, ErrRecoveryPending) || FailureCode(err) != failure.Error() || FailureStage(err) != "policy-remove" || store.journal == nil {
				t.Fatal("cleanup lost its cause or journal:", err)
			}
		})
	}
}
func TestFailedDNSFactoryHasNoPersistentEffect(t *testing.T) {
	store, policy := &memoryJournal{}, &fakePolicy{}
	s := NewSession(store, policy, func() (Listener, error) { return nil, errors.New("dns-upstream-unavailable") }, func(context.Context, *Journal) error { t.Fatal("recovery should not start"); return nil }, 123, 456)
	if s.Start(context.Background()) == nil || store.journal != nil || policy.applyCalls != 0 {
		t.Fatal("unhealthy upstream changed policy")
	}
}
func TestJournalValidationRejectsPathsMissingIdentityAndInvalidVersion(t *testing.T) {
	for _, j := range []*Journal{nil, {Version: 1, Tag: "00000000000000000000000000000000", ParentPID: 1, ParentCreated: 1}, {Version: 2, Tag: "../x", ParentPID: 1, ParentCreated: 1}, {Version: 2, Tag: "00000000000000000000000000000000"}, {Version: 2, Tag: "00000000000000000000000000000000", ParentPID: 1, ParentCreated: 1, RuleName: "command"}} {
		if ValidJournal(j) {
			t.Fatal("invalid journal accepted")
		}
	}
}
