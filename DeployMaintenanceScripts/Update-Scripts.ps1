<#
.SYNOPSIS
    Script for updating SQL Server maintenance scripts

.EXAMPLE
    .\Update-Scripts.ps1

#>

$Config = Get-Content .\Config.json | ConvertFrom-Json 

$ScriptSourceDirectoryBase = $Config.ScriptSourceDirectoryBase
$ScriptDirectoryBase = $Config.ScriptDirectoryBase

$ScriptsDirectory = $ScriptDirectoryBase + "\\scripts\\"

$Source = $ScriptSourceDirectoryBase + "DarlingData\\Install-All\\DarlingData.sql"
Copy-Item $Source -Destination $ScriptsDirectory
$Source = $ScriptSourceDirectoryBase + "SQL-Server-First-Responder-Kit\\Install-All-Scripts.sql"
#Copy-Item $Source -Destination $ScriptsDirectory

$ScriptsDirectory = $ScriptDirectoryBase + "\\scripts_common\\"

$Source = $ScriptSourceDirectoryBase + "sp_CheckBackup\\sp_CheckBackup.sql"
Copy-Item $Source -Destination $ScriptsDirectory
$Source = $ScriptSourceDirectoryBase + "sp_CheckSecurity\\sp_CheckSecurity.sql"
Copy-Item $Source -Destination $ScriptsDirectory
$Source = $ScriptSourceDirectoryBase + "sp_CheckTempdb\\sp_CheckTempdb.sql"
Copy-Item $Source -Destination $ScriptsDirectory
$Source = $ScriptSourceDirectoryBase + "sp_whoisactive\\sp_WhoIsActive.sql"
Copy-Item $Source -Destination $ScriptsDirectory
$Source = $ScriptSourceDirectoryBase + "sql-server-maintenance-solution\\MaintenanceSolution.sql"
Copy-Item $Source -Destination $ScriptsDirectory
