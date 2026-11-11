// Real NtCreateFile detours on disposable files, with release CRT/optimization.
// Keep the worker independent of RentalRuntimeProbe's large main stack frame.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "NestG/RentalRuntime.cpp"
#include <detours.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

namespace {
thread_local volatile bool failPathBuffer = false;
thread_local volatile bool pathBufferFailureObserved = false;
}
// Test-only deterministic allocation failure. No test seam is shipped in DLLs.
void* operator new(size_t size) {
    // MSVC's vector allocator adds up to 63 bytes for large-block alignment.
    if (failPathBuffer && size >= 32768 * sizeof(wchar_t) && size < 32768 * sizeof(wchar_t) + 64) {
        pathBufferFailureObserved = true;
        throw std::bad_alloc();
    }
    if (void* value = std::malloc(size ? size : 1)) return value;
    throw std::bad_alloc();
}
void operator delete(void* value) noexcept { std::free(value); }
void operator delete(void* value, size_t) noexcept { std::free(value); }
void* operator new[](size_t size) { return ::operator new(size); }
void operator delete[](void* value) noexcept { ::operator delete(value); }
void operator delete[](void* value, size_t) noexcept { ::operator delete(value); }

namespace OSTPlatform::Detour {
bool BeginTransaction() { return ::DetourTransactionBegin() == NO_ERROR && ::DetourUpdateThread(GetCurrentThread()) == NO_ERROR; }
bool CommitTransaction() { return ::DetourTransactionCommit() == NO_ERROR; }
bool Attach(void** target, void* hook) { return ::DetourAttach(target, hook) == NO_ERROR; }
bool Detach(void** target, void* hook) { return ::DetourDetach(target, hook) == NO_ERROR; }
}
namespace Hooks_Package { void NotifyLicenseChanged() {} void RequestRentalRefresh() {} bool RentalIsolationReady() { return true; } }
namespace Hooks_Manifest { bool RentalReadReady() { return true; } }

namespace {
using namespace NestGRental;
struct Context {
    std::filesystem::path ordinary, common, privatePath;
    std::wstring operation;
    HANDLE directory = INVALID_HANDLE_VALUE;
    void* originFiber = nullptr;
    SIZE_T requestedReserve = 0, actualReserve = 0, initiallyCommitted = 0;
    DWORD result = 1;
    unsigned checks = 0;
};
void Require(bool condition, const char* name) {
    if (!condition) throw std::runtime_error(name);
}
void Seed(const std::filesystem::path& path, const char* bytes) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    file << bytes;
    Require(!!file, "seed_file");
}
bool Contents(HANDLE handle, const char* expected) {
    if (handle == INVALID_HANDLE_VALUE || !handle) return false;
    char buffer[128]{};
    DWORD read = 0;
    return ReadFile(handle, buffer, sizeof(buffer), &read, nullptr) &&
        read == std::strlen(expected) && std::memcmp(buffer, expected, read) == 0;
}
HANDLE OpenAbsolute(const std::filesystem::path& path) {
    return CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
}
NTSTATUS OpenRelative(Context& context, const wchar_t* fileName, HANDLE& handle) {
    auto ntCreateFile = reinterpret_cast<NtCreateFileFunction>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtCreateFile"));
    const auto length = static_cast<USHORT>(std::wcslen(fileName) * sizeof(wchar_t));
    UNICODE_STRING name{length, length, const_cast<wchar_t*>(fileName)};
    OBJECT_ATTRIBUTES attributes{};
    attributes.Length = sizeof(attributes); attributes.RootDirectory = context.directory;
    attributes.ObjectName = &name; attributes.Attributes = OBJ_CASE_INSENSITIVE;
    IO_STATUS_BLOCK io{};
    return ntCreateFile(&handle, FILE_GENERIC_READ | SYNCHRONIZE, &attributes, &io, nullptr,
        FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, 1 /* FILE_OPEN */, 0x20 /* FILE_SYNCHRONOUS_IO_NONALERT */, nullptr, 0);
}
void CheckRead(Context& context, HANDLE handle, const char* expected, const char* name) {
    const bool valid = Contents(handle, expected);
    if (handle && handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    Require(valid, name); ++context.checks;
}
DWORD WINAPI Worker(void* argument) {
    auto& context = *static_cast<Context*>(argument);
    try {
        char marker = 0;
        MEMORY_BASIC_INFORMATION region{};
        ULONG_PTR stackLow = 0, stackHigh = 0;
        GetCurrentThreadStackLimits(&stackLow, &stackHigh);
        Require(VirtualQuery(&marker, &region, sizeof(region)) == sizeof(region), "query_stack_allocation");
        context.actualReserve = stackHigh - reinterpret_cast<ULONG_PTR>(region.AllocationBase);
        // GetCurrentThreadStackLimits alone does not prove committed bytes.
        // Count the committed regions within the actual reserved allocation.
        for (auto address = reinterpret_cast<ULONG_PTR>(region.AllocationBase); address < stackHigh;) {
            MEMORY_BASIC_INFORMATION part{};
            Require(VirtualQuery(reinterpret_cast<void*>(address), &part, sizeof(part)) == sizeof(part), "query_stack_region");
            const auto bytes = (std::min)(part.RegionSize, static_cast<SIZE_T>(stackHigh - address));
            if (part.State == MEM_COMMIT) context.initiallyCommitted += bytes;
            Require(bytes != 0, "nonempty_stack_region");
            address += bytes;
        }
        Require(context.actualReserve == context.requestedReserve, "actual_stack_reservation_matches_request");
        char line[160]{};
        const int length = sprintf_s(line, "worker reserve=%llu initialCommitted=%llu\n",
            static_cast<unsigned long long>(context.actualReserve), static_cast<unsigned long long>(context.initiallyCommitted));
        DWORD written = 0; WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), line, length, &written, nullptr);
        ++context.checks;

        if (context.operation == L"absolute") {
            // No login or active snapshot exists in this cold-start case.
            Require(!Acquire(), "cold_start_has_no_rental");
            for (unsigned i = 0; i < 100; ++i)
                CheckRead(context, OpenAbsolute(context.ordinary), "ordinary-sentinel", "ordinary_absolute_read");
        } else if (context.operation == L"relative") {
            Require(!Acquire(), "cold_start_has_no_rental");
            for (unsigned i = 0; i < 100; ++i) {
                HANDLE handle = nullptr;
                Require(OpenRelative(context, L"ordinary-\x0111\x01b0\x1eddng.txt", handle) >= 0, "ordinary_relative_open");
                CheckRead(context, handle, "ordinary-sentinel", "ordinary_relative_read");
            }
        } else if (context.operation == L"reserved") {
            HANDLE handle = OpenAbsolute(context.privatePath);
            Require(handle == INVALID_HANDLE_VALUE && GetLastError() == ERROR_ACCESS_DENIED, "private_absolute_denied"); ++context.checks;
            handle = nullptr;
            const auto status = OpenRelative(context, L"nestg-rentals\\76561198000000001\\11111111-1111-4111-8111-111111111111\\manifests\\10\\11_12.manifest", handle);
            Require(status == static_cast<NTSTATUS>(0xC0000022L) && !handle, "private_relative_denied"); ++context.checks;
        } else if (context.operation == L"allocation-failure") {
            HANDLE handle = nullptr;
            failPathBuffer = true;
            const auto status = OpenRelative(context, L"ordinary-\x0111\x01b0\x1eddng.txt", handle);
            failPathBuffer = false;
            Require(pathBufferFailureObserved, "bounded_heap_allocation_failed");
            Require(status == static_cast<NTSTATUS>(0xC0000022L) && !handle, "allocation_failure_fails_closed"); ++context.checks;
            CheckRead(context, OpenAbsolute(context.ordinary), "ordinary-sentinel", "adapter_depth_restored_after_failure");
        } else if (context.operation == L"scoped") {
            ManifestReadScope scope(10, 11, 12);
            for (unsigned i = 0; i < 20; ++i) {
                CheckRead(context, OpenAbsolute(context.common), "private-sentinel", "rental_absolute_read");
                HANDLE handle = nullptr;
                Require(OpenRelative(context, L"depotcache\\11_12.manifest", handle) >= 0, "rental_relative_open");
                CheckRead(context, handle, "private-sentinel", "rental_relative_read");
            }
            Publish(nullptr);
            HANDLE handle = OpenAbsolute(context.common);
            Require(handle == INVALID_HANDLE_VALUE && GetLastError() == ERROR_ACCESS_DENIED, "revoked_scope_denied"); ++context.checks;
        } else throw std::runtime_error("unknown_operation");
        context.result = 0;
    } catch (const std::exception& error) {
        failPathBuffer = false;
        fprintf(stderr, "worker failed: %s; Win32=%lu\n", error.what(), GetLastError());
    }
    return context.result;
}
VOID WINAPI FiberWorker(void* argument) {
    auto& context = *static_cast<Context*>(argument);
    Worker(argument);
    SwitchToFiber(context.originFiber);
}
}
int wmain(int argc, wchar_t** argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    try {
        Require(argc == 5, "expected_fixture_thread_or_fiber_stack_kib_operation");
        auto context = std::make_unique<Context>();
        const auto root = std::filesystem::absolute(argv[1]);
        Require(!std::filesystem::exists(root), "fresh_disposable_root");
        context->requestedReserve = std::stoul(argv[3]) * 1024;
        Require(context->requestedReserve == 65536 || context->requestedReserve == 131072 || context->requestedReserve == 262144, "bounded_stack_size");
        context->operation = argv[4];
        state.steamRoot = root;
        context->ordinary = root / L"ordinary-\x0111\x01b0\x1eddng.txt";
        context->common = root / L"depotcache" / L"11_12.manifest";
        context->privatePath = root / L"nestg-rentals" / L"76561198000000001" / L"11111111-1111-4111-8111-111111111111" / L"manifests" / L"10" / L"11_12.manifest";
        Seed(context->ordinary, "ordinary-sentinel"); Seed(context->common, "retail-sentinel");
        Seed(context->privatePath, "private-sentinel"); Seed(root / L"nestg-rentals" / L".writer.lock", "");
        context->directory = CreateFileW(root.c_str(), FILE_LIST_DIRECTORY | SYNCHRONIZE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        Require(context->directory != INVALID_HANDLE_VALUE, "real_root_directory_handle");
        if (context->operation == L"scoped") {
            RentalIdentity::SetObserverAvailability(true, true);
            RentalIdentity::BeginLogon(76561198000000001ULL);
            RentalIdentity::ObserveLogonResponse(1, true, 76561198000000001ULL, 42);
            auto snapshot = std::make_shared<Snapshot>();
            snapshot->steamId = 76561198000000001ULL; snapshot->generation = RentalIdentity::Capture().generation;
            snapshot->deadlineTicks = GetTickCount64() + 60000;
            snapshot->rentalId = "11111111-1111-4111-8111-111111111111"; snapshot->grantId = "22222222-2222-4222-8222-222222222222";
            snapshot->revision = std::string(64, 'a'); snapshot->root = context->privatePath.parent_path().parent_path().parent_path();
            snapshot->data.depotKeys[10] = "";
            snapshot->manifestFiles[L"10/11_12.manifest"] = {context->privatePath, 16, Sha("private-sentinel")};
            Publish(snapshot);
        }
        Require(InstallReadAdapter(), "actual_nt_hooks_installed"); state.readAdapterReady = true;
        if (std::wstring(argv[2]) == L"thread") {
            HANDLE thread = CreateThread(nullptr, context->requestedReserve, Worker, context.get(), STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr);
            Require(!!thread, "small_stack_thread_created");
            Require(WaitForSingleObject(thread, 15000) == WAIT_OBJECT_0, "small_stack_thread_completed");
            CloseHandle(thread);
        } else {
            Require(std::wstring(argv[2]) == L"fiber", "known_execution_context");
            context->originFiber = ConvertThreadToFiber(nullptr);
            Require(!!context->originFiber, "convert_main_to_fiber");
            void* fiber = CreateFiberEx(4096, context->requestedReserve, FIBER_FLAG_FLOAT_SWITCH, FiberWorker, context.get());
            Require(!!fiber, "small_stack_fiber_created");
            SwitchToFiber(fiber); DeleteFiber(fiber);
            Require(ConvertFiberToThread() != FALSE, "convert_main_back_to_thread");
        }
        CloseHandle(context->directory);
        printf("result=%lu checks=%u reserve=%llu initialCommitted=%llu\n", context->result, context->checks,
            static_cast<unsigned long long>(context->actualReserve), static_cast<unsigned long long>(context->initiallyCommitted));
        return context->result;
    } catch (const std::exception& error) {
        fprintf(stderr, "setup failed: %s; Win32=%lu\n", error.what(), GetLastError()); return 1;
    }
}
