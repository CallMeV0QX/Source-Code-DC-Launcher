using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

public sealed class RuntimeUpdaterClient : IDisposable
{
    private readonly HttpClient http;
    private readonly bool ownsClient;
    private readonly Func<CancellationToken, Task<string>>? desktopAccessToken;
    public RuntimeUpdaterClient(HttpClient? http = null, Func<CancellationToken, Task<string>>? desktopAccessToken = null)
    {
        this.desktopAccessToken = desktopAccessToken;
        ownsClient = http is null;
        this.http = http ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, AutomaticDecompression = DecompressionMethods.None })
            { Timeout = TimeSpan.FromMinutes(3) };
    }

    public async Task<RuntimeUpdaterInstallation> RenewIfNeededAsync(RuntimeUpdaterInstallationStore store,
        RuntimeUpdaterInstallation installation, DateTimeOffset now, CancellationToken token = default)
    {
        RuntimeUpdaterInstallationStore.Validate(installation);
        if (installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.DesktopSession) return installation;
        if (installation.PendingRotationSecret is null && installation.CredentialRenewAfter > now) return installation;
        if (installation.PendingRotationSecret is null)
        {
            installation = installation with { PendingRotationId = Guid.NewGuid(), PendingRotationSecret = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_') };
            store.Save(installation); // Durable intent allows replaying exactly this rotation after a lost response.
        }
        using var request = await RequestAsync(installation, HttpMethod.Post, "api/runtime-updates/installations/renew", token).ConfigureAwait(false);
        request.Content = JsonContent.Create(new { rotationId = installation.PendingRotationId, nextToken = installation.PendingRotationSecret });
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
        var bytes = await ReadResponse(response, request.RequestUri!, 4096, token).ConfigureAwait(false);
        var credential = JsonSerializer.Deserialize<CredentialResponse>(bytes, new JsonSerializerOptions(JsonSerializerDefaults.Web))
            ?? throw new InvalidDataException("runtime_credential_invalid");
        if (credential.InstallationId != installation.InstallationId || credential.Token != installation.PendingRotationSecret ||
            credential.ExpiresAtUtc <= now || credential.RenewAfterUtc <= now || credential.RenewAfterUtc >= credential.ExpiresAtUtc)
            throw new InvalidDataException("runtime_credential_binding_invalid");
        installation = installation with { Credential = installation.InstallationId.ToString("N") + "." + credential.Token,
            CredentialExpiresAt = credential.ExpiresAtUtc, CredentialRenewAfter = credential.RenewAfterUtc,
            PendingRotationId = null, PendingRotationSecret = null };
        store.Save(installation);
        return installation;
    }

    public Task<byte[]> GetChannelAsync(RuntimeUpdaterInstallation installation, CancellationToken token = default)
        => GetAsync(installation, RouteRoot(installation) + "/channels/" + installation.Channel, RuntimeReleaseVerifier.MaxEnvelopeBytes, token);

    public Task<byte[]> GetReleaseAsync(RuntimeUpdaterInstallation installation, string releaseId, CancellationToken token = default)
    {
        if (!RuntimeUpdatePaths.IsSegment(releaseId)) throw new InvalidDataException("runtime_release_id_invalid");
        return GetAsync(installation, RouteRoot(installation) + "/releases/" + releaseId, RuntimeReleaseVerifier.MaxEnvelopeBytes, token);
    }

    public async Task<IReadOnlyList<RuntimeUpdaterVerifiedFile>> DownloadReleaseAsync(RuntimeUpdaterInstallation installation,
        RuntimeReleaseManifest release, string stagingDirectory, CancellationToken token = default, bool includeBootstrap = false,
        IProgress<RuntimeUpdaterProgress>? progress = null)
    {
        RuntimeReleaseVerifier.ValidateRelease(release);
        RuntimeUpdaterInstallationStore.Validate(installation);
        RuntimeUpdaterPaths.Guard(stagingDirectory);
        if (RuntimeUpdaterPaths.IsWithin(stagingDirectory, installation.SteamDirectory)) throw new InvalidDataException("staging_inside_steam");
        RuntimeUpdaterStorageQuota.Check(stagingDirectory, release.Files.Sum(file => file.Size));
        Directory.CreateDirectory(stagingDirectory);
        var files = new List<RuntimeUpdaterVerifiedFile>();
        var required = release.Files.Where(file => (includeBootstrap || file.Component != "bootstrap") &&
            (installation.Mode == "Full" || file.Component != "cloud")).ToArray();
        var totalBytes = required.Sum(file => file.Size);
        long completedBytes = 0;
        foreach (var file in required)
        {
            token.ThrowIfCancellationRequested();
            var target = RuntimeUpdatePaths.Resolve(stagingDirectory, file.InstallPath);
            // Reuse a fully verified staged file; the owning release metadata remains authenticated.
            if (File.Exists(target) && new FileInfo(target).Length == file.Size && Same(RuntimeUpdaterPaths.Hash(target), file.Sha256))
            {
                if (file.InstallPath.EndsWith(".dll", StringComparison.Ordinal)) RuntimeUpdaterPaths.ValidatePeX64(target);
                files.Add(new(file.InstallPath, target, file.Size, file.Sha256));
                completedBytes += file.Size;
                RuntimeUpdaterProgressReporting.Report(progress, new("ReusedStagedFile", completedBytes, totalBytes,
                    files.Count, required.Length, file.InstallPath));
                continue;
            }
            var url = RouteRoot(installation) + "/releases/" + release.ReleaseId + "/files/" + string.Join('/', file.RelativePath.Split('/').Select(Uri.EscapeDataString));
            using var request = await RequestAsync(installation, HttpMethod.Get, url, token).ConfigureAwait(false);
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            EnsureResponse(response, request.RequestUri!);
            if (response.Content.Headers.ContentLength is long length && length != file.Size) throw new InvalidDataException("runtime_download_size_invalid");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            var temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                await using (var input = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false))
                await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous | FileOptions.WriteThrough))
                {
                    var buffer = new byte[65536];
                    long total = 0;
                    int read;
                    while ((read = await input.ReadAsync(buffer, token).ConfigureAwait(false)) != 0)
                    {
                        total += read;
                        if (total > file.Size) throw new InvalidDataException("runtime_download_oversized");
                        hash.AppendData(buffer, 0, read);
                        await output.WriteAsync(buffer.AsMemory(0, read), token).ConfigureAwait(false);
                        RuntimeUpdaterProgressReporting.Report(progress, new("Downloading", completedBytes + total,
                            totalBytes, files.Count, required.Length, file.InstallPath));
                    }
                    RuntimeUpdaterProgressReporting.Report(progress, new("Verifying", completedBytes + total,
                        totalBytes, files.Count, required.Length, file.InstallPath));
                    if (total != file.Size || !Same(Convert.ToHexString(hash.GetHashAndReset()), file.Sha256)) throw new InvalidDataException("runtime_download_hash_invalid");
                    output.Flush(true);
                }
                RuntimeUpdaterPaths.Guard(target);
                File.Move(temporary, target, true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
            if (file.InstallPath.EndsWith(".dll", StringComparison.Ordinal)) RuntimeUpdaterPaths.ValidatePeX64(target);
            files.Add(new(file.InstallPath, target, file.Size, file.Sha256));
            completedBytes += file.Size;
            RuntimeUpdaterProgressReporting.Report(progress, new("VerifiedFile", completedBytes, totalBytes,
                files.Count, required.Length, file.InstallPath));
        }
        return files;
    }

    private async Task<byte[]> GetAsync(RuntimeUpdaterInstallation installation, string relative, int maximum, CancellationToken token)
    {
        using var request = await RequestAsync(installation, HttpMethod.Get, relative, token).ConfigureAwait(false);
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
        return await ReadResponse(response, request.RequestUri!, maximum, token).ConfigureAwait(false);
    }

    private async Task<HttpRequestMessage> RequestAsync(RuntimeUpdaterInstallation installation, HttpMethod method, string relative,
        CancellationToken token)
    {
        RuntimeUpdaterInstallationStore.Validate(installation);
        var request = new HttpRequestMessage(method, new Uri(new Uri(installation.ApiOrigin), relative));
        if (installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.DesktopSession)
        {
            try
            {
                var bearer = desktopAccessToken is null ? null : await desktopAccessToken(token).ConfigureAwait(false);
                if (string.IsNullOrWhiteSpace(bearer) || bearer.Length > 16384 || bearer.Any(c => char.IsControl(c) || char.IsWhiteSpace(c)))
                    throw new InvalidOperationException("runtime_desktop_session_required");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            }
            catch { request.Dispose(); throw; }
        }
        else request.Headers.Authorization = new AuthenticationHeaderValue("DCGamingRuntime", installation.Credential);
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true, NoStore = true };
        return request;
    }

    private static string RouteRoot(RuntimeUpdaterInstallation installation)
        => installation.AuthenticationMode == RuntimeUpdaterAuthenticationModes.DesktopSession
            ? "api/desktop/runtime-updates" : "api/runtime-updates";

    private static void EnsureResponse(HttpResponseMessage response, Uri requested)
    {
        var actual = response.RequestMessage?.RequestUri ?? requested;
        if (actual.Scheme != requested.Scheme || actual.Host != requested.Host || actual.Port != requested.Port ||
            actual.AbsolutePath != requested.AbsolutePath || actual.Query != requested.Query)
            throw new InvalidDataException("runtime_download_redirect_rejected");
        if ((int)response.StatusCode is >= 300 and < 400) throw new InvalidDataException("runtime_download_redirect_rejected");
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentEncoding.Count > 0) throw new InvalidDataException("runtime_encoding_rejected");
    }

    private static async Task<byte[]> ReadResponse(HttpResponseMessage response, Uri requested, int maximum, CancellationToken token)
    {
        EnsureResponse(response, requested);
        if (response.Content.Headers.ContentLength is long length && length > maximum) throw new InvalidDataException("runtime_response_oversized");
        await using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
        using var memory = new MemoryStream();
        var buffer = new byte[16384];
        int read;
        while ((read = await stream.ReadAsync(buffer, token).ConfigureAwait(false)) != 0)
        {
            if (memory.Length + read > maximum) throw new InvalidDataException("runtime_response_oversized");
            memory.Write(buffer, 0, read);
        }
        return memory.ToArray();
    }

    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public void Dispose() { if (ownsClient) http.Dispose(); }
    private sealed record CredentialResponse(Guid InstallationId, string Token, DateTimeOffset ExpiresAtUtc, DateTimeOffset RenewAfterUtc);
}
