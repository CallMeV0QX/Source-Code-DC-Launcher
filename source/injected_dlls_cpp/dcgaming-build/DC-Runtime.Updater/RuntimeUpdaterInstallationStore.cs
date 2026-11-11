using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace DCGaming.RuntimeUpdater;

public sealed record RuntimeUpdaterLogBoundary(DateTimeOffset CapturedAtUtc, long Length, string PrefixSha256);
public sealed record RuntimeUpdaterHealthState
{
    public string? CandidateReleaseId { get; init; }
    public long CandidateSequence { get; init; }
    public RuntimeUpdaterLogBoundary? Boundary { get; init; }
    public long LastGoodSequence { get; init; }
    public string? LastGoodEnvelopeJson { get; init; }
    public string? LastGoodChannelEnvelopeJson { get; init; }
    public string State { get; init; } = "NotObserved";
}

public sealed record RuntimeUpdaterInstallation
{
    public int SchemaVersion { get; init; } = 1;
    public string AuthenticationMode { get; init; } = RuntimeUpdaterAuthenticationModes.InstallationCredential;
    public Guid? OwnerUserId { get; init; }
    public Guid InstallationId { get; init; }
    public string SteamDirectory { get; init; } = "";
    public string ApiOrigin { get; init; } = "";
    // Retained only to validate completed journals after a local desktop binding
    // moves to its configured HTTPS server. Pending journals cannot use it.
    public string? PreviousApiOrigin { get; init; }
    public string Credential { get; init; } = "";
    public DateTimeOffset CredentialExpiresAt { get; init; }
    public DateTimeOffset CredentialRenewAfter { get; init; }
    public string Channel { get; init; } = "stable";
    public bool AutoUpdateEnabled { get; init; } = true;
    public List<string> NotificationKeys { get; init; } = [];
    public string Mode { get; init; } = "Core";
    public long InstalledSequence { get; init; }
    public long HighestSeenSequence { get; init; }
    public string? InstalledEnvelopeJson { get; init; }
    public string? InstalledChannelEnvelopeJson { get; init; }
    public string? LatestChannelEnvelopeJson { get; init; }
    public List<string> KnownRevokedReleaseIds { get; init; } = [];
    public List<string> QuarantinedReleaseIds { get; init; } = [];
    public RuntimeUpdaterHealthState Health { get; init; } = new();
    public string? PendingRotationSecret { get; init; }
    public Guid? PendingRotationId { get; init; }
    public Dictionary<string, string> OwnedHashes { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public RuntimeUpdaterPendingUpdate? PendingUpdate { get; init; }
}

/// <summary>Current-user protected installation state. No launcher session is persisted here.</summary>
public sealed class RuntimeUpdaterInstallationStore
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public string RootDirectory { get; }

    public RuntimeUpdaterInstallationStore(string? rootDirectory = null)
    {
        RootDirectory = Path.GetFullPath(rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DCGamingLauncher", "RuntimeUpdates", "Installations"));
        RuntimeUpdaterPaths.Guard(RootDirectory);
    }

    public string InstallationDirectory(Guid id)
    {
        if (id == Guid.Empty) throw new InvalidDataException("installation_id_invalid");
        var directory = Path.Combine(RootDirectory, id.ToString("N"));
        RuntimeUpdaterPaths.Guard(directory);
        return directory;
    }

    public RuntimeUpdaterInstallation Load(Guid id)
    {
        var path = Path.Combine(InstallationDirectory(id), "installation.dat");
        var installation = JsonSerializer.Deserialize<RuntimeUpdaterInstallation>(Unprotect(ReadBounded(path, 4 * 1024 * 1024), id), Json)
            ?? throw new InvalidDataException("installation_invalid");
        Validate(installation);
        if (installation.InstallationId != id) throw new InvalidDataException("installation_binding_invalid");
        if (RuntimeUpdaterPaths.IsWithin(RootDirectory, installation.SteamDirectory))
            throw new InvalidDataException("installation_store_inside_steam");
        return installation;
    }

    public RuntimeUpdaterInstallation? Find(string steamDirectory)
    {
        RuntimeUpdaterPaths.Guard(steamDirectory);
        if (!RuntimeUpdaterPaths.DirectoryExists(RootDirectory)) return null;
        var directories = Directory.GetDirectories(RootDirectory);
        if (directories.Length > 2048) throw new InvalidDataException("installation_count_invalid");
        RuntimeUpdaterInstallation? found = null;
        foreach (var directory in directories)
        {
            if (!Guid.TryParseExact(Path.GetFileName(directory), "N", out var id)) continue;
            var installation = Load(id);
            if (!string.Equals(Path.GetFullPath(installation.SteamDirectory).TrimEnd('\\', '/'),
                Path.GetFullPath(steamDirectory).TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase)) continue;
            if (found is not null) throw new InvalidDataException("installation_binding_ambiguous");
            found = installation;
        }
        return found;
    }

    public void Save(RuntimeUpdaterInstallation installation)
    {
        Validate(installation);
        if (RuntimeUpdaterPaths.IsWithin(RootDirectory, installation.SteamDirectory))
            throw new InvalidDataException("installation_store_inside_steam");
        RuntimeUpdaterPaths.WriteAtomic(Path.Combine(InstallationDirectory(installation.InstallationId), "installation.dat"),
            Protect(JsonSerializer.SerializeToUtf8Bytes(installation, Json), installation.InstallationId));
    }

    public static void Validate(RuntimeUpdaterInstallation installation)
    {
        var credentialAuthentication = installation.SchemaVersion == 1 &&
            installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.InstallationCredential &&
            installation.OwnerUserId is null && installation.Credential is { Length: 76 } &&
            installation.Credential.StartsWith(installation.InstallationId.ToString("N") + ".", StringComparison.Ordinal) &&
            installation.Credential[33..].All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_') &&
            (installation.PendingRotationSecret is null || installation.PendingRotationSecret.Length == 43 &&
                installation.PendingRotationSecret.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_') && installation.PendingRotationId is not null);
        var desktopAuthentication = installation.SchemaVersion == 2 &&
            installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.DesktopSession &&
            installation.OwnerUserId != Guid.Empty && installation.Credential is { Length: 0 } &&
            installation.CredentialExpiresAt == default && installation.CredentialRenewAfter == default &&
            installation.PendingRotationId is null && installation.PendingRotationSecret is null;
        if ((!credentialAuthentication && !desktopAuthentication) || installation.InstallationId == Guid.Empty ||
            !Path.IsPathFullyQualified(installation.SteamDirectory) ||
            !Uri.TryCreate(installation.ApiOrigin, UriKind.Absolute, out var origin) ||
            origin.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(origin.UserInfo) ||
            origin.AbsolutePath != "/" || !string.IsNullOrEmpty(origin.Query) || !string.IsNullOrEmpty(origin.Fragment) ||
            (installation.PreviousApiOrigin is { } previous &&
                (!desktopAuthentication || origin.IsLoopback ||
                 !Uri.TryCreate(previous, UriKind.Absolute, out var prior) || !prior.IsLoopback ||
                 prior.Scheme != Uri.UriSchemeHttps || prior.UserInfo.Length != 0 || prior.AbsolutePath != "/" ||
                 prior.Query.Length != 0 || prior.Fragment.Length != 0)) ||
            installation.Mode is not ("Full" or "Core") ||
            (credentialAuthentication ? installation.Channel is not ("stable" or "preview")
                : installation.Channel is not ("desktop-stable" or "desktop-preview")) ||
            installation.InstalledSequence < 0 || installation.HighestSeenSequence < 0 ||
            installation.OwnedHashes.Count > 4096 || installation.KnownRevokedReleaseIds.Count > 512 ||
            installation.KnownRevokedReleaseIds.Any(id => !DCGaming.RuntimeUpdates.RuntimeUpdatePaths.IsSegment(id)) ||
            installation.QuarantinedReleaseIds.Count > 128 || installation.QuarantinedReleaseIds.Any(id => !DCGaming.RuntimeUpdates.RuntimeUpdatePaths.IsSegment(id)) ||
            installation.NotificationKeys.Count > 64 || installation.NotificationKeys.Any(key => !RuntimeUpdaterPaths.IsHash(key)) ||
            installation.Health.CandidateSequence < 0 || installation.Health.LastGoodSequence < 0 ||
            installation.Health.Boundary is { Length: < 0 or > 1048576 } ||
            installation.InstalledEnvelopeJson?.Length > 2 * 1024 * 1024 || installation.LatestChannelEnvelopeJson?.Length > 2 * 1024 * 1024)
            throw new InvalidDataException("installation_invalid");
        if (installation.PendingUpdate is { } pending &&
            (!DCGaming.RuntimeUpdates.RuntimeUpdatePaths.IsSegment(pending.ReleaseId) || pending.Sequence <= 0 ||
             pending.Phase is not ("Downloaded" or "WaitingSteamExit" or "Applying" or "Committed" or "RestartAttempted") ||
             pending.RestartAttempted && !pending.RestartAfterCommit))
            throw new InvalidDataException("installation_pending_update_invalid");
        RuntimeUpdaterPaths.Guard(installation.SteamDirectory);
        foreach (var file in installation.OwnedHashes)
        {
            RuntimeUpdaterPaths.ValidateRuntimePath(file.Key, allowBootstrap: true);
            if (!RuntimeUpdaterPaths.IsHash(file.Value)) throw new InvalidDataException("installation_hash_invalid");
        }
    }

    internal static byte[] Protect(byte[] bytes, Guid id) => ProtectedData.Protect(bytes, Entropy(id), DataProtectionScope.CurrentUser);
    internal static byte[] Unprotect(byte[] bytes, Guid id) => ProtectedData.Unprotect(bytes, Entropy(id), DataProtectionScope.CurrentUser);
    private static byte[] Entropy(Guid id) => Encoding.UTF8.GetBytes("DCGaming.RuntimeUpdater.v1|" + id.ToString("N") + "|" + WindowsIdentity.GetCurrent().User?.Value);

    internal static byte[] ReadBounded(string path, int maximum)
    {
        RuntimeUpdaterPaths.Guard(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 || stream.Length > maximum) throw new InvalidDataException("state_size_invalid");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        return bytes;
    }
}
