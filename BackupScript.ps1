$WINDOWS_USERNAME = $env:UserName

$BACKUP_FILENAME = "BackupScript.ps1"
$FOLDER_FROM = -join("C:\Users\", $WINDOWS_USERNAME, "\Google Drive\Documenti\")
$FOLDER_TO = -join("C:\Users\", $WINDOWS_USERNAME, "\OneDrive\")

$COPY_ITEM_PATH = -join($FOLDER_FROM, $BACKUP_FILENAME)
$COPY_ITEM_DESTINATION = -join($FOLDER_TO, "$(Get-Date -f yyyy-MM-dd-hh-mm-ss).", $BACKUP_FILENAME)
Copy-Item -Path $COPY_ITEM_PATH -Destination $COPY_ITEM_DESTINATION
