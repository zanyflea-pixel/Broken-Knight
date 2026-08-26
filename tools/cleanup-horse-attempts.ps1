[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath('C:\Users\Jimmy\Desktop\Broken Knight')
$LogPath = Join-Path $ProjectRoot 'Powershell output\test.txt'
$Targets = [System.Collections.Generic.List[string]]::new()

function Add-CleanupTarget {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $ProjectRoot.TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing horse cleanup outside project: $resolved"
    }
    $Targets.Add($resolved)
}

$godotAnimals = Join-Path $ProjectRoot 'godot\assets\animals'
Get-ChildItem -LiteralPath $godotAnimals -Force |
    Where-Object { $_.Name -notin @('riverwatch_horse.glb', 'riverwatch_horse.glb.import') } |
    ForEach-Object { Add-CleanupTarget $_.FullName }

$blenderAnimals = Join-Path $ProjectRoot 'blender\world\animals'
Get-ChildItem -LiteralPath $blenderAnimals -Force |
    Where-Object { $_.Name -notin @('riverwatch_horse.blend', 'README.md', 'archive') } |
    ForEach-Object { Add-CleanupTarget $_.FullName }

foreach ($name in @(
    'build_riverwatch_stable_and_horse.py',
    'horse_v101_direct_edit.py',
    'riverwatch_horse_lab.py',
    'riverwatch_horse_tuning.py'
)) {
    Add-CleanupTarget (Join-Path $ProjectRoot "blender\world\scripts\$name")
}

Get-ChildItem -LiteralPath $ProjectRoot -Force |
    Where-Object { $_.Name -match '^horse.*\.(ps1|bat)$' } |
    ForEach-Object { Add-CleanupTarget $_.FullName }

$tempRoot = Join-Path $ProjectRoot 'tmp'
if (Test-Path -LiteralPath $tempRoot) {
    Get-ChildItem -LiteralPath $tempRoot -Force |
        Where-Object {
            $_.Name -match 'horse' -or
            $_.Name -in @('build_new_royal_horse.py', 'unify_new_royal_horse.py')
        } |
        ForEach-Object { Add-CleanupTarget $_.FullName }
}

$capturesRoot = Join-Path $ProjectRoot 'captures'
if (Test-Path -LiteralPath $capturesRoot) {
    Get-ChildItem -LiteralPath $capturesRoot -Force |
        Where-Object { $_.Name -match 'horse' -and $_.Name -ne 'horse-reference' } |
        ForEach-Object { Add-CleanupTarget $_.FullName }
}

Add-CleanupTarget (Join-Path $ProjectRoot 'godot\tools\horse_capture')

$importRoot = Join-Path $ProjectRoot 'godot\.godot\imported'
if (Test-Path -LiteralPath $importRoot) {
    Get-ChildItem -LiteralPath $importRoot -Force |
        Where-Object { $_.Name -like 'riverwatch_horse_*' } |
        ForEach-Object { Add-CleanupTarget $_.FullName }
}

$uniqueTargets = @($Targets | Sort-Object -Unique)
$totalBytes = 0L
foreach ($target in $uniqueTargets) {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.PSIsContainer) {
        $sum = Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($null -ne $sum.Sum) { $totalBytes += [long]$sum.Sum }
    }
    else {
        $totalBytes += [long]$item.Length
    }
}

$summary = 'HORSE_CLEANUP_VERIFIED|targets={0}|megabytes={1:N1}' -f $uniqueTargets.Count, ($totalBytes / 1MB)
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($LogPath)) -Force | Out-Null
Set-Content -LiteralPath $LogPath -Value $summary
Write-Output $summary

foreach ($target in $uniqueTargets) {
    if ($PSCmdlet.ShouldProcess($target, 'Remove obsolete horse attempt')) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

$complete = 'HORSE_CLEANUP_COMPLETE|removed={0}|kept=production+best_previous_v73' -f $uniqueTargets.Count
Add-Content -LiteralPath $LogPath -Value $complete
Write-Output $complete
