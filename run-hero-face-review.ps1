$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotExe = Join-Path $repoRoot "tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
$projectDir = Join-Path $repoRoot "godot"
$projectPath = Join-Path $projectDir "project.godot"
$capturesDir = Join-Path $env:APPDATA "Godot\app_userdata\Broken Knight\captures"

if (-not (Test-Path $godotExe)) {
  throw "Godot console executable not found at $godotExe"
}

if (-not (Test-Path $projectPath)) {
  throw "Godot project not found at $projectPath"
}

New-Item -ItemType Directory -Force -Path $capturesDir | Out-Null

& $godotExe --path $projectDir --scene "res://scenes/HeroLab.tscn" -- --capture-face-review-pack --quit-after-capture

if ($LASTEXITCODE -ne 0) {
  throw "Hero face review pack capture failed with exit code $LASTEXITCODE"
}

Write-Host "Hero face review pack updated in: $capturesDir"
