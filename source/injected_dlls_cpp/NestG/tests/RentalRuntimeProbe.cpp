// Disposable fixture: this executable is never named Steam and never opens a
// real Steam installation. Include the implementation so its private helpers
// can be exercised without adding any test exports to the shipped DLL.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "NestG/RentalRuntime.cpp"
#include <detours.h>
#include <iostream>

namespace OSTPlatform::Detour {
bool BeginTransaction() { return ::DetourTransactionBegin() == NO_ERROR && ::DetourUpdateThread(GetCurrentThread()) == NO_ERROR; }
bool CommitTransaction() { return ::DetourTransactionCommit() == NO_ERROR; }
bool Attach(void** target, void* hook) { return ::DetourAttach(target, hook) == NO_ERROR; }
bool Detach(void** target, void* hook) { return ::DetourDetach(target, hook) == NO_ERROR; }
}
namespace Hooks_Package { void NotifyLicenseChanged() {} void RequestRentalRefresh() {} bool RentalIsolationReady() { return true; } }
namespace Hooks_Manifest { bool RentalReadReady() { return true; } }

namespace {
unsigned passed = 0;
void Check(bool condition, const char* name) {
    if (!condition) throw std::runtime_error(name);
    ++passed;
}
template<class Action> void Reject(Action action, const char* name) {
    bool rejected = false; try { action(); } catch (...) { rejected = true; }
    Check(rejected, name);
}
void WriteFixture(const std::filesystem::path& path, const std::string& bytes) {
    NestGRental::NativeFilesystemAccess trusted;
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    if (!file) throw std::runtime_error("fixture_write");
}
std::string ReadPublic(const std::filesystem::path& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) throw std::runtime_error("public_open_denied");
    char buffer[512]{}; DWORD got = 0;
    const bool read = ReadFile(file, buffer, sizeof(buffer), &got, nullptr);
    CloseHandle(file); if (!read) throw std::runtime_error("public_read_denied");
    return std::string(buffer, got);
}
void FiberReadsRetail(void* state) {
    auto* pair = static_cast<std::pair<std::filesystem::path, void*>*>(state);
    Check(ReadPublic(pair->first) == "retail", "fiber_scope_isolation");
    SwitchToFiber(pair->second);
}
}

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc != 2 && argc != 3) throw std::runtime_error("fixture_path_required");
        using namespace NestGRental;
        if (argc == 3) {
            const std::filesystem::path fixture = argv[1];
            std::filesystem::create_directories(fixture);
            if (std::wstring(argv[2]) == L"--adapter-failure") {
                // A resolved but unavailable adapter must stop the caller before
                // unrestricted retail Lua is allowed to execute.
                realNtCreateFile = reinterpret_cast<NtCreateFileFunction>(1);
                bool retailExecuted = false;
                if (Start(fixture)) retailExecuted = true;
                Check(!retailExecuted, "failed_adapter_stops_retail_initialization");
                Check(!Start(fixture), "failed_adapter_retry_remains_closed");
                std::cout << "Passed failed-adapter startup gate.\n";
                return 0;
            }
            if (std::wstring(argv[2]) != L"--worker-exit") throw std::runtime_error("unknown_fixture_mode");
            Check(Start(fixture), "detached_workers_start");
            Sleep(250);
            std::cout << "Passed detached rental worker normal-exit setup.\n";
            return 0;
        }
        Data data;
        const std::string key(64, 'a');
        const std::string lua = "-- fixture\naddappid(10)\naddappid(11,1,\"" + key + "\")\naddtoken(10,\"42\")\nsetManifestid(11,\"12\",99)\nsetstat(10,\"76561198000000001\")\npinapp(10)";
        Check(DataParser(lua).Parse(data), "literal_data_accept");
        Check(data.depotKeys.size() == 2 && data.depotKeys.at(11) == key, "source_scoped_depots");
        Check(data.manifests.at(11).gid == 12 && data.manifests.at(11).size == 0, "manifest_size_ignored");
        for (const std::string bad : {"os.execute('anything')", "dofile('x')", "http_get('https://example.test')", "setappticket(10,'00')", "seteticket(10,'00')", "setlegacycdkey(10,'x')", "addprocess(10,'x.exe')", "forcedenuvo(10)", "seteticketurl('x')", "while true do end", "addappid(4294967296)", "addappid(-1)", "setmanifestid(11,'18446744073709551616')", "addappid(10)\n--[[unterminated"}) {
            Data rejected; Check(!DataParser(bad).Parse(rejected), "unsafe_or_malformed_lua_rejected");
        }
        Data retained; retained.depotKeys[99] = "retained";
        Check(!DataParser("addappid(10)\nos.execute('x')").Parse(retained) && retained.depotKeys.size() == 1 && retained.depotKeys.count(99), "parser_transactional_failure");
        Check(JsonParser("{\"number\":42,\"list\":[\"x\"]}").Parse().At("number").Number() == 42, "json_valid");
        Reject([] { JsonParser("{\"x\":1,\"x\":2}").Parse(); }, "json_duplicate_rejected");
        Reject([] { JsonParser("{\"x\":1.5}").Parse(); }, "json_float_rejected");
        Reject([] { JsonParser("{\"x\":01}").Parse(); }, "json_leading_zero_rejected");
        Reject([] { JsonParser("{\"x\":\"\\u0000\"}").Parse(); }, "json_control_rejected");

        const std::filesystem::path root = std::filesystem::absolute(argv[1]);
        Check(!std::filesystem::exists(root), "new_fixture_root");
        state.steamRoot = root;
        const std::string sid = "76561198000000001", rentalId = "11111111-1111-4111-8111-111111111111";
        const std::string grantId = "22222222-2222-4222-8222-222222222222", accountId = "33333333-3333-4333-8333-333333333333";
        const std::string installationId = "44444444-4444-4444-8444-444444444444", revision(64, 'a');
        const auto rental = root / L"nestg-rentals" / sid / rentalId;
        const auto luaPath = rental / L"lua" / L"10" / L"10.lua";
        const auto privatePath = rental / L"manifests" / L"10" / L"11_12.manifest";
        const auto common = root / L"depotcache" / L"11_12.manifest";
        const std::string privateBytes = "private-manifest-fixture";
        WriteFixture(luaPath, lua); WriteFixture(privatePath, privateBytes); WriteFixture(common, "retail");
        WriteFixture(root / L"nestg-rentals" / L".writer.lock", "");
        const std::string control = "{\"protocolVersion\":1,\"apiOrigin\":\"https://localhost\",\"installationId\":\"" + installationId +
            "\",\"steamId64\":\"" + sid + "\",\"rentalId\":\"" + rentalId + "\",\"grantId\":\"" + grantId + "\",\"steamAccountId\":\"" + accountId +
            "\",\"revision\":\"" + revision + "\",\"grantFile\":\"grant.dat\",\"inventoryFile\":\"inventory.json\"}";
        WriteFixture(rental / L".nestg" / L"runtime.json", control);
        WriteFixture(rental / L".nestg" / L"grant.dat", Protect(std::string(43, 'A'), kGrantPurpose, true));
        const std::string inventory = "{\"protocolVersion\":1,\"steamId64\":\"" + sid + "\",\"rentalId\":\"" + rentalId + "\",\"revision\":\"" + revision +
            "\",\"files\":[{\"relativePath\":\"lua/10/10.lua\",\"steamAppId\":10,\"sizeBytes\":" + std::to_string(lua.size()) + " ,\"sha256\":\"" + Sha(lua) +
            "\"},{\"relativePath\":\"manifests/10/11_12.manifest\",\"steamAppId\":10,\"sizeBytes\":" + std::to_string(privateBytes.size()) + " ,\"sha256\":\"" + Sha(privateBytes) + "\"}]}";
        WriteFixture(rental / L".nestg" / L"inventory.json", inventory);
        WriteFixture(root / L"alias" / L"11_12.manifest", "unrelated");
        const auto accountRoot = rental.parent_path();
        for (unsigned i = 0; i < 140; ++i) {
            WriteFixture(accountRoot / (".stage-" + std::to_string(i)) / "ignored.txt", "stage");
            char historyId[40]{}; sprintf_s(historyId, "%08x-5555-4555-8555-555555555555", i + 1);
            WriteFixture(accountRoot / historyId / L".nestg" / L"runtime.json", "{}");
        }
        std::filesystem::last_write_time(rental / L".nestg" / L"runtime.json", std::filesystem::file_time_type::clock::now() + std::chrono::hours(1));
        const auto discovered = DiscoverCandidates(accountRoot, {});
        Check(discovered.size() == 128 && discovered.front() == rental, "discovery_newest_beyond_128_stage_and_history_entries");
        Check(IsReservedPath(luaPath) && IsReservedPath(rental / L"lua" / L".." / L"manifests"), "reserved_source_paths");
        Check(!IsReservedPath(common), "retail_path_allowed");
        RentalIdentity::SetObserverAvailability(true, true); RentalIdentity::BeginLogon(76561198000000001ULL);
        RentalIdentity::ObserveLogonResponse(1, true, 76561198000000001ULL, 42);
        const auto identity = RentalIdentity::Capture();
        const auto ctl = LoadControl(rental);
        Check(ctl.grant.size() == 43 && Inventory(ctl).size() == 2, "dpapi_grant_and_inventory");
        const std::string replyText = "{\"protocolVersion\":1,\"steamId64\":\"" + sid + "\",\"rentalId\":\"" + rentalId + "\",\"installationId\":\"" + installationId +
            "\",\"grantId\":\"" + grantId + "\",\"steamAccountId\":\"" + accountId + "\",\"revision\":\"" + revision +
            "\",\"serverNowUtc\":\"2026-10-17T00:00:00Z\",\"endsAtUtc\":\"2026-10-17T01:00:00Z\",\"authorizationExpiresAtUtc\":\"2026-10-17T00:02:00Z\",\"allowedAppIds\":[10]}";
        auto snapshot = Authorize(ctl, JsonParser(replyText).Parse(), identity, GetTickCount64());
        Check(DiscoverCandidates(accountRoot, snapshot).front() == rental, "discovery_active_source_always_first");
        Check(snapshot->data.depotKeys.count(10) && snapshot->data.depotKeys.count(11), "authorized_data_loaded");
        auto noApps = JsonParser(replyText).Parse(); noApps.object.at("allowedAppIds").array.clear();
        Check(Authorize(ctl, noApps, identity, GetTickCount64())->data.depotKeys.empty(), "server_owned_app_dedup");
        auto wrongRevision = JsonParser(replyText).Parse(); wrongRevision.object.at("revision").text = std::string(64, 'b');
        Reject([&] { Authorize(ctl, wrongRevision, identity, GetTickCount64()); }, "response_revision_binding");
        auto wrongGrant = JsonParser(replyText).Parse(); wrongGrant.object.at("grantId").text = accountId;
        Reject([&] { Authorize(ctl, wrongGrant, identity, GetTickCount64()); }, "response_grant_binding");
        Check(InstallReadAdapter(), "real_nt_adapter_attached"); state.readAdapterReady = true;
        Publish(snapshot); Check(Acquire() != nullptr, "source_authorized");
        Check(ReadPublic(common) == "retail", "common_read_unchanged");
        std::array<wchar_t, 32768> device{};
        const auto drive = common.root_name().wstring();
        Check(QueryDosDeviceW(drive.c_str(), device.data(), static_cast<DWORD>(device.size())) != 0, "device_alias_fixture");
        const auto devicePath = std::filesystem::path(std::wstring(L"\\\\?\\GLOBALROOT") + device.data() + common.wstring().substr(2));
        Check(ReadPublic(devicePath) == "retail", "device_alias_resolves_retail_outside_scope");
        Reject([&] { ReadPublic(privatePath); }, "private_read_outside_scope_denied");
        {
            ManifestReadScope scope(10, 11, 12);
            Check(ReadPublic(common) == privateBytes, "private_routing_with_existing_common");
            auto renewal = std::make_shared<Snapshot>(*snapshot); renewal->deadlineTicks = GetTickCount64() + 120000; Publish(renewal);
            Check(ReadPublic(common) == privateBytes, "same_lease_renewal_keeps_scoped_read");
            Reject([&] { ReadPublic(root / L"alias" / L"11_12.manifest"); }, "scoped_unrecognized_manifest_alias_fails_closed");
            Reject([&] { ReadPublic(devicePath); }, "device_alias_cannot_fall_back_to_common");
            void* mainFiber = IsThreadAFiber() ? GetCurrentFiber() : ConvertThreadToFiber(nullptr);
            std::pair<std::filesystem::path, void*> args{common, mainFiber};
            void* otherFiber = CreateFiber(0, FiberReadsRetail, &args);
            Check(mainFiber && otherFiber, "fiber_fixture_created");
            SwitchToFiber(otherFiber); DeleteFiber(otherFiber);
            Check(ReadPublic(common) == privateBytes, "scope_preserved_after_fiber_switch");
            HANDLE open = CreateFileW(common.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            Check(open != INVALID_HANDLE_VALUE, "private_handle_open");
            HANDLE duplicate = nullptr;
            Check(DuplicateHandle(GetCurrentProcess(), open, GetCurrentProcess(), &duplicate, 0, false, DUPLICATE_SAME_ACCESS), "private_handle_duplicate_tagged");
            HANDLE mapping = CreateFileMappingW(open, nullptr, PAGE_READONLY, 0, 0, nullptr);
            Check(mapping == nullptr, "non_revocable_mapped_view_rejected");
            if (mapping) CloseHandle(mapping);
            RentalIdentity::SignOut();
            char bytes[64]{}; DWORD got = 0;
            Check(!ReadFile(open, bytes, sizeof(bytes), &got, nullptr), "open_handle_revoked_after_logout");
            Check(!ReadFile(duplicate, bytes, sizeof(bytes), &got, nullptr), "duplicate_handle_revoked_after_logout");
            HANDLE duplicateMapping = CreateFileMappingW(duplicate, nullptr, PAGE_READONLY, 0, 0, nullptr);
            Check(duplicateMapping == nullptr, "duplicate_mapping_rejected_after_logout");
            if (duplicateMapping) CloseHandle(duplicateMapping);
            CloseHandle(duplicate);
            CloseHandle(open);
            Reject([&] { ReadPublic(common); }, "stale_scope_denied_after_logout");
        }
        Check(!Acquire(), "logout_clears_effective_source");
        Check(ReadPublic(common) == "retail", "personal_account_retail_unchanged");
        HANDLE retailHandle = CreateFileW(common.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        HANDLE retailMapping = CreateFileMappingW(retailHandle, nullptr, PAGE_READONLY, 0, 0, nullptr);
        Check(retailHandle != INVALID_HANDLE_VALUE && retailMapping != nullptr, "personal_native_retail_mapping_unchanged");
        CloseHandle(retailMapping); CloseHandle(retailHandle);
        RentalIdentity::BeginLogon(76561198000000001ULL); RentalIdentity::ObserveLogonResponse(1, true, 76561198000000001ULL, 43);
        auto fresh = std::make_shared<Snapshot>(*snapshot); fresh->generation = RentalIdentity::Capture().generation; fresh->deadlineTicks = GetTickCount64() + 30000;
        Publish(fresh);
        auto wrongControl = ctl; wrongControl.grantId = accountId;
        RevokeLease(wrongControl); Check(Acquire() != nullptr, "old_grant_cannot_revoke_new_source");
        {
            ManifestReadScope scope(10, 11, 12);
            HANDLE open = CreateFileW(common.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            auto replacement = std::make_shared<Snapshot>(*fresh); replacement->grantId = accountId; Publish(replacement);
            char bytes[64]{}; DWORD got = 0;
            Check(open != INVALID_HANDLE_VALUE && !ReadFile(open, bytes, sizeof(bytes), &got, nullptr), "handle_grant_epoch_binding"); CloseHandle(open);
        }
        auto expired = std::make_shared<Snapshot>(*fresh); expired->deadlineTicks = GetTickCount64() - 1; Publish(expired);
        Check(!Acquire(), "monotonic_deadline_enforced");
        Publish(nullptr);
        Vault(ctl);
        {
            // Metadata implementations may open the file through the read
            // adapter. Fixture inspection must use the existing trusted scope.
            NativeFilesystemAccess trusted;
            Check(!std::filesystem::exists(luaPath) && !std::filesystem::exists(privatePath), "expired_plaintext_removed");
        }
        const auto vaultFile = rental / L".nestg" / L"vault" / L"lua" / L"10" / L"10.lua.dpapi";
        Check(Protect(Read(vaultFile, lua.size() + 16384), kVaultPurpose, false) == lua, "vault_dpapi_round_trip");
        Check(ReadPublic(common) == "retail", "vault_preserves_common_retail");
        Vault(ctl);
        {
            NativeFilesystemAccess trusted;
            Check(std::filesystem::exists(vaultFile), "vault_recovery_idempotent");
        }
        std::cout << "Passed " << passed << " native rental runtime checks; no real Steam was accessed.\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << "Fixture failed after " << passed << " checks: " << error.what() << "; Win32=" << GetLastError() << "\n"; return 1; }
}
