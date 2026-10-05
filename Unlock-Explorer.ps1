# Unlock-Explorer.ps1
# Removes machine-wide + per-user + domain-pushed registry blocks on File Explorer.
# Run as Administrator. Reversible with Lock-Explorer.ps1.
# NOTE: domain GPO will re-apply its blocks on next gpupdate/reboot unless the
# GPO is unlinked / filtered. This script clears what is currently on disk.

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

function Say($m) { Write-Host $m }

# --- 1. Self-elevate (no-op if already admin) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Relative key paths to wipe (Explorer lockdown lives here, local + domain GPO)
$ExplorerKeys = @(
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
    'SOFTWARE\Policies\Microsoft\Windows\Explorer'
)
# Values in the System policy key that are commonly paired with Explorer lockdown.
# (Only these values are removed; the rest of the key is left alone.)
$SystemValues = @('DisableTaskMgr','DisableRegistryTools','DisableCMD','DisableChangePassword','NoDispCPL','NoDispSettingsPage')

function Clear-ExplorerPolicies($hivePath) {
    foreach ($rel in $ExplorerKeys) {
        $full = "$hivePath\$rel"
        # Delete DisallowRun / RestrictRun subkeys first (blocked-exe lists)
        Remove-Item "$full\DisallowRun" -Recurse -Force
        Remove-Item "$full\RestrictRun" -Recurse -Force
        # Delete the whole policy key (empty = unlocked; Windows recreates as needed)
        if (Test-Path $full) {
            Remove-Item $full -Recurse -Force
            New-Item $full -Force | Out-Null
            Say "  cleared $full"
        }
    }
    # System key: surgical value removal only
    $sysKey = "$hivePath\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    foreach ($v in $SystemValues) {
        Remove-ItemProperty $sysKey -Name $v -Force
    }
    $sysKey2 = "$hivePath\SOFTWARE\Policies\Microsoft\Windows\System"
    foreach ($v in $SystemValues) {
        Remove-ItemProperty $sysKey2 -Name $v -Force
    }
}

Say "[1/4] Clearing HKLM (machine + domain machine policies)..."
Clear-ExplorerPolicies 'HKLM:'

Say "[2/4] Clearing all loaded user hives (HKU, covers current user + domain user policies)..."
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Global
Get-ChildItem 'HKU:\' | Where-Object { $_.PSChildName -match '^S-1-5-21|^S-1-5-18|^S-1-5-19|^S-1-5-20' -and $_.PSChildName -notlike '*_Classes' } | ForEach-Object {
    Clear-ExplorerPolicies ("HKU:\$($_.PSChildName)")
    Say "  cleared user $($_.PSChildName)"
}

Say "[3/4] Clearing offline profiles (C:\Users\*) + Default (future users)..."
$profiles = @()
if (Test-Path 'C:\Users\Default\NTUSER.DAT') { $profiles += 'C:\Users\Default\NTUSER.DAT|DEF' }
Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
    $dat = Join-Path $_.FullName 'NTUSER.DAT'
    if (Test-Path $dat) { $profiles += "$dat|OFF_$($_.Name)" }
}
foreach ($p in $profiles) {
    ($dat, $tag) = $p -split '\|'
    $mount = "HKU\$tag"
    reg load $mount $dat 2>$null | Out-Null
    Clear-ExplorerPolicies ("HKU:\$tag")
    [gc]::Collect(); Start-Sleep -Milliseconds 300
    reg unload $mount 2>$null | Out-Null
    Say "  cleared offline $dat"
}

Say "[4/4] Fixing shell + execution blocks (machine)..."
# Normal logon shell
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'Shell' -Value 'explorer.exe' -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'Userinit' -Value 'C:\Windows\system32\userinit.exe,' -Force
# IFEO debugger hijack on explorer.exe (classic block trick)
Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\explorer.exe' -Recurse -Force
# Explorer always allowed in DisallowRun list if key survived
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'DisallowRun' -Force

Say "Restarting Explorer..."
Stop-Process -Name explorer -Force
Start-Sleep 2
Start-Process explorer.exe

Say ""
Say "DONE. Explorer policy blocks cleared machine-wide."
Say "WARNING: domain GPO re-applies on gpupdate/reboot. If blocks come back, unlink/filter the GPO in Group Policy Management or run: gpupdate /force (to test)."
