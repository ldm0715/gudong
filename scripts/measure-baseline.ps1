param(
  [string]$Exe = "",
  [int]$IdleSeconds = 15
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Exe) {
  $Exe = Join-Path $root "island_app\build\windows\x64\runner\Release\island_app.exe"
}
if (-not (Test-Path $Exe)) {
  throw "Not found: $Exe. Run scripts\build.ps1 first."
}

$release = Split-Path -Parent $Exe
$sidecar = Join-Path $root "island_service\target\release\island_service.exe"
if (Test-Path $sidecar) {
  Copy-Item $sidecar $release -Force
}

if (Get-Process island_app -ErrorAction SilentlyContinue) {
  throw "island_app is already running. Quit it from the tray first."
}

function Get-CpuPercent($delta, $elapsedSeconds) {
  return [math]::Round($delta.TotalSeconds / ($elapsedSeconds * [Environment]::ProcessorCount) * 100, 3)
}

Write-Host "==> launching $Exe"
$sw = [Diagnostics.Stopwatch]::StartNew()
$app = Start-Process -FilePath $Exe -PassThru
$windowMs = $null
for ($i = 0; $i -lt 300; $i++) {
  Start-Sleep -Milliseconds 50
  $app.Refresh()
  if ($app.MainWindowHandle -ne 0) {
    $windowMs = $sw.ElapsedMilliseconds
    break
  }
}
Start-Sleep -Seconds 5
$app.Refresh()
$svc = Get-Process island_service -ErrorAction SilentlyContinue
if (-not $svc) {
  Write-Warning "island_service.exe did not start"
}

Write-Host "==> sampling idle for $IdleSeconds s (leave mouse and keyboard alone)"
$appCpu0 = $app.TotalProcessorTime
$svcCpu0 = if ($svc) { $svc.TotalProcessorTime } else { [TimeSpan]::Zero }
$sample = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds $IdleSeconds
$sample.Stop()
$app.Refresh()
if ($svc) { $svc.Refresh() }
$appCpu1 = $app.TotalProcessorTime
$svcCpu1 = if ($svc) { $svc.TotalProcessorTime } else { [TimeSpan]::Zero }

$appCpu = Get-CpuPercent ($appCpu1 - $appCpu0) $sample.Elapsed.TotalSeconds
$svcCpu = Get-CpuPercent ($svcCpu1 - $svcCpu0) $sample.Elapsed.TotalSeconds

$log = Join-Path $env:LOCALAPPDATA "guduo\logs\app.log"
function Get-LastLogTime([string]$pattern) {
  if (-not (Test-Path $log)) { return $null }
  $line = Get-Content $log -Tail 300 | Where-Object { $_ -match $pattern } | Select-Object -Last 1
  if (-not $line) { return $null }
  try { return [datetime]::Parse($line.Substring(0, 23)) } catch { return $null }
}
$bootstrap = Get-LastLogTime "bootstrap start"
$ready = Get-LastLogTime "sidecar\] ready"
$shown = Get-LastLogTime "window shown"

Write-Host ""
Write-Host "=== Phase 0 baseline ==="
Write-Host ("launch -> window shown : {0} ms" -f $windowMs)
if ($bootstrap -and $shown) {
  Write-Host ("in-app bootstrap -> first frame : {0} ms" -f [int]($shown - $bootstrap).TotalMilliseconds)
}
if ($bootstrap -and $ready) {
  Write-Host ("in-app bootstrap -> sidecar ready : {0} ms" -f [int]($ready - $bootstrap).TotalMilliseconds)
}
# Memory metrics:
# - private working set is what Task Manager shows under "Memory"; the budget uses it.
# - private commit (PrivateMemorySize64) counts pages already paged out as well,
#   so it reads 40-60MB higher and must not be treated as resident memory.
function Get-MemInfo($process) {
  if (-not $process) { return $null }
  $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process `
    -Filter "IDProcess = $($process.Id)" -ErrorAction SilentlyContinue
  $workingSet = [int64]$process.WorkingSet64
  $privateWs = [int64]0
  if ($perf) {
    $workingSet = [int64]$perf.WorkingSet
    $privateWs = [int64]$perf.WorkingSetPrivate
  }
  return [pscustomobject]@{
    WorkingSet        = $workingSet
    PrivateWorkingSet = $privateWs
    Commit            = [int64]$process.PrivateMemorySize64
  }
}

$appMem = Get-MemInfo $app
$svcMem = Get-MemInfo $svc
$rows = @([pscustomobject]@{ Name = "island_app"; Mem = $appMem })
$totalWs = $appMem.WorkingSet
$totalPws = $appMem.PrivateWorkingSet
$totalCommit = $appMem.Commit
if ($svc) {
  $rows += [pscustomobject]@{ Name = "island_service"; Mem = $svcMem }
  $totalWs += $svcMem.WorkingSet
  $totalPws += $svcMem.PrivateWorkingSet
  $totalCommit += $svcMem.Commit
}
$rows += [pscustomobject]@{
  Name = "total"
  Mem  = [pscustomobject]@{
    WorkingSet = $totalWs
    PrivateWorkingSet = $totalPws
    Commit = $totalCommit
  }
}
Write-Host ""
Write-Host ("{0,-16} {1,12} {2,16} {3,14}" -f "process", "working", "private (taskmgr)", "commit*")
foreach ($row in $rows) {
  Write-Host ("{0,-16} {1,12} {2,16} {3,14}" -f $row.Name,
    ("{0:N1} MB" -f ($row.Mem.WorkingSet / 1MB)),
    ("{0:N1} MB" -f ($row.Mem.PrivateWorkingSet / 1MB)),
    ("{0:N1} MB" -f ($row.Mem.Commit / 1MB)))
}
$memOk = $rows[-1].Mem.PrivateWorkingSet / 1MB
Write-Host ("memory budget: private {0:N1} MB / 80 MB  {1}" -f $memOk, $(if ($memOk -le 80) { "OK" } else { "OVER" }))
Write-Host "  * commit is reserved address space, not resident memory; use the private column for the budget."
Write-Host ""
Write-Host ("idle CPU over {0}s: island_app {1:N3}%  island_service {2:N3}%  total {3:N3}% (of all cores)" -f $IdleSeconds, $appCpu, $svcCpu, ($appCpu + $svcCpu))
Write-Host ""
Write-Host "Animation FPS must be measured with: flutter run --profile -d windows, then DevTools Performance."
Write-Host "Budget: idle memory <= 80MB total, idle CPU <= 0.5%, cold start <= 1.5s, 60fps."
