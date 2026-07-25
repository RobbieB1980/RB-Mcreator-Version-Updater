<#
.SYNOPSIS
  Build portable package + Windows installer for RB MCreator Version Updater.

.DESCRIPTION
  Produces:
    dist/portable/RB-Mcreator-Version-Updater/   - fully portable folder
    dist/RB-Mcreator-Version-Updater-Portable.zip
    dist/portable-payload.zip                    - payload for Setup.exe
    dist/RB-Mcreator-Version-Updater-Setup.exe   - GUI installer (self-contained)

.EXAMPLE
  .\scripts\Build-Release.ps1
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'
$PortableRoot = Join-Path $Dist 'portable\RB-Mcreator-Version-Updater'
$GuiProj = Join-Path $RepoRoot 'src\RB.Mcreator.VersionUpdater\RB.Mcreator.VersionUpdater.csproj'
$SetupProj = Join-Path $RepoRoot 'src\RB.Mcreator.VersionUpdater.Setup\RB.Mcreator.VersionUpdater.Setup.csproj'

Write-Host "==> Cleaning dist" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Path $PortableRoot -Force | Out-Null

Write-Host "==> Publishing GUI (self-contained $Runtime)" -ForegroundColor Cyan
$guiOut = Join-Path $Dist 'publish-gui'
dotnet publish $GuiProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $guiOut

if ($LASTEXITCODE -ne 0) { throw "GUI publish failed" }

Write-Host "==> Assembling portable folder" -ForegroundColor Cyan
# EXE
Copy-Item (Join-Path $guiOut 'RB-Mcreator-Version-Updater.exe') $PortableRoot -Force
# tools next to exe (also already under publish-gui/tools from content copy)
$toolsSrc = Join-Path $guiOut 'tools'
if (Test-Path $toolsSrc) {
    Copy-Item $toolsSrc (Join-Path $PortableRoot 'tools') -Recurse -Force
}
else {
    # fallback: copy from repo root
    New-Item -ItemType Directory -Path (Join-Path $PortableRoot 'tools') -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'Convert-ToNeoForge262.ps1') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'Convert-ToNeoForge262-GUI.ps1') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'Launch-GUI.bat') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'lib') (Join-Path $PortableRoot 'tools\lib') -Recurse -Force
    Copy-Item (Join-Path $RepoRoot 'templates') (Join-Path $PortableRoot 'tools\templates') -Recurse -Force
    Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $PortableRoot 'tools') -Force
    if (Test-Path (Join-Path $RepoRoot 'tests\Test-Transforms.ps1')) {
        New-Item -ItemType Directory -Path (Join-Path $PortableRoot 'tools\tests') -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot 'tests\Test-Transforms.ps1') (Join-Path $PortableRoot 'tools\tests') -Force
    }
}

# Convenience launchers at portable root
@'
@echo off
cd /d "%~dp0"
start "" "%~dp0RB-Mcreator-Version-Updater.exe"
'@ | Set-Content (Join-Path $PortableRoot 'Start-Updater.bat') -Encoding ASCII

Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $PortableRoot 'README.md') -Force

# LICENSE note
@'
RB MCreator Version Updater
Copyright (c) RobbieB1980

All Rights Reserved unless otherwise noted by the repository owner.
'@ | Set-Content (Join-Path $PortableRoot 'LICENSE.txt') -Encoding UTF8

Write-Host "==> Creating portable ZIP" -ForegroundColor Cyan
$portableZip = Join-Path $Dist 'RB-Mcreator-Version-Updater-Portable.zip'
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
Compress-Archive -Path (Join-Path $Dist 'portable\RB-Mcreator-Version-Updater') -DestinationPath $portableZip -Force

# Payload for installer (same content)
$payloadZip = Join-Path $Dist 'portable-payload.zip'
Copy-Item $portableZip $payloadZip -Force

Write-Host "==> Publishing Setup installer (self-contained $Runtime, payload embedded)" -ForegroundColor Cyan
$setupOut = Join-Path $Dist 'publish-setup'
# Ensure payload path is available as EmbeddedResource during compile
if (-not (Test-Path $payloadZip)) { throw "portable-payload.zip missing before setup publish" }

dotnet publish $SetupProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $setupOut

if ($LASTEXITCODE -ne 0) { throw "Setup publish failed" }

$setupDest = Join-Path $Dist 'RB-Mcreator-Version-Updater-Setup.exe'
Copy-Item $setupExe $setupDest -Force
# portable-payload.zip already lives in $Dist from earlier step

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
Write-Host "  Portable folder : $PortableRoot"
Write-Host "  Portable ZIP    : $portableZip"
Write-Host "  Payload ZIP     : $payloadZip"
Write-Host "  Setup EXE       : $setupDest  (payload embedded)"
Write-Host ""
Write-Host "Distribute either:" -ForegroundColor Yellow
Write-Host "  - RB-Mcreator-Version-Updater-Setup.exe   (installs portable toolset)"
Write-Host "  - RB-Mcreator-Version-Updater-Portable.zip (no install; run Start-Updater.bat)"
