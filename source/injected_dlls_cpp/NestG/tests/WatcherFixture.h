#pragma once
#include <atomic>
#include <string>
#include <vector>

// Only Steam/config side effects are replaced. Tests compile the real watcher
// sources and Windows directory notification backend from the release archive.
namespace Fixture {
inline std::atomic<unsigned> reloads{0}, changes{0};
}
namespace Config {
struct LoadResult { bool applied, luaPathsChanged; };
inline LoadResult Load(const std::string&) { return {true, true}; }
inline std::vector<std::string> GetLuaPaths() { return {}; }
}
namespace LuaConfig {
inline std::vector<std::string> MergeWatchDirs(const std::vector<std::string>&, const std::string& path) { return {path}; }
inline void ReloadDirectories(const std::vector<std::string>&) { ++Fixture::reloads; }
inline void UnloadFile(const std::string&) { ++Fixture::changes; }
inline void ParseFile(const std::string&) { ++Fixture::changes; }
}
namespace Hooks_Package { inline void NotifyLicenseChanged() {} }
namespace Hooks_NetPacket { inline bool ProbeManifest(unsigned) { return false; } }
namespace CloudRedirectHost { inline void SyncAppSet() {} }
namespace Log { inline void ApplyConfigLevel() {} }
#define LOG_INFO(...) ((void)0)
#define LOG_WARN(...) ((void)0)
#define LOG_PACKAGE_DEBUG(...) ((void)0)
#define LOG_PACKAGE_TRACE(...) ((void)0)
#define LOG_PACKAGE_WARN(...) ((void)0)
