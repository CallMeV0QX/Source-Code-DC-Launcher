#pragma once
#include <windows.h>
// Test-only Win32 seam, force-included while compiling original archived source.
// No shipping file is modified. Simulates an OS with none of the expected exports.
inline FARPROC WINAPI NestGTestMissingExport(HMODULE, LPCSTR) {
    SetLastError(ERROR_PROC_NOT_FOUND);
    return nullptr;
}
#define GetProcAddress NestGTestMissingExport
