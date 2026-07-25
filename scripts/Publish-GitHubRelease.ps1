<#
.SYNOPSIS
  Create/update a GitHub Release and upload portable + setup artifacts from dist/.

.EXAMPLE
  .\scripts\Publish-GitHubRelease.ps1 -Tag v1.3.0
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v1.3.0',
    [string]$Repo = 'RobbieB1980/RB-Mcreator-Version-Updater',
    [string]$Name = 'RB All Updater 1.3.0'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'

$setup = Join-Path $Dist 'RB-All-Updater-Setup.exe'
$portable = Join-Path $Dist 'RB-All-Updater-Portable.zip'
if (-not (Test-Path $setup)) {
    # legacy names from older builds
    $setup = Join-Path $Dist 'RB-Mcreator-Version-Updater-Setup.exe'
}
if (-not (Test-Path $portable)) {
    $portable = Join-Path $Dist 'RB-Mcreator-Version-Updater-Portable.zip'
}
if (-not (Test-Path $setup)) { throw "Missing setup EXE in dist/ - run Build-Release.ps1 first" }
if (-not (Test-Path $portable)) { throw "Missing portable ZIP in dist/ - run Build-Release.ps1 first" }

# Resolve GitHub token from git credential helper
$fill = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($fill | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
$user = ($fill | Where-Object { $_ -like 'username=*' }) -replace '^username=', ''
if (-not $token) { throw 'Could not obtain GitHub credentials from git credential helper.' }

$headers = @{
    Authorization = "Bearer $token"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'RB-All-Updater-Release'
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
## RB All Updater $Tag

Convert **MCreator**, **ModDevGradle**, and **NeoGradle** 26.1.x projects to **Minecraft 26.2**.

### Downloads

| File | Description |
|------|-------------|
| ``RB-All-Updater-Setup.exe`` | Windows installer (self-contained; embeds full portable toolset) |
| ``RB-All-Updater-Portable.zip`` | No install - extract and run ``Start-Updater.bat`` or the EXE |

### What's new in 1.3.0

- Rebranded to **RB All Updater** (not only MCreator)
- Detects project type: MCreator / ModDevGradle / NeoGradle
- Preserves author ``mod_version``; retargets 26.1 strings to 26.2
- Prefer MDG ``src/main/templates`` mods.toml (do not overwrite hand ports)
- Inject NeoForged maven into ``settings.gradle`` when missing
- Auto-scaffold missing ``assets/*/items/*.json`` client item defs (fixes purple creative icons)
- Fix bare model parents (``minecraft:item/generated``, ``minecraft:block/cube``, spawn eggs)
- New Java transform: ``BlockPos.getCenter()`` -> ``Vec3.atCenterOf(...)``
- Dry-run + compile no longer fail with fake wrapper/missing java warnings
- GUI layout reworked for DPI (no overlapping labels/buttons)

### Requirements

- Windows x64
- PowerShell 5.1+ (converter engine)
- JDK 25 if you compile/run the converted Minecraft mod

### Notes

- GUI always copies to an **output** folder; originals are never modified.
- Setup installs under ``%LOCALAPPDATA%\RB-All-Updater`` by default (no admin required).
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
