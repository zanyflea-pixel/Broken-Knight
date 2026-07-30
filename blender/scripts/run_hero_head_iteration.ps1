$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$blenderDir = Join-Path $projectRoot "blender"
$blenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
$buildScript = Join-Path $PSScriptRoot "build_hero_head_test.py"
$renderScript = Join-Path $PSScriptRoot "render_hero_head_test.py"
$headBlend = Join-Path $blenderDir "hero_head_test.blend"
$statusPath = Join-Path $blenderDir "head_test_status.json"

$env:BK_FAST_PREVIEW = "0"
$env:BK_HERO_FAST_LOOP = "0"

& $blenderExe --background --python $buildScript
if ($LASTEXITCODE -ne 0) {
    throw "The isolated head build failed. The accepted hero was not changed."
}

$status = Get-Content $statusPath -Raw | ConvertFrom-Json
if ($status.valid -ne $true) {
    throw "The isolated head failed mesh validation. The accepted hero was not changed."
}

& $blenderExe --background $headBlend --python $renderScript
if ($LASTEXITCODE -ne 0) {
    throw "The isolated head preview render failed. The accepted hero was not changed."
}

Write-Host "Head test accepted by automatic checks. hero_base.blend remains untouched."
