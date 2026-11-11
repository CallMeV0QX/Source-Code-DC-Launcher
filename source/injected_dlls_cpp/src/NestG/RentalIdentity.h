#pragma once

#include <cstdint>
#include <mutex>
#include <set>
#include <utility>

// Identity is observed from the original Steam connection before Better modifies
// any IPC response. A selected account, VDF entry, registry value, game ticket or
// outbound logon request is never sufficient to authorize a rental source.
namespace RentalIdentity {

enum class State { Unknown, Pending, Authenticated, SignedOut };

struct Snapshot {
    State state = State::Unknown;
    std::uint64_t steamId = 0;
    std::uint64_t generation = 0;
    std::int32_t steamSessionId = 0;
    bool observerReady = false;
};

class Tracker {
public:
    Snapshot Capture() const;
    void SetObserverAvailability(bool sendInstalled, bool receiveInstalled);
    void BeginLogon(std::uint64_t expectedSteamId = 0);
    void SignOut();
    void ObserveLogonResponse(std::int32_t result, bool hasResult,
                              std::uint64_t steamId, std::int32_t sessionId);
    void ObserveAuthenticatedHeader(std::uint64_t steamId, std::int32_t sessionId,
                                    bool hasSteamId, bool hasSessionId);
    static bool IsIndividualSteamId(std::uint64_t steamId);

private:
    void InvalidateLocked(State state);
    mutable std::mutex mutex_;
    Snapshot snapshot_;
    std::uint64_t expectedSteamId_ = 0;
    bool ambiguousAttempt_ = false;
    std::set<std::pair<std::uint64_t, std::int32_t>> retiredSessions_;
};

Snapshot Capture();
void SetObserverAvailability(bool sendInstalled, bool receiveInstalled);
void BeginLogon(std::uint64_t expectedSteamId = 0);
void SignOut();
void ObserveLogonResponse(std::int32_t result, bool hasResult,
                          std::uint64_t steamId, std::int32_t sessionId);
void ObserveAuthenticatedHeader(std::uint64_t steamId, std::int32_t sessionId,
                                bool hasSteamId, bool hasSessionId);

} // namespace RentalIdentity
