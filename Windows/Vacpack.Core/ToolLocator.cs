namespace Vacpack.Core;

public sealed class ToolLocator(IEnumerable<string>? directories = null)
{
    public IReadOnlyList<string> Directories { get; } = (directories ?? DefaultDirectories())
        .Where(Path.IsPathFullyQualified).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();

    public string? Find(string name)
    {
        if (Path.GetFileName(name) != name) throw new ArgumentException("Expected a tool name.", nameof(name));
        var executable = name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name : name + ".exe";
        return Directories.Select(directory => Path.Combine(directory, executable)).FirstOrDefault(File.Exists);
    }

    public string Require(string name) => Find(name) ?? throw new FileNotFoundException(
        Loc.T("Не найден {0}.exe. Поместите FFmpeg и ffprobe в папку tools рядом с приложением или добавьте их в PATH.", name));

    private static IEnumerable<string> DefaultDirectories()
    {
        var configured = Environment.GetEnvironmentVariable("VACPACK_TOOLS");
        if (!string.IsNullOrWhiteSpace(configured)) yield return configured;
        yield return Path.Combine(AppContext.BaseDirectory, "tools");
        yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Vacpack", "tools");
        foreach (var path in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
            yield return path.Trim().Trim('"');
        var scoop = Environment.GetEnvironmentVariable("SCOOP")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop");
        yield return Path.Combine(scoop, "apps", "ffmpeg", "current", "bin");
    }
}
