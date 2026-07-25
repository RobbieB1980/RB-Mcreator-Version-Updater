# RB All Updater

Convert **Minecraft 26.1.x NeoForge** projects to **Minecraft 26.2 + NeoForge 26.2.x**.

Works on:

| Project style | Examples |
|---------------|----------|
| **MCreator** workspaces | `*.mcreator`, generated Gradle |
| **ModDevGradle** | Hand-ported / migration mods (`net.neoforged.moddev`) |
| **NeoGradle MDK** | Official NeoForge MDK / userdev |

Built from real migrations (MCreator block mods + hand-ported GeckoLib mods like *The One Who Watches*).

## Download (Windows)

| Asset | Use when |
|-------|----------|
| **RB-All-Updater-Setup.exe** | Installer (Start Menu / desktop shortcuts) |
| **RB-All-Updater-Portable.zip** | Fully portable folder (no install) |

### Installer

1. Run `RB-All-Updater-Setup.exe` (no admin required by default)
2. Default folder: `%LOCALAPPDATA%\RB-All-Updater`
3. Launch **RB All Updater**

### Portable

1. Extract `RB-All-Updater-Portable.zip`
2. Run `Start-Updater.bat` or `RB-All-Updater.exe`

## Using the app

1. **Browse** for the input project folder (MCreator *or* any NeoForge Gradle mod)
2. **Browse** (or accept the suggested) **output folder**
3. Set Minecraft / NeoForge versions if needed
4. Click **Convert**

The tool **always copies to the output folder first**, then converts the copy.  
**Your original project is never modified.**

### Options

| Option | Meaning |
|--------|---------|
| **Fetch Gradle wrapper** | Download `gradlew` from NeoForge 26.2 MDK if missing |
| **Dry run** | Preview only — no files written |
| **Compile after convert** | Run `compileJava` (real runs only; needs JDK 25) |
| **Full build** | Run `gradlew build` |

## What it changes

- `gradle.properties` → Minecraft / NeoForge 26.2 (preserves your `mod_version` when possible)
- Scaffold or patch Gradle files (does **not** replace ModDevGradle with NeoGradle templates)
- `settings.gradle` → inject NeoForged maven when missing
- `neoforge.mods.toml` under **resources** *and/or* **ModDevGradle templates**
- `pack.mcmeta` pack format
- `*.mcreator` metadata when present
- Known **Java API** breaks (26.1 → 26.2)

### Automatic Java transforms

- `emissiveRendering((bs,br,bp)->...)` → `emissiveRendering(bs -> ...)`
- `mc.setScreen(...)` → `mc.gui.setScreen(...)`
- `VertexFormat.Mode.*` → `PrimitiveTopology.*`
- `getMainRenderTarget()` → `gameRenderer.mainRenderTarget()`
- `createRenderPass(... OptionalInt)` → `Optional.empty()`
- `drawIndexed` 4-arg → 5-arg form
- `setVertexBuffer(i, buf)` → `setVertexBuffer(i, buf.slice())`
- `writeTransform(modelViewStack,` → `writeTransform(new Matrix4f(modelViewStack),`
- `pos.getCenter()` → `Vec3.atCenterOf(pos)`

## Requirements

- Windows
- PowerShell (for the converter engine)
- **JDK 25** to compile / run Minecraft 26.2
- Network only if **Fetch Gradle wrapper** is enabled

## CLI

```powershell
cd tools   # or the tools folder next to the EXE
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -FetchWrapper
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -DryRun
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -FetchWrapper -Compile
```

## Build from source

```powershell
.\scripts\Build-Release.ps1
```

Outputs under `dist/`:

- `RB-All-Updater-Setup.exe`
- `RB-All-Updater-Portable.zip`

## Notes

- Third-party libs (e.g. **GeckoLib**) must publish artifacts for the target Minecraft version.
- Official MCreator generators may still target 26.1.x — prefer Gradle builds after conversion.
- Custom mixins / reflection may need manual fixes beyond the automatic transforms.
