#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "RentalRuntime.h"
#include "RentalIdentity.h"
#include "RentalJson.h"
#include "StartupDiagnostics.h"
#include "Hook/Hooks_Package.h"
#include "Hook/Hooks_Manifest.h"
#include "OSTPlatform/include/Encoding.h"
#include "OSTPlatform/include/Detour.h"

#include <windows.h>
#include <winhttp.h>
#include <winternl.h>
#include <wincrypt.h>
#include <bcrypt.h>
#include <objbase.h>
#include <atomic>
#include <array>
#include <chrono>
#include <fstream>
#include <mutex>
#include <set>
#include <thread>
#include <unordered_map>

namespace NestGRental {
namespace fs = std::filesystem;
namespace {
constexpr char kGrantPurpose[] = "NestG.RentalRuntime.Grant.v1";
constexpr char kVaultPurpose[] = "NestG.RentalRuntime.Vault.v1";
constexpr uint64_t kMaximumAllowanceMs = 120000;
constexpr DWORD kPollMs = 30000;
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE h = INVALID_HANDLE_VALUE) : value(h) {}
    ~Handle() { if (value != INVALID_HANDLE_VALUE && value) CloseHandle(value); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
};
struct Internet {
    HINTERNET value = nullptr;
    explicit Internet(HINTERNET h = nullptr) : value(h) {}
    ~Internet() { if (value) WinHttpCloseHandle(value); }
};
struct RuntimeState {
    fs::path steamRoot;
    std::mutex changes;
    std::vector<uint32_t> additions, removals;
    std::set<uint32_t> everTracked;
    // Standard shared_ptr atomic operations retain sequential consistency on
    // libc++ implementations without atomic<shared_ptr<T>> specialization.
    std::shared_ptr<const Snapshot> active;
    std::atomic<bool> started{false};
    bool readAdapterReady = false;
    struct InactiveLease {
        uint64_t steamId = 0, generation = 0;
        std::string rentalId, steamAccountId, installationId, grantId, revision, status;
    };
    std::shared_ptr<const InactiveLease> inactive;
    struct ReadHandle { uint64_t steamId, generation, deadline; std::string rentalId, grantId, revision; };
    std::mutex handlesMutex;
    std::unordered_map<HANDLE, ReadHandle> readHandles;
};
auto& state = *new RuntimeState;
thread_local unsigned trustedFilesystemDepth = 0;
thread_local unsigned retailLuaDepth = 0;
thread_local unsigned adapterDepth = 0;
struct NativeFilesystemAccess {
    NativeFilesystemAccess() { ++trustedFilesystemDepth; }
    ~NativeFilesystemAccess() { --trustedFilesystemDepth; }
};

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
    return value;
}
bool Guid(const std::string& text) {
    if (text.size() != 36) return false;
    for (size_t i = 0; i < text.size(); ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (text[i] != '-') return false; }
        else if (!std::isxdigit(static_cast<unsigned char>(text[i]))) return false;
    }
    return true;
}
bool Under(const fs::path& path, const fs::path& root) {
    const auto child = Lower(path.lexically_normal().wstring());
    auto parent = Lower(root.lexically_normal().wstring());
    while (!parent.empty() && (parent.back() == L'\\' || parent.back() == L'/')) parent.pop_back();
    return child.size() > parent.size() && child.compare(0, parent.size(), parent) == 0 &&
        (child[parent.size()] == L'\\' || child[parent.size()] == L'/');
}
bool SafePath(const fs::path& path) {
    if (state.steamRoot.empty() || !Under(path, state.steamRoot)) return false;
    const auto relative = path.lexically_relative(state.steamRoot);
    fs::path probe = state.steamRoot;
    for (const auto& component : relative) {
        const auto name = component.wstring();
        if (name.empty() || name == L"." || name == L".." || name.find_first_of(L":/\\") != std::wstring::npos) return false;
        probe /= component;
        const DWORD attrs = GetFileAttributesW(probe.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    }
    return true;
}
struct WriterLock : Handle {
    explicit WriterLock(bool allowCreate = true) : Handle() {
        NativeFilesystemAccess trusted;
        const auto root = state.steamRoot / L"nestg-rentals";
        if (!SafePath(root)) throw std::runtime_error("rental_lock_path");
        const auto path = root / L".writer.lock";
        value = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, allowCreate ? OPEN_ALWAYS : OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        BY_HANDLE_FILE_INFORMATION info{};
        if (value == INVALID_HANDLE_VALUE || !GetFileInformationByHandle(value, &info) || info.nNumberOfLinks != 1 ||
            (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) throw std::runtime_error("rental_busy");
    }
};
std::string Read(const fs::path& path, size_t limit) {
    NativeFilesystemAccess trusted;
    if (!SafePath(path)) throw std::runtime_error("rental_path");
    Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
    BY_HANDLE_FILE_INFORMATION info{};
    if (file.value == INVALID_HANDLE_VALUE || !GetFileInformationByHandle(file.value, &info) ||
        info.nNumberOfLinks != 1 || (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) ||
        info.nFileSizeHigh || info.nFileSizeLow > limit) throw std::runtime_error("rental_file");
    std::string bytes(info.nFileSizeLow, '\0');
    DWORD read = 0;
    if (!bytes.empty() && (!ReadFile(file.value, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()))
        throw std::runtime_error("rental_read");
    return bytes;
}
std::string Sha(const std::string& bytes) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw std::runtime_error("rental_hash");
    std::array<unsigned char, 32> digest{};
    const auto result = BCryptHash(algorithm, nullptr, 0,
        reinterpret_cast<PUCHAR>(const_cast<char*>(bytes.data())), static_cast<ULONG>(bytes.size()), digest.data(), static_cast<ULONG>(digest.size()));
    BCryptCloseAlgorithmProvider(algorithm, 0);
    if (result < 0) throw std::runtime_error("rental_hash");
    constexpr char hex[] = "0123456789abcdef";
    std::string output;
    for (const auto byte : digest) { output.push_back(hex[byte >> 4]); output.push_back(hex[byte & 15]); }
    return output;
}
void WriteAtomic(const fs::path& path, const std::string& bytes) {
    NativeFilesystemAccess trusted;
    if (!SafePath(path.parent_path())) throw std::runtime_error("rental_write_path");
    const auto attrs = GetFileAttributesW(path.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)))
        throw std::runtime_error("rental_write_path");
    // Keep temporary names independent of the payload filename; appending to a
    // long manifest name can exceed MAX_PATH even when the final path is valid.
    const auto temporary = path.parent_path() / (L".n-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()) + L".tmp");
    Handle file(CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) throw std::runtime_error("rental_write");
    DWORD wrote = 0;
    if (!WriteFile(file.value, bytes.data(), static_cast<DWORD>(bytes.size()), &wrote, nullptr) || wrote != bytes.size() || !FlushFileBuffers(file.value)) {
        CloseHandle(file.value); file.value = INVALID_HANDLE_VALUE; DeleteFileW(temporary.c_str());
        throw std::runtime_error("rental_write");
    }
    CloseHandle(file.value); file.value = INVALID_HANDLE_VALUE;
    if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str()); throw std::runtime_error("rental_commit");
    }
}
std::string Protect(const std::string& input, const char* purpose, bool encrypt) {
    DATA_BLOB source{static_cast<DWORD>(input.size()), reinterpret_cast<BYTE*>(const_cast<char*>(input.data()))};
    DATA_BLOB entropy{static_cast<DWORD>(strlen(purpose)), reinterpret_cast<BYTE*>(const_cast<char*>(purpose))}, result{};
    const bool ok = encrypt ? CryptProtectData(&source, L"NestG rental data", &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &result) :
        CryptUnprotectData(&source, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &result);
    if (!ok) throw std::runtime_error("rental_protection");
    std::string bytes(reinterpret_cast<char*>(result.pbData), result.cbData);
    SecureZeroMemory(result.pbData, result.cbData); LocalFree(result.pbData);
    return bytes;
}
uint64_t Time(const std::string& value) {
    if (value.size() < 20 || value[4] != '-' || value[7] != '-' || value[10] != 'T' || value[13] != ':' || value[16] != ':')
        throw std::runtime_error("rental_time");
    auto part = [&](size_t start, size_t count) {
        uint64_t number = 0; if (!Decimal(std::string_view(value).substr(start, count), number)) throw std::runtime_error("rental_time");
        return static_cast<WORD>(number);
    };
    SYSTEMTIME time{};
    time.wYear = part(0, 4); time.wMonth = part(5, 2); time.wDay = part(8, 2);
    time.wHour = part(11, 2); time.wMinute = part(14, 2); time.wSecond = part(17, 2);
    size_t suffix = 19;
    if (suffix < value.size() && value[suffix] == '.') {
        const auto start = ++suffix;
        while (suffix < value.size() && value[suffix] >= '0' && value[suffix] <= '9') ++suffix;
        if (suffix == start || suffix - start > 7) throw std::runtime_error("rental_time");
        std::string millis(value.substr(start, std::min<size_t>(3, suffix - start)));
        while (millis.size() < 3) millis.push_back('0');
        uint64_t parsed = 0; Decimal(millis, parsed); time.wMilliseconds = static_cast<WORD>(parsed);
    }
    if (value.substr(suffix) != "Z" && value.substr(suffix) != "+00:00") throw std::runtime_error("rental_time");
    FILETIME ft{}; if (!SystemTimeToFileTime(&time, &ft)) throw std::runtime_error("rental_time");
    return (static_cast<uint64_t>(ft.dwHighDateTime) << 32 | ft.dwLowDateTime) / 10000;
}
std::string RequestId() {
    GUID id{}; wchar_t text[40]{};
    if (CoCreateGuid(&id) != S_OK || !StringFromGUID2(id, text, 40)) throw std::runtime_error("rental_request");
    std::string value; for (size_t i = 1; i < 37; ++i) value.push_back(static_cast<char>(towlower(text[i]))); return value;
}
struct Control {
    fs::path root;
    std::string origin, installationId, steamId, rentalId, grant, grantId, steamAccountId, revision;
    ~Control() { if (!grant.empty()) SecureZeroMemory(grant.data(), grant.size()); }
};
Control LoadControl(const fs::path& root) {
    const auto json = JsonParser(Read(root / L".nestg" / L"runtime.json", 16384)).Parse();
    Control control;
    control.root = root; control.origin = json.At("apiOrigin").String(); control.installationId = json.At("installationId").String();
    control.steamId = json.At("steamId64").String(); control.rentalId = json.At("rentalId").String();
    control.grantId = json.At("grantId").String(); control.steamAccountId = json.At("steamAccountId").String(); control.revision = json.At("revision").String();
    if (json.At("protocolVersion").Number() != 1 || !Guid(control.installationId) || !Guid(control.rentalId) ||
        !Guid(control.grantId) || !Guid(control.steamAccountId) || control.revision.size() != 64 ||
        control.revision.find_first_not_of("0123456789abcdef") != std::string::npos ||
        root.filename() != fs::u8path(control.rentalId) || root.parent_path().filename() != fs::u8path(control.steamId) ||
        json.At("grantFile").String() != "grant.dat" || json.At("inventoryFile").String() != "inventory.json") throw std::runtime_error("rental_control");
    control.grant = Protect(Read(root / L".nestg" / L"grant.dat", 16384), kGrantPurpose, false);
    if (control.grant.size() != 43 || control.grant.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_") != std::string::npos)
        throw std::runtime_error("rental_grant");
    return control;
}
Json Check(const Control& control, const std::string& requestId, uint64_t steamId) {
    const auto url = OSTPlatform::Encoding::Utf8ToWide(control.origin);
    URL_COMPONENTS components{}; components.dwStructSize = sizeof(components);
    components.dwHostNameLength = components.dwUrlPathLength = components.dwUserNameLength = components.dwPasswordLength = components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &components) || components.nScheme != INTERNET_SCHEME_HTTPS ||
        components.dwUserNameLength || components.dwPasswordLength || components.dwExtraInfoLength ||
        (components.dwUrlPathLength && std::wstring(components.lpszUrlPath, components.dwUrlPathLength) != L"/")) throw std::runtime_error("rental_origin");
    Internet session(WinHttpOpen(L"NestG-RentalRuntime/1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session.value || !WinHttpSetTimeouts(session.value, 3000, 3000, 3000, 5000)) throw std::runtime_error("rental_http");
    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    const auto normalizedHost = Lower(host);
    if (!((normalizedHost == L"nestg.cloud" && components.nPort == INTERNET_DEFAULT_HTTPS_PORT) ||
        normalizedHost == L"localhost" || normalizedHost == L"127.0.0.1" || normalizedHost == L"[::1]" || normalizedHost == L"::1"))
        throw std::runtime_error("rental_origin");
    const auto totalDeadline = GetTickCount64() + 15000;
    Internet connection(WinHttpConnect(session.value, host.c_str(), components.nPort, 0));
    Internet request(connection.value ? WinHttpOpenRequest(connection.value, L"POST", L"/api/desktop/account-rentals/runtime/check",
        nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE) : nullptr);
    DWORD disabled = WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_AUTHENTICATION;
    if (!request.value || !WinHttpSetOption(request.value, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled))) throw std::runtime_error("rental_http");
    const std::string body = "{\"requestId\":\"" + requestId + "\",\"steamId64\":\"" + std::to_string(steamId) +
        "\",\"installationId\":\"" + control.installationId + "\",\"protocolVersion\":1}";
    std::wstring headers = L"Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer ";
    headers.append(control.grant.begin(), control.grant.end()); headers += L"\r\n";
    const bool sent = WinHttpSendRequest(request.value, headers.c_str(), static_cast<DWORD>(headers.size()),
        const_cast<char*>(body.data()), static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0);
    SecureZeroMemory(headers.data(), headers.size() * sizeof(wchar_t));
    DWORD status = 0, length = sizeof(status);
    if (!sent || !WinHttpReceiveResponse(request.value, nullptr) ||
        !WinHttpQueryHeaders(request.value, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, nullptr, &status, &length, nullptr) || status != 200)
        throw std::runtime_error("rental_http");
    std::string response;
    for (;;) {
        if (GetTickCount64() >= totalDeadline) throw std::runtime_error("rental_http_deadline");
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.value, &available)) throw std::runtime_error("rental_http");
        if (!available) break;
        if (response.size() + available > 65536) throw std::runtime_error("rental_http_size");
        const auto size = response.size(); response.resize(size + available); DWORD received = 0;
        if (!WinHttpReadData(request.value, response.data() + size, available, &received) || !received) throw std::runtime_error("rental_http");
        response.resize(size + received);
    }
    if (GetTickCount64() >= totalDeadline) throw std::runtime_error("rental_http_deadline");
    return JsonParser(response).Parse();
}
struct InventoryFile { std::string relative, sha; uint32_t app; uint64_t size; };
std::vector<InventoryFile> Inventory(const Control& control) {
    const auto json = JsonParser(Read(control.root / L".nestg" / L"inventory.json", 4 * 1024 * 1024)).Parse();
    if (json.At("protocolVersion").Number() != 1 || json.At("steamId64").String() != control.steamId ||
        json.At("rentalId").String() != control.rentalId || json.At("revision").String() != control.revision)
        throw std::runtime_error("rental_inventory");
    const auto& files = json.At("files");
    if (files.type != Json::Type::Array || files.array.size() > 4000) throw std::runtime_error("rental_inventory");
    std::vector<InventoryFile> result;
    std::set<std::string> seen;
    uint64_t total = 0;
    for (const auto& file : files.array) {
        InventoryFile item{file.At("relativePath").String(), file.At("sha256").String(), static_cast<uint32_t>(file.At("steamAppId").Number()), file.At("sizeBytes").Number()};
        if (item.app == 0 || file.At("steamAppId").Number() > UINT32_MAX || item.sha.size() != 64 || item.sha.find_first_not_of("0123456789abcdef") != std::string::npos ||
            item.relative.find_first_of("\\:") != std::string::npos || item.relative.find("..") != std::string::npos || item.relative.find('\0') != std::string::npos ||
            item.relative.size() > 160 || item.size > 64 * 1024 * 1024 || !seen.insert(item.relative).second || (total += item.size) > 512 * 1024 * 1024)
            throw std::runtime_error("rental_inventory");
        const fs::path relative = fs::u8path(item.relative);
        const auto kind = relative.extension() == L".lua" ? fs::path(L"lua") : fs::path(L"manifests");
        const auto scopedParent = kind / std::to_wstring(item.app);
        if (relative.is_absolute() || (relative.parent_path() != kind && relative.parent_path() != scopedParent) ||
            (relative.extension() != L".lua" && relative.extension() != L".manifest")) throw std::runtime_error("rental_inventory");
        result.push_back(std::move(item));
    }
    return result;
}
std::string Verified(const Control& control, const InventoryFile& item) {
    auto bytes = Read(control.root / fs::u8path(item.relative), static_cast<size_t>(item.size));
    if (bytes.size() != item.size || Sha(bytes) != item.sha) throw std::runtime_error("rental_integrity");
    return bytes;
}
void Publish(std::shared_ptr<const Snapshot> next) {
    {
        std::lock_guard lock(state.changes);
        auto old = std::atomic_exchange(&state.active, next);
        if (!old && !next) return;
        if (old) for (const auto& [id, key] : old->data.depotKeys) if (!next || !next->data.depotKeys.count(id)) state.removals.push_back(id);
        if (next) for (const auto& [id, key] : next->data.depotKeys) {
            state.everTracked.insert(id);
            if (!old || !old->data.depotKeys.count(id)) state.additions.push_back(id);
        }
    }
    Hooks_Package::RequestRentalRefresh();
}
void RevokeLease(const Control& control) {
    bool changed = false;
    {
        std::lock_guard lock(state.changes);
        const auto active = std::atomic_load(&state.active);
        if (active && active->rentalId == control.rentalId && active->grantId == control.grantId && active->revision == control.revision) {
            std::atomic_store(&state.active, std::shared_ptr<const Snapshot>{});
            for (const auto& [id, key] : active->data.depotKeys) state.removals.push_back(id);
            changed = true;
        }
    }
    if (changed) Hooks_Package::RequestRentalRefresh();
}
void Vault(const Control& control) {
    NativeFilesystemAccess trusted;
    WriterLock lease;
    const auto latest = LoadControl(control.root);
    if (latest.revision != control.revision || latest.grantId != control.grantId) throw std::runtime_error("rental_revision_changed");
    // Each file is committed independently. On a crash, an already verified
    // encrypted copy remains; the source is removed only after a round-trip
    // integrity check. The inventory is retained as the recovery authority.
    for (const auto& item : Inventory(control)) {
        const auto source = control.root / fs::u8path(item.relative);
        if (!SafePath(source)) continue;
        auto plain = Verified(control, item);
        const auto encrypted = Protect(plain, kVaultPurpose, true);
        const auto destination = control.root / L".nestg" / L"vault" / fs::u8path(item.relative + ".dpapi");
        std::error_code error;
        auto directory = control.root;
        for (const auto& component : destination.parent_path().lexically_relative(control.root)) {
            if (!SafePath(directory)) throw std::runtime_error("rental_vault_path");
            directory /= component;
            if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) throw std::runtime_error("rental_vault_path");
            if (!SafePath(directory)) throw std::runtime_error("rental_vault_path");
        }
        WriteAtomic(destination, encrypted);
        auto verified = Protect(Read(destination, static_cast<size_t>(item.size + 16384)), kVaultPurpose, false);
        const bool valid = Sha(verified) == item.sha;
        SecureZeroMemory(verified.data(), verified.size()); SecureZeroMemory(plain.data(), plain.size());
        if (!valid || !SafePath(source) || Sha(Read(source, static_cast<size_t>(item.size))) != item.sha || !DeleteFileW(source.c_str()))
            throw std::runtime_error("rental_vault_commit");
    }
    NestGStartup::Write("rental.vault.complete");
}
std::shared_ptr<const Snapshot> Authorize(const Control& control, const Json& reply, const RentalIdentity::Snapshot& identity, uint64_t started) {
    WriterLock lease;
    const auto latest = LoadControl(control.root);
    if (latest.revision != control.revision || latest.grantId != control.grantId) throw std::runtime_error("rental_revision_changed");
    if (reply.At("protocolVersion").Number() != 1 || reply.At("steamId64").String() != control.steamId ||
        reply.At("rentalId").String() != control.rentalId || reply.At("installationId").String() != control.installationId ||
        reply.At("grantId").String() != control.grantId || reply.At("steamAccountId").String() != control.steamAccountId || reply.At("revision").String() != control.revision)
        throw std::runtime_error("rental_response_scope");
    const auto now = Time(reply.At("serverNowUtc").String());
    const auto end = Time(reply.At("endsAtUtc").String());
    const auto allowance = Time(reply.At("authorizationExpiresAtUtc").String());
    const auto deadline = std::min(end, allowance);
    if (deadline <= now || deadline - now > kMaximumAllowanceMs || GetTickCount64() - started >= deadline - now) throw std::runtime_error("rental_allowance");
    const auto& allowed = reply.At("allowedAppIds");
    if (allowed.type != Json::Type::Array || allowed.array.size() > 2048) throw std::runtime_error("rental_apps");
    std::set<uint32_t> appIds;
    for (const auto& value : allowed.array) { const auto app = value.Number(); if (!app || app > UINT32_MAX) throw std::runtime_error("rental_apps"); appIds.insert(static_cast<uint32_t>(app)); }
    auto snapshot = std::make_shared<Snapshot>();
    snapshot->steamId = identity.steamId; snapshot->generation = identity.generation;
    snapshot->deadlineTicks = started + deadline - now; snapshot->rentalId = control.rentalId; snapshot->root = control.root;
    snapshot->grantId = control.grantId; snapshot->revision = control.revision;
    snapshot->steamAccountId = control.steamAccountId; snapshot->installationId = control.installationId;
    for (const auto& item : Inventory(control)) {
        if (!appIds.count(item.app)) continue;
        const auto relative = fs::u8path(item.relative);
        auto bytes = Verified(control, item);
        if (relative.extension() == L".lua") {
            Data data;
            if (item.size > 1024 * 1024 || !DataParser(bytes).Parse(data) || !data.depotKeys.count(item.app) || !Merge(snapshot->data, data))
                throw std::runtime_error("rental_data");
            if (snapshot->data.depotKeys.size() > 65536 || snapshot->data.accessTokens.size() > 16384 ||
                snapshot->data.statIds.size() > 4096 || snapshot->data.manifests.size() > 65536 || snapshot->data.pinned.size() > 65536)
                throw std::runtime_error("rental_data_limit");
        } else {
            const auto file = relative.filename().wstring();
            const auto separator = file.find(L'_'), dot = file.find(L'.');
            if (separator == std::wstring::npos || dot == std::wstring::npos || separator >= dot) throw std::runtime_error("rental_manifest");
            uint64_t depot = 0, gid = 0;
            const std::string narrow = OSTPlatform::Encoding::WideToUtf8(file);
            if (!Decimal(std::string_view(narrow).substr(0, separator), depot) || !depot || depot > UINT32_MAX ||
                !Decimal(std::string_view(narrow).substr(separator + 1, dot - separator - 1), gid) || !gid) throw std::runtime_error("rental_manifest");
            const auto key = std::to_wstring(item.app) + L"/" + Lower(file);
            snapshot->manifestFiles[key] = {control.root / relative, item.size, item.sha};
        }
        SecureZeroMemory(bytes.data(), bytes.size());
    }
    const auto current = RentalIdentity::Capture();
    if (current.state != RentalIdentity::State::Authenticated || current.generation != identity.generation || current.steamId != identity.steamId)
        throw std::runtime_error("rental_account_changed");
    return snapshot;
}
std::vector<fs::path> DiscoverCandidates(const fs::path& accountRoot, const std::shared_ptr<const Snapshot>& prior) {
    struct Candidate { fs::path path; fs::file_time_type modified; bool current; };
    std::vector<Candidate> candidates;
    const auto less = [](const Candidate& left, const Candidate& right) {
        return left.current != right.current ? !left.current : left.modified < right.modified;
    };
    if (prior && SafePath(prior->root)) candidates.push_back({prior->root, fs::file_time_type::max(), true});
    std::error_code error;
    for (const auto& entry : fs::directory_iterator(accountRoot, error)) {
        if (error) break;
        if (!Guid(entry.path().filename().string()) || !entry.is_directory(error) || !SafePath(entry.path()) ||
            (prior && entry.path() == prior->root)) continue;
        std::error_code timestampError;
        const auto modified = fs::last_write_time(entry.path() / L".nestg" / L"runtime.json", timestampError);
        if (timestampError) continue;
        Candidate candidate{entry.path(), modified, false};
        if (candidates.size() < 128) candidates.push_back(std::move(candidate));
        else {
            const auto oldest = std::min_element(candidates.begin(), candidates.end(), less);
            if (less(*oldest, candidate)) *oldest = std::move(candidate);
        }
    }
    std::sort(candidates.begin(), candidates.end(), [&](const auto& left, const auto& right) { return less(right, left); });
    std::vector<fs::path> result;
    for (const auto& candidate : candidates) result.push_back(candidate.path);
    return result;
}
void Run() {
    uint64_t generation = UINT64_MAX, nextCheck = 0;
    size_t candidateCursor = 0;
    for (;;) {
        try {
            const auto identity = RentalIdentity::Capture();
            if (identity.generation != generation) { Publish(nullptr); generation = identity.generation; nextCheck = 0; candidateCursor = 0; }
            auto active = std::atomic_load(&state.active);
            if (active && (!identity.observerReady || identity.state != RentalIdentity::State::Authenticated || GetTickCount64() >= active->deadlineTicks)) Publish(nullptr);
            if (state.readAdapterReady && Hooks_Manifest::RentalReadReady() && Hooks_Package::RentalIsolationReady() && identity.observerReady &&
                identity.state == RentalIdentity::State::Authenticated && GetTickCount64() >= nextCheck) {
                nextCheck = GetTickCount64() + kPollMs;
                const auto accountRoot = state.steamRoot / L"nestg-rentals" / std::to_wstring(identity.steamId);
                if (SafePath(accountRoot)) {
                    const auto prior = Acquire();
                    auto candidates = DiscoverCandidates(accountRoot, prior);
                    const size_t offset = prior && !candidates.empty() && candidates.front() == prior->root ? 1 : 0;
                    const auto remaining = candidates.size() - offset;
                    if (remaining) std::rotate(candidates.begin() + offset, candidates.begin() + offset + candidateCursor % remaining, candidates.end());
                    size_t checked = 0;
                    bool authorized = false;
                    for (const auto& entry : candidates) {
                        if (++checked > 4 || (authorized && checked > 2)) break;
                        if (!prior || entry != prior->root) ++candidateCursor;
                        try {
                            auto control = [&]() { WriterLock lease; return LoadControl(entry); }();
                            const auto request = RequestId(); const auto begin = GetTickCount64();
                            const auto reply = Check(control, request, identity.steamId);
                            if (reply.At("requestId").String() != request || reply.At("steamId64").String() != control.steamId ||
                                reply.At("rentalId").String() != control.rentalId || reply.At("installationId").String() != control.installationId || reply.At("protocolVersion").Number() != 1 ||
                                reply.At("grantId").String() != control.grantId || reply.At("steamAccountId").String() != control.steamAccountId)
                                throw std::runtime_error("rental_response_scope");
                            const auto current = RentalIdentity::Capture();
                            if (current.generation != identity.generation || current.steamId != identity.steamId || current.state != RentalIdentity::State::Authenticated) break;
                            const auto status = reply.At("status").String();
                            if (status == "active") {
                                if (reply.At("revision").String() != control.revision) {
                                    RevokeLease(control); NestGStartup::Write("rental.prepare.required"); continue;
                                }
                                if (!authorized) { Publish(Authorize(control, reply, identity, begin)); authorized = true; NestGStartup::Write("rental.authorized"); }
                            }
                            else if (status == "expired" || status == "revoked" || status == "not_started" || status == "released" || status == "no_active_rental" || status == "unmanaged") {
                                auto inactive = std::make_shared<RuntimeState::InactiveLease>();
                                inactive->steamId = identity.steamId; inactive->generation = identity.generation;
                                inactive->rentalId = control.rentalId; inactive->steamAccountId = control.steamAccountId;
                                inactive->installationId = control.installationId; inactive->grantId = control.grantId;
                                inactive->revision = control.revision; inactive->status = status == "expired" ? "expired" : "revoked";
                                std::atomic_store(&state.inactive, std::shared_ptr<const RuntimeState::InactiveLease>(inactive));
                                RevokeLease(control); if (status == "expired") Vault(control);
                            }
                            else throw std::runtime_error("rental_status");
                        } catch (...) { NestGStartup::Write("rental.check.unavailable"); }
                    }
                }
            }
        } catch (...) { NestGStartup::Write("rental.check.unavailable"); }
        Sleep(250);
    }
}
void Guard() {
    // Keep revocation independent from DNS/network timeouts and from the number
    // of registered leases. Getters also validate on every individual read.
    for (;;) {
        const auto identity = RentalIdentity::Capture();
        const auto snapshot = std::atomic_load(&state.active);
        if (snapshot && (!identity.observerReady || identity.state != RentalIdentity::State::Authenticated ||
            identity.generation != snapshot->generation || identity.steamId != snapshot->steamId || GetTickCount64() >= snapshot->deadlineTicks ||
            !SafePath(snapshot->root / L".nestg" / L"grant.dat"))) {
            auto expected = snapshot;
            {
                std::lock_guard lock(state.changes);
                if (std::atomic_compare_exchange_strong(&state.active, &expected, std::shared_ptr<const Snapshot>{}))
                    for (const auto& [id, key] : snapshot->data.depotKeys) state.removals.push_back(id);
            }
            if (expected == snapshot) Hooks_Package::RequestRentalRefresh();
        }
        Sleep(100);
    }
}

// A fiber-local exact pathname mapping exists only around the original Steam
// manifest load. Ordinary retail filesystem calls do not enter this adapter.
struct ReadScope {
    std::shared_ptr<const Snapshot> snapshot;
    std::wstring expected;
    Snapshot::ManifestFile target;
};
DWORD scopeSlot = FLS_OUT_OF_INDEXES;
using NtCreateFileFunction = NTSTATUS(NTAPI*)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES, PIO_STATUS_BLOCK, PLARGE_INTEGER,
    ULONG, ULONG, ULONG, ULONG, PVOID, ULONG);
NtCreateFileFunction realNtCreateFile = nullptr;
using NtReadFileFunction = NTSTATUS(NTAPI*)(HANDLE, HANDLE, PIO_APC_ROUTINE, PVOID, PIO_STATUS_BLOCK, PVOID, ULONG, PLARGE_INTEGER, PULONG);
using NtCloseFunction = NTSTATUS(NTAPI*)(HANDLE);
using NtCreateSectionFunction = NTSTATUS(NTAPI*)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES, PLARGE_INTEGER, ULONG, ULONG, HANDLE);
using NtDuplicateObjectFunction = NTSTATUS(NTAPI*)(HANDLE, HANDLE, HANDLE, PHANDLE, ACCESS_MASK, ULONG, ULONG);
NtReadFileFunction realNtReadFile = nullptr;
NtCloseFunction realNtClose = nullptr;
NtCreateSectionFunction realNtCreateSection = nullptr;
NtDuplicateObjectFunction realNtDuplicateObject = nullptr;
NTSTATUS NTAPI ReadHandleAdapter(HANDLE handle, HANDLE event, PIO_APC_ROUTINE routine, PVOID context, PIO_STATUS_BLOCK io,
    PVOID buffer, ULONG length, PLARGE_INTEGER offset, PULONG key) {
    bool denied = false;
    {
        std::lock_guard lock(state.handlesMutex);
        const auto found = state.readHandles.find(handle);
        if (found != state.readHandles.end()) {
            const auto current = Acquire();
            denied = !current || current->steamId != found->second.steamId || current->generation != found->second.generation ||
                current->rentalId != found->second.rentalId || current->grantId != found->second.grantId || current->revision != found->second.revision;
        }
    }
    if (denied) {
        if (io) { io->Status = static_cast<NTSTATUS>(0xC0000022L); io->Information = 0; }
        return static_cast<NTSTATUS>(0xC0000022L);
    }
    return realNtReadFile(handle, event, routine, context, io, buffer, length, offset, key);
}
NTSTATUS NTAPI CloseHandleAdapter(HANDLE handle) {
    // Erase before the OS can recycle the numeric HANDLE for another open.
    { std::lock_guard lock(state.handlesMutex); state.readHandles.erase(handle); }
    return realNtClose(handle);
}
NTSTATUS NTAPI SectionAdapter(PHANDLE section, ACCESS_MASK access, POBJECT_ATTRIBUTES attributes, PLARGE_INTEGER size,
    ULONG protection, ULONG allocation, HANDLE file) {
    {
        std::lock_guard lock(state.handlesMutex);
        // A mapped view could outlive account revocation without another read
        // syscall. Until a revocable mapped-view reader is implemented, rental
        // manifest mapping fails closed. Ordinary Steam/retail mappings pass.
        if (state.readHandles.count(file)) return static_cast<NTSTATUS>(0xC0000022L);
    }
    return realNtCreateSection(section, access, attributes, size, protection, allocation, file);
}
NTSTATUS NTAPI DuplicateAdapter(HANDLE sourceProcess, HANDLE source, HANDLE targetProcess, PHANDLE target,
    ACCESS_MASK access, ULONG attributes, ULONG options) {
    RuntimeState::ReadHandle tag{};
    bool tagged = false;
    {
        std::lock_guard lock(state.handlesMutex);
        const auto found = state.readHandles.find(source);
        if (found != state.readHandles.end()) {
            const auto sourcePid = sourceProcess == GetCurrentProcess() ? GetCurrentProcessId() : GetProcessId(sourceProcess);
            // An unqueryable source process cannot be used to bypass a tag.
            if (!sourcePid) return static_cast<NTSTATUS>(0xC0000022L);
            if (sourcePid == GetCurrentProcessId()) { tagged = true; tag = found->second; }
        }
    }
    if (!tagged) return realNtDuplicateObject(sourceProcess, source, targetProcess, target, access, attributes, options);
    const auto targetPid = targetProcess == GetCurrentProcess() ? GetCurrentProcessId() : GetProcessId(targetProcess);
    if (targetPid != GetCurrentProcessId()) return static_cast<NTSTATUS>(0xC0000022L);
    if (options & 1 /* DUPLICATE_CLOSE_SOURCE */) { std::lock_guard lock(state.handlesMutex); state.readHandles.erase(source); }
    const auto result = realNtDuplicateObject(sourceProcess, source, targetProcess, target, access, attributes, options);
    if (result >= 0 && target && *target) { std::lock_guard lock(state.handlesMutex); state.readHandles[*target] = std::move(tag); }
    return result;
}
std::wstring ObjectName(const OBJECT_ATTRIBUTES* attributes) {
    if (!attributes || !attributes->ObjectName || !attributes->ObjectName->Buffer ||
        attributes->ObjectName->Length % sizeof(wchar_t) || attributes->ObjectName->Length > 32766) return {};
    std::wstring path(attributes->ObjectName->Buffer, attributes->ObjectName->Length / sizeof(wchar_t));
    if (attributes->RootDirectory && !path.empty() && path[0] != L'\\') {
        // This hook also runs on SteamUI workers/fibers with small stacks.
        // Keep the bounded path buffer on the heap; allocation failure reaches
        // ReadAdapter's fail-closed exception boundary.
        std::vector<wchar_t> root(32768);
        const auto length = GetFinalPathNameByHandleW(attributes->RootDirectory, root.data(), static_cast<DWORD>(root.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
        if (!length || length >= root.size()) return {};
        path = std::wstring(root.data(), length) + L"\\" + path;
    }
    if (path.starts_with(L"\\??\\") || path.starts_with(L"\\\\?\\")) path.erase(0, 4);
    return Lower(fs::path(path).lexically_normal().wstring());
}
NTSTATUS NTAPI ReadAdapter(PHANDLE handle, ACCESS_MASK access, POBJECT_ATTRIBUTES attributes, PIO_STATUS_BLOCK io,
    PLARGE_INTEGER allocation, ULONG fileAttributes, ULONG share, ULONG disposition, ULONG options, PVOID ea, ULONG eaLength) {
    if (adapterDepth) return realNtCreateFile(handle, access, attributes, io, allocation, fileAttributes, share, disposition, options, ea, eaLength);
    struct Depth { Depth() { ++adapterDepth; } ~Depth() { --adapterDepth; } } depth;
    try {
    auto name = ObjectName(attributes);
    // A retail dofile/loadfile/IO call must not bypass the parser exclusion.
    // Only this module's bounded inventory/DPAPI helpers and the scoped mapping
    // can open a file from a rental source inside Steam.
    if (!trustedFilesystemDepth && !name.empty() &&
        (retailLuaDepth || name.find(L"nestg-rentals") != std::wstring::npos) && IsReservedPath(fs::path(name))) return static_cast<NTSTATUS>(0xC0000022L);
    auto* scope = scopeSlot == FLS_OUT_OF_INDEXES ? nullptr : static_cast<ReadScope*>(FlsGetValue(scopeSlot));
    if (scope && !name.empty() && name != scope->expected) {
        std::error_code error;
        const auto canonical = fs::weakly_canonical(fs::path(name), error);
        if (!error && Lower(canonical.wstring()) == scope->expected) name = scope->expected;
        else {
            const auto file = fs::path(name).filename().wstring();
            const auto expectedFile = fs::path(scope->expected).filename().wstring();
            const auto extension = Lower(fs::path(file).extension().wstring());
            if (file == expectedFile || extension == L".manifest" || extension == L".man") return static_cast<NTSTATUS>(0xC0000022L);
        }
    }
    if (!scope || name != scope->expected) return realNtCreateFile(handle, access, attributes, io, allocation, fileAttributes, share, disposition, options, ea, eaLength);
    const auto current = Acquire();
    constexpr ACCESS_MASK writes = GENERIC_WRITE | GENERIC_ALL | MAXIMUM_ALLOWED | FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_ATTRIBUTES | FILE_WRITE_EA | DELETE | WRITE_DAC | WRITE_OWNER;
    const auto sameLease = [&](const std::shared_ptr<const Snapshot>& candidate) {
        return candidate && candidate->steamId == scope->snapshot->steamId && candidate->generation == scope->snapshot->generation &&
            candidate->rentalId == scope->snapshot->rentalId && candidate->grantId == scope->snapshot->grantId && candidate->revision == scope->snapshot->revision;
    };
    if (!sameLease(current) || (access & writes) || (options & 0x1000 /* FILE_DELETE_ON_CLOSE */) || disposition != 1 /* FILE_OPEN */ || !SafePath(scope->target.path)) {
        if (handle) *handle = nullptr;
        if (io) { io->Status = static_cast<NTSTATUS>(0xC0000022L); io->Information = 0; }
        return static_cast<NTSTATUS>(0xC0000022L);
    }
    std::unique_ptr<WriterLock> lease;
    try {
        lease = std::make_unique<WriterLock>();
        const auto bytes = Read(scope->target.path, static_cast<size_t>(scope->target.size));
        if (bytes.size() != scope->target.size || Sha(bytes) != scope->target.sha) return static_cast<NTSTATUS>(0xC0000022L);
    } catch (...) { return static_cast<NTSTATUS>(0xC0000022L); }
    const auto finalAuthorization = Acquire();
    if (!sameLease(finalAuthorization)) return static_cast<NTSTATUS>(0xC0000022L);
    auto destination = scope->target.path.lexically_normal();
    destination.make_preferred(); // NtCreateFile does not normalize '/' like Win32.
    auto target = L"\\??\\" + destination.wstring();
    if (target.size() > 16382) return static_cast<NTSTATUS>(0xC0000033L);
    UNICODE_STRING targetName{}; targetName.Buffer = target.data(); targetName.Length = static_cast<USHORT>(target.size() * sizeof(wchar_t)); targetName.MaximumLength = targetName.Length;
    OBJECT_ATTRIBUTES redirected = *attributes; redirected.RootDirectory = nullptr; redirected.ObjectName = &targetName;
    const auto result = realNtCreateFile(handle, access, &redirected, io, allocation, fileAttributes, share & FILE_SHARE_READ, disposition,
        options | FILE_OPEN_REPARSE_POINT, ea, eaLength);
    if (result >= 0 && handle && *handle) {
        std::lock_guard lock(state.handlesMutex);
        state.readHandles[*handle] = {current->steamId, current->generation, current->deadlineTicks, current->rentalId, current->grantId, current->revision};
    }
    return result;
    } catch (...) { return static_cast<NTSTATUS>(0xC0000022L); }
}
}

bool Start(const fs::path& steamRoot) {
    if (state.started.exchange(true)) return state.readAdapterReady;
    std::error_code error;
    state.steamRoot = fs::weakly_canonical(steamRoot, error);
    if (error || state.steamRoot.empty()) { NestGStartup::Write("rental.start.failed"); return false; }
    state.readAdapterReady = InstallReadAdapter();
    if (!state.readAdapterReady) { NestGStartup::Write("rental.read_adapter.failed"); return false; }
    std::thread(Run).detach();
    std::thread(Guard).detach();
    if (!RentalStatusPipe::Start(CaptureStatus)) NestGStartup::Write("rental.status.unavailable");
    NestGStartup::Write("rental.monitor.started");
    return true;
}
std::shared_ptr<const Snapshot> Acquire() {
    auto snapshot = std::atomic_load(&state.active);
    if (!snapshot || GetTickCount64() >= snapshot->deadlineTicks) return {};
    const auto identity = RentalIdentity::Capture();
    if (!identity.observerReady || identity.state != RentalIdentity::State::Authenticated || identity.generation != snapshot->generation || identity.steamId != snapshot->steamId) return {};
    return snapshot;
}
RentalStatusPipe::Reply CaptureStatus(const RentalStatusPipe::Request& request) {
    RentalStatusPipe::Reply result;
    static const std::string instance = RequestId();
    result.runtimeInstanceId = instance;
    const auto identity = RentalIdentity::Capture();
    result.identityEpoch = identity.generation;
    if (!identity.observerReady) return result;
    if (identity.state == RentalIdentity::State::Pending || identity.state == RentalIdentity::State::SignedOut) {
        result.state = "pending"; return result;
    }
    if (identity.state != RentalIdentity::State::Authenticated) return result;
    result.actualSteamId64 = std::to_string(identity.steamId);
    if (result.actualSteamId64 != request.steamId64) { result.state = "wrong_account"; return result; }
    result.state = "authenticated";
    if (!state.readAdapterReady || !Hooks_Manifest::RentalReadReady() || !Hooks_Package::RentalIsolationReady()) {
        result.state = "unavailable"; return result;
    }
    auto snapshot = Acquire();
    if (!snapshot) {
        const auto inactive = std::atomic_load(&state.inactive);
        if (inactive && inactive->steamId == identity.steamId && inactive->generation == identity.generation &&
            inactive->rentalId == request.rentalId && inactive->steamAccountId == request.steamAccountId &&
            inactive->installationId == request.installationId && inactive->grantId == request.grantId && inactive->revision == request.revision)
            result.state = inactive->status;
        return result;
    }
    if (snapshot->rentalId != request.rentalId || snapshot->steamAccountId != request.steamAccountId ||
        snapshot->installationId != request.installationId || snapshot->grantId != request.grantId || snapshot->revision != request.revision)
        return result;
    try {
        // Status is read-only and never renews a lease. Reopen the actual
        // protected proof/control so a deleted/rotated grant cannot confirm.
        WriterLock lease(false);
        auto control = LoadControl(snapshot->root);
        const bool currentControl = control.steamId == result.actualSteamId64 && control.rentalId == snapshot->rentalId &&
            control.steamAccountId == snapshot->steamAccountId && control.installationId == snapshot->installationId &&
            control.grantId == snapshot->grantId && control.revision == snapshot->revision;
        SecureZeroMemory(control.grant.data(), control.grant.size());
        const auto current = RentalIdentity::Capture();
        const auto authorized = Acquire();
        if (!currentControl || !authorized || current.generation != identity.generation || current.steamId != identity.steamId ||
            authorized->generation != snapshot->generation || authorized->grantId != snapshot->grantId ||
            authorized->rentalId != snapshot->rentalId || authorized->revision != snapshot->revision) {
            result.state = "unavailable"; return result;
        }
        const auto now = GetTickCount64();
        if (authorized->deadlineTicks <= now || authorized->deadlineTicks - now > kMaximumAllowanceMs) return result;
        result.state = "ready"; result.remainingAuthorizationMs = authorized->deadlineTicks - now;
        result.rentalId = authorized->rentalId; result.steamAccountId = authorized->steamAccountId;
        result.installationId = authorized->installationId; result.grantId = authorized->grantId; result.revision = authorized->revision;
    } catch (...) { result.state = "unavailable"; }
    return result;
}
bool IsReservedPath(const fs::path& path) {
    auto contains = [](const fs::path& value) { for (const auto& component : value) if (Lower(component.wstring()) == L"nestg-rentals") return true; return false; };
    if (contains(path.lexically_normal())) return true;
    std::error_code error; const auto resolved = fs::weakly_canonical(path, error);
    return !error && contains(resolved);
}
bool IsTrackedDepot(uint32_t app, uint32_t depot) {
    std::lock_guard lock(state.changes); return state.everTracked.count(depot) || state.everTracked.count(app);
}
std::vector<uint32_t> TakeAdded() { std::lock_guard lock(state.changes); std::vector<uint32_t> result; result.swap(state.additions); return result; }
std::vector<uint32_t> TakeRemoved() { std::lock_guard lock(state.changes); std::vector<uint32_t> result; result.swap(state.removals); return result; }
bool InstallReadAdapter() {
    if (realNtCreateFile) return state.readAdapterReady;
    scopeSlot = FlsAlloc(nullptr); if (scopeSlot == FLS_OUT_OF_INDEXES) return false;
    realNtCreateFile = reinterpret_cast<NtCreateFileFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtCreateFile"));
    realNtReadFile = reinterpret_cast<NtReadFileFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtReadFile"));
    realNtClose = reinterpret_cast<NtCloseFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtClose"));
    realNtCreateSection = reinterpret_cast<NtCreateSectionFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtCreateSection"));
    realNtDuplicateObject = reinterpret_cast<NtDuplicateObjectFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtDuplicateObject"));
    if (!realNtCreateFile || !realNtReadFile || !realNtClose || !realNtCreateSection || !realNtDuplicateObject) return false;
    if (!OSTPlatform::Detour::BeginTransaction()) return false;
    bool attached = OSTPlatform::Detour::Attach(reinterpret_cast<void**>(&realNtCreateFile), reinterpret_cast<void*>(ReadAdapter));
    attached = OSTPlatform::Detour::Attach(reinterpret_cast<void**>(&realNtReadFile), reinterpret_cast<void*>(ReadHandleAdapter)) && attached;
    attached = OSTPlatform::Detour::Attach(reinterpret_cast<void**>(&realNtClose), reinterpret_cast<void*>(CloseHandleAdapter)) && attached;
    attached = OSTPlatform::Detour::Attach(reinterpret_cast<void**>(&realNtCreateSection), reinterpret_cast<void*>(SectionAdapter)) && attached;
    attached = OSTPlatform::Detour::Attach(reinterpret_cast<void**>(&realNtDuplicateObject), reinterpret_cast<void*>(DuplicateAdapter)) && attached;
    const bool committed = OSTPlatform::Detour::CommitTransaction();
    return attached && committed;
}
ManifestReadScope::ManifestReadScope(uint32_t app, uint32_t depot, uint64_t gid, bool eligible) {
    if (scopeSlot == FLS_OUT_OF_INDEXES || !eligible || !depot || !gid) return;
    auto snapshot = Acquire();
    if (!snapshot || (!snapshot->data.depotKeys.count(app) && !snapshot->data.depotKeys.count(depot))) return;
    const auto name = std::to_wstring(depot) + L"_" + std::to_wstring(gid) + L".manifest";
    auto file = snapshot->manifestFiles.find(std::to_wstring(app) + L"/" + name);
    if (file == snapshot->manifestFiles.end()) {
        // Steam can identify a DLC's manifest with its DLC AppID while the
        // authenticated package belongs to the base AppID. A depot/gid match
        // across authorized packages is usable only when every copy agrees.
        const auto suffix = L"/" + name;
        for (auto candidate = snapshot->manifestFiles.begin(); candidate != snapshot->manifestFiles.end(); ++candidate) {
            if (!candidate->first.ends_with(suffix)) continue;
            if (file != snapshot->manifestFiles.end() && (file->second.sha != candidate->second.sha || file->second.size != candidate->second.size)) {
                file = snapshot->manifestFiles.end(); break;
            }
            file = candidate;
        }
    }
    // A missing private manifest must fail closed rather than read a matching
    // unscoped common-cache file.
    auto* scope = new ReadScope{snapshot, Lower((state.steamRoot / L"depotcache" / name).lexically_normal().wstring()),
        file == snapshot->manifestFiles.end() ? Snapshot::ManifestFile{} : file->second};
    previous = FlsGetValue(scopeSlot);
    if (!FlsSetValue(scopeSlot, scope)) { delete scope; return; }
    current = scope;
}
ManifestReadScope::~ManifestReadScope() {
    if (current) { FlsSetValue(scopeSlot, previous); delete static_cast<ReadScope*>(current); }
}
RetailLuaScope::RetailLuaScope() { ++retailLuaDepth; }
RetailLuaScope::~RetailLuaScope() { --retailLuaDepth; }
}

extern "C" __declspec(dllexport) unsigned WINAPI NestGRentalRuntimeProtocolVersion() { return 1; }
extern "C" __declspec(dllexport) unsigned WINAPI NestGRentalRuntimeCapabilities() {
    // Implemented protocol capabilities, not an assertion of live Steam health.
    // Live readiness additionally requires both packet hooks, both manifest
    // hooks, the filesystem adapter and a successful authenticated lease check.
    return 0x3F; // identity, scoped data, private reads, DPAPI vault, epochs, read-only confirmation.
}
