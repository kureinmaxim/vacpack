using System.Diagnostics;
using System.Text;

namespace Vacpack.Core;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

public sealed class ProcessRunner
{
    public async Task<ProcessResult> RunAsync(string executable, IEnumerable<string> arguments,
        CancellationToken cancellationToken = default, TimeSpan? timeout = null, Action<string>? outputLine = null)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Path.IsPathFullyQualified(executable)) throw new ArgumentException("Use an absolute executable path.");
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = new Process { StartInfo = start };
        using var deadline = new CancellationTokenSource(timeout ?? TimeSpan.FromMinutes(30));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, deadline.Token);
        process.Start();
        using var registration = linked.Token.Register(() =>
        {
            try { process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
        });
        var stdout = ReadAsync(process.StandardOutput, outputLine);
        var stderr = ReadAsync(process.StandardError, null);
        await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
        await Task.WhenAll(stdout, stderr).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        if (deadline.IsCancellationRequested) throw new TimeoutException("Обработка заняла слишком много времени и остановлена.");
        return new ProcessResult(process.ExitCode, await stdout, await stderr);
    }

    private static async Task<string> ReadAsync(StreamReader reader, Action<string>? onLine)
    {
        var tail = new StringBuilder();
        while (await reader.ReadLineAsync().ConfigureAwait(false) is { } line)
        {
            onLine?.Invoke(line);
            tail.AppendLine(line);
            if (tail.Length > 262144) tail.Remove(0, tail.Length - 131072);
        }
        return tail.ToString();
    }
}
