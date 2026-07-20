# Builds an unsigned, Store-ready .msix for Microsoft Store submission.
# The Store re-signs the package after certification, so nothing is signed here.
# The reserved Store package identity is injected at build time (params or the
# STORE_* environment variables) so it stays out of the committed manifest.
param(
    # App version (semver, e.g. 1.2.3; a trailing .0 is added for the package
    # identity). Defaults to the AppxManifest Identity version.
    [string]$Version,
    # Store package identity (from Partner Center > Product identity).
    [string]$IdentityName = $env:STORE_IDENTITY_NAME,
    [string]$IdentityPublisher = $env:STORE_IDENTITY_PUBLISHER,
    [string]$PublisherDisplayName = $env:STORE_PUBLISHER_DISPLAY_NAME
)
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$project = Join-Path $repoRoot 'src\CostWidgetProvider\CostWidgetProvider.csproj'
$srcManifest = Join-Path $repoRoot 'src\CostWidgetProvider\AppxManifest.xml'
$outDir = Join-Path $repoRoot 'build\package'

if (-not $Version) {
    $Version = ([xml](Get-Content $srcManifest -Raw)).Package.Identity.Version
}
$v = [version]$Version
if ($v.Build -lt 0) { throw "Version must have at least three parts, e.g. 1.2.3 (got '$Version')" }
if ($v.Revision -lt 0) { $Version = "$Version.0" }
$ccusageVersion = (Get-Content (Join-Path $repoRoot 'ccusage.version') -Raw).Trim()

$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
if (-not $makeappx) {
    throw 'makeappx.exe not found. Install the Windows SDK: winget install --id Microsoft.WindowsSDK.10.0.26100'
}

& (Join-Path $PSScriptRoot 'fetch-ccusage.ps1') -Version $ccusageVersion

Write-Host '=== dotnet publish ===' -ForegroundColor Cyan
$dotnetArgs = @('publish', $project, '-c', 'Release', '-o', $outDir)
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise exec -- dotnet @dotnetArgs
}
else {
    dotnet @dotnetArgs
}
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }

# Stamp version and, for Store builds, the reserved package identity. Copy fresh
# from source first: publish uses PreserveNewest and would otherwise keep a
# previously stamped manifest.
$outManifest = Join-Path $outDir 'AppxManifest.xml'
Copy-Item $srcManifest $outManifest -Force
$xml = [xml](Get-Content $outManifest -Raw)
$xml.Package.Identity.Version = $Version
if ($IdentityName) { $xml.Package.Identity.Name = $IdentityName }
if ($IdentityPublisher) { $xml.Package.Identity.Publisher = $IdentityPublisher }
if ($PublisherDisplayName) { $xml.Package.Properties.PublisherDisplayName = $PublisherDisplayName }
$xml.Save($outManifest)

if (-not $IdentityName) {
    Write-Host 'WARNING: no Store identity provided; the package uses the dev identity and cannot be submitted to the Store.' -ForegroundColor Yellow
}

Write-Host '=== makeappx pack ===' -ForegroundColor Cyan
$msix = Join-Path $repoRoot "build\TokenCostWidget_$Version.msix"
& $makeappx.FullName pack /d $outDir /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx failed ($LASTEXITCODE)" }

Write-Host "Packed (unsigned, Store-ready): $msix (bundles ccusage $ccusageVersion)" -ForegroundColor Green
