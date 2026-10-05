# Lock-Explorer.ps1
# REVERSE of Unlock-Explorer.ps1. Re-applies machine-wide registry blocks on File Explorer.
# Run as Administrator. Covers HKLM + all users + offline profiles + Default.
# Effect: all drives hidden/inaccessible, folder options / context menus / Run / Find /
# taskbar settings / Control Panel off, explorer.exe on DisallowRun list.

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

function Say($m) { Write-Host $m }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 0x03FFFFFF = all drives A-Z
$ALL_DRIVES = 67108863

$BlockValues = @{
    'NoDrives'          = $ALL_DRIVES
    'NoViewOnDrive'     = $ALL_DRIVES
    'NoFolderOptions'   = 1
    'NoViewContextMenu' = 1
    'NoTrayContextMenu' = 1
    'NoRun'             = 1
    'NoFind'            = 1
    'NoSetTaskbar'      = 1
    'NoSetFolders'      = 1
    'NoControlPanel'    = 1
    'NoClose'           = 1
    'NoLogoff'          = 1
    'DisallowRun'       = 1
}

function Set-ExplorerBlock($hivePath) {
    $key = "$hivePath\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
    foreach ($kv in $BlockValues.GetEnumerator()) {
        New-ItemProperty $key -Name $kv.Key -Value $kv.Value -PropertyType DWord -Force | Out-Null
    }
    # DisallowRun list: block the explorer binary itself
    $dr = "$key\DisallowRun"
    if (-not (Test-Path $dr)) { New-Item $dr -Force | Out-Null }
    New-ItemProperty $dr -Name '1' -Value 'explorer.exe' -PropertyType String -Force | Out-Null
    Say "  blocked $key"
}

Say "[1/3] Blocking HKLM (machine)..."
Set-ExplorerBlock 'HKLM:'

Say "[2/3] Blocking all loaded users (HKU)..."
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Global
Get-ChildItem 'HKU:\' | Where-Object { $_.PSChildName -match '^S-1-5-21|^S-1-5-18|^S-1-5-19|^S-1-5-20' -and $_.PSChildName -notlike '*_Classes' } | ForEach-Object {
    Set-ExplorerBlock ("HKU:\$($_.PSChildName)")
}

Say "[3/3] Blocking offline profiles + Default..."
$profiles = @()
if (Test-Path 'C:\Users\Default\NTUSER.DAT') { $profiles += 'C:\Users\Default\NTUSER.DAT|DEF' }
Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
    $dat = Join-Path $_.FullName 'NTUSER.DAT'
    if (Test-Path $dat) { $profiles += "$dat|OFF_$($_.Name)" }
}
foreach ($p in $profiles) {
    ($dat, $tag) = $p -split '\|'
    reg load "HKU\$tag" $dat 2>$null | Out-Null
    Set-ExplorerBlock ("HKU:\$tag")
    [gc]::Collect(); Start-Sleep -Milliseconds 300
    reg unload "HKU\$tag" 2>$null | Out-Null
    Say "  blocked offline $dat"
}

Say "Killing Explorer to enforce..."
Stop-Process -Name explorer -Force

Say ""
Say "DONE. Explorer is blocked machine-wide. Undo with Unlock-Explorer.ps1."
Say "NOTE: Winlogon Shell left as explorer.exe so logon still works (only the UI is locked)."
