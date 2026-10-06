<#
.SYNOPSIS
  Build a labelled contact sheet from a list of frames.

.DESCRIPTION
  -Items is a semicolon-separated list of "label|path" pairs. Frames are scaled to
  -TileWidth and laid out in -Cols columns with the label drawn above each tile.

.EXAMPLE
  powershell -File scripts\contact-sheet.ps1 -OutPath qa\sheet.png -Cols 4 `
    -Items "f0|qa\r01\motion\element-0000.png;f470|qa\r01\motion\element-0470.png"
#>
param(
  [Parameter(Mandatory = $true)][string]$OutPath,
  [Parameter(Mandatory = $true)][int]$Cols,
  [Parameter(Mandatory = $true)][string]$Items,
  [int]$TileWidth = 520,
  [int]$LabelHeight = 34
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$entries = @()
foreach ($raw in $Items.Split(';')) {
  $piece = $raw.Trim()
  if ($piece.Length -eq 0) { continue }
  $parts = $piece.Split('|')
  if ($parts.Length -lt 2) { continue }
  $entries += [pscustomobject]@{ Label = $parts[0]; Path = $parts[1] }
}
if ($entries.Count -eq 0) { throw 'no items given' }

$images = @()
foreach ($e in $entries) {
  if (-not (Test-Path -LiteralPath $e.Path)) { throw "missing: $($e.Path)" }
  $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $e.Path).Path)
  $h = [int][math]::Round($TileWidth * $img.Height / $img.Width)
  $images += [pscustomobject]@{ Label = $e.Label; Image = $img; H = $h }
}

$rows = [int][math]::Ceiling($entries.Count / $Cols)
$rowH = ($images | ForEach-Object { $_.H } | Measure-Object -Maximum).Maximum + $LabelHeight
$sheetW = $Cols * $TileWidth
$sheetH = $rows * $rowH

$bmp = New-Object System.Drawing.Bitmap($sheetW, $sheetH)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font('Consolas', 20, [System.Drawing.FontStyle]::Bold)
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 214, 0))
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

for ($i = 0; $i -lt $images.Count; $i++) {
  $col = $i % $Cols
  $row = [int][math]::Floor($i / $Cols)
  $x = $col * $TileWidth
  $y = $row * $rowH
  $g.FillRectangle($white, $x, $y + $LabelHeight, $TileWidth, $images[$i].H)
  $g.DrawImage($images[$i].Image, $x, $y + $LabelHeight, $TileWidth, $images[$i].H)
  $g.DrawString($images[$i].Label, $font, $brush, ($x + 8), ($y + 4))
}

$g.Dispose()
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
foreach ($im in $images) { $im.Image.Dispose() }
Write-Output "wrote $OutPath ($sheetW x $sheetH)"
