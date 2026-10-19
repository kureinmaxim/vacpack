using System.Globalization;
using System.Text.Json;

namespace Vacpack.Core;

public sealed record CompressionResult(string Input, string? Output, long InputBytes, long OutputBytes)
{
    public bool KeptOriginal => Output is null;
    public long SavedBytes => Math.Max(0, InputBytes - OutputBytes);
}

public static class OutputStore
{
    public static string Publish(string staged, string input, string extension)
    {
        var directory = Path.GetDirectoryName(staged)!;
        var stem = Path.GetFileNameWithoutExtension(input) + "-vacpack";
        for (var counter = 0; ; counter++)
        {
            var destination = Path.Combine(directory, stem + (counter == 0 ? "" : $" ({counter})") + extension);
            try { File.Move(staged, destination, overwrite: false); return destination; }
            catch (IOException) when (File.Exists(destination) || Directory.Exists(destination)) { }
        }
    }
}

public sealed class CompressionEngine(ToolLocator? tools = null, ProcessRunner? runner = null)
{
    private readonly ToolLocator tools = tools ?? new ToolLocator();
    private readonly ProcessRunner runner = runner ?? new ProcessRunner();

    public async Task<CompressionResult> CompressAsync(string input, CompressionSettings settings,
        IProgress<double>? progress = null, CancellationToken cancellationToken = default)
    {
        settings.Validate();
        input = Path.GetFullPath(input);
        var kind = MediaFiles.Detect(input) ?? throw new NotSupportedException("Этот тип файла пока не поддерживается.");
        var ffmpeg = tools.Require("ffmpeg");
        var ffprobe = tools.Require("ffprobe");
        var original = new FileInfo(input);
        var originalBytes = original.Length;
        var modified = original.LastWriteTimeUtc;
        var created = original.CreationTimeUtc;
        var info = MediaInfo.Parse(await ProbeAsync(ffprobe, input, cancellationToken));
        var extension = EncoderCommands.Extension(input, kind, settings);
        var directory = settings.OutputDirectory is { Length: > 0 } custom ? Path.GetFullPath(custom) : Path.GetDirectoryName(input)!;
        Directory.CreateDirectory(directory);
        var staged = Path.Combine(directory, ".vacpack-" + Guid.NewGuid().ToString("N") + extension);
        try
        {
            var command = EncoderCommands.Build(input, staged, kind, info, settings);
            var result = await runner.RunAsync(ffmpeg, command.Arguments, cancellationToken, outputLine: line =>
            {
                if (info.Duration > 0 && line.StartsWith("out_time_us=", StringComparison.Ordinal)
                    && double.TryParse(line[12..], NumberStyles.Float, CultureInfo.InvariantCulture, out var microseconds))
                    progress?.Report(Math.Clamp(microseconds / 1000000 / info.Duration, 0, .98));
            }).ConfigureAwait(false);
            if (result.ExitCode != 0) throw new InvalidDataException("FFmpeg: " + ErrorTail(result.StandardError));
            cancellationToken.ThrowIfCancellationRequested();
            var outputBytes = new FileInfo(staged).Length;
            if (outputBytes == 0) throw new InvalidDataException("Кодер создал пустой файл.");
            await VerifyAsync(ffprobe, staged, command, info, kind, cancellationToken).ConfigureAwait(false);
            original.Refresh();
            if (!original.Exists || original.Length != originalBytes || original.LastWriteTimeUtc != modified)
                throw new IOException("Исходный файл изменился во время сжатия. Добавьте его заново.");
            if (outputBytes >= originalBytes)
            {
                progress?.Report(1);
                return new CompressionResult(input, null, originalBytes, originalBytes);
            }
            if (settings.KeepFileDates)
            {
                File.SetCreationTimeUtc(staged, created);
                File.SetLastWriteTimeUtc(staged, modified);
            }
            cancellationToken.ThrowIfCancellationRequested();
            var destination = OutputStore.Publish(staged, input, extension);
            progress?.Report(1);
            return new CompressionResult(input, destination, originalBytes, outputBytes);
        }
        finally
        {
            // Only this job's temporary file is removed. Inputs and earlier outputs are never overwritten.
            if (File.Exists(staged)) File.Delete(staged);
        }
    }

    private async Task<string> ProbeAsync(string ffprobe, string path, CancellationToken cancellationToken)
    {
        var result = await runner.RunAsync(ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
            cancellationToken, TimeSpan.FromSeconds(60)).ConfigureAwait(false);
        if (result.ExitCode != 0) throw new InvalidDataException("Не удалось прочитать файл: " + ErrorTail(result.StandardError));
        return result.StandardOutput;
    }

    private async Task VerifyAsync(string ffprobe, string path, EncodingCommand command, MediaInfo source,
        MediaKind kind, CancellationToken cancellationToken)
    {
        var json = await ProbeAsync(ffprobe, path, cancellationToken).ConfigureAwait(false);
        if (command.AudioOnly)
        {
            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.GetProperty("streams").EnumerateArray().Any(stream =>
                    stream.TryGetProperty("codec_type", out var type) && type.GetString() == "audio"))
                throw new InvalidDataException("В результате отсутствует звуковая дорожка.");
            var duration = document.RootElement.TryGetProperty("format", out var format)
                && format.TryGetProperty("duration", out var durationValue)
                && double.TryParse(durationValue.ToString(), CultureInfo.InvariantCulture, out var seconds) ? seconds : 0;
            var expectedDuration = source.AudioDuration ?? source.Duration;
            if (expectedDuration > 0 && duration < expectedDuration * .9)
                throw new InvalidDataException("Звуковой файл короче исходного видео.");
            return;
        }
        var output = MediaInfo.Parse(json);
        if (output.Width != command.Width || output.Height != command.Height)
            throw new InvalidDataException("Размер результата не совпадает с ожидаемым.");
        if (kind != MediaKind.Image && source.Duration > 0 && Math.Abs(output.Duration - source.Duration) > Math.Max(.25, source.Duration * .02))
            throw new InvalidDataException("Продолжительность результата отличается от исходного файла.");
        if (source.HasAlpha && command.Extension is ".png" or ".webp" or ".gif" or ".webm" && !output.HasAlpha)
            throw new InvalidDataException("Кодер не сохранил прозрачность.");
    }

    private static string ErrorTail(string text) => string.Join(Environment.NewLine,
        text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).TakeLast(5));
}
