"""Lower the accepted glute anatomy without changing the accepted loincloth.

This pass exists specifically because enlarging the rear cloth was rejected.
Only ConnectedBody vertex positions are edited. Every loincloth mesh, curve,
material, modifier, parent, and vertex group is hashed before/after and must
remain byte-identical inside Blender's data model.
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
    "BK_GLUTE_BODY_ONLY_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_LoweredGluteBodyOnlyCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_GLUTE_BODY_ONLY_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_lowered_glute_body_only_candidate.glb"),
)
GLUTE_LOWER_AMOUNT = float(os.environ.get("BK_GLUTE_LOWER_AMOUNT", "0.040"))


def smoothstep(edge0, edge1, value):
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def bell(value, center, radius):
    return exp(-((value - center) / radius) ** 2)


def mesh_digest(mesh):
    result = sha256()
    for vertex in mesh.vertices:
        result.update(struct.pack("<3f", *vertex.co))
    for polygon in mesh.polygons:
        result.update(struct.pack("<I", len(polygon.vertices)))
        for index in polygon.vertices:
            result.update(struct.pack("<I", index))
    return result.hexdigest()


def cloth_digest():
    """Hash all accepted cloth geometry and object-level construction data."""
    result = sha256()
    cloth = sorted(
        (
            obj for obj in bpy.data.objects
            if obj.name.startswith(("Loincloth", "ClothWaistCord", "LoinTie", "LoinKnot", "LoinTail"))
        ),
        key=lambda obj: obj.name,
    )
    if not cloth:
        raise RuntimeError("No accepted loincloth objects found")
    for obj in cloth:
        result.update(obj.name.encode("utf8"))
        result.update(obj.type.encode("ascii"))
        result.update(str(tuple(tuple(row) for row in obj.matrix_world)).encode("ascii"))
        result.update((obj.parent.name if obj.parent else "").encode("utf8"))
        result.update(obj.parent_type.encode("ascii"))
        result.update(obj.parent_bone.encode("utf8"))
        for modifier in obj.modifiers:
            result.update((modifier.name + "|" + modifier.type).encode("utf8"))
        for slot in obj.material_slots:
            result.update((slot.material.name if slot.material else "").encode("utf8"))
        if obj.type == "MESH":
            result.update(mesh_digest(obj.data).encode("ascii"))
            for group in obj.vertex_groups:
                result.update(group.name.encode("utf8"))
        elif obj.type == "CURVE":
            for spline in obj.data.splines:
                result.update(spline.type.encode("ascii"))
                points = spline.bezier_points if spline.type == "BEZIER" else spline.points
                for point in points:
                    result.update(struct.pack("<3f", *point.co[:3]))
    return result.hexdigest(), tuple(obj.name for obj in cloth)


def lower_glutes(body):
    """Translate the posterior glute mass down behind the accepted cloth."""
    moved = 0
    max_vertical = 0.0
    max_inward = 0.0
    max_depth_change = 0.0
    for vertex in body.data.vertices:
        point = vertex.co
        original = point.copy()
        if not (0.46 <= point.z <= 1.18 and point.y >= -0.255 and abs(point.x) <= 0.255):
            continue

        posterior = smoothstep(-0.255, -0.025, point.y)
        side_limit = 1.0 - smoothstep(0.218, 0.255, abs(point.x))
        upper_fade = 1.0 - smoothstep(1.040, 1.175, point.z)
        lower_fade = smoothstep(0.465, 0.620, point.z)
        anatomy = posterior * side_limit * upper_fade * lower_fade
        if anatomy <= 0.0001:
            continue

        vertical = GLUTE_LOWER_AMOUNT * anatomy
        point.z -= vertical

        # Give the unchanged narrow panel clearance using one continuous field,
        # rather than clamping isolated vertices to its surface.  The latter
        # caused the rejected notch at the inner thigh and a shelf at the hip.
        panel_width = 1.0 - smoothstep(0.105, 0.158, abs(point.x))
        panel_height = smoothstep(0.650, 0.720, point.z) * (
            1.0 - smoothstep(0.955, 1.025, point.z)
        )
        inward = 0.0145 * posterior * panel_width * panel_height
        point.y -= inward

        moved += 1
        max_vertical = max(max_vertical, vertical)
        max_inward = max(max_inward, inward)
        max_depth_change = max(max_depth_change, inward)

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, max_vertical, max_inward, max_depth_change


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    cloth_before, cloth_names_before = cloth_digest()
    body_before = mesh_digest(body.data)
    moved, max_vertical, max_inward, max_depth = lower_glutes(body)
    body_after = mesh_digest(body.data)
    cloth_after, cloth_names_after = cloth_digest()
    if body_before == body_after or moved < 300:
        raise RuntimeError("Body-only glute correction did not affect the expected region")
    if cloth_before != cloth_after or cloth_names_before != cloth_names_after:
        raise RuntimeError("Rejected: original loincloth changed during body-only correction")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    cloth_export_check, _names = cloth_digest()
    if cloth_export_check != cloth_before:
        raise RuntimeError("Rejected: export preparation changed the original loincloth")
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "BODY_ONLY_GLUTE_DONE|moved=%d|max_vertical=%.5f|max_inward=%.5f|max_depth=%.5f|"
        "cloth=%s|body_before=%s|body_after=%s|blend=%s|glb=%s"
        % (
            moved, max_vertical, max_inward, max_depth, cloth_before,
            body_before, body_after, OUTPUT_BLEND, OUTPUT_GLB,
        )
    )


if __name__ == "__main__":
    main()
