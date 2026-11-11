#include "../NestG/ProxyBootstrap.h"

namespace {
INIT_ONCE once = INIT_ONCE_STATIC_INIT;
FARPROC functions[103]{};
const char* const exports[] = {
#include "exports.inc"
};
static_assert(ARRAYSIZE(exports) == ARRAYSIZE(functions));
HRESULT WINAPI MissingExport() { SetLastError(ERROR_PROC_NOT_FOUND); return E_NOTIMPL; }
BOOL CALLBACK LoadSystemDwm(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t path[MAX_PATH];
    HMODULE real = nullptr;
    const UINT length = GetSystemDirectoryW(path, ARRAYSIZE(path));
    if (length && length < ARRAYSIZE(path) - 12) {
        wcscat_s(path, L"\\dwmapi.dll");
        real = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    }
    if (!real) NestGStartup::Write("dwm.system.failed", GetLastError());
    for (size_t i = 0; i < ARRAYSIZE(functions); ++i) {
        auto function = real ? GetProcAddress(real, exports[i]) : nullptr;
        functions[i] = function ? function : reinterpret_cast<FARPROC>(&MissingExport);
    }
    return TRUE;
}
}
extern "C" FARPROC NestGResolveDwm(unsigned index) {
    const DWORD error = GetLastError();
    InitOnceExecuteOnce(&once, LoadSystemDwm, nullptr, nullptr);
    SetLastError(error);
    return functions[index];
}
BOOL WINAPI DllMain(HMODULE module, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) NestGProxy::Attach(module);
    return TRUE;
}