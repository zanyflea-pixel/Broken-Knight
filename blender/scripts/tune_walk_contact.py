"""Measure candidate contact-leg variants without modifying the source file."""

from math import radians

import bpy


rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
rig.animation_data.action = bpy.data.actions["Walk"]
bpy.context.scene.frame_set(1)


def foot_heights():
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    positions = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
    return (
        min(point.z for point in positions if point.x < -0.05),
        min(point.z for point in positions if point.x > 0.05),
    )


for thigh in (12, 16, 20, 24, 28):
    for knee in (10, 20, 30, 40, 50):
        bone = rig.pose.bones["thigh.R"]
        bone.rotation_euler = (radians(thigh), 0.0, radians(-0.48 * thigh))
        rig.pose.bones["shin.R"].rotation_euler = (radians(knee), 0.0, 0.0)
        left, right = foot_heights()
        print(f"CONTACT_TUNE|trailing_thigh={thigh}|trailing_knee={knee}|left={left:.6f}|right={right:.6f}|gap={left-right:.6f}")
