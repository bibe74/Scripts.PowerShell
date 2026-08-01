#Requires -Version 5.1
<#
.SYNOPSIS
    Generates Windows .lnk shortcuts for each customer/application pair defined
    in shortcuts-config.json. Each shortcut launches a per-shortcut PowerShell
    script that retrieves credentials from Windows Credential Manager and starts
    the application via Start-Process -Credential.

.DESCRIPTION
    Credentials must be pre-stored in Windows Credential Manager by running
    Store-Credentials.ps1. Each customer entry in shortcuts-config.json
    references a credential by its Credential Manager target name
    (credentialName field).

    For each shortcut a companion launcher .ps1 is written to a _launchers
    sub-folder inside the customer's shortcutsDir. The .lnk calls powershell.exe
    to invoke that launcher invisibly.

    Requires the CredentialManager PowerShell module at runtime (installed
    automatically by Store-Credentials.ps1, or manually via
    Install-Module CredentialManager -Scope CurrentUser).

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

# Writes a self-contained PowerShell launcher script for a single shortcut.
function Write-LauncherScript {
    param(
        [string]   $ScriptPath,
        [string]   $CredentialName,
        [string]   $AppPath,
        [string[]] $ExtraArgs
    )

    # Serialize ExtraArgs as a PowerShell array literal
    $ExtraArgs = @($ExtraArgs)   # normalise: null or scalar → array
    $argsLiteral = if ($ExtraArgs.Count -eq 0) {
        '@()'
    } else {
        $quoted = $ExtraArgs | ForEach-Object { "'$($_ -replace "'", "''")'" }
        '@(' + ($quoted -join ', ') + ')'
    }

    $escapedCred = $CredentialName -replace "'", "''"
    $escapedApp  = $AppPath        -replace "'", "''"

    $content = @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
try {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class CredMan {
    [StructLayout(LayoutKind.Sequential)] private struct CRED {
        public uint Flags, Type; public IntPtr TargetName, Comment;
        public long LastWritten; public uint BlobSize; public IntPtr Blob;
        public uint Persist, AttrCount; public IntPtr Attrs, Alias, UserName;
    }
    [DllImport("advapi32",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern bool CredReadW(string t,uint type,uint f,out IntPtr p);
    [DllImport("advapi32")] static extern void CredFree(IntPtr p);
    public static string[] Get(string target) {
        IntPtr p; if (!CredReadW(target,1,0,out p)) return null;
        try { var c=(CRED)Marshal.PtrToStructure(p,typeof(CRED));
              return new[]{Marshal.PtrToStringUni(c.UserName),
                           Marshal.PtrToStringUni(c.Blob,(int)(c.BlobSize/2))};
        } finally { CredFree(p); }
    }
}
'@ -ErrorAction SilentlyContinue
    `$data = [CredMan]::Get('$escapedCred')
    if (-not `$data) { throw "Credential '$CredentialName' not found in Windows Credential Manager. Run Store-Credentials.ps1 first." }
    `$cred = New-Object PSCredential(`$data[0], (ConvertTo-SecureString `$data[1] -AsPlainText -Force))
    Start-Process -FilePath '$escapedApp' -ArgumentList $argsLiteral -Credential `$cred
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(`$_.Exception.Message, 'Shortcuts Manager', 'OK', 'Error') | Out-Null
}
"@
    Set-Content -Path $ScriptPath -Value $content -Encoding UTF8
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
    $shortcut.WorkingDirectory = Split-Path $TargetPath
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

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$totalCreated = 0
$totalSkipped = 0

# --- Process each customer --------------------------------------------------
foreach ($customer in $config.customers) {

    Write-Host "Customer: $($customer.name)" -ForegroundColor Magenta

    # Validate required fields
    if (-not $customer.name -or -not $customer.shortcutsDir -or
        -not $customer.PSObject.Properties['credentialName'] -or -not $customer.credentialName) {
        Write-Warn "Skipping customer – missing required field (name/shortcutsDir/credentialName)."
        continue
    }

    $launchersDir = Join-Path $customer.shortcutsDir '_launchers'

    # Ensure the output directories exist
    foreach ($dir in @($customer.shortcutsDir, $launchersDir)) {
        if (-not (Test-Path $dir)) {
            if ($DryRun) {
                Write-Step "Would create directory: $dir"
            } else {
                Write-Step "Creating directory: $dir"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
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

        $label        = if ($entry.PSObject.Properties['label'])     { $entry.label }      else { "$($appDef.label) – $($customer.name)" }
        $extraArgs    = if ($entry.PSObject.Properties['extraArgs']) { @($entry.extraArgs) } else { @() }
        $launcherFile = Join-Path $launchersDir "$label.ps1"
        $shortcutFile = Join-Path $customer.shortcutsDir "$label.lnk"
        $psArgs       = "-NonInteractive -WindowStyle Hidden -File `"$launcherFile`""

        if ($DryRun) {
            Write-Step "Would create launcher: $launcherFile"
            Write-Step "Would create shortcut: $shortcutFile"
            Write-Step "  Credential : $($customer.credentialName)"
            Write-Step "  App        : $appPath"
            if ($extraArgs.Count -gt 0) { Write-Step "  ExtraArgs  : $($extraArgs -join ' ')" }
        } else {
            Write-LauncherScript `
                -ScriptPath     $launcherFile `
                -CredentialName $customer.credentialName `
                -AppPath        $appPath `
                -ExtraArgs      $extraArgs

            New-Shortcut `
                -ShortcutPath $shortcutFile `
                -TargetPath   $powershell `
                -Arguments    $psArgs `
                -IconPath     $appPath `
                -Description  "Run $($appDef.label) as $($customer.credentialName)"

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
