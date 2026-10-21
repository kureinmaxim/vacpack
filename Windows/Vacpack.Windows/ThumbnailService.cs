using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
using Vacpack.Core;

namespace Vacpack.Windows;

/// <summary>Small, frozen previews; no input file stays open and no preview is persisted.</summary>
public sealed class ThumbnailService(ToolLocator? tools = null, string? temporaryDirectory = null)
{
    private readonly ToolLocator tools = tools ?? new ToolLocator();
    private readonly string temporaryDirectory = temporaryDirectory ?? Path.Combine(Path.GetTempPath(), "Vacpack", "thumbnails");
    private readonly SemaphoreSlim slots = new(2);
    private readonly object cacheLock = new();
    private readonly Dictionary<string, BitmapSource> cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly Queue<string> cacheOrder = new();
    private readonly ProcessRunner runner = new();
    private const int Edge = 160;

    public async Task<BitmapSource?> LoadAsync(string path, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            var key = await Task.Run(() =>
            {
                var file = new FileInfo(path);
                return file.FullName + "\n" + file.Length + "\n" + file.LastWriteTimeUtc.Ticks;
            }, cancellationToken).ConfigureAwait(false);
            lock (cacheLock) if (cache.TryGetValue(key, out var cached)) return cached;
            await slots.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                lock (cacheLock) if (cache.TryGetValue(key, out var cached)) return cached;
                BitmapSource? image = null;
                if (MediaFiles.Detect(path) != MediaKind.Video)
                {
                    try { image = await Task.Run(() => Decode(path, respectOrientation: true), cancellationToken).ConfigureAwait(false); }
                    catch (Exception error) when (PreviewFailure(error)) { System.Diagnostics.Trace.WriteLine("Thumbnail: " + error.Message); }
                }
                image ??= await DecodeWithFfmpegAsync(path, cancellationToken).ConfigureAwait(false);
                cancellationToken.ThrowIfCancellationRequested();
                if (image is not null)
                {
                    lock (cacheLock)
                    {
                        if (!cache.ContainsKey(key))
                        {
                            while (cache.Count >= 128) cache.Remove(cacheOrder.Dequeue());
                            cache.Add(key, image); cacheOrder.Enqueue(key);
                        }
                    }
                }
                return image;
            }
            finally { slots.Release(); }
        }
        catch (Exception error) when (PreviewFailure(error)) { System.Diagnostics.Trace.WriteLine("Thumbnail: " + error.Message); return null; }
    }

    public void ClearCache()
    {
        lock (cacheLock) { cache.Clear(); cacheOrder.Clear(); }
    }

    private async Task<BitmapSource?> DecodeWithFfmpegAsync(string path, CancellationToken cancellationToken)
    {
        var ffmpeg = tools.Find("ffmpeg");
        if (ffmpeg is null) return null;
        Directory.CreateDirectory(temporaryDirectory);
        var preview = Path.Combine(temporaryDirectory, Guid.NewGuid().ToString("N") + ".png");
        try
        {
            var video = MediaFiles.Detect(path) == MediaKind.Video;
            // A short clip may end before the preferred frame; then use its first frame.
            foreach (var seek in video ? new[] { "1", "0" } : new[] { "0" })
            {
                var arguments = new List<string> { "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-threads", "1" };
                if (video) arguments.AddRange(["-ss", seek]);
                arguments.AddRange(["-i", Path.GetFullPath(path), "-map", "0:V:0", "-frames:v", "1", "-an", "-sn", "-dn",
                    "-vf", $"scale={Edge}:{Edge}:force_original_aspect_ratio=decrease,setsar=1", "-filter_threads", "1", "-threads", "1", "-update", "1", preview]);
                var result = await runner.RunAsync(ffmpeg, arguments, cancellationToken, TimeSpan.FromSeconds(15)).ConfigureAwait(false);
                if (result.ExitCode == 0 && File.Exists(preview) && new FileInfo(preview).Length > 0)
                    return await Task.Run(() => Decode(preview, respectOrientation: false), cancellationToken).ConfigureAwait(false);
            }
            return null;
        }
        finally
        {
            try { File.Delete(preview); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static BitmapSource? Decode(string path, bool respectOrientation)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
        if (decoder.Frames.Count == 0) return null;
        var frame = decoder.Frames[0];
        var pixelWidth = frame.PixelWidth;
        var pixelHeight = frame.PixelHeight;
        if (respectOrientation && frame.Metadata is BitmapMetadata metadata)
        {
            foreach (var query in new[] { "/app1/ifd/{ushort=274}", "/ifd/{ushort=274}" })
                if (metadata.ContainsQuery(query) && metadata.GetQuery(query) is ushort orientation && orientation is > 1 and <= 8)
                    return null; // FFmpeg applies EXIF rotation and mirroring before reducing the image.
        }
        stream.Position = 0;
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        if (pixelWidth >= pixelHeight) image.DecodePixelWidth = Math.Min(Edge, pixelWidth);
        else image.DecodePixelHeight = Math.Min(Edge, pixelHeight);
        image.EndInit();
        image.Freeze();
        return image;
    }

    private static bool PreviewFailure(Exception error) => error is IOException or UnauthorizedAccessException
        or NotSupportedException or ArgumentException or FormatException or COMException or TimeoutException
        or System.ComponentModel.Win32Exception;
}
