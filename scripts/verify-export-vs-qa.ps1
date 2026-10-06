<#
.SYNOPSIS
  Prove the finished MP4 is the same cut as the proxy you signed off.

.DESCRIPTION
  Decodes the movie back down to the proxy resolution, recomputes per-frame luma, and
  diffs the curve against the reference CSV from analyze-frames.ps1.

  Expect a mean absolute delta near 1/255 and matching extrema. A constant offset is
  normal (point sprites rasterise at different pixel sizes at different scales); a change
  in the shape of the curve means the master is not the approved cut.

.EXAMPLE
  powershell -File scripts\verify-export-vs-qa.ps1 -Movie output.mp4 -ReferenceCsv qa\r01\motion.csv
#>
param(
  [Parameter(Mandatory = $true)][string]$Movie,
  [Parameter(Mandatory = $true)][string]$ReferenceCsv,
  [int]$Width = 270,
  [int]$Height = 480,
  [string]$Ffmpeg = "",
  [string]$WorkDir = "",
  [int]$SpotCheckLimit = 12
)

$ErrorActionPreference = "Stop"

if ($Ffmpeg -eq "") {
  $candidates = Get-ChildItem -Path (Join-Path (Get-Location) "node_modules\@remotion") -Directory -Filter "compositor-*" -ErrorAction SilentlyContinue
  foreach ($c in $candidates) {
    $exe = Join-Path $c.FullName "ffmpeg.exe"
    if (Test-Path -LiteralPath $exe) { $Ffmpeg = $exe; break }
  }
}
if ($Ffmpeg -eq "" -or -not (Test-Path -LiteralPath $Ffmpeg)) {
  throw "ffmpeg not found. Pass -Ffmpeg, or run from a project with @remotion/compositor-* installed."
}

if ($WorkDir -eq "") { $WorkDir = Join-Path $env:TEMP "particle-film-verify" }
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Output ("decoding {0} -> {1}x{2} proxies ..." -f $Movie, $Width, $Height)
& $Ffmpeg -v error -i $Movie -vf "scale=$Width`:$Height" -vsync 0 (Join-Path $WorkDir "f-%04d.png")
$decoded = (Get-ChildItem -LiteralPath $WorkDir -File -Filter "f-*.png").Count
Write-Output ("decoded frames = {0}" -f $decoded)

Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class LumaScan
{
    public static void Run(string dir, string outCsv)
    {
        var sb = new StringBuilder();
        sb.AppendLine("frame,luma");
        string[] files = Directory.GetFiles(dir, "f-*.png");
        Array.Sort(files, StringComparer.Ordinal);
        int idx = 0;
        foreach (string path in files)
        {
            double sum = 0.0;
            int w, h;
            using (Bitmap bmp = new Bitmap(path))
            {
                w = bmp.Width; h = bmp.Height;
                BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h),
                                               ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
                int stride = data.Stride;
                byte[] buf = new byte[stride * h];
                Marshal.Copy(data.Scan0, buf, 0, buf.Length);
                bmp.UnlockBits(data);
                for (int y = 0; y < h; y++)
                {
                    int off = y * stride;
                    for (int x = 0; x < w; x++)
                    {
                        int p = off + x * 3;
                        sum += 0.114 * buf[p] + 0.587 * buf[p + 1] + 0.299 * buf[p + 2];
                    }
                }
            }
            sb.Append(idx).Append(',')
              .Append((sum / (w * (double)h)).ToString("F4", CultureInfo.InvariantCulture)).Append('\n');
            idx++;
        }
        File.WriteAllText(outCsv, sb.ToString());
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Drawing'
[LumaScan]::Run($WorkDir, (Join-Path $WorkDir "decoded-luma.csv"))

$dec = @{}
Get-Content -LiteralPath (Join-Path $WorkDir "decoded-luma.csv") | Select-Object -Skip 1 | ForEach-Object {
  $p = $_ -split ','
  $dec[[int]$p[0]] = [double]$p[1]
}
$ref = @{}
Get-Content -LiteralPath $ReferenceCsv | Select-Object -Skip 1 | ForEach-Object {
  $p = $_ -split ','
  $ref[[int]$p[0]] = [double]$p[1]
}

$common = $dec.Keys | Where-Object { $ref.ContainsKey($_) } | Sort-Object
if ($common.Count -eq 0) { throw "no overlapping frame indices between decode and reference" }

$sum = 0.0; $max = 0.0; $maxFrame = -1
foreach ($k in $common) {
  $d = [math]::Abs($dec[$k] - $ref[$k])
  $sum += $d
  if ($d -gt $max) { $max = $d; $maxFrame = $k }
}

Write-Output ("decoded samples = {0}   reference samples = {1}   compared = {2}" -f $dec.Count, $ref.Count, $common.Count)
Write-Output ("mean |luma delta| = {0:F4}   max |luma delta| = {1:F4} (frame {2})" -f ($sum / $common.Count), $max, $maxFrame)
if ($dec.Count -ne $ref.Count) {
  Write-Output "WARNING: frame counts differ - the master and the approved proxy are not the same length."
}

# Shape check. Absolute levels are not comparable between the two curves (point sprites
# rasterise at different pixel sizes at different scales), so compare the shape: the
# brightest beat and the Pearson correlation of the whole curve.
$refMax = ($ref.Keys | Sort-Object { $ref[$_] } -Descending | Select-Object -First 1)
$decMax = ($dec.Keys | Sort-Object { $dec[$_] } -Descending | Select-Object -First 1)
Write-Output ("brightest frame  reference {0} / decoded {1}" -f $refMax, $decMax)

$n = $common.Count
$refMean = 0.0; $decMean = 0.0
foreach ($k in $common) { $refMean += $ref[$k]; $decMean += $dec[$k] }
$refMean /= $n; $decMean /= $n
$cov = 0.0; $vr = 0.0; $vd = 0.0
foreach ($k in $common) {
  $a = $ref[$k] - $refMean
  $b = $dec[$k] - $decMean
  $cov += $a * $b; $vr += $a * $a; $vd += $b * $b
}
$corr = if ($vr -gt 0 -and $vd -gt 0) { $cov / [math]::Sqrt($vr * $vd) } else { 0 }
Write-Output ("pearson correlation = {0:F6}" -f $corr)

$step = [math]::Max(1, [int][math]::Floor($common.Count / $SpotCheckLimit))
Write-Output ""
Write-Output "spot checks (frame : reference luma -> decoded luma)"
foreach ($k in ($common | Where-Object { $_ % $step -eq 0 })) {
  Write-Output ("  {0,5} : {1,8:F4} -> {2,8:F4}" -f $k, $ref[$k], $dec[$k])
}
