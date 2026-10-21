using System.Globalization;
using System.Text.Json;

namespace Vacpack.Core;

public sealed record MediaInfo(int Width, int Height, double Duration, double Fps,
    long? VideoBitrate, bool HasAlpha, string Codec, string? AlphaDecoder,
    IReadOnlyList<string> AudioCodecs, bool IsHdr, double? AudioDuration = null)
{
    public static MediaInfo Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var streams = root.GetProperty("streams").EnumerateArray().ToArray();
        var video = streams.FirstOrDefault(stream => Text(stream, "codec_type") == "video"
            && (!stream.TryGetProperty("disposition", out var disposition) || Number(disposition, "attached_pic") != 1));
        if (video.ValueKind == JsonValueKind.Undefined) throw new InvalidDataException("В файле нет изображения или видеодорожки.");
        var width = (int)Number(video, "width");
        var height = (int)Number(video, "height");
        if (width <= 0 || height <= 0) throw new InvalidDataException("Не удалось определить размер изображения.");
        var sar = Rate(Text(video, "sample_aspect_ratio"));
        if (sar > 0) width = Math.Max(1, (int)Math.Round(width * sar));
        if (video.TryGetProperty("side_data_list", out var sides))
        {
            var rotation = sides.EnumerateArray().Select(side => Number(side, "rotation")).FirstOrDefault(value => value != 0);
            if (Math.Abs(rotation) % 180 == 90) (width, height) = (height, width);
        }
        root.TryGetProperty("format", out var format);
        var duration = Number(format, "duration");
        if (duration <= 0) duration = Number(video, "duration");
        var fps = Rate(Text(video, "avg_frame_rate"));
        if (fps <= 0) fps = Rate(Text(video, "r_frame_rate"));
        var audio = streams.Where(stream => Text(stream, "codec_type") == "audio").ToArray();
        var bitrate = Number(video, "bit_rate");
        if (bitrate <= 0 && Number(format, "bit_rate") is var total && total > 0)
            bitrate = total - audio.Sum(stream => Number(stream, "bit_rate") is var rate && rate > 0 ? rate : 128000);
        var pixel = Text(video, "pix_fmt") ?? "";
        var alphaMode = video.TryGetProperty("tags", out var tags) && Text(tags, "alpha_mode") == "1";
        var alpha = alphaMode || new[] { "yuva", "rgba", "bgra", "argb", "abgr", "gbrap", "ya8", "ya16", "pal8" }
            .Any(prefix => pixel.StartsWith(prefix, StringComparison.Ordinal));
        var codec = Text(video, "codec_name") ?? "unknown";
        var decoder = alphaMode ? codec switch { "vp9" => "libvpx-vp9", "vp8" => "libvpx", _ => null } : null;
        var hdr = Text(video, "color_transfer") is "smpte2084" or "arib-std-b67";
        var audioDuration = audio.Length > 0 ? Number(audio[0], "duration") : 0;
        return new MediaInfo(width, height, Math.Max(0, duration), fps, bitrate > 0 ? (long)bitrate : null,
            alpha, codec, decoder, audio.Select(stream => Text(stream, "codec_name") ?? "unknown").ToArray(), hdr,
            audioDuration > 0 ? audioDuration : null);
    }

    private static string? Text(JsonElement element, string property) => element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(property, out var value) ? value.ToString() : null;
    private static double Number(JsonElement element, string property) => double.TryParse(Text(element, property),
        NumberStyles.Float, CultureInfo.InvariantCulture, out var number) && double.IsFinite(number) ? number : 0;
    private static double Rate(string? value)
    {
        var parts = value?.Split('/', ':');
        return parts is { Length: 2 } && double.TryParse(parts[0], CultureInfo.InvariantCulture, out var numerator)
            && double.TryParse(parts[1], CultureInfo.InvariantCulture, out var denominator) && denominator > 0
            && double.IsFinite(numerator) ? numerator / denominator : 0;
    }
}
