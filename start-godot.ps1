$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotExe = Join-Path $repoRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$projectPath = Join-Path $repoRoot "godot\project.godot"

if (-not (Test-Path $godotExe)) {
  throw "Godot executable not found at $godotExe"
}

if (-not (Test-Path $projectPath)) {
  throw "Godot project not found at $projectPath"
}

Start-Process -FilePath $godotExe -ArgumentList "--path", (Join-Path $repoRoot "godot")
