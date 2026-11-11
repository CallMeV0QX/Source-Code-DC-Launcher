#include "NestG/RentalIdentity.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <thread>

namespace {
constexpr std::uint64_t kAccountA = 76561197960265729ULL;
constexpr std::uint64_t kAccountB = 76561197960265730ULL;
unsigned checks = 0;
void Require(bool condition, const char* description) {
    if (!condition) {
        std::cerr << "Rental identity fixture failed: " << description << '\n';
        std::exit(1);
    }
    ++checks;
}
void Authenticate(RentalIdentity::Tracker& tracker, std::uint64_t account, std::int32_t session) {
    static std::int32_t freshSession = 100000;
    session = ++freshSession;
    tracker.BeginLogon(account);
    tracker.ObserveLogonResponse(1, true, account, session);
}
}

int main() {
    using RentalIdentity::State;
    RentalIdentity::Tracker tracker;
    Require(tracker.Capture().state == State::Unknown && !tracker.Capture().observerReady,
            "initial state is unauthenticated");
    Authenticate(tracker, kAccountA, 123);
    Require(tracker.Capture().steamId == 0, "missing hook readiness cannot authenticate");
    tracker.SetObserverAvailability(true, false);
    Require(!tracker.Capture().observerReady, "both observers are required");
    tracker.SetObserverAvailability(true, true);
    Require(tracker.Capture().observerReady, "successful observers publish readiness");
    tracker.ObserveLogonResponse(1, true, kAccountA, 123);
    Require(tracker.Capture().state == State::Unknown, "unsolicited server reply is insufficient");
    tracker.BeginLogon(kAccountA);
    Require(tracker.Capture().state == State::Pending && tracker.Capture().steamId == 0,
            "outbound identity is not authenticated proof");
    tracker.ObserveLogonResponse(1, false, kAccountA, 123);
    Require(tracker.Capture().state == State::Unknown, "missing explicit result is rejected");
    tracker.BeginLogon(kAccountA);
    tracker.ObserveLogonResponse(2, true, kAccountA, 123);
    Require(tracker.Capture().state == State::Unknown, "failed server logon is rejected");
    tracker.BeginLogon(kAccountA);
    tracker.ObserveLogonResponse(1, true, kAccountB, 123);
    Require(tracker.Capture().state == State::Unknown, "expected account mismatch is rejected");
    tracker.BeginLogon(kAccountA);
    tracker.ObserveLogonResponse(1, true, kAccountA, 0);
    Require(tracker.Capture().state == State::Unknown, "missing server session is rejected");
    tracker.BeginLogon();
    tracker.ObserveLogonResponse(1, true, 123, 123);
    Require(tracker.Capture().state == State::Unknown, "malformed SteamID is rejected");
    tracker.BeginLogon();
    tracker.ObserveLogonResponse(1, true, 76561193665298433ULL, 123);
    Require(tracker.Capture().state == State::Unknown, "non-desktop identity is rejected");
    Authenticate(tracker, kAccountA, 123);
    const auto authenticated = tracker.Capture();
    Require(authenticated.state == State::Authenticated && authenticated.steamId == kAccountA &&
            authenticated.steamSessionId != 0, "successful original response authenticates");
    tracker.ObserveLogonResponse(1, true, kAccountB, 456);
    Require(tracker.Capture().generation == authenticated.generation,
            "late duplicate reply cannot replace authenticated identity");
    tracker.ObserveAuthenticatedHeader(0, 0, false, false);
    Require(tracker.Capture().generation == authenticated.generation,
            "omitted optional fields preserve matching proof");
    tracker.ObserveAuthenticatedHeader(kAccountA, authenticated.steamSessionId, true, true);
    Require(tracker.Capture().generation == authenticated.generation,
            "matching traffic preserves authenticated proof");
    tracker.ObserveAuthenticatedHeader(kAccountB, authenticated.steamSessionId, true, true);
    Require(tracker.Capture().state == State::Unknown &&
            tracker.Capture().generation > authenticated.generation,
            "changed account invalidates the previous proof");
    Authenticate(tracker, kAccountA, 123);
    tracker.ObserveAuthenticatedHeader(kAccountA, 456, true, true);
    Require(tracker.Capture().state == State::Unknown, "changed session invalidates proof");
    Authenticate(tracker, kAccountA, 123);
    const auto oldGeneration = tracker.Capture().generation;
    tracker.BeginLogon(kAccountB);
    Require(tracker.Capture().state == State::Pending && tracker.Capture().steamId == 0 &&
            tracker.Capture().generation > oldGeneration, "account change clears old proof immediately");
    tracker.ObserveLogonResponse(1, true, kAccountA, 123);
    Require(tracker.Capture().state == State::Unknown, "stale old account login reply is rejected");
    Authenticate(tracker, kAccountB, 456);
    tracker.SignOut();
    const auto signedOut = tracker.Capture();
    Require(signedOut.state == State::SignedOut && signedOut.steamId == 0 &&
            signedOut.steamSessionId == 0, "logout clears all identity permission");
    tracker.ObserveLogonResponse(1, true, kAccountB, 456);
    Require(tracker.Capture().generation == signedOut.generation,
            "late reply after logout cannot reauthorize");
    Authenticate(tracker, kAccountB, 456);
    tracker.SetObserverAvailability(false, true);
    Require(!tracker.Capture().observerReady && tracker.Capture().state == State::Unknown &&
            tracker.Capture().steamId == 0, "observer loss clears proof");

    tracker.SetObserverAvailability(true, true);
    std::atomic<bool> finished{false};
    std::atomic<bool> coherent{true};
    std::thread reader([&] {
        while (!finished.load()) {
            const auto snapshot = tracker.Capture();
            if (snapshot.state == State::Authenticated &&
                (!snapshot.observerReady || snapshot.steamSessionId == 0 ||
                 (snapshot.steamId != kAccountA && snapshot.steamId != kAccountB)))
                coherent.store(false);
            if (snapshot.state != State::Authenticated &&
                (snapshot.steamId != 0 || snapshot.steamSessionId != 0)) coherent.store(false);
        }
    });
    for (int i = 0; i < 10000; ++i) {
        Authenticate(tracker, i % 2 ? kAccountA : kAccountB, i + 1);
        tracker.SignOut();
    }
    finished.store(true);
    reader.join();
    Require(coherent.load(), "concurrent snapshots never combine accounts or generations");
    RentalIdentity::Tracker overlapping;
    overlapping.SetObserverAvailability(true, true);
    overlapping.BeginLogon(kAccountA); overlapping.BeginLogon(kAccountA);
    overlapping.ObserveLogonResponse(1, true, kAccountA, 100);
    Require(overlapping.Capture().state == State::Unknown, "overlapping same-account attempt cannot authenticate an old reply");
    overlapping.SignOut(); overlapping.BeginLogon(kAccountA);
    overlapping.ObserveLogonResponse(1, true, kAccountA, 101);
    Require(overlapping.Capture().state == State::Unknown, "ambiguous correlation requires a fresh process tracker");
    RentalIdentity::Tracker retired;
    retired.SetObserverAvailability(true, true); retired.BeginLogon(kAccountA);
    retired.ObserveLogonResponse(1, true, kAccountA, 100); retired.SignOut(); retired.BeginLogon(kAccountA);
    retired.ObserveLogonResponse(1, true, kAccountA, 100);
    Require(retired.Capture().state == State::Unknown, "retired same-account session cannot authenticate a later attempt");
    retired.BeginLogon(kAccountA); retired.ObserveLogonResponse(63, true, kAccountA, 0);
    retired.BeginLogon(kAccountA); retired.ObserveLogonResponse(1, true, kAccountA, 102);
    Require(retired.Capture().state == State::Authenticated, "terminal Guard failure permits a fresh non-overlapping response");
    RentalIdentity::Tracker observerLoss;
    observerLoss.SetObserverAvailability(true, true); observerLoss.BeginLogon(kAccountA);
    observerLoss.SetObserverAvailability(false, true); observerLoss.SetObserverAvailability(true, true);
    observerLoss.BeginLogon(kAccountA); observerLoss.ObserveLogonResponse(1, true, kAccountA, 103);
    Require(observerLoss.Capture().state == State::Unknown, "observer loss while pending cannot accept a late same-account reply after reenable");
    std::cout << "Validated " << checks << " deterministic rental identity checks.\n";
    return 0;
}
