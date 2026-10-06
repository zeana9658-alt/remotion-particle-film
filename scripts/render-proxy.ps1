<#
.SYNOPSIS
  Quarter-scale QA pass: render the film as a PNG sequence to measure and sheet.

.EXAMPLE
  powershell -File scripts\render-proxy.ps1 -OutDir qa\r01\motion
#>
param(
  [string]$EntryPoint = "src/index.ts",
  [string]$Composition = "TianyuanOrigin",
  [string]$OutDir = "qa\r01\motion",
  [double]$Scale = 0.25,
  [string]$Frames = "",
  [switch]$NoPng
)

$ErrorActionPreference = "Stop"

$cliArgs = @("remotion", "render", $EntryPoint, $Composition, $OutDir, "--sequence", "--scale=$Scale")
if (-not $NoPng) { $cliArgs += "--image-format=png" }
if ($Frames -ne "") { $cliArgs += "--frames=$Frames" }

Write-Output ("npx " + ($cliArgs -join " "))
& npx @cliArgs
if ($LASTEXITCODE -ne 0) { throw "proxy render failed with exit code $LASTEXITCODE" }

$count = (Get-ChildItem -LiteralPath $OutDir -File -ErrorAction SilentlyContinue).Count
Write-Output "proxy frames: $count"
