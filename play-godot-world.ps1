$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotExe = Join-Path $repoRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$projectDir = Join-Path $repoRoot "godot"
$projectPath = Join-Path $projectDir "project.godot"

if (-not (Test-Path $godotExe)) {
  throw "Godot executable not found at $godotExe"
}

if (-not (Test-Path $projectPath)) {
  throw "Godot project not found at $projectPath"
}

Start-Process -FilePath $godotExe -WorkingDirectory $projectDir -ArgumentList $projectPath, "--scene", "res://scenes/Main.tscn"
