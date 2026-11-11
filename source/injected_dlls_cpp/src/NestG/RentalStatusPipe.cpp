#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "RentalStatusPipe.h"
#include "RentalJson.h"
#include "RentalIdentity.h"
#include <windows.h>
#include <sddl.h>
#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace RentalStatusPipe {
namespace {
constexpr DWORD kFrameLimit = 4096, kIoBudgetMs = 2000;
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE handle = INVALID_HANDLE_VALUE) : value(handle) {}
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(const Handle&) = delete;
};
struct LocalMemory { void* value = nullptr; ~LocalMemory() { if (value) LocalFree(value); } };
struct Context {
    std::vector<BYTE> user, logon;
    DWORD session = 0;
    LUID authentication{};
};
std::vector<BYTE> TokenValue(HANDLE token, TOKEN_INFORMATION_CLASS kind) {
    DWORD size = 0;
    GetTokenInformation(token, kind, nullptr, 0, &size);
    if (!size || size > 65536) throw std::runtime_error("status_token");
    std::vector<BYTE> bytes(size);
    if (!GetTokenInformation(token, kind, bytes.data(), size, &size)) throw std::runtime_error("status_token");
    return bytes;
}
std::vector<BYTE> CopySid(PSID sid) {
    if (!IsValidSid(sid)) throw std::runtime_error("status_sid");
    std::vector<BYTE> result(GetLengthSid(sid));
    if (!::CopySid(static_cast<DWORD>(result.size()), result.data(), sid)) throw std::runtime_error("status_sid");
    return result;
}
Context ProcessContext(HANDLE process) {
    HANDLE raw = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) throw std::runtime_error("status_token");
    Handle token(raw);
    auto user = TokenValue(token.value, TokenUser);
    auto groups = TokenValue(token.value, TokenGroups);
    auto statistics = TokenValue(token.value, TokenStatistics);
    auto session = TokenValue(token.value, TokenSessionId);
    Context result;
    result.user = CopySid(reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid);
    const auto* items = reinterpret_cast<TOKEN_GROUPS*>(groups.data());
    if (items->GroupCount > 1024) throw std::runtime_error("status_groups");
    for (DWORD index = 0; index < items->GroupCount; ++index) {
        if ((items->Groups[index].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID) {
            if (!result.logon.empty()) throw std::runtime_error("status_logon");
            result.logon = CopySid(items->Groups[index].Sid);
        }
    }
    if (result.logon.empty()) throw std::runtime_error("status_logon");
    result.authentication = reinterpret_cast<TOKEN_STATISTICS*>(statistics.data())->AuthenticationId;
    result.session = *reinterpret_cast<DWORD*>(session.data());
    return result;
}
bool EqualContext(const Context& left, const Context& right) {
    return left.session == right.session && left.authentication.LowPart == right.authentication.LowPart &&
        left.authentication.HighPart == right.authentication.HighPart &&
        EqualSid(const_cast<BYTE*>(left.user.data()), const_cast<BYTE*>(right.user.data())) &&
        EqualSid(const_cast<BYTE*>(left.logon.data()), const_cast<BYTE*>(right.logon.data()));
}
bool PeerAllowed(HANDLE pipe, const Context& own) {
    ULONG pid = 0;
    if (!GetNamedPipeClientProcessId(pipe, &pid) || !pid) return false;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
    if (process.value == INVALID_HANDLE_VALUE || !process.value || WaitForSingleObject(process.value, 0) != WAIT_TIMEOUT) return false;
    try { return EqualContext(own, ProcessContext(process.value)); } catch (...) { return false; }
}
struct Server {
    std::mutex mutex;
    Provider provider;
    HANDLE stop = nullptr, finished = nullptr;
    std::atomic<bool> started{false};
    std::wstring name;
};
auto& server = *new Server;
struct Operation {
    OVERLAPPED overlap{};
    Handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    std::array<char, kFrameLimit> bytes{};
    Operation() { if (!event.value) throw std::runtime_error("status_event"); overlap.hEvent = event.value; }
};
bool Finish(HANDLE pipe, std::unique_ptr<Operation>& operation, DWORD& transferred, ULONGLONG deadline, bool& poisoned) {
    HANDLE waits[]{server.stop, operation->event.value};
    const auto now = GetTickCount64();
    const DWORD timeout = deadline > now ? static_cast<DWORD>(deadline - now) : 0;
    const DWORD waited = WaitForMultipleObjects(2, waits, FALSE, timeout);
    if (waited == WAIT_OBJECT_0 + 1) return GetOverlappedResult(pipe, &operation->overlap, &transferred, FALSE) != FALSE;
    CancelIoEx(pipe, &operation->overlap);
    // A pathological kernel cancellation must not hold this worker forever or
    // free an OVERLAPPED/buffer still owned by the kernel. Retain at most this
    // single operation and disable the endpoint if cancellation cannot drain.
    if (WaitForSingleObject(operation->event.value, 1000) != WAIT_OBJECT_0) {
        operation.release(); poisoned = true;
    }
    return false;
}
bool ReadFrame(HANDLE pipe, std::string& frame, bool& poisoned) {
    const auto deadline = GetTickCount64() + kIoBudgetMs;
    while (frame.size() < kFrameLimit) {
        auto operation = std::make_unique<Operation>();
        DWORD count = 0;
        const DWORD limit = kFrameLimit - static_cast<DWORD>(frame.size());
        const BOOL completed = ReadFile(pipe, operation->bytes.data(), limit, &count, &operation->overlap);
        if (!completed && (GetLastError() != ERROR_IO_PENDING || !Finish(pipe, operation, count, deadline, poisoned))) return false;
        if (!count) return false;
        frame.append(operation->bytes.data(), count);
        const auto newline = frame.find('\n');
        if (newline != std::string::npos) return newline + 1 == frame.size();
        if (GetTickCount64() >= deadline) return false;
    }
    return false;
}
bool WriteFrame(HANDLE pipe, const std::string& frame, bool& poisoned) {
    if (frame.size() > kFrameLimit) return false;
    auto operation = std::make_unique<Operation>();
    std::copy(frame.begin(), frame.end(), operation->bytes.begin());
    DWORD written = 0;
    const BOOL completed = WriteFile(pipe, operation->bytes.data(), static_cast<DWORD>(frame.size()), &written, &operation->overlap);
    if (!completed && (GetLastError() != ERROR_IO_PENDING || !Finish(pipe, operation, written, GetTickCount64() + kIoBudgetMs, poisoned))) return false;
    return written == frame.size();
}
void Run(HANDLE pipe, Context own) {
    Handle endpoint(pipe);
    try {
        while (WaitForSingleObject(server.stop, 0) == WAIT_TIMEOUT) {
            bool poisoned = false;
            auto operation = std::make_unique<Operation>();
            const BOOL connected = ConnectNamedPipe(endpoint.value, &operation->overlap);
            const DWORD error = connected ? ERROR_SUCCESS : GetLastError();
            if (!connected && error == ERROR_IO_PENDING) {
                DWORD unused = 0;
                // Connect itself can wait for a client, but the stop event
                // remains in the wait set and always interrupts this wait.
                if (!Finish(endpoint.value, operation, unused, GetTickCount64() + 60000, poisoned)) {
                    if (poisoned) break;
                    DisconnectNamedPipe(endpoint.value); continue;
                }
            } else if (!connected && error != ERROR_PIPE_CONNECTED) break;
            std::string frame;
            if (PeerAllowed(endpoint.value, own) && ReadFrame(endpoint.value, frame, poisoned)) {
                try {
                    const auto request = ParseRequest(frame);
                    auto reply = server.provider(request);
                    if (WriteFrame(endpoint.value, SerializeReply(request, reply), poisoned)) {
                        // A completed buffered write is not proof the client read
                        // it. Wait boundedly for its close before disconnecting;
                        // FlushFileBuffers would let a stalled client block us.
                        auto close = std::make_unique<Operation>();
                        DWORD ignored = 0;
                        if (!ReadFile(endpoint.value, close->bytes.data(), 1, &ignored, &close->overlap) && GetLastError() == ERROR_IO_PENDING)
                            Finish(endpoint.value, close, ignored, GetTickCount64() + kIoBudgetMs, poisoned);
                    }
                } catch (...) { /* Invalid frames receive no partial or reflected response. */ }
            }
            DisconnectNamedPipe(endpoint.value);
            if (poisoned) break;
        }
    } catch (...) { /* Read-only confirmation remains unavailable. */ }
    SetEvent(server.finished);
}
bool Hex(const std::string& value, size_t length) {
    return value.size() == length && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
bool Guid(const std::string& value) {
    if (value.size() != 36 || value == "00000000-0000-0000-0000-000000000000") return false;
    for (size_t index = 0; index < value.size(); ++index)
        if ((index == 8 || index == 13 || index == 18 || index == 23) ? value[index] != '-' : std::string_view("0123456789abcdef").find(value[index]) == std::string_view::npos) return false;
    return true;
}
}
Request ParseRequest(const std::string& frame) {
    if (frame.empty() || frame.size() > kFrameLimit || frame.back() != '\n' || frame.find('\n') != frame.size() - 1 ||
        std::any_of(frame.begin(), frame.end(), [](unsigned char byte) { return byte > 127; })) throw std::runtime_error("status_frame");
    const auto json = NestGRental::JsonParser(frame).Parse();
    if (json.type != NestGRental::Json::Type::Object || json.object.size() != 8 || json.At("protocolVersion").Number() != 1) throw std::runtime_error("status_request");
    Request request{json.At("nonce").String(), json.At("rentalId").String(), json.At("steamAccountId").String(),
        json.At("steamId64").String(), json.At("installationId").String(), json.At("grantId").String(), json.At("revision").String()};
    uint64_t steamId = 0;
    if (!Hex(request.nonce, 64) || !Hex(request.revision, 64) || !Guid(request.rentalId) || !Guid(request.steamAccountId) ||
        !Guid(request.installationId) || !Guid(request.grantId) || request.steamId64.size() != 17 ||
        !NestGRental::Decimal(request.steamId64, steamId) || !RentalIdentity::Tracker::IsIndividualSteamId(steamId)) throw std::runtime_error("status_scope");
    return request;
}
std::string SerializeReply(const Request& request, const Reply& reply) {
    if (!Guid(reply.runtimeInstanceId) || reply.remainingAuthorizationMs > 120000 ||
        (reply.state != "pending" && reply.state != "authenticated" && reply.state != "ready" && reply.state != "wrong_account" &&
         reply.state != "unavailable" && reply.state != "expired" && reply.state != "revoked")) throw std::runtime_error("status_reply");
    if (reply.state == "ready" && (reply.rentalId != request.rentalId || reply.steamAccountId != request.steamAccountId ||
        reply.installationId != request.installationId || reply.grantId != request.grantId || reply.revision != request.revision ||
        reply.actualSteamId64 != request.steamId64 || !reply.remainingAuthorizationMs)) throw std::runtime_error("status_ready");
    const auto quote = [](const std::string& value) {
        if (value.find_first_not_of("0123456789abcdef-_abcdefghijklmnopqrstuvwxyz") != std::string::npos) throw std::runtime_error("status_text");
        return "\"" + value + "\"";
    };
    auto result = "{\"protocolVersion\":1,\"nonce\":" + quote(request.nonce) + ",\"runtimeInstanceId\":" + quote(reply.runtimeInstanceId) +
        ",\"identityEpoch\":" + std::to_string(reply.identityEpoch) + ",\"actualSteamId64\":" + quote(reply.actualSteamId64) +
        ",\"state\":" + quote(reply.state) + ",\"remainingAuthorizationMs\":" + std::to_string(reply.remainingAuthorizationMs) +
        ",\"rentalId\":" + quote(reply.rentalId) + ",\"steamAccountId\":" + quote(reply.steamAccountId) +
        ",\"installationId\":" + quote(reply.installationId) + ",\"grantId\":" + quote(reply.grantId) + ",\"revision\":" + quote(reply.revision) + "}\n";
    if (result.size() > kFrameLimit) throw std::runtime_error("status_frame");
    return result;
}
std::wstring PipeName() {
    FILETIME created{}, exited{}, kernel{}, user{};
    if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) throw std::runtime_error("status_process");
    const uint64_t time = (static_cast<uint64_t>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
    return L"\\\\.\\pipe\\NestG.RentalStatus." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(time);
}
bool Start(Provider provider) {
    std::lock_guard lock(server.mutex);
    if (server.started.load()) return false;
    try {
        const auto own = ProcessContext(GetCurrentProcess());
        LocalMemory logonText;
        if (!ConvertSidToStringSidW(const_cast<BYTE*>(own.logon.data()), reinterpret_cast<LPWSTR*>(&logonText.value))) return false;
        const auto descriptor = L"D:P(A;;GRGW;;;" + std::wstring(static_cast<wchar_t*>(logonText.value)) + L")(A;;GA;;;SY)";
        LocalMemory security;
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(descriptor.c_str(), SDDL_REVISION_1, &security.value, nullptr)) return false;
        SECURITY_ATTRIBUTES attributes{sizeof(attributes), security.value, FALSE};
        server.name = PipeName();
        HANDLE pipe = CreateNamedPipeW(server.name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, kFrameLimit, kFrameLimit, kIoBudgetMs, &attributes);
        if (pipe == INVALID_HANDLE_VALUE) return false;
        server.stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        server.finished = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!server.stop || !server.finished) { CloseHandle(pipe); if (server.stop) CloseHandle(server.stop); if (server.finished) CloseHandle(server.finished); return false; }
        server.provider = std::move(provider);
        server.started.store(true);
        try { std::thread(Run, pipe, own).detach(); }
        catch (...) { server.started.store(false); CloseHandle(pipe); CloseHandle(server.stop); CloseHandle(server.finished); return false; }
        return true;
    } catch (...) { return false; }
}
void Stop() {
    std::lock_guard lock(server.mutex);
    if (!server.started.load()) return;
    SetEvent(server.stop);
    if (WaitForSingleObject(server.finished, 4000) == WAIT_OBJECT_0) {
        CloseHandle(server.stop); CloseHandle(server.finished);
        server.stop = server.finished = nullptr; server.provider = {}; server.started.store(false);
    }
}
}
extern "C" __declspec(dllexport) unsigned WINAPI NestGRentalStatusProtocolVersion() { return 1; }
