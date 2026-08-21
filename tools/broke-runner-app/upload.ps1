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

try {
    Report "UPLOAD_SAFE_STAGE: START"

    if ([string]::IsNullOrWhiteSpace($VideoPath)) {
        Report "UPLOAD_RESULT: FAILED - no file path supplied"
        exit 2
    }

    $VideoPath = [IO.Path]::GetFullPath($VideoPath)

    if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
        Report "UPLOAD_RESULT: FAILED - file missing"
        Report "UPLOAD_FILE_PATH: $VideoPath"
        exit 3
    }

    $BaseName = [IO.Path]::GetFileName($VideoPath)

    Report "UPLOAD_FILE_EXISTS: YES"
    Report "UPLOAD_FILE_PATH: $VideoPath"
    Report "UPLOAD_FILE_BYTES: $((Get-Item -LiteralPath $VideoPath).Length)"

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BKV10RestoreNative {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

    function Diagnostic-Upload-FocusChain([string]$tag) {
        try {
            $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
            Report "UPLOAD_DIAG_FOCUS|$tag|$(Element-Info $focused)"

            if ($focused) {
                $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
                $cur = $focused

                for ($i=0; $i -lt 8; $i++) {
                    if (-not $cur) { break }
                    Report "UPLOAD_DIAG_PARENT_${i}|$tag|$(Element-Info $cur)"
                    try { $cur = $walker.GetParent($cur) } catch { break }
                }
            }
        } catch {
            Report "UPLOAD_DIAG_FOCUS_ERROR|$tag|$($_.Exception.Message)"
        }
    }

    function Descendants($root) {
        return $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
    }

    function Element-Info($e) {
        if (-not $e) { return "<null>" }
        try {
            $r = $e.Current.BoundingRectangle
            return ("type={0}|name={1}|aid={2}|class={3}|focusable={4}|offscreen={5}|rect={6},{7},{8},{9}" -f
                [string]$e.Current.ControlType.ProgrammaticName,
                [string]$e.Current.Name,
                [string]$e.Current.AutomationId,
                [string]$e.Current.ClassName,
                $e.Current.IsKeyboardFocusable,
                $e.Current.IsOffscreen,
                [int]$r.X,[int]$r.Y,[int]$r.Width,[int]$r.Height)
        } catch {
            return "<unavailable>"
        }
    }

    function Report-Focus([string]$tag) {
        try {
            $f = [System.Windows.Automation.AutomationElement]::FocusedElement
            Report "UPLOAD_SAFE_FOCUS_${tag}: $(Element-Info $f)"
        } catch {
            Report "UPLOAD_SAFE_FOCUS_${tag}: ERROR $($_.Exception.Message)"
        }
    }

    function Find-ByAutomationId($root,[string]$automationId) {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $automationId
        )

        return $root.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            $condition
        )
    }

    function Find-AllByAutomationId($root,[string]$automationId) {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $automationId
        )

        return @($root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            $condition
        ))
    }

    function Supported-Pattern-Names($element) {
        $names = @()
        if (-not $element) { return "" }

        try {
            foreach ($pattern in $element.GetSupportedPatterns()) {
                try { $names += [string]$pattern.ProgrammaticName } catch {}
            }
        } catch {}

        return ($names -join ",")
    }

    function Parent-Info($element,[int]$maxDepth=5) {
        if (-not $element) { return }

        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $current = $element

        for ($i=0; $i -lt $maxDepth; $i++) {
            try {
                Report "UPLOAD_SAFE_PARENT_${i}: $(Element-Info $current)"
                $current = $walker.GetParent($current)
                if (-not $current) { break }
            } catch {
                break
            }
        }
    }

    function Get-AncestorFileDialog($element) {
        if (-not $element) { return $null }

        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $current = $element

        for ($i=0; $i -lt 10; $i++) {
            try {
                $class = [string]$current.Current.ClassName
                $type = [string]$current.Current.ControlType.ProgrammaticName
                $name = [string]$current.Current.Name

                if (
                    $type -eq "ControlType.Window" -and
                    $class -eq "#32770" -and
                    $name -match '(?i)file upload|open|choose|select'
                ) {
                    return $current
                }

                $current = $walker.GetParent($current)
                if (-not $current) { break }
            } catch {
                break
            }
        }

        return $null
    }

    function Find-NestedFileDialog($chatRoot) {
        if (-not $chatRoot) { return $null }

        foreach ($e in (Descendants $chatRoot)) {
            try {
                if ($e.Current.IsOffscreen) { continue }

                $type = [string]$e.Current.ControlType.ProgrammaticName
                $class = [string]$e.Current.ClassName
                $name = [string]$e.Current.Name

                if (
                    $type -eq "ControlType.Window" -and
                    $class -eq "#32770" -and
                    $name -match '(?i)file upload|open|choose|select'
                ) {
                    return $e
                }
            } catch {}
        }

        return $null
    }

    function Find-FileDialogAnywhere {
        # First check whether current keyboard focus is already inside the
        # Windows File Upload dialog. Test 43 proved this is exactly what happens.
        try {
            $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
            $ancestor = Get-AncestorFileDialog $focused
            if ($ancestor) { return $ancestor }
        } catch {}

        # Next search inside the Firefox UIA tree because the common dialog is
        # exposed as a CHILD of the Firefox window, not a top-level desktop sibling.
        $chat = Get-ChatGPTWindow
        if ($chat) {
            $nested = Find-NestedFileDialog $chat.Root
            if ($nested) { return $nested }
        }

        # Keep old desktop-level fallback for compatibility.
        return Find-RealFileDialog
    }

    function Wait-FileDialogAnywhere([int]$milliseconds) {
        $iterations = [Math]::Ceiling($milliseconds / 150.0)

        for ($i=0; $i -lt $iterations; $i++) {
            Start-Sleep -Milliseconds 150
            $dialog = Find-FileDialogAnywhere
            if ($dialog) { return $dialog }
        }

        return $null
    }

    function Wait-FileDialogAnywhereClosed([int]$milliseconds) {
        $iterations = [Math]::Ceiling($milliseconds / 150.0)

        for ($i=0; $i -lt $iterations; $i++) {
            Start-Sleep -Milliseconds 150
            if (-not (Find-FileDialogAnywhere)) { return $true }
        }

        return $false
    }

    function Get-ChatGPTWindow {
        foreach ($proc in @(Get-Process firefox -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })) {
            try {
                $root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
                if (-not $root) { continue }

                $urlBox = Find-ByAutomationId $root "urlbar-input"
                if (-not $urlBox) { continue }

                $url = [string]$urlBox.Current.Name
                if ($url -match '^https://chatgpt\.com/') {
                    return [pscustomobject]@{
                        Process = $proc
                        Root = $root
                        Url = $url
                    }
                }
            } catch {}
        }

        return $null
    }

    function Find-RealFileDialog {
        $desktop = [System.Windows.Automation.AutomationElement]::RootElement

        foreach ($window in $desktop.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition
        )) {
            try {
                if ($window.Current.IsOffscreen) { continue }

                $field = Find-ByAutomationId $window "1148"
                if (-not $field) { continue }

                $class = [string]$window.Current.ClassName

                # Never mistake the Firefox browser window itself for a chooser.
                if ($class -eq "MozillaWindowClass") { continue }

                return $window
            } catch {}
        }

        return $null
    }

    function Wait-FileDialog([int]$milliseconds) {
        $iterations = [Math]::Ceiling($milliseconds / 150.0)

        for ($i=0; $i -lt $iterations; $i++) {
            Start-Sleep -Milliseconds 150
            $dialog = Find-RealFileDialog
            if ($dialog) { return $dialog }
        }

        return $null
    }

    function Wait-DialogClosed([int]$milliseconds) {
        $iterations = [Math]::Ceiling($milliseconds / 150.0)

        for ($i=0; $i -lt $iterations; $i++) {
            Start-Sleep -Milliseconds 150
            if (-not (Find-RealFileDialog)) { return $true }
        }

        return $false
    }

    function Read-Value($element) {
        if (-not $element) { return "" }

        try {
            $vp = $null
            if ($element.TryGetCurrentPattern(
                [System.Windows.Automation.ValuePattern]::Pattern,
                [ref]$vp
            )) {
                return [string]([System.Windows.Automation.ValuePattern]$vp).Current.Value
            }
        } catch {}

        foreach ($child in (Descendants $element)) {
            try {
                $vp = $null
                if ($child.TryGetCurrentPattern(
                    [System.Windows.Automation.ValuePattern]::Pattern,
                    [ref]$vp
                )) {
                    $v = [string]([System.Windows.Automation.ValuePattern]$vp).Current.Value
                    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
                }
            } catch {}
        }

        return ""
    }

    function Fill-And-Submit($dialog,[string]$path) {
        $field = Find-ByAutomationId $dialog "1148"

        if (-not $field) {
            Report "UPLOAD_RESULT: FAILED - file-name field 1148 missing"
            return $false
        }

        $dialogHwnd = [IntPtr]([int64]$dialog.Current.NativeWindowHandle)
        if ($dialogHwnd -ne [IntPtr]::Zero) {
            [void][BKV10RestoreNative]::SetForegroundWindow($dialogHwnd)
        }
        Start-Sleep -Milliseconds 200

        $filled = $false

        # Exact method used by the old V10 uploader first.
        try {
            $vp = $null
            if ($field.TryGetCurrentPattern(
                [System.Windows.Automation.ValuePattern]::Pattern,
                [ref]$vp
            )) {
                $pattern = [System.Windows.Automation.ValuePattern]$vp
                if (-not $pattern.Current.IsReadOnly) {
                    $pattern.SetValue($path)
                    Start-Sleep -Milliseconds 180
                    $filled = $true
                    Report "UPLOAD_SAFE_FILL_METHOD: ValuePattern"
                }
            }
        } catch {
            Report "UPLOAD_SAFE_VALUEPATTERN_ERROR: $($_.Exception.Message)"
        }

        $readback = Read-Value $field
        Report "UPLOAD_SAFE_FILENAME_READBACK_1: $readback"

        if (
            -not $filled -or
            ([string]::IsNullOrWhiteSpace($readback))
        ) {
            # Windows common-dialog keyboard path. No mouse.
            try {
                [System.Windows.Forms.Clipboard]::SetText($path)
                [System.Windows.Forms.SendKeys]::SendWait("%n")
                Start-Sleep -Milliseconds 160
                [System.Windows.Forms.SendKeys]::SendWait("^a")
                Start-Sleep -Milliseconds 70
                [System.Windows.Forms.SendKeys]::SendWait("^v")
                Start-Sleep -Milliseconds 220
                $filled = $true
                Report "UPLOAD_SAFE_FILL_METHOD: AltN_Paste"
            } catch {
                Report "UPLOAD_SAFE_PASTE_ERROR: $($_.Exception.Message)"
            }
        }

        $readback = Read-Value $field
        Report "UPLOAD_SAFE_FILENAME_READBACK_2: $readback"

        if (-not $filled) {
            return $false
        }

        # Old V10 preferred the Open button's InvokePattern.
        $openButton = Find-ByAutomationId $dialog "1"

        if ($openButton) {
            try {
                $invoke = $null
                if ($openButton.TryGetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern,
                    [ref]$invoke
                )) {
                    ([System.Windows.Automation.InvokePattern]$invoke).Invoke()
                    Report "UPLOAD_SAFE_SUBMIT_METHOD: Open_InvokePattern"

                    if (Wait-DialogClosed 2500) {
                        return $true
                    }
                }
            } catch {
                Report "UPLOAD_SAFE_OPEN_INVOKE_ERROR: $($_.Exception.Message)"
            }
        }

        # Exact V10 fallback: Enter from the file-name field.
        try {
            $field = Find-ByAutomationId $dialog "1148"
            if ($field) {
                try { $field.SetFocus() } catch {}
            }
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Report "UPLOAD_SAFE_SUBMIT_METHOD: Enter"

            if (Wait-DialogClosed 2500) {
                return $true
            }
        } catch {
            Report "UPLOAD_SAFE_ENTER_ERROR: $($_.Exception.Message)"
        }

        # One final standard accelerator, still bounded.
        try {
            [System.Windows.Forms.SendKeys]::SendWait("%o")
            Report "UPLOAD_SAFE_SUBMIT_METHOD: AltO"

            if (Wait-DialogClosed 1800) {
                return $true
            }
        } catch {}

        return $false
    }

    function Verify-Attachment([string]$basename,[int]$seconds) {
        for ($i=0; $i -lt ($seconds * 4); $i++) {
            Start-Sleep -Milliseconds 250

            $chat = Get-ChatGPTWindow
            if (-not $chat) { continue }

            foreach ($element in (Descendants $chat.Root)) {
                try {
                    $name = [string]$element.Current.Name

                    if ($name -like "*$basename*") {
                        return $true
                    }

                    if ($name -match '(?i)(unsupported|failed to upload|upload failed|could not upload)') {
                        Report "UPLOAD_CHATGPT_MESSAGE: $name"
                    }
                } catch {}
            }
        }

        return $false
    }

    function Find-SendButton($root) {
        if (-not $root) { return $null }

        foreach ($aid in @(
            "composer-submit-button",
            "send-button",
            "composer-send-button"
        )) {
            try {
                $candidate = Find-ByAutomationId $root $aid

                if ($candidate) {
                    return $candidate
                }
            } catch {}
        }

        foreach ($element in (Descendants $root)) {
            try {
                if ($element.Current.IsOffscreen) { continue }
                if ([string]$element.Current.ControlType.ProgrammaticName -ne "ControlType.Button") { continue }

                $name = [string]$element.Current.Name

                if (
                    $name -eq "Send prompt" -or
                    $name -eq "Send" -or
                    $name -match '^(?i)send message$'
                ) {
                    return $element
                }
            } catch {}
        }

        return $null
    }

    function Send-CurrentComposer([int]$seconds) {
        Report "AUTO_SEND_STAGE: WAIT_FOR_SEND_BUTTON"

        for ($i=0; $i -lt ($seconds * 4); $i++) {
            Start-Sleep -Milliseconds 250

            $chatNow = Get-ChatGPTWindow
            if (-not $chatNow) { continue }

            $send = Find-SendButton $chatNow.Root

            if (-not $send) {
                if (($i % 4) -eq 0) {
                    Report "AUTO_SEND_WAIT: send button not found yet"
                }
                continue
            }

            $enabled = $false
            try { $enabled = [bool]$send.Current.IsEnabled } catch {}

            Report "AUTO_SEND_BUTTON: $(Element-Info $send)"
            Report "AUTO_SEND_BUTTON_ENABLED: $enabled"

            if (-not $enabled) {
                continue
            }

            # Give ChatGPT a short quiet window after the attachment appears.
            Start-Sleep -Milliseconds 700

            # Re-fetch after the delay so we do not invoke a stale element.
            $chatNow = Get-ChatGPTWindow
            if (-not $chatNow) { continue }

            $send = Find-SendButton $chatNow.Root
            if (-not $send) { continue }

            try {
                $invoke = $null

                if ($send.TryGetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern,
                    [ref]$invoke
                )) {
                    ([System.Windows.Automation.InvokePattern]$invoke).Invoke()
                    Report "AUTO_SEND_METHOD: InvokePattern"
                    Start-Sleep -Milliseconds 900
                    return $true
                }
            } catch {
                Report "AUTO_SEND_INVOKE_ERROR: $($_.Exception.Message)"
            }

            try {
                $send.SetFocus()
                Start-Sleep -Milliseconds 120
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Report "AUTO_SEND_METHOD: FocusEnter"
                Start-Sleep -Milliseconds 900
                return $true
            } catch {
                Report "AUTO_SEND_ENTER_ERROR: $($_.Exception.Message)"
            }
        }

        return $false
    }

    Report "UPLOAD_SAFE_STAGE: FIND_CHATGPT"

    $chat = Get-ChatGPTWindow

    if (-not $chat) {
        Report "UPLOAD_RESULT: FAILED - ChatGPT Firefox window not found"
        exit 4
    }

    Report "UPLOAD_CHATGPT: FOUND"
    Report "UPLOAD_CHATGPT_URL: $($chat.Url)"

    $wshell = New-Object -ComObject WScript.Shell
    [void]$wshell.AppActivate($chat.Process.Id)
    Start-Sleep -Milliseconds 500

    $chat = Get-ChatGPTWindow
    $plus = Find-ByAutomationId $chat.Root "composer-plus-btn"

    if (-not $plus) {
        Report "UPLOAD_RESULT: FAILED - composer-plus-btn missing"
        exit 5
    }

    Report "UPLOAD_SAFE_STAGE: OPEN_PLUS"

    function Open-PlusMenu {
        $current = Get-ChatGPTWindow
        if (-not $current) { return $false }

        $p = Find-ByAutomationId $current.Root "composer-plus-btn"
        if (-not $p) { return $false }

        try {
            $p.SetFocus()
            Start-Sleep -Milliseconds 120
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Start-Sleep -Milliseconds 450
            return $true
        } catch {
            Report "UPLOAD_SAFE_PLUS_ERROR: $($_.Exception.Message)"
            return $false
        }
    }

    function Close-Menu {
        try {
            [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
            Start-Sleep -Milliseconds 250
        } catch {}
    }

    function Reopen-And-Find1148 {
        Close-Menu
        if (-not (Open-PlusMenu)) { return $null }

        $current = Get-ChatGPTWindow
        if (-not $current) { return $null }

        $items = Find-AllByAutomationId $current.Root "1148"
        Report "UPLOAD_SAFE_1148_COUNT: $($items.Count)"

        $n = 0
        foreach ($item in $items) {
            Report "UPLOAD_SAFE_1148_${n}: $(Element-Info $item)"
            Report "UPLOAD_SAFE_1148_${n}_PATTERNS: $(Supported-Pattern-Names $item)"
            $n++
        }

        # Test 41 put keyboard focus on an element with aid=1148 after Shift+Tab.
        # Prefer a visible 1148 element near the composer.
        foreach ($item in $items) {
            try {
                if (-not $item.Current.IsOffscreen) {
                    return $item
                }
            } catch {}
        }

        if ($items.Count -gt 0) { return $items[0] }
        return $null
    }

    $dialog = $null

    # SAFE MODE:
    # Never paste a path unless keyboard focus is PROVEN to be inside
    # Window "File Upload" class #32770.
    #
    # This prevents paths from ever being typed into the ChatGPT composer.

    if (Open-PlusMenu) {
        Report "UPLOAD_SAFE_SEQUENCE: OPEN_PLUS -> SHIFT_TAB"
        [System.Windows.Forms.SendKeys]::SendWait("+{TAB}")
        Start-Sleep -Milliseconds 180
        Report-Focus "SAFE_AFTER_SHIFT_TAB"
        Diagnostic-Upload-FocusChain "AFTER_SHIFT_TAB"

        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement

        if ($focused) {
            Report "UPLOAD_SAFE_FOCUSED: $(Element-Info $focused)"
            Parent-Info $focused 6
            $dialog = Get-AncestorFileDialog $focused
        }
    }

    if (-not $dialog) {
        Report "UPLOAD_RESULT: FAILED - focus was NOT inside confirmed File Upload dialog"
        Report "UPLOAD_SAFE_ABORT: no paste attempted"
        Log "APP_UPLOAD_SAFE_ABORT|no confirmed file dialog"
        exit 10
    }

    Report "UPLOAD_SAFE_FILE_DIALOG: CONFIRMED"
    Report "UPLOAD_DIALOG_TITLE: $($dialog.Current.Name)"
    Report "UPLOAD_DIALOG_CLASS: $($dialog.Current.ClassName)"
    Report "UPLOAD_DIALOG_PID: $($dialog.Current.ProcessId)"

    # Re-check the focused element immediately before any paste.
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    $confirmed = Get-AncestorFileDialog $focused

    if (-not $confirmed) {
        Report "UPLOAD_RESULT: FAILED - focus left File Upload dialog before paste"
        Report "UPLOAD_SAFE_ABORT: no paste attempted"
        Log "APP_UPLOAD_SAFE_ABORT|focus left dialog"
        exit 11
    }

    try {
        [System.Windows.Forms.Clipboard]::SetText($VideoPath)
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep -Milliseconds 80
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Milliseconds 220
        Report "UPLOAD_SAFE_FILL: CtrlA_Paste"
        Report-Focus "SAFE_AFTER_PASTE"
        Diagnostic-Upload-FocusChain "AFTER_PASTE"
    } catch {
        Report "UPLOAD_RESULT: FAILED - paste into confirmed File Upload field failed"
        Report "UPLOAD_SAFE_PASTE_ERROR: $($_.Exception.Message)"
        exit 12
    }

    # Re-confirm we are still in File Upload before Enter.
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    $confirmed = Get-AncestorFileDialog $focused

    if (-not $confirmed) {
        Report "UPLOAD_RESULT: FAILED - focus left File Upload dialog after paste"
        Log "APP_UPLOAD_SAFE_ABORT|focus left after paste"
        exit 13
    }

    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Report "UPLOAD_SAFE_SUBMIT: Enter"

    if (-not (Wait-FileDialogAnywhereClosed 3500)) {
        Report "UPLOAD_RESULT: FAILED - confirmed File Upload dialog stayed open"
        Log "APP_UPLOAD_SAFE_FAILED|dialog stayed open"
        exit 14
    }

    Report "UPLOAD_SUBMITTED: $VideoPath"
    Log "APP_UPLOAD_SAFE_SUBMITTED|$VideoPath"

    Start-Sleep -Seconds 1
    [void]$wshell.AppActivate($chat.Process.Id)

    Report "UPLOAD_SAFE_STAGE: VERIFY_CHATGPT"

    if (Verify-Attachment $BaseName 12) {
        Report "UPLOAD_VERIFIED: $BaseName"
        Log "APP_UPLOAD_SAFE_VERIFIED|$VideoPath"

        Report "AUTO_SEND_STAGE: ATTACHMENT_VERIFIED"

        if (Send-CurrentComposer 12) {
            Report "AUTO_SEND_RESULT: SUCCESS"
            Report "UPLOAD_RESULT: SUCCESS - ATTACHED AND SENT"
            Log "APP_UPLOAD_AUTO_SENT|$VideoPath"
            exit 0
        }

        # Safe failure: attachment stays in composer for manual Send.
        Report "AUTO_SEND_RESULT: FAILED - attachment left in composer"
        Report "UPLOAD_RESULT: SUCCESS - ATTACHED BUT NOT SENT"
        Log "APP_UPLOAD_AUTO_SEND_FAILED|$VideoPath"
        exit 0
    }

    # Do NOT auto-send if the attachment could not be verified.
    # This avoids accidentally sending an empty composer or unrelated content.
    Report "AUTO_SEND_RESULT: SKIPPED - attachment was not verified"
    Report "UPLOAD_RESULT: SUBMITTED_UNVERIFIED"
    Log "APP_UPLOAD_SAFE_SUBMITTED_UNVERIFIED|$VideoPath"
    exit 0

} catch {
    Report "UPLOAD_RESULT: CRASH"
    Report "UPLOAD_EXCEPTION_TYPE: $($_.Exception.GetType().FullName)"
    Report "UPLOAD_EXCEPTION_MESSAGE: $($_.Exception.Message)"
    Report "UPLOAD_EXCEPTION_LINE: $($_.InvocationInfo.ScriptLineNumber)"
    Report "UPLOAD_EXCEPTION_TEXT: $($_.InvocationInfo.Line)"
    Log "APP_UPLOAD_SAFE_CRASH|$($_.Exception.Message)"
    exit 99
}
