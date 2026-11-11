#include "dllmain.h"
#include "NestG/StartupDiagnostics.h"
#include "NestG/RentalRuntime.h"
#include "OSTPlatform/include/Encoding.h"
#include "Hook/HookManager.h"
#include "Utils/Config/Config.h"
#include "Utils/Config/ConfigFileWatcher.h"
#include "Utils/Config/LuaFileWatcher.h"
#include "Utils/CloudRedirect/CloudRedirectHost.h"
#include "Utils/SteamMetadata/IPCLoader.h"
#include "Utils/SteamMetadata/ManifestDonor.h"
#include "Utils/SteamMetadata/PatternLoader.h"
#include "Utils/SteamMetadata/SteamDiagnostics.h"
#ifdef OST_ENABLE_UPDATER
#include "Utils/Update/AppUpdater.h"
#endif
#include "OSTPlatform/include/Dialog.h"
#include "OSTPlatform/include/DynamicLibrary.h"
#include "OSTPlatform/include/Thread.h"

#include <string>
#include <windows.h>

// prepare key runtime paths.
bool InitializeSteamComponents(OSTPlatform::DynamicLibrary::ModuleHandle selfModule)
{
    const std::string steamInstallPath = OSTPlatform::Encoding::WideToUtf8(OSTPlatform::DynamicLibrary::GetModuleDirectory(selfModule).wstring());
    if (steamInstallPath.empty()) {
        return false;
    }
    sprintf_s(SteamInstallPath, kRuntimePathCapacity, "%s", steamInstallPath.c_str());
    sprintf_s(SteamclientPath, kRuntimePathCapacity, "%s\\steamclient64.dll",  SteamInstallPath);
    sprintf_s(SteamUIPath,     kRuntimePathCapacity, "%s\\steamui.dll",        SteamInstallPath);
    sprintf_s(DiversionPath,   kRuntimePathCapacity, "%s\\bin\\diversion.dll", SteamInstallPath);
    sprintf_s(LuaDir,          kRuntimePathCapacity, "%s\\config\\stplug-in",  SteamInstallPath);
    sprintf_s(ConfigPath,      kRuntimePathCapacity, "%s\\opensteamtool.toml", SteamInstallPath);
    
    client_hModule = OSTPlatform::DynamicLibrary::Load(SteamclientPath);
    if (!client_hModule) {
        LOG_ERROR("Load steamclient64.dll failed: {} (err={})",
                  SteamclientPath, OSTPlatform::DynamicLibrary::GetLastErrorCode());
        return false;
    }
    LOG_INFO("Loaded steamclient64.dll from {}", SteamclientPath);
    
    ui_hModule = OSTPlatform::DynamicLibrary::Load(SteamUIPath);
    if(!ui_hModule) {
        LOG_ERROR("Load failed for steamui.dll: err={}", OSTPlatform::DynamicLibrary::GetLastErrorCode());
        return false;
    }
    return true;
}

// All initialisation that touches the filesystem, loads modules, scans
// memory, or installs detours runs here on a worker thread — we MUST NOT do
// any of that from inside DllMain (loader lock).
static uint32_t InitThread(OSTPlatform::DynamicLibrary::ModuleHandle selfModule) {
    NestGStartup::Write("runtime.init.begin");
    Log::Init(selfModule);
    LOG_INFO("OpenSteamTool init thread started");

    if (!InitializeSteamComponents(selfModule)) {
        NestGStartup::Write("runtime.modules.failed", GetLastError());
        LOG_ERROR("InitializeSteamComponents failed");
        return 1;
    }

    NestGStartup::Write("runtime.config.begin");
    Config::Load(ConfigPath);
    Log::InitModules();
    Log::InstallPlatformLogSink();
    SteamDiagnostics::Initialize(SteamclientPath, SteamUIPath);

    // Load pattern files for steamclient64.dll and steamui.dll.
    // Each call computes the SHA-256 of the DLL on disk, checks the local
    // cache, and downloads from GitHub if needed.  Both calls are synchronous
    // but run on this worker thread, never under the loader lock.
    NestGStartup::Write("runtime.patterns.begin");
    PatternLoader::Load(ui_hModule, SteamUIPath, "steamui");
    PatternLoader::Load(client_hModule, SteamclientPath, "steamclient");

    // IPC method metadata (funcHash, fencepost, argc, ...)
    NestGStartup::Write("runtime.ipc.begin");
    IPCLoader::Load(SteamclientPath);

    // Install the reserved-source filesystem boundary before the unrestricted
    // retail Lua VM can execute dofile/loadfile. The monitor stays closed until
    // the verified identity and manifest hooks are actually installed.
    if (!NestGRental::Start(OSTPlatform::Encoding::Utf8ToWide(SteamInstallPath))) {
        NestGStartup::Write("runtime.rental_boundary.failed");
        return 0;
    }

    NestGStartup::Write("runtime.lua.begin");
    std::vector<std::string> watchDirs =
        LuaConfig::MergeWatchDirs(Config::GetLuaPaths(), std::string(LuaDir));
    for (const auto& dir : watchDirs)
        LuaConfig::ParseDirectory(dir);

    LuaFileWatcher::Start(watchDirs);
    ConfigFileWatcher::Start(ConfigPath, LuaDir);

    NestGStartup::Write("runtime.hooks.ui.begin");
    SteamUI::CoreHook();
    NestGStartup::Write("runtime.hooks.client.begin");
    SteamClient::CoreHook();

    // Surface any functions that FindPattern() could not locate.
    PatternLoader::ReportMissingFunctions();

    // Optional Steam Cloud save redirection (CloudRedirect). No-op unless
    // [cloud].enabled is set and cloud_redirect.dll is present.
    NestGStartup::Write("runtime.cloud.begin");
    CloudRedirectHost::Initialize(SteamInstallPath);

    // Contributes manifest request codes for depots this account owns, on
    // request. Started after the hooks are in place because it needs the
    // netpacket send path; it idles until the license list resolves anyway.
    ManifestDonor::Start();

    // Register the bst:// URI scheme so the website can drive code redemption via this
    // DLL (rundll32 handler). HKCU, no admin; idempotent.
    // NestG owns activation; do not register an external redemption protocol.

    // Optional self-update check. Runs on its own detached thread so the network
    // round-trip never delays hook installation; a staged DLL applies next launch.
    //
    // Compiled out entirely by -DOST_ENABLE_UPDATER=OFF. That is deliberately a
    // build-time cut rather than a runtime one: a pinned or private build should
    // not be replaceable by flipping [update] in opensteamtool.toml, and with the
    // updater absent the DLL makes no update request at all.
#ifdef OST_ENABLE_UPDATER
    if (Config::GetUpdateEnabled()) {
        OSTPlatform::Thread::StartDetached([] () -> uint32_t {
            const std::string self = std::string(SteamInstallPath) + "\\OpenSteamTool.dll";
            AppUpdater::CleanupStagedBackup(self);

            const AppUpdater::CheckResult upd = AppUpdater::Check();
            if (!upd.updateAvailable) return 0;
            if (!AppUpdater::DownloadAndStage(upd, self)) return 0;

            const bool restart = OSTPlatform::Dialog::ShowConfirm(
                "BetterSteamTools Updated!",
                upd.oldVersion + " -> " + upd.newVersion +
                "\n\nRestart Steam now to apply?");
            if (restart) AppUpdater::RestartSteam();
            return 0;
        });
    }
#else
    LOG_INFO("Self-updater not compiled in (OST_ENABLE_UPDATER=OFF)");
#endif

    NestGStartup::Write("runtime.init.complete");
    LOG_INFO("OpenSteamTool init complete");
    return 0;
}

static HMODULE g_self = nullptr;
static INIT_ONCE g_initialize = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK InitializeOnce(PINIT_ONCE, PVOID, PVOID*) {
    try {
        InitThread(reinterpret_cast<OSTPlatform::DynamicLibrary::ModuleHandle>(g_self));
    } catch (const std::exception&) {
        // Do not log exception text, which can contain paths or configuration.
        NestGStartup::Write("runtime.exception", ERROR_UNHANDLED_EXCEPTION);
    } catch (...) {
        NestGStartup::Write("runtime.exception.unknown", ERROR_UNHANDLED_EXCEPTION);
    }
    return TRUE; // A failed/partial initialization must never be repeated in-process.
}

extern "C" __declspec(dllexport) void WINAPI NestGInitialize() {
    // Called on a proxy worker after the OS loader lock has been released.
    wchar_t executable[32768];
    DWORD length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
    if (!length || length >= ARRAYSIZE(executable)) return;
    const wchar_t* name = wcsrchr(executable, L'\\');
    if (!name || _wcsicmp(name + 1, L"steam.exe") != 0) return;
    HMODULE pinned;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(g_self), &pinned)) return;
    InitOnceExecuteOnce(&g_initialize, InitializeOnce, nullptr, nullptr);
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, PVOID) {
    if (reason == DLL_PROCESS_ATTACH) g_self = module;
    // Process-lifetime runtime: never join watchers or call cloud shutdown while
    // Windows holds the loader lock and has already terminated other threads.
    return TRUE;
}
