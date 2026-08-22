param(
    [Parameter(Mandatory=$true)]
    [string]$Script,

    [string[]]$ScriptArguments = @()
)

$Root = "C:\Users\Jimmy\Desktop\Broken Knight"

$LogDir = Join-Path $Root "Powershell output"
$LogFile = Join-Path $LogDir "test.txt"

$RunId = Get-Date -Format "yyyyMMdd_HHmmss_fff"

$WorkDir = Join-Path `
    $Root `
    ("tmp\horse-safe-run-" + $RunId)

$StdOutFile = Join-Path `
    $WorkDir `
    "child.stdout.txt"

$StdErrFile = Join-Path `
    $WorkDir `
    "child.stderr.txt"

$ErrorActionPreference = "Stop"


function Append-SafeLog {

    param(
        [string[]]$Lines
    )

    $Attempts = 0

    while ($Attempts -lt 20) {

        try {

            Add-Content `
                -LiteralPath $LogFile `
                -Value $Lines `
                -Encoding UTF8 `
                -ErrorAction Stop

            return
        }
        catch {

            $Attempts++

            Start-Sleep `
                -Milliseconds 100
        }
    }

    throw (
        "Could not append to permanent horse log after 20 attempts: " +
        $LogFile
    )
}


function Read-RedirectedText {

    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    [byte[]]$Bytes = (
        [System.IO.File]::ReadAllBytes(
            $Path
        )
    )

    if ($Bytes.Length -eq 0) {
        return ""
    }

    # UTF-16 little-endian BOM
    if (
        $Bytes.Length -ge 2 -and
        $Bytes[0] -eq 0xFF -and
        $Bytes[1] -eq 0xFE
    ) {

        return (
            [System.Text.Encoding]::Unicode.GetString(
                $Bytes,
                2,
                $Bytes.Length - 2
            )
        )
    }

    # UTF-8 BOM
    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF
    ) {

        return (
            [System.Text.Encoding]::UTF8.GetString(
                $Bytes,
                3,
                $Bytes.Length - 3
            )
        )
    }

    # Detect UTF-16 without BOM.
    $OddZeroCount = 0
    $OddSamples = 0

    for (
        $Index = 1;
        $Index -lt $Bytes.Length;
        $Index += 2
    ) {

        $OddSamples++

        if ($Bytes[$Index] -eq 0) {
            $OddZeroCount++
        }

        if ($OddSamples -ge 200) {
            break
        }
    }

    if (
        $OddSamples -gt 0 -and
        (
            $OddZeroCount /
            [double]$OddSamples
        ) -gt 0.35
    ) {

        return (
            [System.Text.Encoding]::Unicode.GetString(
                $Bytes
            )
        )
    }

    return (
        [System.Text.Encoding]::UTF8.GetString(
            $Bytes
        )
    )
}


try {

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $LogDir |
        Out-Null

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $WorkDir |
        Out-Null

    Append-SafeLog @(
        "",
        "============================================================",
        "HORSE SAFE RUNNER V2 START",
        "============================================================",
        "TIME=$(Get-Date)",
        "SCRIPT=$Script",
        "WORK_DIR=$WorkDir",
        "LOG=$LogFile",
        ""
    )

    if (-not (Test-Path -LiteralPath $Script)) {

        throw (
            "Target PowerShell script does not exist: " +
            $Script
        )
    }

    # Syntax validation happens BEFORE child execution.
    # If this finds a parser error, THIS runner records it.

    $Source = Get-Content `
        -LiteralPath $Script `
        -Raw

    try {

        [void][ScriptBlock]::Create(
            $Source
        )

        Append-SafeLog @(
            "CHILD_PARSE_CHECK=PASS",
            ""
        )
    }
    catch {

        Append-SafeLog @(
            "",
            "============================================================",
            "CHILD POWERSHELL PARSE ERROR",
            "============================================================",
            "TIME=$(Get-Date)",
            "ERROR_MESSAGE=$($_.Exception.Message)",
            "ERROR_TYPE=$($_.Exception.GetType().FullName)",
            "ERROR_POSITION=$($_.InvocationInfo.PositionMessage)",
            "ERROR_STACK=$($_.ScriptStackTrace)",
            "RESULT=FAILED",
            ""
        )

        throw
    }

    $PowerShellExe = (
        Get-Command `
            powershell.exe `
            -ErrorAction Stop
    ).Source

    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        ('"' + $Script + '"')
    )

    foreach ($Argument in $ScriptArguments) {

        $Arguments += (
            '"' +
            (
                $Argument.Replace(
                    '"',
                    '\"'
                )
            ) +
            '"'
        )
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " HORSE SAFE RUNNER V2" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "SCRIPT=$Script"
    Write-Host "PERMANENT_LOG=$LogFile"
    Write-Host ""
    Write-Host "No process is holding test.txt open while the child runs." -ForegroundColor Green
    Write-Host ""

    # ========================================================
    # CRITICAL:
    #
    # Redirect child console output to TEMP files.
    #
    # DO NOT Tee-Object directly into test.txt.
    #
    # The child is now free to write test.txt itself.
    # ========================================================

    $Process = Start-Process `
        -FilePath $PowerShellExe `
        -ArgumentList $Arguments `
        -RedirectStandardOutput $StdOutFile `
        -RedirectStandardError $StdErrFile `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    $ExitCode = (
        $Process.ExitCode
    )

    # Child is FINISHED now.
    # It can no longer compete for test.txt.

    $StdOut = Read-RedirectedText `
        -Path $StdOutFile

    $StdErr = Read-RedirectedText `
        -Path $StdErrFile

    Append-SafeLog @(
        "",
        "============================================================",
        "HORSE SAFE RUNNER V2 CHILD CONSOLE",
        "============================================================",
        "TIME=$(Get-Date)",
        "CHILD_EXIT_CODE=$ExitCode",
        ""
    )

    if ($StdOut) {

        Append-SafeLog @(
            "---------------- CHILD STDOUT BEGIN ----------------",
            $StdOut,
            "---------------- CHILD STDOUT END ----------------",
            ""
        )

        Write-Host $StdOut
    }

    if ($StdErr) {

        Append-SafeLog @(
            "---------------- CHILD STDERR BEGIN ----------------",
            $StdErr,
            "---------------- CHILD STDERR END ----------------",
            ""
        )

        Write-Host $StdErr -ForegroundColor Yellow
    }

    Append-SafeLog @(
        "CHILD_EXIT_CODE=$ExitCode",
        ""
    )

    if ($ExitCode -ne 0) {

        Append-SafeLog @(
            "RESULT=FAILED",
            ""
        )

        throw (
            "Child PowerShell failed with exit code " +
            $ExitCode
        )
    }

    Append-SafeLog @(
        "RESULT=SUCCESS",
        ""
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " SAFE RUNNER V2 COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""

    exit 0
}
catch {

    try {

        Append-SafeLog @(
            "",
            "============================================================",
            "HORSE SAFE RUNNER V2 FAILURE",
            "============================================================",
            "TIME=$(Get-Date)",
            "SCRIPT=$Script",
            "ERROR_MESSAGE=$($_.Exception.Message)",
            "ERROR_TYPE=$($_.Exception.GetType().FullName)",
            "ERROR_POSITION=$($_.InvocationInfo.PositionMessage)",
            "ERROR_STACK=$($_.ScriptStackTrace)",
            "RESULT=FAILED",
            ""
        )
    }
    catch {

        Write-Host ""
        Write-Host "CRITICAL: permanent log write also failed." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " SAFE RUNNER V2 FAILED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "PERMANENT LOG:" -ForegroundColor Yellow
    Write-Host $LogFile
    Write-Host ""

    exit 1
}
