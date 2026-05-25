Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
    Write-Error "No image in clipboard"
    exit 1
}

$outputDir = "D:\screenshots"
if (-not (Test-Path $outputDir)) {
    [System.IO.Directory]::CreateDirectory($outputDir)
}

$pngPath = "$outputDir\ocr-temp.png"
[System.Windows.Forms.Clipboard]::GetImage().Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

$result = & curl.exe -s -H "apikey:helloworld" --form "file=@$pngPath" --form "language=chs" "https://api.ocr.space/Parse/Image" 2>$null
$response = $result | ConvertFrom-Json

Remove-Item $pngPath -ErrorAction SilentlyContinue

if ($response.ParsedResults -and $response.ParsedResults.Count -gt 0 -and $response.ParsedResults[0].ParsedText) {
    [System.Windows.Forms.Clipboard]::SetText($response.ParsedResults[0].ParsedText.Trim())
    exit 0
} else {
    Write-Error "OCR failed: no result"
    exit 1
}
