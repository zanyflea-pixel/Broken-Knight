# World performance workflow

World content remains authored in `godot/data/world/profile.json`, world meshes and placement live under `godot/scripts/world`, and Blender source assets live under `blender/world`. Generated runtime caches are kept outside the project in Godot's `user://world_cache` directory so editable source folders stay clean.

The caches are versioned in code and rebuild automatically when relevant authored world data changes. They are accelerators, never the authoritative copy of the world:

- `TerrainBuilder.TERRAIN_CACHE_VERSION` controls sampled height data.
- `TerrainBuilder.TERRAIN_MESH_CACHE_VERSION` controls the completed terrain mesh and collision shape.
- `WorldPreviewBuilder.MEADOW_CACHE_VERSION` controls deterministic meadow transforms.
- `WorldMap` retains its own illustrated survey image cache.

Use these supported commands from the project root:

- `world.bat import` — import assets and compile scripts.
- `world.bat check` — run world integrity checks.
- `world.bat perf` — run the moving-camera runtime benchmark.
- `world.bat clean` — remove project-local generated previews only; it does not delete authored assets.

When terrain formulas or cached placement logic changes, increment the matching explicit cache version. Decorative edits that do not affect terrain or meadow transforms should not invalidate these caches.

Set `BROKEN_KNIGHT_BENCHMARK_ROUTE=crownspire` before `world.bat perf` to exercise the densest city and castle approach instead of the default Riverwatch road route.
