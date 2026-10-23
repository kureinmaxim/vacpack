using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Vacpack.Core;

/// <summary>
/// Turns what a failed FFmpeg run left behind (exit code and its last words) into a short explanation
/// for the user: what happened, up to three things to try, and the technical line.
/// </summary>
public static class FfmpegErrors
{
    public static string LogPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Vacpack", "logs", "last-error.txt");

    /// <summary>The exit code as Windows writes it: 0xC0000005 rather than -1073741819.</summary>
    public static string Code(int exitCode) => exitCode < 0 ? "0x" + ((uint)exitCode).ToString("X8", CultureInfo.InvariantCulture)
        : exitCode.ToString(CultureInfo.InvariantCulture);

    public static string Explain(int exitCode, string stderr, string? logPath = null)
    {
        var lines = stderr.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(line => line.Trim()).ToArray();
        var text = string.Join('\n', lines);
        var (summary, tips) = Classify(exitCode, text);
        var message = new StringBuilder(summary);
        message.Append("\n\n").Append(Loc.T("Что попробовать:"));
        foreach (var tip in tips) message.Append("\n• ").Append(tip);
        message.Append("\n\n").Append(Loc.T("FFmpeg (код {0}):", Code(exitCode))).Append(' ');
        message.Append(lines.Length == 0 ? Loc.T("сообщений нет") : string.Join(" / ", lines.TakeLast(2)));
        if (logPath is not null) message.Append('\n').Append(Loc.T("Подробности: {0}", logPath));
        return message.ToString();
    }

    private static (string Summary, string[] Tips) Classify(int exitCode, string text)
    {
        var standard = Loc.T("Попробуйте то же видео без «Сильного сжатия» и со стандартным кодеком.");
        if (Regex.Match(text, @"Unknown encoder '([^']+)'|Encoder ([\w.-]+) not found", RegexOptions.IgnoreCase) is { Success: true } encoder)
            return (Loc.T("В этой сборке FFmpeg нет нужного кодера ({0}).", encoder.Groups[1].Success ? encoder.Groups[1].Value : encoder.Groups[2].Value),
                [Loc.T("Выберите «Стандартный» видеокодек."), Loc.T("Или поставьте полную сборку FFmpeg (gyan.dev, «full») и укажите её папку.")]);
        if (Has(text, "No space left on device", "not enough space", "disk full"))
            return (Loc.T("Не хватает места на диске для результата."),
                [Loc.T("Освободите место или выберите другую папку сохранения (кнопка с папкой справа внизу).")]);
        if (Has(text, "Permission denied", "Access is denied", "Read-only file system"))
            return (Loc.T("Нет доступа к папке, куда нужно записать результат."),
                [Loc.T("Выберите другую папку сохранения."), Loc.T("Закройте файл, если он открыт в другой программе.")]);
        if (Has(text, "Invalid data found when processing input", "moov atom not found", "partial file", "Truncated"))
            return (Loc.T("Файл повреждён или скачан не до конца."),
                [Loc.T("Проверьте, что он проигрывается целиком."), Loc.T("Скачайте или запишите файл заново.")]);
        if (Has(text, "Cannot allocate memory", "Out of memory", "malloc of size", "Failed to allocate"))
            return (Loc.T("FFmpeg не хватило памяти."),
                [Loc.T("Закройте другие программы и уменьшите «Длинную сторону» (например, до 1280 px)."), standard]);
        if (text.Length == 0)
            return (Loc.T("FFmpeg остановился без сообщения. Обычно это нехватка памяти на большом видео, сбой самой сборки FFmpeg или вмешательство антивируса."),
                [standard, Loc.T("Закройте другие программы или уменьшите «Длинную сторону» (например, до 1280 px)."),
                    Loc.T("Обновите FFmpeg до свежей полной сборки (gyan.dev, «full»).")]);
        return (Loc.T("FFmpeg не смог обработать этот файл."),
            [standard, Loc.T("Проверьте, что файл открывается в плеере, и обновите FFmpeg до свежей сборки.")]);
    }

    private static bool Has(string text, params string[] needles) => needles.Any(needle => text.Contains(needle, StringComparison.OrdinalIgnoreCase));

    /// <summary>Saves the details of the last failure for a bug report; returns the path, or null if it cannot be written.</summary>
    public static string? WriteLog(string executable, IEnumerable<string> arguments, int exitCode, string stderr, string stdout)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            var log = new StringBuilder();
            log.AppendLine("Vacpack " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture));
            log.AppendLine("Exit code: " + Code(exitCode));
            log.AppendLine("Command: " + executable + " " + string.Join(' ', arguments.Select(argument => argument.Contains(' ') ? "\"" + argument + "\"" : argument)));
            log.AppendLine().AppendLine("--- stderr ---").AppendLine(stderr.Length > 8000 ? stderr[^8000..] : stderr);
            log.AppendLine("--- stdout (tail) ---").AppendLine(stdout.Length > 2000 ? stdout[^2000..] : stdout);
            File.WriteAllText(LogPath, log.ToString(), new UTF8Encoding(false));
            return LogPath;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }
}
