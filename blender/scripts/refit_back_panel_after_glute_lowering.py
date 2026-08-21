"""Refit the existing rear panel after a body-only glute lowering pass."""

from hashlib import sha256
import os
import struct
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import refine_accepted_hero_layers as layers


ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_BLEND = os.path.join(ROOT, "blender", "BrokenKnight_Hero_LoweredGluteBodyOnlyCandidate.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_lowered_glute_body_only_candidate.glb")
BACK_CLEARANCE = 0.007


def topology_digest(mesh):
    result = sha256()
    for polygon in mesh.polygons:
        result.update(struct.pack("<I", len(polygon.vertices)))
        for index in polygon.vertices:
            result.update(struct.pack("<I", index))
    return result.hexdigest()


def main():
    back = bpy.data.objects["Loincloth.Back.Refined"]
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    topology_before = topology_digest(back.data)
    before = [back.matrix_world @ vertex.co for vertex in back.data.vertices]
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    body_tree = BVHTree.FromObject(body, depsgraph)
    inverse = back.matrix_world.inverted()

    # Fit each horizontal cloth row as a gentle span over the posterior body.
    # Using the row's maximum body depth prevents the cloth from sinking into
    # the glute cleft while still following the lowered silhouette by height.
    rows = {}
    for index, world in enumerate(before):
        rows.setdefault(round(world.z, 4), []).append(index)
    moved = 0
    last_row_delta = 0.0
    for indices in rows.values():
        hits = []
        for index in indices:
            world = before[index]
            hit = body_tree.ray_cast(Vector((world.x, 0.35, world.z)), Vector((0.0, -1.0, 0.0)), 0.70)[0]
            if hit is not None:
                hits.append(hit.y)
        if hits:
            target_center = max(hits) + BACK_CLEARANCE
            original_center = max(before[index].y for index in indices)
            row_delta = max(-0.032, min(0.008, target_center - original_center))
            last_row_delta = row_delta
        else:
            # The lowest three center vertices sit over the open cleft and
            # have no ray hit. Continue the nearest fitted row smoothly.
            row_delta = last_row_delta
        for index in indices:
            world = before[index].copy()
            # Preserve the panel's authored shallow curvature within each row.
            world.y += row_delta
            back.data.vertices[index].co = inverse @ world
            moved += 1
    back.data.update()
    after = [back.matrix_world @ vertex.co for vertex in back.data.vertices]
    if topology_digest(back.data) != topology_before:
        raise RuntimeError("Rear panel topology changed")
    if moved != len(back.data.vertices):
        raise RuntimeError("Rear panel contour fit missed vertices: %d/%d" % (moved, len(back.data.vertices)))
    for first, second in zip(before, after):
        if abs(second.x - first.x) > 0.00001 or abs(second.z - first.z) > 0.00001:
            raise RuntimeError("Rear panel width or raised position changed")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    changes = [second.y - first.y for first, second in zip(before, after)]
    print(
        "BACK_PANEL_REFIT_DONE|clearance=%.5f|depth_delta=%.5f,%.5f|blend=%s|glb=%s"
        % (BACK_CLEARANCE, min(changes), max(changes), OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
