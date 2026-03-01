# $DebugPreference="SilentlyContinue"
# $DebugPreference="Continue"
$i = $args[0]
$j = $args[1]
Write-Debug("First Param:$i")
Write-Debug("SecondParam:$j")
if ($i -eq $null ) {   $i = 1
  Write-Debug("Setting first as a default to 1")
}
if ($j -eq $null ) {   $j = 1
  Write-Debug("Setting second as a default to 1")
}
if ($a -gt $b) {   Write-Output("The first parameter is larger")
}
elseif ($i -eq $j ) {   Write-Output("The parameters are equal.")
}
else {       Write-Output("The second parameter is larger")   }