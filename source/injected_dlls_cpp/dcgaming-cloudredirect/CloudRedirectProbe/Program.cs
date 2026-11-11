using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// Runs the real, unmodified DLL in a disposable non-Steam process. Profile-folder
// imports are redirected in this process before CR_InitCloudSave can touch them.
internal static class Program
{
    private const uint Account = 424242;
    private const uint App = 424242;
    private const string SaveName = "dc-runtime-probe/save.dat";
    private static readonly byte[] Save = Encoding.UTF8.GetBytes("DCGaming CloudRedirect native round trip\n\u0111\u1ed3ng b\u1ed9 save\n");
    private static readonly List<string> Checks = [];
    private static readonly ConcurrentBag<string> KnownFolderCalls = [];
    private static readonly ConcurrentBag<string> OutboundAttempts = [];
    private static readonly List<Delegate> PinnedCallbacks = [];
    private static string _client = "";
    private static string _roaming = "";
    private static string _steam = "";
    private static string _provider = "";

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool Init([MarshalAs(UnmanagedType.LPUTF8Str)] string path, Notify notify);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Notify(int level, IntPtr title, IntPtr message);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool Handle([MarshalAs(UnmanagedType.LPUTF8Str)] string method, uint app, uint account,
        IntPtr body, uint length, IntPtr response, uint maximum, out uint responseLength, out int result);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void SetApps(IntPtr apps, uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void SetAccount(uint account);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] private delegate bool IsApp(uint app);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void VoidCall();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] private delegate bool BoolCall();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void StatsEnable(
        [MarshalAs(UnmanagedType.I1)] bool achievements, [MarshalAs(UnmanagedType.I1)] bool playtime);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Running(uint app, [MarshalAs(UnmanagedType.I1)] bool running);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Stored(uint app);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int KnownFolder(ref Guid id, uint flags, IntPtr token, out IntPtr path);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate IntPtr HttpConnect(IntPtr session,
        [MarshalAs(UnmanagedType.LPWStr)] string host, ushort port, uint reserved);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int RegOpen(IntPtr key, IntPtr name, uint options, uint access, out IntPtr result);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool VirtualProtect(IntPtr address, nuint size, uint protection, out uint previous);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] private static extern void SetLastError(uint error);

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length != 4 || !new[] { "writer", "recover", "reader" }.Contains(args[2]))
                throw new ArgumentException("Usage: CloudRedirectProbe <dll> <test-root> <writer|recover|reader> <provider-root>");
            var dll = Path.GetFullPath(args[0]);
            var root = Path.GetFullPath(args[1]);
            _provider = Path.GetFullPath(args[3]);
            RequireInside(root, dll);
            RequireInside(root, _provider);
            _client = Path.Combine(root, args[2] == "reader" ? "reader" : "writer");
            _steam = Path.Combine(_client, "steam");
            _roaming = Path.Combine(_client, "Roaming");
            foreach (var folder in new[] { _steam, _roaming, _provider, Path.Combine(_client, "Local"), Path.Combine(_client, "Profile"), Path.Combine(_client, "Temp") })
                Directory.CreateDirectory(folder);
            foreach (var pair in new Dictionary<string, string>
            {
                ["APPDATA"] = _roaming, ["LOCALAPPDATA"] = Path.Combine(_client, "Local"),
                ["USERPROFILE"] = Path.Combine(_client, "Profile"), ["TEMP"] = Path.Combine(_client, "Temp"),
                ["TMP"] = Path.Combine(_client, "Temp"), ["HOME"] = Path.Combine(_client, "Profile"),
            }) Environment.SetEnvironmentVariable(pair.Key, pair.Value);
            Environment.CurrentDirectory = _steam;
            Check(GetModuleHandle("steamclient64.dll") == IntPtr.Zero && GetModuleHandle("steamui.dll") == IntPtr.Zero,
                "Probe process has no Steam modules");
            Directory.CreateDirectory(Path.Combine(_steam, "cloud_redirect"));
            Directory.CreateDirectory(Path.Combine(_roaming, "CloudRedirect"));
            var config = JsonSerializer.Serialize(new
            {
                provider = "folder", sync_path = _provider, auto_update_dll = false,
                sync_achievements = false, sync_playtime = false, sync_luas = false,
                parental_bypass_playtime = false, parental_ignore_playtime = false,
            });
            File.WriteAllText(Path.Combine(_roaming, "CloudRedirect", "config.json"), config);
            File.WriteAllText(Path.Combine(_steam, "cloud_redirect", "config.json"), config);
            ValidatePe(dll);
            var module = NativeLibrary.Load(dll);
            // The only DllMain action is recording/pinning its own module. Do not
            // call any entry point until all folder/network/registry guards exist.
            GuardImports(module);
            var required = new[] { "CR_InitCloudSave", "CR_HandleCloudRpc", "CR_SetApps", "CR_IsApp", "CR_Shutdown",
                "CR_SetAccountId", "CR_EnableStatsSync", "CR_NotifyAppRunning", "CR_NotifyStatsStored", "CR_GetAchievements", "CR_InstallVtableHooks" };
            foreach (var name in required) Check(NativeLibrary.TryGetExport(module, name, out _), "Export " + name);
            var init = Export<Init>(module, "CR_InitCloudSave");
            var handle = Export<Handle>(module, "CR_HandleCloudRpc");
            var setApps = Export<SetApps>(module, "CR_SetApps");
            var isApp = Export<IsApp>(module, "CR_IsApp");
            var shutdown = Export<VoidCall>(module, "CR_Shutdown");
            Notify notify = (level, _, _) => { if (level == 2) OutboundAttempts.Add("unexpected error notification"); };
            PinnedCallbacks.Add(notify);
            Check(!init(null!, notify), "Null init path rejected");
            Check(init(_steam + Path.DirectorySeparatorChar, notify), "Third-party CR_InitCloudSave succeeds");
            try
            {
                Check(KnownFolderCalls.Count >= 4, "Known-folder calls routed inside fixture");
                var legacyJunction = Path.Combine(_client, "KnownFolders", "fdd39ad0238f46afadb46c85480369c7", ".cloudredirect");
                Check(!Directory.Exists(legacyJunction), "Legacy cleanup unlinks fixture junction instead of following it");
                foreach (var legacyName in new[] { "Playtime.bin", "UserGameStats.bin" })
                    Check(File.ReadAllText(Path.Combine(_client, "junction-target", legacyName)) == "junction target must survive",
                        "Junction target preserved: " + legacyName);
                var appPointer = Marshal.AllocHGlobal(sizeof(uint));
                try { Marshal.WriteInt32(appPointer, unchecked((int)App)); setApps(appPointer, 1); }
                finally { Marshal.FreeHGlobal(appPointer); }
                Check(isApp(App) && !isApp(App + 1), "Namespace registration excludes other apps");
                Check(!Export<BoolCall>(module, "CR_InstallVtableHooks")(), "Hook installation safely declines outside Steam");
                Export<SetAccount>(module, "CR_SetAccountId")(Account);
                Export<StatsEnable>(module, "CR_EnableStatsSync")(true, true);
                Check(!Rpc(handle, "Player.GetUserStats#1", [], false).Handled, "Disabled achievement config survives host enabling API");
                Check(!Rpc(handle, "Player.ClientGetLastPlayedTimes#1", [], false).Handled, "Disabled playtime config survives host enabling API");
                Export<Running>(module, "CR_NotifyAppRunning")(App, true);
                Export<Running>(module, "CR_NotifyAppRunning")(App, false);
                Export<Stored>(module, "CR_NotifyStatsStored")(App);
                Check(!Rpc(handle, "Cloud.UnknownProbeMethod#1", [], false).Handled, "Unknown RPC chains to host");
                if (args[2] == "writer") WriteAndInterrupt(handle);
                else if (args[2] == "reader") ReadFromOtherClient(handle);
                else RecoverInterrupted(handle);
                setApps(IntPtr.Zero, 0);
                Check(!isApp(App), "Namespace clear works");
            }
            finally { shutdown(); }
            var log = ReadLog();
            Check(log.Contains("CR_InitCloudSave complete"), "Launcher initialization log marker retained");
            Check(log.Contains("[CR_API] SetApps: 1 app(s)"), "Launcher app-registration log marker retained");
            Check(log.Contains("StatsSync API active (config: achievements=0 playtime=0)"), "Actual native sync flags remain disabled");
            Check(!log.Contains($"App {App} session started") && !log.Contains($"Stats captured for app {App}"), "Disabled stats notifications do not start sessions/capture");
            Check(log.Contains("CloudIntercept shutdown complete"), "Native shutdown completes");
            Check(OutboundAttempts.IsEmpty, "No outbound WinHTTP connections or unexpected errors");
            var result = new { phase = args[2], passed = Checks.Count, checks = Checks,
                dllSha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))),
                knownFolderCalls = KnownFolderCalls.Count, outboundAttempts = OutboundAttempts.Count };
            File.WriteAllText(Path.Combine(root, $"probe-{args[2]}.json"), JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine(JsonSerializer.Serialize(result));
            GC.KeepAlive(PinnedCallbacks);
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static void WriteAndInterrupt(Handle handle)
    {
        var first = Begin(handle);
        Upload(handle, Save);
        Rpc(handle, "Cloud.CompleteAppUploadBatchBlocking#1", Message((1, App), (2, first), (3, 1)));
        WaitFor(() => System.Text.RegularExpressions.Regex.IsMatch(ReadLog(), @"publish \d+/\d+ succeeded"), "Successful folder-provider publish", 20000);
        Check(Directory.EnumerateFiles(_provider, "*", SearchOption.AllDirectories).Any(p => File.ReadAllBytes(p).SequenceEqual(Save)), "Provider contains exact published save bytes");
        var second = Begin(handle);
        var newer = Encoding.UTF8.GetBytes("New local progress whose upload was interrupted");
        File.WriteAllBytes(Path.Combine(_client, "local-game-save.dat"), newer);
        Upload(handle, newer);
        Rpc(handle, "Cloud.CompleteAppUploadBatchBlocking#1", Message((1, App), (2, second), (3, 2)));
        Check(File.ReadAllBytes(Path.Combine(_client, "local-game-save.dat")).SequenceEqual(newer), "Interrupted batch leaves synthetic local game progress intact");
        Check(Directory.EnumerateFiles(_provider, "*", SearchOption.AllDirectories).Any(p => File.ReadAllBytes(p).SequenceEqual(Save)), "Failed batch preserves previously published provider save");
    }

    private static void RecoverInterrupted(Handle handle)
    {
        var local = File.ReadAllBytes(Path.Combine(_client, "local-game-save.dat"));
        var response = Rpc(handle, "Cloud.GetAppFileChangelist#1", Message((1, App), (2, 1)));
        var fields = Parse(response.Data);
        Check(Number(fields, 3) == 1 && !fields.Any(f => f.Number == 2), "Restart after interrupted upload returns protective empty delta");
        Check(File.ReadAllBytes(Path.Combine(_client, "local-game-save.dat")).SequenceEqual(local), "Recovery does not replace local game progress");
        var log = ReadLog();
        Check(log.Contains("interrupted upload (cloudCN="), "New interrupted-upload guard is exercised in actual DLL");
    }

    private static void ReadFromOtherClient(Handle handle)
    {
        var response = Rpc(handle, "Cloud.GetAppFileChangelist#1", Message((1, App), (2, 0)));
        var fields = Parse(response.Data);
        Check(fields.Any(f => f.Number == 2), "Fresh client receives cloud save inventory");
        var currentChangeNumber = Number(fields, 1);
        var repeated = Parse(Rpc(handle, "Cloud.GetAppFileChangelist#1", Message((1, App), (2, currentChangeNumber))).Data);
        Check(Number(repeated, 1) == currentChangeNumber && Number(repeated, 3) == 0 && repeated.Any(f => f.Number == 2),
            "Same-CN repeat sync returns authoritative inventory for newer Steam clients");
        var download = Parse(Rpc(handle, "Cloud.ClientFileDownload#1", Message((1, App), (2, SaveName))).Data);
        var url = Loopback(Text(download, 7), Text(download, 8));
        using var client = HttpClient();
        var bytes = client.GetByteArrayAsync(url).GetAwaiter().GetResult();
        Check(bytes.SequenceEqual(Save), "Fresh client downloads exact published save via RPC and HTTP");
        Check(Number(download, 2) == (ulong)Save.Length, "Download metadata matches published size");
        Check(Find(download, 4).Bytes.SequenceEqual(SHA1.HashData(Save)), "Download metadata matches published SHA1");
    }

    private static ulong Begin(Handle handle)
    {
        var response = Parse(Rpc(handle, "Cloud.BeginAppUploadBatch#1", Message((1, App), (3, SaveName))).Data);
        var batch = Number(response, 1);
        Check(batch != 0, "Upload batch assigned native ID");
        return batch;
    }

    private static void Upload(Handle handle, byte[] data)
    {
        var request = Message((1, App), (2, (ulong)data.Length), (3, (ulong)data.Length), (4, SHA1.HashData(data)),
            (5, (ulong)DateTimeOffset.UtcNow.ToUnixTimeSeconds()), (6, SaveName));
        var begin = Parse(Rpc(handle, "Cloud.ClientBeginFileUpload#1", request).Data);
        var block = Parse(Find(begin, 2).Bytes);
        var url = Loopback(Text(block, 1), Text(block, 2));
        Check(Number(block, 4) == 4 && Number(block, 3) == 0, "Native upload block uses local HTTP PUT");
        using var client = HttpClient();
        using var content = new ByteArrayContent(data);
        using var response = client.PutAsync(url, content).GetAwaiter().GetResult();
        Check(response.IsSuccessStatusCode, "Actual native HTTP server accepts save bytes");
        var commit = Parse(Rpc(handle, "Cloud.ClientCommitFileUpload#1", Message((1, 1), (2, App), (4, SaveName))).Data);
        Check(Number(commit, 1) == 1, "Native commit validates uploaded blob");
    }

    private static Uri Loopback(string host, string path)
    {
        var uri = new Uri("http://" + host + path);
        if (uri.Host != "127.0.0.1" || uri.Port <= 0 || uri.UserInfo.Length > 0) throw new InvalidDataException("RPC escaped loopback");
        return uri;
    }
    private static HttpClient HttpClient() => new(new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false, ConnectTimeout = TimeSpan.FromSeconds(3) }) { Timeout = TimeSpan.FromSeconds(10) };
    private static string ReadLog()
    {
        using var stream = new FileStream(Path.Combine(_steam, "cloud_redirect.log"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }
    private static void WaitFor(Func<bool> condition, string name, int timeout)
    {
        var end = Environment.TickCount64 + timeout;
        while (Environment.TickCount64 < end) { if (condition()) { Check(true, name); return; } Thread.Sleep(100); }
        throw new TimeoutException(name);
    }
    private static T Export<T>(IntPtr module, string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(module, name));
    private static void Check(bool condition, string name) { if (!condition) throw new InvalidDataException(name); Checks.Add(name); }
    private static void RequireInside(string root, string path)
    {
        if (!Path.GetFullPath(path).StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Fixture path escaped its test root");
        for (var p = Path.GetFullPath(path); !string.IsNullOrEmpty(p); p = Path.GetDirectoryName(p))
            if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Fixture reparse points are not allowed");
    }
    private static void ValidatePe(string dll)
    {
        var b = File.ReadAllBytes(dll);
        var pe = BitConverter.ToInt32(b, 0x3c);
        Check(BitConverter.ToUInt16(b, 0) == 0x5a4d && BitConverter.ToUInt32(b, pe) == 0x4550 &&
            BitConverter.ToUInt16(b, pe + 4) == 0x8664 && BitConverter.ToUInt16(b, pe + 24) == 0x20b, "DLL is PE Windows x64");
    }
    private static void GuardImports(IntPtr module)
    {
        KnownFolder known = (ref Guid id, uint _, IntPtr _, out IntPtr value) =>
        {
            var path = id == new Guid("3eb685db-65f9-4cf6-a03a-e3ef65729f3d") ? _roaming : Path.Combine(_client, "KnownFolders", id.ToString("N"));
            Directory.CreateDirectory(path);
            KnownFolderCalls.Add(path);
            value = Marshal.StringToCoTaskMemUni(path);
            return 0;
        };
        HttpConnect deny = (_, host, _, _) => { OutboundAttempts.Add(host); SetLastError(12005); return IntPtr.Zero; };
        RegOpen registry = (IntPtr _, IntPtr _, uint _, uint _, out IntPtr result) => { result = IntPtr.Zero; return 2; };
        Check(PatchImport(module, "SHGetKnownFolderPath", known) > 0, "Known-folder isolation installed before native init");
        Check(PatchImport(module, "WinHttpConnect", deny) > 0, "Outbound WinHTTP deny installed before native init");
        PatchImport(module, "RegOpenKeyExA", registry);
        PatchImport(module, "RegOpenKeyExW", registry);
    }
    private static int PatchImport(IntPtr module, string name, Delegate replacement)
    {
        PinnedCallbacks.Add(replacement);
        var pe = Marshal.ReadInt32(module + 0x3c);
        var importRva = Marshal.ReadInt32(module + pe + 24 + 120);
        if (importRva <= 0) throw new InvalidDataException("DLL imports are absent");
        var count = 0;
        for (var d = module + importRva; Marshal.ReadInt32(d + 12) != 0; d += 20)
        {
            var original = Marshal.ReadInt32(d);
            var first = Marshal.ReadInt32(d + 16);
            if (original == 0) throw new InvalidDataException("Named import information absent");
            for (var i = 0; ; i++)
            {
                var thunk = unchecked((ulong)Marshal.ReadInt64(module + original + i * 8));
                if (thunk == 0) break;
                if ((thunk & (1ul << 63)) != 0) continue;
                var imported = Marshal.PtrToStringAnsi(module + checked((int)thunk) + 2);
                if (imported != name) continue;
                var slot = module + first + i * 8;
                if (!VirtualProtect(slot, 8, 4, out var old)) throw new System.ComponentModel.Win32Exception();
                try { Marshal.WriteIntPtr(slot, Marshal.GetFunctionPointerForDelegate(replacement)); }
                finally { if (!VirtualProtect(slot, 8, old, out _)) throw new System.ComponentModel.Win32Exception(); }
                count++;
            }
        }
        return count;
    }

    private record RpcResponse(bool Handled, byte[] Data);
    private static RpcResponse Rpc(Handle handle, string method, byte[] request, bool require = true)
    {
        var input = Marshal.AllocHGlobal(Math.Max(1, request.Length));
        var output = Marshal.AllocHGlobal(1024 * 1024);
        try
        {
            Marshal.Copy(request, 0, input, request.Length);
            var handled = handle(method, App, Account, input, (uint)request.Length, output, 1024 * 1024, out var length, out var result);
            if (require) Check(handled && result == 1, method + " succeeds");
            if (length > 1024 * 1024) throw new InvalidDataException("Native response exceeded buffer");
            var bytes = new byte[length]; Marshal.Copy(output, bytes, 0, bytes.Length);
            return new(handled, bytes);
        }
        finally { Marshal.FreeHGlobal(input); Marshal.FreeHGlobal(output); }
    }
    private record Field(int Number, ulong Value, byte[] Bytes);
    private static byte[] Message(params (int Number, object Value)[] fields)
    {
        using var stream = new MemoryStream();
        foreach (var field in fields)
        {
            if (field.Value is string || field.Value is byte[])
            {
                var bytes = field.Value is string s ? Encoding.UTF8.GetBytes(s) : (byte[])field.Value;
                Varint(stream, (ulong)(field.Number * 8 + 2)); Varint(stream, (ulong)bytes.Length); stream.Write(bytes);
            }
            else { Varint(stream, (ulong)(field.Number * 8)); Varint(stream, Convert.ToUInt64(field.Value)); }
        }
        return stream.ToArray();
    }
    private static void Varint(Stream stream, ulong n) { while (n >= 128) { stream.WriteByte((byte)(n | 128)); n >>= 7; } stream.WriteByte((byte)n); }
    private static ulong ReadVarint(byte[] b, ref int p)
    {
        ulong value = 0;
        for (var shift = 0; shift < 70 && p < b.Length; shift += 7) { var next = b[p++]; value |= (ulong)(next & 127) << shift; if (next < 128) return value; }
        throw new InvalidDataException("Invalid protobuf varint");
    }
    private static List<Field> Parse(byte[] bytes)
    {
        var fields = new List<Field>();
        for (var p = 0; p < bytes.Length;)
        {
            var tag = ReadVarint(bytes, ref p); var number = checked((int)(tag >> 3));
            switch (tag & 7)
            {
                case 0: fields.Add(new(number, ReadVarint(bytes, ref p), [])); break;
                case 1: fields.Add(new(number, BitConverter.ToUInt64(bytes, p), [])); p += 8; break;
                case 2:
                    var length = checked((int)ReadVarint(bytes, ref p));
                    if (length > bytes.Length - p) throw new InvalidDataException("Truncated protobuf bytes");
                    fields.Add(new(number, 0, bytes.AsSpan(p, length).ToArray())); p += length; break;
                case 5: fields.Add(new(number, BitConverter.ToUInt32(bytes, p), [])); p += 4; break;
                default: throw new InvalidDataException("Unsupported protobuf wire type");
            }
        }
        return fields;
    }
    private static Field Find(List<Field> fields, int n) => fields.First(f => f.Number == n);
    private static ulong Number(List<Field> fields, int n) => Find(fields, n).Value;
    private static string Text(List<Field> fields, int n) => Encoding.UTF8.GetString(Find(fields, n).Bytes);
}
