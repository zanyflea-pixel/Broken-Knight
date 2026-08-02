# Broken Knight editing guide

## Open and run

- `../start-godot.ps1`: open the Godot editor.
- `../play-godot-world.bat`: run the game directly.
- Main scene: `scenes/Main.tscn`.
- World data: `data/world/profile.json`.

## Where to make common changes

| Change | Primary file |
| --- | --- |
| Movement speed, sprint, jump, roll, gravity, camera | `scripts/HeroController.gd` |
| Hero model, animation playback, equipment attachment, sword pose | `scripts/HeroVisual.gd` |
| Enemies, combat damage/timing, loot, skills, fishing | `scripts/GameplayDirector.gd` |
| World construction and game/menu orchestration | `scripts/Main.gd` |
| Terrain and roads | `scripts/world/TerrainBuilder.gd` |
| Towns, architecture, vegetation, and world props | `scripts/world/WorldPreviewBuilder.gd` |
| World profile loading/defaults | `scripts/world/WorldProfile.gd` |
| Inventory and 3D hero inspection | `scripts/HeroMenu.gd` |
| Admin panel | `scripts/AdminMenu.gd` |
| HUD | `scripts/OldHud.gd` |
| Minimap / large map | `scripts/Minimap.gd` / `scripts/WorldMap.gd` |
| Vendors / crafting | `scripts/VendorMenu.gd` / `scripts/CraftingMenu.gd` |

## Asset folders

`assets/hero`, `assets/enemies`, `assets/equipment`, `assets/items`,
`assets/architecture`, `assets/terrain`, and `assets/vegetation` contain the
runtime assets. Edit original 3D sources under `../blender/`, then export GLB
files here. Do not edit generated `.godot/` cache files.

## Current sword implementation

The sword and shield are attached in `HeroVisual.gd`. The live sword strike
uses the Blender animation plus a procedural left-arm pose lasting 0.62
seconds. `GameplayDirector.gd` applies the hit 0.23 seconds after the action
starts. If the swing looks wrong, inspect both files; editing only the Blender
action does not control the whole result.

## Verification

Focused checks live in `tools/verification/`. Captures and test output belong
in `artifacts/` or the project-level `captures/` directory, not beside source
files. See `WORKFLOW.md` for the normal test loop.
