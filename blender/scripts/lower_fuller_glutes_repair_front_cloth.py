"""Lower and add mass to the glutes, then refit both original cloth panels.

The connected body keeps its topology and weights.  The six-piece raised
loincloth keeps its width, height, materials, and construction; only panel
depth is contoured to the revised anatomy so no section disappears into skin.
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
OUTPUT_BLEND = os.path.join(ROOT, "blender", "BrokenKnight_Hero_LowerFullerButtCandidate.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_lower_fuller_butt_candidate.glb")


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


def lower_and_build_mass(body):
    moved = 0
    maximum_down = 0.0
    maximum_depth = 0.0
    maximum_width = 0.0
    for vertex in body.data.vertices:
        point = vertex.co
        abs_x = abs(point.x)
        if not (0.50 <= point.z <= 1.10 and point.y >= -0.16 and abs_x <= 0.235):
            continue

        posterior = smoothstep(-0.16, 0.005, point.y)
        side_fade = 1.0 - smoothstep(0.205, 0.235, abs_x)
        vertical_window = smoothstep(0.50, 0.64, point.z) * (1.0 - smoothstep(1.00, 1.10, point.z))
        influence = posterior * side_fade * vertical_window
        if influence <= 0.0001:
            continue

        # Lower the whole posterior mass another two centimetres. The wide
        # transition band avoids the horizontal shelf produced by early passes.
        down = 0.020 * influence
        point.z -= down

        # Build a clearly fuller lower glute belly and gently reduce the old
        # high point. This moves the visual apex down instead of growing the
        # upper thigh uniformly. Side-lobe gating retains a natural cleft.
        lobe = smoothstep(0.028, 0.075, abs_x) * (1.0 - smoothstep(0.185, 0.220, abs_x))
        lower_belly = bell(point.z, 0.735, 0.115)
        high_shelf = bell(point.z, 0.915, 0.105)
        depth = posterior * side_fade * (0.026 * lower_belly * (0.58 + 0.42 * lobe) - 0.006 * high_shelf)
        point.y += depth

        # A small lateral addition gives the lower lobe mass in rear view; it
        # fades before the hip and inner cleft rather than widening the pelvis.
        width = posterior * lobe * lower_belly * 0.008
        point.x += (1.0 if point.x >= 0.0 else -1.0) * width

        moved += 1
        maximum_down = max(maximum_down, down)
        maximum_depth = max(maximum_depth, depth)
        maximum_width = max(maximum_width, width)

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, maximum_down, maximum_depth, maximum_width


def contour_panel(panel, body_tree, rear):
    before = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    inverse = panel.matrix_world.inverted()
    rows = {}
    for index, world in enumerate(before):
        rows.setdefault(round(world.z, 4), []).append(index)

    fitted = 0
    prior_delta = 0.0
    row_deltas = []
    for _z, indices in sorted(rows.items(), reverse=True):
        hits = []
        for index in indices:
            world = before[index]
            origin = Vector((world.x, 0.38 if rear else -0.38, world.z))
            direction = Vector((0.0, -1.0 if rear else 1.0, 0.0))
            hit = body_tree.ray_cast(origin, direction, 0.76)[0]
            if hit is not None:
                hits.append(hit.y)
        if hits:
            if rear:
                # Rear skin expands and twists under thigh deformation. The
                # static surface needs nearly two centimetres of authored air
                # so the panel stays outside it throughout Walk and Jump.
                target = max(hits) + 0.0190
                authored_surface = max(before[index].y for index in indices)
            else:
                target = min(hits) - 0.0090
                authored_surface = min(before[index].y for index in indices)
            delta = max(-0.035, min(0.020, target - authored_surface))
            prior_delta = delta
        else:
            delta = prior_delta
        row_deltas.append(delta)
        for index in indices:
            world = before[index].copy()
            world.y += delta
            panel.data.vertices[index].co = inverse @ world
            fitted += 1
    panel.data.update()
    if fitted != len(panel.data.vertices):
        raise RuntimeError("Panel contour fit missed vertices: %s" % panel.name)
    after = [panel.matrix_world @ vertex.co for vertex in panel.data.vertices]
    for first, second in zip(before, after):
        if abs(second.x - first.x) > 0.00001 or abs(second.z - first.z) > 0.00001:
            raise RuntimeError("Panel size or raised height changed: %s" % panel.name)
    return min(row_deltas), max(row_deltas)


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    body_topology = topology_digest(body.data)
    front = bpy.data.objects["Loincloth.Front.Refined"]
    back = bpy.data.objects["Loincloth.Back.Refined"]
    front_topology = topology_digest(front.data)
    back_topology = topology_digest(back.data)

    moved, down, depth, width = lower_and_build_mass(body)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    body_tree = BVHTree.FromObject(body, depsgraph)
    front_delta = contour_panel(front, body_tree, False)
    back_delta = contour_panel(back, body_tree, True)

    if moved < 500 or topology_digest(body.data) != body_topology:
        raise RuntimeError("Body correction failed or changed topology")
    if topology_digest(front.data) != front_topology or topology_digest(back.data) != back_topology:
        raise RuntimeError("Loincloth topology changed")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "LOWER_FULLER_BUTT_DONE|moved=%d|down=%.5f|depth=%.5f|width=%.5f|front=%.5f,%.5f|back=%.5f,%.5f|blend=%s|glb=%s"
        % (moved, down, depth, width, front_delta[0], front_delta[1], back_delta[0], back_delta[1], OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
