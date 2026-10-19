using System.ComponentModel;
using System.IO;
using Vacpack.Core;

namespace Vacpack.Windows;

public sealed class FileItem(string path) : INotifyPropertyChanged
{
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Kind => MediaFiles.Detect(Path) switch { MediaKind.Image => "Фото", MediaKind.Video => "Видео", _ => "GIF" };
    public bool ShowImageIcon => MediaFiles.Detect(Path) == MediaKind.Image;
    public bool ShowTextIcon => !ShowImageIcon;
    public string KindIcon => MediaFiles.Detect(Path) switch { MediaKind.Image => "▧", MediaKind.Video => "▶", _ => "GIF" };
    public double KindIconSize => Kind == "GIF" ? 10 : 18;
    public string KindColor => Kind switch { "Фото" => "#3E7EB1", "Видео" => "#2D876C", _ => "#B77830" };
    public string KindBackground => Kind switch { "Фото" => "#EDF4FB", "Видео" => "#EAF5F0", _ => "#FFF4DF" };
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
    public string Status { get; private set; } = "В очереди";
    public string? Error { get; private set; }
    public string Details => Error ?? (Result is { KeptOriginal: true }
        ? "Результат оказался не меньше исходника. Оригинал сохранён.\n" + Path : Result?.Output ?? Path);
    public event PropertyChangedEventHandler? PropertyChanged;

    public void Reset()
    {
        Ready = true; IsRunning = false; Result = null; Progress = 0; Error = null; Status = "В очереди"; Changed();
    }
    public void SetLocked(bool locked) { CanRemove = !locked; Changed(); }
    public void Start() { Ready = false; IsRunning = true; Status = "Сжатие…"; Changed(); }
    public void Report(double value)
    {
        if (!IsRunning) return;
        Progress = value * 100; Status = $"Сжатие {Progress:0}%"; Changed();
    }
    public void Complete(CompressionResult result)
    {
        Result = result; Progress = 100; IsRunning = false;
        Status = result.KeptOriginal ? "Без уменьшения" : "Готово";
        Changed();
    }
    public void Fail(string message) { Error = message; IsRunning = false; Status = "Ошибка"; Changed(); }
    public void Cancel() { IsRunning = false; Status = "Отменено"; Changed(); }
    private void Changed() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(""));

    public static string FormatBytes(long bytes)
    {
        var value = (double)bytes;
        string[] units = ["Б", "КБ", "МБ", "ГБ"];
        var index = 0;
        while (value >= 1024 && index < units.Length - 1) { value /= 1024; index++; }
        return $"{value:0.#} {units[index]}";
    }
}
