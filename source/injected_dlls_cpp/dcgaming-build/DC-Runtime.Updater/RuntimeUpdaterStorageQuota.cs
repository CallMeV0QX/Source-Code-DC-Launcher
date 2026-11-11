namespace DCGaming.RuntimeUpdater;

internal static class RuntimeUpdaterStorageQuota
{
    private const long MaximumInstallationBytes = 4L * 1024 * 1024 * 1024;
    internal static void Check(string installationDirectory, long reservationBytes)
    {
        if (reservationBytes < 0 || reservationBytes > 1024L * 1024 * 1024) throw new InvalidDataException("runtime_reservation_invalid");
        var directories = new Stack<string>();
        directories.Push(installationDirectory);
        var count = 0;
        long total = reservationBytes;
        while (directories.TryPop(out var directory))
        {
            RuntimeUpdaterPaths.Guard(directory);
            if (!RuntimeUpdaterPaths.DirectoryExists(directory)) continue;
            foreach (var file in Directory.EnumerateFiles(directory))
            {
                RuntimeUpdaterPaths.Guard(file);
                if (++count > 16384) throw new InvalidDataException("runtime_storage_entry_limit");
                total = checked(total + new FileInfo(file).Length);
                if (total > MaximumInstallationBytes) throw new InvalidDataException("runtime_storage_quota_exceeded");
            }
            foreach (var child in Directory.EnumerateDirectories(directory))
            {
                if (++count > 16384) throw new InvalidDataException("runtime_storage_entry_limit");
                directories.Push(child);
            }
        }
        var drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(installationDirectory))!);
        if (drive.AvailableFreeSpace < reservationBytes + 16L * 1024 * 1024)
            throw new IOException("runtime_storage_space_insufficient");
    }
}
