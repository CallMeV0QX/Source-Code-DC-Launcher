// A disposable host, never the user's Steam. Also built as steam.exe to exercise
// the proxy's host gate with an absent or stub NestG.dll in the fixture directory.
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

namespace {
using ExecuteOnce = BOOL(WINAPI*)(PINIT_ONCE, PINIT_ONCE_FN, PVOID, LPVOID*);
ExecuteOnce realExecuteOnce = nullptr;
volatile LONG runtimeCalls = 0, runtimeCallbacks = 0, runtimeCompletions = 0;
volatile LONG firstWorker = 0, secondWorker = 0;
DWORD runtimeCallbackError = 0;
struct CallbackContext { PINIT_ONCE_FN original; PVOID parameter; };
BOOL CALLBACK CountInitialization(PINIT_ONCE once, PVOID parameter, PVOID* context) {
    auto* call = static_cast<CallbackContext*>(parameter);
    InterlockedIncrement(&runtimeCallbacks);
    // Keep the winning OS callback in flight until both proxy workers have
    // entered this import, so the fixture covers genuinely overlapping calls.
    const auto deadline = GetTickCount64() + 5000;
    while (runtimeCalls < 2 && GetTickCount64() < deadline) Sleep(1);
    const BOOL result = call->original(once, call->parameter, context);
    runtimeCallbackError = GetLastError();
    InterlockedIncrement(&runtimeCompletions);
    return result;
}
BOOL WINAPI CountExecuteOnce(PINIT_ONCE once, PINIT_ONCE_FN callback, PVOID parameter, LPVOID* context) {
    const auto ordinal = InterlockedIncrement(&runtimeCalls);
    if (ordinal == 1) InterlockedExchange(&firstWorker, static_cast<LONG>(GetCurrentThreadId()));
    if (ordinal == 2) InterlockedExchange(&secondWorker, static_cast<LONG>(GetCurrentThreadId()));
    CallbackContext call{callback, parameter};
    return realExecuteOnce(once, CountInitialization, &call, context);
}
bool InstrumentRuntimeInitialization(const wchar_t* proxyPath) {
    // Test host memory only. Preload the immutable runtime without calling its
    // initializer, then wrap its OS InitOnce import before either proxy starts.
    // Counting the callback executed by the real Windows gate is deterministic;
    // best-effort startup log writes can collide and lose individual stages.
    wchar_t runtimePath[32768]{};
    if (!GetFullPathNameW(proxyPath, ARRAYSIZE(runtimePath), runtimePath, nullptr)) return false;
    auto* slash = wcsrchr(runtimePath, L'\\');
    if (!slash) return false;
    wcscpy_s(slash + 1, ARRAYSIZE(runtimePath) - (slash + 1 - runtimePath), L"OpenSteamTool.dll");
    HMODULE runtime = LoadLibraryExW(runtimePath, nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!runtime) return true; // Missing/invalid-runtime cases remain covered.
    auto* base = reinterpret_cast<BYTE*>(runtime);
    const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    const auto directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || nt->Signature != IMAGE_NT_SIGNATURE || !directory.VirtualAddress) return false;
    auto* imports = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);
    for (; imports->Name; ++imports) {
        if (!imports->OriginalFirstThunk) continue;
        auto* names = reinterpret_cast<IMAGE_THUNK_DATA64*>(base + imports->OriginalFirstThunk);
        auto* addresses = reinterpret_cast<IMAGE_THUNK_DATA64*>(base + imports->FirstThunk);
        for (; names->u1.AddressOfData; ++names, ++addresses) {
            if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) continue;
            const auto* name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(base + names->u1.AddressOfData);
            if (strcmp(reinterpret_cast<const char*>(name->Name), "InitOnceExecuteOnce") != 0) continue;
            DWORD previous = 0;
            if (!VirtualProtect(&addresses->u1.Function, sizeof(addresses->u1.Function), PAGE_READWRITE, &previous)) return false;
            realExecuteOnce = reinterpret_cast<ExecuteOnce>(addresses->u1.Function);
            InterlockedExchangePointer(reinterpret_cast<PVOID*>(&addresses->u1.Function), reinterpret_cast<PVOID>(CountExecuteOnce));
            DWORD ignored = 0;
            return VirtualProtect(&addresses->u1.Function, sizeof(addresses->u1.Function), previous, &ignored) != FALSE;
        }
    }
    return false;
}
bool WaitForInitialization() {
    if (!realExecuteOnce) return true;
    const auto deadline = GetTickCount64() + 10000;
    while (GetTickCount64() < deadline && (runtimeCalls < 2 || runtimeCompletions < 1)) Sleep(10);
    printf("Runtime init callbacks=%ld completions=%ld calls=%ld lastError=%lu workerThreadsDistinct=%d\n", runtimeCallbacks, runtimeCompletions, runtimeCalls, runtimeCallbackError, firstWorker != secondWorker);
    return runtimeCalls == 2 && runtimeCallbacks == 1 && runtimeCompletions == 1 && firstWorker && secondWorker && firstWorker != secondWorker;
}
bool CheckColdRuntimeReturn(const wchar_t* proxyPath) {
    // No preload and no memory instrumentation in this path. Both proxy
    // workers discover/load the runtime themselves. Calling the exported
    // initializer after observing it also waits for any in-flight OS once
    // callback, proving the missing-module initialization path returns.
    wchar_t path[32768]{};
    if (!GetFullPathNameW(proxyPath, ARRAYSIZE(path), path, nullptr)) return false;
    auto* slash = wcsrchr(path, L'\\'); if (!slash) return false;
    wcscpy_s(slash + 1, ARRAYSIZE(path) - (slash + 1 - path), L"OpenSteamTool.dll");
    HMODULE runtime = nullptr;
    const auto deadline = GetTickCount64() + 10000;
    while (!(runtime = GetModuleHandleW(path)) && GetTickCount64() < deadline) Sleep(10);
    if (!runtime) return false;
    auto initialize = reinterpret_cast<void(WINAPI*)()>(GetProcAddress(runtime, "NestGInitialize"));
    if (!initialize) return false;
    wcscpy_s(slash + 1, ARRAYSIZE(path) - (slash + 1 - path), L"steamclient64.dll");
    if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES || GetLastError() != ERROR_FILE_NOT_FOUND) return false;
    initialize();
    printf("Cold runtime loaded by proxy workers; initializer returned with absent fixture Steam modules; exact callback count not observed.\n");
    return true;
}
}

DWORD WINAPI CheckXInput(void* proxy) {
    wchar_t systemPath[MAX_PATH]; GetSystemDirectoryW(systemPath, MAX_PATH);
    wcscat_s(systemPath, L"\\xinput1_4.dll");
    auto real = LoadLibraryExW(systemPath, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    using GetState = DWORD(WINAPI*)(DWORD, void*);
    auto wrapped = reinterpret_cast<GetState>(GetProcAddress(static_cast<HMODULE>(proxy), "XInputGetState"));
    auto system = real ? reinterpret_cast<GetState>(GetProcAddress(real, "XInputGetState")) : nullptr;
    if (!wrapped || !system) return 10;
    DWORD result = 0;
    for (int i = 0; i < 100; ++i) {
        char first[32]{}, second[32]{};
        if (wrapped(0xffffffff, first) != system(0xffffffff, second)) result = 11;
    }
    FreeLibrary(real);
    return result;
}

std::map<DWORD, std::string> ExportMap(const wchar_t* path) {
    auto mapped = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE);
    if (!mapped) return {};
    auto base = reinterpret_cast<BYTE*>(reinterpret_cast<uintptr_t>(mapped) & ~uintptr_t(3));
    auto nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
    auto exports = reinterpret_cast<IMAGE_EXPORT_DIRECTORY*>(base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    auto functions = reinterpret_cast<DWORD*>(base + exports->AddressOfFunctions);
    auto names = reinterpret_cast<DWORD*>(base + exports->AddressOfNames);
    auto ordinals = reinterpret_cast<WORD*>(base + exports->AddressOfNameOrdinals);
    std::map<DWORD, std::string> result;
    for (DWORD i = 0; i < exports->NumberOfFunctions; ++i) if (functions[i]) result[exports->Base + i] = "";
    for (DWORD i = 0; i < exports->NumberOfNames; ++i) result[exports->Base + ordinals[i]] = reinterpret_cast<char*>(base + names[i]);
    FreeLibrary(mapped);
    return result;
}

DWORD WINAPI CheckDwm(void* proxy) {
    auto fn = GetProcAddress(static_cast<HMODULE>(proxy), "DwmIsCompositionEnabled");
    if (!fn) return 4;
    BOOL enabled = FALSE;
    return FAILED(reinterpret_cast<HRESULT(WINAPI*)(BOOL*)>(fn)(&enabled)) ? 5 : 0;
}

int wmain(int argc, wchar_t** argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (argc < 2) return 2;
    if (argc == 4 && wcscmp(argv[2], L"exports") == 0) {
        auto actual = ExportMap(argv[1]), old = ExportMap(argv[3]);
        if (actual.size() != 103 || actual != old) return 20;
        auto proxy = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        wchar_t systemPath[MAX_PATH]; GetSystemDirectoryW(systemPath, MAX_PATH);
        wcscat_s(systemPath, L"\\dwmapi.dll");
        auto real = LoadLibraryExW(systemPath, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!proxy || !real || real == proxy) return 21;
        unsigned missing = 0;
        for (const auto& item : actual) {
            auto ordinal = MAKEINTRESOURCEA(item.first);
            auto wrapped = GetProcAddress(proxy, ordinal);
            const char* lookup = item.second.empty() ? ordinal : item.second.c_str();
            if (!wrapped || (!item.second.empty() && wrapped != GetProcAddress(proxy, lookup))) return 22;
            if (!GetProcAddress(real, lookup)) {
                SetLastError(0);
                if (reinterpret_cast<HRESULT(WINAPI*)()>(wrapped)() != E_NOTIMPL || GetLastError() != ERROR_PROC_NOT_FOUND) return 23;
                ++missing;
            }
        }
        printf("103 export ordinals/names preserved; %u unavailable System32 exports fail safely.\n", missing);
        return 0;
    }
    if (argc > 2 && wcscmp(argv[2], L"system-first") == 0) {
        wchar_t systemPath[MAX_PATH]; GetSystemDirectoryW(systemPath, MAX_PATH);
        wcscat_s(systemPath, L"\\dwmapi.dll");
        if (!LoadLibraryExW(systemPath, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32)) return 24;
    }
    const bool cold = argc > 2 && (wcscmp(argv[2], L"both-cold") == 0 || wcscmp(argv[2], L"both-cold-reverse") == 0);
    const bool reverse = argc > 2 && (wcscmp(argv[2], L"both-reverse") == 0 || wcscmp(argv[2], L"both-cold-reverse") == 0);
    const bool both = cold || argc > 2 && (wcscmp(argv[2], L"both") == 0 || wcscmp(argv[2], L"both-reverse") == 0);
    if (both && !cold && !InstrumentRuntimeInitialization(argv[1])) return 27;
    HMODULE proxy = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!proxy) { printf("load-error=%lu\n", GetLastError()); return 3; }
    if (both) {
        auto second = argc == 4 ? LoadLibraryExW(argv[3], nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS) : nullptr;
        if (!second) return 6;
        if (!WaitForInitialization()) return 28;
        if (!realExecuteOnce) Sleep(1000);
        if (cold && !CheckColdRuntimeReturn(argv[1])) return 29;
        auto dwm = reverse ? second : proxy;
        auto xinput = reverse ? proxy : second;
        if (CheckDwm(dwm) || CheckXInput(xinput)) return 25;
        FreeLibrary(proxy); FreeLibrary(second);
        // Steam-host proxies are pinned: dropping our load references is safe.
        if (!GetModuleHandleW(argv[1]) || !GetModuleHandleW(argv[3])) return 26;
        return CheckDwm(dwm);
    }
    if (argc > 2 && (wcscmp(argv[2], L"parallel") == 0 || wcscmp(argv[2], L"xinput-parallel") == 0)) {
        auto check = wcscmp(argv[2], L"parallel") == 0 ? CheckDwm : CheckXInput;
        HANDLE threads[16];
        for (auto& thread : threads) { thread = CreateThread(nullptr, 0, check, proxy, 0, nullptr); if (!thread) return 7; }
        if (WaitForMultipleObjects(16, threads, TRUE, 5000) != WAIT_OBJECT_0) return 8;
        for (auto thread : threads) { DWORD code; GetExitCodeThread(thread, &code); CloseHandle(thread); if (code) return 9; }
        return 0;
    }
    if (argc > 2 && wcscmp(argv[2], L"xinput") == 0) {
        return CheckXInput(proxy);
    }
    if (argc > 2 && wcscmp(argv[2], L"load-only") == 0) { Sleep(1000); return 0; }
    auto fn = GetProcAddress(proxy, "DwmIsCompositionEnabled");
    if (!fn) { printf("resolve-error=%lu\n", GetLastError()); return 4; }
    BOOL enabled = FALSE;
    HRESULT result = reinterpret_cast<HRESULT(WINAPI*)(BOOL*)>(fn)(&enabled);
    printf("DwmIsCompositionEnabled=0x%08lx enabled=%d\n", result, enabled);
    return FAILED(result) ? 5 : 0;
}
