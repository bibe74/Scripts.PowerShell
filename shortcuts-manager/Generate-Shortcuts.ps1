#Requires -Version 5.1
<#
.SYNOPSIS
    Generates Windows .lnk shortcuts for each customer/application pair defined
    in shortcuts-config.json, each launching the application via runas.exe with
    the customer's Windows credentials.

.PARAMETER ConfigFile
    Path to the JSON configuration file. Defaults to shortcuts-config.json in
    the same directory as this script.

.PARAMETER DryRun
    When specified, prints what would be done without creating any files or
    directories.

.EXAMPLE
    .\Generate-Shortcuts.ps1

.EXAMPLE
    .\Generate-Shortcuts.ps1 -ConfigFile "D:\myconfig.json" -DryRun
#>
[CmdletBinding()]
param(
    [string] $ConfigFile = (Join-Path $PSScriptRoot 'shortcuts-config.json'),
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK]   $Message" -ForegroundColor Green
}

# Builds the Arguments string for a runas.exe shortcut.
# runas expects: /user:DOMAIN\user "\"app.exe\" \"arg1\" \"arg2\""
function Build-RunasArguments {
    param(
        [string]   $Domain,
        [string]   $User,
        [string]   $AppPath,
        [string[]] $ExtraArgs
    )

    # Build the inner command line that runas hands to CreateProcess.
    # Quote every token that contains spaces.
    $tokens = @($AppPath) + $ExtraArgs | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }
    $innerCmd = $tokens -join ' '

    # Escape the inner quotes so they survive the outer runas quoting layer.
    $escapedInner = $innerCmd.Replace('"', '\"')

    return "/user:$Domain\$User `"$escapedInner`""
}

# Creates a .lnk shortcut file via the WScript.Shell COM object.
function New-Shortcut {
    param(
        [string] $ShortcutPath,   # full path including .lnk extension
        [string] $TargetPath,     # exe to launch
        [string] $Arguments,      # arguments string
        [string] $IconPath,       # exe to pull the icon from
        [string] $Description
    )

    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath       = $TargetPath
    $shortcut.Arguments        = $Arguments
    $shortcut.IconLocation     = "$IconPath,0"
    $shortcut.Description      = $Description
    $shortcut.WorkingDirectory = Split-Path $IconPath
    $shortcut.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host "`nShortcut Generator" -ForegroundColor White
Write-Host "Config : $ConfigFile"
if ($DryRun) { Write-Host "Mode   : DRY RUN (no files will be written)`n" -ForegroundColor Yellow }
else         { Write-Host "Mode   : LIVE`n" }

# --- Load and validate config -----------------------------------------------
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

if (-not $config.applications -or -not $config.customers) {
    Write-Error "Config file must have 'applications' and 'customers' sections."
}

# Expand {username} placeholder in all application paths
$username = if ($config.PSObject.Properties['username']) { $config.username } else { $env:USERNAME }
foreach ($appKey in ($config.applications.PSObject.Properties.Name)) {
    $app = $config.applications.$appKey
    $app.path = $app.path -replace '\{username\}', $username
}

$runas = "$env:SystemRoot\System32\runas.exe"
$totalCreated = 0
$totalSkipped = 0

# --- Process each customer --------------------------------------------------
foreach ($customer in $config.customers) {

    Write-Host "Customer: $($customer.name)  ($($customer.domain)\$($customer.user))" -ForegroundColor Magenta

    # Validate required fields
    if (-not $customer.name -or -not $customer.shortcutsDir -or
        -not $customer.domain -or -not $customer.user) {
        Write-Warn "Skipping customer – missing required field (name/shortcutsDir/domain/user)."
        continue
    }

    # Ensure the output directory exists
    if (-not (Test-Path $customer.shortcutsDir)) {
        if ($DryRun) {
            Write-Step "Would create directory: $($customer.shortcutsDir)"
        } else {
            Write-Step "Creating directory: $($customer.shortcutsDir)"
            New-Item -ItemType Directory -Path $customer.shortcutsDir -Force | Out-Null
        }
    }

    foreach ($entry in $customer.applications) {

        # Resolve the application definition from the global section
        $appKey = $entry.app
        $appDef = $config.applications.$appKey

        if (-not $appDef) {
            Write-Warn "Unknown application key '$appKey' – skipping."
            $totalSkipped++
            continue
        }

        $appPath = $appDef.path

        # Warn if the application executable is not found on this machine
        if (-not (Test-Path $appPath)) {
            Write-Warn "Executable not found: $appPath  (shortcut will still be created)"
        }

        # Determine the shortcut label
        $label        = if ($entry.PSObject.Properties['label'])     { $entry.label }      else { "$($appDef.label) – $($customer.name)" }
        $extraArgs    = if ($entry.PSObject.Properties['extraArgs']) { @($entry.extraArgs) } else { @() }
        $shortcutFile = Join-Path $customer.shortcutsDir "$label.lnk"

        $runasArgs = Build-RunasArguments `
            -Domain    $customer.domain `
            -User      $customer.user `
            -AppPath   $appPath `
            -ExtraArgs $extraArgs

        if ($DryRun) {
            Write-Step "Would create: $shortcutFile"
            Write-Step "  Target : $runas"
            Write-Step "  Args   : $runasArgs"
        } else {
            New-Shortcut `
                -ShortcutPath $shortcutFile `
                -TargetPath   $runas `
                -Arguments    $runasArgs `
                -IconPath     $appPath `
                -Description  "Run $($appDef.label) as $($customer.domain)\$($customer.user)"

            Write-Ok "Created: $shortcutFile"
            $totalCreated++
        }
    }

    Write-Host ""
}

# --- Summary ----------------------------------------------------------------
if ($DryRun) {
    Write-Host "Dry run complete. No files were written." -ForegroundColor Yellow
} else {
    Write-Host "Done. Shortcuts created: $totalCreated  |  Skipped: $totalSkipped" -ForegroundColor Green
}
