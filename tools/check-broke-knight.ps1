param(
  [string]$BaseUrl = $env:BROKE_KNIGHT_URL
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$required = @(
  "index.html",
  "index-3d.html",
  "serve-broke-knight.ps1",
  "src/entities.js",
  "src/game.js",
  "src/input.js",
  "src/main.js",
  "src/main3d.js",
  "src/render3d/world3d.js",
  "src/save.js",
  "src/ui.js",
  "src/util.js",
  "src/world.js",
  "tools/check-3d-entry.ps1"
)

$failed = $false

foreach ($rel in $required) {
  $path = Join-Path $root $rel
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    Write-Host "OK file $rel"
  } else {
    Write-Host "MISSING file $rel" -ForegroundColor Red
    $failed = $true
  }
}

$imports = Select-String -Path (Join-Path $root "src\*.js") -Pattern 'from\s+["''](\./[^"'']+)["'']' -AllMatches
foreach ($matchInfo in $imports) {
  foreach ($match in $matchInfo.Matches) {
    $importRel = $match.Groups[1].Value
    $dir = Split-Path -Parent $matchInfo.Path
    $target = [System.IO.Path]::GetFullPath((Join-Path $dir $importRel))
    if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
      Write-Host "BROKEN import $($matchInfo.Path) -> $importRel" -ForegroundColor Red
      $failed = $true
    }
  }
}

if (![string]::IsNullOrWhiteSpace($BaseUrl)) {
  try {
    $modules = @("index.html") + ($required | Where-Object { $_ -like "src/*" })
    foreach ($rel in $modules) {
      $uri = "$($BaseUrl.TrimEnd('/'))/$rel"
      $res = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -TimeoutSec 3
      if ($res.StatusCode -eq 200) {
        Write-Host "OK http $rel"
      } else {
        Write-Host "HTTP $($res.StatusCode) $rel" -ForegroundColor Red
        $failed = $true
      }
    }
  } catch {
    Write-Host "HTTP checks skipped or failed at ${BaseUrl}: $($_.Exception.Message)" -ForegroundColor Yellow
  }
} else {
  Write-Host "HTTP checks skipped (no BaseUrl provided)" -ForegroundColor DarkYellow
}

$entryCheck = Join-Path $root "tools\check-3d-entry.ps1"
if (Test-Path -LiteralPath $entryCheck -PathType Leaf) {
  $entryArgs = @()
  if (![string]::IsNullOrWhiteSpace($BaseUrl)) {
    $entryArgs += @("-BaseUrl", $BaseUrl)
  }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $entryCheck @entryArgs
  if ($LASTEXITCODE -ne 0) {
    $failed = $true
  }
}

if ($failed) {
  exit 1
}

Write-Host "Broke Knight checks passed"
