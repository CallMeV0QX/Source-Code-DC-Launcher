// Loads only the explicitly supplied candidate into this disposable non-Steam
// process. Never discovers Steam, authenticates, initializes its hooks or reads saves.
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) return 2;
    wchar_t self[32768]{};
    if (!GetModuleFileNameW(nullptr, self, 32768) || _wcsicmp(std::filesystem::path(self).filename().c_str(), L"steam.exe") == 0) return 3;
    const auto candidate = std::filesystem::absolute(argv[1]).lexically_normal();
    std::ifstream input(candidate, std::ios::binary);
    const std::string bytes((std::istreambuf_iterator<char>(input)), {});
    const std::wstring expectedWide(argv[2]);
    const std::string expected(expectedWide.begin(), expectedWide.end());
    if (!input || expected.empty() || bytes.find(expected) == std::string::npos) return 4;
    HMODULE module = LoadLibraryExW(candidate.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) { std::cerr << "LoadLibraryEx failed: " << GetLastError() << "\n"; return 5; }
    using Getter = unsigned (WINAPI*)();
    using Initialize = void (WINAPI*)();
    const auto protocol = reinterpret_cast<Getter>(GetProcAddress(module, "NestGRentalRuntimeProtocolVersion"));
    const auto capabilities = reinterpret_cast<Getter>(GetProcAddress(module, "NestGRentalRuntimeCapabilities"));
    const auto status = reinterpret_cast<Getter>(GetProcAddress(module, "NestGRentalStatusProtocolVersion"));
    const auto initialize = reinterpret_cast<Initialize>(GetProcAddress(module, "NestGInitialize"));
    if (!protocol || !capabilities || !status || !initialize) return 6;
    for (unsigned iteration = 0; iteration < 1000; ++iteration)
        if (protocol() != 1 || capabilities() != 0x3f || status() != 1) return 7;
    initialize(); // The actual export must refuse this non-Steam executable.
    if (GetModuleHandleW(L"steamclient64.dll") || GetModuleHandleW(L"steamui.dll")) return 8;
    if (!FreeLibrary(module)) return 9;
    std::cout << "Passed actual DLL load, embedded version, 3000 protocol/capability ABI calls and non-Steam initialization refusal.\n";
    return 0;
}
