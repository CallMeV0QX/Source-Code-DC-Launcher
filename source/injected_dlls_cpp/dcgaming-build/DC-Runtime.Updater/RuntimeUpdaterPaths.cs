using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
using DCGaming.RuntimeUpdates;

namespace DCGaming.RuntimeUpdater;

public static class RuntimeUpdaterPaths
{
    public static bool IsHash(string? value) => value?.Length == 64 && value.All(Uri.IsHexDigit);

    public static void ValidateRuntimePath(string path, bool allowBootstrap = false)
    {
        if (!RuntimeUpdatePaths.IsPayloadPath(path) || !allowBootstrap && path is "dwmapi.dll" or "xinput1_4.dll")
            throw new InvalidDataException("runtime_path_not_updatable");
    }

    public static bool IsWithin(string candidate, string root)
    {
        var full = Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var parent = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return string.Equals(full, parent, StringComparison.OrdinalIgnoreCase) ||
            full.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    public static void Guard(string path)
    {
        var current = Path.GetFullPath(path);
        while (!string.IsNullOrEmpty(current))
        {
            var attributes = ExistingAttributes(current);
            if (attributes is not null && (attributes.Value & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("reparse_path_rejected");
            current = Path.GetDirectoryName(current);
        }
    }

    internal static FileAttributes? ExistingAttributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
        // Permission/IO failures never authorize treating a protected target as a new file.
    }

    internal static bool DirectoryExists(string path)
    {
        var attributes = ExistingAttributes(path);
        if (attributes is null) return false;
        if ((attributes.Value & FileAttributes.Directory) == 0) throw new InvalidDataException("runtime_directory_expected");
        return true;
    }

    public static string Target(string steamDirectory, string relativePath)
    {
        ValidateRuntimePath(relativePath);
        var path = Path.GetFullPath(Path.Combine(steamDirectory, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        if (!IsWithin(path, steamDirectory)) throw new InvalidDataException("runtime_path_escape");
        Guard(path);
        return path;
    }

    public static string? Hash(string path)
    {
        Guard(path);
        var attributes = ExistingAttributes(path);
        if (attributes is null) return null;
        if ((attributes.Value & FileAttributes.Directory) != 0) throw new InvalidDataException("runtime_file_expected");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        ValidateSingleLink(stream.SafeFileHandle);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    public static void WriteAtomic(string path, byte[] bytes)
    {
        Guard(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        Guard(path);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                64 * 1024, FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            Guard(path);
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public static void ValidatePeX64(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var reader = new BinaryReader(stream);
        if (stream.Length < 256 || reader.ReadUInt16() != 0x5A4D) throw new InvalidDataException("runtime_pe_invalid");
        stream.Position = 0x3C;
        var offset = reader.ReadInt32();
        if (offset < 0x40 || offset > stream.Length - 26) throw new InvalidDataException("runtime_pe_invalid");
        stream.Position = offset;
        if (reader.ReadUInt32() != 0x00004550 || reader.ReadUInt16() != 0x8664)
            throw new InvalidDataException("runtime_pe_x64_required");
        stream.Position = offset + 24;
        if (reader.ReadUInt16() != 0x20B) throw new InvalidDataException("runtime_pe_x64_required");
    }

    private static void ValidateSingleLink(SafeFileHandle handle)
    {
        if (!GetFileInformationByHandle(handle, out var info) || info.NumberOfLinks != 1)
            throw new InvalidDataException("runtime_file_alias_rejected");
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out ByHandleFileInformation information);
    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime, LastAccessTime, LastWriteTime;
        public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
    }
}
