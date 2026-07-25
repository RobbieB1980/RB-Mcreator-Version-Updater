# Unit-style checks for Java transform rules (no project required)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\JavaApiTransforms.ps1"

function Assert-Contains($hay, $needle, $label) {
    if ($hay -notlike "*$needle*") {
        throw "FAIL [$label]: expected to contain: $needle`nActual:`n$hay"
    }
    Write-Host "  OK  $label" -ForegroundColor Green
}

function Assert-NotContains($hay, $needle, $label) {
    if ($hay -like "*$needle*") {
        throw "FAIL [$label]: should NOT contain: $needle`nActual:`n$hay"
    }
    Write-Host "  OK  $label" -ForegroundColor Green
}

$sample = @'
package net.example.mod;

import java.util.OptionalInt;

public class Sample {
    public Sample(Props p) {
        super(p.emissiveRendering((bs, br, bp) -> true));
    }
    void open(Minecraft mc) {
        mc.setScreen(new InventoryScreen(mc.player));
    }
    void render() {
        BufferBuilder b = new BufferBuilder(buf, VertexFormat.Mode.QUADS, format);
        GpuTextureView color = mc.getMainRenderTarget().getColorTextureView();
        createRenderPass(() -> "x", color, OptionalInt.empty(), depth, OptionalDouble.empty());
        renderPass.setVertexBuffer(0, sunBuffer);
        renderPass.drawIndexed(0, 0, 6, 1);
        renderPass.drawIndexed(baseVertex, 0, 6, 1);
        writeTransform(modelViewStack, new Vector4f(1,1,1,1), new Vector3f(), new Matrix4f());
    }
}
'@

Write-Host "Running transform self-tests..." -ForegroundColor Cyan
$r = Invoke-SingleFileTransforms -Text $sample
if (-not $r.Changed) { throw 'Expected transforms to change sample' }

Assert-Contains $r.Text 'emissiveRendering(bs -> true)' 'emissiveRendering'
Assert-Contains $r.Text 'mc.gui.setScreen(' 'setScreen'
Assert-NotContains $r.Text 'VertexFormat.Mode' 'Mode removed'
Assert-Contains $r.Text 'PrimitiveTopology.QUADS' 'PrimitiveTopology'
Assert-Contains $r.Text 'gameRenderer.mainRenderTarget()' 'mainRenderTarget'
Assert-Contains $r.Text 'Optional.empty()' 'Optional'
Assert-Contains $r.Text 'setVertexBuffer(0, sunBuffer.slice())' 'slice'
Assert-Contains $r.Text 'drawIndexed(6, 1, 0, 0, 0)' 'drawIndexed base0'
Assert-Contains $r.Text 'drawIndexed(6, 1, 0, baseVertex, 0)' 'drawIndexed baseVertex'
Assert-Contains $r.Text 'writeTransform(new Matrix4f(modelViewStack),' 'writeTransform'
Assert-Contains $r.Text 'import com.mojang.blaze3d.PrimitiveTopology;' 'import PrimitiveTopology'

# Idempotent second pass
$r2 = Invoke-SingleFileTransforms -Text $r.Text
if ($r2.Changed -and ($r2.Text -ne $r.Text)) {
    # setScreen / slice may be no-ops; any change should not double-prefix
    Assert-NotContains $r2.Text 'gui.gui.setScreen' 'no double gui'
    Assert-NotContains $r2.Text 'slice().slice()' 'no double slice'
}
Write-Host "All transform tests passed." -ForegroundColor Green
