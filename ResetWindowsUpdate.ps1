# =====================================================================
# FULL WINDOWS UPDATE RESET
# Run as Administrator
# =====================================================================

Write-Host "Stopping Windows Update services..." -ForegroundColor Yellow

$services = @(
    "wuauserv",    # Windows Update
    "bits",        # Background Intelligent Transfer Service
    "cryptsvc",    # Cryptographic Services
    "msiserver"    # Windows Installer
)

foreach ($service in $services) {
    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 5

Write-Host "Removing update cache..." -ForegroundColor Yellow

# Rename SoftwareDistribution
if (Test-Path "$env:SystemRoot\SoftwareDistribution") {
    Rename-Item `
        "$env:SystemRoot\SoftwareDistribution" `
        "SoftwareDistribution.old.$(Get-Date -Format yyyyMMddHHmmss)" `
        -ErrorAction SilentlyContinue
}

# Rename Catroot2
if (Test-Path "$env:SystemRoot\System32\catroot2") {
    Rename-Item `
        "$env:SystemRoot\System32\catroot2" `
        "catroot2.old.$(Get-Date -Format yyyyMMddHHmmss)" `
        -ErrorAction SilentlyContinue
}

Write-Host "Deleting BITS queue files..." -ForegroundColor Yellow

Remove-Item `
    "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\qmgr*.dat" `
    -Force `
    -ErrorAction SilentlyContinue

Write-Host "Resetting Winsock..." -ForegroundColor Yellow
netsh winsock reset | Out-Null

Write-Host "Resetting WinHTTP proxy..." -ForegroundColor Yellow
netsh winhttp reset proxy | Out-Null

Write-Host "Flushing DNS cache..." -ForegroundColor Yellow
ipconfig /flushdns | Out-Null

Write-Host "Starting services..." -ForegroundColor Yellow

foreach ($service in $services) {
    Start-Service -Name $service -ErrorAction SilentlyContinue
}

Write-Host "Running DISM repair..." -ForegroundColor Yellow
DISM /Online /Cleanup-Image /RestoreHealth

Write-Host "Running SFC scan..." -ForegroundColor Yellow
sfc /scannow

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Windows Update reset completed." -ForegroundColor Green
Write-Host "REBOOT THE COMPUTER BEFORE CHECKING FOR UPDATES." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green