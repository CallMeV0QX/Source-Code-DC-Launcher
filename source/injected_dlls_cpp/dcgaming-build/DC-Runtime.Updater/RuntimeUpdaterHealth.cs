using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace DCGaming.RuntimeUpdater;

public sealed record RuntimeUpdaterSteamSession(int ProcessId, DateTimeOffset StartedAtUtc);
public enum RuntimeUpdaterHealthResult { Inconclusive, Healthy, CoreFailed, CloudFailed }

public static partial class RuntimeUpdaterHealth
{
    private const int MaximumLogSize = 1024 * 1024;

    public static RuntimeUpdaterLogBoundary Capture(string steamDirectory)
    {
        var path = LogPath(steamDirectory);
        var bytes = File.Exists(path) ? ReadLog(path) : [];
        var now = DateTimeOffset.UtcNow;
        now = new DateTimeOffset(now.Ticks - now.Ticks % TimeSpan.TicksPerMillisecond, TimeSpan.Zero);
        return new(now, bytes.LongLength, Convert.ToHexString(SHA256.HashData(bytes)));
    }

    public static RuntimeUpdaterSteamSession? FindSession(string steamDirectory)
    {
        Process[] processes = [];
        try
        {
            processes = Process.GetProcessesByName("steam");
            if (processes.Length != 1) return null;
            var process = processes[0];
            using var current = Process.GetCurrentProcess();
            var executable = process.MainModule?.FileName;
            if (process.HasExited || process.SessionId != current.SessionId || executable is null ||
                !string.Equals(Path.GetFullPath(executable), Path.Combine(Path.GetFullPath(steamDirectory), "steam.exe"), StringComparison.OrdinalIgnoreCase)) return null;
            RuntimeUpdaterPaths.Guard(executable);
            return new(process.Id, process.StartTime.ToUniversalTime());
        }
        catch { return null; }
        finally { foreach (var process in processes) process.Dispose(); }
    }

    public static RuntimeUpdaterHealthResult Inspect(string steamDirectory, RuntimeUpdaterLogBoundary boundary,
        RuntimeUpdaterSteamSession session, bool fullMode)
    {
        try
        {
            if (session.StartedAtUtc < boundary.CapturedAtUtc) return RuntimeUpdaterHealthResult.Inconclusive;
            var bytes = ReadLog(LogPath(steamDirectory));
            if (boundary.Length < 0 || boundary.Length > bytes.LongLength || boundary.Length > MaximumLogSize ||
                !string.Equals(Convert.ToHexString(SHA256.HashData(bytes.AsSpan(0, (int)boundary.Length))), boundary.PrefixSha256, StringComparison.Ordinal))
                return RuntimeUpdaterHealthResult.Inconclusive;
            var content = Encoding.UTF8.GetString(bytes.AsSpan((int)boundary.Length));
            return Parse(content, boundary, session, fullMode);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException)
        { return RuntimeUpdaterHealthResult.Inconclusive; }
    }

    public static RuntimeUpdaterHealthResult Parse(string content, RuntimeUpdaterLogBoundary boundary,
        RuntimeUpdaterSteamSession session, bool fullMode)
    {
        var begun = false;
        var complete = false;
        var cloudComplete = false;
        var coreFailed = false;
        var cloudFailed = false;
        foreach (var line in content.Split('\n'))
        {
            var match = StageLine().Match(line.Trim());
            if (!match.Success || !int.TryParse(match.Groups["pid"].Value, out var pid) || pid != session.ProcessId ||
                !DateTimeOffset.TryParseExact(match.Groups["time"].Value, "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var at) ||
                at < boundary.CapturedAtUtc || at < session.StartedAtUtc) continue;
            var stage = match.Groups["stage"].Value;
            if (stage == "runtime.init.begin") { begun = true; complete = false; cloudComplete = false; }
            if (stage is "proxy.load.failed" or "proxy.export.failed" || stage.StartsWith("runtime.exception", StringComparison.Ordinal)) coreFailed = true;
            if (!begun) continue;
            if (stage == "runtime.init.complete") complete = true;
            if (stage == "cloud.init.complete") cloudComplete = true;
            if (stage.StartsWith("cloud.", StringComparison.Ordinal)) cloudFailed |= stage.EndsWith(".failed", StringComparison.Ordinal) || stage == "cloud.file.missing";
            else coreFailed |= stage.EndsWith(".failed", StringComparison.Ordinal);
        }
        if (coreFailed) return RuntimeUpdaterHealthResult.CoreFailed;
        if (fullMode && cloudFailed) return RuntimeUpdaterHealthResult.CloudFailed;
        return begun && complete && (!fullMode || cloudComplete) ? RuntimeUpdaterHealthResult.Healthy : RuntimeUpdaterHealthResult.Inconclusive;
    }

    private static byte[] ReadLog(string path)
    {
        RuntimeUpdaterPaths.Guard(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > MaximumLogSize) throw new InvalidDataException("native_log_oversized");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        return bytes;
    }
    private static string LogPath(string steamDirectory)
    {
        var path = Path.Combine(steamDirectory, "opensteamtool", "nestg_startup.log");
        RuntimeUpdaterPaths.Guard(path);
        return path;
    }
    [GeneratedRegex(@"^(?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z) PID=(?<pid>\d+) TID=\d+ Stage=(?<stage>[a-z.]+) Error=\d+$", RegexOptions.CultureInvariant)]
    private static partial Regex StageLine();
}
