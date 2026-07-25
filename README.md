# RB MCreator Version Updater

Convert **Minecraft 26.1.x NeoForge / MCreator Gradle workspaces** to **Minecraft 26.2 + NeoForge 26.2.x**.

Built from a real large MCreator block mod migration (`robmod`: 26.1.2 → `neoforge-26.2.0.32-beta`).

## Download (Windows)

Get the latest **Release** assets:

| Asset | Use when |
|-------|----------|
| **[RB-Mcreator-Version-Updater-Setup.exe](https://github.com/RobbieB1980/RB-Mcreator-Version-Updater/releases/latest)** | You want an installer (Start Menu / desktop shortcuts) |
| **RB-Mcreator-Version-Updater-Portable.zip** | You want a fully portable folder (no install) |

### Installer

1. Download `RB-Mcreator-Version-Updater-Setup.exe`
2. Run it (no admin required by default)
3. Choose install folder (default: `%LOCALAPPDATA%\RB-Mcreator-Version-Updater`)
4. Launch **RB MCreator Version Updater**

The Setup EXE is **self-contained** and embeds the full portable toolset (GUI + PowerShell converter + templates).

### Portable

1. Download `RB-Mcreator-Version-Updater-Portable.zip`
2. Extract anywhere
3. Run `Start-Updater.bat` or `RB-Mcreator-Version-Updater.exe`

## Using the app

1. **Browse** for the input MCreator / NeoForge project folder  
2. **Browse** (or accept the suggested) **output folder**  
3. Set Minecraft / NeoForge versions if needed  
4. Click **Convert**

The tool **always copies to the output folder first**, then converts the copy.  
**Your original project is never modified.**

Optional:

- Fetch Gradle wrapper (recommended)
- Compile after convert
- Full build (jar)
- Dry run (preview only)

## Requirements

- Windows x64
- PowerShell 5.1+ (converter engine)
- Network only if fetching the Gradle wrapper
- **JDK 25** if you compile/run the converted Minecraft mod

## CLI (PowerShell tools)

Also included under `tools/` next to the EXE (and in this repo root):

```powershell
# Copy to a new folder, then convert (original untouched)
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -FetchWrapper

# Preview only
.\Convert-ToNeoForge262.ps1 -Path "D:\mods\SomeMod" -OutputPath "D:\mods\SomeMod-26.2" -DryRun
```

Legacy PowerShell GUI:

```powershell
.\Convert-ToNeoForge262-GUI.ps1
# or
.\Launch-GUI.bat
```

## What conversion does

| Step | Action |
|------|--------|
| Copy (with output path) | Copies project (skips `build/`, `run/`, `.gradle/`, …) |
| `gradle.properties` | Sets `minecraft_version=26.2`, `neo_version=…` |
| Gradle scaffold | Creates `build.gradle` / `settings.gradle` if missing (NeoGradle **7.1.38**, Java **25**) |
| Wrapper | Optional: pulls `gradlew` from NeoForge MDK 26.2 |
| `neoforge.mods.toml` / `pack.mcmeta` / `*.mcreator` | Version metadata updates |
| Java sources | Known 26.1 → 26.2 API rewrites |

## Automatic Java rewrites

| 26.1 | 26.2 |
|------|------|
| `emissiveRendering((bs, br, bp) -> true)` | `emissiveRendering(bs -> true)` |
| `mc.setScreen(...)` | `mc.gui.setScreen(...)` |
| `VertexFormat.Mode.QUADS` | `PrimitiveTopology.QUADS` |
| `.getMainRenderTarget()` | `.gameRenderer.mainRenderTarget()` |
| `OptionalInt.empty()` in render passes | `Optional.empty()` |
| 4-arg `drawIndexed` (sky helpers) | 5-arg form |
| `setVertexBuffer(i, buf)` | `setVertexBuffer(i, buf.slice())` |

## Build from source

```powershell
git clone https://github.com/RobbieB1980/RB-Mcreator-Version-Updater.git
cd RB-Mcreator-Version-Updater

# Produces dist\ portable zip + Setup.exe
.\scripts\Build-Release.ps1

# Optional: publish GitHub Release assets
.\scripts\Publish-GitHubRelease.ps1 -Tag v1.1.0
```

Requires: .NET 8+ SDK, Windows.

## Project layout

```
RB-Mcreator-Version-Updater/
  Convert-ToNeoForge262.ps1          # CLI converter
  Convert-ToNeoForge262-GUI.ps1      # PowerShell GUI
  Launch-GUI.bat
  lib/  templates/  tests/
  src/
    RB.Mcreator.VersionUpdater/      # WinForms GUI (EXE)
    RB.Mcreator.VersionUpdater.Setup/ # Installer (EXE)
  scripts/
    Build-Release.ps1
    Publish-GitHubRelease.ps1
```

## Limitations

- Mixins / third-party APIs may need manual fixes.
- MCreator regenerate may still target 26.1.x.
- Heavy folders (`build/`, `run/`, `.gradle/`) are skipped when copying to output.

## License

All Rights Reserved unless otherwise noted by the repository owner.
