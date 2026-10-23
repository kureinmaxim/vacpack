namespace Vacpack.Core;

public enum MediaKind { Image, Video, Gif }
public enum Quality { Highest, High, Good, Medium, Acceptable }
public enum ImageOutput { Original, Jpeg, Png, WebP, Avif }
public enum VideoOutput { Original, Mp4, WebM, Gif, M4a, Mp3, Opus }

/// <summary>
/// The video codec. Default is the one the container implies (H.264 in MP4/MOV/MKV, VP9 in WebM);
/// the others are experimental: AV1 (SVT-AV1), HEVC (x265) and H.266 / VVC (vvenc, very slow).
/// </summary>
public enum VideoCodec { Default, Av1, Hevc, Vvc }

public sealed record CompressionSettings
{
    public Quality Quality { get; init; } = Quality.Good;
    public ImageOutput ImageOutput { get; init; }
    public VideoOutput VideoOutput { get; init; }
    public int MaxLongEdge { get; init; }
    public int MaxVideoFps { get; init; }
    public int GifFps { get; init; } = 15;
    public bool RemoveAudio { get; init; }
    public bool SpeechAudio { get; init; }

    // Experimental, video only: strong compression.
    public VideoCodec VideoCodec { get; init; }
    /// <summary>Aim for a file of at most this many megabytes (0 = off). Needs a known duration.</summary>
    public double TargetSizeMb { get; init; }
    /// <summary>Audio bitrate in kbit/s for the first audio track (0 = the usual rules); Opus.</summary>
    public int AudioKbps { get; init; }
    public bool MonoAudio { get; init; }
    public bool Grayscale { get; init; }
    public bool Denoise { get; init; }
    public bool DropDuplicateFrames { get; init; }
    public bool KeepFileDates { get; init; } = true;
    public string? OutputDirectory { get; init; }

    public void Validate()
    {
        if (!Enum.IsDefined(Quality) || !Enum.IsDefined(ImageOutput) || !Enum.IsDefined(VideoOutput))
            throw new ArgumentException(Loc.T("Неизвестная настройка сжатия."));
        if (MaxLongEdge < 0 || MaxVideoFps < 0 || GifFps is < 1 or > 50)
            throw new ArgumentException(Loc.T("Проверьте размеры и частоту кадров."));
        if (!Enum.IsDefined(VideoCodec) || !double.IsFinite(TargetSizeMb) || TargetSizeMb is < 0 or > 1_000_000
            || TargetSizeMb is > 0 and < 0.05 || AudioKbps is < 0 or > 320)
            throw new ArgumentException(Loc.T("Проверьте целевой размер и параметры звука."));
    }
}

public static class MediaFiles
{
    public static MediaKind? Detect(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" or ".png" or ".webp" or ".bmp" or ".tif" or ".tiff" or ".avif" => MediaKind.Image,
        ".mp4" or ".mov" or ".mkv" or ".webm" or ".avi" or ".m4v" or ".mpeg" or ".mpg"
            or ".mts" or ".m2ts" or ".wmv" => MediaKind.Video,
        ".gif" => MediaKind.Gif,
        _ => null
    };

    public static IReadOnlyList<string> Collect(IEnumerable<string> paths)
    {
        var files = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true, IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint | FileAttributes.Hidden | FileAttributes.System
        };
        foreach (var path in paths)
        {
            if (File.Exists(path)) Add(path);
            else if (Directory.Exists(path))
            {
                foreach (var file in Directory.EnumerateFiles(path, "*", options)) Add(file);
            }
        }
        return files.Order(StringComparer.OrdinalIgnoreCase).ToArray();

        void Add(string file)
        {
            if (!Path.GetFileName(file).StartsWith('.') && Detect(file) is not null)
                files.Add(Path.GetFullPath(file));
        }
    }
}
