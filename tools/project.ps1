param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "setup", "status", "check", "save", "sync", "clean", "play", "godot", "hero")]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$Message = "",

    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godotRoot = Join-Path $projectRoot "godot"
$godotConsole = Join-Path $projectRoot "tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
$previousLocation = Get-Location

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Assert-Repository {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ".git") -PathType Container)) {
        throw "Not a Git repository: $projectRoot"
    }
}

function Show-RepositoryStatus {
    $branch = (& git branch --show-current).Trim()
    $remote = (& git remote get-url origin 2>$null)
    Write-Host ""
    Write-Host "Broken Knight repository" -ForegroundColor Cyan
    Write-Host "Folder : $projectRoot"
    Write-Host "Branch : $branch"
    Write-Host "Remote : $remote"

    if ($branch -and $remote) {
        $remoteBranch = "origin/$branch"
        & git show-ref --verify --quiet "refs/remotes/$remoteBranch"
        if ($LASTEXITCODE -eq 0) {
            $counts = ((& git rev-list --left-right --count "HEAD...$remoteBranch").Trim() -split "\s+")
            Write-Host "Ahead  : $($counts[0]) commit(s)"
            Write-Host "Behind : $($counts[1]) commit(s)"
        }
    }
    Write-Host ""
    & git status --short --branch
}

function Test-LargeFiles {
    $limit = 95MB
    $problems = @()
    $paths = @(& git ls-files --cached --others --exclude-standard)
    foreach ($relative in $paths) {
        $full = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $full
        if ($file.Length -lt $limit) { continue }
        $attribute = (& git check-attr filter -- $relative) -join ""
        if ($attribute -notmatch ": filter: lfs$") {
            $problems += "$relative ($([math]::Round($file.Length / 1MB, 1)) MB)"
        }
    }
    if ($problems.Count -gt 0) {
        throw "Files over 95 MB are not in Git LFS:`n$($problems -join "`n")"
    }
    Write-Host "REPOSITORY_SIZE_CHECK_PASSED"
}

function Invoke-GodotScript([string]$Name) {
    Write-Host "RUN|$Name"
    Invoke-Checked $godotConsole @(
        "--headless",
        "--path", $godotRoot,
        "--script", "res://tools/verification/$Name"
    )
}

function Invoke-ProjectChecks {
    if (-not (Test-Path -LiteralPath $godotConsole -PathType Leaf)) {
        throw "Godot console executable is missing. Run 'git lfs pull' first."
    }
    Test-LargeFiles
    Invoke-Checked (Join-Path $projectRoot "tools\world.ps1") @("check")
    foreach ($script in @(
        "verify_default_warrior.gd",
        "verify_hero_visual_animation.gd",
        "verify_hero_glb.gd",
        "verify_royal_weapon_assets.gd",
        "verify_equipment_fit_parity.gd",
        "verify_admin_combat_modes.gd",
        "verify_branding.gd",
        "verify_cave_dragon_asset.gd",
        "verify_imp_enemy.gd"
    )) {
        Invoke-GodotScript $script
    }
    Invoke-Checked git @("-c", "core.safecrlf=false", "diff", "--check")
    Write-Host "ALL_PROJECT_CHECKS_PASSED" -ForegroundColor Green
}

function Initialize-RepositoryTools {
    Invoke-Checked git @("lfs", "install", "--local")
    Invoke-Checked git @("config", "--local", "core.autocrlf", "false")
    Invoke-Checked git @("config", "--local", "core.safecrlf", "warn")
    Invoke-Checked git @("config", "--local", "pull.ff", "only")
    Invoke-Checked git @("config", "--local", "fetch.prune", "true")
    Invoke-Checked git @("config", "--local", "merge.conflictStyle", "zdiff3")
    Invoke-Checked git @("config", "--local", "diff.algorithm", "histogram")
    Invoke-Checked git @("config", "--local", "rerere.enabled", "true")
    Write-Host "GIT_SETUP_COMPLETE" -ForegroundColor Green
    Show-RepositoryStatus
}

function Save-Checkpoint {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        throw 'Provide a message, for example: project.bat save "improve sword swing"'
    }
    $alreadyStaged = @(& git diff --cached --name-only)
    if ($alreadyStaged.Count -gt 0) {
        throw "Files are already staged. Commit or unstage them before using the guided save command."
    }
    if (-not $SkipChecks) {
        Invoke-ProjectChecks
    } else {
        Test-LargeFiles
        Write-Warning "Checks were skipped by request."
    }

    Invoke-Checked git @("add", "--all")
    $canonicalHeroGlbs = @(
        "godot/assets/hero/hero_full_continuous_body.glb",
        "godot/assets/hero/hero_base_body.glb"
    )
    foreach ($canonicalHeroGlb in $canonicalHeroGlbs) {
        if (Test-Path -LiteralPath (Join-Path $projectRoot $canonicalHeroGlb) -PathType Leaf) {
            Invoke-Checked git @("add", "--renormalize", "--", $canonicalHeroGlb)
        }
    }
    $staged = @(& git diff --cached --name-only)
    if ($staged.Count -eq 0) {
        Write-Host "Nothing to save."
        return
    }

    Write-Host ""
    & git diff --cached --stat
    $answer = Read-Host "Commit this checkpoint? [y/N]"
    if ($answer -notmatch "^(y|yes)$") {
        Invoke-Checked git @("reset", "--quiet", "HEAD")
        Write-Host "Cancelled. Your files are unchanged and unstaged."
        return
    }
    Invoke-Checked git @("commit", "-m", $Message)
    Write-Host "CHECKPOINT_SAVED|Run 'project.bat sync' to push it to GitHub." -ForegroundColor Green
}

function Sync-Repository {
    $dirty = @(& git status --porcelain)
    if ($dirty.Count -gt 0) {
        throw "The project has unsaved changes. Run 'project.bat save <message>' before syncing."
    }
    $branch = (& git branch --show-current).Trim()
    if (-not $branch) { throw "Detached HEAD is not supported by the guided sync command." }
    Invoke-Checked git @("fetch", "--prune", "origin")
    Invoke-Checked git @("pull", "--ff-only", "origin", $branch)
    Invoke-Checked git @("push", "origin", $branch)
    Write-Host "GITHUB_SYNC_COMPLETE|branch=$branch" -ForegroundColor Green
}

function Show-Help {
    @"
Broken Knight command center

  project.bat setup                 Configure this clone safely (run once)
  project.bat status                Show local changes and GitHub alignment
  project.bat check                 Run world, hero, combat, and asset checks
  project.bat save "message"        Test and create a local Git checkpoint
  project.bat sync                  Fast-forward pull, then push a clean branch
  project.bat clean                 Remove ignored generated files and reviews
  project.bat play                  Run the game
  project.bat godot                 Open the Godot editor
  project.bat hero                  Open the canonical hero in Blender

Recommended daily loop:
  project.bat status
  project.bat godot
  project.bat check
  project.bat save "describe the working change"
  project.bat sync
"@ | Write-Host
}

$exitCode = 0
try {
    Set-Location -LiteralPath $projectRoot
    Assert-Repository
    switch ($Action) {
        "help" { Show-Help }
        "setup" { Initialize-RepositoryTools }
        "status" {
            & git fetch --prune --quiet origin
            if ($LASTEXITCODE -ne 0) { Write-Warning "Could not refresh origin; showing cached remote status." }
            Show-RepositoryStatus
        }
        "check" { Invoke-ProjectChecks }
        "save" { Save-Checkpoint }
        "sync" { Sync-Repository }
        "clean" {
            $answer = Read-Host "Delete captures, temporary files, previews, logs, and Blender autosaves? [y/N]"
            if ($answer -match "^(y|yes)$") {
                Invoke-Checked (Join-Path $projectRoot "tools\clean-generated.ps1") @()
                Write-Host "PROJECT_CLEAN_COMPLETE" -ForegroundColor Green
            } else {
                Write-Host "Clean cancelled."
            }
        }
        "play" { & (Join-Path $projectRoot "play-godot-world.bat") }
        "godot" { & (Join-Path $projectRoot "start-godot.ps1") }
        "hero" { & (Join-Path $projectRoot "open-hero-blender.bat") }
    }
} catch {
    Write-Host "ERROR|$($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    Set-Location -LiteralPath $previousLocation
}
exit $exitCode
