#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "Hook/Hooks_Package.cpp"
#include <array>
#include <iostream>

// Exercise the actual package reconciliation with disposable package objects.
// Steam callbacks are simulated; this is not a live Steam ABI or UI test.
namespace {
std::shared_ptr<const NestGRental::Snapshot> fixtureSnapshot;
std::unordered_set<AppId_t> retailIds{20}, nativeIds{10}, markedOwned, uiRemovals;
PackageInfo* nativePackage = nullptr;
unsigned checks = 0;
void Check(bool value, const char* name) { if (!value) throw std::runtime_error(name); ++checks; }
bool Contains(PackageInfo* package, AppId_t id) {
    for (uint32 i = 0; i < package->AppIdVec.m_Size; ++i) if (package->AppIdVec.m_Memory.m_pMemory[i] == id) return true;
    return false;
}
PackageInfo* __fastcall GetPackage(void*, uint32, uint64) { return nativePackage; }
void* __fastcall Grow(CUtlVector<AppId_t>* vector, int count) {
    if (count < 0 || vector->m_Size + static_cast<uint32>(count) > vector->m_Memory.m_nAllocationCount) return nullptr;
    vector->m_Size += count; return vector;
}
int64 __fastcall Mark(void*, uint32, bool) { return 1; }
bool __fastcall Process(void*) { return true; }
bool __fastcall Owns(void*, AppId_t app, AppOwnership* output) {
    *output = {};
    const bool real = nativeIds.count(app) > 0;
    const bool injected = nativePackage && Contains(nativePackage, app);
    output->bOwnsLicense = real || injected;
    output->ExistInPackageNums = static_cast<uint32>(real) + static_cast<uint32>(injected);
    return output->bOwnsLicense;
}
void Configure(PackageInfo* package, AppId_t* backing, uint32 capacity) {
    ZeroMemory(package, sizeof(*package)); package->Status = EPackageStatus::Available;
    package->AppIdVec.m_Memory.m_pMemory = backing; package->AppIdVec.m_Memory.m_nAllocationCount = capacity;
}
}
namespace NestGRental {
std::shared_ptr<const Snapshot> Acquire() {
    const auto identity = RentalIdentity::Capture();
    return fixtureSnapshot && identity.state == RentalIdentity::State::Authenticated && identity.generation == fixtureSnapshot->generation ? fixtureSnapshot : nullptr;
}
}
namespace LuaConfig {
bool HasRetailDepot(AppId_t id) { return retailIds.count(id) > 0; }
bool HasDepot(AppId_t id, bool excludeOwned) {
    const auto rental = NestGRental::Acquire();
    return (retailIds.count(id) || (rental && rental->data.depotKeys.count(id))) && (!excludeOwned || !markedOwned.count(id));
}
bool IsOwned(AppId_t id) { return markedOwned.count(id) > 0; }
void MarkOwned(AppId_t id) { markedOwned.insert(id); }
std::vector<AppId_t> GetAllDepotIds() {
    std::vector<AppId_t> ids(retailIds.begin(),retailIds.end());
    if (const auto rental = NestGRental::Acquire()) for (const auto& [id,key] : rental->data.depotKeys) if (!retailIds.count(id)) ids.push_back(id);
    return ids;
}
std::vector<AppId_t> TakePendingRemovals() { return {}; }
std::vector<AppId_t> TakePendingAdditions() { return {}; }
}
namespace Hooks_SteamUI {
void QueueRemoval(AppId_t id) { uiRemovals.insert(id); }
void CancelRemoval(AppId_t id) { uiRemovals.erase(id); }
}
namespace OSTPlatform::Detour {
bool BeginTransaction() { return false; } bool CommitTransaction() { return false; }
bool Attach(void**,void*) { return false; } bool Detach(void**,void*) { return false; }
}
namespace PatternLoader { void* FindPattern(OSTPlatform::DynamicLibrary::ModuleHandle, const char*) { return nullptr; } }
namespace VehCommon { void Arm(Int3Site) {} }
namespace OSTPlatform::Trap { uint64_t Context::Argument(int) const { return 0; } }

int main() {
    try {
        std::array<AppId_t,256> firstIds{}, secondIds{};
        auto* first = static_cast<PackageInfo*>(VirtualAlloc(nullptr,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE));
        PackageInfo second{};
        Check(first != nullptr,"disposable_package_allocated");
        Configure(first,firstIds.data(),256); Configure(&second,secondIds.data(),256);
        nativePackage=first; oGetPackageInfo=GetPackage; g_pCPackageInfo=reinterpret_cast<void*>(1);
        oCUtlMemoryGrow=Grow; oMarkLicenseAsChanged=Mark; oProcessPendingLicenseUpdates=Process; oCheckAppOwnership=Owns;
        g_rentalPackageHooksReady.store(true);
        RentalIdentity::SetObserverAvailability(true,true); RentalIdentity::BeginLogon(76561198000000001ULL);
        RentalIdentity::ObserveLogonResponse(1,true,76561198000000001ULL,42);
        AppOwnership output{};
        hkCheckAppOwnership(reinterpret_cast<void*>(2),20,&output);
        Check(Contains(first,20),"retail_source_initialized");
        auto rental=std::make_shared<NestGRental::Snapshot>(); rental->steamId=76561198000000001ULL; rental->generation=RentalIdentity::Capture().generation;
        rental->data.depotKeys[10]=""; rental->data.depotKeys[30]=""; rental->data.depotKeys[31]="";
        fixtureSnapshot=rental; Hooks_Package::RequestRentalRefresh();
        hkCheckAppOwnership(reinterpret_cast<void*>(2),30,&output);
        Check(Contains(first,30)&&Contains(first,31),"rental_ids_inserted");
        Check(Contains(first,10),"native_owned_id_rental_contribution_tracked");
        RentalIdentity::SignOut(); fixtureSnapshot.reset();
        hkCheckAppOwnership(reinterpret_cast<void*>(3),10,&output);
        Check(!Contains(first,30)&&!Contains(first,31),"rental_ids_removed_before_personal_query");
        Check(output.bOwnsLicense,"personal_native_ownership_preserved");
        Check(!uiRemovals.count(10),"native_owned_game_not_hidden");
        Check(Contains(first,20),"retail_source_preserved_on_logout");
        // Watcher refresh after Steam replaced/freed the package object must
        // query the manager, never dereference the cached prior pointer.
        RentalIdentity::BeginLogon(76561198000000002ULL); RentalIdentity::ObserveLogonResponse(1,true,76561198000000002ULL,43);
        nativePackage=&second;
        DWORD previous=0; Check(VirtualProtect(first,4096,PAGE_NOACCESS,&previous)!=0,"old_package_poisoned");
        Hooks_Package::NotifyLicenseChanged();
        Check(g_pInjectedPackageInfo==first,"watcher_waits_for_new_account_ownership_capture");
        hkCheckAppOwnership(reinterpret_cast<void*>(4),20,&output);
        Check(g_pInjectedPackageInfo==&second&&Contains(&second,20),"replacement_package_requeried_safely");
        Hooks_Package::NotifyLicenseChanged();
        Check(!Contains(&second,30)&&!Contains(&second,31),"old_rental_not_adopted_by_replacement");
        VirtualFree(first,0,MEM_RELEASE);
        std::cout<<"Passed "<<checks<<" simulated package ownership checks; no real Steam was accessed.\n";
        return 0;
    } catch(const std::exception& error) { std::cerr<<"Package fixture failed: "<<error.what()<<"\n";return 1; }
}
