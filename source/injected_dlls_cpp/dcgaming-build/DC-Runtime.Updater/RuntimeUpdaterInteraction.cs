namespace DCGaming.RuntimeUpdater;

public static class RuntimeUpdaterAuthenticationModes
{
    public const string InstallationCredential = "InstallationCredential";
    public const string DesktopSession = "DesktopSession";
}

public sealed record RuntimeUpdaterProgress(string Stage, long BytesReceived = 0, long TotalBytes = 0,
    int CompletedFiles = 0, int TotalFiles = 0, string? FileName = null, string? Version = null)
{
    public int? Percentage => TotalBytes > 0 ? (int)Math.Clamp(BytesReceived * 100d / TotalBytes, 0, 100) : null;
}

/// <summary>ShutdownRequested identifies the current operation's own graceful request, not an observed natural exit.</summary>
public sealed record RuntimeUpdaterSteamClosure(bool IsClosed, bool ShutdownRequested);

public sealed record RuntimeUpdaterPendingUpdate(string ReleaseId, long Sequence, string Phase,
    bool RestartAfterCommit = false, bool RestartAttempted = false);

/// <summary>The launcher supplies UI/process policy; the standalone helper retains natural-exit behavior by default.</summary>
public sealed class RuntimeUpdaterInteraction
{
    public Func<CancellationToken, Task<RuntimeUpdaterSteamClosure>>? CloseSteamAsync { get; init; }
    public Func<CancellationToken, Task<bool>>? ReopenSteamAsync { get; init; }
    public IProgress<RuntimeUpdaterProgress>? Progress { get; init; }
    public Func<DateTimeOffset> UtcNow { get; init; } = () => DateTimeOffset.UtcNow;
    public Func<TimeSpan, CancellationToken, Task> DelayAsync { get; init; } = Task.Delay;
    public TimeSpan SteamExitWaitTimeout { get; init; } = TimeSpan.FromHours(12);
}

internal static class RuntimeUpdaterProgressReporting
{
    internal static void Report(IProgress<RuntimeUpdaterProgress>? progress, RuntimeUpdaterProgress update)
    {
        try { progress?.Report(update); }
        catch { /* Renderer shutdown cannot change verification or committed installation outcomes. */ }
    }
}
