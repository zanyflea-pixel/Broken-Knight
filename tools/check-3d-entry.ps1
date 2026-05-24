param(
  [string]$BaseUrl = $env:BROKE_KNIGHT_URL
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failed = $false

function Fail([string]$message) {
  Write-Host $message -ForegroundColor Red
  $script:failed = $true
}

function Ok([string]$message) {
  Write-Host $message
}

$indexPath = Join-Path $root "index.html"
$index3dPath = Join-Path $root "index-3d.html"

if (!(Test-Path -LiteralPath $indexPath -PathType Leaf)) {
  Fail "MISSING file index.html"
}

if (!(Test-Path -LiteralPath $index3dPath -PathType Leaf)) {
  Fail "MISSING file index-3d.html"
}

if (-not $failed) {
  $indexText = [System.IO.File]::ReadAllText($indexPath)
  $index3dText = [System.IO.File]::ReadAllText($index3dPath)

  if ($indexText -match 'index-3d\.html\?cb=') {
    Ok "OK root redirects to cache-busted 3D entry"
  } else {
    Fail "ROOT page is not redirecting to the cache-busted 3D entry"
  }

  $required3dMarkers = @(
    'id="boot-loading"',
    'id="three-canvas"',
    'id="ui-canvas"',
    'src="./src/main3d.js'
  )

  foreach ($marker in $required3dMarkers) {
    if ($index3dText.Contains($marker)) {
      Ok "OK 3D marker $marker"
    } else {
      Fail "MISSING 3D marker $marker"
    }
  }
}

if (![string]::IsNullOrWhiteSpace($BaseUrl)) {
  try {
    $rootUrl = $BaseUrl.TrimEnd('/')
    $urls = @(
      @{ Name = "root"; Url = "$rootUrl/" },
      @{ Name = "3d"; Url = "$rootUrl/index-3d.html?healthcheck=1" }
    )

    foreach ($entry in $urls) {
      $res = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $entry.Url -TimeoutSec 4
      if ($res.StatusCode -eq 200) {
        Ok "OK http $($entry.Name)"
      } else {
        Fail "HTTP $($res.StatusCode) $($entry.Name)"
        continue
      }

      if ($entry.Name -eq "root" -and $res.Content -notmatch 'index-3d\.html\?cb=') {
        Fail "ROOT response is not forwarding to the cache-busted 3D entry"
      }

      if ($entry.Name -eq "3d") {
        foreach ($marker in @('id="boot-loading"', 'id="three-canvas"', 'id="ui-canvas"', 'main3d.js')) {
          if ($res.Content -match [Regex]::Escape($marker)) {
            Ok "OK live 3D marker $marker"
          } else {
            Fail "MISSING live 3D marker $marker"
          }
        }
      }
    }
  } catch {
    Fail "3D entry HTTP check failed at ${BaseUrl}: $($_.Exception.Message)"
  }
} else {
  Write-Host "3D entry HTTP checks skipped (no BaseUrl provided)" -ForegroundColor DarkYellow
}

if ($failed) {
  exit 1
}

Write-Host "3D entry checks passed"
