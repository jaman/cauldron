# Build and run cauldron_gpu's smoke test on Windows.
#
#   powershell -ExecutionPolicy Bypass -File windows\run.ps1
#
# Run it from a "x64 Native Tools Command Prompt for VS" if `cl` is not on PATH;
# this script explains what is missing rather than guessing.

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$kit = Join-Path $here "kit"

function Note($message) { Write-Host "  $message" -ForegroundColor Yellow }
function Fail($message) { Write-Host "`n$message" -ForegroundColor Red; exit 1 }

Write-Host "`n== What this machine has" -ForegroundColor Cyan

if (-not (Get-Command mix -ErrorAction SilentlyContinue)) {
  Fail @"
mix is not on PATH. Install Erlang/OTP and Elixir, then open a new shell:
  winget install Erlang.Erlang
  winget install Elixir.Elixir
"@
}
& elixir --version

$hasCompiler = (Get-Command cl -ErrorAction SilentlyContinue) -and (Get-Command nmake -ErrorAction SilentlyContinue)
if (-not $hasCompiler) {
  Fail @"
cl.exe and nmake.exe are not on PATH. Open "x64 Native Tools Command Prompt for
VS 2022" (Start menu, Visual Studio 2022 folder) and run this script there:
  powershell -ExecutionPolicy Bypass -File windows\run.ps1
Install Visual Studio Build Tools with the "Desktop development with C++" workload
if you do not have it: https://visualstudio.microsoft.com/visual-cpp-build-tools/
"@
}

if (-not $env:VULKAN_SDK) {
  $candidate = Get-ChildItem "C:\VulkanSDK" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($candidate) { $env:VULKAN_SDK = $candidate.FullName; Note "VULKAN_SDK not set; using $($env:VULKAN_SDK)" }
}
if (-not $env:VULKAN_SDK) {
  Note "VULKAN_SDK is not set. Install the LunarG Vulkan SDK and re-run: https://vulkan.lunarg.com/"
} else {
  $env:VULKAN_INCLUDE = Join-Path $env:VULKAN_SDK "Include"
  Note "Vulkan: $env:VULKAN_INCLUDE"
}

if (-not $env:SDL3_DIR) {
  $candidate = Get-ChildItem "C:\SDL3*" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($candidate) { $env:SDL3_DIR = $candidate.FullName; Note "SDL3_DIR not set; using $($env:SDL3_DIR)" }
}
if (-not $env:SDL3_DIR) {
  Note "SDL3_DIR is not set. Download SDL3-devel-*-VC.zip from https://github.com/libsdl-org/SDL/releases, extract it, and set SDL3_DIR to the extracted folder."
} else {
  Note "SDL3:   $env:SDL3_DIR"
}

Write-Host "`n== Building cauldron_gpu and drawing one frame" -ForegroundColor Cyan

# prod, not dev: cauldron_gpu's dev-only dependencies (the 2D engine, the file formats,
# Credo, ExDoc) are not in this kit and are not needed to draw a frame.
$env:MIX_ENV = "prod"

Push-Location $kit
try {
  & mix deps.get
  if ($LASTEXITCODE -ne 0) { Fail "mix deps.get failed" }

  & mix run smoke.exs
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}

switch ($code) {
  0 {
    Write-Host "`nThe renderer works. The frame is at windows\kit\gpu-smoke.png" -ForegroundColor Green
    exit 0
  }
  1 {
    Fail "The card was found but the frame could not be drawn. Run `vulkaninfo` and check the renderer's message above."
  }
  2 {
    Fail @"
No renderer was built, so cauldron_gpu fell back to software drawing. The usual causes:
  - VULKAN_SDK or SDL3_DIR was not set when mix compiled (set them, then: mix clean && mix run smoke.exs)
  - the Visual Studio "Desktop development with C++" workload is missing
  - nmake was run outside a Native Tools prompt
"@
  }
  default { Fail "mix run smoke.exs exited $code" }
}
