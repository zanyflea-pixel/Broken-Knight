param(
    [string]$Version = "AUTO",
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

$Root = "C:\Users\Jimmy\Desktop\Broken Knight"
Set-Location $Root

$RuntimeHorse = Join-Path $Root "godot\assets\animals\riverwatch_horse_awesome.bkglb"
$Renderer = Join-Path $Root "captures\horse-auto-render.py"

$ReviewRoot = Join-Path $Root "captures\horse-review\auto"
$ViewsDir = Join-Path $ReviewRoot "views"
$ReviewJson = Join-Path $ReviewRoot "review.json"

$Work = Join-Path $Root "tmp\horse_auto_review_work"
$TempGlb = Join-Path $Work "horse_review.glb"

$StdOutFile = Join-Path $Work "blender.stdout.txt"
$StdErrFile = Join-Path $Work "blender.stderr.txt"


function Find-Blender {

    $Command = Get-Command blender.exe -ErrorAction SilentlyContinue

    if ($Command) {
        return $Command.Source
    }

    $SearchRoot = "C:\Program Files\Blender Foundation"

    if (Test-Path $SearchRoot) {

        $Found = Get-ChildItem $SearchRoot -Filter blender.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($Found) {
            return $Found.FullName
        }
    }

    return $null
}


function Write-Utf8NoBom {

    param(
        [string]$Path,
        [string]$Text
    )

    $Encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        $Encoding
    )
}


try {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " HORSE AUTO REVIEW $Version" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $RuntimeHorse)) {
        throw "Runtime horse missing."
    }

    if (-not (Test-Path $Renderer)) {
        throw "Renderer missing."
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw "git.exe not found."
    }

    $Blender = Find-Blender

    if (-not $Blender) {
        throw "blender.exe not found."
    }

    Write-Host "BLENDER=$Blender"
    Write-Host ""

    # ========================================================
    # GIT REPOSITORY
    # ========================================================

    $GitRoot = git rev-parse --show-toplevel

    if ($LASTEXITCODE -ne 0) {
        throw "Not inside a Git repository."
    }

    $GitRoot = $GitRoot.Trim()

    $ExpectedRoot = [System.IO.Path]::GetFullPath($Root)
    $ActualRoot = [System.IO.Path]::GetFullPath($GitRoot)

    if ($ExpectedRoot -ne $ActualRoot) {
        throw "Git root does not match Broken Knight."
    }

    $Branch = git branch --show-current

    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine Git branch."
    }

    $Branch = $Branch.Trim()

    if (-not $Branch) {
        throw "Git branch is empty."
    }

    $Remote = git remote get-url origin

    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git origin."
    }

    $Remote = $Remote.Trim()

    Write-Host "BRANCH=$Branch"
    Write-Host "ORIGIN=$Remote"
    Write-Host ""

    # ========================================================
    # DO NOT MIX WITH PRE-STAGED WORK
    # ========================================================

    $PreStaged = @(git diff --cached --name-only)

    $RealPreStaged = @()

    foreach ($Item in $PreStaged) {

        if ($Item) {

            $Trimmed = $Item.Trim()

            if ($Trimmed.Length -gt 0) {
                $RealPreStaged += $Trimmed
            }
        }
    }

    if ($RealPreStaged.Count -gt 0) {

        Write-Host "Existing staged files detected:" -ForegroundColor Yellow

        foreach ($Item in $RealPreStaged) {
            Write-Host "  $Item" -ForegroundColor Yellow
        }

        throw "Existing staged work must be cleared first."
    }

    # ========================================================
    # CLEAN WORKSPACE
    # ========================================================

    if (Test-Path $Work) {
        Remove-Item $Work -Recurse -Force
    }

    if (Test-Path $ViewsDir) {
        Remove-Item $ViewsDir -Recurse -Force
    }

    New-Item -ItemType Directory -Force $Work | Out-Null
    New-Item -ItemType Directory -Force $ViewsDir | Out-Null

    # ========================================================
    # COPY BKGLB AS TEMP GLB
    # ========================================================

    Copy-Item $RuntimeHorse $TempGlb -Force

    [byte[]]$HorseBytes = [System.IO.File]::ReadAllBytes($TempGlb)

    if ($HorseBytes.Length -lt 24) {
        throw "Runtime horse GLB is too small."
    }

    $Magic = [System.Text.Encoding]::ASCII.GetString($HorseBytes, 0, 4)

    if ($Magic -ne "glTF") {
        throw "Runtime horse is not valid GLB data."
    }

    $RuntimeHash = Get-FileHash $RuntimeHorse -Algorithm SHA256
    $RuntimeHash = $RuntimeHash.Hash

    Write-Host "RUNTIME_SHA256=$RuntimeHash"
    Write-Host ""

    # ========================================================
    # HEADLESS BLENDER
    #
    # Start-Process handles stderr without PowerShell turning
    # Blender warnings into PowerShell exceptions.
    #
    # --background means no Blender GUI window.
    # ========================================================

    $QuotedRenderer = '"' + $Renderer + '"'
    $QuotedGlb = '"' + $TempGlb + '"'
    $QuotedViews = '"' + $ViewsDir + '"'

    $BlenderArgs = @(
        "--background",
        "--python",
        $QuotedRenderer,
        "--",
        $QuotedGlb,
        $QuotedViews
    )

    Write-Host "Starting hidden Blender capture..." -ForegroundColor Cyan
    Write-Host ""

    $Process = Start-Process `
        -FilePath $Blender `
        -ArgumentList $BlenderArgs `
        -RedirectStandardOutput $StdOutFile `
        -RedirectStandardError $StdErrFile `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if (Test-Path $StdOutFile) {

        $StdOutText = Get-Content $StdOutFile -Raw

        if ($StdOutText) {

            Write-Host "---------------- BLENDER OUTPUT ----------------" -ForegroundColor DarkGray
            Write-Host $StdOutText
        }
    }

    if (Test-Path $StdErrFile) {

        $StdErrText = Get-Content $StdErrFile -Raw

        if ($StdErrText) {

            Write-Host "---------------- BLENDER STDERR ----------------" -ForegroundColor Yellow
            Write-Host $StdErrText
        }
    }

    Write-Host ""
    Write-Host "BLENDER_EXIT=$($Process.ExitCode)"
    Write-Host ""

    if ($Process.ExitCode -ne 0) {
        throw "Blender capture failed. Full Blender error is printed above."
    }

    # ========================================================
    # VERIFY REVIEW IMAGES
    # ========================================================

    $ViewFiles = @(
        "01_side_left.png",
        "02_front_3q.png",
        "03_front.png",
        "04_side_right.png",
        "05_rear_3q.png",
        "06_head_detail.png",
        "07_front_detail.png",
        "08_rear_detail.png"
    )

    foreach ($Name in $ViewFiles) {

        $ImagePath = Join-Path $ViewsDir $Name

        if (-not (Test-Path $ImagePath)) {
            throw "Missing review image: $Name"
        }

        $ImageInfo = Get-Item $ImagePath

        if ($ImageInfo.Length -lt 5000) {
            throw "Review image too small: $Name"
        }

        Write-Host "REVIEW_OK=$Name BYTES=$($ImageInfo.Length)"
    }

    # ========================================================
    # CHATGPT_HANDOFF_V8
    #
    # Compact image + Base64 + editable Blend inventory.
    # ========================================================

    $HandoffScript = Join-Path $Root "horse-review-handoff.ps1"

    if (-not (Test-Path $HandoffScript)) {
        throw "ChatGPT handoff script is missing."
    }

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $HandoffScript `
        -Version $Version

    if ($LASTEXITCODE -ne 0) {
        throw "ChatGPT review handoff failed."
    }
    # ========================================================
    # REVIEW METADATA
    # ========================================================

    $Metadata = [ordered]@{}

    $Metadata["status"] = "READY_FOR_CHATGPT"
    $Metadata["version"] = $Version
    $Metadata["generated_utc"] = (Get-Date).ToUniversalTime().ToString("o")
    $Metadata["branch"] = $Branch
    $Metadata["runtime_sha256"] = $RuntimeHash
    $Metadata["review_directory"] = "captures/horse-review/auto/views"
    $Metadata["review_count"] = 8
    $Metadata["review_views"] = $ViewFiles
    $Metadata["capture_method"] = "BLENDER_BACKGROUND"
    $Metadata["gui_windows_opened"] = 0
    $Metadata["manual_image_upload_required"] = $false
    $Metadata["manual_git_push_required"] = $false

    $MetadataJson = $Metadata | ConvertTo-Json -Depth 6

    Write-Utf8NoBom $ReviewJson $MetadataJson

    Write-Host ""
    Write-Host "REVIEW_METADATA=$ReviewJson"
    Write-Host ""

    # ========================================================
    # EXACT GIT WHITELIST
    # ========================================================

    $StagePaths = @(
        "captures/horse-auto-render.py",
        "captures/horse-model-inventory.py",
        "horse-review-handoff.ps1",
        "captures/horse-review/auto/review_chat.jpg",
        "captures/horse-review/auto/review_chat.b64.txt",
        "captures/horse-review/auto/model_inventory.json",
        "horse-auto-review.ps1",
        "captures/horse-review/auto/review.json",
        "captures/horse-review/auto/views/01_side_left.png",
        "captures/horse-review/auto/views/02_front_3q.png",
        "captures/horse-review/auto/views/03_front.png",
        "captures/horse-review/auto/views/04_side_right.png",
        "captures/horse-review/auto/views/05_rear_3q.png",
        "captures/horse-review/auto/views/06_head_detail.png",
        "captures/horse-review/auto/views/07_front_detail.png",
        "captures/horse-review/auto/views/08_rear_detail.png"
    )

    $HorseCandidates = @(
        "blender/world/scripts/build_riverwatch_stable_and_horse.py",
        "blender/world/scripts/riverwatch_horse_lab.py",
        "blender/world/scripts/riverwatch_horse_tuning.py",
        "horse-v80-build.ps1",
        "blender/world/animals/riverwatch_horse.blend",
        "blender/world/animals/riverwatch_horse_lab_base_v74.glb",
        "godot/assets/animals/riverwatch_horse_awesome.bkglb"
    )

    foreach ($Relative in $HorseCandidates) {

        $Absolute = Join-Path $Root $Relative

        if (Test-Path $Absolute) {
            $StagePaths += $Relative
        }
    }

    Write-Host "STAGING EXACT HORSE FILES:" -ForegroundColor Cyan

    foreach ($Relative in $StagePaths) {

        $Absolute = Join-Path $Root $Relative

        if (-not (Test-Path $Absolute)) {
            throw "Expected file missing: $Relative"
        }

        Write-Host "  $Relative"

        Write-Host "    EXACT_WHITELIST_FORCE_ADD=YES" -ForegroundColor Yellow

        git add -f -- $Relative

        if ($LASTEXITCODE -ne 0) {
            throw "git force-add failed for $Relative"
        }
    }

    # ========================================================
    # COMMIT
    # ========================================================

    git diff --cached --quiet

    $HasChanges = $false

    if ($LASTEXITCODE -ne 0) {
        $HasChanges = $true
    }

    if ($HasChanges) {

        $SafeVersion = $Version -replace '[^A-Za-z0-9._-]', '-'
        $CommitMessage = "horse $SafeVersion auto review"

        Write-Host ""
        Write-Host "COMMIT_MESSAGE=$CommitMessage"
        Write-Host ""

        git commit -m $CommitMessage

        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed."
        }

        $Commit = git rev-parse HEAD
        $Commit = $Commit.Trim()

        Write-Host "COMMIT=$Commit" -ForegroundColor Green
    }
    else {

        Write-Host ""
        Write-Host "NO_NEW_COMMIT_REQUIRED" -ForegroundColor Yellow
    }

    # ========================================================
    # PUSH
    # ========================================================

    if ($NoPush) {

        Write-Host ""
        Write-Host "AUTO_PUSH=SKIPPED" -ForegroundColor Yellow
    }
    else {

        Write-Host ""
        Write-Host "PUSHING TO GITHUB..." -ForegroundColor Cyan
        Write-Host ""

        git push origin $Branch

        if ($LASTEXITCODE -ne 0) {
            throw "Automatic Git push failed."
        }

        Write-Host ""
        Write-Host "AUTO_PUSH=SUCCESS" -ForegroundColor Green
    }

    # ========================================================
    # CLEAN TEMP
    # ========================================================

    if (Test-Path $Work) {
        Remove-Item $Work -Recurse -Force
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " HORSE AUTO REVIEW SUCCESS" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "8 REVIEW IMAGES: YES" -ForegroundColor Green
    Write-Host "CAPTURE WINDOWS: 0" -ForegroundColor Green
    Write-Host "MANUAL IMAGE UPLOAD: NO" -ForegroundColor Green

    if (-not $NoPush) {
        Write-Host "GITHUB PUSHED: YES" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "NOW JUST TYPE THIS IN CHATGPT:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    next" -ForegroundColor Yellow
    Write-Host ""

    exit 0
}
catch {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " HORSE AUTO REVIEW FAILED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""

    exit 1
}