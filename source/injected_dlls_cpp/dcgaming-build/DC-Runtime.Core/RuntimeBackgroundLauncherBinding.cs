using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DCGaming.RuntimeUpdates;

public sealed record RuntimeBackgroundLauncherFile
{
    public string RelativePath { get; init; } = "";
    public long Size { get; init; }
    public string Sha256 { get; init; } = "";
}

public sealed record RuntimeBackgroundLauncherManifest
{
    public int SchemaVersion { get; init; } = 1;
    public string Purpose { get; init; } = RuntimeBackgroundLauncherBinding.ManifestPurpose;
    public int ProtocolVersion { get; init; } = 1;
    public string Version { get; init; } = "";
    public string Executable { get; init; } = "";
    public List<RuntimeBackgroundLauncherFile> Files { get; init; } = [];
}

public sealed record RuntimeBackgroundLauncherRegistration
{
    public int SchemaVersion { get; init; } = 1;
    public string SteamRoot { get; init; } = "";
    public string ExecutablePath { get; init; } = "";
    public string ApiOrigin { get; init; } = "";
    public string SignedManifestJson { get; init; } = "";
}

/// <summary>Owns immutable code-file handles while a verified launcher host executes.</summary>
public sealed class RuntimeBackgroundLauncherLease : IDisposable
{
    private readonly IReadOnlyList<FileStream> files;
    internal RuntimeBackgroundLauncherLease(RuntimeBackgroundLauncherRegistration registration,
        RuntimeBackgroundLauncherManifest manifest, IReadOnlyList<FileStream> files)
    {
        Registration = registration;
        Manifest = manifest;
        this.files = files;
        StartInfo = new ProcessStartInfo
        {
            FileName = ExecutablePath,
            WorkingDirectory = Path.GetDirectoryName(ExecutablePath)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        StartInfo.ArgumentList.Add("--runtime-update");
        StartInfo.ArgumentList.Add("--steam-root");
        StartInfo.ArgumentList.Add(SteamRoot);
    }
    public RuntimeBackgroundLauncherRegistration Registration { get; }
    public RuntimeBackgroundLauncherManifest Manifest { get; }
    public string SteamRoot => Registration.SteamRoot;
    public string ApiOrigin => Registration.ApiOrigin;
    public string ExecutablePath => Registration.ExecutablePath;
    public ProcessStartInfo StartInfo { get; }
    public void Dispose() { foreach (var file in files) file.Dispose(); }
}

/// <summary>
/// A stable, hash-pinned dispatcher accepts launcher versions only through this
/// independently signed code inventory. The per-user DPAPI locator contains no credential.
/// </summary>
public static class RuntimeBackgroundLauncherBinding
{
    public const string LauncherManifestFileName = "launcher-background-host.json";
    public const string ManifestPurpose = "DCGaming.RuntimeBackgroundLauncher.v1";
    public const int MaximumManifestBytes = 512 * 1024;
    public const long MaximumFileBytes = 512L * 1024 * 1024;
    private const int MaximumBindingBytes = 1024 * 1024;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("DCGaming.RuntimeBackgroundLauncher.Binding.v1");

    public static RuntimeBackgroundLauncherManifest VerifyManifest(string signedManifestJson,
        IReadOnlyDictionary<string, string>? trustedKeys = null)
    {
        try
        {
            var bytes = Encoding.UTF8.GetBytes(signedManifestJson);
            if (bytes.Length is 0 or > MaximumManifestBytes) throw Invalid();
            var envelope = RuntimeReleaseTrust.ReadEnvelope(bytes);
            if (!(trustedKeys ?? RuntimeReleaseKeys.PublicKeys).TryGetValue(envelope.KeyId, out var spki)) throw Invalid();
            var payload = Convert.FromBase64String(envelope.Payload);
            var signature = Convert.FromBase64String(envelope.Signature);
            using var rsa = RSA.Create();
            var publicBytes = Convert.FromBase64String(spki);
            rsa.ImportSubjectPublicKeyInfo(publicBytes, out var read);
            if (rsa.KeySize < 3072 || read != publicBytes.Length ||
                !rsa.VerifyData(payload, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pss)) throw Invalid();
            using (var document = JsonDocument.Parse(payload)) RuntimeReleaseVerifier.RejectDuplicateProperties(document.RootElement);
            var manifest = JsonSerializer.Deserialize<RuntimeBackgroundLauncherManifest>(payload, RuntimeUpdateJson.Options) ?? throw Invalid();
            ValidateManifest(manifest);
            return manifest;
        }
        catch (Exception error) when (error is FormatException or JsonException or CryptographicException or ArgumentException)
        { throw Invalid(); }
    }

    public static void ValidateManifest(RuntimeBackgroundLauncherManifest manifest)
    {
        if (manifest.SchemaVersion != 1 || manifest.Purpose != ManifestPurpose || manifest.ProtocolVersion != 1 ||
            !Version.TryParse(manifest.Version, out _) || !IsSafeRelativePath(manifest.Executable) ||
            manifest.Executable.Contains('/') || !manifest.Executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            manifest.Files is null || manifest.Files.Count is < 1 or > 2048) throw Invalid();
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        long total = 0;
        foreach (var file in manifest.Files)
        {
            if (file is null || !IsSafeRelativePath(file.RelativePath) ||
                file.RelativePath.Equals(LauncherManifestFileName, StringComparison.OrdinalIgnoreCase) ||
                !paths.Add(file.RelativePath) || file.Size is <= 0 or > MaximumFileBytes ||
                !RuntimeUpdatePaths.IsHash(file.Sha256)) throw Invalid();
            total = checked(total + file.Size);
        }
        if (total > 2L * 1024 * 1024 * 1024 || !paths.Contains(manifest.Executable)) throw Invalid();
    }

    public static void Register(string steamRoot, string launcherExecutablePath, string apiOrigin,
        string signedManifestJson, string? bindingDirectory = null, IReadOnlyDictionary<string, string>? trustedKeys = null)
    {
        var registration = new RuntimeBackgroundLauncherRegistration
        {
            SteamRoot = CanonicalLocalPath(steamRoot),
            ExecutablePath = CanonicalLocalPath(launcherExecutablePath),
            ApiOrigin = CanonicalOrigin(apiOrigin), SignedManifestJson = signedManifestJson
        };
        using var lease = VerifyFiles(registration, trustedKeys);
        var plain = JsonSerializer.SerializeToUtf8Bytes(registration, RuntimeUpdateJson.Options);
        try
        {
            var cipher = Protect(plain, protect: true);
            WriteAtomic(BindingPath(steamRoot, bindingDirectory), cipher);
        }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }

    public static RuntimeBackgroundLauncherRegistration? ReadVerified(string steamRoot,
        string? bindingDirectory = null, IReadOnlyDictionary<string, string>? trustedKeys = null)
    {
        using var lease = Acquire(steamRoot, bindingDirectory, trustedKeys);
        return lease?.Registration;
    }

    public static bool TryAcquire(string steamRoot, out RuntimeBackgroundLauncherLease? lease,
        string? bindingDirectory = null, IReadOnlyDictionary<string, string>? trustedKeys = null)
    {
        try { lease = Acquire(steamRoot, bindingDirectory, trustedKeys); return lease is not null; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException or
            CryptographicException or JsonException or ArgumentException or PlatformNotSupportedException)
        { lease = null; return false; }
    }

    public static string BindingPath(string steamRoot, string? bindingDirectory = null)
    {
        var canonical = CanonicalLocalPath(steamRoot);
        var binding = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical.ToUpperInvariant())));
        var directory = bindingDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DCGamingLauncher", "RuntimeUpdates", "LauncherBindings");
        return Path.Combine(CanonicalLocalPath(directory), binding + ".dat");
    }

    private static RuntimeBackgroundLauncherLease? Acquire(string steamRoot, string? bindingDirectory,
        IReadOnlyDictionary<string, string>? trustedKeys)
    {
        var root = CanonicalLocalPath(steamRoot);
        var path = BindingPath(root, bindingDirectory);
        if (!File.Exists(path)) return null;
        var cipher = ReadBounded(path, MaximumBindingBytes);
        var plain = Protect(cipher, protect: false);
        try
        {
            if (plain.Length > MaximumBindingBytes) throw Invalid();
            using (var document = JsonDocument.Parse(plain)) RuntimeReleaseVerifier.RejectDuplicateProperties(document.RootElement);
            var registration = JsonSerializer.Deserialize<RuntimeBackgroundLauncherRegistration>(plain, RuntimeUpdateJson.Options) ?? throw Invalid();
            if (registration.SchemaVersion != 1 || !string.Equals(registration.SteamRoot, root, StringComparison.OrdinalIgnoreCase) ||
                registration.ExecutablePath != CanonicalLocalPath(registration.ExecutablePath) ||
                registration.ApiOrigin != CanonicalOrigin(registration.ApiOrigin)) throw Invalid();
            return VerifyFiles(registration, trustedKeys);
        }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }

    private static RuntimeBackgroundLauncherLease VerifyFiles(RuntimeBackgroundLauncherRegistration registration,
        IReadOnlyDictionary<string, string>? trustedKeys)
    {
        var manifest = VerifyManifest(registration.SignedManifestJson, trustedKeys);
        if (!Path.GetFileName(registration.ExecutablePath).Equals(manifest.Executable, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        var root = Path.GetDirectoryName(registration.ExecutablePath)!;
        var expected = manifest.Files.Select(file => file.RelativePath).ToHashSet(StringComparer.OrdinalIgnoreCase);
        RejectUnlistedCode(root, expected);
        var opened = new List<FileStream>();
        try
        {
            foreach (var file in manifest.Files)
            {
                var path = Resolve(root, file.RelativePath);
                var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                opened.Add(stream);
                if (stream.Length != file.Size || !Convert.ToHexString(SHA256.HashData(stream)).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                if (path.Equals(registration.ExecutablePath, StringComparison.OrdinalIgnoreCase)) ValidatePeX64(stream);
            }
            RejectUnlistedCode(root, expected);
            return new(registration, manifest, opened);
        }
        catch { foreach (var file in opened) file.Dispose(); throw; }
    }

    private static void RejectUnlistedCode(string root, HashSet<string> expected)
    {
        var pending = new Queue<string>(); pending.Enqueue(root);
        var count = 0;
        while (pending.TryDequeue(out var directory))
        {
            CanonicalLocalPath(directory);
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                if (++count > 8192) throw Invalid();
                CanonicalLocalPath(entry);
                if (Directory.Exists(entry)) { pending.Enqueue(entry); continue; }
                var relative = Path.GetRelativePath(root, entry).Replace('\\', '/');
                if ((relative.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || relative.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                    relative.EndsWith(".deps.json", StringComparison.OrdinalIgnoreCase) || relative.EndsWith(".runtimeconfig.json", StringComparison.OrdinalIgnoreCase)) &&
                    !expected.Contains(relative)) throw Invalid();
            }
        }
    }

    public static bool IsSafeRelativePath(string? path)
    {
        if (path is null || path.Length is < 1 or > 512 || path.Contains('\\') || path.StartsWith('/')) return false;
        return path.Split('/').All(part => part.Length is >= 1 and <= 255 && part is not ("." or "..") &&
            !part.Any(c => char.IsControl(c) || ":*?\"<>|".Contains(c)) && !char.IsWhiteSpace(part[^1]) && part[^1] != '.' &&
            !System.Text.RegularExpressions.Regex.IsMatch(part, "\\A(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\\.|\\z)", System.Text.RegularExpressions.RegexOptions.IgnoreCase));
    }

    public static string Resolve(string root, string relative)
    {
        if (!IsSafeRelativePath(relative)) throw Invalid();
        var canonicalRoot = CanonicalLocalPath(root);
        var path = CanonicalLocalPath(Path.Combine(canonicalRoot, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!path.StartsWith(canonicalRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        return path;
    }

    private static string CanonicalLocalPath(string path)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Launcher binding requires Windows.");
        if (string.IsNullOrWhiteSpace(path) || path.Length is < 3 or > 32700 || !char.IsAsciiLetter(path[0]) || path[1] != ':' || path[2] is not ('\\' or '/') ||
            path[2..].Contains(':') || path.Any(char.IsControl) || path.Contains('"')) throw Invalid();
        var canonical = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        RuntimeUpdatePaths.Guard(canonical);
        return canonical;
    }

    private static string CanonicalOrigin(string origin)
    {
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0 || uri.AbsolutePath != "/") throw Invalid();
        return uri.GetLeftPart(UriPartial.Authority) + "/";
    }

    private static void ValidatePeX64(FileStream file)
    {
        if (file.Length < 128) throw Invalid();
        Span<byte> header = stackalloc byte[64]; file.Position = 0; file.ReadExactly(header);
        if (BitConverter.ToUInt16(header) != 0x5a4d) throw Invalid();
        var offset = BitConverter.ToInt32(header[60..]);
        if (offset < 64 || offset > file.Length - 26) throw Invalid();
        file.Position = offset; Span<byte> pe = stackalloc byte[26]; file.ReadExactly(pe);
        if (BitConverter.ToUInt32(pe) != 0x4550 || BitConverter.ToUInt16(pe[4..]) != 0x8664 || BitConverter.ToUInt16(pe[24..]) != 0x20b) throw Invalid();
    }

    private static byte[] ReadBounded(string path, int maximum)
    {
        RuntimeUpdatePaths.Guard(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 || stream.Length > maximum) throw Invalid();
        var bytes = new byte[checked((int)stream.Length)]; stream.ReadExactly(bytes); return bytes;
    }

    private static void WriteAtomic(string path, byte[] bytes)
    {
        RuntimeUpdatePaths.Guard(path); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            RuntimeUpdatePaths.Guard(path); File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static byte[] Protect(byte[] input, bool protect)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Launcher binding requires Windows DPAPI.");
        var inputMemory = Marshal.AllocHGlobal(input.Length); var entropyMemory = Marshal.AllocHGlobal(Entropy.Length);
        DataBlob output = default;
        try
        {
            Marshal.Copy(input, 0, inputMemory, input.Length); Marshal.Copy(Entropy, 0, entropyMemory, Entropy.Length);
            var source = new DataBlob { Length = input.Length, Data = inputMemory };
            var entropy = new DataBlob { Length = Entropy.Length, Data = entropyMemory };
            var success = protect ? CryptProtectData(ref source, null, ref entropy, IntPtr.Zero, IntPtr.Zero, 1, out output)
                : CryptUnprotectData(ref source, IntPtr.Zero, ref entropy, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!success || output.Length is <= 0 or > MaximumBindingBytes) throw new CryptographicException("Launcher binding protection failed.");
            var result = new byte[output.Length]; Marshal.Copy(output.Data, result, 0, result.Length); return result;
        }
        finally
        {
            Marshal.FreeHGlobal(inputMemory); Marshal.FreeHGlobal(entropyMemory);
            if (output.Data != IntPtr.Zero) LocalFree(output.Data);
        }
    }

    private static InvalidDataException Invalid() => new("runtime_launcher_binding_invalid");
    [StructLayout(LayoutKind.Sequential)] private struct DataBlob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(ref DataBlob input, string? description, ref DataBlob entropy,
        IntPtr reserved, IntPtr prompt, uint flags, out DataBlob output);
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(ref DataBlob input, IntPtr description, ref DataBlob entropy,
        IntPtr reserved, IntPtr prompt, uint flags, out DataBlob output);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
}
