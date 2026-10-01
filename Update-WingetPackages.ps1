#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DoUpdate
)

$ErrorActionPreference = 'Stop'

function Get-WingetUpgradeablePackages {

    Write-Host "Checking for available upgrades..." -ForegroundColor Cyan

    $json = winget upgrade --output json 2>$null

    if ([string]::IsNullOrWhiteSpace($json)) {
        return @()
    }

    try {
        $data = $json | ConvertFrom-Json

        if ($data.Data) {
            return $data.Data
        }

        return $data
    }
    catch {
        throw "Unable to parse winget output. Ensure Winget is updated."
    }
}

try {

    $packages = Get-WingetUpgradeablePackages

    if (-not $packages -or $packages.Count -eq 0) {
        Write-Host "All packages are already up to date." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Upgradeable packages:" -ForegroundColor Yellow

    $packages |
        Select-Object `
            PackageIdentifier,
            InstalledVersion,
            AvailableVersion |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Found $($packages.Count) package(s) with updates available." -ForegroundColor Yellow

    if (-not $DoUpdate) {

        Write-Host ""
        Write-Host "No updates executed." -ForegroundColor Cyan
        Write-Host "Run with -DoUpdate to install the available upgrades." -ForegroundColor Cyan

        return
    }

    Write-Host ""
    Write-Host "Starting upgrades..." -ForegroundColor Cyan

    foreach ($package in $packages) {

        $id = $package.PackageIdentifier

        if ($PSCmdlet.ShouldProcess($id, 'Upgrade package')) {

            Write-Host ""
            Write-Host "Upgrading $id..." -ForegroundColor Yellow

            winget upgrade `
                --id $id `
                --exact `
                --accept-package-agreements `
                --accept-source-agreements
        }
    }

    Write-Host ""
    Write-Host "Upgrade process completed." -ForegroundColor Green
}
catch {
    Write-Error $_
}