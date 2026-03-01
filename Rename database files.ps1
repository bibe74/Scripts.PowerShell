$SQLServer = "METRADW"
$databaseName = "ImportMarco"
$prefixFrom = "ImportMarco"
$prefixTo = "testMarco"

$qcd = "SELECT file_id, name as [logical_file_name], physical_name
FROM sys.database_files;"
Write-Host "Situazione attuale:"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database $databaseName -Query $qcd

$qcd = "ALTER DATABASE $databaseName SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd

$qcd = "ALTER DATABASE $databaseName SET OFFLINE;"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd

Rename-Item -Path "D:\SQLDATA\MSSQL11.MSSQLSERVER\MSSQL\DATA\${prefixFrom}.mdf" -NewName "${prefixTo}.mdf"
Rename-Item -Path "D:\SQLDATA\MSSQL11.MSSQLSERVER\MSSQL\DATA\${prefixFrom}_log.ldf" -NewName "${prefixTo}_log.ldf"

$qcd = "ALTER DATABASE $databaseName MODIFY FILE (Name='${prefixTo}', FILENAME='D:\SQLDATA\MSSQL11.MSSQLSERVER\MSSQL\DATA\${prefixTo}.mdf');"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd
$qcd = "ALTER DATABASE $databaseName MODIFY FILE (Name='${prefixTo}_log', FILENAME='D:\SQLDATA\MSSQL11.MSSQLSERVER\MSSQL\DATA\${prefixTo}_log.ldf');"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd

$qcd = "ALTER DATABASE $databaseName SET ONLINE;"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd
$qcd = "ALTER DATABASE $databaseName SET MULTI_USER;"
Invoke-Sqlcmd -ServerInstance $SQLServer -Database master -Query $qcd
