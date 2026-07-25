<#
.SYNOPSIS
  Create/update a GitHub Release and upload portable + setup artifacts from dist/.

.EXAMPLE
  .\scripts\Publish-GitHubRelease.ps1 -Tag v1.1.0
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v1.1.0',
    [string]$Repo = 'RobbieB1980/RB-Mcreator-Version-Updater',
    [string]$Name = 'RB MCreator Version Updater 1.1.0'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'

$setup = Join-Path $Dist 'RB-Mcreator-Version-Updater-Setup.exe'
$portable = Join-Path $Dist 'RB-Mcreator-Version-Updater-Portable.zip'
if (-not (Test-Path $setup)) { throw "Missing $setup - run Build-Release.ps1 first" }
if (-not (Test-Path $portable)) { throw "Missing $portable - run Build-Release.ps1 first" }

# Resolve GitHub token from git credential helper
$fill = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($fill | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
$user = ($fill | Where-Object { $_ -like 'username=*' }) -replace '^username=', ''
if (-not $token) { throw 'Could not obtain GitHub credentials from git credential helper.' }

$headers = @{
    Authorization = "Bearer $token"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'RB-Mcreator-Version-Updater-Release'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$api = "https://api.github.com/repos/$Repo"

Write-Host "==> Checking for existing release $Tag" -ForegroundColor Cyan
$release = $null
try {
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/tags/$Tag" -Method Get
    Write-Host "    Release exists (id $($release.id))"
}
catch {
    Write-Host "    Creating release $Tag"
    $body = @{
        tag_name   = $Tag
        name       = $Name
        body       = @"
## RB MCreator Version Updater $Tag

Convert MCreator / NeoForge **26.1.x** workspaces to **Minecraft 26.2**.

### Downloads

| File | Description |
|------|-------------|
| ``RB-Mcreator-Version-Updater-Setup.exe`` | Windows installer (self-contained; embeds full portable toolset) |
| ``RB-Mcreator-Version-Updater-Portable.zip`` | No install - extract and run ``Start-Updater.bat`` or the EXE |

### Requirements

- Windows x64
- PowerShell 5.1+ (used by the converter engine)
- JDK 25 if you compile/run the converted Minecraft mod

### Notes

- GUI always copies to an **output** folder; originals are never modified.
- Setup installs under ``%LOCALAPPDATA%\RB-Mcreator-Version-Updater`` by default (no admin required).
"@
        draft      = $false
        prerelease = $false
    } | ConvertTo-Json
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases" -Method Post -Body $body -ContentType 'application/json'
}

function Upload-Asset([string]$FilePath) {
    $name = [IO.Path]::GetFileName($FilePath)
    # Delete existing asset with same name
    if ($release.assets) {
        $existing = $release.assets | Where-Object { $_.name -eq $name }
        foreach ($a in @($existing)) {
            Write-Host "    Deleting existing asset $name"
            Invoke-RestMethod -Headers $headers -Uri "$api/releases/assets/$($a.id)" -Method Delete | Out-Null
        }
    }
    $uploadUrl = $release.upload_url -replace '\{\?name,label\}', "?name=$([uri]::EscapeDataString($name))"
    Write-Host "    Uploading $name ($([math]::Round((Get-Item $FilePath).Length/1MB,1)) MB)..."
    $bytes = [IO.File]::ReadAllBytes($FilePath)
    $ctype = if ($name.EndsWith('.zip')) { 'application/zip' } else { 'application/octet-stream' }
    Invoke-RestMethod -Headers $headers -Uri $uploadUrl -Method Post -Body $bytes -ContentType $ctype | Out-Null
    Write-Host "    Uploaded $name" -ForegroundColor Green
}

# Refresh release for assets list after create
$release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/tags/$Tag" -Method Get

Upload-Asset $setup
Upload-Asset $portable

Write-Host ""
Write-Host "Release published: https://github.com/$Repo/releases/tag/$Tag" -ForegroundColor Green
