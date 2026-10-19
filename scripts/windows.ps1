param(
    [ValidateSet('check', 'run', 'package', 'installer')]
    [string]$Mode = 'check',
    [string]$ToolsDirectory,
    [switch]$RequireMediaTests,
    [string]$DestinationDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$env:DOTNET_CLI_HOME = Join-Path $repoRoot '.build\dotnet-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
if ($ToolsDirectory) { $env:VACPACK_TOOLS = (Resolve-Path -LiteralPath $ToolsDirectory).Path }
$config = Join-Path $repoRoot 'Windows\NuGet.Config'
$publishConfig = Join-Path $repoRoot 'Windows\NuGet.Publish.Config'
$application = Join-Path $repoRoot 'Windows\Vacpack.Windows\Vacpack.Windows.csproj'
$checks = Join-Path $repoRoot 'Windows\Vacpack.Tests\Vacpack.Tests.csproj'

function Invoke-Dotnet {
    & dotnet @args
    if ($LASTEXITCODE -ne 0) { throw "dotnet failed (exit $LASTEXITCODE)." }
}

function Publish-Application($destination) {
    Invoke-Dotnet publish $application --configuration Release --runtime win-x64 --self-contained true --output $destination --configfile $publishConfig --nologo
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Windows\README.md') -Destination (Join-Path $destination 'README.md')
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
        $destination = if ($DestinationDirectory) { [System.IO.Path]::GetFullPath($DestinationDirectory) } else { Join-Path $repoRoot '.build\windows\Vacpack' }
        Publish-Application $destination
        Write-Output "Windows build: $destination\Vacpack.exe"
        Write-Output 'Self-contained: .NET is bundled. FFmpeg and ffprobe are installed separately.'
    }
    'installer' {
        $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $iscc) { throw 'Install Inno Setup 6: https://jrsoftware.org/isdl.php' }
        $version = [regex]::Match((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'project.yml')), 'MARKETING_VERSION: "([0-9.]+)"').Groups[1].Value
        if (-not $version) { throw 'MARKETING_VERSION not found in project.yml.' }
        $destination = Join-Path $repoRoot '.build\windows\installer-staging'
        $output =Join-Path $repoRoot '.build\windows'
        Publish-Application $destination
        & $iscc "/DAppVersion=$version" "/DSourceDir=$destination" "/DOutputDir=$output" (Join-Path $repoRoot 'Windows\installer\Vacpack.iss')
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit $LASTEXITCODE)." }
        Write-Output "Windows installer: $output\Vacpack-Setup-$version.exe"
    }
}
