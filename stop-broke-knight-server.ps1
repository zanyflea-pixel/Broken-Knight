param()

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateFile = Join-Path $root ".broke-knight-server.json"
function Stop-BrokeKnightServerProcess {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return $false }
  try {
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 250
    return $true
  } catch {
    return $false
  }
}

$stopped = $false

if (Test-Path $stateFile) {
  try {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($state.pid) {
      $stopped = (Stop-BrokeKnightServerProcess -ProcessId ([int]$state.pid)) -or $stopped
    }
    if ($state.wrapper -and (Test-Path $state.wrapper)) {
      Remove-Item $state.wrapper -Force -ErrorAction SilentlyContinue
    }
  } catch {}
  Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    ($_.Name -eq "powershell.exe" -or $_.Name -eq "cmd.exe") -and
    $_.CommandLine -match [Regex]::Escape("serve-broke-knight.ps1")
  } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    $stopped = $true
  }

if ($stopped) {
  Write-Host "Broke Knight server stopped."
} else {
  Write-Host "No running Broke Knight server was found."
}

Remove-Item (Join-Path $root ".broke-knight-server.json") -Force -ErrorAction SilentlyContinue
