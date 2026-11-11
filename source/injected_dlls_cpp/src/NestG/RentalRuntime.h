#pragma once
#include "RentalData.h"
#include "RentalStatusPipe.h"
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace NestGRental {
struct Snapshot {
    struct ManifestFile { std::filesystem::path path; uint64_t size = 0; std::string sha; };
    uint64_t steamId = 0;
    uint64_t generation = 0;
    uint64_t deadlineTicks = 0;
    std::string rentalId;
    std::string grantId;
    std::string revision;
    std::string steamAccountId;
    std::string installationId;
    std::filesystem::path root;
    Data data;
    // Only validated inventory files may be routed; no path is constructed from
    // arbitrary Lua text or from a Steam-supplied filename.
    std::map<std::wstring, ManifestFile> manifestFiles;
};

bool Start(const std::filesystem::path& steamRoot);
std::shared_ptr<const Snapshot> Acquire();
RentalStatusPipe::Reply CaptureStatus(const RentalStatusPipe::Request& request);
bool IsReservedPath(const std::filesystem::path& path);
bool IsTrackedDepot(uint32_t app, uint32_t depot);
std::vector<uint32_t> TakeAdded();
std::vector<uint32_t> TakeRemoved();

// Scope lives on a Windows fiber (Steam switches cooperative jobs on the same
// OS thread). A thread_local scope would leak a rental read into another job.
class ManifestReadScope {
    void* previous = nullptr;
    void* current = nullptr;
public:
    ManifestReadScope(uint32_t app, uint32_t depot, uint64_t gid, bool eligible = true);
    ~ManifestReadScope();
    ManifestReadScope(const ManifestReadScope&) = delete;
    ManifestReadScope& operator=(const ManifestReadScope&) = delete;
};
bool InstallReadAdapter();
class RetailLuaScope {
public:
    RetailLuaScope();
    ~RetailLuaScope();
};
}
