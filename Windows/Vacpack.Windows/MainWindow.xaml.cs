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
    private bool initialized;
    private ThumbnailService thumbnails = new();
    private readonly Dictionary<FileItem, CancellationTokenSource> thumbnailJobs = [];

    public MainWindow()
    {
        InitializeComponent();
        LanguageBox.SelectedItem = LanguageBox.Items.Cast<ComboBoxItem>().First(item => (string)item.Tag == Loc.Language);
        initialized = true;
        FileGrid.ItemsSource = files;
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"{version?.ToString(3)} · Windows";
        Refresh();
    }

    public void AddPaths(IEnumerable<string> paths)
    {
        if (cancellation is not null) return;
        var requested = paths.ToArray();
        if (requested.Length == 0) return;
        try
        {
            var known = files.Select(file => file.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var added = 0;
            foreach (var path in MediaFiles.Collect(requested))
                if (known.Add(path))
                {
                    var file = new FileItem(path);
                    files.Add(file); added++;
                    _ = LoadThumbnailAsync(file);
                }
            StatusText.Text = added == 0 ? Loc.T("Поддерживаются JPEG, PNG, WebP, AVIF, TIFF, BMP, видео и GIF") : Loc.T("Добавлено файлов: {0}", added);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            StatusText.Text = Loc.T("Не удалось добавить файлы: ") + error.Message;
        }
        Refresh();
    }

    private void LanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!initialized || LanguageBox.SelectedItem is not ComboBoxItem { Tag: string choice } || choice == Loc.Language) return;
        Loc.Save(choice);
        if (MessageBox.Show(this, Loc.T("Перезапустить Vacpack, чтобы применить язык?"), "Vacpack", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        if (Environment.ProcessPath is { } executable) Process.Start(new ProcessStartInfo(executable) { UseShellExecute = false })?.Dispose();
        Close();
    }

    private void ChooseFiles(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = Loc.T("Добавить файлы в Vacpack"), Multiselect = true,
            Filter = Loc.T("Фото, видео и GIF") + "|*.jpg;*.jpeg;*.png;*.webp;*.avif;*.tif;*.tiff;*.bmp;*.mp4;*.mov;*.mkv;*.webm;*.avi;*.m4v;*.mpeg;*.mpg;*.mts;*.m2ts;*.wmv;*.gif|" + Loc.T("Все файлы") + "|*.*"
        };
        if (dialog.ShowDialog(this) == true) AddPaths(dialog.FileNames);
    }

    private void ChooseFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = Loc.T("Добавить папку с файлами") };
        if (dialog.ShowDialog(this) == true) AddPaths([dialog.FolderName]);
    }

    private void ChooseTools(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = Loc.T("Папка, в которой лежат ffmpeg.exe и ffprobe.exe") };
        if (dialog.ShowDialog(this) != true) return;
        var selected = new ToolLocator([dialog.FolderName]);
        if (selected.Find("ffmpeg") is null || selected.Find("ffprobe") is null)
        {
            MessageBox.Show(this, Loc.T("В папке должны находиться ffmpeg.exe и ffprobe.exe."), "Vacpack", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        tools = selected;
        thumbnails = new ThumbnailService(tools);
        foreach (var file in files.Where(file => !file.HasThumbnail).ToArray()) _ = LoadThumbnailAsync(file);
        Refresh();
    }

    private async Task LoadThumbnailAsync(FileItem file)
    {
        if (thumbnailJobs.ContainsKey(file)) return;
        using var source = new CancellationTokenSource();
        thumbnailJobs.Add(file, source);
        try
        {
            var thumbnail = await thumbnails.LoadAsync(file.Path, source.Token);
            if (thumbnail is not null && !source.IsCancellationRequested && files.Contains(file)) file.SetThumbnail(thumbnail);
        }
        catch (OperationCanceledException) { }
        finally { thumbnailJobs.Remove(file); }
    }

    public async Task WaitForThumbnailsAsync()
    {
        while (thumbnailJobs.Count > 0) await Task.Delay(25);
    }

    private void CancelThumbnail(FileItem file)
    {
        if (thumbnailJobs.TryGetValue(file, out var source)) source.Cancel();
    }

    protected override void OnClosed(EventArgs e)
    {
        foreach (var source in thumbnailJobs.Values.ToArray()) source.Cancel();
        thumbnails.ClearCache();
        base.OnClosed(e);
    }

    private void ChooseOutput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = Loc.T("Куда сохранить сжатые файлы") };
        if (dialog.ShowDialog(this) == true)
        {
            outputDirectory = dialog.FolderName;
            OutputText.Text = Path.GetFileName(outputDirectory.TrimEnd(Path.DirectorySeparatorChar)) is { Length: > 0 } name ? name : outputDirectory;
            OutputText.ToolTip = outputDirectory;
            ResetOutputButton.Visibility = Visibility.Visible;
        }
    }
    private void ResetOutput(object sender, RoutedEventArgs e)
    {
        outputDirectory = null; OutputText.Text = Loc.T("Рядом с исходником"); OutputText.ToolTip = null;
        ResetOutputButton.Visibility = Visibility.Collapsed;
    }
    private void ClearFiles(object sender, RoutedEventArgs e)
    {
        foreach (var file in files) CancelThumbnail(file);
        files.Clear(); thumbnails.ClearCache(); StatusText.Text = Loc.T("Добавьте файлы для сжатия"); Refresh();
    }
    private void CancelJobs(object sender, RoutedEventArgs e) { cancellation?.Cancel(); CancelButton.IsEnabled = false; StatusText.Text = Loc.T("Останавливаем обработку…"); }
    private async void StartCompression(object sender, RoutedEventArgs e)
    {
        if (cancellation is not null) return;
        if (!files.Any(file => file.Ready)) foreach (var file in files) file.Reset();
        await CompressAsync();
    }

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
        DropHint.Visibility = Visibility.Collapsed;
        Refresh();
        try
        {
            var engine = new CompressionEngine(tools);
            for (var index = 0; index < jobs.Length; index++)
            {
                if (source.IsCancellationRequested) break;
                var file = jobs[index];
                file.Start();
                StatusText.Text = Loc.T("Файл {0} из {1}: {2}", index + 1, jobs.Length, file.Name);
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
            StatusText.Text = source.IsCancellationRequested ? Loc.T("Обработка остановлена. Исходники сохранены.")
                : errors > 0 ? Loc.T("Обработка завершена. Ошибок: {0}. Нажмите «Подробнее» в строке файла.", errors)
                : Loc.T("Готово. Можно изменить настройки и сжать снова.");
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
        ToolsText.Text = Loc.T("Для сжатия нужны ffmpeg.exe и ffprobe.exe. Выберите папку с ними или поместите их в tools рядом с приложением.");
        CountText.Text = files.Count.ToString();
        EmptyState.Visibility = files.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        FileGrid.Visibility = files.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        SettingsPanel.IsEnabled = !busy;
        OutputPanel.IsEnabled = !busy;
        FileActions.IsEnabled = !busy;
        LanguageBox.IsEnabled = !busy;
        ClearButton.IsEnabled = !busy && files.Count > 0;
        foreach (var file in files) file.SetLocked(busy);
        var pending = files.Count(file => file.Ready);
        CompressButton.Content = files.Count == 0 ? Loc.T("Сжать файлы") : pending > 0 ? Loc.T("Сжать · {0}", pending) : Loc.T("Сжать снова");
        CompressButton.IsEnabled = !busy && ready && files.Count > 0;
        CompressButton.Visibility = busy ? Visibility.Collapsed : Visibility.Visible;
        CancelButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.IsEnabled = busy;
        QueueHint.Text = files.Count == 0 ? Loc.T("Фото, видео и GIF") : Loc.T("Всего {0} · исходники сохранятся", FileItem.FormatBytes(files.Sum(file => file.InputBytes)));
        RefreshContext();
        RefreshSummary();
    }

    private void SettingsChanged(object sender, SelectionChangedEventArgs e)
    {
        if (initialized) RefreshContext();
    }

    private void RefreshContext()
    {
        var empty = files.Count == 0;
        var images = files.Any(file => MediaFiles.Detect(file.Path) == MediaKind.Image);
        var videos = files.Any(file => MediaFiles.Detect(file.Path) == MediaKind.Video);
        var gifs = files.Any(file => MediaFiles.Detect(file.Path) == MediaKind.Gif);
        var audioOnly = VideoFormatBox.SelectedIndex >= (int)VideoOutput.M4a;
        var videoGif = VideoFormatBox.SelectedIndex == (int)VideoOutput.Gif;
        ImageOptions.Visibility = empty || images ? Visibility.Visible : Visibility.Collapsed;
        VideoOptions.Visibility = empty || videos ? Visibility.Visible : Visibility.Collapsed;
        SizeOptions.Visibility = !empty && videos && audioOnly && !images && !gifs ? Visibility.Collapsed : Visibility.Visible;
        var videoFps = videos && !audioOnly && !videoGif;
        var gifFps = gifs || videos && videoGif;
        VideoFpsOptions.Visibility = videoFps ? Visibility.Visible : Visibility.Collapsed;
        GifFpsOptions.Visibility = gifFps ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetColumn(GifFpsOptions, videoFps ? 2 : 0);
        Grid.SetColumnSpan(VideoFpsOptions, gifFps ? 1 : 3);
        Grid.SetColumnSpan(GifFpsOptions, videoFps ? 1 : 3);
        FpsOptions.Visibility = videoFps || gifFps ? Visibility.Visible : Visibility.Collapsed;
        RemoveAudioBox.Visibility = videos && !audioOnly && !videoGif ? Visibility.Visible : Visibility.Collapsed;
        SpeechBox.Visibility = videos && audioOnly ? Visibility.Visible : Visibility.Collapsed;
        var pngOnly = images && !videos && !gifs && (ImageFormatBox.SelectedIndex == (int)ImageOutput.Png
            || ImageFormatBox.SelectedIndex == 0 && files.All(file => Path.GetExtension(file.Path).Equals(".png", StringComparison.OrdinalIgnoreCase)));
        QualityHint.Text = pngOnly ? Loc.T("PNG: сжатие без потерь, качество не меняется") : new[]
        {
            Loc.T("Максимум деталей, больше размер"), Loc.T("Высокое качество с умеренным сжатием"), Loc.T("Баланс качества и размера"),
            Loc.T("Меньше размер, заметнее сжатие"), Loc.T("Минимальный размер, меньше деталей")
        }[Math.Clamp(QualityBox.SelectedIndex, 0, 4)];
        QualityBox.IsEnabled = !pngOnly;
    }

    private void RefreshSummary()
    {
        var saved = files.Sum(file => file.Result?.SavedBytes ?? 0);
        var originals = files.Where(file => file.Result is not null).Sum(file => file.Result!.InputBytes);
        SummaryText.Text = originals == 0 ? Loc.T("Исходники останутся на месте")
            : Loc.T("Сэкономлено {0}  ·  {1}%", FileItem.FormatBytes(saved), (100.0 * saved / originals).ToString("0"));
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = cancellation is null && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        DropHint.Visibility = e.Effects == DragDropEffects.Copy ? Visibility.Visible : Visibility.Collapsed;
        e.Handled = true;
    }
    private void OnDrop(object sender, DragEventArgs e)
    {
        DropHint.Visibility = Visibility.Collapsed;
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) AddPaths(paths);
        e.Handled = true;
    }
    private void FilesKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Delete || cancellation is not null) return;
        foreach (var file in FileGrid.SelectedItems.Cast<FileItem>().ToArray()) { CancelThumbnail(file); files.Remove(file); }
        Refresh(); e.Handled = true;
    }
    private void OpenSelected(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject element && IsInsideButton(element)) return;
        if (FileGrid.SelectedItem is FileItem file) OpenFolder(file);
    }

    private static bool IsInsideButton(DependencyObject element)
    {
        DependencyObject? current = element;
        while (current is not null)
        {
            if (current is Button) return true;
            current = current is System.Windows.Media.Visual ? System.Windows.Media.VisualTreeHelper.GetParent(current) : LogicalTreeHelper.GetParent(current);
        }
        return false;
    }

    private void OpenItemFolder(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FileItem file }) OpenFolder(file);
        e.Handled = true;
    }

    private void RemoveItem(object sender, RoutedEventArgs e)
    {
        if (cancellation is null && sender is FrameworkElement { DataContext: FileItem file }) { CancelThumbnail(file); files.Remove(file); Refresh(); }
        e.Handled = true;
    }

    private void ShowItemDetails(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FileItem file }) MessageBox.Show(this, file.Error ?? file.Details, file.Name, MessageBoxButton.OK, MessageBoxImage.Information);
        e.Handled = true;
    }

    private void OnDragLeave(object sender, DragEventArgs e)
    {
        var point = e.GetPosition(this);
        if (point.X <= 0 || point.Y <= 0 || point.X >= ActualWidth || point.Y >= ActualHeight) DropHint.Visibility = Visibility.Collapsed;
    }

    private void WindowKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && cancellation is not null) { CancelJobs(sender, e); e.Handled = true; }
        if (Keyboard.Modifiers != ModifierKeys.Control || cancellation is not null) return;
        if (e.Key == Key.O) { ChooseFiles(sender, e); e.Handled = true; }
        if (e.Key == Key.Enter && CompressButton.IsEnabled) { StartCompression(sender, e); e.Handled = true; }
    }

    private const string ProjectUrl = "https://github.com/kureinmaxim/vacpack";

    private void OpenProjectPage(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo(ProjectUrl) { UseShellExecute = true })?.Dispose(); }
        catch (Win32Exception error) { StatusText.Text = error.Message; }
    }

    private void OpenFolder(FileItem file)
    {
        var path = file.Result?.Output ?? file.Path;
        if (!File.Exists(path)) { StatusText.Text = Loc.T("Файл был перемещён или удалён."); return; }
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
