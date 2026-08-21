$ErrorActionPreference = "Stop"

$desktop = "C:\Users\Jimmy\Desktop"
$projectRoot = "C:\Users\Jimmy\Desktop\Broken Knight"
$godotExe = Join-Path $projectRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
$godotDir = Join-Path $projectRoot "godot"
$playBat = Join-Path $projectRoot "play-godot-world.bat"
$blenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
$heroBlend = Join-Path $projectRoot "blender\BrokenKnight_Hero_Master.blend"

$removeShortcuts = @(
    "C:\Users\Jimmy\Desktop\Broke Knight Game.lnk",
    "C:\Users\Jimmy\Desktop\Broke Knight Runner.lnk",
    "C:\Users\Jimmy\Desktop\Broke Knight Godot.lnk",
    "C:\Users\Jimmy\Desktop\Broken Knight Game.lnk",
    "C:\Users\Jimmy\Desktop\Broken Knight Runner.lnk",
    "C:\Users\Jimmy\Desktop\Broken Knight Godot.lnk"
)

foreach ($path in $removeShortcuts) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$shell = New-Object -ComObject WScript.Shell

$playShortcut = $shell.CreateShortcut((Join-Path $desktop "Broken Knight - Play.lnk"))
$playShortcut.TargetPath = $playBat
$playShortcut.WorkingDirectory = $projectRoot
$playShortcut.IconLocation = "$godotExe,0"
$playShortcut.Description = "Play Broken Knight"
$playShortcut.Save()

$editorShortcut = $shell.CreateShortcut((Join-Path $desktop "Broken Knight - Godot Editor.lnk"))
$editorShortcut.TargetPath = $godotExe
$editorShortcut.Arguments = "--path `"$godotDir`""
$editorShortcut.WorkingDirectory = $godotDir
$editorShortcut.IconLocation = "$godotExe,0"
$editorShortcut.Description = "Open Broken Knight in Godot"
$editorShortcut.Save()

if (Test-Path -LiteralPath $blenderExe) {
    $heroShortcut = $shell.CreateShortcut((Join-Path $desktop "Broken Knight - Hero Blender.lnk"))
    $heroShortcut.TargetPath = $blenderExe
    $heroShortcut.Arguments = "`"$heroBlend`""
    $heroShortcut.WorkingDirectory = (Join-Path $projectRoot "blender")
    $heroShortcut.IconLocation = "$blenderExe,0"
    $heroShortcut.Description = "Open Broken Knight hero master in Blender"
    $heroShortcut.Save()
}

Get-ChildItem -LiteralPath $desktop -Filter "Broken Knight*.lnk" |
    Select-Object Name, FullName |
    Sort-Object Name
