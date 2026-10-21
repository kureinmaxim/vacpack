using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Vacpack.Core;
using Vacpack.Windows;

var root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../.build/thumbnail-tests", Guid.NewGuid().ToString("N")));
System.Diagnostics.Trace.Listeners.Add(new System.Diagnostics.TextWriterTraceListener(Console.Out));
Directory.CreateDirectory(root);
var temporary = Path.Combine(root, "temporary");
var tools = new ToolLocator();
var service = new ThumbnailService(tools, temporary);
var failed = 0; var passed = 0;
var photo = Path.Combine(root, "Фото с пробелами & символами.png");
WriteImage(photo, new PngBitmapEncoder(), 640, 320);

await Check("Native photo preview is bounded, proportional, frozen and usable without FFmpeg", async () =>
{
    var native = new ThumbnailService(new ToolLocator([]), temporary);
    var image = await native.LoadAsync(photo);
    Require(image is { IsFrozen: true, PixelWidth: 160, PixelHeight: 80 });
    using var exclusive = new FileStream(photo, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
    Require(exclusive.Length > 0);
});
await Check("Unchanged file reuses its preview; modified file invalidates it", async () =>
{
    var first = await service.LoadAsync(photo);
    Require(ReferenceEquals(first, await service.LoadAsync(photo)));
    File.SetLastWriteTimeUtc(photo, File.GetLastWriteTimeUtc(photo).AddSeconds(5));
    Require(!ReferenceEquals(first, await service.LoadAsync(photo)));
});
await Check("GIF gets a static first-frame preview", async () =>
{
    var gif = Path.Combine(root, "animation.gif"); WriteImage(gif, new GifBitmapEncoder(), 120, 80);
    var image = await service.LoadAsync(gif);
    Require(image is { PixelWidth: 120, PixelHeight: 80, IsFrozen: true });
});
await Check("Missing and corrupt files fall back without failing the queue", async () =>
{
    Require(await service.LoadAsync(Path.Combine(root, "missing.jpg")) is null);
    var broken = Path.Combine(root, "broken.png"); await File.WriteAllTextAsync(broken, "not an image");
    Require(await service.LoadAsync(broken) is null);
    Require(!Directory.Exists(temporary) || !Directory.EnumerateFiles(temporary).Any());
});
await Check("Cancelled preview is not decoded or cached", async () =>
{
    using var token = new CancellationTokenSource(); token.Cancel();
    try { await service.LoadAsync(photo, token.Token); throw new Exception("Cancellation was ignored."); }
    catch (OperationCanceledException) { }
});

if (tools.Find("ffmpeg") is { } ffmpeg)
{
    var runner = new ProcessRunner();
    await Check("Video shorter than one second falls back to its first frame", async () =>
    {
        var video = Path.Combine(root, "Короткое видео.mp4");
        await Encode(["-f", "lavfi", "-i", "color=c=red:size=320x180:rate=12", "-t", "0.25", "-c:v", "libx264", "-pix_fmt", "yuv420p", video]);
        var image = await service.LoadAsync(video);
        Require(image is { IsFrozen: true, PixelWidth: 160, PixelHeight: 90 });
        var pixels = new byte[4];
        new FormatConvertedBitmap(image, PixelFormats.Bgra32, null, 0).CopyPixels(new System.Windows.Int32Rect(80, 45, 1, 1), pixels, 4, 0);
        Require(pixels[2] > 200 && pixels[0] < 50 && pixels[1] < 50);
        Require(!Directory.EnumerateFiles(temporary).Any());
    });
    await Check("EXIF-rotated JPEG preview has the displayed orientation", async () =>
    {
        var jpeg = Path.Combine(root, "rotated.jpg");
        var metadata = new BitmapMetadata("jpg"); metadata.SetQuery("/app1/ifd/{ushort=274}", (ushort)6);
        WriteImage(jpeg, new JpegBitmapEncoder(), 80, 40, metadata);
        var image = await service.LoadAsync(jpeg);
        Require(image is not null && image.PixelHeight > image.PixelWidth);
    });
    await Check("WebP preview works with the FFmpeg fallback", async () =>
    {
        var webp = Path.Combine(root, "photo.webp");
        await Encode(["-i", photo, "-frames:v", "1", "-c:v", "libwebp", webp]);
        var image = await service.LoadAsync(webp);
        Require(image is { IsFrozen: true, PixelWidth: 160, PixelHeight: 80 });
    });
    async Task Encode(string[] arguments)
    {
        var result = await runner.RunAsync(ffmpeg, new[] { "-hide_banner", "-loglevel", "error", "-nostdin", "-n" }.Concat(arguments));
        if (result.ExitCode != 0) throw new Exception(result.StandardError);
    }
}
else
{
    Console.WriteLine("SKIP: FFmpeg preview checks (set VACPACK_TOOLS).");
    if (args.Contains("--require-media")) failed++;
}
Console.WriteLine($"Thumbnail checks: {passed} passed, {failed} failed. Fixtures: {root}");
return failed == 0 ? 0 : 1;

async Task Check(string name, Func<Task> action)
{
    try { await action(); Console.WriteLine("PASS: " + name); passed++; }
    catch (Exception error) { Console.WriteLine("FAIL: " + name + Environment.NewLine + error); failed++; }
}
static void Require(bool condition) { if (!condition) throw new Exception("Assertion failed."); }
static void WriteImage(string path, BitmapEncoder encoder, int width, int height, BitmapMetadata? metadata = null)
{
    var pixels = new byte[width * height * 4];
    for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            var offset = (y * width + x) * 4;
            pixels[offset] = (byte)(x * 255 / width); pixels[offset + 1] = (byte)(y * 255 / height);
            pixels[offset + 2] = 200; pixels[offset + 3] = 255;
        }
    var source = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, width * 4);
    encoder.Frames.Add(BitmapFrame.Create(source, null, metadata, null));
    using var file = File.Create(path); encoder.Save(file);
}
