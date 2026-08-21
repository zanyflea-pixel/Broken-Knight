param(
    [string]$ProjectRoot = "C:\Users\Jimmy\Desktop\Broken Knight"
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$RunnerRoot = Join-Path $ProjectRoot "tools\ai-runner"
$RunnerScript = Join-Path $RunnerRoot "runner.ps1"
$AttachScript = Join-Path $RunnerRoot "attach-video.ps1"
$OutputDir = Join-Path $ProjectRoot "Powershell output"
$LogFile = Join-Path $OutputDir "ai-runner.log"
$TestFile = Join-Path $OutputDir "test.txt"
$HeartbeatFile = Join-Path $RunnerRoot "heartbeat.txt"
$CaptureDir = Join-Path $ProjectRoot "captures"

function Get-RunnerProcess {
    return Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match 'powershell' -and
        $_.CommandLine -like '*tools\ai-runner\runner.ps1*'
    } | Select-Object -First 1
}

function Start-RunnerCore {
    if (Get-RunnerProcess) { return }
    if (-not (Test-Path -LiteralPath $RunnerScript -PathType Leaf)) { return }

    $args = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RunnerScript`" -ProjectRoot `"$ProjectRoot`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
}

function Stop-RunnerCore {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match 'powershell' -and
        $_.CommandLine -like '*tools\ai-runner\runner.ps1*'
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Latest-Stage {
    if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf)) { return "Waiting for work..." }

    $lines = @(Get-Content -LiteralPath $LogFile -Tail 80)
    for ($i=$lines.Count-1; $i -ge 0; $i--) {
        $line = [string]$lines[$i]

        if ($line -match '\| UPLOAD_SUCCESS\|') { return "Video attached to ChatGPT - press Send" }
        if ($line -match '\| UPLOAD_FAILED\|') { return "Upload failed - test.txt has the error" }
        if ($line -match '\| UPLOAD_SUBMITTED\|') { return "Video submitted to ChatGPT..." }
        if ($line -match '\| UPLOAD_FILE_CHOOSER_FOUND') { return "Windows upload window found..." }
        if ($line -match '\| ATTACH_START\|') { return "Uploading capture to ChatGPT..." }
        if ($line -match '\| CAPTURE_SUCCESS\|') { return "Recording complete..." }
        if ($line -match '\| CAPTURE_START\|') { return "Godot is recording..." }
        if ($line -match '\| UPDATE_SUCCESS\|') { return "Update applied..." }
        if ($line -match '\| UPDATE_START\|') { return "Applying update..." }
        if ($line -match '\| PACKAGE_DETECTED\|') { return "New AI update detected..." }
        if ($line -match '\| PACKAGE_FAILED\|') { return "Package failed - see error report" }
        if ($line -match '\| PACKAGE_DONE\|') { return "Finished - waiting for the next update" }
        if ($line -match '\| RUNNER_STARTED') { return "Watching Downloads for AI updates" }
    }

    return "Watching Downloads for AI updates"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Broke Knight Runner"
$form.Size = New-Object System.Drawing.Size(860,610)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(760,500)

$title = New-Object System.Windows.Forms.Label
$title.Text = "BROKE KNIGHT RUNNER"
$title.Font = New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20,18)
$form.Controls.Add($title)

$runnerLabel = New-Object System.Windows.Forms.Label
$runnerLabel.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$runnerLabel.AutoSize = $true
$runnerLabel.Location = New-Object System.Drawing.Point(22,62)
$form.Controls.Add($runnerLabel)

$stageLabel = New-Object System.Windows.Forms.Label
$stageLabel.Font = New-Object System.Drawing.Font("Segoe UI",11)
$stageLabel.AutoSize = $true
$stageLabel.Location = New-Object System.Drawing.Point(22,90)
$form.Controls.Add($stageLabel)

$heartbeatLabel = New-Object System.Windows.Forms.Label
$heartbeatLabel.Font = New-Object System.Drawing.Font("Segoe UI",9)
$heartbeatLabel.AutoSize = $true
$heartbeatLabel.Location = New-Object System.Drawing.Point(22,118)
$form.Controls.Add($heartbeatLabel)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Runner"
$startButton.Size = New-Object System.Drawing.Size(110,34)
$startButton.Location = New-Object System.Drawing.Point(22,150)
$startButton.Add_Click({ Start-RunnerCore })
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop Runner"
$stopButton.Size = New-Object System.Drawing.Size(110,34)
$stopButton.Location = New-Object System.Drawing.Point(142,150)
$stopButton.Add_Click({ Stop-RunnerCore })
$form.Controls.Add($stopButton)

$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "Test Latest Video"
$testButton.Size = New-Object System.Drawing.Size(140,34)
$testButton.Location = New-Object System.Drawing.Point(262,150)
$testButton.Add_Click({
    $latest = Get-ChildItem -LiteralPath $CaptureDir -Filter "*.avi" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($latest -and (Test-Path -LiteralPath $AttachScript -PathType Leaf)) {
        Add-Content -LiteralPath $LogFile -Value ("{0} | DASHBOARD_TEST_UPLOAD|{1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$latest.FullName) -Encoding UTF8
        $args = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$AttachScript`" -ProjectRoot `"$ProjectRoot`" -VideoPath `"$($latest.FullName)`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
    }
})
$form.Controls.Add($testButton)

$capturesButton = New-Object System.Windows.Forms.Button
$capturesButton.Text = "Open Captures"
$capturesButton.Size = New-Object System.Drawing.Size(120,34)
$capturesButton.Location = New-Object System.Drawing.Point(412,150)
$capturesButton.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$CaptureDir`"" })
$form.Controls.Add($capturesButton)

$errorButton = New-Object System.Windows.Forms.Button
$errorButton.Text = "Open test.txt"
$errorButton.Size = New-Object System.Drawing.Size(110,34)
$errorButton.Location = New-Object System.Drawing.Point(542,150)
$errorButton.Add_Click({
    if (Test-Path -LiteralPath $TestFile) { Start-Process notepad.exe -ArgumentList "`"$TestFile`"" }
})
$form.Controls.Add($errorButton)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "Live activity"
$logTitle.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$logTitle.AutoSize = $true
$logTitle.Location = New-Object System.Drawing.Point(22,205)
$form.Controls.Add($logTitle)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.Font = New-Object System.Drawing.Font("Consolas",9)
$logBox.Location = New-Object System.Drawing.Point(22,232)
$logBox.Size = New-Object System.Drawing.Size(800,315)
$logBox.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($logBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $proc = Get-RunnerProcess

    if ($proc) {
        $runnerLabel.Text = "Runner: RUNNING"
    } else {
        $runnerLabel.Text = "Runner: STOPPED"
    }

    $stageLabel.Text = "Current step: " + (Latest-Stage)

    if (Test-Path -LiteralPath $HeartbeatFile -PathType Leaf) {
        $age = [Math]::Round(((Get-Date) - (Get-Item -LiteralPath $HeartbeatFile).LastWriteTime).TotalSeconds,1)
        $heartbeatLabel.Text = "Heartbeat age: $age seconds"
    } else {
        $heartbeatLabel.Text = "Heartbeat: not found"
    }

    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        $text = (Get-Content -LiteralPath $LogFile -Tail 90) -join [Environment]::NewLine
        if ($logBox.Text -ne $text) {
            $logBox.Text = $text
            $logBox.SelectionStart = $logBox.TextLength
            $logBox.ScrollToCaret()
        }
    }
})

$form.Add_Shown({
    Start-RunnerCore
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
})

[void]$form.ShowDialog()
