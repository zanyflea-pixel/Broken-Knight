param(
    [ValidateSet("normal", "static", "hidden")]
    [string]$HeroMode = "normal",
    [int]$WalkSeconds = 25,
    [string]$HeroScene = "",
    [ValidateSet("W", "Up")]
    [string]$MovementKey = "W"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $repoRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$project = Join-Path $repoRoot "godot"
$log = Join-Path $env:APPDATA "Godot\app_userdata\Broken Knight\logs\godot.log"
$previousLogWrite = if (Test-Path $log) { (Get-Item -LiteralPath $log).LastWriteTimeUtc } else { [DateTime]::MinValue }

$env:BROKEN_KNIGHT_HITCH_TRACE = "1"
$env:BROKEN_KNIGHT_HERO_DIAGNOSTIC = if ($HeroMode -eq "normal") { "" } else { $HeroMode }
$env:BROKEN_KNIGHT_HERO_SCENE = $HeroScene

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BrokenKnightInput {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@

$process = Start-Process -FilePath $godot -WorkingDirectory $project -ArgumentList @(
    "--path", ".",
    "--scene", "res://scenes/Boot.tscn",
    "--single-window"
) -PassThru

$deadline = (Get-Date).AddSeconds(70)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
    if (Test-Path $log) {
        $logItem = Get-Item -LiteralPath $log
        $currentLog = Get-Content -LiteralPath $log -Raw
        $traceMarker = "RUNTIME_TRACE|started|hero_mode=$($env:BROKEN_KNIGHT_HERO_DIAGNOSTIC)"
        if ($logItem.LastWriteTimeUtc -gt $previousLogWrite -and $currentLog.Contains($traceMarker) -and $currentLog.Contains("BOOT_PROGRESS|100|Ready")) {
            $ready = $true
            break
        }
    }
}

if (-not $ready) {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    throw "Broken Knight did not reach Ready."
}

for ($attempt = 0; $attempt -lt 20 -and $process.MainWindowHandle -eq 0; $attempt++) {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
}

[void][BrokenKnightInput]::SetForegroundWindow($process.MainWindowHandle)
Start-Sleep -Milliseconds 700

$startCpu = $process.TotalProcessorTime.TotalSeconds
$started = Get-Date
$samples = 0
$nonRespondingSamples = 0
$currentNonResponding = 0
$longestNonResponding = 0
$maxWorkingSet = 0.0
$virtualKey = if ($MovementKey -eq "Up") { 0x26 } else { 0x57 }
$scanCode = if ($MovementKey -eq "Up") { 0x48 } else { 0x11 }
$keyDownFlags = if ($MovementKey -eq "Up") { 0x0001 } else { 0 }
$keyUpFlags = $keyDownFlags -bor 0x0002

[BrokenKnightInput]::keybd_event($virtualKey, $scanCode, $keyDownFlags, [UIntPtr]::Zero)
try {
    while (((Get-Date) - $started).TotalSeconds -lt $WalkSeconds -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 50
        $process.Refresh()
        $samples++
        # Synthetic keybd_event input does not receive the hardware keyboard's
        # normal repeat stream. Refresh the held state so long desktop probes
        # do not silently release an arrow key midway through the route.
        if (($samples % 10) -eq 0) {
            [BrokenKnightInput]::keybd_event($virtualKey, $scanCode, $keyDownFlags, [UIntPtr]::Zero)
        }
        $maxWorkingSet = [Math]::Max($maxWorkingSet, $process.WorkingSet64 / 1MB)
        if (-not $process.Responding) {
            $nonRespondingSamples++
            $currentNonResponding++
            $longestNonResponding = [Math]::Max($longestNonResponding, $currentNonResponding)
        } else {
            $currentNonResponding = 0
        }
    }
} finally {
    [BrokenKnightInput]::keybd_event($virtualKey, $scanCode, $keyUpFlags, [UIntPtr]::Zero)
}

$process.Refresh()
$elapsed = ((Get-Date) - $started).TotalSeconds
$cpuSeconds = $process.TotalProcessorTime.TotalSeconds - $startCpu
Start-Sleep -Seconds 1
$trace = if (Test-Path $log) {
    Get-Content -LiteralPath $log | Where-Object { $_ -match "RUNTIME_(TRACE|HITCH)" }
} else {
    @()
}

[pscustomobject]@{
    Mode = $HeroMode
    MovementKey = $MovementKey
    Ready = $ready
    WalkSeconds = [Math]::Round($elapsed, 2)
    Samples = $samples
    NonRespondingSamples = $nonRespondingSamples
    LongestNonRespondingMs = $longestNonResponding * 50
    CpuPercent = [Math]::Round(100.0 * $cpuSeconds / $elapsed, 1)
    MaxWorkingSetMB = [Math]::Round($maxWorkingSet, 1)
    Exited = $process.HasExited
} | Format-List
$trace

if (-not $process.HasExited) {
    $null = $process.CloseMainWindow()
    Start-Sleep -Seconds 2
    $process.Refresh()
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
