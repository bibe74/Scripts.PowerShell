<#
.SYNOPSIS
    Script for deploying SQL Server maintenance scripts across environments

.EXAMPLE
    .\Deploy-MaintenanceScripts.ps1 -ServerGroup local

#>

[CmdletBinding()] #See http://technet.microsoft.com/en-us/library/hh847884(v=wps.620).aspx for CmdletBinding common parameters
param(
    [parameter(Mandatory = $false)]
    [string]$ServerGroup
)

$Config = Get-Content .\Config.json | ConvertFrom-Json 

$ScriptDirectoryBase = $Config.ScriptDirectoryBase
$ScriptDirectory_common = $ScriptDirectoryBase + "scripts_common\\"
If(-not (Test-Path $ScriptDirectory_common)){
    Write-Error "$ScriptDirectory_common cannot be accessed!" -ErrorAction Stop
}
$common_scripts = Get-ChildItem $ScriptDirectory_common | Where-Object {$_.Extension -eq ".sql"}
$common_scripts_count = (Get-ChildItem $ScriptDirectory_common | Measure-Object).Count
$str_common_script = if($common_scripts_count -eq 1) {'script'} else {'scripts'}

$Servers = $Config.servers | Where-Object {$_.group -eq $ServerGroup}

foreach ($server in $Servers) {
    Write-Host "Deploying to" $server.name

    foreach ($script in $common_scripts) {
        Write-Host "Deploying" $script.Name
        #Invoke-Sqlcmd -ServerInstance $server.Name -TrustServerCertificate -InputFile $script.FullName -DisableVariables
        Invoke-Sqlcmd -ServerInstance $server.Name -Encrypt Optional -InputFile $script.FullName -DisableVariables
    }

    switch($server.sql_version)
    {
        "2008" {$scripts_folder = "scripts_up_to_2008\\"}
        "2008R2" {$scripts_folder = "scripts_up_to_2008\\"}
        "2012" {$scripts_folder = "scripts_up_to_2014\\"}
        "2014" {$scripts_folder = "scripts_up_to_2014\\"}
        default {$scripts_folder = "scripts\\"}
    }

    $ScriptDirectory = $ScriptDirectoryBase + $scripts_folder

    If(Test-Path $ScriptDirectory){
        $scripts = Get-ChildItem $ScriptDirectory | Where-Object {$_.Extension -eq ".sql"}
        $scripts_count = (Get-ChildItem $ScriptDirectory | Measure-Object).Count
        $str_script = if($scripts_count -eq 1) {'script'} else {'scripts'}
        foreach ($script in $scripts) {
            Write-Host "Deploying" $script.Name
            #Invoke-Sqlcmd -ServerInstance $server.Name -TrustServerCertificate -InputFile $script.FullName -DisableVariables
            Invoke-Sqlcmd -ServerInstance $server.Name -Encrypt Optional -InputFile $script.FullName -DisableVariables
        }
    }
}
