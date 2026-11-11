#include <windows.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>

int main(int argc, char** argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (argc != 4) return 10;
    const std::string mode = argv[3];
    auto module = LoadLibraryA(argv[1]);
    if (!module) return 11;
    auto start = reinterpret_cast<void(*)(const char*)>(GetProcAddress(module, "ProbeStart"));
    auto stop = reinterpret_cast<void(*)()>(GetProcAddress(module, "ProbeStop"));
    auto count = reinterpret_cast<unsigned(*)(bool)>(GetProcAddress(module, "ProbeCount"));
    if (!start || !stop || !count) return 12;
    const std::filesystem::path directory(argv[2]);
    if (mode != "missing") std::filesystem::create_directories(directory);
    if (mode == "reload") std::ofstream(directory / "opensteamtool.toml") << "initial";
    start(argv[2]);
    if (mode == "immediate") ExitProcess(0);
    Sleep(200);
    if (mode == "reload") {
        std::ofstream(directory / "opensteamtool.toml") << "changed";
        for (int i = 0; i < 100 && !count(true); ++i) Sleep(50);
        if (!count(true)) return 13;
        // Reload starts a new Lua watcher after joining the old one.
        Sleep(300);
        std::ofstream(directory / "fixture.lua") << "-- fixture";
        for (int i = 0; i < 100 && !count(false); ++i) Sleep(50);
        if (!count(false)) return 14;
    }
    if (mode == "restart") {
        for (int i = 0; i < 3; ++i) { stop(); start(argv[2]); Sleep(100); }
    }
    if (mode == "concurrent") {
        std::thread a([&] { for (int i = 0; i < 3; ++i) { start(argv[2]); stop(); } });
        std::thread b([&] { for (int i = 0; i < 3; ++i) { start(argv[2]); stop(); } });
        a.join(); b.join(); start(argv[2]);
    }
    // Exercise CRT DLL detach with a running OR already-returned joinable watcher.
    // Neither Steam nor its files is accessed by this host.
    return 0;
}
