param(
    [string]$ProjectRoot = "C:\Users\Jimmy\Desktop\Broken Knight"
)

$ErrorActionPreference = "Continue"

$RunnerRoot = Join-Path $ProjectRoot "tools\ai-runner"
$Downloads = Join-Path $env:USERPROFILE "Downloads"
$OutputDir = Join-Path $ProjectRoot "Powershell output"
$TestFile = Join-Path $OutputDir "test.txt"
$LogFile = Join-Path $OutputDir "ai-runner.log"
$HeartbeatFile = Join-Path $RunnerRoot "heartbeat.txt"
$StateFile = Join-Path $RunnerRoot "processed.json"
$AttachScript = Join-Path $RunnerRoot "attach-video.ps1"
$CaptureDir = Join-Path $ProjectRoot "captures"
$GodotExe = Join-Path $ProjectRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$GodotProject = Join-Path $ProjectRoot "godot"

New-Item -ItemType Directory -Force -Path $RunnerRoot,$OutputDir,$CaptureDir | Out-Null

function Log([string]$Message) {
    $line = ("{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Message)
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Report([string]$Message) {
    Add-Content -LiteralPath $TestFile -Value $Message -Encoding UTF8
}

function Heartbeat {
    Set-Content -LiteralPath $HeartbeatFile -Value (Get-Date -Format "o") -Encoding ASCII
}

function Load-State {
    $state = @{}
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { return $state }
    try {
        $raw = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) {
            $state[$p.Name] = [string]$p.Value
        }
    } catch {}
    return $state
}

function Save-State([hashtable]$State) {
    $obj = [ordered]@{}
    foreach ($k in ($State.Keys | Sort-Object)) { $obj[$k] = $State[$k] }
    $obj | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Wait-FileStable([string]$Path) {
    $last = -1L
    $same = 0
    for ($i=0; $i -lt 60; $i++) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Start-Sleep -Milliseconds 250
            continue
        }
        $size = (Get-Item -LiteralPath $Path).Length
        if ($size -gt 0 -and $size -eq $last) {
            $same++
            if ($same -ge 3) { return $true }
        } else {
            $same = 0
        }
        $last = $size
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Capture-Game([object]$Manifest) {
    if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
        Log "CAPTURE_FAILED|Godot executable missing"
        Report "CAPTURE_RESULT: FAILED - Godot executable missing"
        return $null
    }

    $seconds = 12
    try {
        if ($Manifest.PSObject.Properties.Name -contains "capture_wall_seconds") {
            $seconds = [int]$Manifest.capture_wall_seconds
        }
    } catch {}
    if ($seconds -lt 8) { $seconds = 8 }
    if ($seconds -gt 30) { $seconds = 30 }

    $name = "capture"
    try { if ($Manifest.name) { $name = [string]$Manifest.name } } catch {}
    $name = [regex]::Replace($name,'[^A-Za-z0-9_-]+','_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "capture" }

    $avi = Join-Path $CaptureDir ("{0}_{1}.avi" -f $name,(Get-Date -Format "yyyyMMdd_HHmmss"))
    Log "CAPTURE_START|$avi"
    Report "CAPTURE_START: $avi"

    try {
        $args = "--path `"$GodotProject`" --write-movie `"$avi`" --fixed-fps 30"
        $p = Start-Process -FilePath $GodotExe -ArgumentList $args -PassThru

        Start-Sleep -Seconds $seconds

        try {
            if (-not $p.HasExited) {
                [void]$p.CloseMainWindow()
                Start-Sleep -Seconds 3
            }
        } catch {}

        try {
            if (-not $p.HasExited) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}

        Start-Sleep -Seconds 2

        if ((Test-Path -LiteralPath $avi -PathType Leaf) -and ((Get-Item -LiteralPath $avi).Length -gt 0)) {
            $bytes = (Get-Item -LiteralPath $avi).Length
            Log "CAPTURE_SUCCESS|$avi|bytes=$bytes"
            Report "CAPTURE_RESULT: SUCCESS"
            Report "CAPTURE_FILE: $avi"
            return $avi
        }

        Log "CAPTURE_FAILED|empty_or_missing"
        Report "CAPTURE_RESULT: FAILED - AVI empty or missing"
        return $null
    } catch {
        Log "CAPTURE_EXCEPTION|$($_.Exception.Message)"
        Report "CAPTURE_RESULT: FAILED - $($_.Exception.Message)"
        return $null
    }
}

function Attach-Video([string]$VideoPath) {
    if (-not (Test-Path -LiteralPath $AttachScript -PathType Leaf)) {
        Log "ATTACH_FAILED|uploader missing"
        Report "ATTACH_RESULT: FAILED - uploader missing"
        return $false
    }

    Log "ATTACH_START|$VideoPath"
    Report "ATTACH_START: $VideoPath"

    try {
        $args = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$AttachScript`" -ProjectRoot `"$ProjectRoot`" -VideoPath `"$VideoPath`""
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -PassThru -Wait

        if ($p.ExitCode -eq 0) {
            Log "ATTACH_SUCCESS|$VideoPath"
            Report "ATTACH_RESULT: SUCCESS"
            return $true
        }

        Log "ATTACH_FAILED|exit=$($p.ExitCode)"
        Report "ATTACH_RESULT: FAILED - exit $($p.ExitCode)"
        return $false
    } catch {
        Log "ATTACH_EXCEPTION|$($_.Exception.Message)"
        Report "ATTACH_RESULT: FAILED - $($_.Exception.Message)"
        return $false
    }
}

$created = $false
$mutex = New-Object System.Threading.Mutex($true,"Global\BrokeKnightRunnerCore",[ref]$created)
if (-not $created) { exit 0 }

$state = Load-State

"" | Set-Content -LiteralPath $TestFile -Encoding UTF8
Report "BROKE KNIGHT RUNNER"
Report "STATUS: RUNNING"
Report "WATCHING: $Downloads"
Log "RUNNER_STARTED"
Heartbeat

try {
    while ($true) {
        try {
            Heartbeat

            $packages = @(
                Get-ChildItem -LiteralPath $Downloads -Filter "BK_AI_UPDATE_*.zip" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc
            )

            foreach ($pkg in $packages) {
                if (-not (Wait-FileStable $pkg.FullName)) { continue }

                $item = Get-Item -LiteralPath $pkg.FullName
                $sig = "$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"

                if ($state.ContainsKey($item.FullName) -and $state[$item.FullName] -eq $sig) {
                    continue
                }

                # Mark first so a bad package never repeats forever.
                $state[$item.FullName] = $sig
                Save-State $state

                "" | Set-Content -LiteralPath $TestFile -Encoding UTF8
                Report "BROKE KNIGHT RUNNER"
                Report "PACKAGE: $($item.Name)"
                Log "PACKAGE_DETECTED|$($item.Name)"

                $temp = Join-Path $env:TEMP ("BK_AI_" + [guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Force -Path $temp | Out-Null

                try {
                    Expand-Archive -LiteralPath $item.FullName -DestinationPath $temp -Force

                    $manifestPath = Join-Path $temp "manifest.json"
                    $updatePath = Join-Path $temp "update.ps1"

                    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                        Log "PACKAGE_FAILED|manifest.json missing"
                        Report "RESULT: FAILED - manifest.json missing"
                        continue
                    }

                    if (-not (Test-Path -LiteralPath $updatePath -PathType Leaf)) {
                        Log "PACKAGE_FAILED|update.ps1 missing"
                        Report "RESULT: FAILED - update.ps1 missing"
                        continue
                    }

                    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                    if ([int]$manifest.broken_knight_ai_package -ne 1) {
                        Log "PACKAGE_FAILED|invalid manifest"
                        Report "RESULT: FAILED - invalid manifest"
                        continue
                    }

                    Log "UPDATE_START|$($manifest.name)"
                    Report "UPDATE_START: $($manifest.name)"

                    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$updatePath`" -ProjectRoot `"$ProjectRoot`""
                    $update = Start-Process -FilePath "powershell.exe" -ArgumentList $args -PassThru -Wait

                    if ($update.ExitCode -ne 0) {
                        Log "UPDATE_FAILED|exit=$($update.ExitCode)"
                        Report "RESULT: FAILED - update exit $($update.ExitCode)"
                        continue
                    }

                    Log "UPDATE_SUCCESS|$($manifest.name)"
                    Report "UPDATE_RESULT: SUCCESS"

                    $captureRequested = $false
                    try { $captureRequested = [bool]$manifest.capture } catch {}

                    if (-not $captureRequested) {
                        Report "RESULT: SUCCESS"
                        Log "PACKAGE_DONE|$($manifest.name)"
                        continue
                    }

                    $avi = Capture-Game $manifest
                    if (-not $avi) {
                        Report "RESULT: FAILED - capture failed"
                        Log "PACKAGE_FAILED|capture"
                        continue
                    }

                    $attached = Attach-Video $avi
                    if ($attached) {
                        Report "RESULT: SUCCESS"
                        Log "PACKAGE_DONE|$($manifest.name)"
                    } else {
                        # BUG FIX: never report overall SUCCESS when upload failed.
                        Report "RESULT: FAILED - upload failed"
                        Log "PACKAGE_FAILED|upload"
                    }

                } catch {
                    Log "PACKAGE_EXCEPTION|$($_.Exception.Message)"
                    Report "RESULT: FAILED - $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

        } catch {
            Log "WATCHER_EXCEPTION|$($_.Exception.Message)"
            Report "WATCHER_EXCEPTION: $($_.Exception.Message)"
        }

        Heartbeat
        Start-Sleep -Seconds 2
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
