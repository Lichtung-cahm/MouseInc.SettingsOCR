using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class OpenSettings
{
    [STAThread]
    private static void Main()
    {
        Mutex instance = null;
        bool ownsInstance = false;
        try
        {
            string directory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string identity;
            using (SHA256 sha = SHA256.Create())
                identity = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(directory.ToUpperInvariant()))).Replace("-", "");
            string objectName = @"Local\MouseInc.SettingsOCR." + identity;
            instance = new Mutex(false, objectName + ".Mutex");
            try { ownsInstance = instance.WaitOne(0, false); }
            catch (AbandonedMutexException) { ownsInstance = true; }
            if (!ownsInstance)
            {
                SignalExisting(objectName + ".Open");
                return;
            }

            using (EventWaitHandle reopen = new EventWaitHandle(false, EventResetMode.AutoReset, objectName + ".Open"))
            {
                string nativePath = Path.Combine(directory, "MouseInc.exe");
                string zipPath = Path.Combine(directory, "MouseInc.Settings.zip");
                if (!File.Exists(nativePath) || !File.Exists(zipPath))
                    throw new InvalidOperationException("Keep OpenSettings.exe, MouseInc.exe and MouseInc.Settings.zip in the same extracted folder.");

                Dictionary<string, WebAsset> assets = SettingsServer.LoadAssets(zipPath);
                int nativePid;
                int nativePort = FindOrStartNative(nativePath, directory, out nativePid);
                using (SettingsServer server = new SettingsServer(assets, nativePort))
                {
                    server.Start();
                    OpenBrowser(server.Url);
                    while (!server.IsIdle && NativeMethods.IsAlive(nativePid))
                    {
                        if (reopen.WaitOne(1000))
                        {
                            server.Touch();
                            OpenBrowser(server.Url);
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "MouseInc Settings", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            if (instance != null)
            {
                if (ownsInstance) instance.ReleaseMutex();
                instance.Dispose();
            }
        }
    }

    private static void SignalExisting(string name)
    {
        Stopwatch timeout = Stopwatch.StartNew();
        while (timeout.ElapsedMilliseconds < 10000)
        {
            try
            {
                using (EventWaitHandle signal = EventWaitHandle.OpenExisting(name)) signal.Set();
                return;
            }
            catch (WaitHandleCannotBeOpenedException) { Thread.Sleep(100); }
        }
        throw new InvalidOperationException("The settings launcher is still starting. Please try again in a few seconds.");
    }

    private static void OpenBrowser(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private static int FindOrStartNative(string nativePath, string directory, out int nativePid)
    {
        nativePid = FindNativeProcess(nativePath);
        if (nativePid == 0)
        {
            using (Process started = Process.Start(new ProcessStartInfo(nativePath)
            {
                WorkingDirectory = directory,
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Normal
            })) { }
        }

        Stopwatch timeout = Stopwatch.StartNew();
        while (timeout.ElapsedMilliseconds < 10000)
        {
            nativePid = FindNativeProcess(nativePath);
            if (nativePid != 0)
            {
                foreach (int port in NativeMethods.LoopbackListeningPorts(nativePid))
                    if (NativeMethods.IsSettingsSocket(port)) return port;
            }
            Thread.Sleep(200);
        }
        throw new InvalidOperationException("MouseInc did not make its local settings channel available within 10 seconds. Check that MouseInc can run, then try opening its tray settings once and double-click this launcher again.");
    }

    private static int FindNativeProcess(string expectedPath)
    {
        int found = 0;
        foreach (Process process in Process.GetProcessesByName("MouseInc"))
        {
            using (process)
            {
                string path = NativeMethods.ProcessPath(process.Id);
                if (path == null)
                {
                    if (!NativeMethods.IsAlive(process.Id)) continue;
                    throw new InvalidOperationException("Another MouseInc process is running, but its location cannot be read. Exit that existing instance from its tray menu before opening this package. The launcher will not stop it or change its settings.");
                }
                if (!String.Equals(Path.GetFullPath(path), expectedPath, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("MouseInc is already running from another folder:\n" + Path.GetDirectoryName(path) + "\n\nExit that instance from its tray menu first, then double-click this launcher again.");
                found = process.Id;
            }
        }
        return found;
    }
}

internal static class NativeMethods
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("iphlpapi.dll")]
    private static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int addressFamily, int tableClass, uint reserved);

    internal static string ProcessPath(int pid)
    {
        IntPtr handle = OpenProcess(0x1000, false, pid);
        if (handle == IntPtr.Zero) return null;
        try
        {
            StringBuilder path = new StringBuilder(32768);
            int length = path.Capacity;
            return QueryFullProcessImageName(handle, 0, path, ref length) ? path.ToString() : null;
        }
        finally { CloseHandle(handle); }
    }

    internal static bool IsAlive(int pid)
    {
        try { using (Process process = Process.GetProcessById(pid)) return !process.HasExited; }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    internal static List<int> LoopbackListeningPorts(int pid)
    {
        int size = 0;
        uint result = GetExtendedTcpTable(IntPtr.Zero, ref size, false, 2, 3, 0);
        if (result != 0 && result != 122) throw new Win32Exception((int)result);
        for (int attempt = 0; attempt < 4; attempt++)
        {
            IntPtr table = Marshal.AllocHGlobal(size);
            try
            {
                int allocated = size;
                result = GetExtendedTcpTable(table, ref size, false, 2, 3, 0);
                if (result == 122) continue;
                if (result != 0) throw new Win32Exception((int)result);
                int count = Marshal.ReadInt32(table);
                if (count < 0 || count > (allocated - 4) / 24)
                    throw new InvalidOperationException("Windows returned an invalid TCP endpoint table.");
                List<int> ports = new List<int>();
                for (int i = 0; i < count; i++)
                {
                    IntPtr row = IntPtr.Add(table, 4 + i * 24);
                    uint address = unchecked((uint)Marshal.ReadInt32(row, 4));
                    if (Marshal.ReadInt32(row) != 2 || Marshal.ReadInt32(row, 20) != pid ||
                        (address != 0 && !new IPAddress((long)address).Equals(IPAddress.Loopback))) continue;
                    uint networkPort = unchecked((uint)Marshal.ReadInt32(row, 8));
                    int port = (int)(((networkPort & 255) << 8) | ((networkPort >> 8) & 255));
                    if (port > 0 && !ports.Contains(port)) ports.Add(port);
                }
                return ports;
            }
            finally { Marshal.FreeHGlobal(table); }
        }
        throw new InvalidOperationException("The Windows TCP endpoint table kept changing. Please try again.");
    }

    internal static bool IsSettingsSocket(int port)
    {
        try
        {
            using (TcpClient client = new TcpClient(AddressFamily.InterNetwork))
            {
                client.ReceiveTimeout = 500;
                client.SendTimeout = 500;
                client.Connect(IPAddress.Loopback, port);
                using (NetworkStream stream = client.GetStream())
                {
                    string key = Convert.ToBase64String(Guid.NewGuid().ToByteArray());
                    byte[] request = Encoding.ASCII.GetBytes("GET /ws HTTP/1.1\r\nHost: 127.0.0.1:" + port + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n");
                    stream.Write(request, 0, request.Length);
                    string response = ReadHeaders(stream, 8192);
                    if (response == null || !response.StartsWith("HTTP/1.1 101 ", StringComparison.Ordinal)) return false;
                    string accept;
                    using (SHA1 sha = SHA1.Create())
                        accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
                    foreach (string line in response.Split(new string[] { "\r\n" }, StringSplitOptions.None))
                    {
                        int colon = line.IndexOf(':');
                        if (colon > 0 && line.Substring(0, colon).Equals("Sec-WebSocket-Accept", StringComparison.OrdinalIgnoreCase))
                            return line.Substring(colon + 1).Trim() == accept;
                    }
                }
            }
        }
        catch (IOException) { }
        catch (SocketException) { }
        return false;
    }

    internal static string ReadHeaders(NetworkStream stream, int limit)
    {
        byte[] bytes = new byte[limit];
        int length = 0;
        while (length < bytes.Length)
        {
            int value = stream.ReadByte();
            if (value < 0) return null;
            bytes[length++] = (byte)value;
            if (length >= 4 && bytes[length - 4] == 13 && bytes[length - 3] == 10 && bytes[length - 2] == 13 && bytes[length - 1] == 10)
                return Encoding.ASCII.GetString(bytes, 0, length);
        }
        throw new InvalidDataException("HTTP request headers exceed the allowed size.");
    }
}

internal sealed class WebAsset
{
    internal readonly byte[] Bytes;
    internal readonly string ContentType;
    internal WebAsset(byte[] bytes, string contentType) { Bytes = bytes; ContentType = contentType; }
}

internal sealed class SettingsServer : IDisposable
{
    private readonly Dictionary<string, WebAsset> assets;
    private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    private readonly HashSet<TcpClient> clients = new HashSet<TcpClient>();
    private readonly object clientsLock = new object();
    private readonly int nativePort;
    private Thread acceptThread;
    private volatile bool stopping;
    private long lastActivity = Stopwatch.GetTimestamp();
    internal string Url { get; private set; }
    internal bool IsIdle { get { return (Stopwatch.GetTimestamp() - Interlocked.Read(ref lastActivity)) / (double)Stopwatch.Frequency >= 1800; } }

    internal SettingsServer(Dictionary<string, WebAsset> assets, int nativePort)
    {
        this.assets = assets;
        this.nativePort = nativePort;
    }

    internal static Dictionary<string, WebAsset> LoadAssets(string path)
    {
        Dictionary<string, WebAsset> files = new Dictionary<string, WebAsset>(StringComparer.Ordinal);
        long total = 0;
        using (ZipArchive zip = ZipFile.OpenRead(path))
        {
            if (zip.Entries.Count > 4096) throw new InvalidDataException("The settings archive contains too many files.");
            foreach (ZipArchiveEntry entry in zip.Entries)
            {
                string name = entry.FullName;
                if (name.EndsWith("/", StringComparison.Ordinal)) continue;
                if (!IsAssetPath(name) || files.ContainsKey(name))
                    throw new InvalidDataException("The settings archive contains an invalid or duplicate asset path.");
                total += entry.Length;
                if (entry.Length > 16 * 1024 * 1024 || total > 64 * 1024 * 1024)
                    throw new InvalidDataException("The settings archive is unexpectedly large.");
                byte[] bytes;
                using (Stream input = entry.Open())
                using (MemoryStream output = new MemoryStream())
                {
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        if (output.Length + read > entry.Length)
                            throw new InvalidDataException("The settings archive contains an invalid asset size.");
                        output.Write(buffer, 0, read);
                    }
                    if (output.Length != entry.Length) throw new InvalidDataException("The settings archive is truncated.");
                    bytes = output.ToArray();
                }
                files.Add(name, new WebAsset(bytes, ContentType(name)));
            }
        }
        if (!files.ContainsKey("index.html")) throw new InvalidDataException("MouseInc.Settings.zip must contain index.html at its root.");
        return files;
    }

    private static bool IsAssetPath(string path)
    {
        if (String.IsNullOrEmpty(path) || path[0] == '/' || path.IndexOf('\\') >= 0 || path.IndexOf(':') >= 0) return false;
        foreach (char character in path) if (Char.IsControl(character)) return false;
        foreach (string part in path.Split('/')) if (part.Length == 0 || part == "." || part == "..") return false;
        return true;
    }

    internal void Start()
    {
        listener.Start(32);
        Url = "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port + "/mouseinc/?port=" + nativePort;
        acceptThread = new Thread(AcceptClients) { IsBackground = true, Name = "MouseInc local settings" };
        acceptThread.Start();
    }

    internal void Touch() { Interlocked.Exchange(ref lastActivity, Stopwatch.GetTimestamp()); }

    private void AcceptClients()
    {
        while (!stopping)
        {
            TcpClient client;
            try { client = listener.AcceptTcpClient(); }
            catch (SocketException) { if (stopping) return; continue; }
            catch (ObjectDisposedException) { return; }
            lock (clientsLock)
            {
                if (stopping || clients.Count >= 16) { client.Close(); continue; }
                clients.Add(client);
            }
            ThreadPool.QueueUserWorkItem(ServeClient, client);
        }
    }

    private void ServeClient(object state)
    {
        TcpClient client = (TcpClient)state;
        try
        {
            using (client)
            {
                client.ReceiveTimeout = 5000;
                client.SendTimeout = 5000;
                using (NetworkStream stream = client.GetStream())
                {
                    string headers;
                    try { headers = NativeMethods.ReadHeaders(stream, 16 * 1024); }
                    catch (InvalidDataException) { Respond(stream, 431, "Request Header Fields Too Large", "text/plain; charset=utf-8", Encoding.UTF8.GetBytes("Request headers must not exceed 16 KB."), false); return; }
                    if (headers == null) return;
                    string firstLine = headers.Substring(0, headers.IndexOf("\r\n", StringComparison.Ordinal));
                    string[] request = firstLine.Split(' ');
                    bool headOnly = request.Length > 0 && request[0] == "HEAD";
                    if (request.Length != 3 || (request[2] != "HTTP/1.0" && request[2] != "HTTP/1.1"))
                    { Error(stream, 400, "Bad Request", headOnly); return; }
                    if (request[0] != "GET" && !headOnly)
                    { Error(stream, 405, "Method Not Allowed", false); return; }
                    string target = request[1];
                    int query = target.IndexOf('?');
                    if (query >= 0) target = target.Substring(0, query);
                    string path;
                    try { path = Uri.UnescapeDataString(target); }
                    catch (UriFormatException) { Error(stream, 400, "Bad Request", headOnly); return; }
                    if (path == "/mouseinc" || path == "/mouseinc/") path = "/mouseinc/index.html";
                    const string prefix = "/mouseinc/";
                    if (!path.StartsWith(prefix, StringComparison.Ordinal))
                    { Error(stream, 404, "Not Found", headOnly); return; }
                    string name = path.Substring(prefix.Length);
                    WebAsset asset;
                    if (!IsAssetPath(name) || !assets.TryGetValue(name, out asset))
                    { Error(stream, 404, "Not Found", headOnly); return; }
                    Touch();
                    Respond(stream, 200, "OK", asset.ContentType, asset.Bytes, headOnly);
                }
            }
        }
        catch (IOException) { }
        catch (SocketException) { }
        catch (ObjectDisposedException) { }
        finally
        {
            client.Close();
            lock (clientsLock) clients.Remove(client);
        }
    }

    private static void Error(NetworkStream stream, int status, string reason, bool headOnly)
    {
        Respond(stream, status, reason, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes(reason), headOnly);
    }

    private static void Respond(NetworkStream stream, int status, string reason, string contentType, byte[] body, bool headOnly)
    {
        string allow = status == 405 ? "Allow: GET, HEAD\r\n" : String.Empty;
        byte[] headers = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + " " + reason + "\r\nContent-Type: " + contentType + "\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" + allow + "\r\n");
        stream.Write(headers, 0, headers.Length);
        if (!headOnly) stream.Write(body, 0, body.Length);
    }

    private static string ContentType(string name)
    {
        switch (Path.GetExtension(name).ToLowerInvariant())
        {
            case ".html": return "text/html; charset=utf-8";
            case ".js": return "application/javascript; charset=utf-8";
            case ".css": return "text/css; charset=utf-8";
            case ".json": return "application/json; charset=utf-8";
            case ".svg": return "image/svg+xml";
            case ".png": return "image/png";
            case ".jpg": case ".jpeg": return "image/jpeg";
            case ".gif": return "image/gif";
            case ".webp": return "image/webp";
            case ".ico": return "image/x-icon";
            case ".woff": return "font/woff";
            case ".woff2": return "font/woff2";
            case ".ttf": return "font/ttf";
            case ".otf": return "font/otf";
            case ".wasm": return "application/wasm";
            default: return "application/octet-stream";
        }
    }

    public void Dispose()
    {
        stopping = true;
        listener.Stop();
        lock (clientsLock) foreach (TcpClient client in clients) client.Close();
        if (acceptThread != null) acceptThread.Join(1000);
    }
}
