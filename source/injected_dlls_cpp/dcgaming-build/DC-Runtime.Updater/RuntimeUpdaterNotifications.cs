using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

internal static class RuntimeUpdaterNotifications
{
    internal static void Show(RuntimeUpdaterInstallationStore store, RuntimeUpdaterInstallation installation, string code, string release)
    {
        var message = code switch
        {
            "downloaded-waiting-steam-exit" => "DCGaming đã tải bản cập nhật tương thích Steam. Hãy thoát Steam sau khi game và đồng bộ save hoàn tất. Bản mới sẽ được cài khi Steam đóng và sử dụng ở lần mở tiếp theo.",
            "authentication-required" => "DCGaming cần xác thực lại quyền cập nhật runtime. Hãy mở launcher, đăng nhập và ACTIVE lại để khôi phục cập nhật tự động.",
            "bootstrap-upgrade-required" => "Bộ cập nhật nền cần phiên bản mới. Hãy cập nhật launcher và ACTIVE lại một lần để tiếp tục tự cập nhật runtime.",
            "steam-unsupported" => "Phiên bản Steam hiện tại chưa có runtime DCGaming tương thích được phát hành. Hệ thống giữ nguyên file và sẽ kiểm tra lại ở lần mở Steam tiếp theo.",
            "release-unavailable" => "Runtime DCGaming hiện tại đã bị chặn hoặc khởi tạo thất bại. Hệ thống giữ backup và không tự khởi động lại Steam. Hãy mở launcher để kiểm tra hoặc đợi bản sửa mới.",
            _ => null
        };
        if (message is null) return;
        // A foreground notification thread keeps an error message visible after the host exits,
        // while the update/recovery task continues independently from the user's acknowledgement.
        var thread = new Thread(() =>
        {
            try
            {
                var deadline = DateTimeOffset.UtcNow.AddSeconds(5);
                IDisposable? lease;
                while ((lease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory)) is null)
                {
                    if (DateTimeOffset.UtcNow >= deadline) return;
                    Thread.Sleep(100);
                }
                using (lease)
                {
                    installation = store.Load(installation.InstallationId);
                    var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(code + "|" + release)));
                    if (installation.NotificationKeys.Contains(key)) return;
                    store.Save(installation with { NotificationKeys = installation.NotificationKeys.Append(key).TakeLast(64).ToList() });
                }
                MessageBoxW(IntPtr.Zero, message, "DCGaming • Cập nhật Steam", 0x00000040 | 0x00010000);
            }
            catch { }
        }) { IsBackground = false, Name = "DCGaming runtime update notification" };
        thread.Start();
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr window, string text, string caption, uint type);
}
