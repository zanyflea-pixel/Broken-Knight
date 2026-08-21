"""Verify every exported professional head component has normalized rig weights."""

import bpy


rig = bpy.data.objects.get("HeroRig")
if rig is None or rig.type != "ARMATURE":
    raise RuntimeError("HeroRig is missing")

checked = 0
for obj in bpy.context.scene.objects:
    if obj.type != "MESH" or not obj.name.startswith("Professional"):
        continue
    modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
    if not modifiers or any(modifier.object != rig for modifier in modifiers):
        raise RuntimeError(f"{obj.name} is not bound to HeroRig")
    unweighted = 0
    minimum = 10.0
    maximum = 0.0
    for vertex in obj.data.vertices:
        total = sum(member.weight for member in vertex.groups)
        if total < 0.999:
            unweighted += 1
        minimum = min(minimum, total)
        maximum = max(maximum, total)
    if unweighted:
        raise RuntimeError(f"{obj.name} has {unweighted} underweighted vertices")
    print(
        f"HEAD_WEIGHT|{obj.name}|vertices={len(obj.data.vertices)}|"
        f"min={minimum:.6f}|max={maximum:.6f}|unweighted={unweighted}"
    )
    checked += 1

if checked < 8:
    raise RuntimeError(f"Too few professional components were checked: {checked}")
print(f"HEAD_WEIGHT_VERIFY|PASS|components={checked}")
