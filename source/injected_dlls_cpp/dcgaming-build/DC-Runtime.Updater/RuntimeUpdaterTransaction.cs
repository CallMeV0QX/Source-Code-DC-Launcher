using System.Security.Cryptography;
using System.Text.Json;
using System.Text;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

public sealed record RuntimeUpdaterVerifiedFile(string InstallPath, string StagedPath, long Size, string Sha256);

/// <summary>Owns runtime files only. It never opens Lua, game manifests, saves or cloud configuration.</summary>
public sealed class RuntimeUpdaterTransaction(RuntimeUpdaterInstallationStore store, Func<bool> allSteamStopped,
    RuntimeReleaseVerifier? releaseVerifier = null)
{
    private readonly RuntimeReleaseVerifier releaseVerifier = releaseVerifier ?? RuntimeReleaseTrust.CreateVerifier();
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private const int MaximumFileSize = 128 * 1024 * 1024;
    private const long MaximumTotalSize = 512L * 1024 * 1024;

    public void Apply(RuntimeUpdaterInstallation installation, IReadOnlyList<RuntimeUpdaterVerifiedFile> files,
        long sequence, string envelopeJson, string channelEnvelopeJson, CancellationToken cancellationToken = default,
        IProgress<RuntimeUpdaterProgress>? progress = null)
    {
        RuntimeUpdaterInstallationStore.Validate(installation);
        if (sequence <= installation.InstalledSequence || sequence < installation.HighestSeenSequence ||
            files.Count is 0 or > 256 || files.Sum(file => file.Size) > MaximumTotalSize)
            throw new InvalidDataException("update_plan_invalid");
        var release = ValidateProof(installation, sequence, envelopeJson, channelEnvelopeJson, DateTimeOffset.UtcNow);
        ValidateFileBinding(installation, files, release, checkUnchanged: true);
        RuntimeUpdaterHost.ValidateSteamCompatibility(installation.SteamDirectory, release);
        EnsureStopped(cancellationToken);
        if (HasPending(installation)) throw new InvalidOperationException("runtime_recovery_pending");
        RuntimeUpdaterStorageQuota.Check(store.InstallationDirectory(installation.InstallationId), files.Sum(file => file.Size));
        var operation = Guid.NewGuid();
        var directory = Path.Combine(store.InstallationDirectory(installation.InstallationId), "Transactions", operation.ToString("N"));
        var initial = Path.Combine(store.InstallationDirectory(installation.InstallationId), "Preparing", operation.ToString("N"));
        RuntimeUpdaterPaths.Guard(directory);
        RuntimeUpdaterPaths.Guard(initial);
        if (RuntimeUpdaterPaths.IsWithin(directory, installation.SteamDirectory)) throw new InvalidDataException("backup_inside_steam");
        Directory.CreateDirectory(initial);
        var journal = new Journal
        {
            InstallationId = installation.InstallationId, SteamDirectory = Path.GetFullPath(installation.SteamDirectory),
            ApiOrigin = installation.ApiOrigin, BeforeSequence = installation.InstalledSequence,
            AfterEnvelope = envelopeJson, AfterChannelEnvelope = channelEnvelopeJson, AfterSequence = sequence,
            BeforeEnvelope = installation.InstalledEnvelopeJson, BeforeChannelEnvelope = installation.InstalledChannelEnvelopeJson,
            BeforeHashes = new(installation.OwnedHashes, StringComparer.OrdinalIgnoreCase), BeforeHealth = installation.Health
        };
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var totalBytes = files.Sum(file => file.Size);
        RuntimeUpdaterProgressReporting.Report(progress, new("BackingUp", TotalBytes: totalBytes, TotalFiles: files.Count));
        foreach (var file in files)
        {
            EnsureStopped(cancellationToken);
            if (!paths.Add(file.InstallPath) || file.Size is <= 0 or > MaximumFileSize || !RuntimeUpdaterPaths.IsHash(file.Sha256))
                throw new InvalidDataException("update_file_invalid");
            RuntimeUpdaterPaths.ValidateRuntimePath(file.InstallPath);
            if (installation.Mode == "Core" && file.InstallPath == "cloud_redirect.dll") throw new InvalidDataException("runtime_mode_change_rejected");
            RuntimeUpdaterPaths.Guard(file.StagedPath);
            if (RuntimeUpdaterPaths.IsWithin(file.StagedPath, installation.SteamDirectory)) throw new InvalidDataException("staging_inside_steam");
            Verify(file.StagedPath, file.Size, file.Sha256);
            if (file.InstallPath.EndsWith(".dll", StringComparison.Ordinal)) RuntimeUpdaterPaths.ValidatePeX64(file.StagedPath);
            var target = RuntimeUpdaterPaths.Target(installation.SteamDirectory, file.InstallPath);
            var original = RuntimeUpdaterPaths.Hash(target);
            if (original is not null && (!installation.OwnedHashes.TryGetValue(file.InstallPath, out var owned) || !Same(original, owned)))
                throw new InvalidDataException("runtime_target_not_owned");
            var entry = new Entry { RelativePath = file.InstallPath, OriginalHash = original, IntendedHash = file.Sha256, Size = file.Size };
            if (original is not null)
            {
                var bytes = RuntimeUpdaterInstallationStore.ReadBounded(target, MaximumFileSize);
                if (!Same(Convert.ToHexString(SHA256.HashData(bytes)), original)) throw new InvalidDataException("runtime_source_drift");
                RuntimeUpdaterPaths.WriteAtomic(Path.Combine(initial, journal.Entries.Count.ToString("D4") + ".bin"), bytes);
            }
            journal.Entries.Add(entry);
            RuntimeUpdaterProgressReporting.Report(progress, new("BackingUp", TotalBytes: totalBytes,
                CompletedFiles: journal.Entries.Count, TotalFiles: files.Count, FileName: file.InstallPath));
        }
        SaveJournal(initial, journal);
        Directory.CreateDirectory(Path.GetDirectoryName(directory)!);
        RuntimeUpdaterPaths.Guard(directory);
        Directory.Move(initial, directory); // Publish a complete recoverable operation, never an empty journal directory.
        try
        {
            ValidateRecovery(directory, journal, cancellationToken);
            RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory);
            long publishedBytes = 0;
            var publishedFiles = 0;
            foreach (var file in files)
            {
                EnsureStopped(cancellationToken);
                var target = RuntimeUpdaterPaths.Target(installation.SteamDirectory, file.InstallPath);
                var entry = journal.Entries.Single(entry => entry.RelativePath == file.InstallPath);
                if (!Same(RuntimeUpdaterPaths.Hash(target), entry.OriginalHash)) throw new InvalidDataException("runtime_target_drift");
                var bytes = RuntimeUpdaterInstallationStore.ReadBounded(file.StagedPath, MaximumFileSize);
                if (bytes.LongLength != file.Size || !Same(Convert.ToHexString(SHA256.HashData(bytes)), file.Sha256))
                    throw new InvalidDataException("runtime_staging_drift");
                RuntimeUpdaterPaths.WriteAtomic(target, bytes);
                publishedBytes += file.Size;
                RuntimeUpdaterProgressReporting.Report(progress, new("Installing", publishedBytes, totalBytes,
                    ++publishedFiles, files.Count, file.InstallPath));
            }
            EnsureStopped(cancellationToken);
            RuntimeUpdaterHost.ValidateSteamCompatibility(installation.SteamDirectory, release);
            foreach (var file in files) Verify(RuntimeUpdaterPaths.Target(installation.SteamDirectory, file.InstallPath), file.Size, file.Sha256);
            var hashes = new Dictionary<string, string>(installation.OwnedHashes, StringComparer.OrdinalIgnoreCase);
            foreach (var file in files) hashes[file.InstallPath] = file.Sha256;
            var current = store.Load(installation.InstallationId);
            store.Save(current with
            {
                InstalledSequence = sequence, HighestSeenSequence = Math.Max(sequence, current.HighestSeenSequence),
                InstalledEnvelopeJson = envelopeJson, InstalledChannelEnvelopeJson = channelEnvelopeJson, OwnedHashes = hashes,
                Health = current.Health with { CandidateReleaseId = release.ReleaseId, CandidateSequence = sequence,
                    Boundary = RuntimeUpdaterHealth.Capture(installation.SteamDirectory), State = "AwaitingSteamStart" }
            });
            journal.Status = "Committed";
            SaveJournal(directory, journal);
            RuntimeUpdaterProgressReporting.Report(progress, new("FilesCommitted", totalBytes, totalBytes,
                files.Count, files.Count));
        }
        catch
        {
            // Cleanup is independent from a cancelled network/host token, with a bounded deadline.
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(35));
            RuntimeUpdaterProgressReporting.Report(progress, new("RollingBack"));
            try { Rollback(directory, journal, cleanup.Token); } catch { }
            throw;
        }
    }

    public bool HasPending(RuntimeUpdaterInstallation installation)
        => Enumerate(installation).Any(entry => LoadJournal(entry, installation).Status == "Pending");

    public void Recover(RuntimeUpdaterInstallation installation, CancellationToken cancellationToken = default)
    {
        foreach (var directory in Enumerate(installation))
        {
            var journal = LoadJournal(directory, installation);
            if (journal.Status == "Pending") Rollback(directory, journal, cancellationToken);
        }
    }

    private IEnumerable<string> Enumerate(RuntimeUpdaterInstallation installation)
    {
        var root = Path.Combine(store.InstallationDirectory(installation.InstallationId), "Transactions");
        RuntimeUpdaterPaths.Guard(root);
        if (!RuntimeUpdaterPaths.DirectoryExists(root)) return [];
        var directories = Directory.GetDirectories(root);
        if (directories.Length > 2048 || directories.Any(directory => !Guid.TryParseExact(Path.GetFileName(directory), "N", out _)))
            throw new InvalidDataException("runtime_journal_directory_invalid");
        return directories.OrderBy(path => path, StringComparer.Ordinal).ToArray();
    }

    private void ValidateRecovery(string directory, Journal journal, CancellationToken cancellationToken)
    {
        EnsureStopped(cancellationToken);
        for (var index = 0; index < journal.Entries.Count; index++)
        {
            var entry = journal.Entries[index];
            var target = RuntimeUpdaterPaths.Target(journal.SteamDirectory, entry.RelativePath);
            var hash = RuntimeUpdaterPaths.Hash(target);
            if (!Same(hash, entry.OriginalHash) && !Same(hash, entry.IntendedHash))
                throw new InvalidDataException("runtime_recovery_target_drift");
            if (entry.OriginalHash is not null)
            {
                var backup = Path.Combine(directory, index.ToString("D4") + ".bin");
                if (!Same(RuntimeUpdaterPaths.Hash(backup), entry.OriginalHash)) throw new InvalidDataException("runtime_backup_invalid");
            }
        }
    }

    private void Rollback(string directory, Journal journal, CancellationToken cancellationToken)
    {
        ValidateRecovery(directory, journal, cancellationToken); // Preflight the entire operation before changing any target.
        for (var index = journal.Entries.Count - 1; index >= 0; index--)
        {
            EnsureStopped(cancellationToken);
            var entry = journal.Entries[index];
            var target = RuntimeUpdaterPaths.Target(journal.SteamDirectory, entry.RelativePath);
            var observed = RuntimeUpdaterPaths.Hash(target);
            if (Same(observed, entry.OriginalHash)) continue;
            if (!Same(observed, entry.IntendedHash)) throw new InvalidDataException("runtime_recovery_target_drift");
            if (entry.OriginalHash is null) File.Delete(target);
            else
            {
                var bytes = RuntimeUpdaterInstallationStore.ReadBounded(Path.Combine(directory, index.ToString("D4") + ".bin"), MaximumFileSize);
                if (!Same(Convert.ToHexString(SHA256.HashData(bytes)), entry.OriginalHash)) throw new InvalidDataException("runtime_backup_invalid");
                RuntimeUpdaterPaths.WriteAtomic(target, bytes);
            }
        }
        EnsureStopped(cancellationToken);
        var current = store.Load(journal.InstallationId);
        store.Save(current with { InstalledSequence = journal.BeforeSequence, InstalledEnvelopeJson = journal.BeforeEnvelope,
            InstalledChannelEnvelopeJson = journal.BeforeChannelEnvelope, OwnedHashes = journal.BeforeHashes, Health = journal.BeforeHealth });
        journal.Status = "RolledBack";
        SaveJournal(directory, journal);
    }

    private Journal LoadJournal(string directory, RuntimeUpdaterInstallation installation)
    {
        var journal = JsonSerializer.Deserialize<Journal>(RuntimeUpdaterInstallationStore.Unprotect(
            RuntimeUpdaterInstallationStore.ReadBounded(Path.Combine(directory, "journal.dat"), 4 * 1024 * 1024), installation.InstallationId), Json)
            ?? throw new InvalidDataException("runtime_journal_invalid");
        if (journal.SchemaVersion != 1 || journal.InstallationId != installation.InstallationId ||
            !string.Equals(journal.SteamDirectory, Path.GetFullPath(installation.SteamDirectory), StringComparison.OrdinalIgnoreCase) ||
            (journal.ApiOrigin != installation.ApiOrigin &&
                (installation.PreviousApiOrigin is null || journal.ApiOrigin != installation.PreviousApiOrigin ||
                 journal.Status is not ("Committed" or "RolledBack"))) ||
            journal.Status is not ("Pending" or "Committed" or "RolledBack") ||
            journal.Entries.Count is 0 or > 256 || journal.Entries.Sum(entry => entry.Size) > MaximumTotalSize)
            throw new InvalidDataException("runtime_journal_binding_invalid");
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in journal.Entries)
        {
            RuntimeUpdaterPaths.ValidateRuntimePath(entry.RelativePath);
            if (!paths.Add(entry.RelativePath) || !RuntimeUpdaterPaths.IsHash(entry.IntendedHash) ||
                entry.OriginalHash is not null && !RuntimeUpdaterPaths.IsHash(entry.OriginalHash) || entry.Size is <= 0 or > MaximumFileSize)
                throw new InvalidDataException("runtime_journal_entry_invalid");
            if (entry.OriginalHash is not null && (!journal.BeforeHashes.TryGetValue(entry.RelativePath, out var owned) || !Same(owned, entry.OriginalHash)))
                throw new InvalidDataException("runtime_journal_original_not_owned");
        }
        var recoveryClock = ReadChannelIssuedAt(journal.AfterChannelEnvelope).AddSeconds(1);
        var release = ValidateProof(installation with { InstalledSequence = journal.BeforeSequence, HighestSeenSequence = journal.BeforeSequence,
            KnownRevokedReleaseIds = [], QuarantinedReleaseIds = [] },
            journal.AfterSequence, journal.AfterEnvelope, journal.AfterChannelEnvelope, recoveryClock);
        ValidateFileBinding(installation, journal.Entries.Select(entry => new RuntimeUpdaterVerifiedFile(entry.RelativePath, "", entry.Size, entry.IntendedHash)).ToArray(),
            release, checkUnchanged: false);
        if (journal.BeforeEnvelope is not null)
        {
            var before = releaseVerifier.VerifyReleaseBytes(Encoding.UTF8.GetBytes(journal.BeforeEnvelope));
            foreach (var file in before.Files.Where(file => journal.BeforeHashes.ContainsKey(file.InstallPath)))
                if (!Same(journal.BeforeHashes[file.InstallPath], file.Sha256)) throw new InvalidDataException("runtime_journal_original_proof_invalid");
        }
        return journal;
    }

    private RuntimeReleaseManifest ValidateProof(RuntimeUpdaterInstallation installation, long sequence, string envelopeJson,
        string channelEnvelopeJson, DateTimeOffset now)
    {
        var releaseBytes = Encoding.UTF8.GetBytes(envelopeJson);
        var release = releaseVerifier.VerifyReleaseBytes(releaseBytes);
        var channel = releaseVerifier.VerifyChannelBytes(Encoding.UTF8.GetBytes(channelEnvelopeJson), now);
        if (channel.Sequence != sequence || channel.Channel != installation.Channel || release.Channel != channel.Channel ||
            channel.ReleaseId != release.ReleaseId || !Same(channel.ManifestSha256, Convert.ToHexString(SHA256.HashData(releaseBytes))) ||
            installation.KnownRevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase) ||
            installation.QuarantinedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase) ||
            channel.RevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase))
            throw new InvalidDataException("runtime_transaction_proof_invalid");
        return release;
    }

    private static DateTimeOffset ReadChannelIssuedAt(string channelEnvelopeJson)
    {
        var envelope = RuntimeReleaseTrust.ReadEnvelope(Encoding.UTF8.GetBytes(channelEnvelopeJson));
        var channel = JsonSerializer.Deserialize<RuntimeChannelManifest>(Convert.FromBase64String(envelope.Payload), RuntimeUpdateJson.Options)
            ?? throw new InvalidDataException("runtime_channel_invalid");
        return channel.IssuedAtUtc;
    }

    private static void ValidateFileBinding(RuntimeUpdaterInstallation installation, IReadOnlyList<RuntimeUpdaterVerifiedFile> files,
        RuntimeReleaseManifest release, bool checkUnchanged)
    {
        foreach (var file in files)
        {
            var signed = release.Files.SingleOrDefault(candidate => candidate.InstallPath == file.InstallPath);
            if (signed is null || signed.Component == "bootstrap" || signed.Size != file.Size || !Same(signed.Sha256, file.Sha256))
                throw new InvalidDataException("runtime_file_proof_mismatch");
        }
        if (!checkUnchanged) return;
        foreach (var file in release.Files.Where(file => installation.Mode == "Full" || file.Component != "cloud"))
        {
            if (files.Any(planned => planned.InstallPath == file.InstallPath)) continue;
            var path = RuntimeUpdatePaths.Resolve(installation.SteamDirectory, file.InstallPath);
            if (!File.Exists(path) || new FileInfo(path).Length != file.Size || !Same(RuntimeUpdaterPaths.Hash(path), file.Sha256))
                throw new InvalidDataException("runtime_release_file_omitted");
        }
    }

    private void SaveJournal(string directory, Journal journal)
        => RuntimeUpdaterPaths.WriteAtomic(Path.Combine(directory, "journal.dat"), RuntimeUpdaterInstallationStore.Protect(
            JsonSerializer.SerializeToUtf8Bytes(journal, Json), journal.InstallationId));

    private void EnsureStopped(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (!allSteamStopped()) throw new InvalidOperationException("steam_not_verified_stopped");
    }

    private static bool Same(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    private static void Verify(string path, long size, string hash)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != size || !Same(RuntimeUpdaterPaths.Hash(path), hash))
            throw new InvalidDataException("runtime_file_verification_failed");
    }

    private sealed class Journal
    {
        public int SchemaVersion { get; set; } = 1;
        public Guid InstallationId { get; set; }
        public string SteamDirectory { get; set; } = "";
        public string ApiOrigin { get; set; } = "";
        public string Status { get; set; } = "Pending";
        public long BeforeSequence { get; set; }
        public long AfterSequence { get; set; }
        public string AfterEnvelope { get; set; } = "";
        public string AfterChannelEnvelope { get; set; } = "";
        public string? BeforeEnvelope { get; set; }
        public string? BeforeChannelEnvelope { get; set; }
        public RuntimeUpdaterHealthState BeforeHealth { get; set; } = new();
        public Dictionary<string, string> BeforeHashes { get; set; } = [];
        public List<Entry> Entries { get; set; } = [];
    }
    private sealed class Entry
    {
        public string RelativePath { get; set; } = "";
        public string? OriginalHash { get; set; }
        public string IntendedHash { get; set; } = "";
        public long Size { get; set; }
    }
}
