param(
  [string]$Root = "C:\Users\Jimmy\Desktop\Broken Knight"
)
$backupRoot = Join-Path $Root 'backups\hero-face'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = Join-Path $backupRoot $ts
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $Root 'godot\scripts\HeroVisual.gd') (Join-Path $dest 'HeroVisual.gd')
$capture = Join-Path $env:APPDATA 'Godot\app_userdata\Broken Knight\captures\hero_face_sheet.png'
if (Test-Path $capture) {
  Copy-Item $capture (Join-Path $dest 'hero_face_sheet.png')
}
Set-Content -Path (Join-Path $dest 'README.txt') -Value @(
  "Backup created: $ts",
  "Source: $Root\godot\scripts\HeroVisual.gd",
  "Capture included if present."
)
Write-Output $dest
