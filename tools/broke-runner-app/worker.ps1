param(
    [string]$ProjectRoot = "C:\Users\Jimmy\Desktop\Broken Knight",
    [ValidateSet("apply-package","push","capture","upload-latest","push-error")]
    [string]$Mode = "push",
    [string]$PackagePath = ""
)

$ErrorActionPreference = "Stop"

$AppRoot = Join-Path $ProjectRoot "tools\broke-runner-app"
$StatusFile = Join-Path $AppRoot "status.json"
$ProcessedFile = Join-Path $AppRoot "processed.json"
$Uploader = Join-Path $AppRoot "upload.ps1"
$OutputDir = Join-Path $ProjectRoot "Powershell output"
$TestFile = Join-Path $OutputDir "test.txt"
$LogFile = Join-Path $OutputDir "ai-runner.log"
$CaptureDir = Join-Path $ProjectRoot "captures"
$GodotExe = Join-Path $ProjectRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$GodotProject = Join-Path $ProjectRoot "godot"

New-Item -ItemType Directory -Force -Path $AppRoot,$OutputDir,$CaptureDir | Out-Null

function Log([string]$m) {
    Add-Content -LiteralPath $LogFile -Value ("{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m) -Encoding UTF8
}

function Report([string]$m) {
    Add-Content -LiteralPath $TestFile -Value $m -Encoding UTF8
}

function Status([bool]$Busy,[string]$Step,[string]$Detail,[string]$Result="") {
    [ordered]@{
        busy=$Busy
        step=$Step
        detail=$Detail
        result=$Result
        time=(Get-Date -Format "o")
    } | ConvertTo-Json | Set-Content -LiteralPath $StatusFile -Encoding UTF8
}

function Load-Processed {
    $h=@{}
    if (-not (Test-Path -LiteralPath $ProcessedFile -PathType Leaf)) { return $h }
    try {
        $obj=Get-Content -LiteralPath $ProcessedFile -Raw | ConvertFrom-Json
        foreach($p in $obj.PSObject.Properties){$h[$p.Name]=[string]$p.Value}
    } catch {}
    return $h
}

function Save-Processed([hashtable]$h) {
    $o=[ordered]@{}
    foreach($k in ($h.Keys|Sort-Object)){$o[$k]=$h[$k]}
    $o|ConvertTo-Json|Set-Content -LiteralPath $ProcessedFile -Encoding UTF8
}

function Apply-Package([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Package not found: $Path"
    }

    $item=Get-Item -LiteralPath $Path
    $sig="$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"

    # LOOP SAFETY:
    # Record this exact ZIP attempt before executing it. If the update fails,
    # the auto-watcher will NOT repeatedly launch the same broken ZIP forever.
    # Re-downloading a corrected ZIP creates a new path/signature and is eligible.
    $processed=Load-Processed
    $processed[$item.FullName]=$sig
    Save-Processed $processed

    Status $true "Applying update" $item.Name
    Log "APP_UPDATE_START|$($item.Name)"
    Report "UPDATE_PACKAGE: $($item.FullName)"
    Report "UPDATE_PACKAGE_BYTES: $($item.Length)"
    Report "UPDATE_PACKAGE_MTIME_UTC: $($item.LastWriteTimeUtc.ToString("o"))"
    Report "UPDATE_PACKAGE_SIGNATURE: $sig"

    $temp=Join-Path $env:TEMP ("BrokeKnightApp_"+[guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $temp|Out-Null

    try {
        Expand-Archive -LiteralPath $item.FullName -DestinationPath $temp -Force

        $manifestPath=Join-Path $temp "manifest.json"
        $updatePath=Join-Path $temp "update.ps1"

        if (-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "manifest.json missing"}
        if (-not(Test-Path -LiteralPath $updatePath -PathType Leaf)){throw "update.ps1 missing"}

        $manifestRaw=Get-Content -LiteralPath $manifestPath -Raw
        Report "MANIFEST_RAW: $($manifestRaw -replace "`r?`n"," ")"
        $manifest=$manifestRaw|ConvertFrom-Json
        if([int]$manifest.broken_knight_ai_package -ne 1){throw "invalid package manifest"}
        Report "MANIFEST_NAME: $($manifest.name)"
        Report "MANIFEST_CAPTURE: $($manifest.capture)"

        $args="-NoProfile -ExecutionPolicy Bypass -File `"$updatePath`" -ProjectRoot `"$ProjectRoot`""
        Report "UPDATE_PROCESS_START"
        $p=Start-Process powershell.exe -ArgumentList $args -PassThru
        Report "UPDATE_PROCESS_PID: $($p.Id)"
        $p.WaitForExit()
        Report "UPDATE_PROCESS_EXIT: $($p.ExitCode)"
        if($p.ExitCode -ne 0){throw "update script exit $($p.ExitCode)"}

        Log "APP_UPDATE_SUCCESS|$($item.Name)"
        Report "UPDATE_RESULT: SUCCESS"
        return $true
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Capture-Game {
    Status $true "Recording game" "Godot is capturing a fresh video..."
    Log "APP_CAPTURE_START"
    Report "CAPTURE_START"

    if (-not(Test-Path -LiteralPath $GodotExe -PathType Leaf)){throw "Godot executable missing"}

    $avi=Join-Path $CaptureDir ("push_to_chatgpt_{0}.avi" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $args="--path `"$GodotProject`" --write-movie `"$avi`" --fixed-fps 30"

    $p=Start-Process -FilePath $GodotExe -ArgumentList $args -PassThru
    Report "GODOT_PID: $($p.Id)"
    Report "CAPTURE_TARGET: $avi"
    Report "CAPTURE_WAIT_SECONDS: 12"

    Start-Sleep -Seconds 12

    try {
        if(-not$p.HasExited){
            [void]$p.CloseMainWindow()
            Start-Sleep -Seconds 3
        }
    } catch {}

    try {
        if(-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
    } catch {}

    Start-Sleep -Seconds 2

    Report "CAPTURE_FILE_EXISTS_AFTER_GODOT: $(Test-Path -LiteralPath $avi -PathType Leaf)"
    if(-not(Test-Path -LiteralPath $avi -PathType Leaf)){throw "capture file was not created"}
    Report "CAPTURE_FILE_BYTES_AFTER_GODOT: $((Get-Item -LiteralPath $avi).Length)"
    if((Get-Item -LiteralPath $avi).Length -le 0){throw "capture file is empty"}

    Log "APP_CAPTURE_SUCCESS|$avi"
    Report "CAPTURE_RESULT: SUCCESS"
    Report "CAPTURE_FILE: $avi"
    return $avi
}

function Upload-Video([string]$Avi) {
    Status $true "Uploading to ChatGPT" ([IO.Path]::GetFileName($Avi))
    Log "APP_UPLOAD_START|$Avi"
    Report "UPLOAD_START: $Avi"

    $args="-NoProfile -STA -ExecutionPolicy Bypass -File `"$Uploader`" -ProjectRoot `"$ProjectRoot`" -VideoPath `"$Avi`""
    Report "UPLOADER_PROCESS_START"
    $p=Start-Process powershell.exe -ArgumentList $args -PassThru
    Report "UPLOADER_PID: $($p.Id)"
    $p.WaitForExit()
    Report "UPLOADER_EXIT_CODE: $($p.ExitCode)"
    if($p.ExitCode -ne 0){throw "uploader exit $($p.ExitCode)"}

    Log "APP_UPLOAD_DONE|$Avi"
    return $true
}

$created=$false
$mutex=New-Object System.Threading.Mutex($true,"Global\BrokeKnightRunnerAppWorker",[ref]$created)
if(-not$created){exit 0}

$ErrorSnapshot = ""

Report ""
Report "================================================================"
Report ("RUN_START: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"))
Report "BROKE KNIGHT RUNNER APP"
Report "MODE: $Mode"
Report "WORKER_PID: $PID"
Report "POWERSHELL_VERSION: $($PSVersionTable.PSVersion)"
Report "PROJECT_ROOT: $ProjectRoot"
Report "APP_ROOT: $AppRoot"
Report "CAPTURE_DIR: $CaptureDir"
Report "GODOT_EXE_EXISTS: $(Test-Path -LiteralPath $GodotExe -PathType Leaf)"
Report "GODOT_PROJECT_EXISTS: $(Test-Path -LiteralPath $GodotProject -PathType Container)"
Report "UPLOADER_EXISTS: $(Test-Path -LiteralPath $Uploader -PathType Leaf)"

if ($Mode -eq "push-error") {
    if (-not (Test-Path -LiteralPath $TestFile -PathType Leaf)) {
        "BROKE KNIGHT RUNNER APP`r`nNo test.txt existed when Push Error TXT was pressed." |
            Set-Content -LiteralPath $TestFile -Encoding UTF8
    }

    $ErrorSnapshot = Join-Path $OutputDir ("error_to_chatgpt_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Copy-Item -LiteralPath $TestFile -Destination $ErrorSnapshot -Force
    Report "PUSH_ERROR_TXT_SNAPSHOT: $ErrorSnapshot"
    Report "PUSH_ERROR_TXT_BYTES: $((Get-Item -LiteralPath $ErrorSnapshot).Length)"
}

try {
    Status $true "Starting" $Mode

    switch($Mode){
        "apply-package" {
            Apply-Package $PackagePath|Out-Null
            Status $false "Ready" "" "Update installed"
        }

        "capture" {
            $avi=Capture-Game
            Status $false "Ready" $avi "Capture complete"
        }

        "upload-latest" {
            $latest=Get-ChildItem -LiteralPath $CaptureDir -Filter "*.avi" -File -ErrorAction SilentlyContinue|
                Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
            if(-not$latest){throw "no AVI capture found"}
            Upload-Video $latest.FullName|Out-Null
            Status $false "Ready" $latest.FullName "Upload finished - press Send"
        }

        "push-error" {
            if ([string]::IsNullOrWhiteSpace($ErrorSnapshot) -or -not (Test-Path -LiteralPath $ErrorSnapshot -PathType Leaf)) {
                throw "could not create error TXT snapshot"
            }
            Status $true "Uploading error TXT" ([IO.Path]::GetFileName($ErrorSnapshot))
            Log "APP_PUSH_ERROR_START|$ErrorSnapshot"
            Upload-Video $ErrorSnapshot|Out-Null
            Status $false "Ready" $ErrorSnapshot "Error TXT attached - press Send"
        }

        "push" {
            $avi=Capture-Game
            Upload-Video $avi|Out-Null
            Status $false "Ready" $avi "Video attached - press Send"
        }
    }

    Report "RESULT: SUCCESS"
    Report ("RUN_END: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"))
} catch {
    $message=$_.Exception.Message
    Log "APP_WORKER_FAILED|$Mode|$message"
    Report "RESULT: FAILED"
    Report "ERROR: $message"
    Report "ERROR_TYPE: $($_.Exception.GetType().FullName)"
    Report "ERROR_LINE: $($_.InvocationInfo.ScriptLineNumber)"
    Report "ERROR_TEXT: $($_.InvocationInfo.Line)"
    Report ("RUN_END: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"))
    Status $false "Ready" "Open or upload test.txt for the error details." "FAILED"
} finally {
    try{$mutex.ReleaseMutex()}catch{}
    try{$mutex.Dispose()}catch{}
}
