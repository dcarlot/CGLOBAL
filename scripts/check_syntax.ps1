$path = 'c:\Users\dcarlot\OneDrive - ORG-INFOR\USB_CGLOBAL\usb-root\_CGLOBAL\PS1\16_TeamViewerQS.ps1'
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput((Get-Content $path -Raw), [ref]$null, [ref]$errors)
if ($errors) {
    $errors | ForEach-Object { Write-Host $_.Message }
    exit 1
} else {
    Write-Host 'NoSyntaxErrors'
    exit 0
}