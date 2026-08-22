param(
    [string]$Version = "V80"
)

$ErrorActionPreference = "Stop"

$Root = "C:\Users\Jimmy\Desktop\Broken Knight"
$LogDir = "C:\Users\Jimmy\Desktop\Broken Knight\Powershell output"
$LogFile = "C:\Users\Jimmy\Desktop\Broken Knight\Powershell output\test.txt"

$LabPy = Join-Path $Root "blender\world\scripts\riverwatch_horse_lab.py"
$TunePy = Join-Path $Root "blender\world\scripts\riverwatch_horse_tuning.py"

$BlendFile = Join-Path $Root "blender\world\animals\riverwatch_horse.blend"

$FallbackGlb = Join-Path $Root "godot\assets\animals\riverwatch_horse.glb"
$FallbackImport = Join-Path $Root "godot\assets\animals\riverwatch_horse.glb.import"

$RuntimeGlb = Join-Path $Root "godot\assets\animals\riverwatch_horse_awesome.bkglb"

$AutoReview = Join-Path $Root "horse-auto-review.ps1"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$Backup = Join-Path $Root "tmp\horse_v80_backup_$Stamp"
$Work = Join-Path $Root "tmp\horse_v80_build_$Stamp"

$ModelInstalled = $false

Set-Location $Root

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $Work | Out-Null

"============================================================" | Set-Content -LiteralPath $LogFile -Encoding UTF8
"BROKEN KNIGHT HORSE $Version BUILD LOG" | Add-Content -LiteralPath $LogFile -Encoding UTF8
"============================================================" | Add-Content -LiteralPath $LogFile -Encoding UTF8
"STARTED=$(Get-Date)" | Add-Content -LiteralPath $LogFile -Encoding UTF8
"LOG_FILE=$LogFile" | Add-Content -LiteralPath $LogFile -Encoding UTF8
"" | Add-Content -LiteralPath $LogFile -Encoding UTF8


function Log {

    param(
        [string]$Text = ""
    )

    Add-Content -LiteralPath $LogFile -Value $Text -Encoding UTF8
    Write-Host $Text
}


function Find-Blender {

    $Command = Get-Command blender.exe -ErrorAction SilentlyContinue

    if ($Command) {
        return $Command.Source
    }

    $SearchRoot = "C:\Program Files\Blender Foundation"

    if (Test-Path -LiteralPath $SearchRoot) {

        $Found = Get-ChildItem -LiteralPath $SearchRoot -Filter blender.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($Found) {
            return $Found.FullName
        }
    }

    return $null
}


function Stop-Godot {

    Get-Process "Godot_v4.7-stable_win64" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Start-Sleep -Milliseconds 400
}


function Append-ProcessFile {

    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Log ""
    Log "---------------- $Label BEGIN ----------------"

    $Lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue

    foreach ($Line in $Lines) {

        Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
        Write-Host $Line
    }

    Log "---------------- $Label END ----------------"
}


function Invoke-LoggedProcess {

    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Name
    )

    $StdOut = Join-Path $Work "$Name.stdout.txt"
    $StdErr = Join-Path $Work "$Name.stderr.txt"

    if (Test-Path -LiteralPath $StdOut) {
        Remove-Item -LiteralPath $StdOut -Force
    }

    if (Test-Path -LiteralPath $StdErr) {
        Remove-Item -LiteralPath $StdErr -Force
    }

    Log ""
    Log "PROCESS_NAME=$Name"
    Log "PROCESS_FILE=$FilePath"

    $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -WindowStyle Hidden -Wait -PassThru

    Append-ProcessFile -Path $StdOut -Label "$Name STDOUT"
    Append-ProcessFile -Path $StdErr -Label "$Name STDERR"

    Log ""
    Log "PROCESS_EXIT=$($Process.ExitCode)"

    return $Process.ExitCode
}


function Restore-Backup {

    Log ""
    Log "ROLLBACK_BEGIN"

    $BackupBlend = Join-Path $Backup "riverwatch_horse.blend"
    $BackupGlb = Join-Path $Backup "riverwatch_horse.glb"
    $BackupImport = Join-Path $Backup "riverwatch_horse.glb.import"
    $BackupRuntime = Join-Path $Backup "riverwatch_horse_awesome.bkglb"

    if (Test-Path -LiteralPath $BackupBlend) {
        Copy-Item -LiteralPath $BackupBlend -Destination $BlendFile -Force
        Log "RESTORED=riverwatch_horse.blend"
    }

    if (Test-Path -LiteralPath $BackupGlb) {
        Copy-Item -LiteralPath $BackupGlb -Destination $FallbackGlb -Force
        Log "RESTORED=riverwatch_horse.glb"
    }

    if (Test-Path -LiteralPath $BackupImport) {
        Copy-Item -LiteralPath $BackupImport -Destination $FallbackImport -Force
        Log "RESTORED=riverwatch_horse.glb.import"
    }

    if (Test-Path -LiteralPath $BackupRuntime) {
        Copy-Item -LiteralPath $BackupRuntime -Destination $RuntimeGlb -Force
        Log "RESTORED=riverwatch_horse_awesome.bkglb"
    }

    Log "ROLLBACK_COMPLETE"
}


try {

    Log "============================================================"
    Log "HORSE $Version BUILD START"
    Log "============================================================"
    Log ""

    $RequiredFiles = @(
        $LabPy,
        $TunePy,
        $BlendFile,
        $FallbackGlb,
        $FallbackImport,
        $RuntimeGlb,
        $AutoReview
    )

    foreach ($Required in $RequiredFiles) {

        if (-not (Test-Path -LiteralPath $Required)) {
            throw "Missing required file: $Required"
        }

        $Info = Get-Item -LiteralPath $Required

        Log "REQUIRED_OK=$Required"
        Log "REQUIRED_BYTES=$($Info.Length)"
    }

    Log ""

    $Blender = Find-Blender

    if (-not $Blender) {
        throw "Could not locate blender.exe"
    }

    Log "BLENDER=$Blender"

    $VersionFile = Join-Path $Work "blender_version.txt"
    $VersionError = Join-Path $Work "blender_version_error.txt"

    $VersionProcess = Start-Process -FilePath $Blender -ArgumentList @("--version") -RedirectStandardOutput $VersionFile -RedirectStandardError $VersionError -WindowStyle Hidden -Wait -PassThru

    if (Test-Path -LiteralPath $VersionFile) {

        $VersionLines = Get-Content -LiteralPath $VersionFile

        if ($VersionLines.Count -gt 0) {
            Log "BLENDER_VERSION=$($VersionLines[0])"
        }
    }

    Log ""

    New-Item -ItemType Directory -Force -Path $Backup | Out-Null

    Copy-Item -LiteralPath $BlendFile -Destination (Join-Path $Backup "riverwatch_horse.blend") -Force
    Copy-Item -LiteralPath $FallbackGlb -Destination (Join-Path $Backup "riverwatch_horse.glb") -Force
    Copy-Item -LiteralPath $FallbackImport -Destination (Join-Path $Backup "riverwatch_horse.glb.import") -Force
    Copy-Item -LiteralPath $RuntimeGlb -Destination (Join-Path $Backup "riverwatch_horse_awesome.bkglb") -Force

    Log "BACKUP=$Backup"

    $OldRuntimeHash = (Get-FileHash -LiteralPath $RuntimeGlb -Algorithm SHA256).Hash

    Log "OLD_RUNTIME_SHA256=$OldRuntimeHash"
    Log ""

    Stop-Godot

    Log "============================================================"
    Log "BLENDER V80 BUILD"
    Log "============================================================"

    $QuotedLab = '"' + $LabPy + '"'

    $BlenderArgs = @(
        "--background",
        "--python",
        $QuotedLab
    )

    $BlenderExit = Invoke-LoggedProcess -FilePath $Blender -Arguments $BlenderArgs -Name "v80_blender"

    Log ""
    Log "BLENDER_EXIT=$BlenderExit"

    if ($BlenderExit -ne 0) {
        throw "V80 Blender build returned nonzero exit code $BlenderExit"
    }

    if (-not (Test-Path -LiteralPath $BlendFile)) {
        throw "V80 blend was not created."
    }

    if (-not (Test-Path -LiteralPath $FallbackGlb)) {
        throw "V80 GLB was not created."
    }

    $BlendInfo = Get-Item -LiteralPath $BlendFile
    $GeneratedInfo = Get-Item -LiteralPath $FallbackGlb

    Log "GENERATED_BLEND_BYTES=$($BlendInfo.Length)"
    Log "GENERATED_GLB_BYTES=$($GeneratedInfo.Length)"

    if ($GeneratedInfo.Length -lt 10000) {
        throw "Generated V80 GLB is unexpectedly small."
    }

    [byte[]]$GlbBytes = [System.IO.File]::ReadAllBytes($FallbackGlb)

    if ($GlbBytes.Length -lt 4) {
        throw "Generated V80 GLB has invalid length."
    }

    $Magic = [System.Text.Encoding]::ASCII.GetString($GlbBytes, 0, 4)

    Log "GENERATED_GLB_MAGIC=$Magic"

    if ($Magic -ne "glTF") {
        throw "Generated V80 file is not valid GLB data."
    }

    $NewGlbHash = (Get-FileHash -LiteralPath $FallbackGlb -Algorithm SHA256).Hash

    Log "GENERATED_GLB_SHA256=$NewGlbHash"

    if ($NewGlbHash -eq $OldRuntimeHash) {
        throw "Generated V80 GLB hash is identical to old runtime."
    }

    Copy-Item -LiteralPath $FallbackGlb -Destination $RuntimeGlb -Force

    $RuntimeHash = (Get-FileHash -LiteralPath $RuntimeGlb -Algorithm SHA256).Hash

    Log "NEW_RUNTIME_SHA256=$RuntimeHash"

    if ($RuntimeHash -ne $NewGlbHash) {
        throw "Runtime horse copy verification failed."
    }

    Copy-Item -LiteralPath (Join-Path $Backup "riverwatch_horse.glb") -Destination $FallbackGlb -Force
    Copy-Item -LiteralPath (Join-Path $Backup "riverwatch_horse.glb.import") -Destination $FallbackImport -Force

    $ModelInstalled = $true

    Log ""
    Log "MODEL_BUILD=SUCCESS"
    Log "MODEL_INSTALLED=YES"
    Log "FALLBACK_GLB_RESTORED=YES"
    Log "FALLBACK_IMPORT_RESTORED=YES"
    Log ""

    Log "============================================================"
    Log "AUTOMATIC REVIEW / PUSH"
    Log "============================================================"

    $PowerShellExe = (Get-Command powershell.exe).Source

    $QuotedReview = '"' + $AutoReview + '"'

    $ReviewArgs = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $QuotedReview,
        "-Version",
        $Version
    )

    $ReviewExit = Invoke-LoggedProcess -FilePath $PowerShellExe -Arguments $ReviewArgs -Name "auto_review"

    Log ""
    Log "AUTO_REVIEW_EXIT=$ReviewExit"

    if ($ReviewExit -ne 0) {
        throw "V80 model built, but automatic review/push failed."
    }

    Log ""
    Log "============================================================"
    Log "HORSE $Version COMPLETE"
    Log "============================================================"
    Log ""
    Log "RESULT=SUCCESS"
    Log "VERSION=$Version"
    Log "FRESH_ANATOMY_BUILD=YES"
    Log "OLD_V74_WRAPPER_USED=NO"
    Log "AUTO_REVIEW=SUCCESS"
    Log "AUTO_PUSH=SUCCESS"
    Log "FINISHED=$(Get-Date)"
    Log ""

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " HORSE V80 COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "TEST.TXT UPDATED:" -ForegroundColor Cyan
    Write-Host $LogFile -ForegroundColor Yellow
    Write-Host ""
    Write-Host "JUST TYPE: next" -ForegroundColor Yellow
    Write-Host ""

    exit 0
}
catch {

    Log ""
    Log "============================================================"
    Log "HORSE $Version FAILED"
    Log "============================================================"
    Log ""

    Log "ERROR_MESSAGE=$($_.Exception.Message)"
    Log "ERROR_TYPE=$($_.Exception.GetType().FullName)"
    Log "ERROR_POSITION=$($_.InvocationInfo.PositionMessage)"
    Log "ERROR_STACK=$($_.ScriptStackTrace)"
    Log ""

    if (-not $ModelInstalled) {

        Stop-Godot
        Restore-Backup
    }
    else {

        Log "ROLLBACK=SKIPPED"
        Log "REASON=NEW V80 MODEL ALREADY BUILT SUCCESSFULLY"
    }

    Log ""
    Log "RESULT=FAILED"
    Log "FINISHED=$(Get-Date)"
    Log ""

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " V80 FAILED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "ERROR IS IN:" -ForegroundColor Yellow
    Write-Host $LogFile -ForegroundColor Yellow
    Write-Host ""

    exit 1
}
