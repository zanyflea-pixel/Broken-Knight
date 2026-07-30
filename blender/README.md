# Blender source

Canonical editable sources live directly in this directory. Generated previews,
automatic `.blend1` files, and timestamped checkpoints are not source.

## Current hero

- Editable rig: `hero_restart_rigged.blend`
- Runtime export: `..\godot\assets\hero\hero_base_body.glb`
- Export script: `scripts\export_rigged_hero.py`

Use `..\open-hero-blender.bat` to edit and `..\export-hero-blender.bat` to
export the current rig.

`hero_base.blend` and `hero_restart.blend` remain as upstream modeling sources.
Canonical enemy, equipment, and armor `.blend` files are retained so their GLB
assets can be regenerated.
