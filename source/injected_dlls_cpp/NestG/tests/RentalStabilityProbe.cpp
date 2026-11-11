// Exercises the frozen 1.0.8 implementation through the existing real Win32
// fixture seam. Steam callbacks remain simulated; no installed Steam is used.
#define wmain RentalRegressionMain
#include "RentalRuntimeProbe.cpp"
#undef wmain
#include <psapi.h>
#include <thread>

namespace {
struct Resources {
    DWORD handles = 0;
    SIZE_T privateBytes = 0;
};
Resources SampleResources() {
    Resources result;
    PROCESS_MEMORY_COUNTERS_EX memory{};
    memory.cb = sizeof(memory);
    if (!GetProcessHandleCount(GetCurrentProcess(), &result.handles) ||
        !GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory)))
        throw std::runtime_error("resource_sample");
    result.privateBytes = memory.PrivateUsage;
    return result;
}
std::string GuidFor(unsigned value) {
    char id[40]{};
    sprintf_s(id, "%08x-7777-4777-8777-777777777777", value + 1);
    return id;
}
bool ReadMatches(HANDLE handle, const std::string& expected) {
    LARGE_INTEGER zero{};
    if (!SetFilePointerEx(handle, zero, nullptr, FILE_BEGIN)) return false;
    char bytes[256]{};
    DWORD got = 0;
    return ReadFile(handle, bytes, sizeof(bytes), &got, nullptr) && std::string(bytes, got) == expected;
}
bool ReadDenied(HANDLE handle) {
    char byte{}; DWORD got = 0;
    return !ReadFile(handle, &byte, 1, &got, nullptr);
}
}

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc != 4) throw std::runtime_error("expected_fixture_iterations_vault_cycles");
        const auto root = std::filesystem::absolute(argv[1]);
        const auto iterations = std::stoul(argv[2]);
        const auto vaultCycles = std::stoul(argv[3]);
        if (iterations < 100 || iterations > 5000 || vaultCycles < 1 || vaultCycles > 100)
            throw std::runtime_error("bounded_iterations_required");
        Check(!std::filesystem::exists(root), "fresh_stability_root");
        const auto baselineRoot = root / L"baseline";
        std::wstring baselineArgument = baselineRoot.wstring();
        wchar_t* baselineArguments[]{argv[0], baselineArgument.data()};
        const auto beforeBaseline = passed;
        if (RentalRegressionMain(2, baselineArguments) != 0) throw std::runtime_error("baseline_regression");
        const auto baselineChecks = passed - beforeBaseline;
        using namespace NestGRental;
        Publish(nullptr);
        state.steamRoot = root / L"work";
        const std::string sid = "76561198000000001", rentalId = "11111111-1111-4111-8111-111111111111";
        const std::string grantId = "22222222-2222-4222-8222-222222222222", revision(64, 'a');
        const auto rental = state.steamRoot / L"nestg-rentals" / sid / rentalId;
        const auto privatePath = rental / L"manifests" / L"10" / L"11_12.manifest";
        const auto luaPath = rental / L"lua" / L"10" / L"10.lua";
        const auto common = state.steamRoot / L"depotcache" / L"11_12.manifest";
        const std::string manifest = "stability-private-manifest", lua = "addappid(10)\naddappid(11)\nsetmanifestid(11,\"12\")";
        const std::string control = "{\"protocolVersion\":1,\"apiOrigin\":\"https://localhost\",\"installationId\":\"44444444-4444-4444-8444-444444444444\",\"steamId64\":\"" + sid +
            "\",\"rentalId\":\"" + rentalId + "\",\"grantId\":\"" + grantId + "\",\"steamAccountId\":\"33333333-3333-4333-8333-333333333333\",\"revision\":\"" + revision +
            "\",\"grantFile\":\"grant.dat\",\"inventoryFile\":\"inventory.json\"}";
        const std::string inventory = "{\"protocolVersion\":1,\"steamId64\":\"" + sid + "\",\"rentalId\":\"" + rentalId + "\",\"revision\":\"" + revision +
            "\",\"files\":[{\"relativePath\":\"lua/10/10.lua\",\"steamAppId\":10,\"sizeBytes\":" + std::to_string(lua.size()) + ",\"sha256\":\"" + Sha(lua) +
            "\"},{\"relativePath\":\"manifests/10/11_12.manifest\",\"steamAppId\":10,\"sizeBytes\":" + std::to_string(manifest.size()) + ",\"sha256\":\"" + Sha(manifest) + "\"}]}";
        WriteFixture(privatePath, manifest); WriteFixture(luaPath, lua); WriteFixture(common, "retail");
        WriteFixture(state.steamRoot / L"nestg-rentals" / L".writer.lock", "");
        WriteFixture(rental / L".nestg" / L"runtime.json", control);
        WriteFixture(rental / L".nestg" / L"grant.dat", Protect(std::string(43, 'A'), kGrantPurpose, true));
        WriteFixture(rental / L".nestg" / L"inventory.json", inventory);
        const auto ctl = LoadControl(rental);
        auto prototype = std::make_shared<Snapshot>();
        prototype->steamId = 76561198000000001ULL; prototype->rentalId = rentalId; prototype->grantId = grantId;
        prototype->revision = revision; prototype->root = rental;
        prototype->data.depotKeys[10] = ""; prototype->data.depotKeys[11] = "";
        prototype->manifestFiles[L"10/11_12.manifest"] = {privatePath, manifest.size(), Sha(manifest)};

        // Capture concurrent identity snapshots while alternating authenticated
        // accounts. A snapshot must never combine fields from two sessions.
        RentalIdentity::Tracker tracker;
        tracker.SetObserverAvailability(true, true);
        std::atomic<bool> running{true}, coherent{true};
        std::vector<std::thread> readers;
        for (unsigned t = 0; t < 3; ++t) readers.emplace_back([&] {
            while (running.load()) {
                const auto snapshot = tracker.Capture();
                if (snapshot.state == RentalIdentity::State::Authenticated &&
                    !(snapshot.steamSessionId >= 1001 &&
                      snapshot.steamId == 76561198000000001ULL + (snapshot.steamSessionId - 1001) % 2)) coherent.store(false);
            }
        });
        for (unsigned i = 0; i < iterations * 10; ++i) {
            const auto account = 76561198000000001ULL + i % 2;
            tracker.BeginLogon(account); tracker.ObserveLogonResponse(1, true, account, 1001 + i); tracker.SignOut();
        }
        running.store(false);
        for (auto& reader : readers) reader.join();
        Check(coherent.load(), "concurrent_identity_rotation_coherent");

        TakeAdded(); TakeRemoved();
        Resources warm{}, after{};
        unsigned deniedHandles = 0, renewedReads = 0;
        for (unsigned i = 0; i < iterations + 50; ++i) {
            RentalIdentity::BeginLogon(76561198000000001ULL);
            RentalIdentity::ObserveLogonResponse(1, true, 76561198000000001ULL, 10000 + i);
            auto current = std::make_shared<Snapshot>(*prototype);
            current->generation = RentalIdentity::Capture().generation;
            current->grantId = GuidFor(i);
            current->deadlineTicks = GetTickCount64() + 30000;
            Publish(current);
            {
                ManifestReadScope scope(10, 11, 12);
                std::array<HANDLE, 16> handles{};
                for (unsigned h = 0; h < handles.size(); h += 2) {
                    handles[h] = CreateFileW(common.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
                    Check(handles[h] != INVALID_HANDLE_VALUE, "rotation_private_open");
                    Check(DuplicateHandle(GetCurrentProcess(), handles[h], GetCurrentProcess(), &handles[h + 1], 0, false, DUPLICATE_SAME_ACCESS), "rotation_duplicate_tagged");
                }
                auto renewed = std::make_shared<Snapshot>(*current); renewed->deadlineTicks = GetTickCount64() + 60000; Publish(renewed);
                for (const auto handle : handles) { Check(ReadMatches(handle, manifest), "heartbeat_preserves_handle"); ++renewedReads; }
                switch (i % 4) {
                case 0: RentalIdentity::SignOut(); break;
                case 1: {
                    auto replacement = std::make_shared<Snapshot>(*renewed); replacement->grantId = GuidFor(i + 10000); Publish(replacement); break;
                }
                case 2: {
                    auto expired = std::make_shared<Snapshot>(*renewed); expired->deadlineTicks = GetTickCount64() - 1; Publish(expired); break;
                }
                default: Publish(nullptr); break;
                }
                for (const auto handle : handles) { Check(ReadDenied(handle), "rotation_old_handle_denied"); ++deniedHandles; CloseHandle(handle); }
                Reject([&] { ReadPublic(common); }, "rotation_stale_scope_denied");
            }
            Publish(nullptr); TakeAdded(); TakeRemoved();
            Check(ReadPublic(common) == "retail", "rotation_retail_preserved");
            { std::lock_guard lock(state.handlesMutex); Check(state.readHandles.empty(), "closed_handles_not_retained"); }
            if (i == 49) warm = SampleResources();
        }
        after = SampleResources();
        Check(after.handles <= warm.handles + 2, "handle_count_stable_after_warmup");
        Check(after.privateBytes <= warm.privateBytes + 8 * 1024 * 1024, "private_memory_bounded_after_warmup");

        // Deliberately stop vault midway with a bad second payload, then retry.
        // First-file ciphertext must survive, and the bad cleartext must remain.
        unsigned recoveries = 0;
        const auto vaultLua = rental / L".nestg" / L"vault" / L"lua" / L"10" / L"10.lua.dpapi";
        const auto vaultManifest = rental / L".nestg" / L"vault" / L"manifests" / L"10" / L"11_12.manifest.dpapi";
        for (unsigned i = 0; i < vaultCycles; ++i) {
            WriteFixture(luaPath, lua); WriteFixture(privatePath, "invalid-manifest");
            Reject([&] { Vault(ctl); }, "partial_vault_rejects_bad_second_payload");
            {
                NativeFilesystemAccess trusted;
                Check(!std::filesystem::exists(luaPath) && std::filesystem::exists(privatePath), "partial_vault_preserves_unverified_payload");
            }
            Check(Protect(Read(vaultLua, 16384), kVaultPurpose, false) == lua, "partial_vault_verified_first_file_survives");
            WriteFixture(privatePath, manifest); Vault(ctl); Vault(ctl);
            {
                NativeFilesystemAccess trusted;
                Check(!std::filesystem::exists(privatePath), "vault_retry_removes_verified_plaintext");
            }
            Check(Protect(Read(vaultManifest, 16384), kVaultPurpose, false) == manifest, "vault_retry_manifest_round_trip");
            auto ciphertext = Read(vaultManifest, 16384); ciphertext[ciphertext.size() / 2] ^= 1;
            Reject([&] { Protect(ciphertext, kVaultPurpose, false); }, "dpapi_corruption_rejected");
            Reject([&] { Protect(Read(vaultManifest, 16384), kGrantPurpose, false); }, "dpapi_wrong_purpose_rejected");
            Check(ReadPublic(common) == "retail", "vault_cycle_retail_preserved");
            ++recoveries;
        }
        Publish(nullptr); TakeAdded(); TakeRemoved();
        std::ofstream report(root / L"stability-results.json");
        report << "{\"passed\":true,\"checks\":" << passed << ",\"baselineChecks\":" << baselineChecks
            << ",\"identityRotations\":" << iterations * 10 << ",\"leaseRotations\":" << iterations + 50
            << ",\"renewedHandleReads\":" << renewedReads << ",\"deniedOldHandleReads\":" << deniedHandles
            << ",\"vaultRecoveryCycles\":" << recoveries << ",\"warmHandles\":" << warm.handles << ",\"finalHandles\":" << after.handles
            << ",\"warmPrivateBytes\":" << warm.privateBytes << ",\"finalPrivateBytes\":" << after.privateBytes
            << ",\"realSteamAccessed\":false,\"networkUsed\":false}";
        if (!report) throw std::runtime_error("stability_report_write");
        std::cout << "Passed " << passed << " stability checks, " << iterations + 50 << " lease rotations and " << recoveries << " vault recovery cycles; no real Steam/network used.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Stability fixture failed after " << passed << " checks: " << error.what() << "; Win32=" << GetLastError() << "\n";
        return 1;
    }
}
