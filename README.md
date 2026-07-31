# NeoForge 26.2 Converter

Reusable migration tool for **Minecraft 26.1.x NeoForge / MCreator Gradle workspaces → Minecraft 26.2 + NeoForge 26.2.x**.

Built from the `robmod` upgrade (26.1.2 → `neoforge-26.2.0.32-beta`).

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- Network access (only if you use `-FetchWrapper`)
- **JDK 25** to compile/run after conversion

## Quick start

### GUI (recommended)

Double-click **`Launch-GUI.bat`**, or:

```powershell
.\Convert-ToNeoForge262-GUI.ps1
```

- **Browse** for the input MCreator/Gradle project
- **Browse** (or accept the suggested) **output folder**
- Conversion always runs on a **copy** — the original directory is never modified

### CLI

```powershell
cd path\to\RB-Mcreator-Version-Updater

# Preview only
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -DryRun

# Copy to a new folder, then convert (original untouched)
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -FetchWrapper

# In-place convert (modifies Path) + compile
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -FetchWrapper -Compile

# Custom NeoForge build
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -NeoVersion "26.2.0.32-beta" -Build
```

## What it does

| Step | Action |
|------|--------|
| Backup | Zips `src/`, Gradle files, `elements/`, `*.mcreator` → `.converter-backups/` |
| `gradle.properties` | Sets `minecraft_version=26.2`, `neo_version=…`, Java heap, mod metadata |
| Gradle scaffold | Creates `build.gradle` / `settings.gradle` if missing (NeoGradle **7.1.38**, Java **25**) |
| Existing `build.gradle` | Bumps NeoGradle plugin version + Java toolchain to 25 when present |
| Wrapper | Optional: pulls `gradlew` from [MDK-26.2-NeoGradle](https://github.com/NeoForgeMDKs/MDK-26.2-NeoGradle) |
| `neoforge.mods.toml` | Updates NeoForge/Minecraft dependency ranges (or writes property-expansion template) |
| `pack.mcmeta` | Sets pack format **107** (26.2) |
| `*.mcreator` | Updates `currentGenerator` / version / description when found |
| Java sources | Applies known 26.1 → 26.2 API rewrites under `src/main/java` |

## Automatic Java rewrites

| 26.1 pattern | 26.2 result |
|--------------|-------------|
| `emissiveRendering((bs, br, bp) -> true)` | `emissiveRendering(bs -> true)` |
| `mc.setScreen(...)` | `mc.gui.setScreen(...)` |
| `VertexFormat.Mode.QUADS` | `PrimitiveTopology.QUADS` |
| `.getMainRenderTarget()` | `.gameRenderer.mainRenderTarget()` |
| `.getMainCamera()` | `.mainCamera()` |
| `Minecraft.getInstance().renderBuffers()` | `gameRenderer.renderBuffers()` |
| `createRenderPass(..., OptionalInt.empty(), ...)` | `Optional.empty()` |
| `.drawIndexed(0, 0, 6, 1)` | `.drawIndexed(6, 1, 0, 0, 0)` |
| `.drawIndexed(baseVertex, 0, 6, 1)` | `.drawIndexed(6, 1, 0, baseVertex, 0)` |
| `.setVertexBuffer(0, sunBuffer)` | `.setVertexBuffer(0, sunBuffer.slice())` |
| `writeTransform(modelViewStack, ...)` | `writeTransform(new Matrix4f(modelViewStack), ...)` |
| `EntityType.CHEST_MINECART` | `EntityTypes.CHEST_MINECART` |
| `Items.WHITE_WOOL` / `Items.MAGENTA_GLAZED_TERRACOTTA` | `Items.WOOL.white()` / `Items.GLAZED_TERRACOTTA.magenta()` |
| `pos.getCenter()` | `Vec3.atCenterOf(pos)` |

Transforms inject missing imports (`PrimitiveTopology`, `Optional`, `Matrix4f`, `EntityTypes`, `Vec3`) when needed.

**Gradle:** always emits `mod_license`, `mod_credits`, `mod_display_url` (avoids `processResources` unknown property failures on decompiled projects).

**Still manual (warned):** `MultiBufferSource` / `.bufferSource()` world drawing → `SubmitCustomGeometryEvent` + `submitShapeOutline`.

## Parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-Path` | *(required)* | Project root (input) |
| `-OutputPath` | *(empty)* | If set, copy here first and convert the copy only |
| `-MinecraftVersion` | `26.2` | MC version |
| `-NeoVersion` | `26.2.0.32-beta` | NeoForge version |
| `-ModVersion` | `<MC>.0` | `mod_version` |
| `-PackFormat` | `107` | `pack.mcmeta` min/max format |
| `-DryRun` | off | No writes |
| `-SkipBackup` | off | Skip zip backup |
| `-SkipGradleScaffold` | off | Don’t touch Gradle scripts |
| `-SkipJavaTransforms` | off | Don’t rewrite `.java` |
| `-FetchWrapper` | off | Download MDK wrapper |
| `-ForceTomlTemplate` | off | Overwrite mods.toml with template |
| `-Compile` / `-Build` | off | Run Gradle after convert |

## Layout

```
neoforge-26.2-converter/
  Launch-GUI.bat                 # double-click GUI
  Convert-ToNeoForge262-GUI.ps1  # WinForms UI
  Convert-ToNeoForge262.ps1      # CLI entry point
  README.md
  lib/
    JavaApiTransforms.ps1        # source rewrites
  templates/
    build.gradle.template
    settings.gradle.template
    neoforge.mods.toml.template
```

## After conversion

```powershell
cd D:\mods\SomeMod
.\gradlew.bat compileJava
.\gradlew.bat build
.\gradlew.bat runClient
```

## Limitations / not automatic

- **Mixins**, access transformers, and third-party mod APIs — fix manually if they break.
- **MCreator regenerate**: official generators may still target 26.1.x and can overwrite converted Gradle/Java. Prefer Gradle as source of truth after conversion.
- Unusual render/draw call shapes beyond the patterns above may still need hand fixes.
- Data-driven JSON (recipes, loot, models) is left as-is unless formats change; report runtime pack errors separately.
- Re-running is mostly **idempotent**, but always keep the backup zip.

## Extending transforms

Edit `lib/JavaApiTransforms.ps1` → `Invoke-SingleFileTransforms`. Keep replacements **idempotent** (safe if run twice).

## Related

- NeoForge versions: https://projects.neoforged.net/neoforged/neoforge  
- MDK template: https://github.com/NeoForgeMDKs/MDK-26.2-NeoGradle  
- Docs: https://docs.neoforged.net/
