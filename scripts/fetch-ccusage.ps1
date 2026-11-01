# Fetches the official ccusage native binary (@ccusage/ccusage-win32-x64) from
# the npm registry and places it under src/CostWidgetProvider/Tools so it gets
# bundled into the MSIX package.
param(
    # ccusage version to bundle. Defaults to the pin in ccusage.version.
    [string]$Version
)
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$toolsDir = Join-Path $repoRoot 'src\CostWidgetProvider\Tools'
$exePath = Join-Path $toolsDir 'ccusage.exe'

if (-not $Version) {
    $Version = (Get-Content (Join-Path $repoRoot 'ccusage.version') -Raw).Trim()
}

if (Test-Path $exePath) {
    $current = (& $exePath --version) -replace '[^\d.]', ''
    if ($current -eq $Version) {
        Write-Host "ccusage.exe $Version already present, skipping fetch."
        return
    }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "ccusage-fetch-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Force $work | Out-Null
try {
    Push-Location $work
    $url = "https://registry.npmjs.org/@ccusage/ccusage-win32-x64/-/ccusage-win32-x64-$Version.tgz"
    Write-Host "Downloading $url ..."
    Invoke-WebRequest -Uri $url -OutFile package.tgz
    tar -xzf package.tgz
    if ($LASTEXITCODE -ne 0) { throw "tar extract failed ($LASTEXITCODE)" }

    New-Item -ItemType Directory -Force $toolsDir | Out-Null
    Copy-Item .\package\bin\ccusage.exe $exePath -Force

    # The platform package used to ship LICENSE (up to 20.0.19) but no longer
    # does (from 20.0.20). Fall back to the LICENSE in the main `ccusage`
    # package of the same version, and fail loudly if neither has one so the
    # bundled package never ships without the license text.
    $licenseDest = Join-Path $toolsDir 'LICENSE-ccusage.txt'
    if (Test-Path .\package\LICENSE) {
        Copy-Item .\package\LICENSE $licenseDest -Force
    }
    else {
        $mainUrl = "https://registry.npmjs.org/ccusage/-/ccusage-$Version.tgz"
        Write-Host "LICENSE not in the platform package; downloading $mainUrl ..."
        New-Item -ItemType Directory -Force main | Out-Null
        Invoke-WebRequest -Uri $mainUrl -OutFile main.tgz
        tar -xzf main.tgz -C main
        if ($LASTEXITCODE -ne 0) { throw "tar extract failed ($LASTEXITCODE)" }
        if (-not (Test-Path .\main\package\LICENSE)) {
            throw "ccusage $Version: LICENSE not found in either @ccusage/ccusage-win32-x64 or ccusage package."
        }
        Copy-Item .\main\package\LICENSE $licenseDest -Force
    }
}
finally {
    Pop-Location
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

$fetched = & $exePath --version
Write-Host "Bundled: $fetched -> $exePath" -ForegroundColor Green
