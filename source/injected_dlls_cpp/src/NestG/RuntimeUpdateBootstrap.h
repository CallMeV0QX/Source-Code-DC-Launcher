#pragma once
#include <windows.h>
#include <wincrypt.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <algorithm>
#include "StartupDiagnostics.h"
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "shell32.lib")
#ifndef NESTG_RUNTIME_UPDATER_SHA256
#error NESTG_RUNTIME_UPDATER_SHA256 must pin the independently built helper executable
#endif

// Runs only on the proxy worker, never under DllMain/loader lock. No HTTP in Steam.
namespace NestGUpdateBootstrap {
inline std::string Utf8(const std::wstring& value) {
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (count <= 0) return {};
    std::string result(count, '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), &result[0], count, nullptr, nullptr)) return {};
    return result;
}
inline std::wstring Utf16(const std::string& value) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (count <= 0 || count > 32768) return {};
    std::wstring result(count, L'\0');
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), &result[0], count) ? result : std::wstring{};
}
inline bool SafePath(std::wstring path) {
    if (path.size() < 3 || path[1] != L':' || path[2] != L'\\' || path.find(L'"') != std::wstring::npos) return false;
    for (;;) {
        DWORD attributes = GetFileAttributesW(path.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
        auto slash = path.find_last_of(L'\\');
        if (slash == std::wstring::npos || slash < 3) break;
        path.resize(slash);
    }
    return true;
}
struct Hash {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    std::vector<BYTE> object;
    Hash() {
        DWORD size = 0, read = 0;
        if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
            BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&size), sizeof(size), &read, 0) < 0 || size > 1048576) return;
        object.resize(size);
        if (BCryptCreateHash(algorithm, &hash, object.data(), size, nullptr, 0, 0) < 0) hash = nullptr;
    }
    ~Hash() { if (hash) BCryptDestroyHash(hash); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
    bool Add(const BYTE* bytes, size_t count) { return hash && count <= MAXDWORD && BCryptHashData(hash, const_cast<PUCHAR>(bytes), static_cast<ULONG>(count), 0) >= 0; }
    std::string Finish() {
        BYTE digest[32];
        if (!hash || BCryptFinishHash(hash, digest, sizeof(digest), 0) < 0) return {};
        static const char hex[] = "0123456789ABCDEF";
        std::string result;
        for (BYTE b : digest) { result.push_back(hex[b >> 4]); result.push_back(hex[b & 15]); }
        return result;
    }
};
inline std::string FileHash(const std::wstring& path) {
    if (!SafePath(path)) return {};
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    BY_HANDLE_FILE_INFORMATION information{};
    LARGE_INTEGER size{};
    Hash hash;
    bool valid = GetFileInformationByHandle(file, &information) && !(information.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) &&
        GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= 134217728;
    BYTE buffer[65536]; DWORD read = 0; LONGLONG total = 0;
    while (valid) {
        if (!ReadFile(file, buffer, sizeof(buffer), &read, nullptr)) { valid = false; break; }
        if (!read) break;
        total += read;
        if (total > size.QuadPart || !hash.Add(buffer, read)) { valid = false; break; }
    }
    CloseHandle(file);
    return valid && total == size.QuadPart ? hash.Finish() : std::string{};
}
inline std::wstring UpdateRoot() {
    wchar_t local[MAX_PATH];
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, local))) return {};
    std::wstring result = std::wstring(local) + L"\\DCGamingLauncher\\RuntimeUpdates";
    return SafePath(result) ? result : std::wstring{};
}
inline std::string BindingHash(const std::wstring& steamRoot) {
    int size = LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_UPPERCASE, steamRoot.data(), static_cast<int>(steamRoot.size()), nullptr, 0, nullptr, nullptr, 0);
    if (size <= 0 || size > 32768) return {};
    std::wstring upper(size, L'\0');
    if (!LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_UPPERCASE, steamRoot.data(), static_cast<int>(steamRoot.size()), &upper[0], size, nullptr, nullptr, 0)) return {};
    const auto bytes = Utf8(upper);
    Hash hash;
    return !bytes.empty() && hash.Add(reinterpret_cast<const BYTE*>(bytes.data()), bytes.size()) ? hash.Finish() : std::string{};
}
inline bool GateAllows(const std::wstring& root, const std::wstring& steamRoot) {
    const auto binding = BindingHash(steamRoot);
    if (binding.empty() || !SafePath(steamRoot)) return false;
    const std::wstring gate = root + L"\\Gates\\" + std::wstring(binding.begin(), binding.end()) + L".dat";
    if (!SafePath(gate)) return false;
    HANDLE file = CreateFileW(gate.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    BYTE cipher[4096]; DWORD count = 0;
    LARGE_INTEGER size{}; BY_HANDLE_FILE_INFORMATION information{};
    bool valid = GetFileInformationByHandle(file, &information) && !(information.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) &&
        GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= sizeof(cipher) &&
        ReadFile(file, cipher, static_cast<DWORD>(size.QuadPart), &count, nullptr) && count == size.QuadPart;
    CloseHandle(file);
    if (!valid) return false;
    static const char entropyText[] = "DCGaming.RuntimeUpdater.NativeGate.v1";
    DATA_BLOB input{count, cipher}, entropy{sizeof(entropyText) - 1, reinterpret_cast<BYTE*>(const_cast<char*>(entropyText))}, plain{};
    if (!CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &plain)) return false;
    std::string value;
    if (plain.cbData <= 4096) value.assign(reinterpret_cast<char*>(plain.pbData), plain.cbData);
    SecureZeroMemory(plain.pbData, plain.cbData); LocalFree(plain.pbData);
    const std::string prefix = "version=1\nsteamRoot=";
    if (value.compare(0, prefix.size(), prefix) != 0) return false;
    const auto endRoot = value.find('\n', prefix.size());
    if (endRoot == std::string::npos) return false;
    const auto boundRoot = Utf16(value.substr(prefix.size(), endRoot - prefix.size()));
    if (boundRoot.empty() || CompareStringOrdinal(boundRoot.c_str(), -1, steamRoot.c_str(), -1, TRUE) != CSTR_EQUAL) return false;
    const std::string nextField = "\nsteamClientSha256=";
    if (value.compare(endRoot, nextField.size(), nextField) != 0) return false;
    size_t at = endRoot + nextField.size();
    auto readHash = [&](const char* next, std::string& result) {
        if (value.size() < at + 64) return false;
        result = value.substr(at, 64); at += 64;
        for (char c : result) if (!(c >= '0' && c <= '9') && !(c >= 'A' && c <= 'F')) return false;
        const size_t length = strlen(next);
        if (value.compare(at, length, next) != 0) return false;
        at += length; return true;
    };
    std::string client, ui, runtime, clientPattern, clientIpc, uiPattern;
    if (!readHash("\nsteamUiSha256=", client) || !readHash("\nruntimeSha256=", ui) ||
        !readHash("\nsteamClientPatternSha256=", runtime) || !readHash("\nsteamClientIpcSha256=", clientPattern) ||
        !readHash("\nsteamUiPatternSha256=", clientIpc) || !readHash("\npending=0\n", uiPattern) || at != value.size()) return false;
    auto lower = [](std::string hash) { for (char& c : hash) if (c >= 'A' && c <= 'F') c += 'a' - 'A'; return std::wstring(hash.begin(), hash.end()); };
    return FileHash(steamRoot + L"\\steamclient64.dll") == client && FileHash(steamRoot + L"\\steamui.dll") == ui &&
        FileHash(steamRoot + L"\\OpenSteamTool.dll") == runtime &&
        FileHash(steamRoot + L"\\opensteamtool\\pattern\\steamclient\\" + lower(client) + L".toml") == clientPattern &&
        FileHash(steamRoot + L"\\opensteamtool\\ipc\\steamclient\\" + lower(client) + L".toml") == clientIpc &&
        FileHash(steamRoot + L"\\opensteamtool\\pattern\\steamui\\" + lower(ui) + L".toml") == uiPattern;
}
inline void StartHelperOnce(const std::wstring& root, const std::wstring& steamRoot) {
    const auto helper = root + L"\\Helper\\DCGaming.RuntimeUpdater.exe";
    if (!SafePath(helper)) return;
    HANDLE held = CreateFileW(helper.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (held == INVALID_HANDLE_VALUE) { NestGStartup::Write("updater.helper.absent"); return; }
    if (FileHash(helper) != NESTG_RUNTIME_UPDATER_SHA256) { CloseHandle(held); NestGStartup::Write("updater.helper.untrusted"); return; }
    wchar_t marker[96];
    swprintf_s(marker, L"Local\\DCGaming.RuntimeUpdater.Trigger.v1.%lu", GetCurrentProcessId());
    HANDLE once = CreateMutexW(nullptr, FALSE, marker);
    if (!once) { CloseHandle(held); return; }
    if (GetLastError() == ERROR_ALREADY_EXISTS) { CloseHandle(held); CloseHandle(once); return; }
    // Retain the marker until process exit so both independently mapped proxies trigger once.
    const std::wstring arguments = L"\"" + helper + L"\" --steam-root \"" + steamRoot + L"\"";
    std::vector<wchar_t> command(arguments.begin(), arguments.end()); command.push_back(L'\0');
    STARTUPINFOW startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESHOWWINDOW; startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, root.c_str(), &startup, &process)) {
        CloseHandle(process.hThread); CloseHandle(process.hProcess); NestGStartup::Write("updater.helper.started");
    } else { NestGStartup::Write("updater.helper.failed", GetLastError()); CloseHandle(once); }
    CloseHandle(held);
}
inline bool Check(const std::wstring& steamRoot) noexcept {
    try {
        wchar_t host[32768];
        const DWORD hostLength = GetModuleFileNameW(nullptr, host, ARRAYSIZE(host));
        const auto expectedHost = steamRoot + L"\\steam.exe";
        if (!hostLength || hostLength >= ARRAYSIZE(host) ||
            CompareStringOrdinal(host, -1, expectedHost.c_str(), -1, TRUE) != CSTR_EQUAL) return false;
        const auto root = UpdateRoot();
        if (root.empty() || !SafePath(steamRoot)) return false;
        StartHelperOnce(root, steamRoot); // Recovery/update still runs when the runtime is absent or unsupported.
        const bool allowed = GateAllows(root, steamRoot);
        NestGStartup::Write(allowed ? "updater.gate.allowed" : "updater.gate.blocked");
        return allowed;
    } catch (...) { NestGStartup::Write("updater.bootstrap.failed"); return false; }
}
}
