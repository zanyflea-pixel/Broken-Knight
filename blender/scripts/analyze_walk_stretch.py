"""Find body edges that stretch abnormally in a keyed walk pose."""

import bpy


arm = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
arm.animation_data.action = bpy.data.actions["Walk"]
bpy.context.scene.frame_set(13)
bpy.context.view_layer.update()

evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
posed = evaluated.to_mesh()
records = []
for edge in body.data.edges:
    a, b = edge.vertices
    rest_a = body.data.vertices[a].co
    rest_b = body.data.vertices[b].co
    pose_a = posed.vertices[a].co
    pose_b = posed.vertices[b].co
    rest_length = (rest_a - rest_b).length
    pose_length = (pose_a - pose_b).length
    if rest_length > 1e-8:
        records.append((pose_length / rest_length, pose_length, a, b))

records.sort(reverse=True)
for ratio, length, a, b in records[:40]:
    ra = body.data.vertices[a].co
    rb = body.data.vertices[b].co
    pa = posed.vertices[a].co
    pb = posed.vertices[b].co
    print(
        "EDGE|ratio=%.2f|len=%.4f|v=%d,%d|rest=(%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)|pose=(%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)"
        % (ratio, length, a, b, *ra, *rb, *pa, *pb)
    )

evaluated.to_mesh_clear()
