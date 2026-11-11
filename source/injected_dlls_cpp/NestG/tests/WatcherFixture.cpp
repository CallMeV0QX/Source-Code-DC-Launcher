#include <windows.h>
#include "WatcherFixture.h"
#include "Utils/Config/ConfigFileWatcher.h"
#include "Utils/Config/LuaFileWatcher.h"

extern "C" __declspec(dllexport) void ProbeStart(const char* directory) {
    // Match production: a process-lifetime pinned DLL, no joins in DllMain.
    HMODULE pinned;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&ProbeStart), &pinned);
    LuaFileWatcher::Start({directory});
    ConfigFileWatcher::Start(std::string(directory) + "\\opensteamtool.toml", directory);
}
extern "C" __declspec(dllexport) void ProbeStop() {
    ConfigFileWatcher::Stop();
    LuaFileWatcher::Stop();
}
extern "C" __declspec(dllexport) unsigned ProbeCount(bool reload) {
    return reload ? Fixture::reloads.load() : Fixture::changes.load();
}
BOOL WINAPI DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
