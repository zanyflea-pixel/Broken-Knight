"""Focused dimensional audit for the full-body professional rebuild."""

import bpy
from mathutils import Vector


def bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        min(point.x for point in points), max(point.x for point in points),
        min(point.y for point in points), max(point.y for point in points),
        min(point.z for point in points), max(point.z for point in points),
    )


for name in ("HeroProfessionalTopology", "ConnectedBody"):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    print(
        f"FULL_REBUILD_SOURCE|{name}|verts={len(obj.data.vertices)}|faces={len(obj.data.polygons)}|"
        f"bounds={tuple(round(value, 5) for value in bounds(obj))}|"
        f"dimensions={tuple(round(value, 5) for value in obj.dimensions)}|"
        f"groups={len(obj.vertex_groups)}|modifiers={[(modifier.name, modifier.type) for modifier in obj.modifiers]}"
    )
    print("FULL_REBUILD_GROUPS|" + "|".join(group.name for group in obj.vertex_groups))
    for z_center in (0.05, 0.12, 0.30, 0.50, 0.75, 0.90, 1.02, 1.15, 1.30, 1.42, 1.50, 1.60, 1.72, 1.82):
        points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices if abs((obj.matrix_world @ vertex.co).z - z_center) < 0.0125]
        if points:
            xs = sorted(abs(point.x) for point in points)
            ys = sorted(point.y for point in points)
            print(
                f"FULL_REBUILD_SLICE|{name}|z={z_center:.2f}|count={len(points)}|"
                f"x90={xs[int(0.90*(len(xs)-1))]:.5f}|xmax={xs[-1]:.5f}|"
                f"y={ys[0]:.5f}:{ys[-1]:.5f}"
            )
    if name == "HeroProfessionalTopology":
        for group_name in (
            "joint-ground", "joint-pelvis", "joint-spine-1", "joint-spine-2", "joint-spine-3", "joint-spine-4",
            "joint-neck", "joint-head", "joint-head-2", "joint-jaw",
            "joint-l-clavicle", "joint-l-shoulder", "joint-l-elbow", "joint-l-hand",
            "joint-l-upper-leg", "joint-l-knee", "joint-l-ankle", "joint-l-foot-1", "joint-l-foot-2",
        ):
            group = obj.vertex_groups.get(group_name)
            if group is None:
                continue
            coords = []
            for vertex in obj.data.vertices:
                membership = next((item for item in vertex.groups if item.group == group.index and item.weight > 0.01), None)
                if membership is not None:
                    coords.append(obj.matrix_world @ vertex.co)
            if coords:
                center = sum(coords, Vector()) / len(coords)
                print(
                    f"FULL_REBUILD_JOINT|{group_name}|count={len(coords)}|"
                    f"center={tuple(round(value, 5) for value in center)}"
                )

rig = bpy.data.objects.get("HeroRig")
if rig is not None:
    print(f"FULL_REBUILD_RIG|scale={tuple(round(value, 5) for value in rig.scale)}|bones={len(rig.data.bones)}")
    for name in (
        "root", "pelvis", "spine", "chest", "neck", "head", "jaw",
        "clavicle.L", "upper_arm.L", "forearm.L", "hand.L",
        "thigh.L", "shin.L", "foot.L", "toe.L",
    ):
        bone = rig.data.bones.get(name)
        if bone is not None:
            print(
                f"FULL_REBUILD_BONE|{name}|head={tuple(round(value, 5) for value in bone.head_local)}|"
                f"tail={tuple(round(value, 5) for value in bone.tail_local)}"
            )
