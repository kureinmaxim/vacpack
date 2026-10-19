using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using Vacpack.Core;

namespace Vacpack.Windows;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<FileItem> files = [];
    private CancellationTokenSource? cancellation;
    private ToolLocator tools = new();
    private string? outputDirectory;
    private bool closeAfterCancellation;

    public MainWindow()
    {
        InitializeComponent();
        FileGrid.ItemsSource = files;
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"{version?.ToString(3)} · локальное сжатие";
        Refresh();
    }

    public void AddPaths(IEnumerable<string> paths)
    {
        if (cancellation is not null) return;
        try
        {
            var known = files.Select(file => file.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var added = 0;
            foreach (var path in MediaFiles.Collect(paths))
                if (known.Add(path)) { files.Add(new FileItem(path)); added++; }
            StatusText.Text = added == 0 ? "Поддерживаются JPEG, PNG, WebP, AVIF, TIFF, BMP, видео и GIF" : $"Добавлено файлов: {added}";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            StatusText.Text = "Не удалось добавить файлы: " + error.Message;
        }
        Refresh();
    }

    private void ChooseFiles(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Добавить файлы в Vacpack", Multiselect = true,
            Filter = "Фото, видео и GIF|*.jpg;*.jpeg;*.png;*.webp;*.avif;*.tif;*.tiff;*.bmp;*.mp4;*.mov;*.mkv;*.webm;*.avi;*.m4v;*.mpeg;*.mpg;*.mts;*.m2ts;*.wmv;*.gif|Все файлы|*.*"
        };
        if (dialog.ShowDialog(this) == true) AddPaths(dialog.FileNames);
    }

    private void ChooseFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Добавить папку с файлами" };
        if (dialog.ShowDialog(this) == true) AddPaths([dialog.FolderName]);
    }

    private void ChooseTools(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Папка, в которой лежат ffmpeg.exe и ffprobe.exe" };
        if (dialog.ShowDialog(this) != true) return;
        var selected = new ToolLocator([dialog.FolderName]);
        if (selected.Find("ffmpeg") is null || selected.Find("ffprobe") is null)
        {
            MessageBox.Show(this, "В папке должны находиться ffmpeg.exe и ffprobe.exe.", "Vacpack", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        tools = selected;
        Refresh();
    }

    private void ChooseOutput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Куда сохранить сжатые файлы" };
        if (dialog.ShowDialog(this) == true) { outputDirectory = dialog.FolderName; OutputText.Text = outputDirectory; }
    }
    private void ResetOutput(object sender, RoutedEventArgs e) { outputDirectory = null; OutputText.Text = "Рядом с исходником"; }
    private void ClearFiles(object sender, RoutedEventArgs e) { files.Clear(); StatusText.Text = "Добавьте файлы для сжатия"; Refresh(); }
    private void RetryFiles(object sender, RoutedEventArgs e) { foreach (var file in files) file.Reset(); Refresh(); }
    private void CancelJobs(object sender, RoutedEventArgs e) { cancellation?.Cancel(); CancelButton.IsEnabled = false; StatusText.Text = "Останавливаем обработку…"; }
    private async void StartCompression(object sender, RoutedEventArgs e) => await CompressAsync();

    public async Task CompressAsync()
    {
        if (cancellation is not null || tools.Find("ffmpeg") is null || tools.Find("ffprobe") is null) return;
        var jobs = files.Where(file => file.Ready).ToArray();
        if (jobs.Length == 0) return;
        var settings = new CompressionSettings
        {
            Quality = (Quality)QualityBox.SelectedIndex, ImageOutput = (ImageOutput)ImageFormatBox.SelectedIndex,
            VideoOutput = (VideoOutput)VideoFormatBox.SelectedIndex, MaxLongEdge = SelectedNumber(SizeBox),
            MaxVideoFps = SelectedNumber(VideoFpsBox), GifFps = SelectedNumber(GifFpsBox),
            RemoveAudio = RemoveAudioBox.IsChecked == true, SpeechAudio = SpeechBox.IsChecked == true,
            KeepFileDates = DatesBox.IsChecked == true, OutputDirectory = outputDirectory
        };
        using var source = new CancellationTokenSource();
        cancellation = source;
        Refresh();
        try
        {
            var engine = new CompressionEngine(tools);
            for (var index = 0; index < jobs.Length; index++)
            {
                if (source.IsCancellationRequested) break;
                var file = jobs[index];
                file.Start();
                StatusText.Text = $"Файл {index + 1} из {jobs.Length}: {file.Name}";
                try
                {
                    var progress = new Progress<double>(file.Report);
                    var result = await engine.CompressAsync(file.Path, settings, progress, source.Token);
                    file.Complete(result);
                }
                catch (OperationCanceledException) { file.Cancel(); break; }
                catch (Exception error) { file.Fail(error.Message); }
                RefreshSummary();
            }
            var errors = files.Count(file => file.Error is not null);
            StatusText.Text = source.IsCancellationRequested ? "Обработка остановлена. Исходники сохранены."
                : errors > 0 ? $"Обработка завершена. Ошибок: {errors}. Наведите на строку для деталей."
                : "Готово. Двойной щелчок по файлу откроет его папку.";
        }
        finally
        {
            cancellation = null;
            Refresh();
            if (closeAfterCancellation) Close();
        }
    }

    private static int SelectedNumber(ComboBox box) => int.Parse(((ComboBoxItem)box.SelectedItem).Tag.ToString()!, System.Globalization.CultureInfo.InvariantCulture);

    private void Refresh()
    {
        var busy = cancellation is not null;
        var ready = tools.Find("ffmpeg") is not null && tools.Find("ffprobe") is not null;
        ToolsBanner.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
        ToolsText.Text = "Для сжатия нужны ffmpeg.exe и ffprobe.exe. Выберите папку с ними или поместите их в tools рядом с приложением.";
        CountText.Text = files.Count == 0 ? "Ваши файлы" : $"Файлов: {files.Count}";
        EmptyState.Visibility = files.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        FileGrid.Visibility = files.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        SettingsPanel.IsEnabled = !busy;
        FileActions.IsEnabled = !busy;
        ClearButton.IsEnabled = !busy && files.Count > 0;
        RetryButton.IsEnabled = !busy && files.Any(file => !file.Ready);
        CompressButton.IsEnabled = !busy && ready && files.Any(file => file.Ready);
        CancelButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.IsEnabled = busy;
        RefreshSummary();
    }

    private void RefreshSummary()
    {
        var saved = files.Sum(file => file.Result?.SavedBytes ?? 0);
        var originals = files.Where(file => file.Result is not null).Sum(file => file.Result!.InputBytes);
        SummaryText.Text = originals == 0 ? "Всё остаётся на вашем компьютере"
            : $"Освободили {FileItem.FormatBytes(saved)} · {100.0 * saved / originals:0}%";
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = cancellation is null && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }
    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) AddPaths(paths);
        e.Handled = true;
    }
    private void FilesKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Delete || cancellation is not null) return;
        foreach (var file in FileGrid.SelectedItems.Cast<FileItem>().ToArray()) files.Remove(file);
        Refresh(); e.Handled = true;
    }
    private void OpenSelected(object sender, MouseButtonEventArgs e)
    {
        if (FileGrid.SelectedItem is not FileItem file) return;
        var path = file.Result?.Output ?? file.Path;
        if (!File.Exists(path)) { StatusText.Text = "Файл был перемещён или удалён."; return; }
        try
        {
            var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")) { UseShellExecute = false };
            start.ArgumentList.Add("/select,"); start.ArgumentList.Add(path);
            Process.Start(start)?.Dispose();
        }
        catch (Win32Exception error) { StatusText.Text = error.Message; }
    }
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (cancellation is null) return;
        // Finish process termination and temporary-file cleanup before exiting.
        e.Cancel = true; closeAfterCancellation = true; cancellation.Cancel();
    }
}
