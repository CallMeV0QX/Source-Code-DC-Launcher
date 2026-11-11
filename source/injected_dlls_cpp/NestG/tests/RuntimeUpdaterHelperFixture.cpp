#include <windows.h>
int wmain(int argc, wchar_t** argv) {
    if (argc != 3 || wcscmp(argv[1], L"--steam-root") != 0 || !argv[2][0]) return 2;
    HANDLE output = CreateFileW(L"helper-invocations.dat", FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (output == INVALID_HANDLE_VALUE) return 3;
    DWORD count = 0;
    const char marker = '1';
    const bool result = WriteFile(output, &marker, 1, &count, nullptr) && count == 1 && FlushFileBuffers(output);
    CloseHandle(output);
    return result ? 0 : 4;
}
