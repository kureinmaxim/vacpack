using System.Globalization;

namespace Vacpack.Core;

public sealed record EncodingCommand(IReadOnlyList<string> Arguments, string Extension, int Width, int Height, bool AudioOnly);

public static class EncoderCommands
{
    private static readonly int[] X264 = [18, 21, 24, 27, 30];
    private static readonly int[] Vp9 = [24, 30, 34, 38, 42];
    private static readonly double[] SourceShare = [.90, .75, .60, .45, .32];
    private static readonly int[] WebP = [92, 82, 72, 60, 45];
    private static readonly int[] Jpeg = [2, 3, 5, 7, 10];

    public static string Extension(string input, MediaKind kind, CompressionSettings settings) => kind switch
    {
        MediaKind.Gif => ".gif",
        MediaKind.Image => settings.ImageOutput switch
        {
            ImageOutput.Jpeg => ".jpg", ImageOutput.Png => ".png", ImageOutput.WebP => ".webp",
            ImageOutput.Avif => ".avif", _ => Path.GetExtension(input).ToLowerInvariant()
        },
        _ => settings.VideoOutput switch
        {
            VideoOutput.Mp4 => ".mp4", VideoOutput.WebM => ".webm", VideoOutput.Gif => ".gif",
            VideoOutput.M4a => ".m4a", VideoOutput.Mp3 => ".mp3", VideoOutput.Opus => ".opus",
            _ => Path.GetExtension(input).ToLowerInvariant() is ".mov" or ".mkv" or ".webm" ? Path.GetExtension(input).ToLowerInvariant() : ".mp4"
        }
    };

    public static (int Width, int Height) TargetSize(MediaInfo info, int maxLongEdge, bool even)
    {
        var ratio = maxLongEdge > 0 ? Math.Min(1.0, (double)maxLongEdge / Math.Max(info.Width, info.Height)) : 1.0;
        var width = Math.Max(1, (int)Math.Floor(info.Width * ratio));
        var height = Math.Max(1, (int)Math.Floor(info.Height * ratio));
        if (even)
        {
            width -= width % 2; height -= height % 2;
            if (width < 2 || height < 2) throw new InvalidDataException("Размер видео слишком мал для выбранного кодека.");
        }
        return (width, height);
    }

    public static EncodingCommand Build(string input, string output, MediaKind kind, MediaInfo info, CompressionSettings settings)
    {
        settings.Validate();
        var extension = Extension(input, kind, settings);
        var audioOnly = kind == MediaKind.Video && settings.VideoOutput is VideoOutput.M4a or VideoOutput.Mp3 or VideoOutput.Opus;
        var gif = extension == ".gif";
        if (info.IsHdr && kind == MediaKind.Video && !audioOnly)
            throw new NotSupportedException("HDR-видео пока не поддерживается в Windows-версии: требуется отдельное преобразование цвета.");
        if (info.Codec == "apng") throw new NotSupportedException("Анимированный PNG пока не поддерживается.");
        if (info.HasAlpha && kind == MediaKind.Video && !audioOnly && !gif && extension != ".webm")
            throw new NotSupportedException("Для видео с прозрачностью выберите WebM.");
        var (width, height) = TargetSize(info, settings.MaxLongEdge, kind == MediaKind.Video && !gif && !audioOnly);
        var q = (int)settings.Quality;
        var args = new List<string> { "-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-progress", "pipe:1", "-nostats" };
        if (info.AlphaDecoder is not null) args.AddRange(["-c:v", info.AlphaDecoder]);
        args.AddRange(["-i", input]);
        if (audioOnly)
        {
            if (info.AudioCodecs.Count == 0) throw new InvalidDataException("В видео нет звуковой дорожки.");
            args.AddRange(["-map", "0:a:0", "-vn", "-map_metadata", "0"]);
            args.AddRange(extension switch
            {
                ".mp3" => settings.SpeechAudio ? ["-c:a", "libmp3lame", "-b:a", "64k"] : new[] { "-c:a", "libmp3lame", "-q:a", "0" },
                ".opus" => ["-c:a", "libopus", "-b:a", settings.SpeechAudio ? "32k" : "128k"],
                _ => ["-c:a", "aac", "-b:a", settings.SpeechAudio ? "48k" : "192k"]
            });
            if (settings.SpeechAudio) args.AddRange(["-ac", "1", "-ar", "24000", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]);
        }
        else
        {
            var filters = new List<string>();
            var fpsLimit = gif ? settings.GifFps : settings.MaxVideoFps;
            if (fpsLimit > 0 && info.Fps > fpsLimit + .01) filters.Add($"fps={fpsLimit}");
            filters.Add($"scale={width}:{height}:flags=lanczos");
            filters.Add("setsar=1");
            if (gif)
            {
                var colors = new[] { 256, 224, 192, 160, 128 }[q];
                args.AddRange(["-filter_complex", $"[0:V:0]{string.Join(',', filters)},split[a][b];[a]palettegen=max_colors={colors}:reserve_transparent=1[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle[out]",
                    "-map", "[out]", "-an", "-loop", "0", "-fps_mode", "vfr"]);
            }
            else if (kind == MediaKind.Image)
            {
                if (extension is ".jpg" or ".jpeg")
                {
                    // A white canvas makes transparent PNG/WebP -> JPEG predictable.
                    args.AddRange(["-filter_complex", $"[0:V:0]{string.Join(',', filters)}[image];color=c=white:s={width}x{height},format=rgb24[bg];[bg][image]overlay=shortest=1:format=auto,format=yuvj444p[out]", "-map", "[out]"]);
                }
                else args.AddRange(["-map", "0:V:0", "-vf", string.Join(',', filters)]);
                args.AddRange(["-frames:v", "1", "-an"]);
                args.AddRange(extension switch
                {
                    ".jpg" or ".jpeg" => ["-c:v", "mjpeg", "-q:v", Jpeg[q].ToString(CultureInfo.InvariantCulture)],
                    ".png" => ["-c:v", "png", "-compression_level", "9"],
                    ".webp" => ["-c:v", "libwebp", "-quality", WebP[q].ToString(CultureInfo.InvariantCulture), "-compression_level", "6"],
                    ".avif" => ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", new[] { "18", "24", "30", "36", "42" }[q], "-cpu-used", "6"],
                    ".tif" or ".tiff" => ["-c:v", "tiff", "-compression_algo", "deflate"],
                    ".bmp" => ["-c:v", "bmp"],
                    _ => throw new NotSupportedException("Этот формат изображения пока не поддерживается.")
                });
                if (info.HasAlpha && extension == ".avif")
                    throw new NotSupportedException("Для изображения с прозрачностью выберите PNG или WebP.");
                if (extension != ".avif") args.AddRange(["-update", "1"]);
            }
            else
            {
                args.AddRange(["-map", "0:V:0", "-vf", string.Join(',', filters), "-map_metadata", "0", "-sn", "-dn"]);
                if (settings.RemoveAudio) args.Add("-an");
                else args.AddRange(["-map", "0:a?"]);
                if (extension == ".webm")
                    args.AddRange(["-c:v", "libvpx-vp9", "-crf", Vp9[q].ToString(CultureInfo.InvariantCulture), "-b:v", "0", "-row-mt", "1", "-cpu-used", "4",
                        "-pix_fmt", info.HasAlpha ? "yuva420p" : "yuv420p"]);
                else args.AddRange(["-c:v", "libx264", "-crf", X264[q].ToString(CultureInfo.InvariantCulture), "-preset", "medium", "-pix_fmt", "yuv420p"]);
                if (info.VideoBitrate is > 0)
                {
                    var cap = Math.Max(1, (long)(info.VideoBitrate.Value * SourceShare[q]) / 1000).ToString(CultureInfo.InvariantCulture) + "k";
                    if (extension == ".webm")
                    {
                        var index = args.IndexOf("-b:v"); args[index + 1] = cap;
                    }
                    else args.AddRange(["-maxrate", cap, "-bufsize", cap]);
                }
                if (info.HasAlpha && extension == ".webm") args.AddRange(["-auto-alt-ref", "0"]);
                if (!settings.RemoveAudio)
                {
                    for (var i = 0; i < info.AudioCodecs.Count; i++)
                    {
                        var copy = extension == ".webm" ? info.AudioCodecs[i] is "opus" or "vorbis"
                            : extension == ".mkv" || info.AudioCodecs[i] is "aac" or "mp3" or "alac";
                        args.AddRange([$"-c:a:{i}", copy ? "copy" : extension == ".webm" ? "libopus" : "aac"]);
                        if (!copy) args.AddRange([$"-b:a:{i}", extension == ".webm" ? "160k" : "192k"]);
                    }
                }
                if (extension is ".mp4" or ".mov") args.AddRange(["-movflags", "+faststart"]);
            }
        }
        args.Add(output);
        return new EncodingCommand(args, extension, width, height, audioOnly);
    }
}
