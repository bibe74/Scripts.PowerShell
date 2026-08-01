#Requires -Version 5.1
<#
.SYNOPSIS
    Stores customer credentials into Windows Credential Manager from
    credentials-config.json.

.DESCRIPTION
    Reads each entry from the credentials config file and saves it as a Generic
    credential in Windows Credential Manager using the built-in cmdkey.exe.

    After running this script, replace every password value in
    credentials-config.json with "CHANGEME" (or delete the file entirely) so
    plaintext passwords are not left on disk.

.PARAMETER ConfigFile
    Path to the credentials JSON file. Defaults to credentials-config.json in
    the same directory as this script.

.EXAMPLE
    .\Store-Credentials.ps1

.EXAMPLE
    .\Store-Credentials.ps1 -ConfigFile "D:\my-credentials.json"
#>
[CmdletBinding()]
param(
    [string] $ConfigFile = (Join-Path $PSScriptRoot 'credentials-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`nCredential Store" -ForegroundColor White
Write-Host "Config : $ConfigFile`n"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

if (-not $config.credentials) {
    Write-Error "Config file must have a 'credentials' array."
}

$stored  = 0
$skipped = 0

foreach ($cred in $config.credentials) {

    if (-not $cred.credentialName -or -not $cred.domain -or -not $cred.user) {
        Write-Host "  [WARN] Skipping entry – missing credentialName, domain, or user." -ForegroundColor Yellow
        $skipped++
        continue
    }

    if (-not $cred.password -or $cred.password -eq 'CHANGEME') {
        Write-Host "  [SKIP] $($cred.credentialName) – password is not set." -ForegroundColor Yellow
        $skipped++
        continue
    }

    # /generic: stores as CRED_TYPE_GENERIC so CredRead can retrieve it with type=1
    # Marshal the SecureString back to plaintext only for the cmdkey call, then discard
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $cred.password -AsPlainText -Force))
    $plain  = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $result = cmdkey /generic:$($cred.credentialName) /user:"$($cred.domain)\$($cred.user)" /pass:$plain
    $plain  = $null
    if ($LASTEXITCODE -ne 0) { Write-Error "cmdkey failed for $($cred.credentialName): $result" }

    Write-Host "  [OK]   $($cred.credentialName)  ($($cred.domain)\$($cred.user))" -ForegroundColor Green
    $stored++
}

Write-Host "`nDone. Stored: $stored  |  Skipped: $skipped" -ForegroundColor Green
Write-Host "IMPORTANT: Remove or blank the passwords in $ConfigFile`n" -ForegroundColor Yellow
