# Regenerate the full asset set for dsh-gpt-icon from a single SVG source.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-assets.ps1 -SvgPath my-knot.svg
#
# Produces into -OutDir (defaults to the repo's assets\):
#   chatgpt-blue-hollow.png / icon.png / dsh-desktop-logo*.png   512x512 transparent PNG
#   icon.ico                                                     9-size ICO (16..256)
#   dsh-loader.gif / dsh-loader-dark.gif                         196x196 transparent GIF
#   chatgpt-blue-hollow.svg                                      copy of the source SVG
#   dsh-badge.png                                                whale->knot badge composite
#
# Requires: Microsoft Edge (headless rasterizer), .NET System.Drawing / WPF.
param(
  [Parameter(Mandatory = $true)][string]$SvgPath,
  [string]$OutDir,
  [string]$DshInstallRoot = 'D:\dsh desktop',
  [string]$EdgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path -LiteralPath $SvgPath)) { throw "SVG not found: $SvgPath" }
if (-not (Test-Path -LiteralPath $EdgePath)) { throw "Edge not found at $EdgePath (pass -EdgePath)." }

# --- 1. rasterize the SVG to a 512x512 transparent PNG via headless Edge ---
$work = Join-Path $OutDir '.build'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -LiteralPath $SvgPath -Destination (Join-Path $work 'knot.svg') -Force
Copy-Item -LiteralPath $SvgPath -Destination (Join-Path $OutDir 'chatgpt-blue-hollow.svg') -Force
$wrapper = Join-Path $work 'knot-512.html'
$wrapperHtml = @'
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;overflow:hidden}
img{display:block;width:512px;height:512px}
</style></head><body><img src="knot.svg"></body></html>
'@
[System.IO.File]::WriteAllText($wrapper, $wrapperHtml, [System.Text.UTF8Encoding]::new($false))

$knot512 = Join-Path $OutDir 'chatgpt-blue-hollow.png'
Remove-Item -LiteralPath $knot512 -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'
& $EdgePath --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
  --window-size=512,512 --default-background-color=00000000 `
  --virtual-time-budget=1500 --screenshot="$knot512" "file:///$($wrapper -replace '\\','/')" 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
Start-Sleep -Milliseconds 1200
if (-not (Test-Path -LiteralPath $knot512)) { throw 'headless Edge did not produce the PNG.' }

$png = [System.Drawing.Bitmap]::new($knot512)
try {
  if ($png.Width -ne 512 -or $png.Height -ne 512) { throw "rendered PNG is $($png.Width)x$($png.Height), expected 512x512." }
  if ($png.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) { throw "unexpected pixel format $($png.PixelFormat)." }
  foreach ($c in @(@(2,2), @(509,2), @(2,509), @(509,509))) {
    if ($png.GetPixel($c[0], $c[1]).A -ne 0) { throw "corner $($c[0]),$($c[1]) is not transparent; does the SVG have a background rect?" }
  }
} finally { $png.Dispose() }
Write-Host '[ok] 512 PNG rendered'

# --- 2. multi-size ICO (16..256) built from PNG frames of the 512 master ---
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = @()
$master = [System.Drawing.Image]::FromFile($knot512)
try {
  foreach ($size in $sizes) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($master, 0, 0, $size, $size)
      $stream = [System.IO.MemoryStream]::new()
      $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
      $frames += ,$stream.ToArray()
      $stream.Dispose()
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
  }
} finally { $master.Dispose() }

$icoPath = Join-Path $OutDir 'icon.ico'
$output = [System.IO.File]::Create($icoPath)
$writer = [System.IO.BinaryWriter]::new($output)
try {
  $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
  $offset = 6 + 16 * $frames.Count
  for ($i = 0; $i -lt $frames.Count; $i++) {
    $size = $sizes[$i]
    $writer.Write([byte]($(if ($size -eq 256) { 0 } else { $size })))
    $writer.Write([byte]($(if ($size -eq 256) { 0 } else { $size })))
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$frames[$i].Length); $writer.Write([uint32]$offset)
    $offset += $frames[$i].Length
  }
  foreach ($frame in $frames) { $writer.Write($frame) }
} finally { $writer.Dispose(); $output.Dispose() }
Write-Host "[ok] icon.ico ($((Get-Item $icoPath).Length) bytes, $($frames.Count) frames)"

# --- 3. splash loader GIFs (transparent, 196x196) via WPF ---
Add-Type -AssemblyName PresentationCore
$src = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($knot512))
$scaled = [System.Windows.Media.Imaging.TransformedBitmap]::new($src,
  [System.Windows.Media.MatrixTransform]::new([System.Windows.Media.Matrix]::new(196/512, 0, 0, 196/512, 0, 0)))
$gifFrame = [System.Windows.Media.Imaging.BitmapFrame]::Create($scaled)
foreach ($name in @('dsh-loader.gif', 'dsh-loader-dark.gif')) {
  $encoder = [System.Windows.Media.Imaging.GifBitmapEncoder]::new()
  $encoder.Frames.Add($gifFrame)
  $fs = [System.IO.File]::Create((Join-Path $OutDir $name))
  try { $encoder.Save($fs) } finally { $fs.Dispose() }
}
Write-Host '[ok] loader GIFs'

# --- 4. sidebar/manifest logo PNGs (same 512 knot) ---
foreach ($name in @('icon.png', 'dsh-desktop-logo.png', 'dsh-desktop-logo-light.png', 'dsh-desktop-logo-dark.png')) {
  Copy-Item -LiteralPath $knot512 -Destination (Join-Path $OutDir $name) -Force
}
Write-Host '[ok] logo PNGs'

# --- 5. skill badge composite (replace only the whale pixels) ---
$stockBadge = Join-Path $DshInstallRoot 'resources\app\node_modules\@deepseek-ai\dsh-skill-badge\assets\dsh-badge.png'
if (Test-Path -LiteralPath $stockBadge) {
  $badge = [System.Drawing.Bitmap]::new($stockBadge)
  $sourceIcon = [System.Drawing.Image]::FromFile($knot512)
  try {
    $background = $badge.GetPixel(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($badge)
    try {
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $graphics.FillRectangle([System.Drawing.SolidBrush]::new($background), 0, 0, 132, $badge.Height)
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
      $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($sourceIcon, [System.Drawing.Rectangle]::new(38, 26, 68, 68))
    } finally { $graphics.Dispose() }
    $badge.Save((Join-Path $OutDir 'dsh-badge.png'), [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $sourceIcon.Dispose(); $badge.Dispose() }
  Write-Host '[ok] badge composite'
} else {
  Write-Warning "stock badge not found at $stockBadge; dsh-badge.png not regenerated (the committed one still works)."
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[done] assets regenerated in $OutDir"
