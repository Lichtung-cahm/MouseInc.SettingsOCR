Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$outputPath = "D:\screenshots\cc-screenshot.png"
$outputDir  = Split-Path $outputPath -Parent

if (-not (Test-Path $outputDir)) {
    [System.IO.Directory]::CreateDirectory($outputDir)
}

if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    $image = [System.Windows.Forms.Clipboard]::GetImage()
    $image.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    [System.Windows.Forms.Clipboard]::SetText($outputPath)
    exit 0
} else {
    exit 1
}
