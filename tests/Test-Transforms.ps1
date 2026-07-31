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
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.item.Items;

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
        Camera camera = Minecraft.getInstance().gameRenderer.getMainCamera();
        var buffers = Minecraft.getInstance().renderBuffers().bufferSource();
    }
    void menu() {
        var type = EntityType.CHEST_MINECART;
        var wool = Items.WHITE_WOOL;
        var glaze = Items.MAGENTA_GLAZED_TERRACOTTA;
        var pos = blockPos.getCenter();
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
Assert-Contains $r.Text '.mainCamera()' 'mainCamera'
Assert-NotContains $r.Text 'getMainCamera()' 'getMainCamera removed'
Assert-Contains $r.Text 'Minecraft.getInstance().gameRenderer.renderBuffers()' 'renderBuffers via gameRenderer'
Assert-Contains $r.Text 'EntityTypes.CHEST_MINECART' 'EntityTypes'
Assert-Contains $r.Text 'import net.minecraft.world.entity.EntityTypes;' 'import EntityTypes'
Assert-Contains $r.Text 'Items.WOOL.white()' 'WHITE_WOOL'
Assert-Contains $r.Text 'Items.GLAZED_TERRACOTTA.magenta()' 'MAGENTA_GLAZED_TERRACOTTA'
Assert-Contains $r.Text 'Vec3.atCenterOf(blockPos)' 'getCenter'
Assert-NotContains $r.Text 'Items.WHITE_WOOL' 'old WHITE_WOOL gone'
Assert-NotContains $r.Text 'EntityType.CHEST_MINECART' 'old EntityType field gone'

# Residual warnings for MultiBufferSource-era APIs
if (-not ($r.Warnings -and ($r.Warnings -join ' ') -match 'bufferSource')) {
    throw 'FAIL [residual]: expected bufferSource warning'
}
Write-Host "  OK  residual bufferSource warning" -ForegroundColor Green

# Color map sanity
$map = Get-ColorCollectionFieldMap
if ($map['Items.BLACK_WOOL'] -ne 'Items.WOOL.black()') { throw 'FAIL color map Items.BLACK_WOOL' }
if ($map['Blocks.RED_BED'] -ne 'Blocks.BED.red()') { throw 'FAIL color map Blocks.RED_BED' }
Write-Host "  OK  color collection map" -ForegroundColor Green

# Must not rewrite EntityType.Builder (mixed-case) to EntityTypes.B...
$builderSample = 'EntityType.Builder.of(MinecartChest::new, MobCategory.MISC)'
$rb = Invoke-SingleFileTransforms -Text $builderSample
Assert-Contains $rb.Text 'EntityType.Builder' 'EntityType.Builder preserved'
Assert-NotContains $rb.Text 'EntityTypes.Builder' 'not EntityTypes.Builder'
Assert-NotContains $rb.Text 'EntityTypes.B' 'not partial EntityTypes.B'

# Idempotent second pass
$r2 = Invoke-SingleFileTransforms -Text $r.Text
if ($r2.Changed -and ($r2.Text -ne $r.Text)) {
    Assert-NotContains $r2.Text 'gui.gui.setScreen' 'no double gui'
    Assert-NotContains $r2.Text 'slice().slice()' 'no double slice'
    Assert-NotContains $r2.Text 'EntityTypes.EntityTypes' 'no double EntityTypes'
    Assert-NotContains $r2.Text 'gameRenderer.gameRenderer' 'no double gameRenderer'
}
Write-Host "All transform tests passed." -ForegroundColor Green
