"""Report how root pose translation maps to world-space body height."""

import bpy


rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
root = rig.pose.bones["root"]


def body_minimum():
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)


rig.animation_data.action = None
for bone in rig.pose.bones:
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = (0.0, 0.0, 0.0)
    bone.location = (0.0, 0.0, 0.0)
bpy.context.scene.frame_set(0)
baseline = body_minimum()
print(f"ROOT_AXIS|baseline={baseline:.6f}")
for axis in range(3):
    root.location = (0.0, 0.0, 0.0)
    root.location[axis] = 0.10
    print(f"ROOT_AXIS|axis={axis}|positive|min_z={body_minimum():.6f}")
    root.location[axis] = -0.10
    print(f"ROOT_AXIS|axis={axis}|negative|min_z={body_minimum():.6f}")

rig.animation_data.action = bpy.data.actions["Walk"]
for frame in (1, 4, 7, 10):
    bpy.context.scene.frame_set(frame)
    print(f"ROOT_KEY|frame={frame}|location={tuple(round(value, 6) for value in root.location)}|min_z={body_minimum():.6f}")
