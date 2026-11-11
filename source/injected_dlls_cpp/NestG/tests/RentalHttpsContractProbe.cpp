// Production WinHTTP implementation, compiled from frozen corresponding source.
// Identity is synthetic. This never starts Steam, the monitor, or a Lua VM.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "NestG/RentalRuntime.cpp"
#include <iostream>
namespace OSTPlatform::Detour {
bool BeginTransaction() { return false; } bool CommitTransaction() { return false; }
bool Attach(void**, void*) { return false; } bool Detach(void**, void*) { return false; }
}
namespace Hooks_Package { void NotifyLicenseChanged() {} void RequestRentalRefresh() {} bool RentalIsolationReady() { return false; } }
namespace Hooks_Manifest { bool RentalReadReady() { return false; } }

int wmain(int argc, wchar_t** argv) {
    const char* stage = "arguments";
    try {
        if (argc != 4) return 2;
        using namespace NestGRental;
        const auto root = std::filesystem::absolute(argv[1]).lexically_normal();
        bool temporary = false;
        for (const auto& component : root) if (component == L".codex-temp") temporary = true;
        if (!temporary || !IsReservedPath(root)) return 3;
        const std::string mode = OSTPlatform::Encoding::WideToUtf8(argv[2]);
        const std::string expected = OSTPlatform::Encoding::WideToUtf8(argv[3]);
        state.steamRoot = root.parent_path().parent_path().parent_path();
        stage = "private-control";
        auto control = LoadControl(root);
        uint64_t steamId = std::stoull(control.steamId);
        if (mode == "wrong-steam") ++steamId;
        if (mode == "wrong-installation") control.installationId = RequestId();
        if (mode == "wrong-proof") control.grant.assign(43, 'B');
        const auto request = RequestId();
        const auto started = GetTickCount64();
        stage = "winhttp-tls";
        Json reply;
        try { reply = NestGRental::Check(control, request, steamId); }
        catch (...) {
            if (expected == "http-error") { std::cout << "Expected native transport/HTTP rejection.\n"; return 0; }
            throw;
        }
        if (expected == "http-error") throw std::runtime_error("expected_rejection");
        stage = "scope";
        if (reply.At("protocolVersion").Number() != 1 || reply.At("requestId").String() != request ||
            reply.At("steamId64").String() != control.steamId || reply.At("rentalId").String() != control.rentalId ||
            reply.At("steamAccountId").String() != control.steamAccountId || reply.At("installationId").String() != control.installationId ||
            reply.At("grantId").String() != control.grantId || reply.At("status").String() != expected)
            throw std::runtime_error("scope_or_status");
        stage = "authorization";
        if (expected == "active") {
            RentalIdentity::SetObserverAvailability(true, true); RentalIdentity::BeginLogon(steamId);
            RentalIdentity::ObserveLogonResponse(1, true, steamId, 42);
            const auto snapshot = Authorize(control, reply, RentalIdentity::Capture(), started);
            const auto now = Time(reply.At("serverNowUtc").String());
            const auto deadline = Time(reply.At("authorizationExpiresAtUtc").String());
            if (snapshot->deadlineTicks <= GetTickCount64() || deadline <= now || deadline - now > 120000)
                throw std::runtime_error("allowance");
            const auto metadata = JsonParser(Read(root / L".nestg" / L"qa-expected.json", 16384)).Parse();
            std::set<uint64_t> wanted, actual;
            for (const auto& app : metadata.At("allowedAppIds").array) wanted.insert(app.Number());
            for (const auto& app : reply.At("allowedAppIds").array) actual.insert(app.Number());
            if (wanted != actual) throw std::runtime_error("app_scope");
            if (mode == "near-expiry" && deadline - now > 20000) throw std::runtime_error("near_expiry_cap");
        } else if (reply.At("allowedAppIds").array.size() ||
                   Time(reply.At("authorizationExpiresAtUtc").String()) != Time(reply.At("serverNowUtc").String())) {
            throw std::runtime_error("inactive_authorization");
        }
        std::cout << "Native HTTPS contract accepted expected status; elapsedMs=" << GetTickCount64() - started << ".\n";
        return 0;
    } catch (...) {
        std::cerr << "Native HTTPS contract failed at " << stage << "; Win32=" << GetLastError() << ".\n";
        return 1;
    }
}
