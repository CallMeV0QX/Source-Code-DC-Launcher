#pragma once
#include <windows.h>
#include <cstdio>
#include <cwchar>

// Release diagnostics use fixed stage labels and numeric OS errors only.
// Never enable upstream verbose logging of Lua, tickets or provider settings.
namespace NestGStartup {
inline void Write(const char* stage, DWORD error = ERROR_SUCCESS) noexcept {
    const DWORD savedError = GetLastError();
    HMODULE self = nullptr;
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&Write), &self)) {
        wchar_t path[32768];
        DWORD length = GetModuleFileNameW(self, path, ARRAYSIZE(path));
        if (length && length < ARRAYSIZE(path) - 64) {
            wchar_t* slash = wcsrchr(path, L'\\');
            if (slash) {
                wcscpy_s(slash + 1, ARRAYSIZE(path) - (slash + 1 - path), L"opensteamtool");
                CreateDirectoryW(path, nullptr);
                wcscat_s(path, L"\\nestg_startup.log");
                HANDLE file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
                if (file != INVALID_HANDLE_VALUE) {
                    BY_HANDLE_FILE_INFORMATION info{};
                    LARGE_INTEGER size{}, zero{};
                    if (GetFileInformationByHandle(file, &info) &&
                        !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
                        GetFileSizeEx(file, &size)) {
                        if (size.QuadPart > 512 * 1024) {
                            SetFilePointerEx(file, zero, nullptr, FILE_BEGIN);
                            SetEndOfFile(file);
                        }
                        SetFilePointerEx(file, zero, nullptr, FILE_END);
                        SYSTEMTIME time; GetSystemTime(&time);
                        char line[256];
                        int count = sprintf_s(line,
                            "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ PID=%lu TID=%lu Stage=%s Error=%lu\r\n",
                            time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute,
                            time.wSecond, time.wMilliseconds, GetCurrentProcessId(),
                            GetCurrentThreadId(), stage, error);
                        DWORD written;
                        if (count > 0) WriteFile(file, line, count, &written, nullptr);
                    }
                    CloseHandle(file);
                }
            }
        }
    }
    SetLastError(savedError);
}
}
