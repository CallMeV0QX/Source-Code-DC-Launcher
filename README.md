# BÁO CÁO PHÂN TÍCH KỸ THUẬT & BẰNG CHỨNG DỊCH NGƯỢC: DCGAMINGLAUNCHER (`v1.0.29`)

> **Mục đích tài liệu**: Báo cáo này tổng hợp toàn bộ bằng chứng kỹ thuật thu được từ quá trình dịch ngược (reverse engineering) bộ cài **DCGamingLauncher** (`DC-Launcher.exe` v1.0.29 / Runtime Bundle `bettersteamtools-cloud` v1.0.19), bao gồm các assembly .NET đã bóc tách, các thư viện `.dll` native x64 tiêm vào Steam và toàn bộ mã nguồn C++/Go gốc bị nhà phát triển bỏ quên trong kho lưu trữ cục bộ. Mọi nhận định trong báo cáo đều đính kèm **file gốc, bảng trích xuất mã máy, và link trực tiếp đến từng dòng code cụ thể** ngay trong repository này để đối chứng và làm bằng chứng pháp lý/kỹ thuật.

---

## BẢNG CHỈ MỤC NHANH CÁC BẰNG CHỨNG & FILE ĐỐI CHIẾU TRONG REPO

| STT | Nội dung cáo buộc / Hành vi bất thường | File bằng chứng nhị phân gốc (Raw Artifacts) | File mã nguồn / Bằng chứng đối chiếu (Kèm số dòng) |
| :---: | :--- | :--- | :--- |
| **1** | **Bán game lậu dưới danh nghĩa "ACTIVE Game"**: Không cấp license thật từ Valve mà tải script `.lua` chứa khóa AES-256 Depot bị đánh cắp & file `.manifest` từ các máy chủ lậu (`hubcapmanifest.com`, `dcgaming.cloud`) ép Steam giải mã từ CDN của Valve | - [`binaries/unpacked_launcher_assemblies/DC-Launcher.dll`](binaries/unpacked_launcher_assemblies/DC-Launcher.dll)<br>- [`binaries/unpacked_launcher_assemblies/DC-Runtime.Core.dll`](binaries/unpacked_launcher_assemblies/DC-Runtime.Core.dll) | - Tiêm khóa giải mã AES-256: [`source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp#L45-L85`](source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp#L45-L85)<br>- Nạp đè Manifest từ web lậu: [`source/injected_dlls_cpp/src/Hook/Hooks_Manifest.cpp#L100-L165`](source/injected_dlls_cpp/src/Hook/Hooks_Manifest.cpp#L100-L165)<br>- Client tải Manifest lậu: [`source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestClient.cpp#L40-L120`](source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestClient.cpp#L40-L120) |
| **2** | **Tấn công DLL Hijacking vào Steam (`<SteamRoot>`)**: Cưỡng bức tắt `steam.exe`, thả 04 DLL native x64 giả mạo và ghim chặt trong bộ nhớ (`GET_MODULE_HANDLE_EX_FLAG_PIN`) để tước quyền kiểm soát của Steam | - [`binaries/injected_steam_dlls/dwmapi.dll`](binaries/injected_steam_dlls/dwmapi.dll)<br>- [`binaries/injected_steam_dlls/xinput1_4.dll`](binaries/injected_steam_dlls/xinput1_4.dll) | - Chuyển tiếp 103 export giả mạo: [`source/injected_dlls_cpp/src/dwmapi/dwmapi.cpp#L14-L45`](source/injected_dlls_cpp/src/dwmapi/dwmapi.cpp#L14-L45)<br>- Bảng nhảy assembly: [`source/injected_dlls_cpp/src/dwmapi/thunks.asm#L1-L120`](source/injected_dlls_cpp/src/dwmapi/thunks.asm#L1-L120)<br>- Khóa bộ nhớ vĩnh viễn: [`source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h#L37-L50`](source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h#L37-L50) |
| **3** | **Cài cắm mã chạy ngầm (Persistence) 3 tầng & Lợi dụng `steam.exe` sinh tiến trình ẩn**: Tạo Scheduled Task 30 phút/lần vô hạn, và mỗi khi người dùng mở Steam, `dwmapi.dll` tự gọi `CreateProcessW(CREATE_NO_WINDOW)` chạy `DCGaming.RuntimeUpdater.exe` | - [`binaries/unpacked_launcher_assemblies/DCGaming.RuntimeUpdater.dll`](binaries/unpacked_launcher_assemblies/DCGaming.RuntimeUpdater.dll)<br>- [`binaries/unpacked_launcher_assemblies/DC-Runtime.Core.dll`](binaries/unpacked_launcher_assemblies/DC-Runtime.Core.dll) | - Gọi tiến trình ngầm từ `steam.exe`: [`source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L148-L168`](source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L148-L168)<br>- Kiểm tra cổng DPAPI Gate: [`source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L99-L140`](source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L99-L140) |
| **4** | **Can thiệp mạng tầng Kernel (`WinDivert64.sys`) & Thay đổi chính sách DNS Windows NRPT**: Nhúng Zapret2 (`winws2.exe`) sửa gói tin TCP/UDP ở mức nhân và ép đổi bảng phân giải DNS hệ thống của toàn bộ card mạng | - [`source/steamdpi_helper_go/`](source/steamdpi_helper_go/) | - Điều phối driver `WinDivert64.sys` & `winws2`: [`source/steamdpi_helper_go/.../internal/dpi/zapret2/engine.go#L1-L75`](source/steamdpi_helper_go/steam-dpi-helper/internal/dpi/zapret2/engine.go#L1-L75)<br>- Thao túng Windows NRPT: [`source/steamdpi_helper_go/.../internal/steamdns/policy_windows.go#L40-L65`](source/steamdpi_helper_go/steam-dpi-helper/internal/steamdns/policy_windows.go#L40-L65) |
| **5** | **Giả mạo toàn diện bản quyền Steam, phá khóa Denuvo & Spacewar Online-Fix**: Hook `CheckAppOwnership`, chèn toàn bộ AppID lậu vào Package `0`, giả lập vé Denuvo IPC và đổi AppID sang `480` (*Spacewar*) | - [`binaries/injected_steam_dlls/OpenSteamTool.dll`](binaries/injected_steam_dlls/OpenSteamTool.dll) | - Bơm game vào Package 0: [`source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp#L33-L105`](source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp#L33-L105)<br>- Vượt Denuvo qua IPC: [`source/injected_dlls_cpp/src/Hook/Hooks_IPC_ISteamUser.cpp#L50-L120`](source/injected_dlls_cpp/src/Hook/Hooks_IPC_ISteamUser.cpp#L50-L120)<br>- Quét chữ ký Denuvo: [`source/injected_dlls_cpp/src/Pipe/Features/DenuvoAuth/ProtectionScan.cpp#L20-L80`](source/injected_dlls_cpp/src/Pipe/Features/DenuvoAuth/ProtectionScan.cpp#L20-L80)<br>- Đổi sang AppID 480: [`source/injected_dlls_cpp/src/Hook/Hooks_Misc.cpp#L150-L210`](source/injected_dlls_cpp/src/Hook/Hooks_Misc.cpp#L150-L210) |
| **6** | **Xâm phạm tài khoản Steam thật của người dùng (`ManifestDonor`)**: Quét danh sách game bản quyền mà tài khoản người dùng đã mua, tự động lấy `ManifestRequestCode` từ Valve rồi gửi lén lên máy chủ cộng đồng lậu | - [`binaries/injected_steam_dlls/OpenSteamTool.dll`](binaries/injected_steam_dlls/OpenSteamTool.dll) | - Quét kho game và gửi code lên web lậu: [`source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp#L50-L150`](source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp#L50-L150)<br>- Bắt gói tin bản quyền `EMsg 780`: [`source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp#L350-L420`](source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp#L350-L420) |
| **7** | **Chặn bắt Steam Cloud & Phá khóa kiểm soát phụ huynh (Steam Family View)**: Chặn 11 RPC `Cloud.*`, giả lập server lưu trữ cục bộ, và vá nhị phân trực tiếp (`0xEB` / `0x90` NOP) xóa giới hạn giờ chơi | - [`binaries/injected_steam_dlls/cloud_redirect.dll`](binaries/injected_steam_dlls/cloud_redirect.dll) | - 12 hàm Export C: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cr_api.cpp#L27-L145`](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cr_api.cpp#L27-L145)<br>- Chặn bắt gói `Cloud.*`: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cloud_intercept.cpp#L1819-L2480`](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cloud_intercept.cpp#L1819-L2480)<br>- Vá mã máy vượt Parental: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp#L190-L280`](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp#L190-L280) |

---

## CHI TIẾT TỪNG BẰNG CHỨNG KỸ THUẬT

### Bằng chứng 1: Cơ chế "ACTIVE Game" — Thương mại hóa bẻ khóa Steam và đánh cắp Depot

Người dùng chi tiền mua game trên hệ sinh thái `dcgaming.cloud`, tuy nhiên họ hoàn toàn **không nhận được Product Key hay bản quyền hợp lệ** từ Valve Corporation. Khi bấm nút **"ACTIVE"**, Launcher thực hiện bẻ khóa ngoại tuyến thông qua việc tải trộm kịch bản giải mã:

- **📂 File bằng chứng trực tiếp**:
  1. Assembly chính: [`binaries/unpacked_launcher_assemblies/DC-Launcher.dll`](binaries/unpacked_launcher_assemblies/DC-Launcher.dll)
  2. Mã nguồn hook tiêm khóa giải mã: [`source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp` (dòng 45–85)](source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp#L45-L85)
  3. Mã nguồn hook ghi đè Manifest: [`source/injected_dlls_cpp/src/Hook/Hooks_Manifest.cpp` (dòng 100–165)](source/injected_dlls_cpp/src/Hook/Hooks_Manifest.cpp#L100-L165)
  4. Mã nguồn client tải Manifest từ máy chủ lậu: [`source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestClient.cpp` (dòng 40–120)](source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestClient.cpp#L40-L120)

**Cơ chế hoạt động**:
1. Launcher gọi API bí mật `POST /api/launcher/activation/versions/{id}/download-plan` tới `dcgaming.cloud` hoặc trực tiếp sang máy chủ lậu **`hubcapmanifest.com`** (`/api/v1/manifest/`, `/api/v1/lua/`, `/api/v1/lua/basegame/`).
2. Tải về tệp kịch bản `.lua` chứa các lệnh tiêm khóa:
   ```lua
   addappid(AppId, 1, "<64 ký tự Hex: Khóa giải mã AES-256 của Depot>")
   setManifestid(DepotId, "<Manifest_GID>", Size)
   ```
3. Kịch bản `.lua` được ghi lén vào `<SteamRoot>\local-data\scripts\` và `<SteamRoot>\config\lua\`, tệp `.manifest` được ghi vào `<SteamRoot>\depotcache\`.
4. Trong [`source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp` (dòng 50–75)](source/injected_dlls_cpp/src/Hook/Hooks_Decryption.cpp#L50-L75), khi Steam tìm kiếm khóa giải mã game qua hàm `ConfigStoreGetBinary`, hook chặn lại và trả về 32 byte khóa AES-256 từ file `.lua`, ép Steam tải thẳng dữ liệu gốc từ máy chủ CDN của Valve mà không cần sở hữu bản quyền.

---

### Bằng chứng 2: Tấn công DLL Search Order Hijacking chiếm quyền `steam.exe`

Để mã bẻ khóa có hiệu lực trong RAM, `DCGamingLauncher` lợi dụng lỗ hổng nạp DLL của Windows trên tiến trình `steam.exe`:

- **📂 File bằng chứng trực tiếp**:
  1. DLL Proxy giả mạo: [`binaries/injected_steam_dlls/dwmapi.dll`](binaries/injected_steam_dlls/dwmapi.dll) & [`binaries/injected_steam_dlls/xinput1_4.dll`](binaries/injected_steam_dlls/xinput1_4.dll)
  2. Mã nguồn chuyển tiếp hàm API: [`source/injected_dlls_cpp/src/dwmapi/dwmapi.cpp` (dòng 14–45)](source/injected_dlls_cpp/src/dwmapi/dwmapi.cpp#L14-L45)
  3. Bảng nhảy Assembly chuyển tiếp 103 export: [`source/injected_dlls_cpp/src/dwmapi/thunks.asm` (dòng 1–120)](source/injected_dlls_cpp/src/dwmapi/thunks.asm#L1-L120)
  4. Mã nguồn ghim DLL trong bộ nhớ: [`source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h` (dòng 37–50)](source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h#L37-L50)

Trích đoạn mã nguồn nạp DLL hệ thống thật và ghim chặt DLL giả mạo trong bộ nhớ Steam tại [`source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h` (dòng 37–50)](source/injected_dlls_cpp/src/NestG/ProxyBootstrap.h#L37-L50):

```cpp
inline void Attach(HMODULE module) noexcept {
    HMODULE pinned = nullptr;
    // Khóa cứng DLL trong bộ nhớ của steam.exe - ngăn chặn hoàn toàn FreeLibrary gỡ bỏ DLL
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(module), &pinned)) {
        return;
    }
    std::thread([module]() noexcept {
        Initialize(module);
    }).detach();
}
```

➡️ **Ý nghĩa**: Launcher đặt các tệp `dwmapi.dll` và `xinput1_4.dll` giả mạo vào thư mục Steam. Khi `steam.exe` khởi động, Windows ưu tiên nạp 2 DLL này trước thư viện trong `C:\Windows\System32`. Cờ `GET_MODULE_HANDLE_EX_FLAG_PIN` giữ cho DLL chạy vĩnh viễn trong không gian địa chỉ của Steam.

---

### Bằng chứng 3: Cài đặt cơ chế chạy ngầm (Persistence) đa tầng & Kích hoạt tiến trình ẩn từ bên trong `steam.exe`

- **📂 File bằng chứng trực tiếp**:
  1. File nhị phân Updater chạy ngầm: [`binaries/unpacked_launcher_assemblies/DCGaming.RuntimeUpdater.dll`](binaries/unpacked_launcher_assemblies/DCGaming.RuntimeUpdater.dll)
  2. Mã nguồn khởi tạo tiến trình ẩn từ `steam.exe`: [`source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h` (dòng 148–168)](source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L148-L168)
  3. Mã nguồn kiểm tra Gate DPAPI: [`source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h` (dòng 99–140)](source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L99-L140)

Trích đoạn mã nguồn trong [`source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h` (dòng 148–168)](source/injected_dlls_cpp/src/NestG/RuntimeUpdateBootstrap.h#L148-L168):

```cpp
const auto helper = root + L"\\Helper\\DCGaming.RuntimeUpdater.exe";
std::wstring command = L"\"" + helper + L"\" --steam-root \"" + steamRoot + L"\"";

STARTUPINFOW si{};
PROCESS_INFORMATION pi{};
si.cb = sizeof(si);

// ÂM THẦM KHỞI CHẠY TIẾN TRÌNH CẬP NHẬT TỪ BÊN TRONG STEAM.EXE MÀ KHÔNG HIỂN THỊ CỬA SỔ
if (CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
}
```

**Hệ thống thiết lập 3 tầng bám trụ**:
1. **Windows Scheduled Task (`PT30M`)**: Tác vụ `DCGamingLauncher_<User>_<Hash>` chạy tự động mỗi **30 phút** ở chế độ nền vô hạn (`ExecutionTimeLimit = PT0S`).
2. **Registry Run Key**: Ghi khóa khởi động cùng Windows tại `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
3. **Kích hoạt ngầm từ `steam.exe`**: Ngay cả khi người dùng gỡ cài đặt Launcher, mỗi khi mở Steam, `dwmapi.dll` sẽ tự động thực thi `DCGaming.RuntimeUpdater.exe` (`CREATE_NO_WINDOW`) để tự động tải lại và ghi đè toàn bộ các DLL bẻ khóa vào máy.

---

### Bằng chứng 4: Can thiệp mạng mức Kernel (`WinDivert64.sys`) & Sửa đổi chính sách DNS hệ thống

- **📂 File bằng chứng trực tiếp**:
  1. Mã nguồn Go điều phối Zapret2 và driver: [`source/steamdpi_helper_go/steam-dpi-helper/internal/dpi/zapret2/engine.go` (dòng 1–75)](source/steamdpi_helper_go/steam-dpi-helper/internal/dpi/zapret2/engine.go#L1-L75)
  2. Mã nguồn Go can thiệp chính sách DNS Windows NRPT: [`source/steamdpi_helper_go/steam-dpi-helper/internal/steamdns/policy_windows.go` (dòng 40–65)](source/steamdpi_helper_go/steam-dpi-helper/internal/steamdns/policy_windows.go#L40-L65)

Trích đoạn can thiệp Windows Name Resolution Policy Table trong [`source/steamdpi_helper_go/steam-dpi-helper/internal/steamdns/policy_windows.go` (dòng 45–52)](source/steamdpi_helper_go/steam-dpi-helper/internal/steamdns/policy_windows.go#L45-L52):

```powershell
# ÉP TOÀN BỘ PHÂN GIẢI DNS CÁC DOMAIN STEAM PHẢI ĐI QUA PROXY NỘI BỘ
$r = Add-DnsClientNrptRule -Namespace @($p.namespaces) -NameServers '127.0.0.1' -DisplayName 'DCGaming Steam DNS v2' -Comment ('DCGamingSteamDns:'+ $p.tag) -PassThru -ErrorAction Stop
```

➡️ **Ý nghĩa**: Launcher yêu cầu quyền Administrator (`runas`) để giải nén driver nhân **`WinDivert64.sys`** và công cụ **`winws2.exe`** (Zapret2), bắt giữ và cắt nhỏ các gói tin TCP/UDP trên cổng 80/443, đồng thời sửa đổi bảng chính sách DNS Windows NRPT và toàn bộ adapter mạng nhằm kiểm soát lưu lượng truy cập tới Steam.

---

### Bằng chứng 5: Giả mạo bản quyền game, phá khóa Denuvo & Spacewar Online-Fix

- **📂 File bằng chứng trực tiếp**:
  1. DLL lõi bẻ khóa: [`binaries/injected_steam_dlls/OpenSteamTool.dll`](binaries/injected_steam_dlls/OpenSteamTool.dll)
  2. Bơm quyền sở hữu vào Package 0: [`source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp` (dòng 33–105)](source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp#L33-L105)
  3. Vượt Denuvo qua IPC `ISteamUser`: [`source/injected_dlls_cpp/src/Hook/Hooks_IPC_ISteamUser.cpp` (dòng 50–120)](source/injected_dlls_cpp/src/Hook/Hooks_IPC_ISteamUser.cpp#L50-L120)
  4. Quét chữ ký bảo vệ Denuvo trên file game: [`source/injected_dlls_cpp/src/Pipe/Features/DenuvoAuth/ProtectionScan.cpp` (dòng 20–80)](source/injected_dlls_cpp/src/Pipe/Features/DenuvoAuth/ProtectionScan.cpp#L20-L80)
  5. Đánh tráo sang AppID 480 (*Spacewar*): [`source/injected_dlls_cpp/src/Hook/Hooks_Misc.cpp` (dòng 150–210)](source/injected_dlls_cpp/src/Hook/Hooks_Misc.cpp#L150-L210)
  6. Xóa bỏ gói tin ngắt kết nối Family Sharing: [`source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp` (dòng 280–340)](source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp#L280-L340)

Trích đoạn mã nguồn can thiệp Package 0 trong [`source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp` (dòng 33–79)](source/injected_dlls_cpp/src/Hook/Hooks_Package.cpp#L33-L79):

```cpp
constexpr PackageId_t kInjectedPackageId = 0;
constexpr uint64_t kInjectedPkgAccessToken = 10660652434190618804ull;

// BƠM TOÀN BỘ APPID LẬU TỪ FILE .LUA VÀO PACKAGE ID 0 MẶC ĐỊNH
LOG_PACKAGE_INFO("InitFakeLicense(PackageId={}): adding {} apps, oldSize={}", kInjectedPackageId, numApps, pVector->m_Size);
```

**Các cơ chế bẻ khóa tinh vi**:
- **Package 0 Injection**: Bơm danh sách AppID lậu vào Package `0` với token giả lập `10660652434190618804ULL`, đánh lừa `steamclient64.dll` rằng tài khoản đã mua toàn bộ game và DLC.
- **Vượt DRM Denuvo**: Chặn hàm `ISteamUser::GetSteamID` và `GetAppOwnershipTicketExtendedData` để trả về vé kích hoạt Denuvo mua chung (`EticketClient.cpp`).
- **Chơi Online lậu qua Spacewar (AppID 480)**: Chặn `CUser::SpawnProcess`, đổi `GameID` thành `480` để tận dụng hạ tầng P2P của Steam, đồng thời sửa gói tin `CMsgClientGamesPlayed` (`EMsg 742`) để bạn bè vẫn thấy tên game thật.
- **Phá khóa Family Sharing**: Bắt gói tin `k_EMsgClientSharedLibraryStopPlaying` (`EMsg 9406`) và xóa sạch danh sách `stop_apps`, ngăn không cho Valve cưỡng bức tắt game khi có người khác cùng chơi.

---

### Bằng chứng 6: Xâm phạm tài khoản Steam thật của người dùng (`ManifestDonor`)

Hệ thống lạm dụng chính phiên đăng nhập của người dùng để thu thập dữ liệu trái phép phục vụ mạng lưới chia sẻ game lậu:

- **📂 File bằng chứng trực tiếp**:
  1. Mã nguồn trích xuất dữ liệu bản quyền: [`source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp` (dòng 50–150)](source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp#L50-L150)
  2. Bắt gói tin bản quyền `EMsg 780`: [`source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp` (dòng 350–420)](source/injected_dlls_cpp/src/Hook/Hooks_NetPacket.cpp#L350-L420)

Trích đoạn mã nguồn gửi lén `ManifestRequestCode` lên máy chủ lậu tại [`source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp` (dòng 110–135)](source/injected_dlls_cpp/src/Utils/SteamMetadata/ManifestDonor.cpp#L110-L135):

```cpp
// 1. Quét danh sách game bản quyền mà tài khoản người dùng đang sở hữu
// 2. Hỏi máy chủ lậu xem đang thiếu manifest nào: https://manifest.luastools.xyz/manifestwanted
// 3. DÙNG CHÍNH TÀI KHOẢN CỦA NGƯỜI DÙNG để xin mã GetManifestRequestCode từ Valve
// 4. Âm thầm tải mã giải mã lên: https://manifest.luastools.xyz/manifestcode/submit
```

➡️ **Ý nghĩa**: Mỗi người dùng cài đặt `DCGamingLauncher` đều bị biến thành một "botnet node", âm thầm đem tài khoản Steam cá nhân của mình đi lấy mã bản quyền từ Valve để cấp phát cho máy chủ game lậu công cộng.

---

### Bằng chứng 7: Chặn bắt Steam Cloud & Phá khóa kiểm soát phụ huynh (Steam Family View)

- **📂 File bằng chứng trực tiếp**:
  1. DLL xử lý Cloud: [`binaries/injected_steam_dlls/cloud_redirect.dll`](binaries/injected_steam_dlls/cloud_redirect.dll)
  2. Bảng 12 hàm export C: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cr_api.cpp` (dòng 27–145)](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cr_api.cpp#L27-L145)
  3. Chặn bắt RPC Cloud: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cloud_intercept.cpp` (dòng 1819–2480)](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/platform/win/cloud_intercept.cpp#L1819-L2480)
  4. Vá mã máy vượt Parental Control: [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp` (dòng 190–280)](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp#L190-L280)

Trích đoạn vá mã máy nhị phân trong RAM tại [`source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp` (dòng 200–215 & 255–275)](source/injected_dlls_cpp/dcgaming-cloudredirect/cr_src/src/common/parental_bypass.cpp#L200-L275):

```cpp
// 1. Vượt qua kiểm tra chữ ký cài đặt Family View: sửa JNZ (0x75) thành JMP (0xEB)
const char* needle = "Parental settings signature did not ver";
if (c[0] == 0x84 && c[1] == 0xC0 && (c[2] == 0x75 || c[2] == 0xEB)) {
    c[2] = 0xEB; // Ép Steam luôn coi như chữ ký Family View hợp lệ
}

// 2. Vô hiệu hóa tính năng cưỡng bức đóng game khi hết giờ chơi của phụ huynh
uint8_t* dailyStr = FindString(base, mi.SizeOfImage, "Daily playtime expired, closing games");
// GHI ĐÈ TOÀN BỘ 5 BYTE LỆNH GỌI CloseGamesForParental BẰNG LỆNH NOP (0x90 0x90 0x90 0x90 0x90)
memset(site, 0x90, 5);
```

➡️ **Ý nghĩa**: `cloud_redirect.dll` ngăn chặn Steam gửi gói tin Cloud Save của game lậu lên Valve (tránh bị phát hiện gian lận), tự lưu trữ cục bộ tại máy người dùng, đồng thời dùng kỹ thuật vá mã máy trong bộ nhớ RAM (`0xEB` và `0x90 NOP`) để triệt tiêu hoàn toàn tính năng giới hạn giờ chơi của phụ huynh (Steam Family View).
