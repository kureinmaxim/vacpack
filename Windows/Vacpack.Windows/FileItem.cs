using System.ComponentModel;
using System.IO;
using Vacpack.Core;

namespace Vacpack.Windows;

public sealed class FileItem(string path) : INotifyPropertyChanged
{
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Kind => MediaFiles.Detect(Path) switch { MediaKind.Image => "Фото", MediaKind.Video => "Видео", _ => "GIF" };
    public long InputBytes { get; } = new FileInfo(path).Length;
    public string InputSize => FormatBytes(InputBytes);
    public string OutputSize => Result is { KeptOriginal: false } result ? FormatBytes(result.OutputBytes) : "—";
    public string Saved => Result is { SavedBytes: > 0 } result ? $"−{100.0 * result.SavedBytes / result.InputBytes:0}%" : "—";
    public CompressionResult? Result { get; private set; }
    public bool Ready { get; private set; } = true;
    public double Progress { get; private set; }
    public string Status { get; private set; } = "Готов к сжатию";
    public string? Error { get; private set; }
    public string Details => Error ?? Result?.Output ?? Path;
    public event PropertyChangedEventHandler? PropertyChanged;

    public void Reset()
    {
        Ready = true; Result = null; Progress = 0; Error = null; Status = "Готов к сжатию"; Changed();
    }
    public void Start() { Ready = false; Status = "Сжимаем…"; Changed(); }
    public void Report(double value)
    {
        if (Result is not null || Error is not null || Status == "Отменено") return;
        Progress = value * 100; Status = $"Сжимаем… {Progress:0}%"; Changed();
    }
    public void Complete(CompressionResult result)
    {
        Result = result; Progress = 100;
        Status = result.KeptOriginal ? "Без уменьшения" : "Готово";
        Changed();
    }
    public void Fail(string message) { Error = message; Status = "Ошибка — наведите для деталей"; Changed(); }
    public void Cancel() { Status = "Отменено"; Changed(); }
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
