# Broken Knight - World Build start here

Read this file before asking ChatGPT to change the world. World Build is
separate from Hero Build.

## Scope

World Build owns terrain, rivers, lakes, coastlines, roads, trails, bridges,
town placement, caves, vegetation, traversal, maps, lighting, and performance
while moving through the world.

Do not change hero meshes, the hero rig, armor fit, face art, or hero animation
sources during a World Build task. Those belong to the separate Hero Build
workflow.

## Canonical files

- Layout data: `godot/data/world/profile.json`
- Layout schema and rules: `godot/data/world/README.md`
- Terrain, elevation, riverbeds, and walkable height: `godot/scripts/world/TerrainBuilder.gd`
- World visuals, towns, roads, water, bridges, props, and vegetation: `godot/scripts/world/WorldPreviewBuilder.gd`
- Profile validation/normalization: `godot/scripts/world/WorldProfile.gd`
- Main world assembly and streaming: `godot/scripts/Main.gd`
- Large map: `godot/scripts/WorldMap.gd`
- Minimap: `godot/scripts/Minimap.gd`
- World Blender sources: `blender/world/`
- Runtime world assets: `godot/assets/terrain/`, `vegetation/`, `architecture/`, and `sky/`
- Story and location intent: `docs/story/LORE-AND-WORLD.md`

## Preferred workflow

1. Change `profile.json` first when the request concerns placement, width,
   routing, or world scale.
2. Change `TerrainBuilder.gd` only for terrain shape, elevation, riverbeds, or
   collision-height behavior.
3. Change `WorldPreviewBuilder.gd` only for generated visuals and world props.
4. Keep maps derived from the same profile instead of drawing unrelated map
   geometry.
5. Use Blender only when an authored 3D asset is needed. Keep the `.blend`
   source under `blender/world/` and export a GLB into `godot/assets/`.
6. Run `.\world.bat check` after each meaningful pass.
7. Launch with `.\world.bat play` and inspect in-engine before accepting
   the change.

## Feature routing

- Rivers: edit `river_corridors`, then verify terrain bed, water surface, bank
  access, crossings, and map continuity together.
- Roads/trails: edit their corridor points and widths; route around steep slopes
  and terminate at real destinations.
- Bridges: keep bridge anchors in `ford_sites`; roads should meet bridge ends
  without drawing road material across the bridge deck.
- Towns: move `town_sites` before changing generated buildings. Town radii must
  sit on usable ground outside riverbeds and road centers.
- Vegetation: edit region density in the profile; edit species geometry under
  `blender/world/` only when the actual model needs to change.
- Maps: fix world data first, then map rendering. The map should represent the
  same profile and show the player's actual position/facing.
- Performance: prefer streaming, batching, cached spatial lookups, and bounded
  local collision over reducing important traversal landmarks. Run
  `world.bat perf`; use `BROKEN_KNIGHT_BENCHMARK_ROUTE=crownspire` for the
  densest city route. Cache details live in `docs/world/PERFORMANCE.md`.

## Safety rules

- Never edit or delete `godot/.godot/` as a gameplay change.
- Keep `.import` sidecars; they can contain authored import settings.
- Do not overwrite the ZIP backup at `C:\Users\Jimmy\Desktop\Broken Knight.zip`.
- Preserve unrelated Hero Build changes already present in the worktree.
- If a pass worsens traversal, rivers, or map readability, revert that pass.

## Prompt for a regular ChatGPT session

Use this at the beginning of a world task:

> Work only on Broken Knight World Build. Read WORLD-BUILD-START-HERE.md and
> godot/data/world/README.md first. Do not edit hero or armor source files.
> Make a meaningful world pass, run world.bat check, test the main scene,
> and keep rivers, roads, bridges, terrain height, maps, and traversal logically
> aligned.
