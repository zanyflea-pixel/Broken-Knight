param(
    [string]$ProjectRoot = "C:\Users\Jimmy\Desktop\Broken Knight"
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$AppRoot = Join-Path $ProjectRoot "tools\broke-runner-app"
$Worker = Join-Path $AppRoot "worker.ps1"
$StatusFile = Join-Path $AppRoot "status.json"
$ProcessedFile = Join-Path $AppRoot "processed.json"
$OutputDir = Join-Path $ProjectRoot "Powershell output"
$LogFile = Join-Path $OutputDir "ai-runner.log"
$TestFile = Join-Path $OutputDir "test.txt"
$CaptureDir = Join-Path $ProjectRoot "captures"
$Downloads = Join-Path $env:USERPROFILE "Downloads"

$script:LastDiagnosticState = @{}
$script:LastHeartbeatDiagnostic = [datetime]::MinValue

function Diagnostic([string]$Message) {
    $line = "{0} | APP | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -LiteralPath $TestFile -Value $line -Encoding UTF8
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Diagnostic-Changed([string]$Key,[string]$Value) {
    if (-not $script:LastDiagnosticState.ContainsKey($Key) -or $script:LastDiagnosticState[$Key] -ne $Value) {
        $old = if ($script:LastDiagnosticState.ContainsKey($Key)) { $script:LastDiagnosticState[$Key] } else { "<unset>" }
        $script:LastDiagnosticState[$Key] = $Value
        Diagnostic "CHANGE|$Key|OLD=$old|NEW=$Value"
    }
}

function Diagnostic-Snapshot {
    try {
        $s = Read-Status
        Diagnostic-Changed "status.busy" ([string]$s.busy)
        Diagnostic-Changed "status.step" ([string]$s.step)
        Diagnostic-Changed "status.detail" ([string]$s.detail)
        Diagnostic-Changed "status.result" ([string]$s.result)
    } catch {
        Diagnostic "SNAPSHOT_ERROR|status|$($_.Exception.Message)"
    }

    try {
        $wp = Get-WorkerProcess
        $workerValue = if ($wp) { "PID=$($wp.ProcessId)" } else { "NONE" }
        Diagnostic-Changed "worker.process" $workerValue
    } catch {
        Diagnostic "SNAPSHOT_ERROR|worker|$($_.Exception.Message)"
    }

    try {
        $packages = @(Get-ChildItem -LiteralPath $Downloads -Filter "BK_AI_UPDATE_*.zip" -File -ErrorAction SilentlyContinue)
        Diagnostic-Changed "downloads.update_zip_count" ([string]$packages.Count)

        if ($packages.Count -gt 0) {
            $latestPkg = $packages | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            Diagnostic-Changed "downloads.latest_update" ("{0}|bytes={1}|mtime={2:o}" -f $latestPkg.Name,$latestPkg.Length,$latestPkg.LastWriteTimeUtc)
        } else {
            Diagnostic-Changed "downloads.latest_update" "NONE"
        }
    } catch {
        Diagnostic "SNAPSHOT_ERROR|downloads|$($_.Exception.Message)"
    }

    try {
        $captures = @(Get-ChildItem -LiteralPath $CaptureDir -Filter "*.avi" -File -ErrorAction SilentlyContinue)
        Diagnostic-Changed "captures.count" ([string]$captures.Count)

        if ($captures.Count -gt 0) {
            $latestCap = $captures | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            Diagnostic-Changed "captures.latest" ("{0}|bytes={1}|mtime={2:o}" -f $latestCap.Name,$latestCap.Length,$latestCap.LastWriteTimeUtc)
        } else {
            Diagnostic-Changed "captures.latest" "NONE"
        }
    } catch {
        Diagnostic "SNAPSHOT_ERROR|captures|$($_.Exception.Message)"
    }

    try {
        $firefox = @(Get-Process firefox -ErrorAction SilentlyContinue)
        Diagnostic-Changed "firefox.process_count" ([string]$firefox.Count)
        $chatWindows = @($firefox | Where-Object { $_.MainWindowHandle -ne 0 })
        Diagnostic-Changed "firefox.windows" ([string]$chatWindows.Count)
    } catch {
        Diagnostic "SNAPSHOT_ERROR|firefox|$($_.Exception.Message)"
    }

    if (((Get-Date) - $script:LastHeartbeatDiagnostic).TotalSeconds -ge 5) {
        $script:LastHeartbeatDiagnostic = Get-Date
        Diagnostic "HEARTBEAT|app alive|PID=$PID"
    }
}


New-Item -ItemType Directory -Force -Path $AppRoot,$OutputDir,$CaptureDir | Out-Null

function Read-Status {
    if (-not (Test-Path -LiteralPath $StatusFile -PathType Leaf)) {
        return [pscustomobject]@{ busy=$false; step="Ready"; detail=""; result="" }
    }
    try {
        return Get-Content -LiteralPath $StatusFile -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ busy=$false; step="Ready"; detail=""; result="" }
    }
}

function Get-WorkerProcess {
    return Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'powershell' -and
        $_.CommandLine -like '*tools\broke-runner-app\worker.ps1*'
    } | Select-Object -First 1
}

function Reset-Stale-BusyStatus {
    $s = Read-Status

    if ([bool]$s.busy -and -not (Get-WorkerProcess)) {
        [ordered]@{
            busy=$false
            step="Ready"
            detail="Recovered from a stale busy state."
            result="Ready"
            time=(Get-Date -Format "o")
        } | ConvertTo-Json | Set-Content -LiteralPath $StatusFile -Encoding UTF8
        return $true
    }

    return $false
}

function Worker-Busy {
    [void](Reset-Stale-BusyStatus)
    return [bool](Get-WorkerProcess)
}

function Start-Worker([string]$Mode,[string]$PackagePath="") {
    if (Worker-Busy) { return $false }
    if (-not (Test-Path -LiteralPath $Worker -PathType Leaf)) { return $false }

    $args = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Worker`" -ProjectRoot `"$ProjectRoot`" -Mode `"$Mode`""
    if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
        $args += " -PackagePath `"$PackagePath`""
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
    return $true
}

function Load-Processed {
    $h = @{}
    if (-not (Test-Path -LiteralPath $ProcessedFile -PathType Leaf)) { return $h }
    try {
        $obj = Get-Content -LiteralPath $ProcessedFile -Raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    } catch {}
    return $h
}

function Next-Unprocessed-Package {
    $processed = Load-Processed

    foreach ($f in @(
        Get-ChildItem -LiteralPath $Downloads -Filter "BK_AI_UPDATE_*.zip" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc
    )) {
        $sig = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        if (-not $processed.ContainsKey($f.FullName) -or $processed[$f.FullName] -ne $sig) {
            return $f
        }
    }
    return $null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Broken Knight Runner"
$form.Size = New-Object System.Drawing.Size(940,690)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(840,590)
$brandIconPath = Join-Path $ProjectRoot "godot\assets\branding\broken_knight.ico"
if (Test-Path -LiteralPath $brandIconPath) {
    $form.Icon = New-Object System.Drawing.Icon($brandIconPath)
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "BROKEN KNIGHT RUNNER"
$title.Font = New-Object System.Drawing.Font("Segoe UI",20,[System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22,18)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "DIAGNOSTIC MODE: manual updates only; every important state change is logged."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI",10)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(25,56)
$form.Controls.Add($subtitle)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(25,88)
$form.Controls.Add($statusLabel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Font = New-Object System.Drawing.Font("Segoe UI",9)
$detailLabel.AutoSize = $true
$detailLabel.Location = New-Object System.Drawing.Point(25,118)
$form.Controls.Add($detailLabel)

$autoBox = New-Object System.Windows.Forms.CheckBox
$autoBox.Text = "Auto-install updates (disabled for safety)"
$autoBox.Checked = $false
$autoBox.AutoSize = $true
$autoBox.Location = New-Object System.Drawing.Point(28,150)
$autoBox.Enabled = $false
$autoBox.Visible = $false
$form.Controls.Add($autoBox)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Install Update ZIP"
$applyButton.Size = New-Object System.Drawing.Size(150,38)
$applyButton.Location = New-Object System.Drawing.Point(25,190)
$applyButton.Add_Click({
    Diagnostic "BUTTON_CLICK|Install Update ZIP"

    if (Worker-Busy) {
        Diagnostic "BUTTON_BLOCKED|Install Update ZIP|worker busy"
        return
    }

    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Choose Broken Knight AI Update ZIP"
    $picker.InitialDirectory = $Downloads
    $picker.Filter = "Broken Knight AI Updates (BK_AI_UPDATE_*.zip)|BK_AI_UPDATE_*.zip|ZIP files (*.zip)|*.zip"
    $picker.Multiselect = $false
    $picker.CheckFileExists = $true

    $result = $picker.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        Diagnostic "UPDATE_PICKER_SELECTED|$($picker.FileName)"
        [void](Start-Worker "apply-package" $picker.FileName)
    } else {
        Diagnostic "UPDATE_PICKER_CANCELLED"
    }
})
$form.Controls.Add($applyButton)

$pushButton = New-Object System.Windows.Forms.Button
$pushButton.Text = "Push to ChatGPT"
$pushButton.Size = New-Object System.Drawing.Size(150,38)
$pushButton.Location = New-Object System.Drawing.Point(185,190)
$pushButton.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$pushButton.Add_Click({
    Diagnostic "BUTTON_CLICK|Push to ChatGPT"
    [void](Start-Worker "push")
})
$form.Controls.Add($pushButton)

$captureButton = New-Object System.Windows.Forms.Button
$captureButton.Text = "Capture Only"
$captureButton.Size = New-Object System.Drawing.Size(125,38)
$captureButton.Location = New-Object System.Drawing.Point(345,190)
$captureButton.Add_Click({
    Diagnostic "BUTTON_CLICK|Capture Only"
    [void](Start-Worker "capture")
})
$form.Controls.Add($captureButton)

$uploadButton = New-Object System.Windows.Forms.Button
$uploadButton.Text = "Upload Latest"
$uploadButton.Size = New-Object System.Drawing.Size(125,38)
$uploadButton.Location = New-Object System.Drawing.Point(480,190)
$uploadButton.Add_Click({
    Diagnostic "BUTTON_CLICK|Upload Latest"
    [void](Start-Worker "upload-latest")
})
$form.Controls.Add($uploadButton)

$captureFolderButton = New-Object System.Windows.Forms.Button
$captureFolderButton.Text = "Open Captures"
$captureFolderButton.Size = New-Object System.Drawing.Size(120,38)
$captureFolderButton.Location = New-Object System.Drawing.Point(615,190)
$captureFolderButton.Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$CaptureDir`""
})
$form.Controls.Add($captureFolderButton)

$errorButton = New-Object System.Windows.Forms.Button
$errorButton.Text = "Open test.txt"
$errorButton.Size = New-Object System.Drawing.Size(120,38)
$errorButton.Location = New-Object System.Drawing.Point(185,242)
$errorButton.Add_Click({
    if (Test-Path -LiteralPath $TestFile) {
        Start-Process notepad.exe -ArgumentList "`"$TestFile`""
    }
})
$form.Controls.Add($errorButton)

$pushErrorButton = New-Object System.Windows.Forms.Button
$pushErrorButton.Text = "Push Error TXT"
$pushErrorButton.Size = New-Object System.Drawing.Size(150,38)
$pushErrorButton.Location = New-Object System.Drawing.Point(25,242)
$pushErrorButton.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$pushErrorButton.Add_Click({
    Diagnostic "BUTTON_CLICK|Push Error TXT"
    [void](Start-Worker "push-error")
})
$form.Controls.Add($pushErrorButton)

$helpLabel = New-Object System.Windows.Forms.Label
$helpLabel.Text = "Push to ChatGPT = record current game -> close Godot -> attach the new video here. You press Send."
$helpLabel.Font = New-Object System.Drawing.Font("Segoe UI",9)
$helpLabel.AutoSize = $true
$helpLabel.Location = New-Object System.Drawing.Point(27,294)
$form.Controls.Add($helpLabel)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "Live activity"
$logTitle.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$logTitle.AutoSize = $true
$logTitle.Location = New-Object System.Drawing.Point(25,329)
$form.Controls.Add($logTitle)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.Font = New-Object System.Drawing.Font("Consolas",9)
$logBox.Location = New-Object System.Drawing.Point(25,357)
$logBox.Size = New-Object System.Drawing.Size(875,263)
$logBox.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($logBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    [void](Reset-Stale-BusyStatus)
    Diagnostic-Snapshot
    $s = Read-Status

    if ([bool]$s.busy) {
        $statusLabel.Text = "BUSY: " + [string]$s.step
        $applyButton.Enabled = $false
        $pushButton.Enabled = $false
        $captureButton.Enabled = $false
        $uploadButton.Enabled = $false
        $pushErrorButton.Enabled = $false
    } else {
        if (-not [string]::IsNullOrWhiteSpace([string]$s.result)) {
            $statusLabel.Text = "READY - " + [string]$s.result
        } else {
            $statusLabel.Text = "READY"
        }
        $applyButton.Enabled = $true
        $pushButton.Enabled = $true
        $captureButton.Enabled = $true
        $uploadButton.Enabled = $true
        $pushErrorButton.Enabled = $true

    }

    $detailLabel.Text = [string]$s.detail

    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        $text = (Get-Content -LiteralPath $LogFile -Tail 110) -join [Environment]::NewLine
        if ($logBox.Text -ne $text) {
            $logBox.Text = $text
            $logBox.SelectionStart = $logBox.TextLength
            $logBox.ScrollToCaret()
        }
    }
})

$form.Add_Shown({
    [void](Reset-Stale-BusyStatus)
    Diagnostic "APP_OPEN|PID=$PID|ProjectRoot=$ProjectRoot|Downloads=$Downloads"
    Diagnostic "APP_VERSION|DiagnosticModeV1"
    Diagnostic-Snapshot
    $timer.Start()
})

$form.Add_FormClosing({
    Diagnostic "APP_CLOSING|PID=$PID"
    $timer.Stop()
})

[void]$form.ShowDialog()
