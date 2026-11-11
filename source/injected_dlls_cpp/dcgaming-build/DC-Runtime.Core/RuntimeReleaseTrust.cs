using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DCGaming.RuntimeUpdates;

public sealed class RuntimeReleaseVerifier
{
    public const int MaxEnvelopeBytes = 2 * 1024 * 1024;
    private readonly IReadOnlyDictionary<string, string> keys;
    public RuntimeReleaseVerifier(IReadOnlyDictionary<string, string>? keys = null) => this.keys = keys ?? RuntimeReleaseKeys.PublicKeys;
    public RuntimeReleaseManifest VerifyReleaseBytes(byte[] bytes) => VerifyRelease(RuntimeReleaseTrust.ReadEnvelope(bytes));
    public RuntimeChannelManifest VerifyChannelBytes(byte[] bytes, DateTimeOffset now) => VerifyChannel(RuntimeReleaseTrust.ReadEnvelope(bytes), now);

    public RuntimeReleaseManifest VerifyRelease(SignedRuntimeEnvelope envelope)
    {
        var manifest = Verify<RuntimeReleaseManifest>(envelope);
        ValidateRelease(manifest);
        return manifest;
    }

    public RuntimeChannelManifest VerifyChannel(SignedRuntimeEnvelope envelope, DateTimeOffset now)
    {
        var channel = Verify<RuntimeChannelManifest>(envelope);
        if (channel.SchemaVersion != 1 || !RuntimeUpdatePaths.IsSegment(channel.Channel) ||
            !RuntimeUpdatePaths.IsSegment(channel.ReleaseId) || !RuntimeUpdatePaths.IsHash(channel.ManifestSha256) ||
            channel.Sequence <= 0 || channel.MinimumSequence < 0 || channel.MinimumSequence > channel.Sequence ||
            channel.IssuedAtUtc > now.AddMinutes(5) || channel.ExpiresAtUtc <= now ||
            channel.ExpiresAtUtc <= channel.IssuedAtUtc || channel.ExpiresAtUtc - channel.IssuedAtUtc > TimeSpan.FromDays(31) ||
            channel.RevokedReleaseIds is null || channel.RevokedReleaseIds.Count > 512 ||
            channel.RevokedReleaseIds.Any(id => !RuntimeUpdatePaths.IsSegment(id)) ||
            channel.RevokedReleaseIds.Contains(channel.ReleaseId, StringComparer.OrdinalIgnoreCase))
            throw new InvalidDataException("Runtime channel is invalid, expired or revoked.");
        return channel;
    }

    private T Verify<T>(SignedRuntimeEnvelope envelope)
    {
        try
        {
            if (envelope is null || envelope.KeyId is null || envelope.Payload is null || envelope.Signature is null ||
                envelope.Payload.Length > MaxEnvelopeBytes || !keys.TryGetValue(envelope.KeyId, out var spki))
                throw new InvalidDataException("Unknown runtime release signer.");
            var payload = Convert.FromBase64String(envelope.Payload);
            var signature = Convert.FromBase64String(envelope.Signature);
            using var rsa = RSA.Create();
            rsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(spki), out var read);
            if (rsa.KeySize < 3072 || read != Convert.FromBase64String(spki).Length ||
                !rsa.VerifyData(payload, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pss))
                throw new InvalidDataException("Runtime release signature is invalid.");
            using (var doc = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 24 })) RejectDuplicateProperties(doc.RootElement);
            return JsonSerializer.Deserialize<T>(payload, RuntimeUpdateJson.Options) ?? throw new InvalidDataException("Empty runtime release.");
        }
        catch (Exception ex) when (ex is FormatException or JsonException or CryptographicException or ArgumentException)
        { throw new InvalidDataException("Runtime release proof is invalid.", ex); }
    }

    internal static void RejectDuplicateProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new InvalidDataException("Duplicate runtime metadata property.");
                RejectDuplicateProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicateProperties(item);
    }

    public static void ValidateRelease(RuntimeReleaseManifest release)
    {
        if (release.SchemaVersion != 1 || release.BundleId != "bettersteamtools-cloud" ||
            release.RuntimeMode != "BetterSteamToolsCloudRedirect" || release.Architecture != "x64" ||
            !RuntimeUpdatePaths.IsSegment(release.ReleaseId) || !RuntimeUpdatePaths.IsSegment(release.Channel) ||
            !System.Version.TryParse(release.Version, out _) || !System.Version.TryParse(release.MinimumDesktopVersion, out _) ||
            !System.Version.TryParse(release.MinimumHelperVersion, out var helper) || helper > new Version(1, 0, 0) ||
            release.BootstrapProtocol != 1 || release.RentalIsolationProtocol != 1 || release.RentalLoginProtocol != 1 ||
            !Regex.IsMatch(release.OpenSteamToolCommit ?? "", "\\A[0-9a-fA-F]{40}\\z") ||
            !Version.TryParse(release.CloudRedirectVersion, out _) ||
            release.Files is null || release.Files.Count is < 4 or > 256 ||
            release.SteamBuilds is null || release.SteamBuilds.Count is < 1 or > 128)
            throw new InvalidDataException("Runtime release protocol or identity is unsupported.");
        long total = 0;
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var downloads = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in release.Files)
        {
            if (file is null || !RuntimeUpdatePaths.IsPayloadPath(file.InstallPath) ||
                !RuntimeUpdatePaths.IsRelativePath(file.RelativePath) || !paths.Add(file.InstallPath) ||
                !downloads.Add(file.RelativePath) || !RuntimeUpdatePaths.IsHash(file.Sha256) || file.Size is <= 0 or > 134217728 ||
                file.Component != RuntimeUpdatePaths.ComponentFor(file.InstallPath))
                throw new InvalidDataException("Runtime release file is outside its allowed scope.");
            total = checked(total + file.Size);
        }
        if (total > 536870912 || !paths.Contains("OpenSteamTool.dll") || !paths.Contains("dwmapi.dll") ||
            !paths.Contains("xinput1_4.dll") || !paths.Contains("cloud_redirect.dll"))
            throw new InvalidDataException("Runtime release is incomplete or oversized.");
        var builds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var build in release.SteamBuilds)
        {
            if (build is null || !RuntimeUpdatePaths.IsHash(build.SteamClientSha256) || !RuntimeUpdatePaths.IsHash(build.SteamUiSha256) ||
                !builds.Add(build.SteamClientSha256 + ":" + build.SteamUiSha256) ||
                !paths.Contains($"opensteamtool/pattern/steamclient/{build.SteamClientSha256.ToLowerInvariant()}.toml") ||
                !paths.Contains($"opensteamtool/ipc/steamclient/{build.SteamClientSha256.ToLowerInvariant()}.toml") ||
                !paths.Contains($"opensteamtool/pattern/steamui/{build.SteamUiSha256.ToLowerInvariant()}.toml"))
                throw new InvalidDataException("Runtime release lacks its declared Steam compatibility metadata.");
        }
    }
}

public static class RuntimeReleaseTrust
{
    public static RuntimeReleaseVerifier CreateVerifier() => new();
    public static RuntimeReleaseManifest VerifyRelease(SignedRuntimeEnvelope envelope) => new RuntimeReleaseVerifier().VerifyRelease(envelope);
    public static RuntimeChannelManifest VerifyChannel(SignedRuntimeEnvelope envelope, DateTimeOffset now) => new RuntimeReleaseVerifier().VerifyChannel(envelope, now);
    public static SignedRuntimeEnvelope ReadEnvelope(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length > RuntimeReleaseVerifier.MaxEnvelopeBytes) throw new InvalidDataException("Runtime proof is oversized.");
        using (var document = JsonDocument.Parse(bytes.ToArray(), new JsonDocumentOptions { MaxDepth = 24 }))
            RuntimeReleaseVerifier.RejectDuplicateProperties(document.RootElement);
        return JsonSerializer.Deserialize<SignedRuntimeEnvelope>(bytes, RuntimeUpdateJson.Options) ?? throw new InvalidDataException("Empty runtime proof.");
    }
    public static RuntimeReleaseManifest VerifyReleaseBytes(byte[] bytes) => VerifyRelease(ReadEnvelope(bytes));
}

public static class RuntimeUpdatePaths
{
    public static bool IsSegment(string? value) => value is { Length: >= 1 and <= 80 } && Regex.IsMatch(value, "\\A[a-zA-Z0-9][a-zA-Z0-9._-]*\\z") && value != "." && value != "..";
    public static bool IsHash(string? value) => value is { Length: 64 } && value.All(c => char.IsAsciiHexDigit(c));
    public static bool IsRelativePath(string? value)
    {
        if (value is null || value.Length is < 1 or > 240 || value.Contains('\\') || value.StartsWith('/')) return false;
        return value.Split('/').All(part => IsSegment(part) && !part.EndsWith('.') && !Regex.IsMatch(part, "\\A(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\\.|\\z)", RegexOptions.IgnoreCase));
    }
    public static bool IsPayloadPath(string? path) => IsRelativePath(path) &&
        (path is "OpenSteamTool.dll" or "dwmapi.dll" or "xinput1_4.dll" or "cloud_redirect.dll" ||
         Regex.IsMatch(path!, "\\Aopensteamtool/(?:pattern/(?:steamclient|steamui)|ipc/steamclient)/[a-f0-9]{64}\\.toml\\z") ||
         path is "cloud_redirect/THIRD_PARTY_NOTICES.md" or "cloud_redirect/licenses/OpenSteamTool-LICENSE.txt" or
             "cloud_redirect/licenses/CloudRedirect-LICENSE.txt" or "cloud_redirect/sources/BetterSteamTools-DCGaming-source.zip");
    public static string ComponentFor(string path) => path switch
    {
        "dwmapi.dll" or "xinput1_4.dll" => "bootstrap",
        "cloud_redirect.dll" => "cloud",
        _ when path.StartsWith("cloud_redirect/", StringComparison.Ordinal) => "source",
        _ => "core"
    };
    public static void Guard(string path)
    {
        var full = Path.GetFullPath(path);
        for (var current = full; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
        {
            try
            {
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Runtime update path contains a reparse point.");
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
    public static string Resolve(string root, string relative)
    {
        if (!IsRelativePath(relative)) throw new InvalidDataException("Unsafe runtime update path.");
        var fullRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        var full = Path.GetFullPath(Path.Combine(fullRoot, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Runtime path escaped its root.");
        Guard(full);
        return full;
    }
}
