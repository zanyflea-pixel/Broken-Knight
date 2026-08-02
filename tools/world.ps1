param(
    [ValidateSet("check", "play", "import", "clean", "trees", "grass", "outcrops", "verges", "perf")]
    [string]$Action = "check"
)

$ErrorActionPreference = "Stop"

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godotProject = Join-Path $projectRoot "godot"
$godotConsole = Join-Path $projectRoot "tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
$godotEditor = Join-Path $projectRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
$profile = Join-Path $godotProject "data\world\profile.json"

function Assert-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }
}

function Test-WorldProfile {
    Assert-File $profile
    $data = Get-Content -LiteralPath $profile -Raw | ConvertFrom-Json
    foreach ($required in @("world_size", "spawn_site", "town_sites", "river_corridors", "road_corridors", "ford_sites")) {
        if (-not $data.PSObject.Properties.Name.Contains($required)) {
            throw "World profile is missing '$required'."
        }
    }
    Write-Output "WORLD_PROFILE_OK|towns=$($data.town_sites.Count)|rivers=$($data.river_corridors.Count)|roads=$($data.road_corridors.Count)|crossings=$($data.ford_sites.Count)"
}

function Invoke-GodotCheck([string]$Script) {
    Write-Output "RUN|$Script"
    & $godotConsole --headless --path $godotProject --script "res://tools/verification/$Script"
    if ($LASTEXITCODE -ne 0) {
        throw "World verification failed: $Script"
    }
}

switch ($Action) {
    "check" {
        Assert-File $godotConsole
        Test-WorldProfile
        foreach ($script in @(
            "verify_world_gameplay_pass.gd",
            "verify_world_map_pass.gd",
            "verify_surface_collision_pass.gd",
            "verify_river_spatial_cache.gd",
            "verify_castle_tree_pass.gd",
            "verify_highland_outcrop_pass.gd",
            "verify_roadside_verge_pass.gd",
            "verify_world_optimization_pass.gd",
            "verify_solid_world_pass.gd"
        )) {
            Invoke-GodotCheck $script
        }
        Write-Output "WORLD_CHECKS_PASSED"
    }
    "play" {
        Assert-File $godotEditor
        Start-Process -FilePath $godotEditor -WorkingDirectory $godotProject -ArgumentList "--path", $godotProject, "--scene", "res://scenes/Main.tscn", "--single-window"
    }
    "import" {
        Assert-File $godotConsole
        & $godotConsole --headless --path $godotProject --editor --quit
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed." }
    }
    "clean" {
        $worldGenerated = @(
            (Join-Path $godotProject "artifacts"),
            (Join-Path $godotProject "tools\blender\__pycache__"),
            (Join-Path $projectRoot "blender\world\scripts\__pycache__"),
            (Join-Path $projectRoot "blender\world\preview"),
            (Join-Path $projectRoot "blender\world\previews"),
            (Join-Path $projectRoot "tmp\story-docx-review")
        )
        foreach ($path in $worldGenerated) {
            $fullPath = [System.IO.Path]::GetFullPath($path)
            if (-not $fullPath.StartsWith($projectRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing path outside project: $fullPath"
            }
            if (Test-Path -LiteralPath $fullPath) {
                Remove-Item -LiteralPath $fullPath -Recurse -Force
            }
        }
        Get-ChildItem -LiteralPath (Join-Path $projectRoot "blender\world") -Recurse -File -Filter "*.blend1" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Get-ChildItem -LiteralPath (Join-Path $godotProject "tools\blender") -File -Filter "realistic_*_v1.blend1" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Write-Output "WORLD_GENERATED_FILES_CLEAN"
    }
    "trees" {
        Assert-File $blender
        $script = Join-Path $projectRoot "blender\world\scripts\create_tree_species.py"
        Assert-File $script
        & $blender -b --python $script
        if ($LASTEXITCODE -ne 0) { throw "Tree export failed." }
    }
    "grass" {
        Assert-File $blender
        $script = Join-Path $projectRoot "blender\world\scripts\build_ground_cover.py"
        Assert-File $script
        & $blender -b --python $script
        if ($LASTEXITCODE -ne 0) { throw "Ground-cover export failed." }
    }
    "outcrops" {
        Assert-File $blender
        $script = Join-Path $projectRoot "blender\world\scripts\build_highland_outcrop.py"
        Assert-File $script
        & $blender -b --python $script
        if ($LASTEXITCODE -ne 0) { throw "Highland outcrop export failed." }
    }
    "verges" {
        Assert-File $blender
        $script = Join-Path $projectRoot "blender\world\scripts\build_roadside_verge.py"
        Assert-File $script
        & $blender -b --python $script
        if ($LASTEXITCODE -ne 0) { throw "Roadside verge export failed." }
    }
    "perf" {
        Assert-File $godotConsole
        & $godotConsole --path $godotProject --rendering-method gl_compatibility --resolution 960x540 --script "res://tools/performance/benchmark_world_runtime.gd"
        if ($LASTEXITCODE -ne 0) { throw "World runtime benchmark failed." }
    }
}
