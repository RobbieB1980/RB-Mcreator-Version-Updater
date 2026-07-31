# Changelog

## 1.3.1 — 2026-08-01

### Critical fix
- **`mod_license` / processResources crash:** decompiled or partial projects that already had `mod_id` in `gradle.properties` skipped metadata defaults. Scaffolded NeoGradle `build.gradle` then failed with  
  `Could not get unknown property 'mod_license' for task ':processResources'`.  
  Converter now always emits `mod_license`, `mod_credits`, and `mod_display_url` (and still fills from mods.toml when present).

### Java API transforms (26.1 → 26.2)
- `EntityType.VANILLA_FIELD` → `EntityTypes.VANILLA_FIELD` (+ import)
- Full **ColorCollection** grid for `Items` / `Blocks` (wool, glazed terracotta, beds, carpets, …)
- `getMainCamera()` → `mainCamera()`
- `Minecraft.getInstance().renderBuffers()` → `gameRenderer.renderBuffers()`
- Residual warnings for `MultiBufferSource` / `.bufferSource()` (still manual: `SubmitCustomGeometryEvent` + `submitShapeOutline`)

### Docs / tests
- README transform table updated
- Unit tests extended for new rewrites + Builder safety

### Packaging
- GUI / Setup version **1.3.1**

## 1.3.0
- Prior release (see package history)
