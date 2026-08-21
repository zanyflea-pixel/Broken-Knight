# Blender file index

## Edit this hero

`BrokenKnight_Hero_Master.blend` is the one canonical hero file. It contains
the current body, rig, colors, hair, loincloth, royal armor, improved shoulder
pieces, staff, and animations. The root shortcut `open-hero-blender.bat` opens
this file. See `ARMOR-EDITING.md` before changing armor geometry or weights.

The current unarmored anatomy/complexion/loincloth authoring pass is recorded
in `scripts/hero_realism_pass_v4.py`. Neutral review renders are produced by
`scripts/render_unarmored_hero_review.py` under
`previews/unarmored_hero_review/`.

The accepted body is locked. The current animation pass is recorded by
`scripts/refine_locked_body_animation_pass.py`. The current royal harness is
recorded by `scripts/build_articulated_royal_harness.py`; edit its individual
parts in `royal_armor_articulated_editable.blend`, organized by slot in
collections `10A_ARMOR_HEAD` through `10F_ARMOR_FEET`. The promoted master is
runtime-consolidated to six skinned slot meshes using
`scripts/consolidate_armor_for_runtime.py`.

The current athletic leg sculpt and Walk/TorchWalk/StaffWalk/WarriorWalk pass
is recorded in `scripts/hero_leg_walk_pass_v1.py`. Its eight gait-pose review
renderer is `scripts/render_walk_cycle_review.py`, with output under
`previews/walk_cycle_review/`.

The current head and movement correction is already applied to the master and
is recorded in this order:

1. `scripts/hero_head_movement_pass_v1.py` — adult head proportions plus the
   upright, low-bob Walk/TorchWalk/StaffWalk/WarriorWalk refresh and the current
   Jump, Land, and Roll rebuild.
2. `scripts/hero_head_finish_pass_v2.py` and
   `scripts/hero_head_finish_pass_v3.py` — nose, jaw, chin, brow, and mouth-plane
   corrections made after the first close review.
3. `scripts/hero_mouth_surface_pass_v4.py` and
   `scripts/hero_mouth_parent_fix_v5.py` — the final shallow, face-conforming,
   head-weighted lip and mouth surfaces used by the runtime GLB.

The current sword/shield clearance is implemented in
`../godot/scripts/HeroVisual.gd` and regression-checked by
`../godot/tools/verification/verify_sword_shield_clearance.gd`.

## Professional hero head

The canonical master now contains the rebuilt continuous-topology adult male
head, surface-rooted directional hair and brows, facial stubble, embedded eyes,
and a sealed neck extruded directly from the head boundary. The rebuild is recorded by
`scripts/build_hero_head_mpfb_wip.py`, integrated by
`scripts/integrate_professional_hero_head_wip.py`, and exported by
`scripts/export_rigged_hero.py`.

| File | Purpose |
| --- | --- |
| `BrokenKnight_Hero_Master.blend` | Canonical complete hero and the file to edit for the game |
| `BrokenKnight_Hero_Head_Professional_WIP.blend` | Isolated editable professional head source |
| `BrokenKnight_Hero_Master_HeadRebuild_WIP.blend` | Full integration checkpoint before promotion |
| `references/hero_head_reference_v1.png` | Custom visual reference used for the rebuild |
| `textures/hero_skin_micro_albedo_v1.png` | Packed project-owned skin micro-albedo source |

The runtime export is `../godot/assets/hero/hero_full_continuous_body.glb`.
It contains the 53-bone continuous hero, six consolidated skinned royal-armor
meshes, and 23 gameplay clips. `hero_base_body.glb` remains a compatibility
copy. The final
head topology audit reported zero boundary and zero non-manifold edges.

## Current standalone assets

| File | Purpose |
| --- | --- |
| `royal_armor_articulated_editable.blend` | Current unconsolidated royal harness source; use this for armor geometry edits |
| `royal_vanguard_staff.blend` | Standalone royal staff |
| `royal_vanguard_weapons.blend` | Standalone sword and shield |
| `imp_enemy.blend` | Imp source |
| `ashfang_hound.blend` | Ashfang hound source |
| `cave_dragon.blend` | Cave dragon source |

## Hero and armor history

These are retained as recovery or rebuild inputs. Do not use them for normal
hero edits or exports.

| File | Role |
| --- | --- |
| `hero_restart_rigged_shoulders_improved.blend` | Immediate source used to create the current master |
| `hero_restart_rigged.blend` | Older rig before the improved shoulder pass |
| `hero_restart.blend` | Upstream unrigged restart model |
| `hero_base.blend` | Earliest retained hero base |
| `backups/retired_articulated_armor_drafts_20260813_2220/` | Earlier Apex, ducal, closed-harness, and rejected procedural armor drafts |

Blender's `.blend1` automatic backups are kept under `_archive/autosaves/` so
they do not crowd the source directory.
