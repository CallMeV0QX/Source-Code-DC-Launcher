using System.Diagnostics;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

internal static class Program
{
    [STAThread]
    private static async Task<int> Main(string[] args)
    {
        var action = args.Length == 3 ? args[0] : "--run";
        var offset = args.Length == 3 ? 1 : 0;
        if (args.Length is not (2 or 3) || action is not ("--run" or "--status" or "--enable" or "--disable") ||
            args[offset] != "--steam-root" || !Path.IsPathFullyQualified(args[offset + 1])) return 2;
        RuntimeUpdaterHost? host = null;
        RuntimeUpdaterInstallation? installation = null;
        RuntimeUpdaterInstallationStore? store = null;
        try
        {
            if (action == "--run" && RuntimeBackgroundLauncherBinding.TryAcquire(args[offset + 1], out var launcher))
            {
                // Keep the independently signed executable/dependency handles held until
                // the background launcher finishes. A verified launch failure never falls
                // through into a different update policy or an unverified executable.
                using (launcher)
                using (var process = Process.Start(launcher!.StartInfo))
                {
                    if (process is null) return 4;
                    await process.WaitForExitAsync().ConfigureAwait(false);
                    return process.ExitCode;
                }
            }
            store = new RuntimeUpdaterInstallationStore();
            installation = store.Find(args[offset + 1]);
            if (installation is null) return 3;
            if (action == "--status")
            {
                Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { installation.AutoUpdateEnabled,
                    installation.InstalledSequence, installation.HighestSeenSequence, Health = installation.Health.State }));
                return 0;
            }
            if (action is "--enable" or "--disable")
            {
                using var lease = DCGaming.RuntimeUpdates.RuntimeUpdateLease.TryAcquire(installation.SteamDirectory);
                if (lease is null) return 4;
                installation = store.Load(installation.InstallationId) with { AutoUpdateEnabled = action == "--enable" };
                store.Save(installation);
                if (action == "--disable") return 0;
            }
            using var client = new RuntimeUpdaterClient();
            host = new RuntimeUpdaterHost(store, client, notify: (current, code, release) => RuntimeUpdaterNotifications.Show(store, current, code, release));
            using var cancellation = new CancellationTokenSource(TimeSpan.FromHours(13));
            await host.RunAsync(installation, cancellation.Token).ConfigureAwait(false);
            return 0;
        }
        catch (Exception exception)
        {
            // Exception messages can contain URLs/headers; only the stable type is recorded.
            if (host is not null && installation is not null)
            {
                try { host.Status(installation, "Failed:" + exception.GetType().Name); } catch { }
                if (store is not null)
                {
                    var code = exception switch
                    {
                        HttpRequestException { StatusCode: System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden } => "authentication-required",
                        InvalidDataException { Message: "runtime_bootstrap_upgrade_required" } => "bootstrap-upgrade-required",
                        InvalidDataException { Message: "steam_build_not_supported" } => "steam-unsupported",
                        _ => null
                    };
                    if (code is not null)
                    {
                        try { RuntimeUpdaterNotifications.Show(store, installation, code, installation.CredentialExpiresAt.ToString("O")); } catch { }
                    }
                }
            }
            return 1;
        }
    }
}
