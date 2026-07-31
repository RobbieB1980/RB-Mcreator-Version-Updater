# Java source transforms for Minecraft / NeoForge 26.1.x -> 26.2

function Get-JavaApiTransformNames {
    return @(
        'emissiveRendering-predicate',
        'setScreen-via-gui',
        'VertexFormat.Mode-to-PrimitiveTopology',
        'getMainRenderTarget',
        'getMainCamera',
        'minecraft-renderBuffers-via-gameRenderer',
        'createRenderPass-OptionalInt',
        'drawIndexed-4arg-to-5arg-base0',
        'drawIndexed-4arg-to-5arg-baseVertex',
        'setVertexBuffer-slice',
        'writeTransform-Matrix4f-copy',
        'getSequentialBuffer-PrimitiveTopology',
        'BlockPos.getCenter-to-Vec3.atCenterOf',
        'EntityType-fields-to-EntityTypes',
        'Items-ColorCollection',
        'Blocks-ColorCollection'
    )
}

function Get-DyeColorAccessors {
    # DyeColor name (SCREAMING) -> ColorCollection record accessor
    return [ordered]@{
        'WHITE'      = 'white'
        'ORANGE'     = 'orange'
        'MAGENTA'    = 'magenta'
        'LIGHT_BLUE' = 'lightBlue'
        'YELLOW'     = 'yellow'
        'LIME'       = 'lime'
        'PINK'       = 'pink'
        'GRAY'       = 'gray'
        'LIGHT_GRAY' = 'lightGray'
        'CYAN'       = 'cyan'
        'PURPLE'     = 'purple'
        'BLUE'       = 'blue'
        'BROWN'      = 'brown'
        'GREEN'      = 'green'
        'RED'        = 'red'
        'BLACK'      = 'black'
    }
}

function Get-ColorCollectionFieldMap {
    <#
    .SYNOPSIS
      Build Items./Blocks.COLOR_SUFFIX => Collection.accessor() replacements for 26.2 ColorCollection.
    #>
    $colors = Get-DyeColorAccessors
    # suffix on old field name -> (new collection field, prefix class)
    $itemGroups = @(
        @{ Suffix = 'WOOL';               Collection = 'WOOL' },
        @{ Suffix = 'CARPET';             Collection = 'CARPET' },
        @{ Suffix = 'BED';                Collection = 'BED' },
        @{ Suffix = 'CONCRETE';           Collection = 'CONCRETE' },
        @{ Suffix = 'CONCRETE_POWDER';    Collection = 'CONCRETE_POWDER' },
        @{ Suffix = 'STAINED_GLASS';      Collection = 'STAINED_GLASS' },
        @{ Suffix = 'STAINED_GLASS_PANE'; Collection = 'STAINED_GLASS_PANE' },
        @{ Suffix = 'TERRACOTTA';         Collection = 'DYED_TERRACOTTA' },
        @{ Suffix = 'GLAZED_TERRACOTTA';  Collection = 'GLAZED_TERRACOTTA' },
        @{ Suffix = 'SHULKER_BOX';        Collection = 'DYED_SHULKER_BOX' },
        @{ Suffix = 'CANDLE';             Collection = 'DYED_CANDLE' },
        @{ Suffix = 'BANNER';             Collection = 'BANNER' },
        @{ Suffix = 'DYE';                Collection = 'DYE' },
        @{ Suffix = 'HARNESS';            Collection = 'HARNESS' },
        @{ Suffix = 'BUNDLE';             Collection = 'DYED_BUNDLE' }
    )
    $blockGroups = @(
        @{ Suffix = 'WOOL';               Collection = 'WOOL' },
        @{ Suffix = 'CARPET';             Collection = 'CARPET' },
        @{ Suffix = 'BED';                Collection = 'BED' },
        @{ Suffix = 'CONCRETE';           Collection = 'CONCRETE' },
        @{ Suffix = 'CONCRETE_POWDER';    Collection = 'CONCRETE_POWDER' },
        @{ Suffix = 'STAINED_GLASS';      Collection = 'STAINED_GLASS' },
        @{ Suffix = 'STAINED_GLASS_PANE'; Collection = 'STAINED_GLASS_PANE' },
        @{ Suffix = 'TERRACOTTA';         Collection = 'DYED_TERRACOTTA' },
        @{ Suffix = 'GLAZED_TERRACOTTA';  Collection = 'GLAZED_TERRACOTTA' },
        @{ Suffix = 'SHULKER_BOX';        Collection = 'DYED_SHULKER_BOX' },
        @{ Suffix = 'CANDLE';             Collection = 'DYED_CANDLE' },
        @{ Suffix = 'BANNER';             Collection = 'BANNER' }
    )

    $map = [ordered]@{}
    foreach ($g in $itemGroups) {
        foreach ($c in $colors.Keys) {
            $old = "Items.${c}_$($g.Suffix)"
            $new = "Items.$($g.Collection).$($colors[$c])()"
            $map[$old] = $new
        }
    }
    foreach ($g in $blockGroups) {
        foreach ($c in $colors.Keys) {
            $old = "Blocks.${c}_$($g.Suffix)"
            $new = "Blocks.$($g.Collection).$($colors[$c])()"
            $map[$old] = $new
        }
    }
    # Non-color renames that commonly trip 26.1 decompiles
    $map['Blocks.CHAIN'] = 'Blocks.IRON_CHAIN'
    $map['Items.CHAIN'] = 'Items.IRON_CHAIN'
    return $map
}

function Add-JavaImport {
    param([string]$Source, [string]$Import)
    $importLine = "import $Import;"
    if ($Source -match [regex]::Escape($importLine)) { return $Source }

    if ($Source -match '(?s)(package\s+[\w\.]+;\s*)') {
        $pkg = $Matches[1]
        $rest = $Source.Substring($pkg.Length)
        if ($rest -match '(?s)^((?:\s*import\s+[\w\.\*]+;\s*)+)') {
            $imports = $Matches[1]
            $after = $rest.Substring($imports.Length)
            return $pkg + $imports + $importLine + "`r`n" + $after
        }
        return $pkg + "`r`n" + $importLine + "`r`n" + $rest
    }
    return $importLine + "`r`n" + $Source
}

function Find-JavaApiResidualWarnings {
    <#
    .SYNOPSIS
      Patterns that still need manual 26.2 porting (feature rendering, etc.).
    #>
    param([string]$Text)

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($Text -match '\bMultiBufferSource\b') {
        $warnings.Add('MultiBufferSource removed in 26.2 — use SubmitNodeCollector / submitShapeOutline / SubmitCustomGeometryEvent') | Out-Null
    }
    if ($Text -match '\.bufferSource\s*\(') {
        $warnings.Add('RenderBuffers.bufferSource() removed — world geometry must submit via SubmitNodeCollector') | Out-Null
    }
    if ($Text -match 'RenderLevelStageEvent' -and $Text -match '(getBuffer|VertexConsumer|bufferSource)') {
        $warnings.Add('RenderLevelStageEvent + direct buffers: prefer SubmitCustomGeometryEvent for custom outlines') | Out-Null
    }
    if ($Text -match 'import\s+net\.minecraft\.client\.renderer\.MultiBufferSource') {
        $warnings.Add('Stale MultiBufferSource import') | Out-Null
    }
    return @($warnings)
}

function Invoke-SingleFileTransforms {
    param([string]$Text)

    $hits = New-Object System.Collections.Generic.List[string]
    $needsPrimitiveTopology = $false
    $needsOptional = $false
    $needsMatrix4f = $false
    $needsVec3 = $false
    $needsEntityTypes = $false
    $result = $Text

    # 1) emissiveRendering((bs, br, bp) ->  =>  emissiveRendering(bs ->
    $next = [regex]::Replace($result, 'emissiveRendering\(\(\s*(\w+)\s*,\s*\w+\s*,\s*\w+\s*\)\s*->', 'emissiveRendering($1 ->')
    if ($next -ne $result) { $hits.Add('emissiveRendering-predicate') | Out-Null; $result = $next }

    # 2) foo.setScreen( => foo.gui.setScreen(  (skip if already .gui.setScreen)
    $next = [regex]::Replace($result, '(\w+)\.setScreen\(', {
        param($m)
        if ($m.Groups[1].Value -eq 'gui') { return $m.Value }
        return $m.Groups[1].Value + '.gui.setScreen('
    })
    $next = $next -replace '(\w+)\.gui\.gui\.setScreen\(', '$1.gui.setScreen('
    if ($next -ne $result) { $hits.Add('setScreen-via-gui') | Out-Null; $result = $next }

    # 3) VertexFormat.Mode.X => PrimitiveTopology.X
    $next = $result -replace 'VertexFormat\.Mode\.', 'PrimitiveTopology.'
    if ($next -ne $result) {
        $hits.Add('VertexFormat.Mode-to-PrimitiveTopology') | Out-Null
        $needsPrimitiveTopology = $true
        $result = $next
    }

    # 4) .getMainRenderTarget() => .gameRenderer.mainRenderTarget()
    $next = [regex]::Replace($result, '(?<!gameRenderer)\.getMainRenderTarget\(\)', '.gameRenderer.mainRenderTarget()')
    if ($next -ne $result) { $hits.Add('getMainRenderTarget') | Out-Null; $result = $next }

    # 4b) .getMainCamera() => .mainCamera()  (GameRenderer field accessor rename)
    $next = $result -replace '\.getMainCamera\(\)', '.mainCamera()'
    if ($next -ne $result) { $hits.Add('getMainCamera') | Out-Null; $result = $next }

    # 4c) Minecraft.getInstance().renderBuffers() => gameRenderer.renderBuffers()
    #     RenderBuffers.bufferSource() is gone; residual scanner still warns on bufferSource().
    $next = [regex]::Replace(
        $result,
        'Minecraft\.getInstance\(\)\.renderBuffers\(\)',
        'Minecraft.getInstance().gameRenderer.renderBuffers()'
    )
    # Idempotent if already rewritten
    $next = $next -replace 'Minecraft\.getInstance\(\)\.gameRenderer\.gameRenderer\.renderBuffers\(\)',
        'Minecraft.getInstance().gameRenderer.renderBuffers()'
    if ($next -ne $result) {
        $hits.Add('minecraft-renderBuffers-via-gameRenderer') | Out-Null
        $result = $next
    }

    # 5) createRenderPass(..., OptionalInt.empty() => Optional.empty()
    $next = [regex]::Replace(
        $result,
        'createRenderPass\(([^,]+),\s*([^,]+),\s*OptionalInt\.empty\(\)',
        'createRenderPass($1, $2, Optional.empty()'
    )
    if ($next -ne $result) {
        $hits.Add('createRenderPass-OptionalInt') | Out-Null
        $needsOptional = $true
        $result = $next
    }

    # 6) drawIndexed(0, 0, N, 1) => drawIndexed(N, 1, 0, 0, 0)
    $next = [regex]::Replace($result, '\.drawIndexed\(\s*0\s*,\s*0\s*,\s*(\d+)\s*,\s*1\s*\)', '.drawIndexed($1, 1, 0, 0, 0)')
    if ($next -ne $result) { $hits.Add('drawIndexed-4arg-to-5arg-base0') | Out-Null; $result = $next }

    # 7) drawIndexed(baseVertex, 0, N, 1) => drawIndexed(N, 1, 0, baseVertex, 0)
    $next = [regex]::Replace(
        $result,
        '\.drawIndexed\(\s*([a-zA-Z_][\w\.]*)\s*,\s*0\s*,\s*(\d+)\s*,\s*1\s*\)',
        '.drawIndexed($2, 1, 0, $1, 0)'
    )
    if ($next -ne $result) { $hits.Add('drawIndexed-4arg-to-5arg-baseVertex') | Out-Null; $result = $next }

    # 8) setVertexBuffer(i, bareIdent) => setVertexBuffer(i, bareIdent.slice())
    $next = [regex]::Replace($result, '\.setVertexBuffer\(\s*(\d+)\s*,\s*([a-zA-Z_]\w*)\s*\)', {
        param($m)
        $id = $m.Groups[2].Value
        return ".setVertexBuffer($($m.Groups[1].Value), $id.slice())"
    })
    $next = $next -replace '\.slice\(\)\.slice\(\)', '.slice()'
    if ($next -ne $result) { $hits.Add('setVertexBuffer-slice') | Out-Null; $result = $next }

    # 9) writeTransform(modelViewStack, => writeTransform(new Matrix4f(modelViewStack),
    $next = [regex]::Replace(
        $result,
        'writeTransform\(\s*modelViewStack\s*,',
        'writeTransform(new Matrix4f(modelViewStack),'
    )
    $next = $next -replace 'writeTransform\(\s*new Matrix4f\(new Matrix4f\(modelViewStack\)\)\s*,', 'writeTransform(new Matrix4f(modelViewStack),'
    if ($next -ne $result) {
        $hits.Add('writeTransform-Matrix4f-copy') | Out-Null
        $needsMatrix4f = $true
        $result = $next
    }

    # 10) leftover getSequentialBuffer(VertexFormat.Mode.X)
    $next = [regex]::Replace(
        $result,
        'getSequentialBuffer\(\s*VertexFormat\.Mode\.(\w+)\s*\)',
        'getSequentialBuffer(PrimitiveTopology.$1)'
    )
    if ($next -ne $result) {
        $hits.Add('getSequentialBuffer-PrimitiveTopology') | Out-Null
        $needsPrimitiveTopology = $true
        $result = $next
    }

    # 11) BlockPos.getCenter() removed in 26.2 => Vec3.atCenterOf(pos)
    $next = [regex]::Replace(
        $result,
        '(?<![\w.])([a-zA-Z_]\w*(?:\.\w+)*)\.getCenter\(\)',
        {
            param($m)
            $recv = $m.Groups[1].Value
            if ($recv -match 'atCenterOf$') { return $m.Value }
            return "Vec3.atCenterOf($recv)"
        }
    )
    $next = [regex]::Replace($next, 'Vec3\.atCenterOf\(\s*Vec3\.atCenterOf\(([^)]+)\)\s*\)', 'Vec3.atCenterOf($1)')
    if ($next -ne $result) {
        $hits.Add('BlockPos.getCenter-to-Vec3.atCenterOf') | Out-Null
        $needsVec3 = $true
        $result = $next
    }

    # 12) EntityType.VANILLA_FIELD => EntityTypes.VANILLA_FIELD (registry objects moved in 26.2)
    #     Only SCREAMING_SNAKE constants; leaves EntityType.Builder / generics alone.
    $next = [regex]::Replace(
        $result,
        '\bEntityType\.([A-Z][A-Z0-9_]*)\b',
        {
            param($m)
            $field = $m.Groups[1].Value
            # Skip nested type names that are not registry entries (none currently SCREAMING on EntityType besides constants)
            return "EntityTypes.$field"
        }
    )
    if ($next -ne $result) {
        $hits.Add('EntityType-fields-to-EntityTypes') | Out-Null
        $needsEntityTypes = $true
        $result = $next
    }

    # 13) Items/Blocks color fields => ColorCollection accessors
    $colorMap = Get-ColorCollectionFieldMap
    $colorHit = $false
    $blockColorHit = $false
    foreach ($old in $colorMap.Keys) {
        if ($result.Contains($old)) {
            $result = $result.Replace($old, $colorMap[$old])
            if ($old.StartsWith('Items.')) { $colorHit = $true }
            if ($old.StartsWith('Blocks.')) { $blockColorHit = $true }
        }
    }
    if ($colorHit) { $hits.Add('Items-ColorCollection') | Out-Null }
    if ($blockColorHit) { $hits.Add('Blocks-ColorCollection') | Out-Null }

    $warnings = Find-JavaApiResidualWarnings -Text $result

    if ($hits.Count -eq 0) {
        return [pscustomobject]@{
            Text     = $Text
            Hits     = @()
            Warnings = $warnings
            Changed  = $false
        }
    }

    if ($needsPrimitiveTopology -and $result -notmatch 'import com\.mojang\.blaze3d\.PrimitiveTopology;') {
        $result = Add-JavaImport -Source $result -Import 'com.mojang.blaze3d.PrimitiveTopology'
    }
    if ($needsOptional -and $result -notmatch 'import java\.util\.Optional;') {
        $result = Add-JavaImport -Source $result -Import 'java.util.Optional'
    }
    if ($needsMatrix4f -and $result -notmatch 'import org\.joml\.Matrix4f;') {
        $result = Add-JavaImport -Source $result -Import 'org.joml.Matrix4f'
    }
    if ($needsVec3 -and $result -notmatch 'import net\.minecraft\.world\.phys\.Vec3;') {
        $result = Add-JavaImport -Source $result -Import 'net.minecraft.world.phys.Vec3'
    }
    if ($needsEntityTypes -and $result -notmatch 'import net\.minecraft\.world\.entity\.EntityTypes;') {
        $result = Add-JavaImport -Source $result -Import 'net.minecraft.world.entity.EntityTypes'
    }
    if ($result -match 'import java\.util\.OptionalInt;' -and $result -notmatch 'OptionalInt\.') {
        $result = $result -replace "(?m)^import java\.util\.OptionalInt;\r?\n", ''
    }

    # Re-scan residuals after rewrites
    $warnings = Find-JavaApiResidualWarnings -Text $result

    return [pscustomobject]@{
        Text     = $result
        Hits     = @($hits)
        Warnings = $warnings
        Changed  = ($result -ne $Text)
    }
}

function Invoke-JavaApiTransforms {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$DryRun,
        [switch]$VerboseLog
    )

    $files = Get-ChildItem -Path $Root -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\build\\|\\run\\|\\\.gradle\\|\\\.converter-backups\\' }

    $report = New-Object System.Collections.Generic.List[object]
    $warningReport = New-Object System.Collections.Generic.List[object]
    $filesTouched = 0

    foreach ($file in $files) {
        $original = [System.IO.File]::ReadAllText($file.FullName)
        $applied = Invoke-SingleFileTransforms -Text $original
        $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/')

        if ($applied.Warnings -and $applied.Warnings.Count -gt 0) {
            $warningReport.Add([pscustomobject]@{
                File     = $rel
                Warnings = ($applied.Warnings -join ' | ')
            }) | Out-Null
            if ($VerboseLog) {
                Write-Host "  WARN  $rel  [$($applied.Warnings -join '; ')]" -ForegroundColor Yellow
            }
        }

        if (-not $applied.Changed) { continue }

        $report.Add([pscustomobject]@{
            File       = $rel
            Transforms = ($applied.Hits -join ', ')
        }) | Out-Null
        $filesTouched++

        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($file.FullName, $applied.Text)
        }

        if ($VerboseLog) {
            Write-Host "  JAVA  $rel  [$($applied.Hits -join ', ')]"
        }
    }

    return [pscustomobject]@{
        FilesTouched  = $filesTouched
        Report        = $report
        WarningReport = $warningReport
    }
}
