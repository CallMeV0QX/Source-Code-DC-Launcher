#include "RentalIdentity.h"

namespace RentalIdentity {
namespace {
// As with the existing pinned-runtime watchers, keep synchronization alive
// through Windows process teardown. No worker or destructor runs in DllMain.
Tracker& RuntimeTracker() {
    static auto* tracker = new Tracker;
    return *tracker;
}
}

bool Tracker::IsIndividualSteamId(std::uint64_t steamId) {
    // Public universe, individual account, desktop instance, nonzero AccountID.
    return (steamId >> 56) == 1 && ((steamId >> 52) & 0xf) == 1 &&
           ((steamId >> 32) & 0xfffff) == 1 && (steamId & 0xffffffffu) != 0;
}

Snapshot Tracker::Capture() const {
    std::lock_guard lock(mutex_);
    return snapshot_;
}

void Tracker::InvalidateLocked(State state) {
    if (snapshot_.state == State::Authenticated) {
        if (retiredSessions_.size() >= 32768) ambiguousAttempt_ = true;
        else retiredSessions_.emplace(snapshot_.steamId, snapshot_.steamSessionId);
    }
    ++snapshot_.generation;
    snapshot_.state = state;
    snapshot_.steamId = 0;
    snapshot_.steamSessionId = 0;
    expectedSteamId_ = 0;
}

void Tracker::SetObserverAvailability(bool sendInstalled, bool receiveInstalled) {
    std::lock_guard lock(mutex_);
    const bool ready = sendInstalled && receiveInstalled;
    if (snapshot_.observerReady == ready) return;
    if (!ready && snapshot_.state == State::Pending) ambiguousAttempt_ = true;
    snapshot_.observerReady = ready;
    InvalidateLocked(State::Unknown);
}

void Tracker::BeginLogon(std::uint64_t expectedSteamId) {
    std::lock_guard lock(mutex_);
    // The existing hook has no proven per-attempt request correlation. An
    // overlapping request could receive an old same-account reply; do not
    // guess a socket layout or treat that reply as a new proof. A fresh Steam
    // process is required after ambiguity (ordinary terminal Guard failures
    // leave Unknown and permit a later non-overlapping attempt).
    if (snapshot_.state == State::Pending) ambiguousAttempt_ = true;
    InvalidateLocked(snapshot_.observerReady && !ambiguousAttempt_ ? State::Pending : State::Unknown);
    // Only a correlation hint; never permission to load rental data.
    if (IsIndividualSteamId(expectedSteamId)) expectedSteamId_ = expectedSteamId;
}

void Tracker::SignOut() {
    std::lock_guard lock(mutex_);
    if (snapshot_.state == State::Pending) ambiguousAttempt_ = true;
    InvalidateLocked(State::SignedOut);
}

void Tracker::ObserveLogonResponse(std::int32_t result, bool hasResult,
                                  std::uint64_t steamId, std::int32_t sessionId) {
    std::lock_guard lock(mutex_);
    // Late replies after logout, unsolicited replies and duplicate replies do
    // not reauthorize an account. Every proof belongs to an observed login.
    if (!snapshot_.observerReady || ambiguousAttempt_ || snapshot_.state != State::Pending) return;
    if (!hasResult || result != 1 || !IsIndividualSteamId(steamId) ||
        sessionId == 0 || retiredSessions_.count({steamId, sessionId}) ||
        (expectedSteamId_ != 0 && expectedSteamId_ != steamId)) {
        InvalidateLocked(State::Unknown);
        return;
    }
    ++snapshot_.generation;
    snapshot_.state = State::Authenticated;
    snapshot_.steamId = steamId;
    snapshot_.steamSessionId = sessionId;
    expectedSteamId_ = 0;
}

void Tracker::ObserveAuthenticatedHeader(std::uint64_t steamId, std::int32_t sessionId,
                                        bool hasSteamId, bool hasSessionId) {
    std::lock_guard lock(mutex_);
    if (snapshot_.state != State::Authenticated) return;
    // Generic traffic can invalidate an old proof, but cannot grant a new one.
    // Some service headers omit identity/session, so absence is not a mismatch.
    if ((hasSteamId && steamId != 0 && steamId != snapshot_.steamId) ||
        (hasSessionId && sessionId != 0 && sessionId != snapshot_.steamSessionId)) {
        InvalidateLocked(State::Unknown);
    }
}

Snapshot Capture() { return RuntimeTracker().Capture(); }
void SetObserverAvailability(bool send, bool receive) {
    RuntimeTracker().SetObserverAvailability(send, receive);
}
void BeginLogon(std::uint64_t steamId) { RuntimeTracker().BeginLogon(steamId); }
void SignOut() { RuntimeTracker().SignOut(); }
void ObserveLogonResponse(std::int32_t result, bool hasResult,
                          std::uint64_t steamId, std::int32_t sessionId) {
    RuntimeTracker().ObserveLogonResponse(result, hasResult, steamId, sessionId);
}
void ObserveAuthenticatedHeader(std::uint64_t steamId, std::int32_t sessionId,
                                bool hasSteamId, bool hasSessionId) {
    RuntimeTracker().ObserveAuthenticatedHeader(steamId, sessionId, hasSteamId, hasSessionId);
}
} // namespace RentalIdentity
