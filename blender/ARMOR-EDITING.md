# Royal armor editing

Open `BrokenKnight_Hero_Master.blend`. This is the current armor source as well
as the canonical hero file; do not edit the older standalone armor studies for
game changes.

## Where the armor is

The Outliner is split into six armor collections:

| Collection | Contents |
| --- | --- |
| `10A_ARMOR_HEAD` | Unified close helmet, forged crown ribs, and its joined layered horsehair plume |
| `10B_ARMOR_CHEST` | Convex tapul cuirass, integral royal plastron, fitted plackarts, gorget, fauld, pointed front tassets, wraparound hip lames and rear culet |
| `10C_ARMOR_SHOULDERS` | Crowned and fluted grand pauldrons, rerebraces, and articulated arm lames |
| `10D_ARMOR_HANDS` | Couters, vambraces and gauntlets |
| `10E_ARMOR_PANTS` | Arming layer, cuisses and knee voids |
| `10F_ARMOR_FEET` | Poleyns, greaves and sabatons |

Every newly authored outer piece has the custom properties `bk_edit_group`,
`bk_visual_pass`, and `bk_editable`. The `ARMOR_EDITING_GUIDE` text inside the
Blend file repeats the important rules without requiring this document.

## Safe changes

1. Duplicate the Blend file before a large experiment.
2. Select one armor collection and use Edit Mode to move its vertices.
3. Preserve every `RoyalArmor_<slot>_` object-name prefix; Godot uses it to
   identify equipment slots.
4. Keep the `RoyalArmorRig` armature modifier and existing vertex groups.
5. Material changes and Bevel widths are safe. Applying modifiers or joining
   differently weighted plates can break animation deformation.
6. Do not add freestanding rays, badges, trim bars, visor chunks, rivet props,
   or other decorations in front of the armor. Detail must be modeled into a
   structural shell, share its surface, or visibly overlap an adjacent plate.
7. Preserve the generated UV layers. They make the engraved cobalt filigree,
   normal relief, and roughness maps visible in Blender and Godot.
8. Save the master, run `..\export-hero-blender.bat`, then run
   `..\project.bat check` from the project root.

## Rebuilding this pass

`scripts/refine_royal_armor_visual_pass.py` is the repeatable source for this
visual pass. It rebuilds the edited outer shells in the master while preserving
the hero, rig, actions, staff, and deformation-safe underlayers. Current outer
tassets, hip lames, cuirass relief, shoulders, helmet, and plume are generated
directly by this script; the older reference file is retained only for legacy
underlayer pieces that have not been replaced.

Do not run the rebuild script after hand-editing those generated outer pieces
unless you intend to replace those edits.
