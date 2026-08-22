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

$InventoryPy = Join-Path $Root "captures\horse-model-inventory.py"
$BlendFile = Join-Path $Root "blender\world\animals\riverwatch_horse.blend"

$Temp = Join-Path $Root "tmp\horse_handoff_work"
$StdOutFile = Join-Path $Temp "inventory.stdout.txt"
$StdErrFile = Join-Path $Temp "inventory.stderr.txt"


function Find-Blender {

    $Command = Get-Command blender.exe -ErrorAction SilentlyContinue

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

    $Encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        $Encoding
    )
}


try {

    Write-Host ""
    Write-Host "CHATGPT_HANDOFF_VERSION=$Version"

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

        $Path = Join-Path $ViewsDir $Name

        if (-not (Test-Path $Path)) {
            throw "Missing review image: $Name"
        }
    }

    # ========================================================
    # COMPACT 4 x 2 CONTACT SHEET
    # ========================================================

    Add-Type -AssemblyName System.Drawing

    $CellWidth = 256
    $CellHeight = 256

    $Columns = 4
    $Rows = 2

    $SheetWidth = 1024
    $SheetHeight = 512

    $Canvas = New-Object `
        -TypeName System.Drawing.Bitmap `
        -ArgumentList $SheetWidth,$SheetHeight

    $Graphics = [System.Drawing.Graphics]::FromImage(
        $Canvas
    )

    $Background = [System.Drawing.Color]::FromArgb(
        15,
        18,
        23
    )

    $Graphics.Clear(
        $Background
    )

    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    for (
        $Index = 0;
        $Index -lt $ViewFiles.Count;
        $Index++
    ) {

        $Row = [Math]::Floor(
            $Index / $Columns
        )

        $Column = (
            $Index % $Columns
        )

        $X = (
            $Column * $CellWidth
        )

        $Y = (
            $Row * $CellHeight
        )

        $ImagePath = Join-Path `
            $ViewsDir `
            $ViewFiles[$Index]

        $Image = [System.Drawing.Image]::FromFile(
            $ImagePath
        )

        $Graphics.DrawImage(
            $Image,
            $X,
            $Y,
            $CellWidth,
            $CellHeight
        )

        $Image.Dispose()
    }

    if (Test-Path $ReviewJpg) {
        Remove-Item $ReviewJpg -Force
    }

    $JpegEncoder = $null

    foreach (
        $Encoder in
        [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
    ) {

        if (
            $Encoder.MimeType -eq
            "image/jpeg"
        ) {

            $JpegEncoder = $Encoder
            break
        }
    }

    if (-not $JpegEncoder) {
        throw "JPEG encoder was not found."
    }

    $EncoderParameters = New-Object `
        -TypeName System.Drawing.Imaging.EncoderParameters `
        -ArgumentList 1

    $QualityEncoder = [System.Drawing.Imaging.Encoder]::Quality

    $QualityParameter = New-Object `
        -TypeName System.Drawing.Imaging.EncoderParameter `
        -ArgumentList $QualityEncoder,62L

    $EncoderParameters.Param[0] = $QualityParameter

    $Canvas.Save(
        $ReviewJpg,
        $JpegEncoder,
        $EncoderParameters
    )

    $QualityParameter.Dispose()
    $EncoderParameters.Dispose()
    $Graphics.Dispose()
    $Canvas.Dispose()

    if (-not (Test-Path $ReviewJpg)) {
        throw "review_chat.jpg was not created."
    }

    $ReviewSize = (
        Get-Item $ReviewJpg
    ).Length

    if ($ReviewSize -lt 10000) {
        throw "review_chat.jpg appears invalid."
    }

    Write-Host "REVIEW_CHAT_JPG=$ReviewJpg"
    Write-Host "REVIEW_CHAT_BYTES=$ReviewSize"

    # ========================================================
    # LINE-WRAPPED BASE64
    #
    # This is specifically for ChatGPT retrieval from GitHub.
    # ========================================================

    [byte[]]$ReviewBytes = [System.IO.File]::ReadAllBytes(
        $ReviewJpg
    )

    $Base64 = [Convert]::ToBase64String(
        $ReviewBytes
    )

    $TextBuilder = New-Object System.Text.StringBuilder

    $Index = 0

    while ($Index -lt $Base64.Length) {

        $Remaining = (
            $Base64.Length - $Index
        )

        $Length = 120

        if ($Remaining -lt 120) {
            $Length = $Remaining
        }

        $Chunk = $Base64.Substring(
            $Index,
            $Length
        )

        [void]$TextBuilder.AppendLine(
            $Chunk
        )

        $Index += $Length
    }

    Write-Utf8NoBom `
        $ReviewBase64 `
        $TextBuilder.ToString()

    $Base64Size = (
        Get-Item $ReviewBase64
    ).Length

    Write-Host "REVIEW_BASE64=$ReviewBase64"
    Write-Host "REVIEW_BASE64_BYTES=$Base64Size"

    # ========================================================
    # INVENTORY ACTUAL EDITABLE .BLEND
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
        Remove-Item $Temp -Recurse -Force
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

    if (Test-Path $Temp) {
        Remove-Item $Temp -Recurse -Force
    }

    Write-Host "CHATGPT_HANDOFF_SUCCESS=YES" -ForegroundColor Green

    exit 0
}
catch {

    Write-Host ""
    Write-Host "CHATGPT_HANDOFF_FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""

    exit 1
}