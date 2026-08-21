param(
    [string]$ProjectRoot = "C:\Users\Jimmy\Desktop\Broken Knight",
    [string]$VideoPath = ""
)

$ErrorActionPreference = "Stop"

$OutputDir = Join-Path $ProjectRoot "Powershell output"
$TestFile = Join-Path $OutputDir "test.txt"
$LogFile = Join-Path $OutputDir "ai-runner.log"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Report([string]$m) {
    Add-Content -LiteralPath $TestFile -Value $m -Encoding UTF8
}
function Log([string]$m) {
    Add-Content -LiteralPath $LogFile -Value ("{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m) -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($VideoPath)) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "captures") -Filter "*.avi" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $latest) {
        Report "AUTO_UPLOAD_RESULT: FAILED - no AVI found"
        Log "UPLOAD_V3_FAILED|no AVI"
        exit 2
    }
    $VideoPath = $latest.FullName
}

$VideoPath = [IO.Path]::GetFullPath($VideoPath)
$BaseName = [IO.Path]::GetFileName($VideoPath)

if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
    Report "AUTO_UPLOAD_RESULT: FAILED - AVI missing"
    Log "UPLOAD_V3_FAILED|AVI missing|$VideoPath"
    exit 3
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BKUploadNativeV3
{
    public const uint WM_SETTEXT = 0x000C;
    public const uint BM_CLICK = 0x00F5;

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, string lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
"@

function Desc($root) {
    return $root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
}

function ById($root,[string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,$id
    )
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$cond)
}

function Chat {
    foreach ($p in @(Get-Process firefox -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0})) {
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
            $url = ById $root "urlbar-input"
            if ($url -and ([string]$url.Current.Name -match '^https://chatgpt\.com/')) {
                return [pscustomobject]@{ Process=$p; Root=$root }
            }
        } catch {}
    }
    return $null
}

function FileDialog {
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    foreach ($w in $desktop.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )) {
        try {
            if ($w.Current.IsOffscreen) { continue }

            # A real Windows common file chooser exposes either the standard
            # 1148 filename control or a visible Open button plus one Edit/ComboBox.
            if (ById $w "1148") { return $w }

            $hasOpen = $false
            $hasField = $false
            foreach ($e in (Desc $w)) {
                try {
                    $type = [string]$e.Current.ControlType.ProgrammaticName
                    $name = [string]$e.Current.Name
                    if ($type -match 'Button$' -and $name -match '^(Open|Choose|Select)$') { $hasOpen = $true }
                    if ($type -match '(Edit|ComboBox)$') { $hasField = $true }
                } catch {}
                if ($hasOpen -and $hasField) { return $w }
            }
        } catch {}
    }
    return $null
}

function WaitDialog([int]$ms) {
    $count = [Math]::Ceiling($ms/150.0)
    for ($i=0;$i-lt$count;$i++) {
        Start-Sleep -Milliseconds 150
        $d = FileDialog
        if ($d) { return $d }
    }
    return $null
}

function WaitDialogClosed([int]$ms) {
    $count = [Math]::Ceiling($ms/150.0)
    for ($i=0;$i-lt$count;$i++) {
        Start-Sleep -Milliseconds 150
        if (-not (FileDialog)) { return $true }
    }
    return $false
}

function Try-GetValue($e) {
    try {
        $vp = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$vp)) {
            return [string]([System.Windows.Automation.ValuePattern]$vp).Current.Value
        }
    } catch {}
    return ""
}

function Try-SetValue($e,[string]$value) {
    try {
        $vp = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$vp)) {
            $pattern = [System.Windows.Automation.ValuePattern]$vp
            if (-not $pattern.Current.IsReadOnly) {
                $pattern.SetValue($value)
                Start-Sleep -Milliseconds 150
                return $true
            }
        }
    } catch {}
    return $false
}

function Field-Candidates($dialog) {
    $list = @()

    $standard = ById $dialog "1148"
    if ($standard) {
        $list += [pscustomobject]@{ Element=$standard; Score=1000; Why="automationId=1148" }
    }

    foreach ($e in (Desc $dialog)) {
        try {
            if ($e.Current.IsOffscreen) { continue }
            $type = [string]$e.Current.ControlType.ProgrammaticName
            if ($type -notmatch '(Edit|ComboBox)$') { continue }

            $score = 0
            $aid = [string]$e.Current.AutomationId
            $name = [string]$e.Current.Name
            $class = [string]$e.Current.ClassName

            if ($aid -eq "1148") { $score += 900 }
            if ($name -match '(?i)file.*name|name.*file') { $score += 500 }
            if ($class -match '(?i)edit') { $score += 200 }
            if ($type -match 'Edit$') { $score += 150 }
            if ($e.Current.IsKeyboardFocusable) { $score += 100 }

            # Prefer writable controls.
            $vp = $null
            if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$vp)) {
                if (-not ([System.Windows.Automation.ValuePattern]$vp).Current.IsReadOnly) { $score += 350 }
            }

            $list += [pscustomobject]@{ Element=$e; Score=$score; Why="$type|$name|$aid|$class" }
        } catch {}
    }

    return @($list | Sort-Object Score -Descending)
}

function Open-Candidates($dialog) {
    $list = @()

    $id1 = ById $dialog "1"
    if ($id1) { $list += [pscustomobject]@{ Element=$id1; Score=1000; Why="automationId=1" } }

    foreach ($e in (Desc $dialog)) {
        try {
            if ($e.Current.IsOffscreen) { continue }
            $type = [string]$e.Current.ControlType.ProgrammaticName
            $name = [string]$e.Current.Name
            if ($type -notmatch 'Button$') { continue }

            $score = 0
            if ($name -eq "Open") { $score += 900 }
            elseif ($name -match '^(Choose|Select)$') { $score += 700 }
            if ($e.Current.IsKeyboardFocusable) { $score += 100 }

            if ($score -gt 0) {
                $list += [pscustomobject]@{ Element=$e; Score=$score; Why="$type|$name|$($e.Current.AutomationId)" }
            }
        } catch {}
    }

    return @($list | Sort-Object Score -Descending)
}

function Activate-Open($dialog) {
    foreach ($candidate in (Open-Candidates $dialog)) {
        $e = $candidate.Element
        try {
            $inv = $null
            if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern,[ref]$inv)) {
                ([System.Windows.Automation.InvokePattern]$inv).Invoke()
                Log "UPLOAD_V3_OPEN|InvokePattern|$($candidate.Why)"
                return $true
            }
        } catch {}

        try {
            $hwnd = [IntPtr]([int64]$e.Current.NativeWindowHandle)
            if ($hwnd -ne [IntPtr]::Zero) {
                [BKUploadNativeV3]::SendMessage($hwnd,[BKUploadNativeV3]::BM_CLICK,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
                Log "UPLOAD_V3_OPEN|BM_CLICK|$($candidate.Why)"
                return $true
            }
        } catch {}

        try {
            $e.SetFocus()
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Log "UPLOAD_V3_OPEN|FocusEnter|$($candidate.Why)"
            return $true
        } catch {}
    }

    return $false
}

function Put-Path-In-Dialog($dialog,[string]$path,[string]$basename) {
    foreach ($candidate in (Field-Candidates $dialog)) {
        $e = $candidate.Element
        Log "UPLOAD_V3_FIELD_TRY|score=$($candidate.Score)|$($candidate.Why)"

        # Method A: UIA ValuePattern, then READ IT BACK before continuing.
        if (Try-SetValue $e $path) {
            $readback = Try-GetValue $e
            Log "UPLOAD_V3_FIELD_VALUEPATTERN|readback=$readback"
            if ($readback -eq $path -or $readback -like "*$basename*") {
                return $true
            }
        }

        # Method B: direct WM_SETTEXT to this exact UIA element HWND.
        try {
            $hwnd = [IntPtr]([int64]$e.Current.NativeWindowHandle)
            if ($hwnd -ne [IntPtr]::Zero) {
                [BKUploadNativeV3]::SendMessage($hwnd,[BKUploadNativeV3]::WM_SETTEXT,[IntPtr]::Zero,$path) | Out-Null
                Start-Sleep -Milliseconds 150
                $readback = Try-GetValue $e
                Log "UPLOAD_V3_FIELD_WM_SETTEXT|readback=$readback"
                if ($readback -eq $path -or $readback -like "*$basename*") {
                    return $true
                }
            }
        } catch {}

        # Method C: focus this exact candidate and paste.
        try {
            [System.Windows.Forms.Clipboard]::SetText($path)
            $e.SetFocus()
            Start-Sleep -Milliseconds 120
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Start-Sleep -Milliseconds 60
            [System.Windows.Forms.SendKeys]::SendWait("^v")
            Start-Sleep -Milliseconds 180
            $readback = Try-GetValue $e
            Log "UPLOAD_V3_FIELD_PASTE|readback=$readback"
            if ($readback -eq $path -or $readback -like "*$basename*") {
                return $true
            }
        } catch {}
    }

    # Final bounded keyboard fallback: focus dialog and use File name access key.
    try {
        $hwnd = [IntPtr]([int64]$dialog.Current.NativeWindowHandle)
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][BKUploadNativeV3]::SetForegroundWindow($hwnd)
        }
        [System.Windows.Forms.Clipboard]::SetText($path)
        [System.Windows.Forms.SendKeys]::SendWait("%n")
        Start-Sleep -Milliseconds 120
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Milliseconds 180
        Log "UPLOAD_V3_FIELD_ALT_N_PASTE|attempted"
        return $true
    } catch {}

    return $false
}

function Verify-Attachment([string]$basename,[int]$seconds) {
    for ($i=0;$i-lt($seconds*4);$i++) {
        Start-Sleep -Milliseconds 250
        $c = Chat
        if (-not $c) { continue }

        foreach ($e in (Desc $c.Root)) {
            try {
                if ([string]$e.Current.Name -like "*$basename*") { return $true }
            } catch {}
        }
    }
    return $false
}

$chat = Chat
if (-not $chat) {
    Report "AUTO_UPLOAD_RESULT: FAILED - ChatGPT Firefox tab not found"
    Log "UPLOAD_V3_FAILED|ChatGPT tab not found"
    exit 4
}

$ws = New-Object -ComObject WScript.Shell
[void]$ws.AppActivate($chat.Process.Id)
Start-Sleep -Milliseconds 400

$chat = Chat
$plus = ById $chat.Root "composer-plus-btn"
if (-not $plus) {
    Report "AUTO_UPLOAD_RESULT: FAILED - composer plus button not found"
    Log "UPLOAD_V3_FAILED|composer-plus-btn missing"
    exit 5
}

try {
    $plus.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
} catch {
    Report "AUTO_UPLOAD_RESULT: FAILED - could not open attachment menu"
    Log "UPLOAD_V3_FAILED|plus activation"
    exit 6
}

Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait("{HOME}")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

$dialog = WaitDialog 1800
if (-not $dialog) {
    [System.Windows.Forms.SendKeys]::SendWait("{HOME}")
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    $dialog = WaitDialog 2200
}

if (-not $dialog) {
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}{ESC}")
    Report "AUTO_UPLOAD_RESULT: FAILED - Windows file chooser did not appear"
    Log "UPLOAD_V3_FAILED|no file chooser"
    exit 10
}

Report "AUTO_UPLOAD_FILE_CHOOSER: FOUND"
Log "UPLOAD_V3_FILE_CHOOSER_FOUND|name=$($dialog.Current.Name)|class=$($dialog.Current.ClassName)"

$pathInserted = Put-Path-In-Dialog $dialog $VideoPath $BaseName
if (-not $pathInserted) {
    Report "AUTO_UPLOAD_RESULT: FAILED - no writable filename control found"
    Log "UPLOAD_V3_FAILED|no writable filename field"
    exit 11
}

Log "UPLOAD_V3_PATH_INSERTED"

$opened = Activate-Open $dialog
if (-not $opened) {
    # One keyboard fallback only.
    try {
        [System.Windows.Forms.SendKeys]::SendWait("%o")
        $opened = $true
        Log "UPLOAD_V3_OPEN|Alt+O"
    } catch {}
}

if (-not $opened) {
    Report "AUTO_UPLOAD_RESULT: FAILED - could not activate Open"
    Log "UPLOAD_V3_FAILED|Open activation"
    exit 12
}

$closed = WaitDialogClosed 3000
if (-not $closed) {
    # One Enter fallback if Open action was accepted by UIA but did not submit.
    try {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Log "UPLOAD_V3_OPEN|final Enter"
    } catch {}
    $closed = WaitDialogClosed 1800
}

if (-not $closed) {
    Report "AUTO_UPLOAD_RESULT: FAILED - chooser stayed open after verified path entry"
    Log "UPLOAD_V3_FAILED|chooser stayed open after path entry"
    exit 13
}

Report "AUTO_UPLOAD_SUBMITTED: $VideoPath"
Log "UPLOAD_V3_SUBMITTED|$VideoPath"

Start-Sleep -Seconds 1
[void]$ws.AppActivate($chat.Process.Id)

if (Verify-Attachment $BaseName 12) {
    Report "AUTO_UPLOAD_VERIFIED: $BaseName"
    Report "AUTO_UPLOAD_RESULT: SUCCESS"
    Log "UPLOAD_V3_SUCCESS|$VideoPath"
    exit 0
}

Report "AUTO_UPLOAD_RESULT: SUBMITTED_UNVERIFIED"
Log "UPLOAD_V3_SUBMITTED_UNVERIFIED|$VideoPath"
exit 0
