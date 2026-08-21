"""Lower the accepted hero's glute mass and refit only the loincloth.

Hair, brows, face, limbs, rig, and all animation actions remain untouched.
The deformation is deliberately broad and weight-preserving: it moves the
posterior pelvis surface down without separating or remeshing ConnectedBody.
"""

from hashlib import sha256
from math import exp
import os
import struct
import sys

import bpy
import bmesh


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import refine_accepted_hero_layers as layers


ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_BLEND = os.environ.get(
    "BK_GLUTE_OUTPUT_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_LoweredGluteCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_GLUTE_OUTPUT_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_lowered_glute_candidate.glb"),
)


def smoothstep(edge0, edge1, value):
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def digest(body):
    result = sha256()
    for vertex in body.data.vertices:
        result.update(struct.pack("<3f", *vertex.co))
    return result.hexdigest()


def lower_glute_mass(body):
    moved = 0
    maximum_shift = 0.0
    for vertex in body.data.vertices:
        point = vertex.co
        if point.z < 0.70 or point.z > 1.11 or point.y < -0.035 or abs(point.x) > 0.19:
            continue

        posterior = smoothstep(-0.035, 0.050, point.y)
        side_fade = 1.0 - smoothstep(0.155, 0.19, abs(point.x))
        region = posterior * side_fade
        if region <= 0.0001:
            continue

        # Smooth Gaussian volume transfer: pull in the old high projection and
        # restore it around the lower glute belly. Unlike stacked smoothstep
        # bands, this has no horizontal transition plateau.
        high_shelf = exp(-((point.z - 0.995) / 0.082) ** 2)
        lower_belly = exp(-((point.z - 0.865) / 0.105) ** 2)
        lobe = smoothstep(0.010, 0.050, abs(point.x)) * (1.0 - smoothstep(0.140, 0.185, abs(point.x)))
        reduction = 0.0260 * region * high_shelf
        addition = 0.0275 * region * lower_belly * (0.64 + 0.36 * lobe)
        point.y += addition - reduction

        # A small, broad vertical drift carries the lower surface down without
        # creating a boundary crease; silhouette lowering comes mainly from
        # the posterior redistribution above.
        vertical_window = exp(-((point.z - 0.900) / 0.175) ** 2)
        shift = 0.012 * region * vertical_window
        point.z -= shift

        moved += 1
        maximum_shift = max(maximum_shift, shift)

    # Blend neighboring posterior rows gently in Y only. This keeps the leg
    # length and rig joints fixed while removing topology-row banding.
    adjacency = {vertex.index: set() for vertex in body.data.vertices}
    for edge in body.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    for _iteration in range(3):
        original_y = [vertex.co.y for vertex in body.data.vertices]
        for vertex in body.data.vertices:
            point = vertex.co
            region = (
                smoothstep(-0.025, 0.060, point.y)
                * (1.0 - smoothstep(0.155, 0.19, abs(point.x)))
                * smoothstep(0.70, 0.78, point.z)
                * (1.0 - smoothstep(1.04, 1.11, point.z))
            )
            neighbors = adjacency[vertex.index]
            if region <= 0.0 or not neighbors:
                continue
            average_y = sum(original_y[index] for index in neighbors) / len(neighbors)
            point.y += (average_y - point.y) * 0.16 * region

    # Recalculate shading normals after the sculpt. Keeping the pre-sculpt
    # normals was responsible for the false horizontal stripe in diagnostics.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, maximum_shift


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    before = digest(body)
    moved, maximum_shift = lower_glute_mass(body)
    after = digest(body)
    if before == after or moved < 300:
        raise RuntimeError("Glute correction did not affect the expected continuous-body region")

    layers.rebuild_loincloth(body, rig)

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "LOWER_GLUTE_DONE|moved=%d|max_shift=%.5f|before=%s|after=%s|blend=%s|glb=%s"
        % (moved, maximum_shift, before, after, OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
