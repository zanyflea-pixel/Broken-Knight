"""Print focused rest-pose bounds for integrated armor fit work."""

import bpy


rig = bpy.data.objects["HeroRig"]
print("REST_BONES_BEGIN")
for name in (
    "clavicle.L", "upper_arm.L", "forearm.L", "hand.L",
    "clavicle.R", "upper_arm.R", "forearm.R", "hand.R",
    "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
):
    bone = rig.data.bones[name]
    print(
        "%s|head=%s|tail=%s" % (
            name,
            tuple(round(value, 4) for value in bone.head_local),
            tuple(round(value, 4) for value in bone.tail_local),
        )
    )

print("ARMOR_FIT_BEGIN")
tokens = ("Gauntlet", "Vambrace", "Greave", "Sabaton", "Cuisse", "Rerebrace", "Arming")
for obj in bpy.data.objects:
    if obj.type != "MESH" or not obj.name.startswith("RoyalArmor_"):
        continue
    if not any(token in obj.name for token in tokens):
        continue
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    bounds = (
        min(point.x for point in points), max(point.x for point in points),
        min(point.y for point in points), max(point.y for point in points),
        min(point.z for point in points), max(point.z for point in points),
    )
    print(
        "%s|verts=%d|groups=%s|bounds=%s" % (
            obj.name, len(obj.data.vertices), [group.name for group in obj.vertex_groups],
            tuple(round(value, 4) for value in bounds),
        )
    )
