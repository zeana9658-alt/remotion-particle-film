<#
.SYNOPSIS
  Render the deliverable MP4 from a signed-off proxy.

.EXAMPLE
  powershell -File scripts\render-master.ps1 -Out output.mp4
#>
param(
  [string]$EntryPoint = "src/index.ts",
  [string]$Composition = "TianyuanOrigin",
  [string]$Out = "output.mp4",
  [string]$Codec = "h264",
  [int]$Crf = 16,
  [string]$PixelFormat = "yuv420p",
  [int]$Concurrency = 0,
  [string]$X264Preset = ""
)

$ErrorActionPreference = "Stop"

$cliArgs = @("remotion", "render", $EntryPoint, $Composition, $Out,
             "--codec=$Codec", "--crf=$Crf", "--pixel-format=$PixelFormat")
if ($Concurrency -gt 0) { $cliArgs += "--concurrency=$Concurrency" }
if ($X264Preset -ne "") { $cliArgs += "--x264-preset=$X264Preset" }

Write-Output ("npx " + ($cliArgs -join " "))
& npx @cliArgs
if ($LASTEXITCODE -ne 0) { throw "master render failed with exit code $LASTEXITCODE" }

$file = Get-Item -LiteralPath $Out
Write-Output ("master: {0}  {1:N0} bytes" -f $file.FullName, $file.Length)
