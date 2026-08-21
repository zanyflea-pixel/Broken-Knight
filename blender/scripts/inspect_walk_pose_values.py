"""Print evaluated Walk transforms for selected hero bones."""

import bpy


rig = bpy.data.objects["HeroRig"]
rig.animation_data.action = bpy.data.actions["Walk"]
for frame in (1, 4, 7, 10, 13, 16, 19, 22):
    bpy.context.scene.frame_set(frame)
    values = []
    for name in ("root", "pelvis", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "upper_arm.L", "forearm.L", "upper_arm.R", "forearm.R"):
        bone = rig.pose.bones[name]
        rotation = tuple(round(value * 57.2957795, 2) for value in bone.rotation_euler)
        location = tuple(round(value, 4) for value in bone.location)
        values.append(f"{name}=R{rotation}L{location}")
    print(f"WALK_POSE|{frame}|" + "|".join(values))
