using System.Text.Json;

namespace DCGaming.RuntimeUpdates;

public sealed record SignedRuntimeEnvelope
{
    public string KeyId { get; init; } = "";
    public string Payload { get; init; } = "";
    public string Signature { get; init; } = "";
}

public sealed record RuntimeReleaseFile
{
    public string RelativePath { get; init; } = "";
    public string InstallPath { get; init; } = "";
    public long Size { get; init; }
    public string Sha256 { get; init; } = "";
    public string Component { get; init; } = "core";
}

public sealed record RuntimeSteamBuild
{
    public string SteamClientSha256 { get; init; } = "";
    public string SteamUiSha256 { get; init; } = "";
}

public sealed record RuntimeReleaseManifest
{
    public int SchemaVersion { get; init; } = 1;
    public string ReleaseId { get; init; } = "";
    public string BundleId { get; init; } = "bettersteamtools-cloud";
    public string Version { get; init; } = "";
    public string Channel { get; init; } = "stable";
    public string Architecture { get; init; } = "x64";
    public string RuntimeMode { get; init; } = "BetterSteamToolsCloudRedirect";
    public string MinimumDesktopVersion { get; init; } = "2.2.34";
    public string OpenSteamToolCommit { get; init; } = "";
    public string CloudRedirectVersion { get; init; } = "2.6.5";
    public string MinimumHelperVersion { get; init; } = "1.0.0";
    public int BootstrapProtocol { get; init; } = 1;
    public int RentalIsolationProtocol { get; init; } = 1;
    public int RentalLoginProtocol { get; init; } = 1;
    public List<RuntimeReleaseFile> Files { get; init; } = [];
    public List<RuntimeSteamBuild> SteamBuilds { get; init; } = [];
}

public sealed record RuntimeChannelManifest
{
    public int SchemaVersion { get; init; } = 1;
    public string Channel { get; init; } = "stable";
    public long Sequence { get; init; }
    public string ReleaseId { get; init; } = "";
    public string ManifestSha256 { get; init; } = "";
    public DateTimeOffset IssuedAtUtc { get; init; }
    public DateTimeOffset ExpiresAtUtc { get; init; }
    public List<string> RevokedReleaseIds { get; init; } = [];
    public long MinimumSequence { get; init; }
}

public static class RuntimeUpdateJson
{
    public static JsonSerializerOptions Options { get; } = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        MaxDepth = 24,
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
    };
}
