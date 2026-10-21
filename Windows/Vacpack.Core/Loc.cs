using System.Globalization;
using System.IO;
using System.Text.Json;

namespace Vacpack.Core;

/// <summary>
/// Interface language. The Russian text is the key (as a gettext msgid); English is the translation,
/// so a string that is missing from the table simply shows in Russian instead of failing.
/// English is the default, whatever the system language; the choice ("ru" or "en") is kept in
/// %LOCALAPPDATA%\Vacpack\settings.json and applied on the next start. VACPACK_LANG overrides it (used by tests and snapshots).
/// </summary>
public static class Loc
{
    private static string? language;

    public static string SettingsPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Vacpack", "settings.json");

    /// <summary>The language in use: "ru" or "en".</summary>
    public static string Language => language ??= Resolve(Environment.GetEnvironmentVariable("VACPACK_LANG") is { Length: > 0 } forced ? forced : Saved());

    /// <summary>What the user picked: "ru" or "en" (English when nothing is saved).</summary>
    public static string Saved()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return "en";
            using var document = JsonDocument.Parse(File.ReadAllText(SettingsPath));
            return document.RootElement.TryGetProperty("language", out var value) && value.GetString() is "ru" ? "ru" : "en";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return "en"; }
    }

    public static void Save(string choice)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(new { language = choice == "ru" ? "ru" : "en" }));
    }

    /// <summary>Forces a language for this process (tests).</summary>
    public static void Use(string choice) => language = Resolve(choice);

    private static string Resolve(string choice) => choice == "ru" ? "ru" : "en";

    public static string T(string russian) => Language == "ru" ? russian : English.GetValueOrDefault(russian, russian);

    public static string T(string russian, params object[] arguments) => string.Format(CultureInfo.CurrentCulture, T(russian), arguments);

    public static bool Has(string russian) => English.ContainsKey(russian);

    private static readonly Dictionary<string, string> English = new()
    {
        // Engine and tools
        ["Этот тип файла пока не поддерживается."] = "This file type is not supported yet.",
        ["Кодер создал пустой файл."] = "The encoder produced an empty file.",
        ["Исходный файл изменился во время сжатия. Добавьте его заново."] = "The source file changed during compression. Add it again.",
        ["Не удалось прочитать файл: "] = "Could not read the file: ",
        ["В результате отсутствует звуковая дорожка."] = "The result has no audio track.",
        ["Звуковой файл короче исходного видео."] = "The audio file is shorter than the source video.",
        ["Размер результата не совпадает с ожидаемым."] = "The result size does not match what was expected.",
        ["Продолжительность результата отличается от исходного файла."] = "The result's duration differs from the source.",
        ["Кодер не сохранил прозрачность."] = "The encoder did not keep transparency.",
        ["Неизвестная настройка сжатия."] = "Unknown compression setting.",
        ["Проверьте размеры и частоту кадров."] = "Check the sizes and frame rates.",
        ["Размер видео слишком мал для выбранного кодека."] = "The video is too small for the chosen codec.",
        ["HDR-видео пока не поддерживается в Windows-версии: требуется отдельное преобразование цвета."] = "HDR video is not supported in the Windows version yet: it needs a separate colour conversion.",
        ["Анимированный PNG пока не поддерживается."] = "Animated PNG is not supported yet.",
        ["Для видео с прозрачностью выберите WebM."] = "Choose WebM for video with transparency.",
        ["В видео нет звуковой дорожки."] = "The video has no audio track.",
        ["Этот формат изображения пока не поддерживается."] = "This image format is not supported yet.",
        ["Для изображения с прозрачностью выберите PNG или WebP."] = "Choose PNG or WebP for an image with transparency.",
        ["В файле нет изображения или видеодорожки."] = "The file has no image or video track.",
        ["Не удалось определить размер изображения."] = "Could not determine the image size.",
        ["Обработка заняла слишком много времени и остановлена."] = "Processing took too long and was stopped.",
        ["Не найден {0}.exe. Поместите FFmpeg и ffprobe в папку tools рядом с приложением или добавьте их в PATH."] = "{0}.exe not found. Put FFmpeg and ffprobe in the tools folder next to the app or add them to PATH.",

        // Units and file kinds
        ["Б"] = "B", ["КБ"] = "KB", ["МБ"] = "MB", ["ГБ"] = "GB",
        ["Фото"] = "Photo", ["Видео"] = "Video",

        // Queue row status
        ["В очереди"] = "Queued", ["Сжатие…"] = "Compressing…", ["Сжатие {0}%"] = "Compressing {0}%",
        ["Без уменьшения"] = "Not smaller", ["Готово"] = "Done", ["Ошибка"] = "Error", ["Отменено"] = "Cancelled",
        ["Результат оказался не меньше исходника. Оригинал сохранён.\n"] = "The result was not smaller than the original. The original is kept.\n",

        // Window: messages and dialogs
        ["Поддерживаются JPEG, PNG, WebP, AVIF, TIFF, BMP, видео и GIF"] = "JPEG, PNG, WebP, AVIF, TIFF, BMP, video and GIF are supported",
        ["Добавлено файлов: {0}"] = "Files added: {0}",
        ["Не удалось добавить файлы: "] = "Could not add the files: ",
        ["Добавить файлы в Vacpack"] = "Add files to Vacpack",
        ["Фото, видео и GIF"] = "Photos, videos and GIFs",
        ["Все файлы"] = "All files",
        ["Добавить папку с файлами"] = "Add a folder of files",
        ["Папка, в которой лежат ffmpeg.exe и ffprobe.exe"] = "The folder containing ffmpeg.exe and ffprobe.exe",
        ["В папке должны находиться ffmpeg.exe и ffprobe.exe."] = "The folder must contain ffmpeg.exe and ffprobe.exe.",
        ["Куда сохранить сжатые файлы"] = "Where to save the compressed files",
        ["Рядом с исходником"] = "Next to the original",
        ["Добавьте файлы для сжатия"] = "Add files to compress",
        ["Останавливаем обработку…"] = "Stopping…",
        ["Файл {0} из {1}: {2}"] = "File {0} of {1}: {2}",
        ["Обработка остановлена. Исходники сохранены."] = "Stopped. Originals are kept.",
        ["Обработка завершена. Ошибок: {0}. Нажмите «Подробнее» в строке файла."] = "Finished. Errors: {0}. Click “Details” on the file's row.",
        ["Готово. Можно изменить настройки и сжать снова."] = "Done. You can change the settings and compress again.",
        ["Для сжатия нужны ffmpeg.exe и ffprobe.exe. Выберите папку с ними или поместите их в tools рядом с приложением."] = "ffmpeg.exe and ffprobe.exe are needed for compression. Choose the folder that has them or put them in tools next to the app.",
        ["Сжать · {0}"] = "Compress · {0}",
        ["Сжать снова"] = "Compress again",
        ["Всего {0} · исходники сохранятся"] = "Total {0} · originals are kept",
        ["PNG: сжатие без потерь, качество не меняется"] = "PNG: lossless, quality does not change",
        ["Максимум деталей, больше размер"] = "Most detail, larger size",
        ["Высокое качество с умеренным сжатием"] = "High quality, moderate compression",
        ["Меньше размер, заметнее сжатие"] = "Smaller size, visible compression",
        ["Минимальный размер, меньше деталей"] = "Smallest size, less detail",
        ["Исходники останутся на месте"] = "Originals stay where they are",
        ["Сэкономлено {0}  ·  {1}%"] = "Saved {0}  ·  {1}%",
        ["Файл был перемещён или удалён."] = "The file was moved or deleted.",
        ["Перезапустить Vacpack, чтобы применить язык?"] = "Restart Vacpack to apply the language?",

        // Window: layout
        ["Экспериментальная версия"] = "Experimental version",
        ["Сжатие фото, видео и GIF"] = "Photo, video and GIF compression",
        ["Разработчик: Kurein M.N. · "] = "Developer: Kurein M.N. · ",
        ["Открыть страницу проекта на GitHub"] = "Open the project page on GitHub",
        ["Страница проекта на GitHub"] = "Project page on GitHub",
        ["Язык"] = "Language",
        ["Указать папку…"] = "Choose folder…",
        ["Файлы"] = "Files",
        ["+  Добавить файлы"] = "+  Add files",
        ["Добавить файлы (Ctrl+O)"] = "Add files (Ctrl+O)",
        ["Папку…"] = "Folder…",
        ["Очистить список"] = "Clear the list",
        ["Имя файла"] = "File name", ["Размер"] = "Size", ["Результат"] = "Result",
        ["Подробнее"] = "Details",
        ["Показать файл в папке"] = "Show the file in its folder",
        ["Убрать из списка"] = "Remove from the list",
        ["Убрать файл из списка"] = "Remove the file from the list",
        ["Перетащите файлы сюда"] = "Drop files here",
        ["Фото, видео, GIF или папку целиком"] = "Photos, videos, GIFs or a whole folder",
        ["Выбрать файлы…"] = "Choose files…",
        ["Исходники сохранятся. Обработка — на вашем компьютере."] = "Originals are kept. Everything is processed on your computer.",
        ["Отпустите, чтобы добавить файлы"] = "Release to add the files",
        ["Можно добавлять файлы и папки"] = "You can add files and folders",
        ["Delete — убрать из списка"] = "Delete — remove from the list",
        ["Настройки"] = "Settings",
        ["Применяются ко всей очереди"] = "Applied to the whole queue",
        ["Качество"] = "Quality",
        ["Наивысшее"] = "Highest", ["Высокое"] = "High", ["Хорошее"] = "Good", ["Среднее"] = "Medium", ["Приемлемое"] = "Acceptable",
        ["Баланс качества и размера"] = "Balance of quality and size",
        ["Формат фото"] = "Photo format",
        ["Как в исходнике"] = "Same as the original",
        ["PNG · без потерь"] = "PNG · lossless",
        ["Формат видео"] = "Video format",
        ["Звук · M4A"] = "Sound · M4A", ["Звук · MP3"] = "Sound · MP3", ["Звук · Opus"] = "Sound · Opus",
        ["Длинная сторона"] = "Long side",
        ["Исходный размер"] = "Original size",
        ["Не более 3840 px"] = "At most 3840 px", ["Не более 2560 px"] = "At most 2560 px", ["Не более 1920 px"] = "At most 1920 px",
        ["Не более 1280 px"] = "At most 1280 px", ["Не более 800 px"] = "At most 800 px",
        ["Кадров/с, видео"] = "Frames/s, video", ["Кадров/с, GIF"] = "Frames/s, GIF", ["Исходная"] = "Original",
        ["Частота кадров видео"] = "Video frame rate", ["Частота кадров GIF"] = "GIF frame rate",
        ["Убрать звук из видео"] = "Remove sound from videos",
        ["Речь / подкаст"] = "Speech / podcast",
        ["Для звуковых файлов: моно, выравнивание громкости и низкий битрейт"] = "For sound files: mono, even loudness and a low bitrate",
        ["Дополнительно"] = "Advanced",
        ["Сохранить даты файлов"] = "Keep file dates",
        ["Размеры и частота кадров только уменьшаются. PNG сжимается без потерь."] = "Sizes and frame rates only go down. PNG is compressed losslessly.",
        ["Сохранить"] = "Save",
        ["Отдельный файл, без перезаписи"] = "A separate file, nothing overwritten",
        ["Выбрать папку"] = "Choose a folder",
        ["Выбрать папку вывода"] = "Choose the output folder",
        ["Вернуть папку исходника"] = "Use the original's folder",
        ["Сохраним результат, только если файл станет меньше"] = "The result is saved only if the file gets smaller",
        ["Остановить"] = "Stop",
        ["Сжать файлы"] = "Compress files",
        ["Запустить сжатие (Ctrl+Enter)"] = "Start compression (Ctrl+Enter)",
    };
}
