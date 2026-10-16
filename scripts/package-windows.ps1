[CmdletBinding()]
param(
  [string]$MouseIncExePath,
  [string]$MouseIncDownloadUrl = $env:MOUSEINC_DOWNLOAD_URL,
  [string]$MouseIncSha256 = $env:MOUSEINC_SHA256,
  [string]$MouseIncSource,
  [string]$DistPath,
  [string]$OutputDirectory,
  [switch]$SettingsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $DistPath) { $DistPath = Join-Path $repoRoot 'dist' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts' }
$absoluteOutput = [IO.Path]::GetFullPath($OutputDirectory)
if ($absoluteOutput.TrimEnd('\', '/') -eq [IO.Path]::GetPathRoot($absoluteOutput).TrimEnd('\', '/')) {
  throw 'OutputDirectory must not be a filesystem root.'
}
$distRoot = [IO.Path]::GetFullPath($DistPath).TrimEnd('\', '/')
$outputRoot = $absoluteOutput.TrimEnd('\', '/')
$separator = [IO.Path]::DirectorySeparatorChar
$distPrefix = $distRoot + $separator
$outputPrefix = $outputRoot + $separator

function Assert-RegularFile([string]$Path, [string]$Description) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Description is missing: $Path"
  }
  if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "$Description must be a regular file: $Path"
  }
}

function Write-Utf8File([string]$Path, [string]$Content) {
  [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Get-Sha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
  } finally {
    $algorithm.Dispose()
    $stream.Dispose()
  }
}

function New-ArchiveFromDirectory([string]$Source, [string]$Destination) {
  $sourcePrefix = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/') + $separator
  $archive = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($file in (Get-ChildItem -LiteralPath $Source -Recurse -File | Sort-Object FullName)) {
      Assert-RegularFile $file.FullName 'Archive input'
      if (-not $file.FullName.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Archive input is outside the staging directory: $($file.FullName)"
      }
      $relative = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal
      ) | Out-Null
    }
  } finally {
    $archive.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $distRoot -PathType Container)) {
  throw "Build output is missing. Run npm ci and npm run build first: $distRoot"
}
if ((Get-Item -LiteralPath $distRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
  throw 'DistPath must not be a linked directory.'
}
if ($outputRoot -eq $repoRoot -or $outputRoot -eq $distRoot -or
    $outputRoot.StartsWith($distPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $distRoot.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'OutputDirectory must be separate from the repository root and dist directory.'
}
Assert-RegularFile (Join-Path $distRoot 'index.html') 'Built index.html'

# Only web assets belong in the offline settings archive.
$webExtensions = @('.html', '.js', '.css', '.json', '.png', '.svg', '.jpg', '.jpeg',
  '.gif', '.webp', '.ico', '.woff', '.woff2', '.ttf', '.otf', '.wasm')
$distFiles = @(Get-ChildItem -LiteralPath $distRoot -Recurse -File)
foreach ($file in $distFiles) {
  Assert-RegularFile $file.FullName 'Built web asset'
  $relative = $file.FullName.Substring($distPrefix.Length).Replace('\', '/')
  if ($webExtensions -notcontains $file.Extension.ToLowerInvariant() -or
      $relative -match '(^|/)(scripts?|debug|node_modules|\.git)(/|$)' -or
      $file.Name -ieq 'MouseInc.json') {
    throw "Unexpected file in dist; refusing to include it: $relative"
  }
}
foreach ($directory in (Get-ChildItem -LiteralPath $distRoot -Recurse -Directory)) {
  if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "dist must not contain linked directories: $($directory.FullName)"
  }
}
$index = [IO.File]::ReadAllText((Join-Path $distRoot 'index.html'))
foreach ($match in [regex]::Matches($index, '(?:src|href)=["''](/mouseinc/[^"''?#]+)')) {
  $relative = [Uri]::UnescapeDataString($match.Groups[1].Value.Substring('/mouseinc/'.Length))
  $asset = [IO.Path]::GetFullPath((Join-Path $distRoot $relative))
  if (-not $asset.StartsWith($distPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "index.html references an asset outside dist: $relative"
  }
  Assert-RegularFile $asset 'Asset referenced by index.html'
}

if (-not $SettingsOnly) {
  Assert-RegularFile (Join-Path $repoRoot 'scripts/ocr-local.ps1') 'Local OCR script'
  Assert-RegularFile (Join-Path $repoRoot 'portable/README.txt') 'Portable package instructions'
  if ($MouseIncExePath -and $MouseIncDownloadUrl) {
    throw 'Provide MouseIncExePath or MouseIncDownloadUrl, not both.'
  }
  if (-not $MouseIncExePath -and -not $MouseIncDownloadUrl) {
    throw 'Portable packaging requires an official MouseInc executable or download URL.'
  }
  if ($MouseIncDownloadUrl) {
    $downloadUri = $null
    if (-not [Uri]::TryCreate($MouseIncDownloadUrl, [UriKind]::Absolute, [ref]$downloadUri) -or
        $downloadUri.Scheme -ne 'https') {
      throw 'MouseIncDownloadUrl must be an absolute HTTPS URL for the official .exe.'
    }
    if ($MouseIncSha256 -notmatch '^[a-fA-F0-9]{64}$') {
      throw 'An official download requires its expected 64-character SHA-256 hash.'
    }
  }
  if ($MouseIncSha256 -and $MouseIncSha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'MouseIncSha256 must contain exactly 64 hexadecimal characters.'
  }
}

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$stageRoot = Join-Path $outputRoot ('.package-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stageRoot) | Out-Null
try {
  $settingsPath = Join-Path $stageRoot 'MouseInc.Settings.zip'
  New-ArchiveFromDirectory $distRoot $settingsPath
  $settingsArchive = [IO.Compression.ZipFile]::OpenRead($settingsPath)
  try {
    if (-not $settingsArchive.GetEntry('index.html')) {
      throw 'Settings archive must contain index.html at its root.'
    }
  } finally {
    $settingsArchive.Dispose()
  }
  $outputs = @($settingsPath)

  if (-not $SettingsOnly) {
    if ($MouseIncDownloadUrl) {
      $MouseIncExePath = Join-Path $stageRoot 'upstream-MouseInc.exe'
      Invoke-WebRequest -Uri $MouseIncDownloadUrl -OutFile $MouseIncExePath -UseBasicParsing
    } else {
      $MouseIncExePath = [IO.Path]::GetFullPath($MouseIncExePath)
    }
    Assert-RegularFile $MouseIncExePath 'Upstream MouseInc executable'
    $exeHash = Get-Sha256 $MouseIncExePath
    if ($MouseIncSha256 -and $exeHash -ne $MouseIncSha256.ToLowerInvariant()) {
      throw "MouseInc SHA-256 mismatch. Expected $MouseIncSha256, got $exeHash."
    }
    $exeStream = [IO.File]::OpenRead($MouseIncExePath)
    try {
      if ($exeStream.Length -lt 64 -or $exeStream.ReadByte() -ne 77 -or $exeStream.ReadByte() -ne 90) {
        throw 'MouseInc input is not a Windows executable (MZ header missing).'
      }
    } finally {
      $exeStream.Dispose()
    }
    $nativeInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($MouseIncExePath)
    $nativeVersion = $null
    if ($nativeInfo.ProductName -ne 'MouseInc' -or
        -not [version]::TryParse($nativeInfo.ProductVersion, [ref]$nativeVersion) -or
        $nativeVersion -lt [version]'2.13.0') {
      throw 'Portable packaging requires MouseInc 2.13.0 or newer (the WebSocket settings protocol).'
    }

    $portableRoot = Join-Path $stageRoot 'portable'
    [IO.Directory]::CreateDirectory((Join-Path $portableRoot 'scripts')) | Out-Null
    Copy-Item -LiteralPath $MouseIncExePath -Destination (Join-Path $portableRoot 'MouseInc.exe')
    Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $portableRoot 'MouseInc.Settings.zip')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/ocr-local.ps1') -Destination (Join-Path $portableRoot 'scripts/ocr-local.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'portable/README.txt') -Destination (Join-Path $portableRoot 'README.txt')
    $ocrLauncher = @'
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\ocr-local.ps1"
if errorlevel 1 pause
'@
    [IO.File]::WriteAllText((Join-Path $portableRoot 'OCR-Clipboard.cmd'),
      $ocrLauncher.Replace("`r", '').Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
    if (-not $MouseIncSource) {
      $MouseIncSource = if ($MouseIncDownloadUrl) {
        'Downloaded from the supplied upstream URL; verified against the supplied SHA-256.'
      } else {
        'Supplied existing upstream executable; original download provenance was not independently verified.'
      }
    }
    $sourceUrl = if ($MouseIncDownloadUrl) { $MouseIncDownloadUrl } else { 'Not provided.' }
    Write-Utf8File (Join-Path $portableRoot 'UPSTREAM.txt') @"
MouseInc.exe is a separately distributed upstream binary and was not compiled by this settings project.
Vendor reference: https://github.com/shuax/MouseInc.Settings
Source description: $MouseIncSource
Download URL: $sourceUrl
Product version: $($nativeInfo.ProductVersion)
SHA-256: $exeHash

No existing MouseInc.json configuration is read, changed, or included by the packager.
"@
    $portablePath = Join-Path $stageRoot 'MouseInc.SettingsOCR-Windows-Portable.zip'
    New-ArchiveFromDirectory $portableRoot $portablePath
    $outputs += $portablePath
  }

  $hashLines = @()
  foreach ($output in $outputs) {
    $name = [IO.Path]::GetFileName($output)
    $hash = Get-Sha256 $output
    $hashLines += "$hash  $name"
    Move-Item -LiteralPath $output -Destination (Join-Path $outputRoot $name) -Force
    Write-Output (Join-Path $outputRoot $name)
  }
  Write-Utf8File (Join-Path $outputRoot 'SHA256SUMS.txt') (($hashLines -join "`n") + "`n")
} finally {
  # Remove only this invocation's unique staging directory, inside the checked output root.
  $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
  if ($resolvedStage.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) -and
      [IO.Path]::GetFileName($resolvedStage) -match '^\.package-[a-f0-9]{32}$' -and
      (Test-Path -LiteralPath $resolvedStage -PathType Container)) {
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
  }
}
