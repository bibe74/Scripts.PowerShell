$reportsLocalPath = ".\Excel_Reports"

$ssrsServer = "http://localhost/ReportServer";
$folder = "/Test02" # MUST exist!

# echo $reportsLocalPath

$ssrsMgmtProxy = New-WebServiceProxy $ssrsServer'/ReportService2010.asmx?WSDL' `
	-UseDefaultCredential;

function Deploy-Folder {
    Param (
        [string]$reportsLocalPath,
        [string]$reportsRemoteFolder
    )
    Process {
        foreach ($report in Get-ChildItem -Path $reportsLocalPath -File -Filter "*.xlsx") {

            Try {
                # This is needed for the ref clause in the method
                $warnings = $null
 
                #$report = Get-ChildItem $fileSource;

                $reportName = [System.IO.Path]::GetFileNameWithoutExtension($report.Name)
                $bytes = [System.IO.File]::ReadAllBytes($report.FullName)
 
                $type = $ssrsMgmtProxy.GetType().Namespace
                $datatype = ($type + '.Property')              
                $mimeTypeProperty =New-Object ($datatype);
                $mimeTypeProperty.Name = "MimeType"
                #$mimeTypeProperty.Value = “application/vnd.ms-excel”
                $mimeTypeProperty.Value = “application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

                $contentTypeProperty =New-Object ($datatype);
                $contentTypeProperty.Name = "Content-Type"
                $contentTypeProperty.Value = “application/vnd.ms-excel”
                #$contentTypeProperty.Value = “application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

                #Write-Output "Uploading report ""$reportName"" to ""$reportsRemoteFolder""..."

                $ssrsMgmtProxy.CreateCatalogItem(
                    "Resource",       # You specify what kind of object you are uploading
                    $report.Name,     # Name of the report
                    $reportsRemoteFolder,          # Folder 
                    $true,            # Overwrite flag
                    $bytes,           # Contents of the file
                    @($mimeTypeProperty,$contentTypeProperty),        # Properties
                    [ref]$warnings)   # Warnings

                $ssrsMgmtProxy.create
            }
            Catch
            {
                "Error was $_"
                $line = $_.InvocationInfo.ScriptLineNumber
                "Error was in Line $line"
            }

        }

        foreach ($subfolder in Get-ChildItem -Path $reportsLocalPath -Directory)
        {
            Try {
                $ssrsMgmtProxy.CreateFolder(
                    $subfolder,    # Folder to be created
                    $reportsRemoteFolder, # Folder into which the new folder is created
                    $null);        # Properties to set

                #Write-Host "Folder created!";
            }
            Catch
            {
                #"Error was $_"
                #$line = $_.InvocationInfo.ScriptLineNumber
                #"Error was in Line $line"
            }

            Deploy-Folder -reportsLocalPath $reportsLocalPath'\'$subFolder -reportsRemoteFolder $reportsRemoteFolder'/'$subFolder
        }
    }
}

Deploy-Folder -reportsLocalPath $reportsLocalPath -reportsRemoteFolder $folder
#EOF