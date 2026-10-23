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
    // Experimental codecs: CRF (SVT-AV1, x265) or QP (vvenc) per quality level; higher = smaller.
    private static readonly int[] Av1Crf = [26, 32, 38, 44, 50];
    private static readonly int[] HevcCrf = [20, 24, 28, 32, 36];
    private static readonly int[] VvcQp = [26, 30, 34, 38, 42];

    /// <summary>Below this a video stream is not worth encoding: a target size that needs less is refused.</summary>
    public const int MinVideoKbps = 20;

    public static string Extension(string input, MediaKind kind, CompressionSettings settings)
    {
        if (kind == MediaKind.Gif) return ".gif";
        if (kind == MediaKind.Image)
            return settings.ImageOutput switch
            {
                ImageOutput.Jpeg => ".jpg", ImageOutput.Png => ".png", ImageOutput.WebP => ".webp",
                ImageOutput.Avif => ".avif", _ => Path.GetExtension(input).ToLowerInvariant()
            };
        var source = Path.GetExtension(input).ToLowerInvariant();
        if (settings.VideoCodec != VideoCodec.Default && settings.VideoOutput is VideoOutput.Original or VideoOutput.Mp4 or VideoOutput.WebM)
        {
            // AV1 goes into WebM; HEVC and H.266 do not, and VVC is safest in Matroska.
            if (settings.VideoOutput == VideoOutput.WebM)
                return settings.VideoCodec == VideoCodec.Av1 ? ".webm"
                    : throw new NotSupportedException(Loc.T("HEVC и H.266 нельзя положить в WebM: выберите MP4 или «Как в исходнике»."));
            if (settings.VideoCodec == VideoCodec.Vvc || source == ".mkv") return ".mkv";
            return ".mp4";
        }
        return settings.VideoOutput switch
        {
            VideoOutput.Mp4 => ".mp4", VideoOutput.WebM => ".webm", VideoOutput.Gif => ".gif",
            VideoOutput.M4a => ".m4a", VideoOutput.Mp3 => ".mp3", VideoOutput.Opus => ".opus",
            _ => source is ".mov" or ".mkv" or ".webm" ? source : ".mp4"
        };
    }

    public static (int Width, int Height) TargetSize(MediaInfo info, int maxLongEdge, bool even)
    {
        var ratio = maxLongEdge > 0 ? Math.Min(1.0, (double)maxLongEdge / Math.Max(info.Width, info.Height)) : 1.0;
        var width = Math.Max(1, (int)Math.Floor(info.Width * ratio));
        var height = Math.Max(1, (int)Math.Floor(info.Height * ratio));
        if (even)
        {
            width -= width % 2; height -= height % 2;
            if (width < 2 || height < 2) throw new InvalidDataException(Loc.T("Размер видео слишком мал для выбранного кодека."));
        }
        return (width, height);
    }

    /// <summary>
    /// What happens to the first audio track in the strong-compression modes, or null when the usual
    /// rules apply: an explicit bitrate, or, with a target size, a small share of the budget.
    /// </summary>
    public static (int Kbps, bool Mono)? AudioPlan(MediaInfo info, CompressionSettings settings)
    {
        if (settings.RemoveAudio || info.AudioCodecs.Count == 0) return null;
        if (settings.AudioKbps > 0) return (settings.AudioKbps, settings.MonoAudio || settings.AudioKbps <= 32);
        if (settings.TargetSizeMb > 0 && info.Duration > 0)
        {
            // About 8% of the whole budget, in steps of 8, between 16 and 96 kbit/s.
            var total = settings.TargetSizeMb * 1024 * 1024 * 8 / info.Duration / 1000;
            var kbps = (int)Math.Clamp(Math.Round(total * .08 / 8) * 8, 16, 96);
            return (kbps, settings.MonoAudio || kbps <= 32);
        }
        return settings.MonoAudio ? (64, true) : null;
    }

    /// <summary>
    /// The video bitrate (kbit/s) for the first try at a target size, or null when no target is set.
    /// It leaves room for the audio and the container, and starts a little low: rate control tends
    /// to overshoot at small bitrates, and a second try costs more than a smaller file.
    /// </summary>
    public static int? TargetVideoKbps(MediaInfo info, CompressionSettings settings)
    {
        if (settings.TargetSizeMb <= 0) return null;
        if (info.Duration <= 0) throw new NotSupportedException(Loc.T("Не удалось определить длительность: целевой размер недоступен."));
        var audio = AudioPlan(info, settings)?.Kbps ?? 0;
        var total = settings.TargetSizeMb * 1024 * 1024 * 8 * .95 / info.Duration / 1000;
        var video = (int)Math.Floor((total - audio) * .92);
        if (video < MinVideoKbps) throw TooSmall(info, audio);
        return video;
    }

    /// <summary>
    /// The next bitrate after a try that came out at <paramref name="actualBytes"/>. Encoders overshoot
    /// by more than the bitrate ratio at small bitrates, so the correction is steeper than the ratio.
    /// </summary>
    public static int NextVideoKbps(MediaInfo info, CompressionSettings settings, int kbps, long actualBytes)
    {
        var targetBytes = settings.TargetSizeMb * 1024 * 1024;
        var next = (int)Math.Floor(kbps * Math.Pow(targetBytes / actualBytes, 1.25) * .94);
        if (next < MinVideoKbps) throw TooSmall(info, AudioPlan(info, settings)?.Kbps ?? 0);
        return next;
    }

    private static InvalidDataException TooSmall(MediaInfo info, int audioKbps)
    {
        var needed = (MinVideoKbps + audioKbps) * info.Duration / 8 / 1024 / .95;
        return new InvalidDataException(Loc.T("Целевой размер слишком мал для {0} с видео: нужно хотя бы {1} МБ.",
            Math.Round(info.Duration).ToString("0", CultureInfo.CurrentCulture), Math.Max(0.1, Math.Ceiling(needed * 10) / 10).ToString("0.#", CultureInfo.CurrentCulture)));
    }

    public static EncodingCommand Build(string input, string output, MediaKind kind, MediaInfo info, CompressionSettings settings,
        int? targetVideoKbps = null)
    {
        settings.Validate();
        var extension = Extension(input, kind, settings);
        var audioOnly = kind == MediaKind.Video && settings.VideoOutput is VideoOutput.M4a or VideoOutput.Mp3 or VideoOutput.Opus;
        var gif = extension == ".gif";
        if (info.IsHdr && kind == MediaKind.Video && !audioOnly)
            throw new NotSupportedException(Loc.T("HDR-видео пока не поддерживается в Windows-версии: требуется отдельное преобразование цвета."));
        if (info.Codec == "apng") throw new NotSupportedException(Loc.T("Анимированный PNG пока не поддерживается."));
        if (info.HasAlpha && kind == MediaKind.Video && !audioOnly && !gif && extension != ".webm")
            throw new NotSupportedException(Loc.T("Для видео с прозрачностью выберите WebM."));
        var experimental = kind == MediaKind.Video && !audioOnly && !gif && settings.VideoCodec != VideoCodec.Default;
        if (experimental && info.HasAlpha)
            throw new NotSupportedException(Loc.T("Прозрачность сохраняет только WebM со стандартным кодеком (VP9)."));
        var (width, height) = TargetSize(info, settings.MaxLongEdge, kind == MediaKind.Video && !gif && !audioOnly);
        var q = (int)settings.Quality;
        var args = new List<string> { "-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-progress", "pipe:1", "-nostats" };
        if (info.AlphaDecoder is not null) args.AddRange(["-c:v", info.AlphaDecoder]);
        args.AddRange(["-i", input]);
        if (audioOnly)
        {
            if (info.AudioCodecs.Count == 0) throw new InvalidDataException(Loc.T("В видео нет звуковой дорожки."));
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
                    _ => throw new NotSupportedException(Loc.T("Этот формат изображения пока не поддерживается."))
                });
                if (info.HasAlpha && extension == ".avif")
                    throw new NotSupportedException(Loc.T("Для изображения с прозрачностью выберите PNG или WebP."));
                if (extension != ".avif") args.AddRange(["-update", "1"]);
            }
            else
            {
                // Strong compression, step by step: what the eye misses least goes first.
                if (settings.Denoise) filters.Add("hqdn3d=3:2:6:4");
                if (settings.Grayscale) filters.Add("hue=s=0");
                if (settings.DropDuplicateFrames) filters.Add("mpdecimate");
                var audio = AudioPlan(info, settings);
                args.AddRange(["-map", "0:V:0", "-vf", string.Join(',', filters), "-map_metadata", "0", "-sn", "-dn"]);
                if (settings.DropDuplicateFrames) args.AddRange(["-fps_mode", "vfr"]); // dropped frames must not be filled in again
                if (settings.RemoveAudio) args.Add("-an");
                else args.AddRange(["-map", audio is null ? "0:a?" : "0:a:0?"]);
                args.AddRange(VideoCodecArguments(extension, settings.VideoCodec, q, info, targetVideoKbps));
                if (info.HasAlpha && extension == ".webm") args.AddRange(["-auto-alt-ref", "0"]);
                if (!settings.RemoveAudio)
                {
                    if (audio is { } plan)
                    {
                        // Opus holds up best at small bitrates; speech mode suits them.
                        args.AddRange(["-c:a", "libopus", "-b:a", $"{plan.Kbps}k"]);
                        if (plan.Mono) args.AddRange(["-ac", "1"]);
                        if (plan.Kbps <= 24) args.AddRange(["-application", "voip"]);
                    }
                    else
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

    /// <summary>The video encoder and its rate control: constant quality, or a bitrate when a target size is set.</summary>
    private static List<string> VideoCodecArguments(string extension, VideoCodec codec, int q, MediaInfo info, int? kbps)
    {
        string K(double value) => ((int)Math.Max(1, Math.Round(value))).ToString(CultureInfo.InvariantCulture) + "k";
        var args = new List<string>();
        switch (codec)
        {
            case VideoCodec.Av1:
                args.AddRange(["-c:v", "libsvtav1", "-preset", "6", "-g", "240", "-pix_fmt", "yuv420p"]);
                args.AddRange(kbps is { } av1 ? ["-b:v", K(av1)] : ["-crf", Av1Crf[q].ToString(CultureInfo.InvariantCulture)]);
                break;
            case VideoCodec.Hevc:
                args.AddRange(["-c:v", "libx265", "-preset", "medium", "-pix_fmt", "yuv420p", "-x265-params", "log-level=error"]);
                if (extension is ".mp4" or ".mov") args.AddRange(["-tag:v", "hvc1"]); // Apple players want this tag
                args.AddRange(kbps is { } hevc ? ["-b:v", K(hevc), "-maxrate", K(hevc * 1.2), "-bufsize", K(hevc * 2)]
                    : ["-crf", HevcCrf[q].ToString(CultureInfo.InvariantCulture)]);
                break;
            case VideoCodec.Vvc:
                // vvenc takes only 10-bit input.
                args.AddRange(["-c:v", "libvvenc", "-preset", "medium", "-pix_fmt", "yuv420p10le"]);
                args.AddRange(kbps is { } vvc ? ["-b:v", K(vvc)] : ["-qp", VvcQp[q].ToString(CultureInfo.InvariantCulture)]);
                break;
            default:
                if (extension == ".webm")
                {
                    args.AddRange(["-c:v", "libvpx-vp9"]);
                    if (kbps is { } vp9) args.AddRange(["-b:v", K(vp9)]);
                    else args.AddRange(["-crf", Vp9[q].ToString(CultureInfo.InvariantCulture), "-b:v", Cap(info, q) ?? "0"]);
                    args.AddRange(["-row-mt", "1", "-cpu-used", "4", "-pix_fmt", info.HasAlpha ? "yuva420p" : "yuv420p"]);
                }
                else
                {
                    args.AddRange(["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p"]);
                    if (kbps is { } x264) args.AddRange(["-b:v", K(x264), "-maxrate", K(x264 * 1.25), "-bufsize", K(x264 * 2)]);
                    else
                    {
                        args.AddRange(["-crf", X264[q].ToString(CultureInfo.InvariantCulture)]);
                        // Never let a re-encode come out bigger than the source: cap the bitrate below it.
                        if (Cap(info, q) is { } cap) args.AddRange(["-maxrate", cap, "-bufsize", cap]);
                    }
                }
                break;
        }
        return args;
    }

    private static string? Cap(MediaInfo info, int q) => info.VideoBitrate is > 0
        ? Math.Max(1, (long)(info.VideoBitrate.Value * SourceShare[q]) / 1000).ToString(CultureInfo.InvariantCulture) + "k" : null;
}
