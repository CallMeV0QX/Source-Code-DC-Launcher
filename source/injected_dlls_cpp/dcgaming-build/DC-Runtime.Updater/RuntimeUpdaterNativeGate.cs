using System.Security.Cryptography;
using System.Text;

namespace DCGaming.RuntimeUpdater;

/// <summary>Fail-closed bootstrap compatibility evidence; no capability or credential is included.</summary>
public static class RuntimeUpdaterNativeGate
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("DCGaming.RuntimeUpdater.NativeGate.v1");

    public static string GatePath(string steamDirectory, string? gatesDirectory = null)
    {
        var canonical = Path.GetFullPath(steamDirectory).TrimEnd('\\', '/');
        var binding = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical.ToUpperInvariant())));
        var root = gatesDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DCGamingLauncher", "RuntimeUpdates", "Gates");
        return Path.Combine(root, binding + ".dat");
    }

    public static void Write(string steamDirectory, string steamClientSha256, string steamUiSha256,
        string runtimeSha256, string? gatesDirectory = null)
    {
        RuntimeUpdaterPaths.Guard(steamDirectory);
        if (!RuntimeUpdaterPaths.IsHash(steamClientSha256) || !RuntimeUpdaterPaths.IsHash(steamUiSha256) ||
            !RuntimeUpdaterPaths.IsHash(runtimeSha256)) throw new InvalidDataException("native_gate_hash_invalid");
        var canonical = Path.GetFullPath(steamDirectory).TrimEnd('\\', '/');
        if (canonical.Contains('\n') || canonical.Contains('\r')) throw new InvalidDataException("native_gate_root_invalid");
        var clientKey = steamClientSha256.ToLowerInvariant();
        var uiKey = steamUiSha256.ToLowerInvariant();
        var clientPattern = RuntimeUpdaterPaths.Hash(Path.Combine(canonical, "opensteamtool", "pattern", "steamclient", clientKey + ".toml"));
        var clientIpc = RuntimeUpdaterPaths.Hash(Path.Combine(canonical, "opensteamtool", "ipc", "steamclient", clientKey + ".toml"));
        var uiPattern = RuntimeUpdaterPaths.Hash(Path.Combine(canonical, "opensteamtool", "pattern", "steamui", uiKey + ".toml"));
        if (clientPattern is null || clientIpc is null || uiPattern is null) throw new InvalidDataException("native_gate_metadata_missing");
        var plain = Encoding.UTF8.GetBytes($"version=1\nsteamRoot={canonical}\nsteamClientSha256={steamClientSha256.ToUpperInvariant()}\nsteamUiSha256={steamUiSha256.ToUpperInvariant()}\nruntimeSha256={runtimeSha256.ToUpperInvariant()}\nsteamClientPatternSha256={clientPattern}\nsteamClientIpcSha256={clientIpc}\nsteamUiPatternSha256={uiPattern}\npending=0\n");
        RuntimeUpdaterPaths.WriteAtomic(GatePath(steamDirectory, gatesDirectory), ProtectedData.Protect(plain, Entropy, DataProtectionScope.CurrentUser));
    }

    public static void Disable(string steamDirectory, string? gatesDirectory = null)
    {
        var path = GatePath(steamDirectory, gatesDirectory);
        RuntimeUpdaterPaths.Guard(path);
        if (RuntimeUpdaterPaths.ExistingAttributes(path) is not null) File.Delete(path);
    }
}
