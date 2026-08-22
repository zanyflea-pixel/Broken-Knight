param(
    [string]$Version = "AUTO"
)

$ErrorActionPreference = "Stop"

$Root = "C:\Users\Jimmy\Desktop\Broken Knight"
Set-Location $Root

$ReviewRoot = Join-Path $Root "captures\horse-review\auto"
$ViewsDir = Join-Path $ReviewRoot "views"

$ReviewJpg = Join-Path $ReviewRoot "review_chat.jpg"
$ReviewBase64 = Join-Path $ReviewRoot "review_chat.b64.txt"
$InventoryJson = Join-Path $ReviewRoot "model_inventory.json"

$ChatDir = Join-Path $ReviewRoot "chat"

$SilhouetteJpg = Join-Path $ChatDir "01_silhouette.jpg"
$SilhouetteBase64 = Join-Path $ChatDir "01_silhouette.b64.txt"

$HeadJpg = Join-Path $ChatDir "02_head.jpg"
$HeadBase64 = Join-Path $ChatDir "02_head.b64.txt"

$LegsJpg = Join-Path $ChatDir "03_legs.jpg"
$LegsBase64 = Join-Path $ChatDir "03_legs.b64.txt"

$TransportManifest = Join-Path $ChatDir "review_transport.json"

$InventoryPy = Join-Path $Root "captures\horse-model-inventory.py"
$BlendFile = Join-Path $Root "blender\world\animals\riverwatch_horse.blend"

$Temp = Join-Path $Root "tmp\horse_handoff_work"
$StdOutFile = Join-Path $Temp "inventory.stdout.txt"
$StdErrFile = Join-Path $Temp "inventory.stderr.txt"


function Find-Blender {

    $Command = Get-Command `
        blender.exe `
        -ErrorAction SilentlyContinue

    if ($Command) {
        return $Command.Source
    }

    $SearchRoot = "C:\Program Files\Blender Foundation"

    if (Test-Path $SearchRoot) {

        $Found = Get-ChildItem `
            $SearchRoot `
            -Filter blender.exe `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($Found) {
            return $Found.FullName
        }
    }

    return $null
}


function Write-Utf8NoBom {

    param(
        [string]$Path,
        [string]$Text
    )

    $Encoding = New-Object `
        System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        $Encoding
    )
}


function Get-JpegEncoder {

    foreach (
        $Encoder in
        [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
    ) {

        if (
            $Encoder.MimeType -eq
            "image/jpeg"
        ) {
            return $Encoder
        }
    }

    return $null
}


function Save-ContactSheet {

    param(
        [string[]]$ImageNames,
        [string]$OutputPath,
        [int]$CellWidth,
        [int]$CellHeight,
        [int]$Columns,
        [long]$Quality
    )

    $Rows = [int][Math]::Ceiling(
        $ImageNames.Count /
        [double]$Columns
    )

    $SheetWidth = (
        $Columns *
        $CellWidth
    )

    $SheetHeight = (
        $Rows *
        $CellHeight
    )

    $Canvas = New-Object `
        -TypeName System.Drawing.Bitmap `
        -ArgumentList $SheetWidth,$SheetHeight

    $Graphics = [System.Drawing.Graphics]::FromImage(
        $Canvas
    )

    try {

        $Background = [System.Drawing.Color]::FromArgb(
            15,
            18,
            23
        )

        $Graphics.Clear(
            $Background
        )

        $Graphics.InterpolationMode = (
            [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        )

        $Graphics.PixelOffsetMode = (
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        )

        $Graphics.SmoothingMode = (
            [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        )

        for (
            $Index = 0;
            $Index -lt $ImageNames.Count;
            $Index++
        ) {

            $Row = [int][Math]::Floor(
                $Index /
                [double]$Columns
            )

            $Column = (
                $Index %
                $Columns
            )

            $CellX = (
                $Column *
                $CellWidth
            )

            $CellY = (
                $Row *
                $CellHeight
            )

            $ImagePath = Join-Path `
                $ViewsDir `
                $ImageNames[$Index]

            if (-not (Test-Path $ImagePath)) {
                throw "Missing review image: $($ImageNames[$Index])"
            }

            $Image = [System.Drawing.Image]::FromFile(
                $ImagePath
            )

            try {

                $ScaleX = (
                    $CellWidth /
                    [double]$Image.Width
                )

                $ScaleY = (
                    $CellHeight /
                    [double]$Image.Height
                )

                $Scale = [Math]::Min(
                    $ScaleX,
                    $ScaleY
                )

                $DrawWidth = [int][Math]::Round(
                    $Image.Width *
                    $Scale
                )

                $DrawHeight = [int][Math]::Round(
                    $Image.Height *
                    $Scale
                )

                $DrawX = [int](
                    $CellX +
                    (($CellWidth - $DrawWidth) / 2)
                )

                $DrawY = [int](
                    $CellY +
                    (($CellHeight - $DrawHeight) / 2)
                )

                $Graphics.DrawImage(
                    $Image,
                    $DrawX,
                    $DrawY,
                    $DrawWidth,
                    $DrawHeight
                )
            }
            finally {

                $Image.Dispose()
            }
        }

        $JpegEncoder = Get-JpegEncoder

        if (-not $JpegEncoder) {
            throw "JPEG encoder was not found."
        }

        $EncoderParameters = New-Object `
            -TypeName System.Drawing.Imaging.EncoderParameters `
            -ArgumentList 1

        $QualityEncoder = (
            [System.Drawing.Imaging.Encoder]::Quality
        )

        $QualityParameter = New-Object `
            -TypeName System.Drawing.Imaging.EncoderParameter `
            -ArgumentList $QualityEncoder,$Quality

        $EncoderParameters.Param[0] = (
            $QualityParameter
        )

        try {

            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
            }

            $Canvas.Save(
                $OutputPath,
                $JpegEncoder,
                $EncoderParameters
            )
        }
        finally {

            $QualityParameter.Dispose()
            $EncoderParameters.Dispose()
        }
    }
    finally {

        $Graphics.Dispose()
        $Canvas.Dispose()
    }
}


function Save-ConnectorSheet {

    param(
        [string[]]$ImageNames,
        [string]$OutputPath,
        [int]$CellWidth,
        [int]$CellHeight,
        [int]$Columns,
        [long]$MaxBytes
    )

    $Qualities = @(
        44L,
        38L,
        32L,
        26L
    )

    foreach ($Quality in $Qualities) {

        Save-ContactSheet `
            -ImageNames $ImageNames `
            -OutputPath $OutputPath `
            -CellWidth $CellWidth `
            -CellHeight $CellHeight `
            -Columns $Columns `
            -Quality $Quality

        $Size = (
            Get-Item $OutputPath
        ).Length

        if ($Size -le $MaxBytes) {

            Write-Host (
                "CONNECTOR_JPG=" +
                $OutputPath +
                " BYTES=" +
                $Size +
                " QUALITY=" +
                $Quality
            )

            return $Size
        }
    }

    $FinalSize = (
        Get-Item $OutputPath
    ).Length

    if ($FinalSize -gt $MaxBytes) {

        throw (
            "Connector review image is still too large: " +
            $OutputPath +
            " BYTES=" +
            $FinalSize +
            " LIMIT=" +
            $MaxBytes
        )
    }

    return $FinalSize
}


function Write-Base64Lines {

    param(
        [string]$SourcePath,
        [string]$OutputPath
    )

    [byte[]]$Bytes = (
        [System.IO.File]::ReadAllBytes(
            $SourcePath
        )
    )

    $Base64 = [Convert]::ToBase64String(
        $Bytes
    )

    $Builder = New-Object `
        System.Text.StringBuilder

    $Offset = 0

    while ($Offset -lt $Base64.Length) {

        $Remaining = (
            $Base64.Length -
            $Offset
        )

        $Length = 96

        if ($Remaining -lt $Length) {
            $Length = $Remaining
        }

        [void]$Builder.AppendLine(
            $Base64.Substring(
                $Offset,
                $Length
            )
        )

        $Offset += $Length
    }

    Write-Utf8NoBom `
        $OutputPath `
        $Builder.ToString()

    return (
        Get-Item $OutputPath
    ).Length
}


function New-TransportRecord {

    param(
        [string]$Role,
        [string]$JpgRelative,
        [string]$Base64Relative,
        [string]$JpgAbsolute,
        [string]$Base64Absolute,
        [string[]]$Views
    )

    $ImageHash = (
        Get-FileHash `
            $JpgAbsolute `
            -Algorithm SHA256
    ).Hash

    return [ordered]@{
        role = $Role
        image_path = $JpgRelative
        base64_path = $Base64Relative
        image_bytes = (Get-Item $JpgAbsolute).Length
        base64_bytes = (Get-Item $Base64Absolute).Length
        sha256 = $ImageHash
        views = $Views
    }
}


try {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " CHATGPT HORSE REVIEW HANDOFF $Version" -ForegroundColor Cyan
    Write-Host " CONNECTOR-SAFE TRANSPORT" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw "git.exe not found."
    }

    Add-Type -AssemblyName System.Drawing

    $ViewFiles = @(
        "01_side_left.png",
        "02_front_3q.png",
        "03_front.png",
        "04_side_right.png",
        "05_rear_3q.png",
        "06_head_detail.png",
        "07_front_detail.png",
        "08_rear_detail.png"
    )

    foreach ($Name in $ViewFiles) {

        $Path = Join-Path `
            $ViewsDir `
            $Name

        if (-not (Test-Path $Path)) {
            throw "Missing review image: $Name"
        }

        if ((Get-Item $Path).Length -lt 5000) {
            throw "Review image appears invalid: $Name"
        }
    }

    if (Test-Path $ChatDir) {
        Remove-Item `
            $ChatDir `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Force `
        $ChatDir |
        Out-Null

    # ========================================================
    # LEGACY CONTACT SHEET
    #
    # Retained so older tooling remains compatible.
    # Future ChatGPT review should use /chat/ files below.
    # ========================================================

    Save-ContactSheet `
        -ImageNames $ViewFiles `
        -OutputPath $ReviewJpg `
        -CellWidth 256 `
        -CellHeight 256 `
        -Columns 4 `
        -Quality 62L

    $ReviewSize = (
        Get-Item $ReviewJpg
    ).Length

    if ($ReviewSize -lt 10000) {
        throw "Legacy review_chat.jpg appears invalid."
    }

    $LegacyBase64Size = Write-Base64Lines `
        -SourcePath $ReviewJpg `
        -OutputPath $ReviewBase64

    Write-Host "LEGACY_REVIEW_JPG=$ReviewJpg"
    Write-Host "LEGACY_REVIEW_BYTES=$ReviewSize"
    Write-Host "LEGACY_BASE64_BYTES=$LegacyBase64Size"
    Write-Host ""

    # ========================================================
    # CONNECTOR SAFE IMAGE 1
    #
    # Five silhouette / whole-horse views.
    # Very small so GitHub fetch does not truncate it.
    # ========================================================

    $SilhouetteViews = @(
        "01_side_left.png",
        "02_front_3q.png",
        "03_front.png",
        "04_side_right.png",
        "05_rear_3q.png"
    )

    $SilhouetteSize = Save-ConnectorSheet `
        -ImageNames $SilhouetteViews `
        -OutputPath $SilhouetteJpg `
        -CellWidth 150 `
        -CellHeight 150 `
        -Columns 5 `
        -MaxBytes 16000L

    $SilhouetteBase64Size = Write-Base64Lines `
        -SourcePath $SilhouetteJpg `
        -OutputPath $SilhouetteBase64

    # ========================================================
    # CONNECTOR SAFE IMAGE 2
    #
    # Dedicated head detail.
    # ========================================================

    $HeadViews = @(
        "06_head_detail.png"
    )

    $HeadSize = Save-ConnectorSheet `
        -ImageNames $HeadViews `
        -OutputPath $HeadJpg `
        -CellWidth 280 `
        -CellHeight 280 `
        -Columns 1 `
        -MaxBytes 16000L

    $HeadBase64Size = Write-Base64Lines `
        -SourcePath $HeadJpg `
        -OutputPath $HeadBase64

    # ========================================================
    # CONNECTOR SAFE IMAGE 3
    #
    # Front-leg + rear-leg closeups.
    # ========================================================

    $LegViews = @(
        "07_front_detail.png",
        "08_rear_detail.png"
    )

    $LegSize = Save-ConnectorSheet `
        -ImageNames $LegViews `
        -OutputPath $LegsJpg `
        -CellWidth 240 `
        -CellHeight 240 `
        -Columns 2 `
        -MaxBytes 18000L

    $LegBase64Size = Write-Base64Lines `
        -SourcePath $LegsJpg `
        -OutputPath $LegsBase64

    # ========================================================
    # TRANSPORT MANIFEST
    # ========================================================

    $TransportImages = @()

    $TransportImages += New-TransportRecord `
        -Role "whole_horse_silhouette" `
        -JpgRelative "captures/horse-review/auto/chat/01_silhouette.jpg" `
        -Base64Relative "captures/horse-review/auto/chat/01_silhouette.b64.txt" `
        -JpgAbsolute $SilhouetteJpg `
        -Base64Absolute $SilhouetteBase64 `
        -Views $SilhouetteViews

    $TransportImages += New-TransportRecord `
        -Role "head_detail" `
        -JpgRelative "captures/horse-review/auto/chat/02_head.jpg" `
        -Base64Relative "captures/horse-review/auto/chat/02_head.b64.txt" `
        -JpgAbsolute $HeadJpg `
        -Base64Absolute $HeadBase64 `
        -Views $HeadViews

    $TransportImages += New-TransportRecord `
        -Role "limb_detail" `
        -JpgRelative "captures/horse-review/auto/chat/03_legs.jpg" `
        -Base64Relative "captures/horse-review/auto/chat/03_legs.b64.txt" `
        -JpgAbsolute $LegsJpg `
        -Base64Absolute $LegsBase64 `
        -Views $LegViews

    $Manifest = [ordered]@{
        status = "READY_FOR_CHATGPT_TRANSPORT"
        version = $Version
        generated_utc = (Get-Date).ToUniversalTime().ToString("o")
        preferred_retrieval_order = @(
            "captures/horse-review/auto/chat/01_silhouette.jpg",
            "captures/horse-review/auto/chat/02_head.jpg",
            "captures/horse-review/auto/chat/03_legs.jpg"
        )
        fallback = "Use the matching line-wrapped .b64.txt file. Fetch it in line ranges if necessary."
        images = $TransportImages
        legacy_review = "captures/horse-review/auto/review_chat.jpg"
        full_resolution_views = "captures/horse-review/auto/views"
    }

    $ManifestJson = (
        $Manifest |
        ConvertTo-Json -Depth 10
    )

    Write-Utf8NoBom `
        $TransportManifest `
        $ManifestJson

    if (-not (Test-Path $TransportManifest)) {
        throw "review_transport.json was not created."
    }

    Write-Host ""
    Write-Host "TRANSPORT_MANIFEST=$TransportManifest" -ForegroundColor Green
    Write-Host "SILHOUETTE_BYTES=$SilhouetteSize"
    Write-Host "SILHOUETTE_BASE64_BYTES=$SilhouetteBase64Size"
    Write-Host "HEAD_BYTES=$HeadSize"
    Write-Host "HEAD_BASE64_BYTES=$HeadBase64Size"
    Write-Host "LEGS_BYTES=$LegSize"
    Write-Host "LEGS_BASE64_BYTES=$LegBase64Size"
    Write-Host ""

    # ========================================================
    # INVENTORY ACTUAL EDITABLE BLEND
    # ========================================================

    if (-not (Test-Path $InventoryPy)) {
        throw "Inventory Python script is missing."
    }

    if (-not (Test-Path $BlendFile)) {
        throw "Horse blend file is missing."
    }

    $Blender = Find-Blender

    if (-not $Blender) {
        throw "blender.exe not found."
    }

    if (Test-Path $Temp) {

        Remove-Item `
            $Temp `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Force `
        $Temp |
        Out-Null

    $QuotedBlend = '"' + $BlendFile + '"'
    $QuotedScript = '"' + $InventoryPy + '"'
    $QuotedOutput = '"' + $InventoryJson + '"'

    $Arguments = @(
        $QuotedBlend,
        "--background",
        "--python",
        $QuotedScript,
        "--",
        $QuotedOutput
    )

    $Process = Start-Process `
        -FilePath $Blender `
        -ArgumentList $Arguments `
        -RedirectStandardOutput $StdOutFile `
        -RedirectStandardError $StdErrFile `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if (Test-Path $StdOutFile) {

        $OutputText = Get-Content `
            $StdOutFile `
            -Raw

        if ($OutputText) {
            Write-Host $OutputText
        }
    }

    if (Test-Path $StdErrFile) {

        $ErrorText = Get-Content `
            $StdErrFile `
            -Raw

        if ($ErrorText) {

            Write-Host ""
            Write-Host "BLENDER_INVENTORY_STDERR:" -ForegroundColor Yellow
            Write-Host $ErrorText
        }
    }

    if ($Process.ExitCode -ne 0) {
        throw "Blender model inventory failed."
    }

    if (-not (Test-Path $InventoryJson)) {
        throw "model_inventory.json was not created."
    }

    $InventorySize = (
        Get-Item $InventoryJson
    ).Length

    if ($InventorySize -lt 100) {
        throw "model_inventory.json appears invalid."
    }

    Write-Host "MODEL_INVENTORY=$InventoryJson"
    Write-Host "MODEL_INVENTORY_BYTES=$InventorySize"
    Write-Host ""

    # ========================================================
    # EXACT CONNECTOR TRANSPORT STAGING
    #
    # This is intentionally exact.
    # No git add .
    # No git add -A
    # ========================================================

    $TransportStagePaths = @(
        "captures/horse-review/auto/chat/01_silhouette.jpg",
        "captures/horse-review/auto/chat/01_silhouette.b64.txt",
        "captures/horse-review/auto/chat/02_head.jpg",
        "captures/horse-review/auto/chat/02_head.b64.txt",
        "captures/horse-review/auto/chat/03_legs.jpg",
        "captures/horse-review/auto/chat/03_legs.b64.txt",
        "captures/horse-review/auto/chat/review_transport.json"
    )

    foreach ($Relative in $TransportStagePaths) {

        $Absolute = Join-Path `
            $Root `
            $Relative

        if (-not (Test-Path $Absolute)) {
            throw "Transport output missing: $Relative"
        }

        git add -f -- $Relative

        if ($LASTEXITCODE -ne 0) {
            throw "Git force-add failed for transport file: $Relative"
        }

        Write-Host "TRANSPORT_STAGED=$Relative"
    }

    if (Test-Path $Temp) {

        Remove-Item `
            $Temp `
            -Recurse `
            -Force
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " CHATGPT HANDOFF SUCCESS" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "CONNECTOR_SAFE_REVIEW=YES" -ForegroundColor Green
    Write-Host "TRANSPORT_STATUS=READY_FOR_CHATGPT_TRANSPORT" -ForegroundColor Green
    Write-Host "TRANSPORT_VERSION=$Version" -ForegroundColor Green
    Write-Host ""
    Write-Host "Future review order:" -ForegroundColor Cyan
    Write-Host "  1. chat/01_silhouette.jpg"
    Write-Host "  2. chat/02_head.jpg"
    Write-Host "  3. chat/03_legs.jpg"
    Write-Host ""
    Write-Host "Base64 text fallback is also generated for each image." -ForegroundColor Cyan
    Write-Host ""

    exit 0
}
catch {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " CHATGPT HANDOFF FAILED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""

    exit 1
}
