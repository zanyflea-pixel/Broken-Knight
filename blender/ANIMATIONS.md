# Hero animation index

The canonical source is `BrokenKnight_Hero_Master.blend`. Select `HeroRig`,
open the Dope Sheet in **Action Editor** mode, and choose an action by the exact
name below. The same index is embedded in the blend as the `ANIMATION_INDEX`
text block.

Do not rename runtime actions: Godot refers to these names. Playback is 24 fps.

| Category | Action | Frames | Loop | Notes |
| --- | --- | ---: | :---: | --- |
| Locomotion | `Idle` | 1-73 | Yes | Unarmed base idle |
| Locomotion | `Walk` | 1-25 | Yes | Unarmed base walk |
| Locomotion | `WarriorIdle` | 1-73 | Yes | Sword-and-shield idle |
| Locomotion | `WarriorWalk` | 1-25 | Yes | Sword-and-shield walk |
| Locomotion | `TorchIdle` | 1-73 | Yes | Torch idle |
| Locomotion | `TorchWalk` | 1-25 | Yes | Torch walk |
| Locomotion | `StaffIdle` | 1-73 | Yes | Mage idle |
| Locomotion | `StaffWalk` | 1-25 | Yes | Mage walk |
| Traversal | `Jump` | 1-19 | No | Jump rise |
| Traversal | `Land` | 1-18 | No | Landing recovery |
| Traversal | `Roll` | 1-19 | No | Combat roll |
| Combat | `SwordSlash` | 1-17 | No | Source sword action |
| Combat | `ShieldBash` | 1-19 | No | Shield attack |
| Combat | `Death` | 1-34 | No | Hero death |
| Magic | `Spark` | 1-14 | No | Unarmed spark |
| Magic | `Nova` | 1-20 | No | Unarmed nova |
| Magic | `Blink` | 1-13 | No | Unarmed blink |
| Magic | `Orb` | 1-24 | No | Unarmed orb |
| Magic | `StaffSpark` | 1-14 | No | Staff spark |
| Magic | `StaffNova` | 1-20 | No | Staff nova |
| Magic | `StaffBlink` | 1-14 | No | Staff blink |
| Magic | `StaffOrb` | 1-24 | No | Staff orb |
| Utility | `FishCast` | 1-27 | No | Fishing cast |
| Experimental | `SwordSlash_Improved_Test` | 1-17 | No | Kept for reference; excluded from export |

The live sword attack also applies a procedural left-arm pose in
`godot/scripts/HeroVisual.gd`. Its current gameplay duration is 0.62 seconds,
and damage lands after 0.23 seconds in `godot/scripts/GameplayDirector.gd`.
Changing only the Blender `SwordSlash` action will therefore not fully define
the in-game swing.
