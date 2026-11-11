// New read-only confirmation, against disposable roots and synthetic original
// Steam logon events. No installed Steam, DLL injection, credentials or network.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "NestG/RentalRuntime.cpp"
#include "NestG/RentalStatusPipe.cpp"
#include <iostream>

namespace OSTPlatform::Detour {
bool BeginTransaction() { return false; } bool CommitTransaction() { return false; }
bool Attach(void**, void*) { return false; } bool Detach(void**, void*) { return false; }
}
namespace { bool fixtureHooksReady = true; unsigned checks = 0; }
namespace Hooks_Package { void NotifyLicenseChanged() {} void RequestRentalRefresh() {} bool RentalIsolationReady() { return fixtureHooksReady; } }
namespace Hooks_Manifest { bool RentalReadReady() { return fixtureHooksReady; } }

namespace {
void Check(bool condition, const char* name) { if (!condition) throw std::runtime_error(name); ++checks; }
template<class Action> void Reject(Action action, const char* name) {
    bool rejected = false; try { action(); } catch (...) { rejected = true; } Check(rejected, name);
}
std::string Frame(const RentalStatusPipe::Request& request) {
    return "{\"protocolVersion\":1,\"nonce\":\"" + request.nonce + "\",\"rentalId\":\"" + request.rentalId +
        "\",\"steamAccountId\":\"" + request.steamAccountId + "\",\"steamId64\":\"" + request.steamId64 +
        "\",\"installationId\":\"" + request.installationId + "\",\"grantId\":\"" + request.grantId + "\",\"revision\":\"" + request.revision + "\"}\n";
}
void Write(const std::filesystem::path& path, const std::string& bytes) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc); stream.write(bytes.data(), bytes.size());
    if (!stream) throw std::runtime_error("fixture_write");
}
NestGRental::Json Query(const std::wstring& name, const std::string& frame, DWORD expectedPid) {
    if (!WaitNamedPipeW(name.c_str(), 4000)) throw std::runtime_error("pipe_wait");
    RentalStatusPipe::Handle pipe(CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr));
    Check(pipe.value != INVALID_HANDLE_VALUE, "pipe_client_open");
    ULONG pid = 0; Check(GetNamedPipeServerProcessId(pipe.value, &pid) && pid == expectedPid, "pipe_kernel_server_pid");
    DWORD written = 0; Check(WriteFile(pipe.value, frame.data(), static_cast<DWORD>(frame.size()), &written, nullptr) && written == frame.size(), "pipe_client_write");
    std::string result; char bytes[4096]{}; DWORD read = 0;
    while (result.find('\n') == std::string::npos) {
        Check(ReadFile(pipe.value, bytes, sizeof(bytes), &read, nullptr) && read && result.size() + read <= 4096, "pipe_client_read");
        result.append(bytes, read);
    }
    return NestGRental::JsonParser(result).Parse();
}
void RejectedFrame(const std::wstring& name, const std::string& frame) {
    Check(WaitNamedPipeW(name.c_str(), 4000), "rejected_frame_connect_ready");
    RentalStatusPipe::Handle pipe(CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr));
    Check(pipe.value != INVALID_HANDLE_VALUE, "rejected_frame_open");
    DWORD written = 0, read = 0; char bytes[4096]{};
    Check(WriteFile(pipe.value, frame.data(), static_cast<DWORD>(frame.size()), &written, nullptr) && written == frame.size(), "rejected_frame_written");
    const auto started = GetTickCount64();
    Check(!ReadFile(pipe.value, bytes, sizeof(bytes), &read, nullptr) || !read, "invalid_frame_receives_no_reply");
    Check(GetTickCount64() - started < 4500, "invalid_or_slow_frame_has_deadline");
}
}
int wmain(int argc, wchar_t** argv) {
    try {
        if (argc == 5 && std::wstring(argv[1]) == L"--child-query") {
            const auto path = std::filesystem::absolute(argv[3]);
            bool disposable = false; for (const auto& part : path) if (part == L".codex-temp") disposable = true;
            if (!disposable || std::filesystem::file_size(path) > 4096) return 3;
            std::ifstream file(path, std::ios::binary); const std::string request((std::istreambuf_iterator<char>(file)), {});
            const auto response = Query(argv[2], request, static_cast<DWORD>(std::stoul(argv[4])));
            return response.At("state").String() == "ready" ? 0 : 4;
        }
        if (argc != 2) return 2;
        using namespace NestGRental;
        const auto root = std::filesystem::absolute(argv[1]).lexically_normal();
        bool temporary = false; for (const auto& component : root) if (component == L".codex-temp") temporary = true;
        Check(temporary && !std::filesystem::exists(root), "new_disposable_root_required");
        std::filesystem::create_directories(root);
        state.steamRoot = root / L"Steam";
        const RentalStatusPipe::Request request{std::string(64, 'a'), "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222", "76561198000000001", "33333333-3333-4333-8333-333333333333",
            "44444444-4444-4444-8444-444444444444", std::string(64, 'b')};
        const auto rental = state.steamRoot / L"nestg-rentals" / request.steamId64 / request.rentalId;
        const auto metadata = rental / L".nestg";
        Write(state.steamRoot / L"nestg-rentals" / L".writer.lock", "");
        const auto control = "{\"protocolVersion\":1,\"apiOrigin\":\"https://localhost\",\"installationId\":\"" + request.installationId +
            "\",\"steamId64\":\"" + request.steamId64 + "\",\"rentalId\":\"" + request.rentalId + "\",\"grantId\":\"" + request.grantId +
            "\",\"steamAccountId\":\"" + request.steamAccountId + "\",\"revision\":\"" + request.revision + "\",\"grantFile\":\"grant.dat\",\"inventoryFile\":\"inventory.json\"}";
        Write(metadata / L"runtime.json", control);
        Write(metadata / L"grant.dat", Protect(std::string(43, 'x'), kGrantPurpose, true));
        auto identity = [&] {
            static int32_t session = 1000;
            RentalIdentity::BeginLogon(76561198000000001ULL);
            RentalIdentity::ObserveLogonResponse(1, true, 76561198000000001ULL, ++session);
            return RentalIdentity::Capture();
        };
        auto publish = [&] {
            auto snapshot = std::make_shared<Snapshot>(); const auto actual = identity();
            snapshot->steamId = actual.steamId; snapshot->generation = actual.generation; snapshot->deadlineTicks = GetTickCount64() + 30000;
            snapshot->rentalId = request.rentalId; snapshot->steamAccountId = request.steamAccountId;
            snapshot->installationId = request.installationId; snapshot->grantId = request.grantId; snapshot->revision = request.revision; snapshot->root = rental;
            Publish(snapshot); return snapshot;
        };
        Check(RentalStatusPipe::ParseRequest(Frame(request)).nonce == request.nonce, "strict_wire_valid");
        Reject([&] { RentalStatusPipe::ParseRequest(Frame(request) + "\n"); }, "second_frame_rejected");
        Reject([&] { RentalStatusPipe::ParseRequest(std::string(4097, 'x') + "\n"); }, "oversize_rejected");
        auto invalid = Frame(request); invalid.insert(1, "\"protocolVersion\":1,");
        Reject([&] { RentalStatusPipe::ParseRequest(invalid); }, "duplicate_field_rejected");
        invalid = Frame(request); invalid.insert(1, "\"extra\":1,");
        Reject([&] { RentalStatusPipe::ParseRequest(invalid); }, "unknown_field_rejected");
        auto badNonce = request; badNonce.nonce[0] = 'A';
        Reject([&] { RentalStatusPipe::ParseRequest(Frame(badNonce)); }, "noncanonical_nonce_rejected");
        auto badScope = request; badScope.grantId = "00000000-0000-0000-0000-000000000000";
        Reject([&] { RentalStatusPipe::ParseRequest(Frame(badScope)); }, "empty_scope_rejected");
        Check(CaptureStatus(request).state == "unavailable", "observer_missing_never_confirms");
        RentalIdentity::SetObserverAvailability(true, true); RentalIdentity::BeginLogon();
        Check(CaptureStatus(request).state == "pending", "pending_no_selected_identity");
        RentalIdentity::ObserveLogonResponse(63, true, 0, 0);
        state.readAdapterReady = true;
        auto snapshot = publish();
        auto ready = CaptureStatus(request);
        Check(ready.state == "ready" && ready.actualSteamId64 == request.steamId64 && ready.grantId == request.grantId && ready.remainingAuthorizationMs <= 30000, "ready_binds_actual_scope");
        auto wrong = request; wrong.steamId64 = "76561198000000002";
        Check(CaptureStatus(wrong).state == "wrong_account", "actual_account_mismatch");
        wrong = request; wrong.grantId = request.steamAccountId;
        Check(CaptureStatus(wrong).state == "authenticated" && CaptureStatus(wrong).grantId.empty(), "requested_grant_cannot_create_scope");
        wrong = request; wrong.revision[0] = 'c';
        Check(CaptureStatus(wrong).state != "ready", "revision_mismatch");
        fixtureHooksReady = false; Check(CaptureStatus(request).state == "unavailable", "hook_missing_never_confirms"); fixtureHooksReady = true;
        std::filesystem::rename(metadata / L"grant.dat", metadata / L"grant.saved");
        Check(CaptureStatus(request).state == "unavailable", "deleted_proof_never_confirms");
        std::filesystem::rename(metadata / L"grant.saved", metadata / L"grant.dat");
        auto rotated = control; rotated.replace(rotated.find(request.grantId), request.grantId.size(), request.steamAccountId);
        Write(metadata / L"runtime.json", rotated);
        Check(CaptureStatus(request).state == "unavailable", "local_grant_rotation_never_confirms_old_snapshot");
        Write(metadata / L"runtime.json", control);
        const auto own = RentalStatusPipe::ProcessContext(GetCurrentProcess());
        Check(RentalStatusPipe::EqualContext(own, own), "same_windows_context");
        auto other = own; ++other.session;
        Check(!RentalStatusPipe::EqualContext(own, other), "different_windows_session_rejected");
        other = own; ++other.authentication.LowPart;
        Check(!RentalStatusPipe::EqualContext(own, other), "different_logon_authentication_rejected");
        RentalStatusPipe::LocalMemory sid;
        Check(ConvertStringSidToSidW(L"S-1-5-18", &sid.value), "fixture_sid_created");
        other = own; other.user = RentalStatusPipe::CopySid(sid.value);
        Check(!RentalStatusPipe::EqualContext(own, other), "different_windows_user_rejected");
        const auto pipeName = RentalStatusPipe::PipeName();
        HANDLE preclaimed = CreateNamedPipeW(pipeName.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE, PIPE_TYPE_BYTE, 1, 4096, 4096, 0, nullptr);
        Check(preclaimed != INVALID_HANDLE_VALUE, "fixture_preclaim_created");
        Check(!RentalStatusPipe::Start(CaptureStatus), "preclaimed_endpoint_is_fail_closed"); CloseHandle(preclaimed);
        Check(RentalStatusPipe::Start(CaptureStatus), "status_server_started");
        Check(!RentalStatusPipe::Start(CaptureStatus), "duplicate_start_refused");
        const auto baseline = Query(pipeName, Frame(request), GetCurrentProcessId());
        Check(baseline.At("state").String() == "ready" && baseline.At("nonce").String() == request.nonce &&
            baseline.At("actualSteamId64").String() == request.steamId64 && baseline.At("grantId").String() == request.grantId, "actual_pipe_confirmation");
        const auto instance = baseline.At("runtimeInstanceId").String();
        Write(root / L"child-request.json", Frame(request));
        wchar_t executable[32768]{}; Check(GetModuleFileNameW(nullptr, executable, 32768) != 0, "probe_image_path");
        std::wstring command = L"\"" + std::wstring(executable) + L"\" --child-query \"" + pipeName + L"\" \"" +
            (root / L"child-request.json").wstring() + L"\" " + std::to_wstring(GetCurrentProcessId());
        STARTUPINFOW startup{sizeof(startup)}; PROCESS_INFORMATION child{};
        Check(CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &child), "separate_client_process_started");
        CloseHandle(child.hThread);
        const auto childWait = WaitForSingleObject(child.hProcess, 10000);
        if (childWait != WAIT_OBJECT_0) { TerminateProcess(child.hProcess, 9); WaitForSingleObject(child.hProcess, 5000); }
        DWORD childExit = 0; GetExitCodeProcess(child.hProcess, &childExit); CloseHandle(child.hProcess);
        Check(childWait == WAIT_OBJECT_0 && childExit == 0, "real_peer_pid_same_context_accepted");
        RejectedFrame(pipeName, "{\"protocolVersion\":1}\n");
        RejectedFrame(pipeName, "{");
        Check(Query(pipeName, Frame(request), GetCurrentProcessId()).At("state").String() == "ready", "server_recovers_after_invalid_and_slow_peer");
        for (unsigned index = 0; index < 50; ++index) {
            auto fresh = request; fresh.nonce = std::string(64, static_cast<char>('a' + index % 6));
            const auto reply = Query(pipeName, Frame(fresh), GetCurrentProcessId());
            Check(reply.At("nonce").String() == fresh.nonce && reply.At("runtimeInstanceId").String() == instance && reply.At("state").String() == "ready", "repeated_pipe_nonce_and_instance");
        }
        RentalIdentity::SignOut();
        auto reply = Query(pipeName, Frame(request), GetCurrentProcessId());
        Check(reply.At("state").String() != "ready" && reply.At("actualSteamId64").String().empty() && reply.At("grantId").String().empty(), "logout_erases_confirmable_scope");
        snapshot = publish(); snapshot->deadlineTicks = GetTickCount64() - 1;
        Check(CaptureStatus(request).state != "ready", "monotonic_expiry_never_confirms");
        auto inactive = std::make_shared<RuntimeState::InactiveLease>();
        inactive->steamId = snapshot->steamId; inactive->generation = snapshot->generation;
        inactive->rentalId = request.rentalId; inactive->steamAccountId = request.steamAccountId; inactive->installationId = request.installationId;
        inactive->grantId = request.grantId; inactive->revision = request.revision; inactive->status = "expired";
        std::atomic_store(&state.inactive, std::shared_ptr<const RuntimeState::InactiveLease>(inactive));
        Check(CaptureStatus(request).state == "expired", "authoritative_expired_reported_without_authorizing");
        inactive = std::make_shared<RuntimeState::InactiveLease>(*inactive); inactive->status = "revoked";
        std::atomic_store(&state.inactive, std::shared_ptr<const RuntimeState::InactiveLease>(inactive));
        Check(CaptureStatus(request).state == "revoked", "authoritative_revoked_reported_without_authorizing");
        const auto beforeStop = GetTickCount64(); RentalStatusPipe::Stop();
        Check(GetTickCount64() - beforeStop < 4000, "server_shutdown_bounded");
        Check(RentalStatusPipe::Start(CaptureStatus), "server_restart_fixture"); RentalStatusPipe::Stop();
        std::cout << "Passed " << checks << " native status checks; synthetic identity only, no real Steam.\n";
        return 0;
    } catch (const std::exception& error) {
        RentalStatusPipe::Stop();
        std::cerr << "Status fixture failed after " << checks << " checks: " << error.what() << "; Win32=" << GetLastError() << ".\n";
        return 1;
    }
}
