"""Print compact world-space landmarks used by the royal armor finish pass."""

import bpy


def bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return (
        min(point.x for point in points), max(point.x for point in points),
        min(point.y for point in points), max(point.y for point in points),
        min(point.z for point in points), max(point.z for point in points),
    )


for name in ("ConnectedBody", "ProfessionalEyes", "HeroHairFoundation"):
    matches = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name.startswith(name)]
    for obj in matches:
        print("ARMOR_LANDMARK|%s|bounds=%s" % (obj.name, ",".join(f"{value:.4f}" for value in bounds(obj))))

rig = bpy.data.objects["HeroRig"]
for bone_name in ("head", "neck", "chest", "pelvis", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"):
    bone = rig.data.bones.get(bone_name)
    if bone:
        head = rig.matrix_world @ bone.head_local
        tail = rig.matrix_world @ bone.tail_local
        print(f"ARMOR_BONE|{bone_name}|head={head.x:.4f},{head.y:.4f},{head.z:.4f}|tail={tail.x:.4f},{tail.y:.4f},{tail.z:.4f}")
