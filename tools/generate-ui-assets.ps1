Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "assets\ui"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function New-Graphics($bitmap) {
  $g = [System.Drawing.Graphics]::FromImage($bitmap)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  return $g
}

function Save-HeroPortrait {
  $path = Join-Path $outDir "hero-portrait-knight.png"
  $bmp = New-Object System.Drawing.Bitmap 320, 400
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $bgRect = New-Object System.Drawing.Rectangle 0,0,320,400
  $bg = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $bgRect,
    [System.Drawing.Color]::FromArgb(255, 33, 24, 58),
    [System.Drawing.Color]::FromArgb(255, 9, 12, 22),
    90
  )
  $g.FillRectangle($bg, $bgRect)

  $glow = New-Object System.Drawing.Drawing2D.GraphicsPath
  $glow.AddEllipse(26, 18, 268, 268)
  $glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
  $glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(176, 129, 103, 213)
  $glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 129, 103, 213))
  $g.FillPath($glowBrush, $glow)

  $capeBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 76, 29, 59))
  $g.FillPolygon($capeBrush, @(
      [System.Drawing.PointF]::new(60, 372),
      [System.Drawing.PointF]::new(118, 210),
      [System.Drawing.PointF]::new(158, 242),
      [System.Drawing.PointF]::new(202, 210),
      [System.Drawing.PointF]::new(260, 372)
    ))

  $armorBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(70, 180),
    [System.Drawing.Point]::new(250, 372),
    [System.Drawing.Color]::FromArgb(255, 155, 170, 187),
    [System.Drawing.Color]::FromArgb(255, 66, 76, 94)
  )
  $g.FillPolygon($armorBrush, @(
      [System.Drawing.PointF]::new(88, 360),
      [System.Drawing.PointF]::new(108, 216),
      [System.Drawing.PointF]::new(160, 188),
      [System.Drawing.PointF]::new(212, 216),
      [System.Drawing.PointF]::new(232, 360)
    ))

  $trimPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 214, 224, 239), 5)
  $g.DrawLine($trimPen, 160, 194, 160, 354)
  $g.DrawArc($trimPen, 118, 202, 84, 44, 195, 150)

  $neckBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 228, 188, 160))
  $g.FillRectangle($neckBrush, 146, 152, 28, 26)

  $faceBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 231, 191, 164))
  $g.FillEllipse($faceBrush, 118, 72, 86, 104)

  $hairPath = New-Object System.Drawing.Drawing2D.GraphicsPath
  $hairPath.AddClosedCurve(@(
      [System.Drawing.PointF]::new(116, 110),
      [System.Drawing.PointF]::new(124, 78),
      [System.Drawing.PointF]::new(160, 60),
      [System.Drawing.PointF]::new(198, 80),
      [System.Drawing.PointF]::new(204, 116),
      [System.Drawing.PointF]::new(188, 144),
      [System.Drawing.PointF]::new(176, 112),
      [System.Drawing.PointF]::new(140, 118),
      [System.Drawing.PointF]::new(128, 144)
    ))
  $hairBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(118, 70),
    [System.Drawing.Point]::new(198, 148),
    [System.Drawing.Color]::FromArgb(255, 88, 54, 28),
    [System.Drawing.Color]::FromArgb(255, 34, 23, 16)
  )
  $g.FillPath($hairBrush, $hairPath)

  $hoodPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 93, 48, 124), 9)
  $g.DrawArc($hoodPen, 103, 58, 116, 132, 202, 136)

  $eyePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 38, 29, 28), 2.4)
  $g.DrawArc($eyePen, 136, 114, 16, 8, 200, 140)
  $g.DrawArc($eyePen, 168, 114, 16, 8, 200, 140)
  $g.FillEllipse([System.Drawing.Brushes]::Black, 142, 118, 4, 4)
  $g.FillEllipse([System.Drawing.Brushes]::Black, 174, 118, 4, 4)

  $browPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 81, 50, 31), 3)
  $g.DrawLine($browPen, 134, 108, 150, 104)
  $g.DrawLine($browPen, 170, 104, 186, 108)

  $nosePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 133, 86, 60), 1.5)
  $g.DrawCurve($nosePen, @(
      [System.Drawing.PointF]::new(161, 120),
      [System.Drawing.PointF]::new(156, 134),
      [System.Drawing.PointF]::new(160, 146),
      [System.Drawing.PointF]::new(164, 150)
    ))

  $mouthPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 136, 74, 64), 2)
  $g.DrawArc($mouthPen, 146, 152, 26, 10, 15, 150)

  $beardPath = New-Object System.Drawing.Drawing2D.GraphicsPath
  $beardPath.AddClosedCurve(@(
      [System.Drawing.PointF]::new(128, 146),
      [System.Drawing.PointF]::new(136, 176),
      [System.Drawing.PointF]::new(160, 190),
      [System.Drawing.PointF]::new(184, 176),
      [System.Drawing.PointF]::new(192, 146),
      [System.Drawing.PointF]::new(160, 166)
    ))
  $beard = New-Object System.Drawing.Drawing2D.PathGradientBrush $beardPath
  $beard.CenterColor = [System.Drawing.Color]::FromArgb(220, 107, 69, 39)
  $beard.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 56, 33, 21))
  $g.FillPath($beard, $beardPath)

  $shoulderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 197, 209, 226), 4)
  $g.DrawArc($shoulderPen, 82, 214, 72, 80, 206, 110)
  $g.DrawArc($shoulderPen, 166, 214, 72, 80, 224, 110)
  $g.FillEllipse([System.Drawing.Brushes]::White, 148, 216, 24, 24)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 136, 152, 173))), 151, 219, 18, 18)

  $swordPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 218, 234, 246), 7)
  $g.DrawLine($swordPen, 254, 126, 218, 310)
  $shinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 255, 255, 255), 2)
  $g.DrawLine($shinePen, 250, 124, 214, 306)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 176, 128, 74))), 210, 292, 22, 10)

  $framePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 208, 178, 255), 4)
  $g.DrawRectangle($framePen, 10, 10, 300, 380)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $framePen.Dispose()
  $shinePen.Dispose()
  $swordPen.Dispose()
  $shoulderPen.Dispose()
  $beard.Dispose()
  $beardPath.Dispose()
  $mouthPen.Dispose()
  $nosePen.Dispose()
  $browPen.Dispose()
  $eyePen.Dispose()
  $hoodPen.Dispose()
  $hairBrush.Dispose()
  $hairPath.Dispose()
  $faceBrush.Dispose()
  $neckBrush.Dispose()
  $trimPen.Dispose()
  $armorBrush.Dispose()
  $capeBrush.Dispose()
  $glowBrush.Dispose()
  $glow.Dispose()
  $bg.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-SpellIcons {
  $path = Join-Path $outDir "spell-icons.png"
  $bmp = New-Object System.Drawing.Bitmap 256, 64
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  for ($i = 0; $i -lt 4; $i++) {
    $x = $i * 64
    $circle = New-Object System.Drawing.Rectangle ($x + 8), 8, 48, 48
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
      $circle,
      [System.Drawing.Color]::FromArgb(255, 40, 28, 68),
      [System.Drawing.Color]::FromArgb(255, 15, 17, 28),
      90
    )
    $g.FillEllipse($brush, $circle)
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 214, 184, 255), 2.2)), $circle)
    $brush.Dispose()
  }

  $sparkBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 221, 112))
  $sparkPts = @(
    [System.Drawing.PointF]::new(30, 14),
    [System.Drawing.PointF]::new(39, 28),
    [System.Drawing.PointF]::new(34, 28),
    [System.Drawing.PointF]::new(42, 46),
    [System.Drawing.PointF]::new(22, 32),
    [System.Drawing.PointF]::new(28, 32)
  )
  $g.FillPolygon($sparkBrush, $sparkPts)

  $novaPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 205, 248, 255), 3)
  $centerNova = [System.Drawing.PointF]::new(96, 32)
  for ($i = 0; $i -lt 8; $i++) {
    $a = [Math]::PI * 2 * $i / 8
    $x1 = $centerNova.X + [Math]::Cos($a) * 8
    $y1 = $centerNova.Y + [Math]::Sin($a) * 8
    $x2 = $centerNova.X + [Math]::Cos($a) * 16
    $y2 = $centerNova.Y + [Math]::Sin($a) * 16
    $g.DrawLine($novaPen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
  }
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 231, 251, 255))), 90, 26, 12, 12)

  $blinkBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 205, 112))
  $blinkPts = @(
    [System.Drawing.PointF]::new(132, 32),
    [System.Drawing.PointF]::new(149, 20),
    [System.Drawing.PointF]::new(151, 26),
    [System.Drawing.PointF]::new(166, 26),
    [System.Drawing.PointF]::new(166, 38),
    [System.Drawing.PointF]::new(151, 38),
    [System.Drawing.PointF]::new(149, 44)
  )
  $g.FillPolygon($blinkBrush, $blinkPts)
  $blinkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 242, 196), 2.4)
  $g.DrawLine($blinkPen, 124, 22, 137, 27)
  $g.DrawLine($blinkPen, 122, 32, 136, 32)
  $g.DrawLine($blinkPen, 124, 42, 137, 37)

  $orbRect = New-Object System.Drawing.Rectangle 201, 17, 22, 22
  $orb = New-Object System.Drawing.Drawing2D.GraphicsPath
  $orb.AddEllipse($orbRect)
  $orbBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $orb
  $orbBrush.CenterColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
  $orbBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 175, 116, 246))
  $g.FillPath($orbBrush, $orb)
  $orbPenA = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 246, 229, 255), 2)
  $orbPenB = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 126, 71, 220), 2)
  $g.DrawArc($orbPenA, 196, 12, 32, 32, 28, 200)
  $g.DrawArc($orbPenB, 192, 10, 40, 38, 218, 116)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $orbBrush.Dispose()
  $orb.Dispose()
  $orbPenA.Dispose()
  $orbPenB.Dispose()
  $blinkPen.Dispose()
  $blinkBrush.Dispose()
  $novaPen.Dispose()
  $sparkBrush.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-MapParchment {
  $path = Join-Path $outDir "map-parchment.png"
  $bmp = New-Object System.Drawing.Bitmap 512, 512
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::FromArgb(255, 238, 223, 194))

  $baseRect = New-Object System.Drawing.Rectangle 0,0,512,512
  $base = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $baseRect,
    [System.Drawing.Color]::FromArgb(255, 244, 233, 207),
    [System.Drawing.Color]::FromArgb(255, 201, 174, 136),
    90
  )
  $g.FillRectangle($base, $baseRect)

  $rand = [System.Random]::new(44)
  for ($i = 0; $i -lt 240; $i++) {
    $alpha = $rand.Next(10, 42)
    $warm = [System.Drawing.Color]::FromArgb($alpha, 120 + $rand.Next(0, 60), 88 + $rand.Next(0, 55), 40 + $rand.Next(0, 35))
    $brush = New-Object System.Drawing.SolidBrush $warm
    $w = $rand.Next(8, 42)
    $h = $rand.Next(8, 30)
    $x = $rand.Next(-10, 512)
    $y = $rand.Next(-10, 512)
    $g.FillEllipse($brush, $x, $y, $w, $h)
    $brush.Dispose()
  }

  $creasePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(42, 105, 79, 49), 3)
  $g.DrawArc($creasePen, 36, 94, 436, 226, 6, 168)
  $g.DrawArc($creasePen, 72, 260, 382, 168, 190, 146)
  $g.DrawLine($creasePen, 110, 70, 108, 442)
  $g.DrawLine($creasePen, 386, 88, 400, 458)

  for ($i = 0; $i -lt 6; $i++) {
    $size = 42 + $i * 18
    $alpha = 18 + $i * 4
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($alpha, 57, 35, 19), 12)
    $g.DrawRectangle($pen, $size / 2, $size / 2, 512 - $size, 512 - $size)
    $pen.Dispose()
  }

  $speckPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(28, 255, 255, 255), 1)
  for ($i = 0; $i -lt 160; $i++) {
    $x1 = $rand.Next(0, 512)
    $y1 = $rand.Next(0, 512)
    $g.DrawLine($speckPen, $x1, $y1, $x1 + $rand.Next(-5, 5), $y1 + $rand.Next(-5, 5))
  }

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $speckPen.Dispose()
  $creasePen.Dispose()
  $base.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-TreeSprite {
  $path = Join-Path $outDir "tree-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 128, 160
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(64, 16, 24, 13))
  $g.FillEllipse($shadow, 22, 132, 84, 18)

  $trunkBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
    [System.Drawing.Rectangle]::new(54, 74, 20, 60),
    [System.Drawing.Color]::FromArgb(255, 91, 57, 32),
    [System.Drawing.Color]::FromArgb(255, 58, 35, 20),
    90
  )
  $g.FillRectangle($trunkBrush, 55, 76, 18, 56)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 72, 43, 24))), 49, 110, 10, 28)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 72, 43, 24))), 71, 106, 10, 30)

  $canopyDark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 42, 98, 46))
  $canopyMid = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 57, 132, 58))
  $canopyLight = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 97, 174, 85))

  $g.FillEllipse($canopyDark, 22, 52, 42, 44)
  $g.FillEllipse($canopyDark, 62, 48, 44, 48)
  $g.FillEllipse($canopyDark, 38, 26, 50, 52)
  $g.FillEllipse($canopyMid, 18, 70, 52, 38)
  $g.FillEllipse($canopyMid, 58, 66, 54, 40)
  $g.FillEllipse($canopyMid, 28, 42, 68, 44)
  $g.FillEllipse($canopyLight, 34, 34, 30, 22)
  $g.FillEllipse($canopyLight, 62, 34, 28, 20)
  $g.FillEllipse($canopyLight, 48, 56, 22, 16)

  $edgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(190, 20, 56, 24), 2.2)
  $g.DrawEllipse($edgePen, 22, 52, 42, 44)
  $g.DrawEllipse($edgePen, 62, 48, 44, 48)
  $g.DrawEllipse($edgePen, 38, 26, 50, 52)
  $g.DrawEllipse($edgePen, 18, 70, 52, 38)
  $g.DrawEllipse($edgePen, 58, 66, 54, 40)
  $g.DrawEllipse($edgePen, 28, 42, 68, 44)

  $shinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(92, 245, 255, 238), 2)
  $g.DrawArc($shinePen, 28, 38, 30, 18, 220, 120)
  $g.DrawArc($shinePen, 60, 44, 28, 16, 220, 120)
  $g.DrawArc($shinePen, 42, 60, 26, 14, 220, 120)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $shinePen.Dispose()
  $edgePen.Dispose()
  $canopyLight.Dispose()
  $canopyMid.Dispose()
  $canopyDark.Dispose()
  $trunkBrush.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-MountainTexture {
  $path = Join-Path $outDir "mountain-texture.png"
  $bmp = New-Object System.Drawing.Bitmap 128, 128
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::FromArgb(255, 88, 96, 106))

  $baseRect = [System.Drawing.Rectangle]::new(0, 0, 128, 128)
  $base = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $baseRect,
    [System.Drawing.Color]::FromArgb(255, 126, 135, 146),
    [System.Drawing.Color]::FromArgb(255, 70, 76, 84),
    90
  )
  $g.FillRectangle($base, $baseRect)

  $rand = [System.Random]::new(71)
  for ($i = 0; $i -lt 140; $i++) {
    $alpha = $rand.Next(18, 64)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, 58 + $rand.Next(0, 42), 64 + $rand.Next(0, 42), 74 + $rand.Next(0, 42)))
    $x = $rand.Next(-8, 128)
    $y = $rand.Next(-8, 128)
    $w = $rand.Next(8, 28)
    $h = $rand.Next(4, 18)
    $g.FillEllipse($brush, $x, $y, $w, $h)
    $brush.Dispose()
  }

  $ridgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(82, 232, 238, 245), 3)
  for ($i = 0; $i -lt 8; $i++) {
    $x = 8 + $i * 14
    $g.DrawLine($ridgePen, $x, 0, $x - 12, 128)
  }
  $shadowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(56, 18, 22, 28), 4)
  for ($i = 0; $i -lt 7; $i++) {
    $x = 20 + $i * 16
    $g.DrawLine($shadowPen, $x, 0, $x + 10, 128)
  }
  $screePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(44, 210, 216, 224), 1.4)
  for ($i = 0; $i -lt 18; $i++) {
    $x = $rand.Next(6, 122)
    $y = $rand.Next(14, 118)
    $g.DrawLine($screePen, $x, $y, $x - $rand.Next(3, 8), $y + $rand.Next(8, 18))
  }

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $screePen.Dispose()
  $shadowPen.Dispose()
  $ridgePen.Dispose()
  $base.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-TreeAltSprite {
  $path = Join-Path $outDir "tree-sprite-alt.png"
  $bmp = New-Object System.Drawing.Bitmap 128, 128
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(42, 0, 0, 0))
  $g.FillEllipse($shadow, 28, 104, 72, 18)

  $trunkBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 76, 54, 34))
  $g.FillRectangle($trunkBrush, 58, 62, 12, 42)

  $canopyA = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 38, 78, 42))
  $canopyB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 58, 114, 64))
  $canopyC = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 94, 152, 82))
  $g.FillEllipse($canopyA, 28, 34, 72, 52)
  $g.FillEllipse($canopyB, 18, 48, 46, 42)
  $g.FillEllipse($canopyB, 62, 46, 48, 44)
  $g.FillEllipse($canopyC, 42, 18, 46, 38)
  $g.FillEllipse($canopyC, 28, 64, 26, 20)
  $g.FillEllipse($canopyC, 74, 64, 26, 20)

  $edgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 26, 56, 28), 2.4)
  $g.DrawEllipse($edgePen, 28, 34, 72, 52)
  $g.DrawEllipse($edgePen, 18, 48, 46, 42)
  $g.DrawEllipse($edgePen, 62, 46, 48, 44)
  $g.DrawEllipse($edgePen, 42, 18, 46, 38)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $edgePen.Dispose()
  $canopyA.Dispose()
  $canopyB.Dispose()
  $canopyC.Dispose()
  $trunkBrush.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-RockSprite {
  $path = Join-Path $outDir "rock-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 96, 64
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(38, 0, 0, 0))
  $g.FillEllipse($shadow, 18, 46, 56, 12)

  $basePath = New-Object System.Drawing.Drawing2D.GraphicsPath
  $basePath.AddPolygon(@(
    [System.Drawing.PointF]::new(14, 46),
    [System.Drawing.PointF]::new(22, 28),
    [System.Drawing.PointF]::new(36, 16),
    [System.Drawing.PointF]::new(56, 14),
    [System.Drawing.PointF]::new(72, 24),
    [System.Drawing.PointF]::new(80, 44),
    [System.Drawing.PointF]::new(62, 54),
    [System.Drawing.PointF]::new(30, 54)
  ))
  $baseBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(18, 18),
    [System.Drawing.Point]::new(74, 52),
    [System.Drawing.Color]::FromArgb(255, 132, 142, 152),
    [System.Drawing.Color]::FromArgb(255, 86, 94, 104)
  )
  $g.FillPath($baseBrush, $basePath)

  $facetA = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 165, 174, 183))
  $g.FillPolygon($facetA, @(
    [System.Drawing.PointF]::new(24, 34),
    [System.Drawing.PointF]::new(38, 20),
    [System.Drawing.PointF]::new(52, 18),
    [System.Drawing.PointF]::new(46, 36),
    [System.Drawing.PointF]::new(28, 40)
  ))
  $facetB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 102, 110, 120))
  $g.FillPolygon($facetB, @(
    [System.Drawing.PointF]::new(48, 22),
    [System.Drawing.PointF]::new(66, 24),
    [System.Drawing.PointF]::new(74, 42),
    [System.Drawing.PointF]::new(56, 48),
    [System.Drawing.PointF]::new(46, 38)
  ))

  $edgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 52, 58, 66), 2)
  $g.DrawPath($edgePen, $basePath)
  $crackPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 40, 46, 52), 1.6)
  $g.DrawLine($crackPen, 40, 20, 36, 42)
  $g.DrawLine($crackPen, 54, 20, 64, 42)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $crackPen.Dispose()
  $edgePen.Dispose()
  $facetA.Dispose()
  $facetB.Dispose()
  $baseBrush.Dispose()
  $basePath.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-MountainEdgeSprite {
  $path = Join-Path $outDir "mountain-edge-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 128, 32
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 18, 22, 26))
  $midBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 58, 64, 72))
  $lightBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 220, 228, 236))

  $ridge = @(
    [System.Drawing.PointF]::new(0, 18),
    [System.Drawing.PointF]::new(12, 16),
    [System.Drawing.PointF]::new(24, 8),
    [System.Drawing.PointF]::new(34, 15),
    [System.Drawing.PointF]::new(48, 9),
    [System.Drawing.PointF]::new(61, 18),
    [System.Drawing.PointF]::new(72, 12),
    [System.Drawing.PointF]::new(84, 8),
    [System.Drawing.PointF]::new(95, 16),
    [System.Drawing.PointF]::new(108, 10),
    [System.Drawing.PointF]::new(118, 14),
    [System.Drawing.PointF]::new(128, 12),
    [System.Drawing.PointF]::new(128, 25),
    [System.Drawing.PointF]::new(0, 25)
  )
  $g.FillPolygon($shadowBrush, $ridge)

  $mid = @(
    [System.Drawing.PointF]::new(0, 20),
    [System.Drawing.PointF]::new(12, 18),
    [System.Drawing.PointF]::new(24, 11),
    [System.Drawing.PointF]::new(34, 17),
    [System.Drawing.PointF]::new(48, 12),
    [System.Drawing.PointF]::new(61, 20),
    [System.Drawing.PointF]::new(72, 14),
    [System.Drawing.PointF]::new(84, 11),
    [System.Drawing.PointF]::new(95, 18),
    [System.Drawing.PointF]::new(108, 13),
    [System.Drawing.PointF]::new(118, 16),
    [System.Drawing.PointF]::new(128, 15),
    [System.Drawing.PointF]::new(128, 22),
    [System.Drawing.PointF]::new(0, 22)
  )
  $g.FillPolygon($midBrush, $mid)

  $lightPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(165, 238, 244, 250), 2)
  $g.DrawCurve($lightPen, @(
    [System.Drawing.PointF]::new(2, 21),
    [System.Drawing.PointF]::new(14, 19),
    [System.Drawing.PointF]::new(24, 13),
    [System.Drawing.PointF]::new(34, 18),
    [System.Drawing.PointF]::new(48, 14),
    [System.Drawing.PointF]::new(61, 20),
    [System.Drawing.PointF]::new(72, 15),
    [System.Drawing.PointF]::new(84, 13),
    [System.Drawing.PointF]::new(95, 18),
    [System.Drawing.PointF]::new(108, 14),
    [System.Drawing.PointF]::new(118, 17),
    [System.Drawing.PointF]::new(126, 16)
  ))

  $facetPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 248, 250, 252), 1.2)
  foreach ($x in 10, 28, 50, 76, 98, 116) {
    $g.DrawLine($facetPen, $x, 17, $x - 4, 23)
  }

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $facetPen.Dispose()
  $lightPen.Dispose()
  $lightBrush.Dispose()
  $midBrush.Dispose()
  $shadowBrush.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-MountainPeakSprite {
  $path = Join-Path $outDir "mountain-peak-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 160, 128
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(228, 29, 34, 40))
  $midBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 82, 92, 104))
  $lightBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 146, 156, 168))
  $snowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(214, 245, 249, 252))
  $ridgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 244, 248, 252), 2)
  $facePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(72, 20, 24, 30), 2)

  $shadow = @(
    [System.Drawing.PointF]::new(10, 114),
    [System.Drawing.PointF]::new(30, 86),
    [System.Drawing.PointF]::new(48, 70),
    [System.Drawing.PointF]::new(62, 84),
    [System.Drawing.PointF]::new(84, 18),
    [System.Drawing.PointF]::new(108, 70),
    [System.Drawing.PointF]::new(126, 56),
    [System.Drawing.PointF]::new(150, 114)
  )
  $g.FillPolygon($shadowBrush, $shadow)

  $mid = @(
    [System.Drawing.PointF]::new(16, 114),
    [System.Drawing.PointF]::new(40, 84),
    [System.Drawing.PointF]::new(56, 74),
    [System.Drawing.PointF]::new(70, 86),
    [System.Drawing.PointF]::new(84, 30),
    [System.Drawing.PointF]::new(98, 62),
    [System.Drawing.PointF]::new(118, 58),
    [System.Drawing.PointF]::new(142, 114)
  )
  $g.FillPolygon($midBrush, $mid)

  $light = @(
    [System.Drawing.PointF]::new(22, 114),
    [System.Drawing.PointF]::new(50, 92),
    [System.Drawing.PointF]::new(68, 88),
    [System.Drawing.PointF]::new(84, 40),
    [System.Drawing.PointF]::new(94, 62),
    [System.Drawing.PointF]::new(110, 72),
    [System.Drawing.PointF]::new(128, 114)
  )
  $g.FillPolygon($lightBrush, $light)

  $snow = @(
    [System.Drawing.PointF]::new(76, 52),
    [System.Drawing.PointF]::new(84, 36),
    [System.Drawing.PointF]::new(91, 54),
    [System.Drawing.PointF]::new(86, 67),
    [System.Drawing.PointF]::new(80, 62)
  )
  $g.FillPolygon($snowBrush, $snow)

  $g.DrawLine($ridgePen, 84, 36, 70, 92)
  $g.DrawLine($ridgePen, 84, 36, 102, 72)
  $g.DrawLine($ridgePen, 84, 36, 58, 78)
  $g.DrawLine($facePen, 56, 74, 44, 112)
  $g.DrawLine($facePen, 74, 84, 68, 112)
  $g.DrawLine($facePen, 98, 62, 106, 112)
  $g.DrawLine($facePen, 116, 58, 128, 112)

  $mistBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Point]::new(0, 90),
    [System.Drawing.Point]::new(0, 127),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(54, 225, 233, 240)
  )
  $g.FillRectangle($mistBrush, 0, 86, 160, 42)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $mistBrush.Dispose()
  $facePen.Dispose()
  $ridgePen.Dispose()
  $snowBrush.Dispose()
  $lightBrush.Dispose()
  $midBrush.Dispose()
  $shadowBrush.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-DockBoatSprite {
  $path = Join-Path $outDir "dock-boat-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 96, 48
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 10, 16, 24))
  $g.FillEllipse($shadow, 18, 31, 50, 10)

  $hull = New-Object System.Drawing.Drawing2D.GraphicsPath
  $hull.AddPolygon(@(
    [System.Drawing.PointF]::new(18, 25),
    [System.Drawing.PointF]::new(30, 33),
    [System.Drawing.PointF]::new(62, 33),
    [System.Drawing.PointF]::new(74, 25),
    [System.Drawing.PointF]::new(60, 18),
    [System.Drawing.PointF]::new(28, 18)
  ))
  $hullBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(18, 18),
    [System.Drawing.Point]::new(74, 33),
    [System.Drawing.Color]::FromArgb(255, 120, 84, 48),
    [System.Drawing.Color]::FromArgb(255, 82, 55, 33)
  )
  $g.FillPath($hullBrush, $hull)
  $hullPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 38, 26, 19), 2)
  $g.DrawPath($hullPen, $hull)

  $mastPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 200, 180, 150), 2.4)
  $g.DrawLine($mastPen, 47, 8, 47, 24)
  $ropePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 228, 236, 244), 1.2)
  $g.DrawLine($ropePen, 47, 9, 61, 17)

  $sail = New-Object System.Drawing.Drawing2D.GraphicsPath
  $sail.AddPolygon(@(
    [System.Drawing.PointF]::new(47, 10),
    [System.Drawing.PointF]::new(47, 24),
    [System.Drawing.PointF]::new(63, 18)
  ))
  $sailBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(47, 10),
    [System.Drawing.Point]::new(63, 24),
    [System.Drawing.Color]::FromArgb(255, 234, 242, 248),
    [System.Drawing.Color]::FromArgb(255, 194, 208, 220)
  )
  $g.FillPath($sailBrush, $sail)

  $shinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 255, 250, 236), 1.4)
  $g.DrawLine($shinePen, 27, 19, 59, 19)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $shinePen.Dispose()
  $sailBrush.Dispose()
  $sail.Dispose()
  $ropePen.Dispose()
  $mastPen.Dispose()
  $hullPen.Dispose()
  $hullBrush.Dispose()
  $hull.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-ShrineSprite {
  $path = Join-Path $outDir "shrine-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 72, 88
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $aura = New-Object System.Drawing.Drawing2D.GraphicsPath
  $aura.AddEllipse(10, 16, 52, 52)
  $auraBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $aura
  $auraBrush.CenterColor = [System.Drawing.Color]::FromArgb(120, 197, 146, 255)
  $auraBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 197, 146, 255))
  $g.FillPath($auraBrush, $aura)

  $baseBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(20, 58),
    [System.Drawing.Point]::new(52, 78),
    [System.Drawing.Color]::FromArgb(255, 100, 79, 142),
    [System.Drawing.Color]::FromArgb(255, 56, 43, 86)
  )
  $g.FillRectangle($baseBrush, 20, 58, 32, 10)
  $g.FillRectangle($baseBrush, 26, 50, 20, 10)

  $crystal = New-Object System.Drawing.Drawing2D.GraphicsPath
  $crystal.AddPolygon(@(
    [System.Drawing.PointF]::new(36, 18),
    [System.Drawing.PointF]::new(48, 46),
    [System.Drawing.PointF]::new(36, 58),
    [System.Drawing.PointF]::new(24, 46)
  ))
  $crystalBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(24, 18),
    [System.Drawing.Point]::new(48, 58),
    [System.Drawing.Color]::FromArgb(255, 228, 196, 255),
    [System.Drawing.Color]::FromArgb(255, 151, 98, 241)
  )
  $g.FillPath($crystalBrush, $crystal)
  $crystalPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 249, 238, 255), 2)
  $shinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 255), 1.4)
  $g.DrawPath($crystalPen, $crystal)
  $g.DrawLine($shinePen, 36, 20, 36, 57)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $shinePen.Dispose()
  $crystalPen.Dispose()
  $crystalBrush.Dispose()
  $crystal.Dispose()
  $baseBrush.Dispose()
  $auraBrush.Dispose()
  $aura.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-CacheSprite {
  $path = Join-Path $outDir "cache-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 64, 52
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(64, 12, 16, 24))
  $g.FillEllipse($shadow, 12, 36, 40, 10)

  $box = New-Object System.Drawing.Rectangle 14, 18, 36, 20
  $boxBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $box,
    [System.Drawing.Color]::FromArgb(255, 213, 163, 83),
    [System.Drawing.Color]::FromArgb(255, 130, 92, 42),
    90
  )
  $boxPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 92, 56, 24), 2)
  $trimBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 246, 220, 146))
  $bandBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 244, 211, 120))
  $lockBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 241, 179))
  $g.FillRectangle($boxBrush, $box)
  $g.DrawRectangle($boxPen, $box)
  $g.FillRectangle($trimBrush, 14, 18, 36, 4)
  $g.FillRectangle($bandBrush, 30, 18, 4, 20)
  $g.FillEllipse($lockBrush, 28, 24, 8, 8)

  $sparkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 255, 240, 186), 1.6)
  $g.DrawLine($sparkPen, 22, 14, 26, 18)
  $g.DrawLine($sparkPen, 42, 12, 38, 18)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $sparkPen.Dispose()
  $lockBrush.Dispose()
  $bandBrush.Dispose()
  $trimBrush.Dispose()
  $boxPen.Dispose()
  $boxBrush.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-BushSprite {
  $path = Join-Path $outDir "bush-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 72, 48
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(56, 12, 18, 20))
  $g.FillEllipse($shadow, 10, 31, 52, 11)

  $leafA = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 56, 112, 58))
  $leafB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 74, 140, 72))
  $leafC = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 98, 168, 88))
  $g.FillEllipse($leafA, 10, 16, 20, 18)
  $g.FillEllipse($leafB, 22, 10, 24, 22)
  $g.FillEllipse($leafA, 36, 15, 20, 18)
  $g.FillEllipse($leafC, 16, 18, 18, 16)
  $g.FillEllipse($leafC, 34, 19, 18, 16)

  $berry = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 244, 212, 112))
  $g.FillEllipse($berry, 26, 22, 4, 4)
  $g.FillEllipse($berry, 41, 23, 4, 4)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $berry.Dispose()
  $leafC.Dispose()
  $leafB.Dispose()
  $leafA.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-LogSprite {
  $path = Join-Path $outDir "log-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 84, 40
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(52, 14, 14, 18))
  $g.FillEllipse($shadow, 12, 25, 60, 10)

  $bodyBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(12, 14),
    [System.Drawing.Point]::new(68, 28),
    [System.Drawing.Color]::FromArgb(255, 112, 78, 46),
    [System.Drawing.Color]::FromArgb(255, 76, 50, 30)
  )
  $g.FillRectangle($bodyBrush, 16, 14, 48, 12)
  $ringBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 158, 118, 74))
  $barkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 56, 36, 24), 1.6)
  $g.FillEllipse($ringBrush, 10, 12, 14, 14)
  $g.FillEllipse($ringBrush, 58, 14, 14, 14)
  $g.DrawEllipse($barkPen, 10, 12, 14, 14)
  $g.DrawEllipse($barkPen, 58, 14, 14, 14)
  $g.DrawLine($barkPen, 24, 18, 56, 18)
  $g.DrawLine($barkPen, 26, 22, 54, 22)

  $moss = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 96, 132, 70))
  $g.FillEllipse($moss, 28, 11, 14, 7)
  $g.FillEllipse($moss, 42, 21, 12, 6)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $moss.Dispose()
  $barkPen.Dispose()
  $ringBrush.Dispose()
  $bodyBrush.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-CampSprite {
  $path = Join-Path $outDir "camp-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 84, 64
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(58, 12, 16, 18))
  $g.FillEllipse($shadow, 14, 42, 56, 12)

  $tent = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tent.AddPolygon(@(
    [System.Drawing.PointF]::new(20, 40),
    [System.Drawing.PointF]::new(42, 16),
    [System.Drawing.PointF]::new(64, 40)
  ))
  $tentBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(20, 16),
    [System.Drawing.Point]::new(64, 40),
    [System.Drawing.Color]::FromArgb(255, 142, 102, 62),
    [System.Drawing.Color]::FromArgb(255, 84, 58, 36)
  )
  $g.FillPath($tentBrush, $tent)
  $tentPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 58, 38, 26), 2)
  $g.DrawPath($tentPen, $tent)
  $g.DrawLine($tentPen, 42, 16, 42, 40)

  $fireGlow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(96, 255, 190, 88))
  $g.FillEllipse($fireGlow, 34, 32, 16, 12)
  $fireA = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 208, 116))
  $fireB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 132, 64))
  $g.FillEllipse($fireB, 37, 34, 10, 8)
  $g.FillEllipse($fireA, 39, 32, 6, 7)

  $logBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 98, 68, 44))
  $g.FillRectangle($logBrush, 24, 38, 10, 3)
  $g.FillRectangle($logBrush, 50, 38, 10, 3)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $logBrush.Dispose()
  $fireB.Dispose()
  $fireA.Dispose()
  $fireGlow.Dispose()
  $tentPen.Dispose()
  $tentBrush.Dispose()
  $tent.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-WaystoneSprite {
  $path = Join-Path $outDir "waystone-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 64, 92
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $aura = New-Object System.Drawing.Drawing2D.GraphicsPath
  $aura.AddEllipse(8, 18, 48, 52)
  $auraBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $aura
  $auraBrush.CenterColor = [System.Drawing.Color]::FromArgb(110, 116, 228, 255)
  $auraBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 116, 228, 255))
  $g.FillPath($auraBrush, $aura)

  $stone = New-Object System.Drawing.Drawing2D.GraphicsPath
  $stone.AddPolygon(@(
    [System.Drawing.PointF]::new(32, 16),
    [System.Drawing.PointF]::new(44, 54),
    [System.Drawing.PointF]::new(32, 72),
    [System.Drawing.PointF]::new(20, 54)
  ))
  $stoneBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(20, 16),
    [System.Drawing.Point]::new(44, 72),
    [System.Drawing.Color]::FromArgb(255, 98, 198, 224),
    [System.Drawing.Color]::FromArgb(255, 44, 128, 152)
  )
  $g.FillPath($stoneBrush, $stone)
  $stonePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 216, 248, 255), 2)
  $g.DrawPath($stonePen, $stone)
  $runePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 255, 255, 255), 1.4)
  $g.DrawLine($runePen, 32, 26, 32, 60)
  $g.DrawLine($runePen, 26, 42, 38, 42)

  $baseBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 74, 112, 136))
  $g.FillRectangle($baseBrush, 18, 72, 28, 8)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $baseBrush.Dispose()
  $runePen.Dispose()
  $stonePen.Dispose()
  $stoneBrush.Dispose()
  $stone.Dispose()
  $auraBrush.Dispose()
  $aura.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-HerbSprite {
  $path = Join-Path $outDir "herb-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 44, 44
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(44, 10, 16, 18))
  $g.FillEllipse($shadow, 10, 30, 22, 7)

  $leafA = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 86, 170, 88))
  $leafB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 62, 138, 72))
  $stemPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 84, 118, 62), 1.8)
  $flower = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 214, 188, 255))
  $core = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 246, 218, 124))

  $g.DrawLine($stemPen, 21, 28, 21, 16)
  $g.DrawLine($stemPen, 21, 25, 12, 20)
  $g.DrawLine($stemPen, 21, 23, 30, 18)
  $g.FillEllipse($leafB, 7, 16, 11, 7)
  $g.FillEllipse($leafA, 24, 14, 12, 8)
  $g.FillEllipse($leafA, 15, 10, 8, 12)
  $g.FillEllipse($flower, 16, 8, 5, 5)
  $g.FillEllipse($flower, 21, 6, 5, 5)
  $g.FillEllipse($flower, 25, 10, 5, 5)
  $g.FillEllipse($flower, 19, 12, 5, 5)
  $g.FillEllipse($core, 20, 9, 4, 4)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $core.Dispose()
  $flower.Dispose()
  $stemPen.Dispose()
  $leafB.Dispose()
  $leafA.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-AshTreeSprite {
  $path = Join-Path $outDir "ash-tree-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 48, 48
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 10, 12, 12))
  $trunk = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 92, 78, 64), 2.2)
  $branch = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 118, 98, 76), 1.6)
  $ember = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 184, 124, 82))

  $g.FillEllipse($shadow, 12, 34, 24, 7)
  $g.DrawLine($trunk, 24, 34, 24, 15)
  $g.DrawLine($branch, 24, 18, 16, 10)
  $g.DrawLine($branch, 24, 21, 32, 12)
  $g.DrawLine($branch, 24, 24, 15, 25)
  $g.DrawLine($branch, 24, 26, 33, 24)
  $g.FillEllipse($ember, 14, 8, 4, 4)
  $g.FillEllipse($ember, 31, 11, 3, 3)
  $g.FillEllipse($ember, 34, 22, 3, 3)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $ember.Dispose()
  $branch.Dispose()
  $trunk.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-AshTreeAltSprite {
  $path = Join-Path $outDir "ash-tree-alt-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 48, 48
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(38, 10, 12, 12))
  $trunk = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 86, 72, 60), 2.0)
  $branch = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 126, 108, 88), 1.4)
  $ash = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110, 166, 138, 114))

  $g.FillEllipse($shadow, 11, 34, 24, 6)
  $g.DrawLine($trunk, 23, 34, 21, 15)
  $g.DrawLine($branch, 21, 18, 12, 15)
  $g.DrawLine($branch, 20, 22, 30, 15)
  $g.DrawLine($branch, 22, 24, 14, 28)
  $g.DrawLine($branch, 21, 27, 31, 26)
  $g.FillEllipse($ash, 10, 13, 4, 3)
  $g.FillEllipse($ash, 29, 14, 4, 3)
  $g.FillEllipse($ash, 14, 27, 3, 3)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $ash.Dispose()
  $branch.Dispose()
  $trunk.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-AshShrubSprite {
  $path = Join-Path $outDir "ash-shrub-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 40, 28
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(36, 12, 12, 12))
  $twigA = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 108, 88, 66), 1.5)
  $twigB = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 142, 116, 84), 1.2)

  $g.FillEllipse($shadow, 8, 18, 22, 6)
  $g.DrawLine($twigA, 18, 20, 12, 12)
  $g.DrawLine($twigA, 18, 20, 22, 10)
  $g.DrawLine($twigA, 18, 20, 27, 14)
  $g.DrawLine($twigB, 15, 17, 9, 16)
  $g.DrawLine($twigB, 20, 17, 26, 17)
  $g.DrawLine($twigB, 22, 16, 30, 11)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $twigB.Dispose()
  $twigA.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

function Save-AshDeadBrushSprite {
  $path = Join-Path $outDir "ash-dead-brush-sprite.png"
  $bmp = New-Object System.Drawing.Bitmap 40, 24
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(30, 10, 10, 10))
  $stemA = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 126, 112, 88), 1.4)
  $stemB = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 164, 142, 112), 1.1)
  $ash = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(100, 162, 146, 126))

  $g.FillEllipse($shadow, 8, 16, 24, 5)
  $g.DrawLine($stemA, 18, 18, 12, 7)
  $g.DrawLine($stemA, 18, 18, 17, 5)
  $g.DrawLine($stemA, 18, 18, 24, 7)
  $g.DrawLine($stemA, 18, 18, 27, 10)
  $g.DrawLine($stemB, 12, 17, 8, 12)
  $g.DrawLine($stemB, 24, 16, 31, 12)
  $g.FillEllipse($ash, 9, 10, 4, 3)
  $g.FillEllipse($ash, 17, 6, 4, 3)
  $g.FillEllipse($ash, 26, 10, 4, 3)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

  $ash.Dispose()
  $stemB.Dispose()
  $stemA.Dispose()
  $shadow.Dispose()
  $g.Dispose()
  $bmp.Dispose()
}

Save-HeroPortrait
Save-SpellIcons
Save-MapParchment
Save-TreeSprite
Save-TreeAltSprite
Save-MountainTexture
Save-RockSprite
Save-MountainEdgeSprite
Save-MountainPeakSprite
Save-DockBoatSprite
Save-ShrineSprite
Save-CacheSprite
Save-BushSprite
Save-LogSprite
Save-CampSprite
Save-WaystoneSprite
Save-HerbSprite
Save-AshTreeSprite
Save-AshTreeAltSprite
Save-AshShrubSprite
Save-AshDeadBrushSprite

Write-Output "Generated UI assets in $outDir"
