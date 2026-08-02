# Blender source

Canonical editable sources live directly in this directory. Generated previews,
automatic `.blend1` files, and timestamped checkpoints are not source.

## Current hero

- Editable rig: `BrokenKnight_Hero_Master.blend`
- Runtime export: `..\godot\assets\hero\hero_base_body.glb`
- Export script: `scripts\export_rigged_hero.py`

Use `..\open-hero-blender.bat` to edit and `..\export-hero-blender.bat` to
export the current rig. The master contains named Outliner collections plus
the `00_START_HERE` and `ANIMATION_INDEX` text blocks.

`hero_base.blend` and `hero_restart.blend` remain as upstream modeling sources.
Canonical enemy, equipment, and armor `.blend` files are retained so their GLB
assets can be regenerated.

See `FILE-INDEX.md` for the purpose of every retained blend, `ANIMATIONS.md`
for the full action list, `ARMOR-EDITING.md` for safe armor changes, and
`scripts/README.md` before running a build or one-off revision script.

## World assets

World-only Blender work is isolated under `world/`:

- `world/vegetation/`: editable tree source files.
- `world/scripts/`: deterministic vegetation and ground-cover builders.
- `world/README.md`: export commands and asset destinations.

Do not place world source `.blend` files inside the Godot project. Godot should
contain exported runtime assets only.
