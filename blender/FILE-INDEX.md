# Blender file index

## Edit this hero

`BrokenKnight_Hero_Master.blend` is the one canonical hero file. It contains
the current body, rig, colors, hair, loincloth, royal armor, improved shoulder
pieces, staff, and animations. The root shortcut `open-hero-blender.bat` opens
this file. See `ARMOR-EDITING.md` before changing armor geometry or weights.

## Current standalone assets

| File | Purpose |
| --- | --- |
| `royal_armor_apex_editable_shoulders_improved.blend` | Standalone source study used by the current master armor pass |
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
| `royal_armor_apex_editable.blend` | Earlier Apex armor |
| `royal_armor_closed_harness_editable.blend` | Earlier closed-harness armor |
| `royal_armor_ducal_editable.blend` | Earlier ducal armor |

Blender's `.blend1` automatic backups are kept under `_archive/autosaves/` so
they do not crowd the source directory.
