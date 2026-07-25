<#
.SYNOPSIS
    Convert a NeoForge / MCreator Gradle mod workspace from Minecraft 26.1.x to 26.2.

.DESCRIPTION
    Applies the same migration used for robmod:
      - Scaffold or update Gradle MDK files (NeoGradle 7.1.x, Java 25)
      - Bump minecraft/neo versions in gradle.properties
      - Normalize neoforge.mods.toml for property expansion
      - Update pack.mcmeta pack formats
      - Patch known Java API breaks (emissiveRendering, setScreen, render APIs, ...)
      - Optionally update *.mcreator workspace metadata
      - Optionally download Gradle wrapper from the official NeoForge 26.2 MDK
      - Optionally compile to verify

.PARAMETER Path
    Root of the mod project (folder containing src/ and/or *.mcreator).

.PARAMETER OutputPath
    Optional destination folder. When set, the project is copied here first and
    conversion runs only on the copy (original Path is never modified).

.PARAMETER MinecraftVersion
    Target Minecraft version. Default: 26.2

.PARAMETER NeoVersion
    Target NeoForge version. Default: 26.2.0.32-beta

.PARAMETER ModVersion
    Optional override for mod_version in gradle.properties. Default: <MinecraftVersion>.0

.PARAMETER DryRun
    Show what would change without writing files.

.PARAMETER SkipGradleScaffold
    Do not create/overwrite build.gradle / settings.gradle.

.PARAMETER SkipJavaTransforms
    Do not rewrite Java sources.

.PARAMETER SkipBackup
    Do not write a timestamped backup zip before modifying.

.PARAMETER Compile
    Run gradlew compileJava after conversion.

.PARAMETER Build
    Run gradlew build after conversion.

.PARAMETER FetchWrapper
    Download Gradle wrapper from NeoForgeMDKs/MDK-26.2-NeoGradle if missing.

.EXAMPLE
    .\Convert-ToNeoForge262.ps1 -Path "D:\mods\MyMod"

.EXAMPLE
    .\Convert-ToNeoForge262.ps1 -Path "D:\mods\MyMod" -OutputPath "D:\mods\MyMod-26.2"

.EXAMPLE
    .\Convert-ToNeoForge262.ps1 -Path ".\othermod" -NeoVersion "26.2.0.32-beta" -DryRun

.EXAMPLE
    .\Convert-ToNeoForge262.ps1 -Path ".\othermod" -Compile -FetchWrapper
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [string]$OutputPath = '',

    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.32-beta',
    [string]$ModVersion = '',
    [string]$NeoGradleVersion = '7.1.38',
    [string]$CompilerHeap = '4g',
    [int]$PackFormat = 107,
    [int]$GradleJvmMb = 4096,

    [switch]$DryRun,
    [switch]$SkipGradleScaffold,
    [switch]$SkipJavaTransforms,
    [switch]$SkipBackup,
    [switch]$Compile,
    [switch]$Build,
    [switch]$FetchWrapper,
    [switch]$ForceTomlTemplate
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
$Templates = Join-Path $ToolRoot 'templates'
. (Join-Path $ToolRoot 'lib\JavaApiTransforms.ps1')

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Warn2([string]$Message) {
    Write-Host "    WARN: $Message" -ForegroundColor Yellow
}

function Write-Info([string]$Message) {
    Write-Host "    $Message"
}

function Resolve-ProjectRoot([string]$InputPath) {
    $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
    return $resolved.Path
}

function Get-PropValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Key))\s*=\s*(.*)\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Set-PropValue([string]$Text, [string]$Key, [string]$Value) {
    if ($Text -match "(?m)^\s*$([regex]::Escape($Key))\s*=") {
        return [regex]::Replace($Text, "(?m)^(\s*$([regex]::Escape($Key))\s*=\s*).*$", "`${1}$Value")
    }
    # append under a sensible section
    if ($Text -notmatch "`n$") { $Text += "`r`n" }
    return $Text + "$Key=$Value`r`n"
}

function Ensure-PropDefaults([hashtable]$Props, [hashtable]$Defaults) {
    foreach ($k in $Defaults.Keys) {
        if (-not $Props.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($Props[$k])) {
            $Props[$k] = $Defaults[$k]
        }
    }
    return $Props
}

function Read-GradleProperties([string]$File) {
    $map = @{}
    if (-not (Test-Path $File)) { return $map }
    foreach ($line in Get-Content -LiteralPath $File) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)\s*$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

function Write-GradlePropertiesFile {
    param(
        [string]$File,
        [hashtable]$Props,
        [string]$MinecraftVersion,
        [string]$MinecraftVersionRange,
        [string]$NeoVersion,
        [string]$ModVersion,
        [int]$GradleJvmMb
    )

    # Preserve unknown keys; rewrite known environment keys
    $order = @(
        'org.gradle.jvmargs', 'org.gradle.daemon', 'org.gradle.parallel',
        'org.gradle.caching', 'org.gradle.configuration-cache',
        'minecraft_version', 'minecraft_version_range', 'neo_version',
        'mod_id', 'mod_name', 'mod_license', 'mod_version', 'mod_group_id',
        'mod_authors', 'mod_description', 'mod_credits', 'mod_display_url'
    )

    $Props['org.gradle.jvmargs'] = "-Xmx${GradleJvmMb}M"
    $Props['org.gradle.daemon'] = 'true'
    $Props['org.gradle.parallel'] = 'true'
    $Props['org.gradle.caching'] = 'true'
    $Props['org.gradle.configuration-cache'] = 'true'
    $Props['minecraft_version'] = $MinecraftVersion
    $Props['minecraft_version_range'] = $MinecraftVersionRange
    $Props['neo_version'] = $NeoVersion
    $Props['mod_version'] = $ModVersion

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Generated/updated by neoforge-26.2-converter')
    [void]$sb.AppendLine("# Target: Minecraft $MinecraftVersion / NeoForge $NeoVersion")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Gradle')
    foreach ($k in @('org.gradle.jvmargs', 'org.gradle.daemon', 'org.gradle.parallel', 'org.gradle.caching', 'org.gradle.configuration-cache')) {
        [void]$sb.AppendLine("$k=$($Props[$k])")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Environment - https://projects.neoforged.net/neoforged/neoforge')
    foreach ($k in @('minecraft_version', 'minecraft_version_range', 'neo_version')) {
        [void]$sb.AppendLine("$k=$($Props[$k])")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Mod Properties')
    foreach ($k in @('mod_id', 'mod_name', 'mod_license', 'mod_version', 'mod_group_id', 'mod_authors', 'mod_description', 'mod_credits', 'mod_display_url')) {
        if ($Props.ContainsKey($k)) {
            [void]$sb.AppendLine("$k=$($Props[$k])")
        }
    }

    # Preserve any extra keys
    $known = [System.Collections.Generic.HashSet[string]]::new([string[]]$order)
    $extras = @()
    foreach ($k in $Props.Keys) {
        if (-not $known.Contains($k)) { $extras += $k }
    }
    if ($extras.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('# Other preserved properties')
        foreach ($k in ($extras | Sort-Object)) {
            [void]$sb.AppendLine("$k=$($Props[$k])")
        }
    }

    $content = $sb.ToString()
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($File, $content)
    }
    return $content
}

function Expand-Template([string]$TemplatePath, [hashtable]$Tokens) {
    $text = [System.IO.File]::ReadAllText($TemplatePath)
    foreach ($k in $Tokens.Keys) {
        $text = $text.Replace("{{$k}}", [string]$Tokens[$k])
    }
    return $text
}

function Update-ModsToml {
    param(
        [string]$TomlPath,
        [string]$TemplatePath,
        [hashtable]$Props,
        [string]$NeoVersion,
        [string]$MinecraftVersion,
        [string]$MinecraftVersionRange,
        [switch]$ForceTemplate
    )

    if (-not (Test-Path $TomlPath) -or $ForceTemplate) {
        $dir = Split-Path $TomlPath -Parent
        if (-not (Test-Path $dir) -and -not $DryRun) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $content = [System.IO.File]::ReadAllText($TemplatePath)
        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($TomlPath, $content)
        }
        return 'wrote-template'
    }

    $text = [System.IO.File]::ReadAllText($TomlPath)
    $original = $text

    # Prefer property-expansion style if already using ${}
    $usesExpand = $text -match '\$\{mod_id\}|\$\{neo_version\}'

    if ($usesExpand) {
        # Ensure dependency blocks reference properties
        $text = $text -replace 'versionRange\s*=\s*"(?:\[)?26\.1[^"]*"', 'versionRange="[${neo_version},)"'
        $text = $text -replace 'versionRange\s*=\s*"(?:\[)?26\.2[^"]*"', 'versionRange="[${neo_version},)"'
        $text = $text -replace 'versionRange\s*=\s*"\[26\.1[^\]]*\]"', 'versionRange="${minecraft_version_range}"'
        # minecraft dependency often exact
        $text = [regex]::Replace($text, '(?s)(\[\[dependencies\.[^\]]+\]\][^\[]*?modId\s*=\s*"minecraft"[^\[]*?versionRange\s*=\s*")[^"]*(")', {
            param($m)
            return $m.Groups[1].Value + '${minecraft_version_range}' + $m.Groups[2].Value
        })
        $text = [regex]::Replace($text, '(?s)(\[\[dependencies\.[^\]]+\]\][^\[]*?modId\s*=\s*"neoforge"[^\[]*?versionRange\s*=\s*")[^"]*(")', {
            param($m)
            return $m.Groups[1].Value + '[${neo_version},)' + $m.Groups[2].Value
        })
    }
    else {
        # Hardcoded MCreator-style toml
        $modVersion = $Props['mod_version']
        $desc = $Props['mod_description']

        if ($modVersion) {
            $text = [regex]::Replace($text, '(?m)^(version\s*=\s*")[^"]*(")', "`${1}$modVersion`${2}")
        }
        if ($desc) {
            $text = [regex]::Replace($text, '(?m)^(description\s*=\s*")[^"]*(")', "`${1}$desc`${2}")
        }
        else {
            # At least bump embedded 26.1.x version strings in description
            $text = [regex]::Replace($text, '(?m)^(description\s*=\s*"[^"]*?)26\.1(?:\.\d+)?', "`${1}$MinecraftVersion")
        }
        # NeoForge dependency
        $text = [regex]::Replace($text, '(?s)(modId\s*=\s*"neoforge"\s*.*?versionRange\s*=\s*")[^"]*(")', {
            param($m)
            return $m.Groups[1].Value + "[$NeoVersion,)" + $m.Groups[2].Value
        })
        # Minecraft dependency
        $text = [regex]::Replace($text, '(?s)(modId\s*=\s*"minecraft"\s*.*?versionRange\s*=\s*")[^"]*(")', {
            param($m)
            return $m.Groups[1].Value + $MinecraftVersionRange + $m.Groups[2].Value
        })
    }

    if ($text -ne $original -and -not $DryRun) {
        [System.IO.File]::WriteAllText($TomlPath, $text)
    }
    return $(if ($text -ne $original) { 'patched' } else { 'unchanged' })
}

function Update-PackMcmeta {
    param([string]$File, [int]$PackFormat, [string]$Description)

    $json = @{
        pack = @{
            min_format  = $PackFormat
            max_format  = $PackFormat
            description = $Description
        }
    } | ConvertTo-Json -Depth 5

    # ConvertTo-Json may produce different key order; write a stable form
    $content = @"
{
  "pack": {
    "min_format": $PackFormat,
    "max_format": $PackFormat,
    "description": "$($Description.Replace('"','\"'))"
  }
}
"@
    if (-not $DryRun) {
        $dir = Split-Path $File -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($File, $content.TrimStart() + "`r`n")
    }
}

function Update-McreatorWorkspace {
    param([string]$ProjectRoot, [string]$MinecraftVersion, [string]$ModVersion, [string]$Description)

    $files = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.mcreator' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $original = $text

        # workspaceSettings version / generator
        $text = $text -replace '"currentGenerator"\s*:\s*"neoforge-26\.1(?:\.\d+)?"', "`"currentGenerator`": `"neoforge-$MinecraftVersion`""
        $text = $text -replace '"currentGenerator"\s*:\s*"neoforge-1\.21[^"]*"', "`"currentGenerator`": `"neoforge-$MinecraftVersion`""

        # Only touch workspaceSettings.version (near the end) carefully:
        if ($text -match '"workspaceSettings"\s*:\s*\{') {
            $text = [regex]::Replace($text, '("workspaceSettings"\s*:\s*\{[^}]*?"version"\s*:\s*")[^"]*(")', "`${1}$ModVersion`${2}")
            $text = [regex]::Replace($text, '("workspaceSettings"\s*:\s*\{[^}]*?"description"\s*:\s*")[^"]*(")', {
                param($m)
                $esc = $Description -replace '\\', '\\' -replace '"', '\"'
                # keep unicode-escaped apostrophes style if present originally
                return $m.Groups[1].Value + $esc + $m.Groups[2].Value
            })
        }

        if ($text -ne $original) {
            if (-not $DryRun) {
                [System.IO.File]::WriteAllText($f.FullName, $text)
            }
            Write-Ok "Updated $($f.Name)"
        }
        else {
            Write-Info "No mcreator metadata changes in $($f.Name)"
        }
    }
}

function Ensure-ClientItemDefinitions {
    <#
    .SYNOPSIS
      MC 26.x requires assets/<namespace>/items/<id>.json client item defs that
      point at models. Many 26.1 / MCreator / partial ports only ship models/item.
      Scaffold missing items/*.json and normalize common parent paths.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$DryRun
    )

    $assetsRoot = Join-Path $ProjectRoot 'src\main\resources\assets'
    $created = 0
    $existing = 0
    $scanned = 0
    $parentFixes = 0

    if (-not (Test-Path $assetsRoot)) {
        return [pscustomobject]@{ Created = 0; Existing = 0; Scanned = 0; ModelParentFixes = 0 }
    }

    foreach ($nsDir in Get-ChildItem -LiteralPath $assetsRoot -Directory -ErrorAction SilentlyContinue) {
        $modelsItem = Join-Path $nsDir.FullName 'models\item'
        if (-not (Test-Path $modelsItem)) { continue }

        $itemsDir = Join-Path $nsDir.FullName 'items'
        $ns = $nsDir.Name

        foreach ($modelFile in Get-ChildItem -LiteralPath $modelsItem -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            $scanned++
            $id = [System.IO.Path]::GetFileNameWithoutExtension($modelFile.Name)
            $clientPath = Join-Path $itemsDir "$id.json"

            # Normalize model parents for 26.x
            $modelText = [System.IO.File]::ReadAllText($modelFile.FullName)
            $origModel = $modelText
            $modelText = $modelText -replace '"parent"\s*:\s*"item/generated"', '"parent": "minecraft:item/generated"'
            $modelText = $modelText -replace '"parent"\s*:\s*"item/handheld"', '"parent": "minecraft:item/handheld"'
            # template_spawn_egg removed in modern versions
            if ($modelText -match '"parent"\s*:\s*"item/template_spawn_egg"' -or
                $modelText -match '"parent"\s*:\s*"minecraft:item/template_spawn_egg"') {
                # Prefer a same-namespace item texture if present, else leave generated without textures (still better than broken parent)
                $fallbackTex = "$ns`:item/$id"
                $texFile = Join-Path $nsDir.FullName "textures\item\$id.png"
                if (-not (Test-Path $texFile)) {
                    $anyItemTex = Get-ChildItem (Join-Path $nsDir.FullName 'textures\item') -Filter '*.png' -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($anyItemTex) {
                        $fallbackTex = "$ns`:item/$([System.IO.Path]::GetFileNameWithoutExtension($anyItemTex.Name))"
                    }
                }
                $modelText = @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": "$fallbackTex"
  }
}
"@
            }
            if ($modelText -ne $origModel) {
                $parentFixes++
                if (-not $DryRun) {
                    [System.IO.File]::WriteAllText($modelFile.FullName, $modelText.TrimEnd() + "`r`n")
                }
            }

            # Also fix bare block/cube parents under models/block
            if (Test-Path (Join-Path $nsDir.FullName 'models\block')) {
                # handled once per ns outside loop for efficiency - skip here
            }

            if (Test-Path $clientPath) {
                $existing++
                continue
            }

            # Point block-looking models at block model when parent is a block path
            $modelRef = "$ns`:item/$id"
            if ($modelText -match '"parent"\s*:\s*"' + [regex]::Escape($ns) + ':block/([^"]+)"') {
                $modelRef = "$ns`:block/$($Matches[1])"
            }
            elseif ($id -match '^(block_|.*_block$)' -and (Test-Path (Join-Path $nsDir.FullName "models\block\$id.json"))) {
                $modelRef = "$ns`:block/$id"
            }
            elseif (Test-Path (Join-Path $nsDir.FullName "models\block\$id.json")) {
                # e.g. scratched_oak_log item model parents block — prefer block for 3D icon
                if ($modelText -match ':block/') {
                    if ($modelText -match '"parent"\s*:\s*"([^"]+:block/[^"]+)"') {
                        $modelRef = $Matches[1]
                    }
                }
            }

            $clientJson = @"
{
  "model": {
    "type": "minecraft:model",
    "model": "$modelRef"
  }
}
"@
            $created++
            if (-not $DryRun) {
                if (-not (Test-Path $itemsDir)) {
                    New-Item -ItemType Directory -Path $itemsDir -Force | Out-Null
                }
                [System.IO.File]::WriteAllText($clientPath, $clientJson.TrimEnd() + "`r`n")
            }
        }

        # Fix bare block/* parents once per namespace
        $blockModels = Join-Path $nsDir.FullName 'models\block'
        if (Test-Path $blockModels) {
            foreach ($bm in Get-ChildItem -LiteralPath $blockModels -Filter '*.json' -File -ErrorAction SilentlyContinue) {
                $bt = [System.IO.File]::ReadAllText($bm.FullName)
                $ob = $bt
                $bt = $bt -replace '"parent"\s*:\s*"block/cube"', '"parent": "minecraft:block/cube"'
                $bt = $bt -replace '"parent"\s*:\s*"block/cube_all"', '"parent": "minecraft:block/cube_all"'
                $bt = $bt -replace '"parent"\s*:\s*"block/cube_column"', '"parent": "minecraft:block/cube_column"'
                $bt = $bt -replace '"parent"\s*:\s*"block/cross"', '"parent": "minecraft:block/cross"'
                if ($bt -ne $ob) {
                    $parentFixes++
                    if (-not $DryRun) {
                        [System.IO.File]::WriteAllText($bm.FullName, $bt)
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        Created           = $created
        Existing          = $existing
        Scanned           = $scanned
        ModelParentFixes  = $parentFixes
    }
}

function Install-GradleWrapper {
    param([string]$ProjectRoot)

    $wrapperJar = Join-Path $ProjectRoot 'gradle\wrapper\gradle-wrapper.jar'
    $hasWrapper = (Test-Path $wrapperJar) -and (Test-Path (Join-Path $ProjectRoot 'gradlew.bat'))
    if ($hasWrapper) {
        Write-Info 'Gradle wrapper already present.'
        return
    }

    Write-Step 'Fetching Gradle wrapper from NeoForge 26.2 MDK'
    if ($DryRun) {
        Write-Info 'Dry run: would download MDK-26.2-NeoGradle and install gradlew / gradle-wrapper'
        return
    }

    $tmp = Join-Path $env:TEMP ("neoforge-mdk-26.2-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = Join-Path $tmp 'mdk.zip'
        $url = 'https://github.com/NeoForgeMDKs/MDK-26.2-NeoGradle/archive/refs/heads/main.zip'
        Write-Info "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $mdk = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like 'MDK-*' } | Select-Object -First 1
        if (-not $mdk) { throw 'MDK extract failed' }

        New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'gradle\wrapper') -Force | Out-Null
        Copy-Item (Join-Path $mdk.FullName 'gradle\wrapper\*') (Join-Path $ProjectRoot 'gradle\wrapper') -Force
        Copy-Item (Join-Path $mdk.FullName 'gradlew.bat') $ProjectRoot -Force
        if (Test-Path (Join-Path $mdk.FullName 'gradlew')) {
            Copy-Item (Join-Path $mdk.FullName 'gradlew') $ProjectRoot -Force
        }
        if ((Test-Path (Join-Path $mdk.FullName '.gitignore')) -and -not (Test-Path (Join-Path $ProjectRoot '.gitignore'))) {
            Copy-Item (Join-Path $mdk.FullName '.gitignore') $ProjectRoot -Force
        }
        Write-Ok 'Wrapper installed from MDK-26.2-NeoGradle'
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-ProjectBackup {
    param([string]$ProjectRoot)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $ProjectRoot '.converter-backups'
    $zipPath = Join-Path $backupDir "pre-26.2-$stamp.zip"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    Write-Step "Creating backup: $zipPath"

    # Zip only source-ish trees (skip build/run/.gradle)
    $include = @('src', 'gradle', 'elements')
    $files = @()
    foreach ($name in @('build.gradle', 'settings.gradle', 'gradle.properties', 'gradlew', 'gradlew.bat')) {
        $p = Join-Path $ProjectRoot $name
        if (Test-Path $p) { $files += $p }
    }
    Get-ChildItem $ProjectRoot -Filter '*.mcreator' -File -ErrorAction SilentlyContinue | ForEach-Object { $files += $_.FullName }
    foreach ($dir in $include) {
        $p = Join-Path $ProjectRoot $dir
        if (Test-Path $p) {
            $files += Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\build\\|\\run\\|\\\.gradle\\' } |
                Select-Object -ExpandProperty FullName
        }
    }

    if ($DryRun) {
        Write-Info "Would backup $($files.Count) files"
        return $null
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($f in $files) {
            $rel = $f.Substring($ProjectRoot.Length).TrimStart('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, $rel.Replace('\', '/')) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }
    Write-Ok "Backup written ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB)"
    return $zipPath
}

function Infer-ModMetadata {
    param([string]$ProjectRoot, [hashtable]$Props)

    # From existing gradle.properties
    if ($Props['mod_id']) { return $Props }

    # From neoforge.mods.toml
    $toml = Join-Path $ProjectRoot 'src\main\resources\META-INF\neoforge.mods.toml'
    if (Test-Path $toml) {
        $t = Get-Content $toml -Raw
        if (-not $Props['mod_id'] -and $t -match 'modId\s*=\s*"([^"]+)"') { $Props['mod_id'] = $Matches[1] }
        if (-not $Props['mod_name'] -and $t -match 'displayName\s*=\s*"([^"]+)"') { $Props['mod_name'] = $Matches[1] }
        if (-not $Props['mod_license'] -and $t -match 'license\s*=\s*"([^"]+)"') { $Props['mod_license'] = $Matches[1] }
        if (-not $Props['mod_authors'] -and $t -match 'authors\s*=\s*"([^"]+)"') { $Props['mod_authors'] = $Matches[1] }
        if (-not $Props['mod_description'] -and $t -match '(?m)^\s*description\s*=\s*"([^"]+)"') {
            $Props['mod_description'] = $Matches[1].Trim()
        }
        elseif (-not $Props['mod_description'] -and $t -match "(?s)description\s*=\s*'''\s*(.*?)\s*'''") {
            $Props['mod_description'] = ($Matches[1] -replace '\s+', ' ').Trim()
        }
        if (-not $Props['mod_credits'] -and $t -match 'credits\s*=\s*"([^"]+)"') { $Props['mod_credits'] = $Matches[1] }
        if (-not $Props['mod_display_url'] -and $t -match 'displayURL\s*=\s*"([^"]+)"') { $Props['mod_display_url'] = $Matches[1] }
    }

    # From main @Mod class package
    $javaRoot = Join-Path $ProjectRoot 'src\main\java'
    if ((-not $Props['mod_group_id']) -and (Test-Path $javaRoot)) {
        $modClass = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -ErrorAction SilentlyContinue |
            Select-String -Pattern '@Mod\(' -List |
            Select-Object -First 1
        if ($modClass) {
            $pkgLine = Select-String -Path $modClass.Path -Pattern '^package\s+([\w\.]+);' | Select-Object -First 1
            if ($pkgLine) {
                $pkg = $pkgLine.Matches[0].Groups[1].Value
                # group is package without last segment if last is mod id-ish
                $Props['mod_group_id'] = $pkg
            }
        }
    }

    # Folder name fallback
    $folder = Split-Path $ProjectRoot -Leaf
    if (-not $Props['mod_id']) {
        $Props['mod_id'] = ($folder -replace '[^a-z0-9_]', '').ToLower()
        if ($Props['mod_id'].Length -lt 2) { $Props['mod_id'] = 'examplemod' }
    }
    if (-not $Props['mod_name']) { $Props['mod_name'] = $Props['mod_id'] }
    if (-not $Props['mod_license']) { $Props['mod_license'] = 'All Rights Reserved' }
    if (-not $Props['mod_group_id']) { $Props['mod_group_id'] = "net.mcreator.$($Props['mod_id'])" }
    if (-not $Props['mod_authors']) { $Props['mod_authors'] = 'Unknown' }
    if (-not $Props['mod_description']) { $Props['mod_description'] = "$($Props['mod_name']) for Minecraft $MinecraftVersion" }
    if (-not $Props['mod_credits']) { $Props['mod_credits'] = '' }
    if (-not $Props['mod_display_url']) { $Props['mod_display_url'] = '' }

    return $Props
}

function Update-ExistingBuildGradle {
    param([string]$File, [string]$MinecraftVersion, [string]$NeoGradleVersion)

    if (-not (Test-Path $File)) { return $false }
    $text = [System.IO.File]::ReadAllText($File)
    $original = $text

    # NeoGradle plugin version
    $text = $text -replace "id\s+'net\.neoforged\.gradle\.userdev'\s+version\s+'[^']+'", "id 'net.neoforged.gradle.userdev' version '$NeoGradleVersion'"

    # Java toolchain 21/22/23/24 -> 25
    $text = $text -replace 'JavaLanguageVersion\.of\(\s*2[1-4]\s*\)', 'JavaLanguageVersion.of(25)'
    $text = $text -replace 'languageVersion\s*=\s*JavaLanguageVersion\.of\(\s*2[1-4]\s*\)', 'languageVersion = JavaLanguageVersion.of(25)'

    # Comments about Java version for MC
    $text = $text -replace 'Mojang ships Java \d+ to end users in 26\.1', "Mojang ships Java 25 to end users in $MinecraftVersion"

    if ($text -ne $original -and -not $DryRun) {
        [System.IO.File]::WriteAllText($File, $text)
    }
    return ($text -ne $original)
}

function Copy-ProjectToOutput {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestRoot,
        [switch]$DryRun
    )

    $SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
    $DestRoot = [System.IO.Path]::GetFullPath($DestRoot)

    if ($SourceRoot.TrimEnd('\') -ieq $DestRoot.TrimEnd('\')) {
        throw "OutputPath must be different from Path (refusing to overwrite the original)."
    }
    if ($DestRoot.StartsWith($SourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $DestRoot.StartsWith($SourceRoot + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath cannot be inside the input project folder."
    }
    if ($SourceRoot.StartsWith($DestRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $SourceRoot.StartsWith($DestRoot + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Input Path cannot be inside OutputPath."
    }

    # Skip heavy / regenerable trees
    $excludeDirNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('build', 'run', '.gradle', '.converter-backups', 'bin', 'out', 'repo', 'node_modules', '.idea'),
        [StringComparer]::OrdinalIgnoreCase
    )

    Write-Step "Copying project to output (original will not be modified)"
    Write-Info "From: $SourceRoot"
    Write-Info "To  : $DestRoot"

    if ($DryRun) {
        Write-Info 'Dry run: would copy project files (excluding build/run/.gradle/...)'
        return $DestRoot
    }

    if (Test-Path -LiteralPath $DestRoot) {
        $existing = Get-ChildItem -LiteralPath $DestRoot -Force -ErrorAction SilentlyContinue
        if ($existing) {
            throw "Output folder already exists and is not empty: $DestRoot"
        }
    }
    else {
        New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
    }

    $fileCount = 0
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($SourceRoot)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $relDir = if ($current.Length -le $SourceRoot.Length) { '' } else { $current.Substring($SourceRoot.Length).TrimStart('\', '/') }
        $destDir = if ($relDir) { Join-Path $DestRoot $relDir } else { $DestRoot }
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        foreach ($item in Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) {
                if ($excludeDirNames.Contains($item.Name)) { continue }
                $stack.Push($item.FullName)
            }
            else {
                $destFile = Join-Path $destDir $item.Name
                Copy-Item -LiteralPath $item.FullName -Destination $destFile -Force
                $fileCount++
            }
        }
    }

    Write-Ok "Copied $fileCount file(s) to output folder"
    return $DestRoot
}

# -------------------- main --------------------

$SourceRoot = Resolve-ProjectRoot $Path
if (-not (Test-Path (Join-Path $SourceRoot 'src')) -and -not (Get-ChildItem $SourceRoot -Filter '*.mcreator' -ErrorAction SilentlyContinue)) {
    throw "Does not look like a mod project (no src/ or *.mcreator): $SourceRoot"
}

$WorkingOnCopy = $false
if ($OutputPath) {
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location) $OutputPath
    }
    $destFull = [System.IO.Path]::GetFullPath($OutputPath)
    $ProjectRoot = Copy-ProjectToOutput -SourceRoot $SourceRoot -DestRoot $destFull -DryRun:$DryRun
    if ($DryRun) {
        # Preview reads must use source content — output is empty until a real run copies it.
        # (Using the empty output path previously caused false "No src/main/java", wrong mod_id
        # from the output folder name, and fake "wrapper installed" then compile exit 2.)
        Write-Info "Dry run: previewing transforms against source; real run would write to: $destFull"
        $ProjectRoot = $SourceRoot
    }
    else {
        $ProjectRoot = Resolve-ProjectRoot $ProjectRoot
    }
    $WorkingOnCopy = $true
    # Original is untouched; no need for in-tree backup zip
    $SkipBackup = $true
}
else {
    $ProjectRoot = $SourceRoot
}

$MinecraftVersionRange = "[$MinecraftVersion]"

# Detect project style: MCreator workspace, ModDevGradle (hand/migration), NeoGradle MDK
$buildGradleProbe = Join-Path $ProjectRoot 'build.gradle'
$isModDevGradle = $false
$isNeoGradle = $false
$isMcreator = [bool](Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.mcreator' -File -ErrorAction SilentlyContinue)
if (Test-Path $buildGradleProbe) {
    $bgProbe = [System.IO.File]::ReadAllText($buildGradleProbe)
    $isModDevGradle = $bgProbe -match "net\.neoforged\.moddev"
    $isNeoGradle = $bgProbe -match "net\.neoforged\.gradle\.userdev"
}
$projectKind = if ($isMcreator) { 'MCreator' }
    elseif ($isModDevGradle) { 'ModDevGradle' }
    elseif ($isNeoGradle) { 'NeoGradle' }
    elseif (Test-Path $buildGradleProbe) { 'Gradle-other' }
    else { 'scaffold-needed' }

# --- gradle.properties (read first so we can preserve mod_version) ---
Write-Step 'Updating gradle.properties'
$propsFile = Join-Path $ProjectRoot 'gradle.properties'
$props = Read-GradleProperties $propsFile
$props = Infer-ModMetadata -ProjectRoot $ProjectRoot -Props $props

if (-not $ModVersion) {
    if ($props['mod_version']) {
        # Keep author version; only retarget embedded 26.1.x strings to target MC
        $ModVersion = $props['mod_version'] -replace '26\.1(?:\.\d+)?', $MinecraftVersion
        $ModVersion = $ModVersion -replace 'mc26\.1(?:\.\d+)?', "mc$MinecraftVersion"
    }
    else {
        $ModVersion = "$MinecraftVersion.0"
    }
}
$props['mod_version'] = $ModVersion
if ($props['mod_description'] -match '26\.1') {
    $props['mod_description'] = $props['mod_description'] -replace '26\.1(?:\.\d+)?', $MinecraftVersion
}

Write-Host ""
Write-Host "RB All Updater - NeoForge 26.2 Converter" -ForegroundColor White
Write-Host "  Source  : $SourceRoot"
Write-Host "  Working : $ProjectRoot"
if ($WorkingOnCopy) { Write-Host "  Mode    : copy-to-output (original preserved)" -ForegroundColor Green }
Write-Host "  Project : $projectKind" -ForegroundColor Cyan
Write-Host "  Target  : Minecraft $MinecraftVersion / NeoForge $NeoVersion"
Write-Host "  Mod ver : $ModVersion"
if ($DryRun) { Write-Host "  DryRun  : yes (no writes)" -ForegroundColor Yellow }

if (-not $SkipBackup -and -not $DryRun) {
    New-ProjectBackup -ProjectRoot $ProjectRoot | Out-Null
}
elseif ($SkipBackup) {
    Write-Info 'Backup skipped.'
}

Write-GradlePropertiesFile -File $propsFile -Props $props `
    -MinecraftVersion $MinecraftVersion `
    -MinecraftVersionRange $MinecraftVersionRange `
    -NeoVersion $NeoVersion `
    -ModVersion $ModVersion `
    -GradleJvmMb $GradleJvmMb | Out-Null
Write-Ok "mod_id=$($props['mod_id'])  neo_version=$NeoVersion  minecraft_version=$MinecraftVersion"

# --- Gradle scaffold ---
if (-not $SkipGradleScaffold) {
    Write-Step 'Gradle build files'
    $buildGradle = Join-Path $ProjectRoot 'build.gradle'
    $settingsGradle = Join-Path $ProjectRoot 'settings.gradle'

    if (-not (Test-Path $buildGradle)) {
        $tokens = @{
            NEOGRADLE_VERSION = $NeoGradleVersion
            COMPILER_HEAP     = $CompilerHeap
        }
        $content = Expand-Template (Join-Path $Templates 'build.gradle.template') $tokens
        if (-not $DryRun) { [System.IO.File]::WriteAllText($buildGradle, $content) }
        Write-Ok 'Created build.gradle from NeoGradle MDK template (MCreator-style scaffold)'
    }
    else {
        # Never replace ModDevGradle buildscripts with NeoGradle templates
        if ($isModDevGradle) {
            $changed = Update-ExistingBuildGradle -File $buildGradle -MinecraftVersion $MinecraftVersion -NeoGradleVersion $NeoGradleVersion
            if ($changed) { Write-Ok 'Patched ModDevGradle build.gradle (Java toolchain / comments)' }
            else { Write-Info 'ModDevGradle build.gradle present - left as-is (versions in gradle.properties)' }
        }
        else {
            $changed = Update-ExistingBuildGradle -File $buildGradle -MinecraftVersion $MinecraftVersion -NeoGradleVersion $NeoGradleVersion
            if ($changed) { Write-Ok 'Patched existing build.gradle (NeoGradle / Java 25)' }
            else { Write-Info 'build.gradle present - left mostly as-is (versions live in gradle.properties)' }
        }
    }

    if (-not (Test-Path $settingsGradle)) {
        $tokens = @{ PROJECT_NAME = $props['mod_id'] }
        $content = Expand-Template (Join-Path $Templates 'settings.gradle.template') $tokens
        if (-not $DryRun) { [System.IO.File]::WriteAllText($settingsGradle, $content) }
        Write-Ok 'Created settings.gradle from template'
    }
    else {
        $sg = [System.IO.File]::ReadAllText($settingsGradle)
        if ($sg -notmatch 'maven\.neoforged\.net') {
            # Inject NeoForged maven into pluginManagement.repositories when possible
            if ($sg -match '(?s)(pluginManagement\s*\{\s*repositories\s*\{)') {
                $sg2 = [regex]::Replace(
                    $sg,
                    '(pluginManagement\s*\{\s*repositories\s*\{)',
                    "`$1`r`n        maven { url = 'https://maven.neoforged.net/releases' }",
                    1
                )
                if ($sg2 -ne $sg -and -not $DryRun) {
                    [System.IO.File]::WriteAllText($settingsGradle, $sg2)
                }
                Write-Ok 'Injected maven.neoforged.net into settings.gradle pluginManagement'
            }
            else {
                Write-Warn2 'settings.gradle missing maven.neoforged.net - add it if plugin resolve fails'
            }
        }
        else {
            Write-Info 'settings.gradle OK (NeoForged maven present)'
        }
        # Bump rootProject.name 26.1 -> target when present
        if ($sg -match "rootProject\.name\s*=\s*'[^']*26\.1[^']*'") {
            $sg3 = [regex]::Replace($sg, "(rootProject\.name\s*=\s*')([^']*?)26\.1(?:\.\d+)?([^']*')", "`${1}`${2}$MinecraftVersion`${3}")
            if ($sg3 -ne $sg -and -not $DryRun) {
                # re-read if we already wrote neo maven
                $current = if (Test-Path $settingsGradle) { [System.IO.File]::ReadAllText($settingsGradle) } else { $sg }
                $sg3 = [regex]::Replace($current, "(rootProject\.name\s*=\s*')([^']*?)26\.1(?:\.\d+)?([^']*')", "`${1}`${2}$MinecraftVersion`${3}")
                [System.IO.File]::WriteAllText($settingsGradle, $sg3)
            }
            Write-Ok "Updated rootProject.name for $MinecraftVersion"
        }
    }
}

if ($FetchWrapper) {
    Install-GradleWrapper -ProjectRoot $ProjectRoot
}
else {
    $hasWrapper = Test-Path (Join-Path $ProjectRoot 'gradlew.bat')
    if (-not $hasWrapper) {
        Write-Warn2 'No gradlew.bat - re-run with -FetchWrapper to install from MDK'
    }
}

# --- mods.toml (MDG uses src/main/templates; MCreator/NeoGradle use resources) ---
Write-Step 'Updating neoforge.mods.toml'
$tomlTemplatePath = Join-Path $ProjectRoot 'src\main\templates\META-INF\neoforge.mods.toml'
$tomlResourcesPath = Join-Path $ProjectRoot 'src\main\resources\META-INF\neoforge.mods.toml'
$tomlPaths = @()
if (Test-Path $tomlTemplatePath) {
    $tomlPaths += $tomlTemplatePath
    Write-Info 'ModDevGradle / template-style mods.toml detected (src/main/templates)'
}
if ((Test-Path $tomlResourcesPath) -or (-not (Test-Path $tomlTemplatePath))) {
    # Only write resources path when templates are absent, or when both already exist (patch both)
    if (Test-Path $tomlResourcesPath) {
        $tomlPaths += $tomlResourcesPath
    }
    elseif (-not (Test-Path $tomlTemplatePath)) {
        $tomlPaths += $tomlResourcesPath
    }
}
if ($tomlPaths.Count -eq 0) {
    $tomlPaths = @($tomlResourcesPath)
}

foreach ($tomlPath in $tomlPaths) {
    # Never force-write our scaffold template over an MDG project that already has templates
    $force = $ForceTomlTemplate -and -not (Test-Path $tomlTemplatePath)
    $tomlResult = Update-ModsToml -TomlPath $tomlPath `
        -TemplatePath (Join-Path $Templates 'neoforge.mods.toml.template') `
        -Props $props `
        -NeoVersion $NeoVersion `
        -MinecraftVersion $MinecraftVersion `
        -MinecraftVersionRange $MinecraftVersionRange `
        -ForceTemplate:$force
    $relToml = $tomlPath.Substring($ProjectRoot.Length).TrimStart('\', '/')
    Write-Ok "${relToml}: $tomlResult"
}

# --- pack.mcmeta ---
Write-Step 'Updating pack.mcmeta'
$packPath = Join-Path $ProjectRoot 'src\main\resources\pack.mcmeta'
$desc = if ($props['mod_description']) { $props['mod_description'] } else { "$($props['mod_name']) $MinecraftVersion" }
Update-PackMcmeta -File $packPath -PackFormat $PackFormat -Description $desc
Write-Ok "pack.mcmeta format $PackFormat"

# --- mcreator ---
Write-Step 'Updating MCreator workspace metadata (if any)'
Update-McreatorWorkspace -ProjectRoot $ProjectRoot -MinecraftVersion $MinecraftVersion -ModVersion $ModVersion -Description $desc

# --- Java API transforms ---
if (-not $SkipJavaTransforms) {
    Write-Step 'Applying Java API transforms (26.1 -> 26.2)'
    $javaRoot = Join-Path $ProjectRoot 'src\main\java'
    if (Test-Path $javaRoot) {
        $result = Invoke-JavaApiTransforms -Root $ProjectRoot -DryRun:$DryRun -VerboseLog
        Write-Ok "Touched $($result.FilesTouched) Java file(s)"
        if ($result.Report.Count -gt 0 -and $result.Report.Count -le 40) {
            foreach ($r in $result.Report) {
                Write-Info "$($r.File)  ($($r.Transforms))"
            }
        }
        elseif ($result.Report.Count -gt 40) {
            Write-Info "($($result.Report.Count) files changed; listing suppressed)"
        }
    }
    else {
        Write-Warn2 'No src/main/java - skipped Java transforms'
    }
}
else {
    Write-Info 'Java transforms skipped'
}

# --- Client items (MC 26.x requires assets/<ns>/items/<id>.json) ---
Write-Step 'Ensuring client item definitions (items/*.json)'
$clientItemResult = Ensure-ClientItemDefinitions -ProjectRoot $ProjectRoot -DryRun:$DryRun
if ($clientItemResult.Created -gt 0) {
    Write-Ok "Created $($clientItemResult.Created) missing client item file(s)"
}
elseif ($clientItemResult.Scanned -eq 0) {
    Write-Info 'No models/item found - skipped client items'
}
else {
    Write-Info "Client items OK ($($clientItemResult.Existing) already present)"
}
if ($clientItemResult.ModelParentFixes -gt 0) {
    Write-Ok "Fixed $($clientItemResult.ModelParentFixes) model parent path(s) (minecraft: namespace / spawn egg)"
}

# --- Summary notes ---
Write-Step 'Done'
$summary = @"
Next steps:
  1. Ensure JDK 25 is installed (Minecraft 26.2 requirement).
  2. From the project folder:
       .\gradlew.bat compileJava
       .\gradlew.bat build
       .\gradlew.bat runClient
  3. Fix any remaining compile errors not covered by automatic transforms
     (custom mixins, reflection, third-party APIs).
  4. MCreator: official generators may still target 26.1.x. Prefer building
     with Gradle; regenerating in MCreator can overwrite converted files.

Known automatic Java transforms:
  - emissiveRendering((bs,br,bp)->...)  =>  emissiveRendering(bs -> ...)
  - mc.setScreen(...)                   =>  mc.gui.setScreen(...)
  - VertexFormat.Mode.*                 =>  PrimitiveTopology.*
  - getMainRenderTarget()               =>  gameRenderer.mainRenderTarget()
  - createRenderPass(... OptionalInt)   =>  Optional.empty()
  - drawIndexed 4-arg (MCreator sky)    =>  5-arg form
  - setVertexBuffer(i, buf)             =>  setVertexBuffer(i, buf.slice())
  - writeTransform(modelViewStack,      =>  writeTransform(new Matrix4f(modelViewStack),
  - pos.getCenter()                     =>  Vec3.atCenterOf(pos)

Also auto-scaffolds missing assets/<ns>/items/*.json client item defs (MC 26.x).

Supports: MCreator workspaces, NeoGradle MDK, ModDevGradle hand ports.

Converter path: $ToolRoot
"@
Write-Host $summary -ForegroundColor Gray

# --- optional compile/build ---
if ($Compile -or $Build) {
    if ($DryRun) {
        $task = if ($Build) { 'build' } else { 'compileJava' }
        Write-Info "Skipping Gradle $task during dry run (no files written). Re-run without -DryRun to compile."
    }
    else {
        $gradlew = Join-Path $ProjectRoot 'gradlew.bat'
        if (-not (Test-Path $gradlew)) {
            Write-Warn2 'Cannot compile: gradlew.bat missing. Use -FetchWrapper.'
            exit 2
        }
        $task = if ($Build) { 'build' } else { 'compileJava' }
        Write-Step "Running $task"
        Push-Location $ProjectRoot
        try {
            & .\gradlew.bat $task --no-daemon
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle $task failed with exit code $LASTEXITCODE"
            }
            Write-Ok "Gradle $task succeeded"
        }
        finally {
            Pop-Location
        }
    }
}

if ($WorkingOnCopy -and -not $DryRun) {
    Write-Host ""
    Write-Host "Conversion wrote to: $ProjectRoot" -ForegroundColor Green
    Write-Host "Original unchanged:  $SourceRoot" -ForegroundColor Green
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete - re-run without -DryRun to apply changes." -ForegroundColor Yellow
}
