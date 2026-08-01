
Get-InstalledModule | ForEach-Object {
    $latest = Find-Module $_.Name -ErrorAction SilentlyContinue
    # if ($latest.Version -gt $_.Version) {
        [PSCustomObject]@{
            Name = $_.Name
            InstalledVersion = $_.Version
            AvailableVersion = $latest.Version
        }
    # }
}
