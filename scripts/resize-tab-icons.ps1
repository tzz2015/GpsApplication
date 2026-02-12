# Resize tab icons to 48x48 to reduce memory (target < 100px)
Add-Type -AssemblyName System.Drawing
$media = Join-Path $PSScriptRoot "..\entry\src\main\resources\base\media"
$size = 48
$names = @("ic_tab_home", "ic_tab_profile")
foreach ($name in $names) {
    $path = Join-Path $media "$name.png"
    if (-not (Test-Path $path)) { Write-Warning "Skip: $path"; continue }
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $path))
    Write-Output "$name : $($img.Width)x$($img.Height) -> ${size}x${size}"
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $size, $size)
    $g.Dispose()
    $img.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "Saved: $path"
}
