# Blender source

Canonical editable sources live directly in this directory. Generated previews,
automatic `.blend1` files, and timestamped checkpoints are not source.

## Current hero

- Editable rig: `BrokenKnight_Hero_Master.blend`
- Runtime body export: `..\godot\assets\hero\hero_full_continuous_body.glb`
- Legacy staff carrier: `..\godot\assets\hero\hero_base_body.glb`
- Current exporter: `scripts\export_current_hero.py`
- Current animation pass: `scripts\refine_locked_body_animation_pass.py`
- Current armor builder: `scripts\build_articulated_royal_harness.py`
- Editable armor source: `royal_armor_articulated_editable.blend`
- Runtime armor optimizer: `scripts\consolidate_armor_for_runtime.py`

Use `..\open-hero-blender.bat` to edit and `..\export-hero-blender.bat` to
export the current rig. The promoted master is the continuous 53-bone hero.
The current armor now lives on the continuous hero's own rig.
Godot loads the standalone `royal_vanguard_staff.glb`; the obsolete second
character/equipment rig is no longer instantiated. Runtime armor is joined to
one skinned mesh per equipment slot in the master and GLB; the separate
`royal_armor_articulated_editable.blend` keeps every plate, trim, and rivet
organized for manual Blender edits.

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
