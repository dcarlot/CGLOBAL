$package=Get-AppxPackage -name "539ff419-48ba-45d9-b919-436958f37863"
if ($package) {
     Remove-AppxPackage -Package $package.PackageFullName -AllUsers
}
