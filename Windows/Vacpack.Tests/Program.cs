using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Vacpack.Core;

// Dependency-free executable checks: no test adapter or NuGet feed is needed.
if (args.FirstOrDefault() == "--child")
{
    if (args[1] == "echo") { Console.WriteLine(JsonSerializer.Serialize(args.Skip(2))); return 0; }
    if (args[1] == "flood")
    {
        for (var i = 0; i < 12000; i++) { Console.WriteLine(new string('x', 100)); Console.Error.WriteLine(new string('y', 100)); }
        return 7;
    }
    if (args[1] == "sleep")
    {
        if (args.Length > 2) File.WriteAllText(args[2], Environment.ProcessId.ToString(CultureInfo.InvariantCulture));
        await Task.Delay(TimeSpan.FromMinutes(5)); return 0;
    }
    if (args[1] == "tree")
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in new[] { "--child", "sleep", args[2] }) start.ArgumentList.Add(argument);
        using var child = Process.Start(start);
        await Task.Delay(TimeSpan.FromMinutes(5)); return 0;
    }
}

var root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../.build/windows-tests"));
Directory.CreateDirectory(root);
var work = Path.Combine(root, Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(work);
var failed = 0;
var passed = 0;
var skipped = 0;
var runner = new ProcessRunner();
var info = new MediaInfo(1920, 1080, 4, 30, 2000000, false, "h264", null, ["aac", "pcm_s16le"], false);

await Check("Probe skips cover art, handles rotation, aspect ratio and all audio tracks", () =>
{
    var parsed = MediaInfo.Parse("""
        {"streams":[
          {"codec_type":"video","width":20,"height":20,"disposition":{"attached_pic":1}},
          {"codec_type":"video","codec_name":"vp9","width":720,"height":480,"sample_aspect_ratio":"4:3",
           "avg_frame_rate":"30000/1001","pix_fmt":"yuv420p","side_data_list":[{"rotation":90}],"tags":{"alpha_mode":"1"}},
          {"codec_type":"audio","codec_name":"aac","bit_rate":"128000"},
          {"codec_type":"audio","codec_name":"opus","bit_rate":"64000"}],
         "format":{"duration":"4.2","bit_rate":"1000000"}}
        """);
    Require(parsed.Width == 480 && parsed.Height == 960 && parsed.AudioCodecs.Count == 2);
    Require(parsed.VideoBitrate == 808000 && parsed.HasAlpha && parsed.AlphaDecoder == "libvpx-vp9");
    Require(Math.Abs(parsed.Fps - 29.97003) < .0001);
    return Task.CompletedTask;
});
await Check("Resize never upscales, rounds video dimensions down and respects longest edge", () =>
{
    Require(EncoderCommands.TargetSize(info, 800, true) == (800, 450));
    Require(EncoderCommands.TargetSize(info with { Width = 321, Height = 241 }, 1920, true) == (320, 240));
    Require(EncoderCommands.TargetSize(info with { Width = 321, Height = 241 }, 1920, false) == (321, 241));
    return Task.CompletedTask;
});
await Check("Arguments preserve Unicode paths and cap bitrate under ru-RU culture", () =>
{
    var before = CultureInfo.CurrentCulture;
    try
    {
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("ru-RU");
        var command = EncoderCommands.Build("C:\\Фото и видео\\a & b.mp4", "C:\\out.mp4", MediaKind.Video, info, new CompressionSettings());
        Require(command.Arguments.Contains("C:\\Фото и видео\\a & b.mp4"));
        Require(ValueAfter(command.Arguments, "-maxrate") == "1200k");
        Require(ValueAfter(command.Arguments, "-c:a:0") == "copy" && ValueAfter(command.Arguments, "-c:a:1") == "aac");
        Require(!ValueAfter(command.Arguments, "-vf").Contains("fps="));
    }
    finally { CultureInfo.CurrentCulture = before; }
    return Task.CompletedTask;
});
await Check("HDR and incompatible alpha are rejected before encoding", async () =>
{
    await Throws<NotSupportedException>(() => Task.FromResult(EncoderCommands.Build("a.mp4", "b.mp4", MediaKind.Video, info with { IsHdr = true }, new())));
    await Throws<NotSupportedException>(() => Task.FromResult(EncoderCommands.Build("a.mov", "b.mov", MediaKind.Video, info with { HasAlpha = true }, new())));
});
await Check("Output publication never overwrites input, files or existing directories", async () =>
{
    var input = Path.Combine(work, "source.png"); await File.WriteAllTextAsync(input, "original");
    await File.WriteAllTextAsync(Path.Combine(work, "source-vacpack.png"), "earlier");
    Directory.CreateDirectory(Path.Combine(work, "source-vacpack (1).png"));
    var staged = Path.Combine(work, ".temp.png"); await File.WriteAllTextAsync(staged, "new");
    var published = OutputStore.Publish(staged, input, ".png");
    Require(Path.GetFileName(published) == "source-vacpack (2).png");
    Require(await File.ReadAllTextAsync(input) == "original");
    Require(await File.ReadAllTextAsync(Path.Combine(work, "source-vacpack.png")) == "earlier");
});
await Check("Collection deduplicates folders and ignores unsupported and staging files", async () =>
{
    var directory = Path.Combine(work, "collect"); Directory.CreateDirectory(directory);
    var file = Path.Combine(directory, "фото.PNG"); await File.WriteAllTextAsync(file, "x");
    await File.WriteAllTextAsync(Path.Combine(directory, "note.txt"), "x");
    await File.WriteAllTextAsync(Path.Combine(directory, ".vacpack-temporary.png"), "x");
    Require(MediaFiles.Collect([directory, file]).SequenceEqual(new[] { file }));
});
await Check("Tool resolution uses absolute paths and explicit directory priority", async () =>
{
    var first = Path.Combine(work, "tools1"); var second = Path.Combine(work, "tools2");
    Directory.CreateDirectory(first); Directory.CreateDirectory(second);
    await File.WriteAllTextAsync(Path.Combine(first, "ffmpeg.exe"), "first");
    await File.WriteAllTextAsync(Path.Combine(second, "ffmpeg.exe"), "second");
    Require(new ToolLocator([".", first, second]).Require("ffmpeg") == Path.Combine(first, "ffmpeg.exe"));
});
await Check("Process runner passes arguments literally without invoking a shell", async () =>
{
    string[] expected = ["привет мир", "& exit 42", "a\"b", "", "C:\\folder with spaces\\", "$(whoami)"];
    var result = await runner.RunAsync(Environment.ProcessPath!, new[] { "--child", "echo" }.Concat(expected));
    Require(result.ExitCode == 0 && JsonSerializer.Deserialize<string[]>(result.StandardOutput)!.SequenceEqual(expected));
});
await Check("Process runner drains both pipes and limits captured logs", async () =>
{
    var result = await runner.RunAsync(Environment.ProcessPath!, ["--child", "flood"]);
    Require(result.ExitCode == 7 && result.StandardOutput.Length < 270000 && result.StandardError.Length < 270000);
});
await Check("Timeout terminates the child instead of waiting for completion", async () =>
{
    var clock = Stopwatch.StartNew();
    await Throws<TimeoutException>(() => runner.RunAsync(Environment.ProcessPath!, ["--child", "sleep"], timeout: TimeSpan.FromMilliseconds(250)));
    Require(clock.Elapsed < TimeSpan.FromSeconds(10));
});
await Check("Cancellation terminates the entire spawned process tree", async () =>
{
    var pidFile = Path.Combine(work, "child.pid");
    using var token = new CancellationTokenSource();
    var task = runner.RunAsync(Environment.ProcessPath!, ["--child", "tree", pidFile], token.Token);
    for (var i = 0; i < 100 && !File.Exists(pidFile); i++) await Task.Delay(50);
    Require(File.Exists(pidFile));
    var pid = int.Parse(await File.ReadAllTextAsync(pidFile), CultureInfo.InvariantCulture);
    token.Cancel(); await Throws<OperationCanceledException>(() => task);
    await Task.Delay(100);
    try { using var child = Process.GetProcessById(pid); Require(child.HasExited); } catch (ArgumentException) { }
});

var tools = new ToolLocator();
if (tools.Find("ffmpeg") is { } ffmpeg && tools.Find("ffprobe") is { } ffprobe)
{
    Console.WriteLine($"Integration tools: {ffmpeg}");
    var engine = new CompressionEngine(tools);
    var png = Path.Combine(work, "Прозрачное фото & пример.png");
    WritePng(png, 128, 96, compressed: false);
    await Check("PNG -> WebP retains alpha, shrinks and preserves input and file dates", async () =>
    {
        var before = await File.ReadAllBytesAsync(png);
        File.SetLastWriteTimeUtc(png, new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc));
        var result = await engine.CompressAsync(png, new() { ImageOutput = ImageOutput.WebP });
        Require(result.Output is not null && result.SavedBytes > 0);
        var output = await Probe(result.Output!);
        Require(output.HasAlpha && output.Width == 128 && output.Height == 96);
        Require((await File.ReadAllBytesAsync(png)).SequenceEqual(before));
        Require(File.GetLastWriteTimeUtc(result.Output!) == File.GetLastWriteTimeUtc(png));
    });
    await Check("Transparent PNG -> JPEG composites transparent pixels onto white", async () =>
    {
        var result = await engine.CompressAsync(png, new() { ImageOutput = ImageOutput.Jpeg });
        Require(result.Output is not null);
        var raw = Path.Combine(work, "white.rgb");
        await RunFfmpeg(["-i", result.Output!, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", raw]);
        var bytes = await File.ReadAllBytesAsync(raw);
        Require(bytes[0] > 240 && bytes[1] > 240 && bytes[2] > 240);
    });
    await Check("Odd-sized JPEG keeps exact dimensions and converts to AVIF", async () =>
    {
        var odd = Path.Combine(work, "odd.png"); WritePng(odd, 127, 95, compressed: false);
        var jpeg = await engine.CompressAsync(odd, new() { ImageOutput = ImageOutput.Jpeg });
        Require(jpeg.Output is not null);
        var jpegInfo = await Probe(jpeg.Output!);
        Require(jpegInfo.Width == 127 && jpegInfo.Height == 95);
        // The small JPEG may already be smaller than AVIF: either outcome is valid after verification.
        var avif = await engine.CompressAsync(jpeg.Output!, new() { ImageOutput = ImageOutput.Avif });
        if (avif.Output is not null) Require((await Probe(avif.Output)).Codec == "av1");
    });
    await Check("PNG output preserves full alpha without palette quantization", async () =>
    {
        var result = await engine.CompressAsync(png, new() { ImageOutput = ImageOutput.Png, MaxLongEdge = 64 });
        Require(result.Output is not null);
        var output = await Probe(result.Output!);
        Require(output.HasAlpha && output.Width == 64 && output.Height == 48);
    });
    await Check("Larger output is discarded; the original and destination remain intact", async () =>
    {
        var tiny = Path.Combine(work, "tiny.png"); WritePng(tiny, 1, 1, compressed: true);
        var before = await File.ReadAllBytesAsync(tiny);
        var result = await engine.CompressAsync(tiny, new());
        Require(result.KeptOriginal && result.SavedBytes == 0);
        Require((await File.ReadAllBytesAsync(tiny)).SequenceEqual(before));
        Require(!Directory.EnumerateFiles(work, ".vacpack-*").Any());
    });
    var video = Path.Combine(work, "Видео с двумя дорожками.mov");
    await Check("Create real video fixture with two audio streams", async () =>
    {
        await RunFfmpeg(["-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", "-t", "2", "-map", "0:v", "-map", "1:a", "-map", "2:a",
            "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast", "-c:a", "pcm_s16le", video]);
    });
    await Check("Video -> MP4 keeps both audio tracks, duration and smaller dimensions", async () =>
    {
        var result = await engine.CompressAsync(video, new() { VideoOutput = VideoOutput.Mp4, MaxLongEdge = 160, MaxVideoFps = 24 });
        Require(result.Output is not null && result.SavedBytes > 0);
        var output = await Probe(result.Output!);
        Require(output.Width == 160 && output.Height == 120 && output.AudioCodecs.Count == 2 && output.Fps <= 24.01);
        Require(Math.Abs(output.Duration - 2) < .15);
    });
    await Check("Video -> WebM uses VP9 and converts both audio tracks to Opus", async () =>
    {
        var result = await engine.CompressAsync(video, new() { VideoOutput = VideoOutput.WebM, MaxLongEdge = 160 });
        Require(result.Output is not null);
        var output = await Probe(result.Output!);
        Require(output.Codec == "vp9" && output.AudioCodecs.SequenceEqual(new[] { "opus", "opus" }));
    });
    await Check("Video -> GIF and GIF recompression preserve duration and cap frame rate", async () =>
    {
        var result = await engine.CompressAsync(video, new() { VideoOutput = VideoOutput.Gif, MaxLongEdge = 160, GifFps = 10 });
        Require(result.Output is not null);
        var output = await Probe(result.Output!);
        Require(output.Codec == "gif" && output.Fps <= 10.1 && Math.Abs(output.Duration - 2) < .2);
        var second = await engine.CompressAsync(result.Output!, new() { MaxLongEdge = 80, GifFps = 10 });
        Require(second.Output is not null && (await Probe(second.Output!)).Width == 80);
    });
    foreach (var format in new[] { VideoOutput.M4a, VideoOutput.Mp3, VideoOutput.Opus })
        await Check($"Extract {format} speech audio without truncation", async () =>
        {
            var result = await engine.CompressAsync(video, new() { VideoOutput = format, SpeechAudio = true });
            Require(result.Output is not null);
            var probe = await runner.RunAsync(ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", result.Output!]);
            using var document = JsonDocument.Parse(probe.StandardOutput);
            var stream = document.RootElement.GetProperty("streams")[0];
            Require(stream.GetProperty("codec_type").GetString() == "audio" && stream.GetProperty("channels").GetInt32() == 1);
            Require(double.Parse(document.RootElement.GetProperty("format").GetProperty("duration").ToString(), CultureInfo.InvariantCulture) >= 1.9);
        });
    await Check("Video mute removes every audio stream", async () =>
    {
        var result = await engine.CompressAsync(video, new() { VideoOutput = VideoOutput.Mp4, RemoveAudio = true });
        Require(result.Output is not null && (await Probe(result.Output!)).AudioCodecs.Count == 0);
    });
    await Check("Cancelling the compression pipeline removes staging and retains input", async () =>
    {
        using var cancellation = new CancellationTokenSource();
        await Throws<OperationCanceledException>(() => engine.CompressAsync(video, new() { VideoOutput = VideoOutput.WebM },
            new CancelOnProgress(cancellation), cancellation.Token));
        Require(File.Exists(video) && !Directory.EnumerateFiles(work, ".vacpack-*").Any());
    });
    await Check("Audio shorter than the video is validated against its own duration", async () =>
    {
        var shortAudio = Path.Combine(work, "short-audio.mov");
        await RunFfmpeg(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=15:duration=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast", "-c:a", "pcm_s16le", shortAudio]);
        var result = await engine.CompressAsync(shortAudio, new() { VideoOutput = VideoOutput.M4a });
        Require(result.Output is not null);
    });
    await Check("Invalid media fails without leaving any temporary output", async () =>
    {
        var invalid = Path.Combine(work, "broken.mp4"); await File.WriteAllTextAsync(invalid, "broken");
        await Throws<InvalidDataException>(() => engine.CompressAsync(invalid, new()));
        Require(await File.ReadAllTextAsync(invalid) == "broken");
        Require(!Directory.EnumerateFiles(work, ".vacpack-*").Any());
    });

    async Task<MediaInfo> Probe(string path)
    {
        var result = await runner.RunAsync(ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", path]);
        Require(result.ExitCode == 0); return MediaInfo.Parse(result.StandardOutput);
    }
    async Task RunFfmpeg(string[] arguments)
    {
        var result = await runner.RunAsync(ffmpeg, new[] { "-hide_banner", "-loglevel", "error", "-nostdin", "-n" }.Concat(arguments));
        if (result.ExitCode != 0) throw new Exception(result.StandardError);
    }
}
else
{
    skipped++;
    Console.WriteLine("SKIP: integration tests need ffmpeg.exe and ffprobe.exe; set VACPACK_TOOLS.");
    if (args.Contains("--require-media")) { Console.WriteLine("FAIL: media tests are required."); failed++; }
}
Console.WriteLine($"Checks: {passed} passed, {failed} failed, {skipped} skipped. Fixtures: {work}");
return failed == 0 ? 0 : 1;

async Task Check(string name, Func<Task> test)
{
    try { await test(); Console.WriteLine("PASS: " + name); passed++; }
    catch (Exception exception) { Console.WriteLine("FAIL: " + name + Environment.NewLine + exception); failed++; }
}
static void Require(bool condition) { if (!condition) throw new Exception("Assertion failed."); }
static string ValueAfter(IReadOnlyList<string> args, string key) => args[args.ToList().IndexOf(key) + 1];
static async Task Throws<T>(Func<Task> action) where T : Exception
{
    try { await action(); } catch (T) { return; }
    throw new Exception($"Expected {typeof(T).Name}.");
}

static void WritePng(string path, int width, int height, bool compressed)
{
    using var file = File.Create(path);
    file.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
    var header = new byte[13];
    System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(header, width);
    System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), height);
    header[8] = 8; header[9] = 6;
    Chunk("IHDR", header);
    using var memory = new MemoryStream();
    using (var zlib = new ZLibStream(memory, compressed ? CompressionLevel.SmallestSize : CompressionLevel.NoCompression, leaveOpen: true))
    {
        for (var y = 0; y < height; y++)
        {
            zlib.WriteByte(0);
            for (var x = 0; x < width; x++)
                zlib.Write(new byte[] { (byte)(x * 255 / width), (byte)(y * 255 / height), 160, (byte)(x < width / 2 ? 0 : 255) });
        }
    }
    Chunk("IDAT", memory.ToArray()); Chunk("IEND", []);
    void Chunk(string type, byte[] payload)
    {
        Span<byte> number = stackalloc byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(number, payload.Length); file.Write(number);
        var bytes = Encoding.ASCII.GetBytes(type).Concat(payload).ToArray(); file.Write(bytes);
        var crc = uint.MaxValue;
        foreach (var value in bytes)
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320u);
        }
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(number, ~crc); file.Write(number);
    }
}

sealed class CancelOnProgress(CancellationTokenSource source) : IProgress<double>
{
    public void Report(double value) => source.Cancel();
}
