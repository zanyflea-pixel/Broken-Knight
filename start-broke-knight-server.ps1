param(
  [int]$Port = $(if ($env:BROKE_KNIGHT_PORT) { [int]$env:BROKE_KNIGHT_PORT } else { 8000 }),
  [int]$StartupTimeoutSec = 45,
  [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serveScript = Join-Path $root "serve-broke-knight.ps1"
$entryCheckScript = Join-Path $root "tools\check-3d-entry.ps1"
$stateFile = Join-Path $root ".broke-knight-server.json"

function Stop-BrokeKnightServerProcess {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return }
  try {
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
  } catch {}
}

if (Test-Path $stateFile) {
  try {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($state.pid) {
      Stop-BrokeKnightServerProcess -ProcessId ([int]$state.pid)
    }
  } catch {}
  Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -eq "powershell.exe" -and $_.CommandLine -match [Regex]::Escape("serve-broke-knight.ps1")
  } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

$serveCommand = @"
Set-Location -LiteralPath '$root'
& '$serveScript' -Port $Port
"@
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($serveCommand))
$commandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encoded
$created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine }

if (($created.ReturnValue | Out-String).Trim() -ne "0") {
  throw "Could not start Broke Knight server process."
}

$url = "http://127.0.0.1:$Port/"
$ok = $false
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

while ($stopwatch.Elapsed.TotalSeconds -lt $StartupTimeoutSec) {
  Start-Sleep -Milliseconds 350
  try {
    $resp = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 3
    if ($resp.StatusCode -eq 200) {
      $ok = $true
      break
    }
  } catch {}
}

if (-not $ok) {
  Stop-BrokeKnightServerProcess -ProcessId ([int]$created.ProcessId)
  throw "Broke Knight server did not respond on $url within $StartupTimeoutSec seconds."
}

if (Test-Path $entryCheckScript) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $entryCheckScript -BaseUrl $url
  if ($LASTEXITCODE -ne 0) {
    Stop-BrokeKnightServerProcess -ProcessId ([int]$created.ProcessId)
    throw "Broke Knight server responded, but the 3D entry health check failed."
  }
}

$branch = (git -C $root branch --show-current 2>$null)
$commit = (git -C $root rev-parse --short HEAD 2>$null)
$canonicalUrl = "${url}index-3d.html?cb=20260518a"

@{
  pid = [int]$created.ProcessId
  port = $Port
  url = $url
  canonical3dUrl = $canonicalUrl
  branch = $branch
  commit = $commit
  wrapper = "encoded-command"
  startedAt = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8

Write-Host "Broke Knight server ready"
Write-Host "  Root:      $url"
Write-Host "  3D entry:  $canonicalUrl"
if ($branch) { Write-Host "  Branch:    $branch" }
if ($commit) { Write-Host "  Commit:    $commit" }

if ($OpenBrowser) {
  Start-Process $canonicalUrl | Out-Null
}
