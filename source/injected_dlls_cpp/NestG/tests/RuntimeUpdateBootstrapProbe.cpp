#include "RuntimeUpdateBootstrap.h"
#include <cstdio>
using namespace NestGUpdateBootstrap;
static int cases = 0;
static void Require(bool result, const char* name) { if (!result) { std::fprintf(stderr, "FAIL %s\n", name); ExitProcess(1); } ++cases; }
static void Write(const std::wstring& path, const std::string& value) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    Require(file != INVALID_HANDLE_VALUE, "fixture-open");
    DWORD count = 0;
    Require(WriteFile(file, value.data(), static_cast<DWORD>(value.size()), &count, nullptr) && count == value.size(), "fixture-write");
    CloseHandle(file);
}
int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    const std::wstring root = argv[1], steam = root + L"\\Steam có dấu";
    CreateDirectoryW(steam.c_str(), nullptr); CreateDirectoryW((root + L"\\Gates").c_str(), nullptr);
    Require(!GateAllows(root, steam), "missing-gate-fails-closed");
    Write(steam + L"\\steamclient64.dll", "abc"); Write(steam + L"\\steamui.dll", "ui"); Write(steam + L"\\OpenSteamTool.dll", "runtime");
    const auto client = FileHash(steam + L"\\steamclient64.dll"), ui = FileHash(steam + L"\\steamui.dll");
    Require(client == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", "sha256-known-vector");
    const auto folder = steam + L"\\opensteamtool";
    CreateDirectoryW(folder.c_str(), nullptr); CreateDirectoryW((folder + L"\\pattern").c_str(), nullptr); CreateDirectoryW((folder + L"\\ipc").c_str(), nullptr);
    CreateDirectoryW((folder + L"\\pattern\\steamclient").c_str(), nullptr); CreateDirectoryW((folder + L"\\ipc\\steamclient").c_str(), nullptr); CreateDirectoryW((folder + L"\\pattern\\steamui").c_str(), nullptr);
    auto lower = [](std::string value) { for (char& c : value) if (c >= 'A' && c <= 'F') c += 'a' - 'A'; return std::wstring(value.begin(), value.end()); };
    const auto clientPattern = folder + L"\\pattern\\steamclient\\" + lower(client) + L".toml";
    const auto clientIpc = folder + L"\\ipc\\steamclient\\" + lower(client) + L".toml";
    const auto uiPattern = folder + L"\\pattern\\steamui\\" + lower(ui) + L".toml";
    Write(clientPattern, "pattern"); Write(clientIpc, "ipc"); Write(uiPattern, "ui-pattern");
    std::string gate = "version=1\nsteamRoot=" + Utf8(steam) + "\nsteamClientSha256=" + client + "\nsteamUiSha256=" + ui + "\nruntimeSha256=" + FileHash(steam + L"\\OpenSteamTool.dll") +
        "\nsteamClientPatternSha256=" + FileHash(clientPattern) + "\nsteamClientIpcSha256=" + FileHash(clientIpc) + "\nsteamUiPatternSha256=" + FileHash(uiPattern) + "\npending=0\n";
    const auto binding = BindingHash(steam);
    const std::wstring gatePath = root + L"\\Gates\\" + std::wstring(binding.begin(), binding.end()) + L".dat";
    auto protect = [&](const std::string& text, bool wrongEntropy = false) {
        const std::string entropyText = wrongEntropy ? "wrong" : "NestG.RuntimeUpdater.NativeGate.v1";
        DATA_BLOB input{static_cast<DWORD>(text.size()), reinterpret_cast<BYTE*>(const_cast<char*>(text.data()))}, entropy{static_cast<DWORD>(entropyText.size()), reinterpret_cast<BYTE*>(const_cast<char*>(entropyText.data()))}, cipher{};
        Require(CryptProtectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &cipher), "fixture-protect");
        Write(gatePath, std::string(reinterpret_cast<char*>(cipher.pbData), cipher.cbData)); LocalFree(cipher.pbData);
    };
    protect(gate);
    Require(GateAllows(root, steam), "valid-protected-unicode-gate");
    std::wstring differentCase = steam; CharLowerBuffW(&differentCase[0], static_cast<DWORD>(differentCase.size()));
    Require(GateAllows(root, differentCase), "case-insensitive-root-binding");
    Write(clientPattern, "changed"); Require(!GateAllows(root, steam), "modified-pattern-refused"); Write(clientPattern, "pattern");
    Write(clientIpc, "changed"); Require(!GateAllows(root, steam), "modified-ipc-refused"); Write(clientIpc, "ipc");
    Write(uiPattern, "changed"); Require(!GateAllows(root, steam), "modified-ui-pattern-refused"); Write(uiPattern, "ui-pattern");
    Write(steam + L"\\steamclient64.dll", "updated"); Require(!GateAllows(root, steam), "steam-update-refused"); Write(steam + L"\\steamclient64.dll", "abc");
    Write(steam + L"\\OpenSteamTool.dll", "updated"); Require(!GateAllows(root, steam), "runtime-drift-refused"); Write(steam + L"\\OpenSteamTool.dll", "runtime");
    protect(gate.substr(0, gate.size() - 2) + "1\n"); Require(!GateAllows(root, steam), "pending-transaction-refused");
    protect(gate + "extra=1\n"); Require(!GateAllows(root, steam), "extra-fields-refused");
    protect(gate, true); Require(!GateAllows(root, steam), "wrong-entropy-refused");
    Write(gatePath, "corrupt"); Require(!GateAllows(root, steam), "corrupt-proof-refused");
    protect(gate); Require(!GateAllows(root, steam + L"-other"), "different-installation-refused");
    StartHelperOnce(root, steam); StartHelperOnce(root, steam);
    const auto marker = root + L"\\helper-invocations.dat";
    for (int i = 0; i < 100 && GetFileAttributesW(marker.c_str()) == INVALID_FILE_ATTRIBUTES; ++i) Sleep(20);
    Sleep(100);
    HANDLE file = CreateFileW(marker.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    LARGE_INTEGER size{};
    Require(file != INVALID_HANDLE_VALUE && GetFileSizeEx(file, &size) && size.QuadPart == 1, "helper-started-exactly-once");
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    Require(!SafePath(L"C:\\unsafe\"path"), "command-injection-path-refused");
    std::printf("Passed %d bootstrap assertions; no installed Steam or saves used.\n", cases);
    return 0;
}
