# Java source transforms for Minecraft / NeoForge 26.1.x -> 26.2

function Get-JavaApiTransformNames {
    return @(
        'emissiveRendering-predicate',
        'setScreen-via-gui',
        'VertexFormat.Mode-to-PrimitiveTopology',
        'getMainRenderTarget',
        'createRenderPass-OptionalInt',
        'drawIndexed-4arg-to-5arg-base0',
        'drawIndexed-4arg-to-5arg-baseVertex',
        'setVertexBuffer-slice',
        'writeTransform-Matrix4f-copy',
        'getSequentialBuffer-PrimitiveTopology',
        'BlockPos.getCenter-to-Vec3.atCenterOf'
    )
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

function Invoke-SingleFileTransforms {
    param([string]$Text)

    $hits = New-Object System.Collections.Generic.List[string]
    $needsPrimitiveTopology = $false
    $needsOptional = $false
    $needsMatrix4f = $false
    $needsVec3 = $false
    $result = $Text

    # 1) emissiveRendering((bs, br, bp) ->  =>  emissiveRendering(bs ->
    $next = [regex]::Replace($result, 'emissiveRendering\(\(\s*(\w+)\s*,\s*\w+\s*,\s*\w+\s*\)\s*->', 'emissiveRendering($1 ->')
    if ($next -ne $result) { $hits.Add('emissiveRendering-predicate') | Out-Null; $result = $next }

    # 2) foo.setScreen( => foo.gui.setScreen(  (skip if already .gui.setScreen)
    $next = [regex]::Replace($result, '(\w+)\.setScreen\(', {
        param($m)
        if ($m.Groups[1].Value -eq 'gui') { return $m.Value }
        # avoid double-prefix: something.gui.setScreen already has setScreen after gui — handled above
        return $m.Groups[1].Value + '.gui.setScreen('
    })
    # Fix accidental gui.gui.setScreen if re-run
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
    #    avoid double if already gameRenderer.mainRenderTarget
    $next = [regex]::Replace($result, '(?<!gameRenderer)\.getMainRenderTarget\(\)', '.gameRenderer.mainRenderTarget()')
    if ($next -ne $result) { $hits.Add('getMainRenderTarget') | Out-Null; $result = $next }

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
        # Don't touch if someone passed a method call style we can't parse; bare id only
        return ".setVertexBuffer($($m.Groups[1].Value), $id.slice())"
    })
    # Undo if we double-sliced: foo.slice().slice()
    $next = $next -replace '\.slice\(\)\.slice\(\)', '.slice()'
    if ($next -ne $result) { $hits.Add('setVertexBuffer-slice') | Out-Null; $result = $next }

    # 9) writeTransform(modelViewStack, => writeTransform(new Matrix4f(modelViewStack),
    $next = [regex]::Replace(
        $result,
        'writeTransform\(\s*modelViewStack\s*,',
        'writeTransform(new Matrix4f(modelViewStack),'
    )
    # idempotent
    $next = $next -replace 'writeTransform\(\s*new Matrix4f\(new Matrix4f\(modelViewStack\)\)\s*,', 'writeTransform(new Matrix4f(modelViewStack),'
    if ($next -ne $result) {
        $hits.Add('writeTransform-Matrix4f-copy') | Out-Null
        $needsMatrix4f = $true
        $result = $next
    }

    # 10) leftover getSequentialBuffer(VertexFormat.Mode.X) if Mode rename missed quotes
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
    #     Also handle chained: pos.getCenter() in AABB.ofSize etc.
    $next = [regex]::Replace(
        $result,
        '(?<![\w.])([a-zA-Z_]\w*(?:\.\w+)*)\.getCenter\(\)',
        {
            param($m)
            $recv = $m.Groups[1].Value
            # Skip if already Vec3.atCenterOf(...)
            if ($recv -match 'atCenterOf$') { return $m.Value }
            return "Vec3.atCenterOf($recv)"
        }
    )
    # idempotent: Vec3.atCenterOf(Vec3.atCenterOf(x))
    $next = [regex]::Replace($next, 'Vec3\.atCenterOf\(\s*Vec3\.atCenterOf\(([^)]+)\)\s*\)', 'Vec3.atCenterOf($1)')
    if ($next -ne $result) {
        $hits.Add('BlockPos.getCenter-to-Vec3.atCenterOf') | Out-Null
        $needsVec3 = $true
        $result = $next
    }

    if ($hits.Count -eq 0) {
        return [pscustomobject]@{ Text = $Text; Hits = @(); Changed = $false }
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
    if ($result -match 'import java\.util\.OptionalInt;' -and $result -notmatch 'OptionalInt\.') {
        $result = $result -replace "(?m)^import java\.util\.OptionalInt;\r?\n", ''
    }

    return [pscustomobject]@{
        Text    = $result
        Hits    = @($hits)
        Changed = ($result -ne $Text)
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
    $filesTouched = 0

    foreach ($file in $files) {
        $original = [System.IO.File]::ReadAllText($file.FullName)
        $applied = Invoke-SingleFileTransforms -Text $original
        if (-not $applied.Changed) { continue }

        $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
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
        FilesTouched = $filesTouched
        Report       = $report
    }
}
