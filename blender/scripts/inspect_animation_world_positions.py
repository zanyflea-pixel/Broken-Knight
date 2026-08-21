"""Report world-space gait landmarks for animation tuning."""

import bpy


rig = bpy.data.objects["HeroRig"]
for action_name in ("Walk", "WarriorWalk", "TorchWalk", "StaffWalk"):
    rig.animation_data.action = bpy.data.actions[action_name]
    for frame in (1, 4, 7, 10, 13, 16, 19, 22):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        values = []
        for name in ("foot.L", "foot.R", "hand.L", "hand.R", "head", "pelvis"):
            bone = rig.pose.bones[name]
            point = rig.matrix_world @ bone.head
            values.append("%s=(%.3f,%.3f,%.3f)" % (name, point.x, point.y, point.z))
        print("ANIM_WORLD|%s|%d|%s" % (action_name, frame, "|".join(values)))
