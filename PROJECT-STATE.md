# Broken Knight Project State

## Canonical build

The canonical game is the Godot project at `godot/project.godot`. The old
JavaScript/browser prototype is retired and is not a recovery or runtime
dependency.

Read `START-HERE.md` first if you just need to know what to open.

## Runtime

- Engine: Godot 4.7 stable
- Main scene: `res://scenes/Main.tscn`
- Game launcher: `play-godot-world.bat`
- Editor launcher: `start-godot.ps1`
- Window title/project identity: Broken Knight

## Authoring

- World/game source: `godot/`
- World layout profile: `godot/data/world/profile.json`
- World Blender source: `blender/world/`
- Editable story/lore: `docs/story/LORE-AND-WORLD.md`
- Current hero source: `blender/BrokenKnight_Hero_Master.blend`
- Current hero export script: `blender/scripts/export_rigged_hero.py`
- Current hero runtime asset: `godot/assets/hero/hero_base_body.glb`
- Other Blender source files without checkpoint-style names are retained as
  regeneration sources for enemies, weapons, and armor.

## Generated content

These locations are disposable and ignored:

- `godot/.godot/`
- `godot/artifacts/`
- `blender/preview/`
- `blender/previews/`
- `tmp/`
- `*.blend1`
- runtime logs and capture output

Deleting `godot/.godot/` causes one slower import pass on the next launch, but
does not remove game source.

Godot `.import` sidecars are not disposable. They preserve per-asset import
settings such as the hero animation post-import hook and must remain beside
their source assets.

## Change rules

1. Make gameplay changes only in `godot/`.
2. Export 3D assets from canonical Blender source into `godot/assets/`.
3. Keep generated reviews and caches out of the project root.
4. Run `world.bat check` after World Build changes.
5. Never treat a timestamped checkpoint as a canonical source file.
