import math
import os

import bpy
from mathutils import Vector


OUTPUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "enemies", "rimecrawler_v1.glb")
)
BLEND_SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "blender", "enemies", "rimecrawler_v1.blend")
)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.86, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.2
    return mat


CHITIN = material("Rimecrawler slate chitin", (0.19, 0.25, 0.28), 0.88)
CHITIN_LIGHT = material("Rimecrawler weathered chitin", (0.34, 0.42, 0.44), 0.82)
ICE = material("Rimecrawler translucent ice plate", (0.24, 0.61, 0.72), 0.30, 0.06)
CLAW = material("Rimecrawler dark claw", (0.075, 0.09, 0.10), 0.72)
EYE = material("Rimecrawler amber eye", (0.90, 0.42, 0.055), 0.25, 0.0, (1.0, 0.18, 0.015))


def parent_preserve(obj, parent):
    # Blender defers matrix evaluation after scripted quaternion/Euler changes.
    # Force that evaluation before reparenting or glTF receives identity
    # rotations and the crawler's angled legs become disconnected posts.
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = matrix


def add_ico(name, location, scale, mat, parent):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for vertex in obj.data.vertices:
        vertex.co += vertex.co.normalized() * (0.035 * math.sin(vertex.index * 3.77))
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def cylinder_between(name, start, end, radius, mat, parent, vertices=9):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def add_cone(name, location, radius, depth, rotation, mat, parent, vertices=8):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=0.0, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def build_rimecrawler():
    root = bpy.data.objects.new("RimecrawlerRig", None)
    bpy.context.collection.objects.link(root)

    add_ico("ArmoredAbdomen", (0, 0.58, 0.78), (1.22, 1.36, 0.58), CHITIN, root)
    add_ico("Thorax", (0, -0.58, 0.82), (1.02, 0.95, 0.60), CHITIN_LIGHT, root)
    add_ico("HeadCarapace", (0, -1.48, 0.72), (0.76, 0.66, 0.46), CHITIN, root)
    add_ico("Underbody", (0, 0.05, 0.46), (0.77, 1.18, 0.30), CLAW, root)

    # Layered ice plates and dorsal spines make the creature identifiable from
    # above on snow, rather than reading as another wolf or recolored hound.
    for index, (y, scale) in enumerate([(0.82, (0.90, 0.54, 0.16)), (0.15, (0.80, 0.50, 0.18)), (-0.50, (0.68, 0.44, 0.17))]):
        add_ico("IceBackPlate_%d" % index, (0, y, 1.28), scale, ICE, root)
    for index, y in enumerate((0.92, 0.35, -0.20, -0.73)):
        add_cone("DorsalIceSpine_%d" % index, (0, y, 1.62), 0.18 + index * 0.015, 0.72, (0, 0, 0), ICE, root, 7)

    for side in (-1, 1):
        add_ico("AmberEye_%s" % ("L" if side < 0 else "R"), (side * 0.38, -1.96, 0.88), (0.11, 0.075, 0.11), EYE, root)
        add_cone(
            "Mandible_%s" % ("L" if side < 0 else "R"),
            (side * 0.34, -2.28, 0.52), 0.16, 0.92,
            (math.radians(72), side * math.radians(13), 0), CLAW, root, 8,
        )

    leg_y = (-0.90, 0.02, 0.92)
    for side in (-1, 1):
        side_label = "L" if side < 0 else "R"
        for leg_index, y in enumerate(leg_y):
            hip = Vector((side * 0.82, y, 0.75))
            knee = Vector((side * (1.42 + 0.10 * abs(leg_index - 1)), y - 0.06, 0.43))
            foot = Vector((side * (1.92 + 0.14 * abs(leg_index - 1)), y - 0.18 + (leg_index - 1) * 0.10, 0.10))
            pivot = bpy.data.objects.new("LegPivot_%s%d" % (side_label, leg_index), None)
            pivot.location = hip
            bpy.context.collection.objects.link(pivot)
            pivot.parent = root
            upper = cylinder_between("UpperLeg_%s%d" % (side_label, leg_index), hip, knee, 0.14, CHITIN_LIGHT, pivot, 8)
            lower = cylinder_between("LowerLeg_%s%d" % (side_label, leg_index), knee, foot, 0.105, CLAW, pivot, 8)
            add_cone(
                "FootClaw_%s%d" % (side_label, leg_index),
                (foot.x, foot.y - 0.19, foot.z), 0.09, 0.48,
                (math.radians(86), 0, 0), CLAW, pivot, 7,
            )

    # Short segmented tail used for readable attack anticipation.
    cylinder_between("TailBase", (0, 1.48, 0.72), (0, 2.02, 0.62), 0.24, CHITIN, root, 9)
    add_cone("TailSpike", (0, 2.36, 0.62), 0.23, 0.85, (math.radians(-90), 0, 0), ICE, root, 8)
    return root


clear_scene()
build_rimecrawler()

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
os.makedirs(os.path.dirname(BLEND_SOURCE), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_SOURCE)
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
)
print("RIMECRAWLER_EXPORT|%s" % OUTPUT)
