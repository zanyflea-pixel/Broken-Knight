"""Rebuild the hero's glutes from the clean pre-swelling body.

The two rejected lowering passes moved vertices vertically and left the rear
volume in the upper hamstrings.  This pass intentionally changes only X/Y:
it removes that low posterior bulge, establishes two connected glute lobes at
pelvis height, and leaves every vertex at its authored height.  The existing
loincloth is contour-fitted in depth only; it is not enlarged.
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
OUTPUT_BLEND = os.path.join(ROOT, "blender", "BrokenKnight_Hero_AnatomicalGluteRebuildCandidate.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_anatomical_glute_rebuild_candidate.glb")


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


def rebuild_glutes(body):
    before_z = [vertex.co.z for vertex in body.data.vertices]
    moved = 0
    maximum_add = 0.0
    maximum_remove = 0.0
    maximum_width_add = 0.0
    maximum_width_remove = 0.0

    for vertex in body.data.vertices:
        point = vertex.co
        abs_x = abs(point.x)
        if not (0.55 <= point.z <= 1.075 and point.y >= -0.10 and abs_x <= 0.235):
            continue

        posterior = smoothstep(-0.055, 0.045, point.y)
        side_fade = 1.0 - smoothstep(0.195, 0.230, abs_x)
        vertical_fade = smoothstep(0.55, 0.64, point.z) * (1.0 - smoothstep(1.01, 1.075, point.z))
        influence = posterior * side_fade * vertical_fade
        if influence <= 0.0001:
            continue

        # Two side lobes give the butt real volume while retaining the centre
        # cleft.  The high lobe peaks at pelvis height; the low subtraction
        # creates an under-fold and removes the old hamstring/calf-like mass.
        lobe = smoothstep(0.025, 0.065, abs_x) * (1.0 - smoothstep(0.175, 0.215, abs_x))
        glute = bell(point.z, 0.895, 0.105)
        underfold = bell(point.z, 0.715, 0.105)
        depth_add = 0.057 * glute * (0.44 + 0.56 * lobe) * influence
        depth_remove = 0.030 * underfold * (0.62 + 0.38 * lobe) * influence
        point.y += depth_add - depth_remove

        # Rear-view redistribution follows the same anatomy.  No Z movement
        # is allowed: this avoids shelves, bands, and displaced joint mass.
        width_add = 0.014 * glute * lobe * influence
        width_remove = 0.010 * underfold * lobe * influence
        point.x += (1.0 if point.x >= 0.0 else -1.0) * (width_add - width_remove)

        moved += 1
        maximum_add = max(maximum_add, depth_add)
        maximum_remove = max(maximum_remove, depth_remove)
        maximum_width_add = max(maximum_width_add, width_add)
        maximum_width_remove = max(maximum_width_remove, width_remove)

    for index, vertex in enumerate(body.data.vertices):
        if abs(vertex.co.z - before_z[index]) > 0.0000001:
            raise RuntimeError("A body vertex moved vertically")

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, maximum_add, maximum_remove, maximum_width_add, maximum_width_remove


def contour_panel(panel, body_tree, rear):
    before = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    inverse = panel.matrix_world.inverted()
    rows = {}
    for index, world in enumerate(before):
        rows.setdefault(round(world.z, 4), []).append(index)

    prior_delta = 0.0
    row_deltas = []
    for _z, indices in sorted(rows.items(), reverse=True):
        hits = []
        for index in indices:
            world = before[index]
            origin = Vector((world.x, 0.40 if rear else -0.40, world.z))
            direction = Vector((0.0, -1.0 if rear else 1.0, 0.0))
            hit = body_tree.ray_cast(origin, direction, 0.80)[0]
            if hit is not None:
                hits.append(hit.y)
        if hits:
            if rear:
                target = max(hits) + 0.019
                authored = max(before[index].y for index in indices)
            else:
                target = min(hits) - 0.009
                authored = min(before[index].y for index in indices)
            delta = max(-0.035, min(0.035, target - authored))
            prior_delta = delta
        else:
            delta = prior_delta
        row_deltas.append(delta)
        for index in indices:
            world = before[index].copy()
            world.y += delta
            panel.data.vertices[index].co = inverse @ world

    panel.data.update()
    after = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    for first, second in zip(before, after):
        if abs(first.x - second.x) > 0.00001 or abs(first.z - second.z) > 0.00001:
            raise RuntimeError("Loincloth width or height changed: %s" % panel.name)
    return min(row_deltas), max(row_deltas)


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    front = bpy.data.objects["Loincloth.Front.Refined"]
    back = bpy.data.objects["Loincloth.Back.Refined"]
    body_topology = topology_digest(body.data)
    front_topology = topology_digest(front.data)
    back_topology = topology_digest(back.data)

    stats = rebuild_glutes(body)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    body_tree = BVHTree.FromObject(body, depsgraph)
    front_delta = contour_panel(front, body_tree, False)
    back_delta = contour_panel(back, body_tree, True)

    if stats[0] < 450 or topology_digest(body.data) != body_topology:
        raise RuntimeError("Body rebuild failed or changed topology")
    if topology_digest(front.data) != front_topology or topology_digest(back.data) != back_topology:
        raise RuntimeError("Loincloth topology changed")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "ANATOMICAL_GLUTE_REBUILD_DONE|moved=%d|add=%.5f|remove=%.5f|width_add=%.5f|width_remove=%.5f|front=%.5f,%.5f|back=%.5f,%.5f|blend=%s|glb=%s"
        % (stats[0], stats[1], stats[2], stats[3], stats[4], front_delta[0], front_delta[1], back_delta[0], back_delta[1], OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
