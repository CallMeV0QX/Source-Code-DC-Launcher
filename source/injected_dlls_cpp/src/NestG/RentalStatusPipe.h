#pragma once
#include <cstdint>
#include <functional>
#include <string>

namespace RentalStatusPipe {
struct Request {
    std::string nonce, rentalId, steamAccountId, steamId64, installationId, grantId, revision;
};
struct Reply {
    std::string runtimeInstanceId;
    std::uint64_t identityEpoch = 0;
    std::string actualSteamId64;
    std::string state = "unavailable";
    std::uint64_t remainingAuthorizationMs = 0;
    std::string rentalId, steamAccountId, installationId, grantId, revision;
};
using Provider = std::function<Reply(const Request&)>;
// One read-only endpoint per runtime process. No request mutates identity,
// credentials, a server lease, configuration, or rental payloads.
bool Start(Provider provider);
void Stop();
std::wstring PipeName();
Request ParseRequest(const std::string& frame);
std::string SerializeReply(const Request& request, const Reply& reply);
}
