"""Print rear body/cloth depth samples for a body-only glute correction."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


depsgraph = bpy.context.evaluated_depsgraph_get()
depsgraph.update()
body = bpy.data.objects["ConnectedBody"]
cloth = bpy.data.objects["Loincloth.Back.Refined"]
body_tree = BVHTree.FromObject(body, depsgraph)
cloth_tree = BVHTree.FromObject(cloth, depsgraph)

print("REAR_DEPTH_BEGIN")
for z in (1.00, .96, .92, .88, .84, .80, .76, .72, .68):
    row = []
    for x in (0.0, .05, .10, .115, .13, .15, .18):
        origin = Vector((x, .40, z))
        direction = Vector((0.0, -1.0, 0.0))
        bhit = body_tree.ray_cast(origin, direction, .8)[0]
        chit = cloth_tree.ray_cast(origin, direction, .8)[0]
        by = None if bhit is None else round(bhit.y, 5)
        cy = None if chit is None else round(chit.y, 5)
        row.append((x, by, cy, None if by is None or cy is None else round(cy - by, 5)))
    print(f"REAR_DEPTH|z={z:.3f}|samples={row}")
print("REAR_DEPTH_END")
