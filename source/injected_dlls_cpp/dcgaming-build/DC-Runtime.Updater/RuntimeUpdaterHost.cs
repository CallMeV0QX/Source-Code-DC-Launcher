using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

public sealed class RuntimeUpdaterHost(RuntimeUpdaterInstallationStore store, RuntimeUpdaterClient client,
    RuntimeReleaseVerifier? verifier = null, Func<bool>? allSteamStopped = null, string? gatesDirectory = null,
    Action<RuntimeUpdaterInstallation, string, string>? notify = null, RuntimeUpdaterInteraction? interaction = null)
{
    private readonly RuntimeReleaseVerifier verifier = verifier ?? RuntimeReleaseTrust.CreateVerifier();
    private readonly Func<bool> allSteamStopped = allSteamStopped ?? AreAllSteamProcessesStopped;

    /// <summary>Downloads while Steam runs; never infers that Steam Cloud has finished syncing.</summary>
    public Task<string> RunAsync(RuntimeUpdaterInstallation installation, CancellationToken token = default)
        => interaction is null ? RunLegacyAsync(installation, token) : RunInteractiveAsync(installation, token);

    private async Task<string> RunLegacyAsync(RuntimeUpdaterInstallation installation, CancellationToken token)
    {
        var home = store.InstallationDirectory(installation.InstallationId);
        Directory.CreateDirectory(home);
        RuntimeUpdaterPaths.Guard(home);
        FileStream singleton;
        try { singleton = new FileStream(Path.Combine(home, "helper.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { return "AlreadyRunning"; }
        using (singleton)
        {
          while (true)
          {
            IReadOnlyList<RuntimeUpdaterVerifiedFile> files;
            RuntimeReleaseManifest release;
            RuntimeChannelManifest channel;
            string releaseJson;
            string channelJson;
            using (var lease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
            {
                if (lease is null) return Status(installation, "DeferredActiveBusy");
                installation = store.Load(installation.InstallationId);
                installation = await ObserveCandidateHealthAsync(installation, token).ConfigureAwait(false);
                Status(installation, "Checking");
                var transaction = new RuntimeUpdaterTransaction(store, allSteamStopped, verifier);
                if (transaction.HasPending(installation))
                {
                    RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                    if (!allSteamStopped())
                    {
                        Status(installation, "RecoveryWaitingSteamExit");
                        lease.Dispose();
                        var recoveryDeadline = DateTimeOffset.UtcNow.AddHours(12);
                        while (!allSteamStopped())
                        {
                            if (DateTimeOffset.UtcNow >= recoveryDeadline) return Status(installation, "DeferredSteamStillRunning");
                            await Task.Delay(TimeSpan.FromSeconds(2), token).ConfigureAwait(false);
                        }
                        continue;
                    }
                    transaction.Recover(installation, token);
                    installation = store.Load(installation.InstallationId);
                }
                if (!installation.AutoUpdateEnabled) return Status(installation, "AutoUpdateDisabled");
                installation = await client.RenewIfNeededAsync(store, installation, DateTimeOffset.UtcNow, token).ConfigureAwait(false);
                var channelBytes = await client.GetChannelAsync(installation, token).ConfigureAwait(false);
                channelJson = Encoding.UTF8.GetString(channelBytes);
                channel = verifier.VerifyChannelBytes(channelBytes, DateTimeOffset.UtcNow);
                ValidateChannel(installation, channel);
                installation = installation with { HighestSeenSequence = Math.Max(installation.HighestSeenSequence, channel.Sequence),
                    LatestChannelEnvelopeJson = channelJson, KnownRevokedReleaseIds = installation.KnownRevokedReleaseIds
                        .Concat(channel.RevokedReleaseIds).Distinct(StringComparer.OrdinalIgnoreCase).ToList() };
                store.Save(installation);
                if (installation.InstalledSequence < channel.MinimumSequence) RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                if (installation.InstalledEnvelopeJson is not null)
                {
                    var installed = verifier.VerifyRelease(RuntimeReleaseTrust.ReadEnvelope(Encoding.UTF8.GetBytes(installation.InstalledEnvelopeJson)));
                    if (channel.RevokedReleaseIds.Contains(installed.ReleaseId, StringComparer.OrdinalIgnoreCase))
                        RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                }
                var releaseBytes = await client.GetReleaseAsync(installation, channel.ReleaseId, token).ConfigureAwait(false);
                releaseJson = Encoding.UTF8.GetString(releaseBytes);
                var envelope = RuntimeReleaseTrust.ReadEnvelope(releaseBytes);
                release = verifier.VerifyRelease(envelope);
                ValidateReleaseBinding(installation, channel, release, releaseBytes);
                if (installation.KnownRevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase) ||
                    installation.QuarantinedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase))
                {
                    RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                    Notify(installation, "release-unavailable", release.ReleaseId);
                    return Status(installation, installation.KnownRevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase)
                        ? "ReleaseRevoked" : "ReleaseQuarantined");
                }
                var build = ValidateSteamCompatibility(installation.SteamDirectory, release);
                if (installation.InstalledEnvelopeJson == releaseJson && AllInstalledFilesMatch(installation, release))
                {
                    installation = installation with { InstalledSequence = channel.Sequence, InstalledChannelEnvelopeJson = channelJson,
                        Health = installation.Health.State == "Healthy" ? installation.Health with
                        { LastGoodSequence = channel.Sequence, LastGoodChannelEnvelopeJson = channelJson } : installation.Health with
                        { CandidateSequence = installation.Health.CandidateReleaseId == release.ReleaseId ? channel.Sequence : installation.Health.CandidateSequence } };
                    store.Save(installation);
                    WriteGate(installation, release, build);
                    return Status(installation, "UpToDate");
                }
                if (channel.Sequence <= installation.InstalledSequence) throw new InvalidDataException("runtime_sequence_repair_requires_new_release");
                var staging = Path.Combine(home, "Staging", release.ReleaseId);
                RuntimeUpdaterStorageQuota.Check(home, release.Files.Sum(file => file.Size));
                lease.Dispose(); // Staging performs no Steam/profile mutation; ACTIVE can proceed while the network is slow.
                files = await client.DownloadReleaseAsync(installation, release, staging, token).ConfigureAwait(false);
                Status(installation, "DownloadedWaitingSteamExit");
                if (!allSteamStopped()) Notify(installation, "downloaded-waiting-steam-exit", release.ReleaseId);
            }

            // No supported signal proves Steam Cloud idle yet. V1 deliberately awaits a natural user shutdown.
            var waitUntil = DateTimeOffset.UtcNow.AddHours(12);
            while (!allSteamStopped())
            {
                if (DateTimeOffset.UtcNow >= waitUntil) return Status(installation, "DeferredSteamStillRunning");
                await Task.Delay(TimeSpan.FromSeconds(2), token).ConfigureAwait(false);
            }
            using (var lease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
            {
                if (lease is null) return Status(installation, "DeferredActiveBusy");
                var current = store.Load(installation.InstallationId);
                if (!current.AutoUpdateEnabled) return Status(current, "AutoUpdateDisabled");
                if (current.InstalledSequence != installation.InstalledSequence || current.Mode != installation.Mode ||
                    current.ApiOrigin != installation.ApiOrigin || current.InstalledEnvelopeJson != installation.InstalledEnvelopeJson)
                    return Status(current, "DeferredInstallationChanged");
                // Recheck publication/revocation immediately before mutating, after any long wait for Steam to close.
                var latestBytes = await client.GetChannelAsync(current, token).ConfigureAwait(false);
                var latest = verifier.VerifyChannelBytes(latestBytes, DateTimeOffset.UtcNow);
                ValidateChannel(current, latest);
                if (latest.Sequence != channel.Sequence || latest.ReleaseId != channel.ReleaseId ||
                    !Same(latest.ManifestSha256, channel.ManifestSha256)) return Status(current, "DeferredReleaseChanged");
                var build = ValidateSteamCompatibility(current.SteamDirectory, release);
                if (!allSteamStopped()) return Status(current, "DeferredSteamRestarted");
                RuntimeUpdaterNativeGate.Disable(current.SteamDirectory, gatesDirectory);
                new RuntimeUpdaterTransaction(store, allSteamStopped, verifier).Apply(current, files, channel.Sequence,
                    releaseJson, channelJson, token);
                current = store.Load(current.InstallationId);
                WriteGate(current, release, build);
                return Status(current, "InstalledWaitingSteamStart");
            }
          }
        }
    }

    private async Task<string> RunInteractiveAsync(RuntimeUpdaterInstallation installation, CancellationToken token)
    {
        if (interaction!.SteamExitWaitTimeout <= TimeSpan.Zero || interaction.SteamExitWaitTimeout > TimeSpan.FromHours(12))
            throw new ArgumentOutOfRangeException(nameof(interaction.SteamExitWaitTimeout));
        RuntimeUpdaterInstallationStore.Validate(installation);
        var home = store.InstallationDirectory(installation.InstallationId);
        Directory.CreateDirectory(home);
        RuntimeUpdaterPaths.Guard(home);
        FileStream singleton;
        try { singleton = new FileStream(Path.Combine(home, "helper.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { return "AlreadyRunning"; }
        using (singleton)
        {
            // Recovery never requests shutdown or inherits a restart intent from an interrupted operation.
            while (true)
            {
                using var recoveryLease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory);
                if (recoveryLease is null) return PublishStatus(installation, "DeferredActiveBusy");
                installation = store.Load(installation.InstallationId);
                var recovery = new RuntimeUpdaterTransaction(store, allSteamStopped, verifier);
                if (!recovery.HasPending(installation)) break;
                RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                if (!allSteamStopped())
                {
                    PublishStatus(installation, "RecoveryWaitingSteamExit");
                    recoveryLease.Dispose();
                    if (!await WaitForNaturalExitAsync(token).ConfigureAwait(false))
                        return PublishStatus(installation, "DeferredSteamStillRunning");
                    continue;
                }
                Report("Recovering");
                recovery.Recover(installation, token);
                installation = store.Load(installation.InstallationId);
                break;
            }

            RuntimeReleaseManifest release;
            RuntimeChannelManifest channel;
            string releaseJson;
            string channelJson;
            using (var lease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
            {
                if (lease is null) return PublishStatus(installation, "DeferredActiveBusy");
                installation = store.Load(installation.InstallationId);
                installation = await ObserveCandidateHealthAsync(installation, token).ConfigureAwait(false);
                if (!installation.AutoUpdateEnabled) return PublishStatus(installation, "AutoUpdateDisabled");
                Report("Checking");
                installation = await client.RenewIfNeededAsync(store, installation, interaction.UtcNow(), token).ConfigureAwait(false);
                var channelBytes = await client.GetChannelAsync(installation, token).ConfigureAwait(false);
                channelJson = Encoding.UTF8.GetString(channelBytes);
                channel = verifier.VerifyChannelBytes(channelBytes, interaction.UtcNow());
                ValidateChannel(installation, channel);
                installation = installation with
                {
                    HighestSeenSequence = Math.Max(installation.HighestSeenSequence, channel.Sequence),
                    LatestChannelEnvelopeJson = channelJson,
                    KnownRevokedReleaseIds = installation.KnownRevokedReleaseIds.Concat(channel.RevokedReleaseIds)
                        .Distinct(StringComparer.OrdinalIgnoreCase).ToList()
                };
                store.Save(installation);
                if (installation.InstalledSequence < channel.MinimumSequence)
                    RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                if (installation.InstalledEnvelopeJson is not null)
                {
                    var installed = verifier.VerifyReleaseBytes(Encoding.UTF8.GetBytes(installation.InstalledEnvelopeJson));
                    if (installation.KnownRevokedReleaseIds.Contains(installed.ReleaseId, StringComparer.OrdinalIgnoreCase))
                        RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                }
                var releaseBytes = await client.GetReleaseAsync(installation, channel.ReleaseId, token).ConfigureAwait(false);
                releaseJson = Encoding.UTF8.GetString(releaseBytes);
                release = verifier.VerifyReleaseBytes(releaseBytes);
                ValidateReleaseBinding(installation, channel, release, releaseBytes);
                if (installation.KnownRevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase) ||
                    installation.QuarantinedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase))
                {
                    RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
                    return PublishStatus(installation, installation.KnownRevokedReleaseIds.Contains(release.ReleaseId, StringComparer.OrdinalIgnoreCase)
                        ? "ReleaseRevoked" : "ReleaseQuarantined");
                }
                var build = ValidateSteamCompatibility(installation.SteamDirectory, release);
                if (installation.SchemaVersion == 2 &&
                    installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.DesktopSession &&
                    installation.InstalledSequence == 0 && installation.InstalledEnvelopeJson is null &&
                    AllInstalledFilesMatch(installation, release))
                {
                    // The transition launcher already installed the independently pinned bytes.
                    // Adopt an identical independently signed release without downloading or
                    // shutting Steam down a second time. This is metadata publication only.
                    var owned = new Dictionary<string, string>(installation.OwnedHashes, StringComparer.OrdinalIgnoreCase);
                    foreach (var file in release.Files.Where(file => installation.Mode == "Full" || file.Component != "cloud"))
                        owned[file.InstallPath] = file.Sha256;
                    installation = installation with
                    {
                        InstalledSequence = channel.Sequence, InstalledEnvelopeJson = releaseJson,
                        InstalledChannelEnvelopeJson = channelJson, PendingUpdate = null, OwnedHashes = owned,
                        Health = new RuntimeUpdaterHealthState
                        {
                            CandidateReleaseId = release.ReleaseId, CandidateSequence = channel.Sequence,
                            Boundary = RuntimeUpdaterHealth.Capture(installation.SteamDirectory), State = "AwaitingSteamStart"
                        }
                    };
                    store.Save(installation);
                    WriteGate(installation, release, build);
                    return PublishStatus(installation, "UpToDate");
                }
                if (installation.InstalledEnvelopeJson == releaseJson && AllInstalledFilesMatch(installation, release))
                {
                    installation = installation with
                    {
                        InstalledSequence = channel.Sequence, InstalledChannelEnvelopeJson = channelJson, PendingUpdate = null,
                        Health = installation.Health.State == "Healthy" ? installation.Health with
                        { LastGoodSequence = channel.Sequence, LastGoodChannelEnvelopeJson = channelJson } : installation.Health with
                        { CandidateSequence = installation.Health.CandidateReleaseId == release.ReleaseId ? channel.Sequence : installation.Health.CandidateSequence }
                    };
                    store.Save(installation);
                    WriteGate(installation, release, build);
                    return PublishStatus(installation, "UpToDate");
                }
                if (channel.Sequence <= installation.InstalledSequence)
                    throw new InvalidDataException("runtime_sequence_repair_requires_new_release");
            }

            Report("UpdateAvailable", release.Version);
            var staging = Path.Combine(home, "Staging", release.ReleaseId);
            var files = await client.DownloadReleaseAsync(installation, release, staging, token, progress: interaction.Progress).ConfigureAwait(false);
            var restart = false;
            using (var closureLease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
            {
                if (closureLease is null) return PublishStatus(installation, "DeferredActiveBusy");
                var current = store.Load(installation.InstallationId);
                if (!SameInstallation(installation, current)) return PublishStatus(current, "DeferredInstallationChanged");
                current = current with { PendingUpdate = new(release.ReleaseId, channel.Sequence, "Downloaded") };
                store.Save(current);
                installation = current;
                if (!allSteamStopped() && interaction.CloseSteamAsync is not null)
                {
                    Report("ClosingSteam");
                    RuntimeUpdaterSteamClosure closure;
                    try { closure = await interaction.CloseSteamAsync(token).ConfigureAwait(false); }
                    catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                    catch { closure = new(false, false); }
                    restart = closure.IsClosed && closure.ShutdownRequested && allSteamStopped();
                }
                current = current with { PendingUpdate = new(release.ReleaseId, channel.Sequence,
                    "WaitingSteamExit", RestartAfterCommit: restart) };
                store.Save(current);
                installation = current;
            }

            if (!allSteamStopped())
            {
                restart = false;
                installation = installation with { PendingUpdate = installation.PendingUpdate! with { RestartAfterCommit = false } };
                // Save under the mutation lease so a late ACTIVE cannot have its new profile overwritten.
                using (var deferredLease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
                {
                    if (deferredLease is null) return PublishStatus(installation, "DeferredActiveBusy");
                    var current = store.Load(installation.InstallationId);
                    if (!SameInstallation(installation, current)) return PublishStatus(current, "DeferredInstallationChanged");
                    store.Save(current with { PendingUpdate = installation.PendingUpdate });
                }
                PublishStatus(installation, "DownloadedWaitingSteamExit");
                if (!await WaitForNaturalExitAsync(token).ConfigureAwait(false))
                    return PublishStatus(installation, "DeferredSteamStillRunning");
            }

            RuntimeUpdaterInstallation committed;
            using (var lease = RuntimeUpdateLease.TryAcquire(installation.SteamDirectory))
            {
                if (lease is null) return PublishStatus(installation, "DeferredActiveBusy");
                var current = store.Load(installation.InstallationId);
                if (!SameInstallation(installation, current)) return PublishStatus(current, "DeferredInstallationChanged");
                var latestBytes = await client.GetChannelAsync(current, token).ConfigureAwait(false);
                var latest = verifier.VerifyChannelBytes(latestBytes, interaction.UtcNow());
                ValidateChannel(current, latest);
                if (latest.Sequence != channel.Sequence || latest.ReleaseId != channel.ReleaseId ||
                    !Same(latest.ManifestSha256, channel.ManifestSha256)) return PublishStatus(current, "DeferredReleaseChanged");
                var build = ValidateSteamCompatibility(current.SteamDirectory, release);
                if (!allSteamStopped()) return PublishStatus(current, "DeferredSteamRestarted");
                current = current with { PendingUpdate = new(release.ReleaseId, channel.Sequence, "Applying", RestartAfterCommit: restart) };
                store.Save(current);
                RuntimeUpdaterNativeGate.Disable(current.SteamDirectory, gatesDirectory);
                new RuntimeUpdaterTransaction(store, allSteamStopped, verifier).Apply(current, files, channel.Sequence,
                    releaseJson, channelJson, token, interaction.Progress);
                // Apply returned only after its protected transaction committed. No later UI, metadata or start error may undo it.
                committed = store.Load(current.InstallationId);
                try
                {
                    WriteGate(committed, release, build);
                    committed = committed with { PendingUpdate = new(release.ReleaseId, channel.Sequence, "Committed", RestartAfterCommit: restart) };
                    store.Save(committed);
                }
                catch
                {
                    return CommittedStatus(committed, "InstalledWithGateWarning");
                }
            }

            // Release the mutation lease before starting Steam: its proxy may immediately trigger another worker.
            if (restart && interaction.ReopenSteamAsync is not null && allSteamStopped())
            {
                try
                {
                    using (var restartLease = RuntimeUpdateLease.TryAcquire(committed.SteamDirectory))
                    {
                        if (restartLease is null) return CommittedStatus(committed, "InstalledWaitingSteamStart");
                        var current = store.Load(committed.InstallationId);
                        if (current.InstalledSequence != committed.InstalledSequence || current.InstalledEnvelopeJson != releaseJson)
                            return CommittedStatus(current, "InstalledWaitingSteamStart");
                        committed = current with { PendingUpdate = new(release.ReleaseId, channel.Sequence,
                            "RestartAttempted", RestartAfterCommit: true, RestartAttempted: true) };
                        store.Save(committed);
                    }
                    Report("OpeningSteam");
                    // Closing the popup/cancelling after commit cannot revoke a completed installation.
                    using var startDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                    var opened = await interaction.ReopenSteamAsync(startDeadline.Token).WaitAsync(startDeadline.Token).ConfigureAwait(false);
                    return CommittedStatus(committed, opened ? "InstalledSteamReopened" : "InstalledWithLaunchWarning");
                }
                catch { return CommittedStatus(committed, "InstalledWithLaunchWarning"); }
            }
            return CommittedStatus(committed, "InstalledWaitingSteamStart");
        }
    }

    private async Task<bool> WaitForNaturalExitAsync(CancellationToken token)
    {
        var deadline = interaction!.UtcNow() + interaction.SteamExitWaitTimeout;
        while (!allSteamStopped())
        {
            if (interaction.UtcNow() >= deadline) return false;
            await interaction.DelayAsync(TimeSpan.FromSeconds(2), token).ConfigureAwait(false);
        }
        return true;
    }

    private static bool SameInstallation(RuntimeUpdaterInstallation expected, RuntimeUpdaterInstallation current)
        => current.AutoUpdateEnabled && current.InstallationId == expected.InstallationId && current.Channel == expected.Channel &&
           string.Equals(Path.GetFullPath(current.SteamDirectory).TrimEnd('\\', '/'),
               Path.GetFullPath(expected.SteamDirectory).TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase) &&
           current.InstalledSequence == expected.InstalledSequence && current.Mode == expected.Mode &&
           current.ApiOrigin == expected.ApiOrigin && current.InstalledEnvelopeJson == expected.InstalledEnvelopeJson &&
           current.AuthenticationMode == expected.AuthenticationMode && current.OwnerUserId == expected.OwnerUserId;

    private void Report(string stage, string? version = null)
        => RuntimeUpdaterProgressReporting.Report(interaction?.Progress, new(stage, Version: version));

    private string PublishStatus(RuntimeUpdaterInstallation installation, string code)
    {
        Report(code);
        return Status(installation, code);
    }

    private string CommittedStatus(RuntimeUpdaterInstallation installation, string code)
    {
        Report(code);
        try { Status(installation, code); } catch { /* Installation is already committed. */ }
        return code;
    }

    public static RuntimeSteamBuild ValidateSteamCompatibility(string steamDirectory, RuntimeReleaseManifest release)
    {
        RuntimeUpdaterPaths.Guard(steamDirectory);
        var clientHash = RuntimeUpdaterPaths.Hash(Path.Combine(steamDirectory, "steamclient64.dll"));
        var uiHash = RuntimeUpdaterPaths.Hash(Path.Combine(steamDirectory, "steamui.dll"));
        return release.SteamBuilds.SingleOrDefault(build => Same(build.SteamClientSha256, clientHash) && Same(build.SteamUiSha256, uiHash))
            ?? throw new InvalidDataException("steam_build_not_supported");
    }

    public static bool AreAllSteamProcessesStopped()
    {
        var processes = new List<Process>();
        try
        {
            processes.AddRange(Process.GetProcessesByName("steam"));
            processes.AddRange(Process.GetProcessesByName("steamwebhelper"));
            return processes.Count == 0;
        }
        catch { return false; }
        finally { foreach (var process in processes) process.Dispose(); }
    }

    private static void ValidateChannel(RuntimeUpdaterInstallation installation, RuntimeChannelManifest channel)
    {
        if (channel.Channel != installation.Channel || channel.Sequence < installation.HighestSeenSequence ||
            channel.Sequence < installation.InstalledSequence || channel.Sequence < channel.MinimumSequence)
            throw new InvalidDataException("runtime_channel_replay_rejected");
    }

    private static void ValidateReleaseBinding(RuntimeUpdaterInstallation installation, RuntimeChannelManifest channel,
        RuntimeReleaseManifest release, byte[] envelopeBytes)
    {
        var hash = Convert.ToHexString(SHA256.HashData(envelopeBytes));
        if (release.ReleaseId != channel.ReleaseId || release.Channel != channel.Channel || !Same(hash, channel.ManifestSha256))
            throw new InvalidDataException("runtime_release_channel_mismatch");
        // Bootstrap is stable in v1 and cannot silently acquire a new trust root/protocol through an ordinary release.
        foreach (var bootstrap in release.Files.Where(file => file.Component == "bootstrap"))
            if (!installation.OwnedHashes.TryGetValue(bootstrap.InstallPath, out var owned) || !Same(owned, bootstrap.Sha256) ||
                !Same(RuntimeUpdaterPaths.Hash(Path.Combine(installation.SteamDirectory, bootstrap.InstallPath)), bootstrap.Sha256))
                throw new InvalidDataException("runtime_bootstrap_upgrade_required");
    }

    private static bool AllInstalledFilesMatch(RuntimeUpdaterInstallation installation, RuntimeReleaseManifest release)
        => release.Files.Where(file => installation.Mode == "Full" || file.Component != "cloud")
            .All(file => File.Exists(RuntimeUpdatePaths.Resolve(installation.SteamDirectory, file.InstallPath)) &&
                new FileInfo(RuntimeUpdatePaths.Resolve(installation.SteamDirectory, file.InstallPath)).Length == file.Size &&
                Same(RuntimeUpdaterPaths.Hash(RuntimeUpdatePaths.Resolve(installation.SteamDirectory, file.InstallPath)), file.Sha256));

    private async Task<RuntimeUpdaterInstallation> ObserveCandidateHealthAsync(RuntimeUpdaterInstallation installation, CancellationToken token)
    {
        if (installation.Health.CandidateReleaseId is null || installation.Health.Boundary is null || installation.Health.State == "Failed") return installation;
        var session = RuntimeUpdaterHealth.FindSession(installation.SteamDirectory);
        if (session is null) return installation;
        var deadline = DateTimeOffset.UtcNow.AddSeconds(30);
        RuntimeUpdaterHealthResult result;
        do
        {
            result = RuntimeUpdaterHealth.Inspect(installation.SteamDirectory, installation.Health.Boundary, session, installation.Mode == "Full");
            if (result != RuntimeUpdaterHealthResult.Inconclusive) break;
            if (RuntimeUpdaterHealth.FindSession(installation.SteamDirectory) != session) break;
            await Task.Delay(200, token).ConfigureAwait(false);
        } while (DateTimeOffset.UtcNow < deadline);
        return RecordCandidateHealth(installation, result);
    }

    public RuntimeUpdaterInstallation RecordCandidateHealth(RuntimeUpdaterInstallation installation, RuntimeUpdaterHealthResult result)
    {
        if (installation.Health.CandidateReleaseId is null || installation.InstalledEnvelopeJson is null) return installation;
        var release = verifier.VerifyReleaseBytes(Encoding.UTF8.GetBytes(installation.InstalledEnvelopeJson));
        if (release.ReleaseId != installation.Health.CandidateReleaseId || installation.InstalledSequence != installation.Health.CandidateSequence)
            throw new InvalidDataException("runtime_health_candidate_binding_invalid");
        if (result is RuntimeUpdaterHealthResult.CoreFailed or RuntimeUpdaterHealthResult.CloudFailed)
        {
            installation = installation with { QuarantinedReleaseIds = installation.QuarantinedReleaseIds.Append(release.ReleaseId)
                .Distinct(StringComparer.OrdinalIgnoreCase).ToList(), Health = installation.Health with { State = "Failed" } };
            store.Save(installation);
            RuntimeUpdaterNativeGate.Disable(installation.SteamDirectory, gatesDirectory);
            Status(installation, "RuntimeInitializationFailed");
            return installation;
        }
        installation = result == RuntimeUpdaterHealthResult.Healthy
            ? installation with { Health = installation.Health with { State = "Healthy", CandidateReleaseId = null,
                LastGoodSequence = installation.InstalledSequence, LastGoodEnvelopeJson = installation.InstalledEnvelopeJson,
                LastGoodChannelEnvelopeJson = installation.InstalledChannelEnvelopeJson } }
            : installation with { Health = installation.Health with { State = "Inconclusive" } };
        store.Save(installation);
        return installation;
    }

    private void WriteGate(RuntimeUpdaterInstallation installation, RuntimeReleaseManifest release, RuntimeSteamBuild build)
    {
        var runtime = release.Files.Single(file => file.InstallPath == "OpenSteamTool.dll");
        if (!Same(RuntimeUpdaterPaths.Hash(Path.Combine(installation.SteamDirectory, runtime.InstallPath)), runtime.Sha256))
            throw new InvalidDataException("runtime_gate_target_changed");
        RuntimeUpdaterNativeGate.Write(installation.SteamDirectory, build.SteamClientSha256, build.SteamUiSha256, runtime.Sha256, gatesDirectory);
    }

    public string Status(RuntimeUpdaterInstallation installation, string code)
    {
        RuntimeUpdaterPaths.WriteAtomic(Path.Combine(store.InstallationDirectory(installation.InstallationId), "status.json"),
            JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, code, atUtc = DateTimeOffset.UtcNow, installationId = installation.InstallationId }));
        return code;
    }
    private void Notify(RuntimeUpdaterInstallation installation, string code, string release)
    {
        try { notify?.Invoke(installation, code, release); } catch { }
    }
    private static bool Same(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
}
