"""Make the new mouth surfaces explicit children of the export armature."""

import bpy


MARKER = "hero_mouth_parent_v5"


body = bpy.data.objects.get("ConnectedBody")
rig = bpy.data.objects.get("HeroRig")
if body is None or rig is None:
    raise RuntimeError("ConnectedBody or HeroRig is missing")
if not body.get(MARKER):
    for name in ("MouthUpperSurface", "MouthLowerSurface", "MouthCreaseSurface"):
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError(f"{name} is missing")
        world = obj.matrix_world.copy()
        obj.parent = rig
        obj.matrix_world = world
    body[MARKER] = True
    body["hero_mouth_parent_v5_notes"] = "Mouth surfaces are explicit HeroRig children for deterministic glTF skin export"
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_MOUTH_PARENT_V5|applied")
else:
    print("HERO_MOUTH_PARENT_V5|already_applied")
