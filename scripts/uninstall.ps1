# Unregisters the widget package.
$ErrorActionPreference = 'Stop'

$pkg = Get-AppxPackage -Name CostWidget
if ($pkg) {
    Remove-AppxPackage -Package $pkg.PackageFullName -Confirm:$false
    Write-Host "Removed: $($pkg.PackageFullName)" -ForegroundColor Green
}
else {
    Write-Host 'CostWidget is not registered.'
}
