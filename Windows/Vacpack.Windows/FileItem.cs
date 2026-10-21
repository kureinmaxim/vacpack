using System.ComponentModel;
using System.IO;
using System.Windows.Media.Imaging;
using Vacpack.Core;

namespace Vacpack.Windows;

public sealed class FileItem(string path) : INotifyPropertyChanged
{
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Kind => MediaFiles.Detect(Path) switch { MediaKind.Image => Loc.T("Фото"), MediaKind.Video => Loc.T("Видео"), _ => "GIF" };
    public BitmapSource? Thumbnail { get; private set; }
    public bool HasThumbnail => Thumbnail is not null;
    public bool ShowImageIcon => !HasThumbnail && MediaFiles.Detect(Path) == MediaKind.Image;
    public bool ShowTextIcon => !HasThumbnail && MediaFiles.Detect(Path) != MediaKind.Image;
    public bool ShowThumbnailBadge => MediaFiles.Detect(Path) is MediaKind.Video or MediaKind.Gif;
    public string ThumbnailBadge => MediaFiles.Detect(Path) == MediaKind.Video ? "▶" : "GIF";
    public string KindIcon => MediaFiles.Detect(Path) switch { MediaKind.Image => "▧", MediaKind.Video => "▶", _ => "GIF" };
    public double KindIconSize => MediaFiles.Detect(Path) is MediaKind.Image or MediaKind.Video ? 18 : 10;
    public string KindColor => MediaFiles.Detect(Path) switch { MediaKind.Image => "#3E7EB1", MediaKind.Video => "#2D876C", _ => "#B77830" };
    public string KindBackground => MediaFiles.Detect(Path) switch { MediaKind.Image => "#EDF4FB", MediaKind.Video => "#EAF5F0", _ => "#FFF4DF" };
    public string Description => Kind + " · " + System.IO.Path.GetExtension(Path).TrimStart('.').ToUpperInvariant()
        + (Result?.Output is { } output && !string.Equals(System.IO.Path.GetExtension(Path), System.IO.Path.GetExtension(output), StringComparison.OrdinalIgnoreCase)
            ? " → " + System.IO.Path.GetExtension(output).TrimStart('.').ToUpperInvariant() : "");
    public long InputBytes { get; } = new FileInfo(path).Length;
    public string InputSize => FormatBytes(InputBytes);
    public string OutputSize => Result is { } result ? FormatBytes(result.OutputBytes) : "—";
    public string Saved => Result is { SavedBytes: > 0 } result ? $"−{100.0 * result.SavedBytes / result.InputBytes:0}%" : "0%";
    public CompressionResult? Result { get; private set; }
    public bool Ready { get; private set; } = true;
    public bool IsRunning { get; private set; }
    public bool CanRemove { get; private set; } = true;
    public bool HasResult => Result is not null;
    public bool HasError => Error is not null;
    public string StatusColor => HasError ? "#AF4038" : IsRunning ? "#8C6314" : Result is { SavedBytes: > 0 } ? "#267457" : "#68717E";
    public string StatusBackground => HasError ? "#FBEDEB" : IsRunning ? "#FFF3D5" : Result is { SavedBytes: > 0 } ? "#E8F5EE" : "#F0F2F5";
    public double Progress { get; private set; }
    public string Status { get; private set; } = Loc.T("В очереди");
    public string? Error { get; private set; }
    public string Details => Error ?? (Result is { KeptOriginal: true }
        ? Loc.T("Результат оказался не меньше исходника. Оригинал сохранён.\n") + Path : Result?.Output ?? Path);
    public event PropertyChangedEventHandler? PropertyChanged;

    public void SetThumbnail(BitmapSource thumbnail) { Thumbnail = thumbnail; Changed(); }

    public void Reset()
    {
        Ready = true; IsRunning = false; Result = null; Progress = 0; Error = null; Status = Loc.T("В очереди"); Changed();
    }
    public void SetLocked(bool locked) { CanRemove = !locked; Changed(); }
    public void Start() { Ready = false; IsRunning = true; Status = Loc.T("Сжатие…"); Changed(); }
    public void Report(double value)
    {
        if (!IsRunning) return;
        Progress = value * 100; Status = Loc.T("Сжатие {0}%", Progress.ToString("0")); Changed();
    }
    public void Complete(CompressionResult result)
    {
        Result = result; Progress = 100; IsRunning = false;
        Status = result.KeptOriginal ? Loc.T("Без уменьшения") : Loc.T("Готово");
        Changed();
    }
    public void Fail(string message) { Error = message; IsRunning = false; Status = Loc.T("Ошибка"); Changed(); }
    public void Cancel() { IsRunning = false; Status = Loc.T("Отменено"); Changed(); }
    private void Changed() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(""));

    public static string FormatBytes(long bytes)
    {
        var value = (double)bytes;
        string[] units = [Loc.T("Б"), Loc.T("КБ"), Loc.T("МБ"), Loc.T("ГБ")];
        var index = 0;
        while (value >= 1024 && index < units.Length - 1) { value /= 1024; index++; }
        return $"{value:0.#} {units[index]}";
    }
}
