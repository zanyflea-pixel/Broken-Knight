"""Report posed foot clearance for the continuous hero walk."""

import os

import bpy


rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
rig.animation_data.action = bpy.data.actions["Walk"]
for frame in (1, 4, 7, 10, 13, 16, 19, 22):
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    positions = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
    left = min(point.z for point in positions if point.x < -0.05)
    right = min(point.z for point in positions if point.x > 0.05)
    minimum = min(point.z for point in positions)
    print(f"WALK_CLEARANCE|frame={frame}|min_z={minimum:.6f}|left={left:.6f}|right={right:.6f}")
