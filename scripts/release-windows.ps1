param(
    [string]$ToolsDirectory,
    [string]$PythonExecutable = 'python',
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9.-]*$')]
    [string]$ReleaseLabel = 'windows-preview.1'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$changes = & git -c "safe.directory=$repoRoot" -C $repoRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Commit all release sources first. A release requires a clean working tree.' }
$sourceCommit = & git -c "safe.directory=$repoRoot" -C $repoRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the source commit.' }
& $PythonExecutable (Join-Path $PSScriptRoot 'update_version.py') status
if ($LASTEXITCODE -ne 0) { throw 'Version files are out of sync.' }
$version = [regex]::Match((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'project.yml')), 'MARKETING_VERSION: "([0-9.]+)"').Groups[1].Value
if (-not $version) { throw 'MARKETING_VERSION not found.' }
$tag = "v$version-$ReleaseLabel"

$checkArguments = @{ Mode = 'check'; RequireMediaTests = $true }
if ($ToolsDirectory) { $checkArguments.ToolsDirectory = $ToolsDirectory }
& (Join-Path $PSScriptRoot 'windows.ps1') @checkArguments

# A fresh destination prevents old runtime files and locked running copies entering the release.
$staging = Join-Path $repoRoot ('.build\windows\release-staging-' + [guid]::NewGuid().ToString('N'))
$applicationFolder = Join-Path $staging 'Vacpack'
& (Join-Path $PSScriptRoot 'windows.ps1') -Mode installer -DestinationDirectory $applicationFolder
$manifest = Get-Content -Raw -LiteralPath (Join-Path $applicationFolder 'BUILD.json') | ConvertFrom-Json
if ($manifest.sourceDirty -or $manifest.sourceCommit -ne $sourceCommit.Trim()) { throw 'Release source changed during the build.' }
$changes = & git -c "safe.directory=$repoRoot" -C $repoRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Working tree changed during the release build.' }

$destination = Join-Path $repoRoot ".build\dist\$tag"
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$installer = Join-Path $destination "Vacpack-Setup-$version.exe"
Copy-Item -LiteralPath (Join-Path $repoRoot ".build\windows\Vacpack-Setup-$version.exe") -Destination $installer
$archive = Join-Path $destination "Vacpack-$version-$ReleaseLabel-win-x64.zip"
Compress-Archive -LiteralPath $applicationFolder -DestinationPath $archive -CompressionLevel Optimal -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
try {
    if (-not $zip.GetEntry('Vacpack/Vacpack.exe') -or -not $zip.GetEntry('Vacpack/BUILD.json')) { throw 'Release archive is incomplete.' }
} finally { $zip.Dispose() }
$hashes = foreach ($file in @($installer, $archive)) {
    $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
    $hash.Hash.ToLowerInvariant() + '  ' + [System.IO.Path]::GetFileName($file)
}
$hashes | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Release $tag built from $sourceCommit"
Write-Output "Application: $applicationFolder\Vacpack.exe"
Write-Output "Artifacts: $destination"
Get-ChildItem -LiteralPath $destination | Select-Object Name,Length
