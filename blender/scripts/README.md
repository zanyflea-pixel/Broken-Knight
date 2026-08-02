# Blender scripts

The scripts remain in one directory because several are imported or launched
by other scripts. Use this index instead of moving them and breaking paths.

## Normal editing workflow

| Script | Use |
| --- | --- |
| `export_rigged_hero.py` | Export the open master to Godot; normally use `../../export-hero-blender.bat` |
| `render_hero_preview.py` | Render a full-body review from the open hero |
| `render_head_preview.py` | Render a head review from the open hero |
| `audit_blend_workspace.py` | Print object, rig, collection, and action counts |
| `audit_all_hero_animations.py` | Audit the hero action set |
| `validate_rig.py` | Validate rig structure and weights |
| `verify_exported_glb.py` | Verify a generated hero GLB |

## Master-file maintenance

`organize_hero_master.py` rebuilds `BrokenKnight_Hero_Master.blend` from the
blend passed to Blender. It reorganizes data but does not remodel the hero.
Run it only when intentionally promoting another hero file to master.

## Asset builders

- `build_hero_*.py`, `rig_hero_for_godot.py`: rebuild older hero stages.
- `build_royal_armor.py`, `build_royal_staff.py`,
  `build_royal_vanguard_weapons.py`: rebuild equipment.
- `build_imp_enemy.py`, `build_ashfang_hound.py`, `build_cave_dragon.py`:
  rebuild enemies.
- `make_*_pbr_maps.py`: regenerate procedural texture maps.

Builder scripts can replace substantial geometry. Save or copy the master
before running one manually.

## Review and diagnostics

- `render_*.py`: review renders and animation contact sheets.
- `audit_*.py`, `analyze_*.py`, `inspect_*.py`, `validate_*.py`,
  `verify_*.py`: non-authoring diagnostics unless their header says otherwise.

## Historical one-off passes

Scripts beginning with `adjust_`, `apply_`, `blunt_`, `fill_`, `flatten_`,
`lifelike_`, `polish_`, `refine_`, `repair_`, `restore_`, `safe_`, or
`strongman_` are retained to explain earlier revisions. Do not run them on the
master casually; many save changes directly into whichever blend is open.
