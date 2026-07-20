# Builds the widget provider and registers it as a loose (unpackaged-layout)
# MSIX package. Requires developer mode.
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$project = Join-Path $repoRoot 'src\CostWidgetProvider\CostWidgetProvider.csproj'
$outDir = Join-Path $repoRoot 'build\package'

& (Join-Path $PSScriptRoot 'fetch-ccusage.ps1')

Write-Host '=== dotnet publish ===' -ForegroundColor Cyan
Push-Location $repoRoot
try {
    mise exec -- dotnet publish $project -c Release -o $outDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$manifest = Join-Path $outDir 'AppxManifest.xml'
# Publish uses PreserveNewest; overwrite with the source manifest in case a
# previous pack.ps1 run left a stamped (unsigned-namespace) copy behind.
Copy-Item (Join-Path $repoRoot 'src\CostWidgetProvider\AppxManifest.xml') $manifest -Force

Write-Host '=== Add-AppxPackage -Register ===' -ForegroundColor Cyan
try {
    Add-AppxPackage -Register $manifest -ForceUpdateFromAnyVersion -ForceApplicationShutdown -ErrorAction Stop
}
catch {
    # Re-registering the same version with a modified manifest fails (0x80073CFB);
    # remove and register again. Pinned widgets must then be re-added.
    Write-Host 'Registration blocked; removing the package and registering again...' -ForegroundColor Yellow
    Get-AppxPackage -Name CostWidget | Remove-AppxPackage -Confirm:$false
    Add-AppxPackage -Register $manifest -ErrorAction Stop
}

$pkg = Get-AppxPackage -Name CostWidget
if ($pkg) {
    Write-Host "Registered: $($pkg.PackageFullName)" -ForegroundColor Green
    Write-Host 'Open the Widgets Board (Win+W) and add "Token Cost Widget" from the widget picker.'
}
else {
    throw 'Registration failed (package not found).'
}
