param(
    [ValidateSet('check', 'run', 'package')]
    [string]$Mode = 'check',
    [string]$ToolsDirectory,
    [switch]$RequireMediaTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$env:DOTNET_CLI_HOME = Join-Path $repoRoot '.build\dotnet-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
if ($ToolsDirectory) { $env:VACPACK_TOOLS = (Resolve-Path -LiteralPath $ToolsDirectory).Path }
$config = Join-Path $repoRoot 'Windows\NuGet.Config'
$application = Join-Path $repoRoot 'Windows\Vacpack.Windows\Vacpack.Windows.csproj'
$checks = Join-Path $repoRoot 'Windows\Vacpack.Tests\Vacpack.Tests.csproj'

function Invoke-Dotnet {
    & dotnet @args
    if ($LASTEXITCODE -ne 0) { throw "dotnet failed (exit $LASTEXITCODE)." }
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Install the .NET 8 SDK: https://dotnet.microsoft.com/download/dotnet/8.0' }

switch ($Mode) {
    'check' {
        Invoke-Dotnet build $application --configuration Debug --configfile $config --nologo
        Invoke-Dotnet build $checks --configuration Debug --configfile $config --nologo
        $testArguments = @()
        if ($RequireMediaTests) { $testArguments += '--require-media' }
        & (Join-Path $repoRoot 'Windows\Vacpack.Tests\bin\Debug\net8.0\Vacpack.Tests.exe') @testArguments
        if ($LASTEXITCODE -ne 0) { throw "Windows checks failed (exit $LASTEXITCODE)." }
        # Render a real row as well as the empty window: catches deferred WPF binding errors.
        $snapshot = Join-Path $repoRoot '.build\windows-ui-check.png'
        $sample = Join-Path $repoRoot 'App\Resources\Assets.xcassets\AppIcon.appiconset\icon_128x128@2x.png'
        $ui = Start-Process -FilePath (Join-Path $repoRoot 'Windows\Vacpack.Windows\bin\Debug\net8.0-windows\Vacpack.exe') -ArgumentList @('--snapshot', ('"' + $snapshot + '"'), ('"' + $sample + '"')) -WindowStyle Hidden -PassThru
        try {
            if (-not $ui.WaitForExit(30000)) { $ui.Kill(); throw 'Windows UI check timed out.' }
            if ($ui.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) { throw "Windows UI check failed (exit $($ui.ExitCode))." }
        } finally { $ui.Dispose() }
        Write-Output "PASS: Windows window with a populated queue ($snapshot)"
    }
    'run' {
        Invoke-Dotnet build $application --configuration Debug --configfile $config --nologo
        & (Join-Path $repoRoot 'Windows\Vacpack.Windows\bin\Debug\net8.0-windows\Vacpack.exe')
    }
    'package' {
        $destination = Join-Path $repoRoot '.build\windows\Vacpack'
        Invoke-Dotnet publish $application --configuration Release --self-contained false --output $destination --configfile $config --nologo
        Copy-Item -LiteralPath (Join-Path $repoRoot 'Windows\README.md') -Destination (Join-Path $destination 'README.md')
        Write-Output "Windows build: $destination\Vacpack.exe"
        Write-Output 'Requires the .NET 8 Desktop Runtime. FFmpeg and ffprobe are installed separately.'
    }
}
