"""Print rear pelvis surface samples for anatomical correction planning."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


body = bpy.data.objects["ConnectedBody"]
depsgraph = bpy.context.evaluated_depsgraph_get()
depsgraph.update()
tree = BVHTree.FromObject(body, depsgraph)

print("GLUTE_PROFILE_BEGIN")
for z in (1.04, 1.02, 1.00, .98, .96, .94, .92, .90, .88, .86, .84, .82, .80, .78, .76, .74, .72):
    samples = []
    for x in (0.0, .025, .05, .075, .10, .125, .15, .175, .19, .205):
        hit = tree.ray_cast(Vector((x, .55, z)), Vector((0.0, -1.0, 0.0)), 1.1)
        samples.append(None if hit[0] is None else round(hit[0].y, 5))
    print(f"GLUTE_PROFILE|z={z:.3f}|y={samples}")

for group_name in ("pelvis", "spine", "thigh.L", "thigh.R"):
    group = body.vertex_groups.get(group_name)
    if group is None:
        print(f"GLUTE_GROUP|{group_name}|missing")
        continue
    weighted = []
    for vertex in body.data.vertices:
        try:
            weight = group.weight(vertex.index)
        except RuntimeError:
            continue
        if weight > .02 and vertex.co.y > .02 and .68 < vertex.co.z < 1.08:
            weighted.append((vertex.co.z, vertex.co.y, weight))
    print(f"GLUTE_GROUP|{group_name}|count={len(weighted)}|z={min((v[0] for v in weighted), default=0):.4f},{max((v[0] for v in weighted), default=0):.4f}|ymax={max((v[1] for v in weighted), default=0):.4f}")
print("GLUTE_PROFILE_END")
