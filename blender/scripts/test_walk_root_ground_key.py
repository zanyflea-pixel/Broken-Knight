"""Exercise a single grounded root key and report the resulting sole height."""

import bpy


rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
action = bpy.data.actions["Walk"]
rig.animation_data.action = action
root = rig.pose.bones["root"]


def minimum():
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)


bpy.context.scene.frame_set(1)
before = minimum()
print(f"GROUND_KEY_TEST|before={before:.6f}|root={tuple(root.location)}")
root.location.z -= before
inserted = root.keyframe_insert("location", frame=1, group=root.name)
bpy.context.view_layer.update()
print(f"GROUND_KEY_TEST|inserted={inserted}|after={minimum():.6f}|root={tuple(root.location)}")
