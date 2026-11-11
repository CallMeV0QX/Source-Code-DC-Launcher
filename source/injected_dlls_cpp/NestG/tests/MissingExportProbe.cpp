#include <windows.h>
#include <cstdio>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    auto module = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!module) return 3;
    auto base = reinterpret_cast<BYTE*>(module);
    auto nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
    auto exports = reinterpret_cast<IMAGE_EXPORT_DIRECTORY*>(base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    auto functions = reinterpret_cast<DWORD*>(base + exports->AddressOfFunctions);
    unsigned count = 0;
    for (DWORD i = 0; i < exports->NumberOfFunctions; ++i) {
        if (!functions[i]) continue;
        auto function = reinterpret_cast<HRESULT(WINAPI*)()>(GetProcAddress(module, MAKEINTRESOURCEA(exports->Base + i)));
        SetLastError(0);
        if (!function || function() != E_NOTIMPL || GetLastError() != ERROR_PROC_NOT_FOUND) return 4;
        ++count;
    }
    printf("Controlled missing System32 exports: %u safe fallbacks.\n", count);
    return count == 103 ? 0 : 5;
}
