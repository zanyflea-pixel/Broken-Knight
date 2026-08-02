param(
    [switch]$IncludeLegacy,
    [switch]$RebuildGodotCache
)

$ErrorActionPreference = "Stop"

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectPrefix = $projectRoot.TrimEnd("\") + "\"
$script:deletedFiles = 0
$script:deletedBytes = [int64]0

function Assert-ProjectPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (
        $fullPath -eq $projectRoot -or
        -not $fullPath.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "Refusing path outside the project: $fullPath"
    }
    return $fullPath
}

function Remove-ProjectPath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $fullPath = Assert-ProjectPath (Join-Path $projectRoot $RelativePath)
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if ($item.PSIsContainer) {
        $files = Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue
        $script:deletedFiles += $files.Count
        $script:deletedBytes += [int64](($files | Measure-Object Length -Sum).Sum)
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    } else {
        $script:deletedFiles += 1
        $script:deletedBytes += [int64]$item.Length
        Remove-Item -LiteralPath $fullPath -Force
    }
}

function Remove-ProjectFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $fullPath = Assert-ProjectPath $File.FullName
    $script:deletedFiles += 1
    $script:deletedBytes += [int64]$File.Length
    Remove-Item -LiteralPath $fullPath -Force
}

$generatedDirectories = @(
    ".agents",
    ".godot-user",
    ".godot-user-local",
    "_downloads",
    "captures",
    "Powershell output",
    "tmp",
    "tmp-map-check",
    "visual_reviews",
    "godot\artifacts",
    "blender\preview",
    "blender\previews",
    "blender\snapshots",
    "blender\scripts\backups"
)

foreach ($relativePath in $generatedDirectories) {
    Remove-ProjectPath $relativePath
}

if ($RebuildGodotCache) {
    Remove-ProjectPath "godot\.godot"
}

Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter "*.blend1" -Force -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-ProjectFile $_ }

Get-ChildItem -LiteralPath $projectRoot -Recurse -Directory -Filter "__pycache__" -Force -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    ForEach-Object {
        $relativePath = $_.FullName.Substring($projectPrefix.Length)
        Remove-ProjectPath $relativePath
    }

Get-ChildItem -LiteralPath $projectRoot -File -Force |
    Where-Object {
        $_.Extension -in ".png", ".jpg", ".jpeg" -or
        $_.Name -like "~`$*"
    } |
    ForEach-Object { Remove-ProjectFile $_ }

if ($IncludeLegacy) {
    $legacyDirectories = @(
        "assets",
        "broken-knight-rebuild-(4.0)",
        "src"
    )
    foreach ($relativePath in $legacyDirectories) {
        Remove-ProjectPath $relativePath
    }

    $legacyFiles = @(
        "all-project.txt",
        "audit-dom.txt",
        "audit-dom.txt.err",
        "audit-river-dom.html",
        "audit-river-dom-latest.html",
        "favicon.ico",
        "favicon.svg",
        "index.html",
        "index-3d.html",
        "serve-broken-knight.ps1",
        "start-broken-knight-server.ps1",
        "stop-broken-knight-server.ps1",
        "world3d-dom.html",
        "world-audit.html",
        "world-layout.html",
        "rebuild-hero-blender.bat",
        "godot_capture_stderr.txt",
        "godot_capture_stdout.txt",
        "head_capture_stderr.txt",
        "head_capture_stdout.txt",
        "play_stderr.txt",
        "play_stdout.txt",
        "tmp-current.jpg",
        "docs\GODOT-MIGRATION.md",
        "tools\audit-world.mjs",
        "tools\check-3d-entry.ps1",
        "tools\check-broken-knight.ps1",
        "tools\update-project-snapshot.ps1",
        "blender\scripts\build_hero_base.pass_backup.py",
        "blender\scripts\build_cave_dragon_pre_detail_overhaul_20260726.py",
        "blender\scripts\build_royal_armor_pre_detail_overhaul_20260726.py",
        "godot\assets\hero\hero_base_body_pre_rig_backup.glb"
    )
    foreach ($relativePath in $legacyFiles) {
        Remove-ProjectPath $relativePath
    }

    $heroAssetDirectory = Join-Path $projectRoot "godot\assets\hero"
    Get-ChildItem -LiteralPath $heroAssetDirectory -File |
        Where-Object {
            $_.Name -match "^(hero_base_body_20260726_pre_closed_harness|hero_base_body_pre_compact_sword_20260729)"
        } |
        ForEach-Object { Remove-ProjectFile $_ }

    $obsoleteBlendPattern = (
        "(?i)(\.blend1$|_pre_|^hero_base\.pre_|\.pass_backup|" +
        "lockfix_backup|_accepted|_before_|^hero_restart_pass|" +
        "^hero_\d+\.blend$|^hero_current\.blend$|" +
        "^hero_general_pass_test\.blend$|^hero_head_test\.blend$|" +
        "^hero_v2\.blend$|^hero_base_tmp|_backup_|" +
        "^hero_restart_rigged_compact_sword13_source_20260729\.blend$|" +
        "^hero_restart_rigged_gothic_first_fit\.blend$)"
    )
    Get-ChildItem -LiteralPath (Join-Path $projectRoot "blender") -File |
        Where-Object { $_.Name -match $obsoleteBlendPattern } |
        ForEach-Object { Remove-ProjectFile $_ }
}

$deletedGiB = [math]::Round($script:deletedBytes / 1GB, 2)
Write-Host "CLEANUP_COMPLETE|files=$script:deletedFiles|gb=$deletedGiB"
