$ErrorActionPreference = "Stop"

$root = "C:\Users\Jimmy\Desktop\Broken Knight"
$blenderDir = Join-Path $root "blender"
$scriptsDir = Join-Path $blenderDir "scripts"
$previewDir = Join-Path $blenderDir "preview"
$snapshotDir = Join-Path $blenderDir "snapshots"
$blenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
$buildScript = Join-Path $scriptsDir "build_hero_base.py"
$renderScript = Join-Path $scriptsDir "render_hero_preview.py"
$metricsScript = Join-Path $scriptsDir "inspect_hero_metrics.py"
$statusPath = Join-Path $blenderDir "build_status.json"
$fastLoop = $env:BK_HERO_FAST_LOOP
if ([string]::IsNullOrWhiteSpace($fastLoop)) { $fastLoop = "1" }

New-Item -ItemType Directory -Force -Path $previewDir | Out-Null
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

& $blenderExe --background --python $buildScript

if (-not (Test-Path $statusPath)) {
    throw "Missing build status: $statusPath"
}

$status = Get-Content $statusPath | ConvertFrom-Json
$activeBlend = $status.active_blend_path
if (-not (Test-Path $activeBlend)) {
    throw "Missing active blend: $activeBlend"
}

& $blenderExe --background $activeBlend --python $renderScript
if ($fastLoop -ne "1") {
    & $blenderExe --background $activeBlend --python $metricsScript

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapshotBlend = Join-Path $snapshotDir "hero_$stamp.blend"
    Copy-Item -LiteralPath $activeBlend -Destination $snapshotBlend -Force

    $artifacts = @(
        "hero_preview.png",
        "hero_preview_side.png",
        "hero_preview_threequarter.png",
        "hero_preview_face.png",
        "hero_preview_torso.png",
        "hero_preview_manifest.json",
        "hero_metrics.json"
    )

    foreach ($artifact in $artifacts) {
        $src = Join-Path $previewDir $artifact
        if (Test-Path $src) {
            $dest = Join-Path $previewDir (($artifact -replace "\.", "_$stamp."))
            Copy-Item -LiteralPath $src -Destination $dest -Force
        }
    }
} else {
    $stamp = "FAST_LOOP"
    $snapshotBlend = ""
}

Write-Output "ACTIVE_BLEND=$activeBlend"
Write-Output "PROMOTED=$($status.promoted)"
Write-Output "SNAPSHOT_BLEND=$snapshotBlend"
Write-Output "TIMESTAMP=$stamp"
