"""Move misplaced low-leg volume back into an anatomical glute region.

This pass preserves the repaired front loincloth exactly. It removes the
previous low posterior bulge, rebuilds the glute lobe around the pelvis, and
lifts the posterior apex modestly. The original rear panel is only contour-fit
in depth for deformation clearance; its width, height, and topology stay fixed.
"""

from hashlib import sha256
from math import exp
import os
import struct
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import refine_accepted_hero_layers as layers


ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_BLEND = os.path.join(ROOT, "blender", "BrokenKnight_Hero_AnatomicalGluteRebalanceCandidate.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_anatomical_glute_rebalance_candidate.glb")


def smoothstep(edge0, edge1, value):
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def bell(value, center, radius):
    return exp(-((value - center) / radius) ** 2)


def topology_digest(mesh):
    result = sha256()
    result.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for polygon in mesh.polygons:
        result.update(struct.pack("<I", len(polygon.vertices)))
        for index in polygon.vertices:
            result.update(struct.pack("<I", index))
    return result.hexdigest()


def geometry_digest(mesh):
    result = sha256()
    for vertex in mesh.vertices:
        result.update(struct.pack("<3f", *vertex.co))
    result.update(topology_digest(mesh).encode("ascii"))
    return result.hexdigest()


def rebalance_body(body):
    moved = 0
    maximum_lift = 0.0
    maximum_upper_add = 0.0
    maximum_low_remove = 0.0
    for vertex in body.data.vertices:
        point = vertex.co
        abs_x = abs(point.x)
        if not (0.53 <= point.z <= 1.08 and point.y >= -0.17 and abs_x <= 0.235):
            continue

        posterior = smoothstep(-0.17, 0.005, point.y)
        side_fade = 1.0 - smoothstep(0.205, 0.235, abs_x)
        lobe = smoothstep(0.028, 0.072, abs_x) * (1.0 - smoothstep(0.185, 0.220, abs_x))
        influence = posterior * side_fade
        if influence <= 0.0001:
            continue

        # Remove the mass that was mistakenly centered near the upper
        # hamstring, then restore more of it at the actual glute belly.
        low_excess = bell(point.z, 0.700, 0.135)
        glute_belly = bell(point.z, 0.870, 0.120)
        low_remove = 0.034 * influence * low_excess * (0.52 + 0.48 * lobe)
        upper_add = 0.043 * influence * glute_belly * (0.55 + 0.45 * lobe)
        point.y += upper_add - low_remove

        # Rear-view volume follows the same redistribution. It stops before
        # the pelvis edge and inner cleft, so this creates two glute lobes
        # instead of another wide thigh cylinder.
        width_delta = influence * lobe * (0.0110 * glute_belly - 0.0090 * low_excess)
        point.x += (1.0 if point.x >= 0.0 else -1.0) * width_delta

        # Lift only the posterior glute field. Broad fades keep the lumbar and
        # hamstring transitions smooth while moving the apex visibly upward.
        lift = 0.022 * influence * bell(point.z, 0.815, 0.165)
        point.z += lift

        moved += 1
        maximum_lift = max(maximum_lift, lift)
        maximum_upper_add = max(maximum_upper_add, upper_add)
        maximum_low_remove = max(maximum_low_remove, low_remove)

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, maximum_lift, maximum_upper_add, maximum_low_remove


def contour_rear_panel(panel, body):
    before = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    inverse = panel.matrix_world.inverted()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    rows = {}
    for index, world in enumerate(before):
        rows.setdefault(round(world.z, 4), []).append(index)

    previous_delta = 0.0
    deltas = []
    for _z, indices in sorted(rows.items(), reverse=True):
        hits = []
        for index in indices:
            world = before[index]
            hit = tree.ray_cast(Vector((world.x, 0.40, world.z)), Vector((0.0, -1.0, 0.0)), 0.80)[0]
            if hit is not None:
                hits.append(hit.y)
        if hits:
            target = max(hits) + 0.019
            authored = max(before[index].y for index in indices)
            delta = max(-0.030, min(0.024, target - authored))
            previous_delta = delta
        else:
            delta = previous_delta
        deltas.append(delta)
        for index in indices:
            world = before[index].copy()
            world.y += delta
            panel.data.vertices[index].co = inverse @ world
    panel.data.update()

    after = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    for first, second in zip(before, after):
        if abs(first.x - second.x) > 0.00001 or abs(first.z - second.z) > 0.00001:
            raise RuntimeError("Rear panel width or height changed")
    return min(deltas), max(deltas)


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    front = bpy.data.objects["Loincloth.Front.Refined"]
    back = bpy.data.objects["Loincloth.Back.Refined"]
    body_topology = topology_digest(body.data)
    front_before = geometry_digest(front.data)
    back_topology = topology_digest(back.data)

    moved, lift, upper_add, low_remove = rebalance_body(body)
    rear_delta = contour_rear_panel(back, body)

    if moved < 500 or topology_digest(body.data) != body_topology:
        raise RuntimeError("Body rebalance failed or changed topology")
    if geometry_digest(front.data) != front_before:
        raise RuntimeError("Repaired front loincloth changed")
    if topology_digest(back.data) != back_topology:
        raise RuntimeError("Rear loincloth topology changed")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    if geometry_digest(front.data) != front_before:
        raise RuntimeError("Export preparation changed repaired front loincloth")
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "ANATOMICAL_GLUTE_REBALANCE_DONE|moved=%d|lift=%.5f|upper_add=%.5f|low_remove=%.5f|rear=%.5f,%.5f|blend=%s|glb=%s"
        % (moved, lift, upper_add, low_remove, rear_delta[0], rear_delta[1], OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
