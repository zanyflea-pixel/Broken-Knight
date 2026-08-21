"""Lower the accepted glute anatomy further and raise the original loincloth.

The garment is translated as one six-object set.  It is not rebuilt, scaled,
or widened.  ConnectedBody keeps its topology, weights, and modifiers; only a
broad posterior vertex field is moved to lower the glute mass further.
"""

from hashlib import sha256
import os
import struct
import sys

import bpy
import bmesh
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import refine_accepted_hero_layers as layers


ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_BLEND = os.environ.get(
    "BK_GLUTE_CLOTH_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_LowerButtRaisedLoinclothCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_GLUTE_CLOTH_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_lower_butt_raised_loincloth_candidate.glb"),
)
LOINCLOTH_PREFIXES = ("Loincloth", "ClothWaistCord", "LoinTie", "LoinKnot", "LoinTail")
LOINCLOTH_RAISE = 0.035
FRONT_DEPTH_OFFSET = -0.014
BACK_DEPTH_OFFSET = 0.010
CORD_RADIAL_OFFSET = 0.012


def smoothstep(edge0, edge1, value):
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def mesh_topology_digest(mesh):
    result = sha256()
    result.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for polygon in mesh.polygons:
        result.update(struct.pack("<I", len(polygon.vertices)))
        for index in polygon.vertices:
            result.update(struct.pack("<I", index))
    return result.hexdigest()


def garment_objects():
    objects = sorted(
        (obj for obj in bpy.data.objects if obj.name.startswith(LOINCLOTH_PREFIXES)),
        key=lambda obj: obj.name,
    )
    if len(objects) != 6:
        raise RuntimeError("Expected the accepted six-object loincloth, found %d" % len(objects))
    return objects


def world_points(obj):
    if obj.type == "MESH":
        return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    points = []
    if obj.type == "CURVE":
        for spline in obj.data.splines:
            source = spline.bezier_points if spline.type == "BEZIER" else spline.points
            points.extend(obj.matrix_world @ point.co.xyz for point in source)
    return points


def garment_signature(objects):
    signature = {}
    for obj in objects:
        points = world_points(obj)
        if not points:
            raise RuntimeError("Loincloth object has no geometry: %s" % obj.name)
        bounds = (
            min(point.x for point in points), max(point.x for point in points),
            min(point.y for point in points), max(point.y for point in points),
            min(point.z for point in points), max(point.z for point in points),
        )
        topology = mesh_topology_digest(obj.data) if obj.type == "MESH" else (
            tuple((spline.type, len(spline.bezier_points if spline.type == "BEZIER" else spline.points)) for spline in obj.data.splines)
        )
        signature[obj.name] = {
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else "",
            "parent_type": obj.parent_type,
            "parent_bone": obj.parent_bone,
            "materials": tuple(slot.material.name if slot.material else "" for slot in obj.material_slots),
            "modifiers": tuple((modifier.name, modifier.type) for modifier in obj.modifiers),
            "bounds": bounds,
            "topology": topology,
        }
    return signature


def raise_original_garment(objects):
    for obj in objects:
        world_delta = Vector((0.0, 0.0, LOINCLOTH_RAISE))
        if obj.name.startswith("Loincloth.Front"):
            world_delta.y += FRONT_DEPTH_OFFSET
        elif obj.name.startswith("Loincloth.Back"):
            world_delta.y += BACK_DEPTH_OFFSET
        elif obj.name.startswith(("Loincloth.HipKnot", "Loincloth.TieTail")):
            world_delta.y += FRONT_DEPTH_OFFSET * 0.65
        local_delta = obj.matrix_world.inverted().to_3x3() @ world_delta
        if obj.type == "MESH":
            if obj.name.startswith("Loincloth.WaistCord"):
                inverse = obj.matrix_world.inverted()
                for vertex in obj.data.vertices:
                    world = obj.matrix_world @ vertex.co
                    radial = Vector((world.x, world.y, 0.0))
                    if radial.length > 0.0001:
                        radial.normalize()
                        world += radial * CORD_RADIAL_OFFSET
                    world.z += LOINCLOTH_RAISE
                    vertex.co = inverse @ world
            else:
                for vertex in obj.data.vertices:
                    vertex.co += local_delta
            obj.data.update()
        elif obj.type == "CURVE":
            for spline in obj.data.splines:
                points = spline.bezier_points if spline.type == "BEZIER" else spline.points
                for point in points:
                    point.co.xyz += local_delta


def assert_preserved_and_refit(before, after):
    for name, first in before.items():
        second = after[name]
        for field in ("type", "parent", "parent_type", "parent_bone", "materials", "modifiers", "topology"):
            if first[field] != second[field]:
                raise RuntimeError("Original loincloth construction changed: %s/%s" % (name, field))
        fb = first["bounds"]
        sb = second["bounds"]
        # Extents remain identical for the panels/ties; the cord is expanded
        # radially just enough to sit on the narrower waist at its new height.
        if not name.startswith("Loincloth.WaistCord"):
            for first_axis, second_axis in ((0, 1), (2, 3)):
                if abs((fb[first_axis + 1] - fb[first_axis]) - (sb[second_axis] - sb[first_axis])) > 0.00001:
                    raise RuntimeError("Original loincloth dimensions changed: %s" % name)
        if abs((sb[4] - fb[4]) - LOINCLOTH_RAISE) > 0.00001 or abs((sb[5] - fb[5]) - LOINCLOTH_RAISE) > 0.00001:
            raise RuntimeError("Original loincloth was not raised uniformly: %s" % name)


def lower_glutes_further(body):
    moved = 0
    maximum_shift = 0.0
    maximum_clearance = 0.0
    for vertex in body.data.vertices:
        point = vertex.co
        if not (0.44 <= point.z <= 1.18 and point.y >= -0.255 and abs(point.x) <= 0.255):
            continue

        posterior = smoothstep(-0.255, -0.025, point.y)
        side_fade = 1.0 - smoothstep(0.218, 0.255, abs(point.x))
        upper_fade = 1.0 - smoothstep(1.035, 1.175, point.z)
        lower_fade = smoothstep(0.445, 0.605, point.z)
        influence = posterior * side_fade * upper_fade * lower_fade
        if influence <= 0.0001:
            continue

        shift = 0.030 * influence
        point.z -= shift

        # Maintain clearance behind the raised, unchanged panel with a very
        # small continuous depth adjustment.  This is not a shape change to
        # the garment and avoids skin flashing through during Walk/Jump.
        panel_width = 1.0 - smoothstep(0.105, 0.160, abs(point.x))
        panel_height = smoothstep(0.690, 0.755, point.z) * (
            1.0 - smoothstep(0.985, 1.060, point.z)
        )
        clearance = 0.0045 * posterior * panel_width * panel_height
        point.y -= clearance

        moved += 1
        maximum_shift = max(maximum_shift, shift)
        maximum_clearance = max(maximum_clearance, clearance)

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return moved, maximum_shift, maximum_clearance


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    objects = garment_objects()
    garment_before = garment_signature(objects)
    body_before = mesh_topology_digest(body.data)

    moved, maximum_shift, maximum_clearance = lower_glutes_further(body)
    raise_original_garment(objects)

    garment_after = garment_signature(objects)
    assert_preserved_and_refit(garment_before, garment_after)
    if mesh_topology_digest(body.data) != body_before or moved < 300:
        raise RuntimeError("Body topology changed or expected posterior region was not moved")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    assert_preserved_and_refit(garment_before, garment_signature(objects))
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(
        "LOWER_BUTT_RAISE_CLOTH_DONE|moved=%d|max_shift=%.5f|max_clearance=%.5f|raise=%.5f|blend=%s|glb=%s"
        % (moved, maximum_shift, maximum_clearance, LOINCLOTH_RAISE, OUTPUT_BLEND, OUTPUT_GLB)
    )


if __name__ == "__main__":
    main()
