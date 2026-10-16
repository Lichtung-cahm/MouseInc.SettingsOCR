#Requires -Version 5.1
<#
.SYNOPSIS
Recognize clipboard image text with the offline Windows OCR engine.
.DESCRIPTION
By default, reads an image from the clipboard and replaces it with recognized
text only after recognition succeeds. No network service is used.
Use both -ImagePath and -OutputPath for a test that never accesses the clipboard.
The requested OCR language must already be installed in Windows.
.EXAMPLE
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\ocr-local.ps1
.EXAMPLE
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\ocr-local.ps1 -ImagePath .\sample.png -OutputPath .\result.txt
#>
[CmdletBinding()]
param(
  [string]$ImagePath,
  [string]$OutputPath,
  [string]$Language
)

$ErrorActionPreference = 'Stop'
$temporaryImage = $null
$clipboardImage = $null
$imageStream = $null
$softwareBitmap = $null
$exitCode = 0

try {
  if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this script with Windows PowerShell 5.1: powershell.exe -NoProfile -STA -File ocr-local.ps1'
  }
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'STA is required. Start Windows PowerShell with the -STA option.'
  }

  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
  $null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

  $asyncAsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and
      $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
  if (-not $asyncAsTask) {
    throw 'The Windows Runtime async adapter is unavailable.'
  }

  function Wait-WindowsOperation {
    param($Operation, [Type]$ResultType)
    $task = $asyncAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
  }

  $availableLanguages = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages)
  if ($availableLanguages.Count -eq 0) {
    throw 'No Windows OCR language is installed. Install an OCR language in Windows Settings > Time & language > Language & region.'
  }
  if ($Language) {
    $requestedLanguage = New-Object Windows.Globalization.Language($Language)
    $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($requestedLanguage)
    if (-not $ocrEngine) {
      $availableTags = ($availableLanguages | ForEach-Object { $_.LanguageTag }) -join ', '
      throw "OCR language '$Language' is not installed. Available: $availableTags"
    }
  } else {
    $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (-not $ocrEngine) {
      $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($availableLanguages[0])
    }
  }
  if (-not $ocrEngine) {
    throw 'Windows could not initialize an OCR engine.'
  }
  Write-Verbose ('OCR language: ' + $ocrEngine.RecognizerLanguage.LanguageTag)

  if ($ImagePath) {
    $resolvedImage = Get-Item -LiteralPath $ImagePath
    if ($resolvedImage.PSIsContainer -or $resolvedImage.PSProvider.Name -ne 'FileSystem') {
      throw 'ImagePath must be an image file on the filesystem.'
    }
    $sourcePath = $resolvedImage.FullName
  } else {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not [Windows.Forms.Clipboard]::ContainsImage()) {
      throw 'There is no image in the clipboard. Take a screenshot or copy an image first.'
    }
    $clipboardImage = [Windows.Forms.Clipboard]::GetImage()
    if (-not $clipboardImage) {
      throw 'The clipboard image could not be read.'
    }
    $temporaryImage = Join-Path ([IO.Path]::GetTempPath()) ('MouseInc-OCR-' + [Guid]::NewGuid().ToString('N') + '.png')
    $clipboardImage.Save($temporaryImage, [Drawing.Imaging.ImageFormat]::Png)
    $sourcePath = $temporaryImage
  }

  if ($OutputPath) {
    $targetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if ([string]::Equals($sourcePath, $targetPath, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'OutputPath must differ from ImagePath.'
    }
    $targetDirectory = [IO.Path]::GetDirectoryName($targetPath)
    if (-not [IO.Directory]::Exists($targetDirectory)) {
      throw 'The OutputPath parent directory does not exist.'
    }
  }

  $imageFile = Wait-WindowsOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($sourcePath)) ([Windows.Storage.StorageFile])
  $imageStream = Wait-WindowsOperation ($imageFile.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
  $decoder = Wait-WindowsOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($imageStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $maxDimension = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
  if ($decoder.PixelWidth -gt $maxDimension -or $decoder.PixelHeight -gt $maxDimension) {
    throw "The image is too large. Windows OCR supports up to $maxDimension pixels per side."
  }
  $softwareBitmap = Wait-WindowsOperation ($decoder.GetSoftwareBitmapAsync(
    [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
    [Windows.Graphics.Imaging.BitmapAlphaMode]::Ignore
  )) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $ocrResult = Wait-WindowsOperation ($ocrEngine.RecognizeAsync($softwareBitmap)) ([Windows.Media.Ocr.OcrResult])
  $recognizedText = (($ocrResult.Lines | ForEach-Object { $_.Text }) -join [Environment]::NewLine).Trim()
  # Windows OCR inserts word separators between individual Chinese characters.
  # Remove only those separators, preserving English spaces and line breaks.
  $recognizedText = [regex]::Replace($recognizedText, '(?<=[\u3400-\u9fff])[\x20\t]+(?=[\u3400-\u9fff])', '')
  if ([string]::IsNullOrWhiteSpace($recognizedText)) {
    throw 'No text was recognized. The clipboard has not been changed.'
  }

  if ($OutputPath) {
    [IO.File]::WriteAllText($targetPath, $recognizedText, (New-Object Text.UTF8Encoding($false)))
  } else {
    Add-Type -AssemblyName System.Windows.Forms
    # Do not clear the clipboard before writing: failure leaves the source intact.
    [Windows.Forms.Clipboard]::SetText($recognizedText)
  }
  Write-Verbose ('Recognized ' + $recognizedText.Length + ' characters.')
} catch {
  [Console]::Error.WriteLine('MouseInc local OCR: ' + $_.Exception.Message)
  $exitCode = 1
} finally {
  if ($softwareBitmap) { $softwareBitmap.Dispose() }
  if ($imageStream) { $imageStream.Dispose() }
  if ($clipboardImage) { $clipboardImage.Dispose() }
  if ($temporaryImage -and [IO.File]::Exists($temporaryImage)) {
    Remove-Item -LiteralPath $temporaryImage -Force -ErrorAction SilentlyContinue
  }
}

exit $exitCode
