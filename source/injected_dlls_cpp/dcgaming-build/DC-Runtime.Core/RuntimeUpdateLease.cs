namespace DCGaming.RuntimeUpdates;

public static class RuntimeUpdateLease
{
    // Same user/session gate as all launcher mutations. An OS file lease is released after a crash.
    private static string GatePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DCGamingLauncher", "RuntimeUpdates", "operation.lock");
    public static IDisposable? TryAcquire(string steamRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(steamRoot);
        RuntimeUpdatePaths.Guard(steamRoot);
        var path = GatePath;
        RuntimeUpdatePaths.Guard(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { return null; }
    }
    public static async Task<IDisposable> AcquireAsync(string steamRoot, CancellationToken cancellationToken = default)
    {
        var deadline = DateTime.UtcNow.AddMinutes(3);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (TryAcquire(steamRoot) is { } lease) return lease;
            if (DateTime.UtcNow >= deadline) throw new TimeoutException("Another runtime operation is still active.");
            await Task.Delay(200, cancellationToken).ConfigureAwait(false);
        }
    }
}
