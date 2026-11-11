#pragma once
#include "StartupDiagnostics.h"
#include "RuntimeUpdateBootstrap.h"

namespace NestGProxy {
inline bool IsSteamHost() noexcept {
    wchar_t path[32768];
    const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
    if (!length || length >= ARRAYSIZE(path)) return false;
    const wchar_t* name = wcsrchr(path, L'\\');
    return name && _wcsicmp(name + 1, L"steam.exe") == 0;
}

inline DWORD WINAPI Initialize(void* module) noexcept {
    NestGStartup::Write("proxy.worker");
    wchar_t path[32768];
    DWORD length = GetModuleFileNameW(static_cast<HMODULE>(module), path, ARRAYSIZE(path));
    if (!length || length >= ARRAYSIZE(path) - ARRAYSIZE(L"OpenSteamTool.dll")) {
        NestGStartup::Write("proxy.path.failed", GetLastError()); return 0;
    }
    wchar_t* slash = wcsrchr(path, L'\\');
    if (!slash) { NestGStartup::Write("proxy.path.failed", ERROR_BAD_PATHNAME); return 0; }
    const std::wstring steamRoot(path, slash);
    if (!NestGUpdateBootstrap::Check(steamRoot)) return 0;
    wcscpy_s(slash + 1, ARRAYSIZE(path) - (slash + 1 - path), L"OpenSteamTool.dll");
    NestGStartup::Write("proxy.load.begin");
    HMODULE runtime = LoadLibraryExW(path, nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!runtime) { NestGStartup::Write("proxy.load.failed", GetLastError()); return 0; }
    auto initialize = reinterpret_cast<void(WINAPI*)()>(GetProcAddress(runtime, "NestGInitialize"));
    if (!initialize) { NestGStartup::Write("proxy.export.failed", GetLastError()); return 0; }
    NestGStartup::Write("proxy.load.complete");
    initialize(); // The runtime serializes initialization across both proxies.
    return 0;
}

inline void Attach(HMODULE module) noexcept {
    if (!IsSteamHost()) return;
    // No LoadLibrary or waiting under the loader lock. Pin before scheduling so
    // a host FreeLibrary cannot unmap the worker's instructions before it runs.
    HMODULE pinned = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(module), &pinned)) return;
    HANDLE thread = CreateThread(nullptr, 0, Initialize, module, 0, nullptr);
    if (thread) CloseHandle(thread);
    else NestGStartup::Write("proxy.worker.failed", GetLastError());
    // The optional runtime failing never makes the OS proxy's DllMain fail.
}
}
