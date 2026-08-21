"""Inspect transforms and nearest accepted-body weights for rear cloth."""

import bpy
from mathutils.kdtree import KDTree


body = bpy.data.objects["ConnectedBody"]
rig = bpy.data.objects["HeroRig"]
back = bpy.data.objects["Loincloth.Back.Refined"]
print(f"SKINNING|body_matrix={tuple(round(value, 5) for row in body.matrix_world for value in row)}")
print(f"SKINNING|rig_matrix={tuple(round(value, 5) for row in rig.matrix_world for value in row)}")
print(f"SKINNING|back_parent={back.parent_type},{back.parent_bone}|matrix={tuple(round(value, 5) for row in back.matrix_world for value in row)}")
print(f"SKINNING|body_modifiers={[(modifier.type, modifier.name) for modifier in body.modifiers]}")

tree = KDTree(len(body.data.vertices))
for vertex in body.data.vertices:
    tree.insert(vertex.co, vertex.index)
tree.balance()
for cloth_index in (0, 5, 10, 55, 60, 65, 110, 115, 120, 165, 170, 175):
    vertex = back.data.vertices[cloth_index]
    _co, nearest_index, distance = tree.find(vertex.co)
    nearest = body.data.vertices[nearest_index]
    weights = sorted(
        ((body.vertex_groups[group.group].name, group.weight) for group in nearest.groups),
        key=lambda item: item[1], reverse=True,
    )[:6]
    print(f"SKINNING|cloth={cloth_index}|co={tuple(round(v,4) for v in vertex.co)}|nearest={nearest_index}|distance={distance:.5f}|weights={weights}")
