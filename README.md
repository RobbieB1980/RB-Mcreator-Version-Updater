# RB MCreator Version Updater

Convert **Minecraft 26.1.x NeoForge / MCreator Gradle workspaces** to **Minecraft 26.2 + NeoForge 26.2.x**.

Built from a real large MCreator block mod migration (`robmod`: 26.1.2 → `neoforge-26.2.0.32-beta`).

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- Network access only if you use `-FetchWrapper`
- **JDK 25** to compile/run after conversion (Minecraft 26.2)

## Quick start

```powershell
# Clone
git clone https://github.com/RobbieB1980/RB-Mcreator-Version-Updater.git
cd RB-Mcreator-Version-Updater

# Preview (no writes)
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -DryRun

# Apply + install Gradle wrapper if missing + compile
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -FetchWrapper -Compile

# Custom NeoForge build
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -NeoVersion "26.2.0.32-beta" -Build
```

## What it does

| Step | Action |
|------|--------|
| Backup | Zips `src/`, Gradle files, `elements/`, `*.mcreator` → `.converter-backups/` |
| `gradle.properties` | Sets `minecraft_version=26.2`, `neo_version=…`, heap, mod metadata |
| Gradle scaffold | Creates `build.gradle` / `settings.gradle` if missing (NeoGradle **7.1.38**, Java **25**) |
| Existing `build.gradle` | Bumps NeoGradle plugin + Java toolchain to 25 when present |
| Wrapper | Optional: pulls `gradlew` from [MDK-26.2-NeoGradle](https://github.com/NeoForgeMDKs/MDK-26.2-NeoGradle) |
| `neoforge.mods.toml` | Updates NeoForge/Minecraft dependency ranges |
| `pack.mcmeta` | Sets pack format **107** (26.2) |
| `*.mcreator` | Updates generator / version / description when found |
| Java sources | Applies known 26.1 → 26.2 API rewrites under `src/main/java` |

## Automatic Java rewrites

| 26.1 pattern | 26.2 result |
|--------------|-------------|
| `emissiveRendering((bs, br, bp) -> true)` | `emissiveRendering(bs -> true)` |
| `mc.setScreen(...)` | `mc.gui.setScreen(...)` |
| `VertexFormat.Mode.QUADS` | `PrimitiveTopology.QUADS` |
| `.getMainRenderTarget()` | `.gameRenderer.mainRenderTarget()` |
| `createRenderPass(..., OptionalInt.empty(), ...)` | `Optional.empty()` |
| `.drawIndexed(0, 0, 6, 1)` | `.drawIndexed(6, 1, 0, 0, 0)` |
| `.drawIndexed(baseVertex, 0, 6, 1)` | `.drawIndexed(6, 1, 0, baseVertex, 0)` |
| `.setVertexBuffer(0, sunBuffer)` | `.setVertexBuffer(0, sunBuffer.slice())` |
| `writeTransform(modelViewStack, ...)` | `writeTransform(new Matrix4f(modelViewStack), ...)` |

Missing imports (`PrimitiveTopology`, `Optional`, `Matrix4f`) are injected when needed.

## Parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-Path` | *(required)* | Project root |
| `-MinecraftVersion` | `26.2` | MC version |
| `-NeoVersion` | `26.2.0.32-beta` | NeoForge version |
| `-ModVersion` | `<MC>.0` | `mod_version` |
| `-PackFormat` | `107` | `pack.mcmeta` min/max format |
| `-DryRun` | off | No writes |
| `-SkipBackup` | off | Skip zip backup |
| `-SkipGradleScaffold` | off | Don't touch Gradle scripts |
| `-SkipJavaTransforms` | off | Don't rewrite `.java` |
| `-FetchWrapper` | off | Download MDK wrapper |
| `-ForceTomlTemplate` | off | Overwrite mods.toml with template |
| `-Compile` / `-Build` | off | Run Gradle after convert |

## Project layout

```
RB-Mcreator-Version-Updater/
  Convert-ToNeoForge262.ps1   # entry point
  README.md
  lib/
    JavaApiTransforms.ps1     # source rewrites
  templates/
    build.gradle.template
    settings.gradle.template
    neoforge.mods.toml.template
  tests/
    Test-Transforms.ps1       # self-tests for rewrite rules
```

## After conversion

```powershell
cd D:\mods\SomeMod
.\gradlew.bat compileJava
.\gradlew.bat build
.\gradlew.bat runClient
```

## Self-test transforms

```powershell
.\tests\Test-Transforms.ps1
```

## Limitations

- **Mixins**, access transformers, and third-party mod APIs may still need manual fixes.
- **MCreator regenerate**: official generators may still target 26.1.x and can overwrite converted Gradle/Java. Prefer Gradle as source of truth after conversion.
- Unusual render/draw call shapes beyond the patterns above may need hand fixes.
- Data-driven JSON is left as-is unless you extend the tool.
- Re-running is mostly **idempotent**, but always keep the backup zip.

## Extending transforms

Edit `lib/JavaApiTransforms.ps1` → `Invoke-SingleFileTransforms`. Keep replacements **idempotent** (safe if run twice).

## Links

- NeoForge versions: https://projects.neoforged.net/neoforged/neoforge  
- MDK template: https://github.com/NeoForgeMDKs/MDK-26.2-NeoGradle  
- Docs: https://docs.neoforged.net/

## License

All Rights Reserved unless otherwise noted by the repository owner.
