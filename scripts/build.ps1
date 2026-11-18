$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

Write-Host "==> cargo build --release"
Push-Location (Join-Path $root "island_service")
try {
  cargo build --release
} finally {
  Pop-Location
}

Write-Host "==> flutter build windows --release"
Push-Location (Join-Path $root "island_app")
try {
  flutter build windows --release
} finally {
  Pop-Location
}

$release = Join-Path $root "island_app\build\windows\x64\runner\Release"
Copy-Item (Join-Path $root "island_service\target\release\island_service.exe") $release -Force

Write-Host ""
Write-Host "Built:  $release\island_app.exe"
Write-Host "Sidecar: $release\island_service.exe"
Write-Host "Run the exe, or use scripts\measure-baseline.ps1 to collect Phase 0 metrics."
