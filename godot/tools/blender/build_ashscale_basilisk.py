import math
import os

import bpy
from mathutils import Vector


OUTPUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "enemies", "ashscale_basilisk_v1.glb")
)
BLEND_SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "blender", "enemies", "ashscale_basilisk_v1.blend")
)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.82, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.4
    return mat


SCALE_DARK = material("Ashscale charcoal armor", (0.17, 0.145, 0.12), 0.90)
SCALE_WARM = material("Ashscale iron-brown scales", (0.32, 0.205, 0.115), 0.86)
BELLY = material("Ashscale ochre belly", (0.46, 0.32, 0.17), 0.92)
BASALT = material("Ashscale fractured basalt", (0.245, 0.225, 0.205), 0.94)
CLAW = material("Ashscale horn claw", (0.095, 0.075, 0.055), 0.76)
EMBER = material("Ashscale ember organ", (0.90, 0.19, 0.025), 0.32, 0.0, (1.0, 0.075, 0.008))
EYE = material("Ashscale gold eye", (1.0, 0.47, 0.045), 0.24, 0.0, (1.0, 0.16, 0.01))


def parent_preserve(obj, parent):
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = matrix


def add_ico(name, location, scale, mat, parent, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for vertex in obj.data.vertices:
        ripple = 0.026 * math.sin(vertex.index * 2.73 + location[1] * 1.9)
        vertex.co += vertex.co.normalized() * ripple
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def cylinder_between(name, start, end, radius, mat, parent, vertices=10):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=delta.length,
        location=(start_v + end_v) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def add_cone_between(name, start, end, radius, mat, parent, vertices=8):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius,
        radius2=0.0,
        depth=delta.length,
        location=(start_v + end_v) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    obj.data.materials.append(mat)
    parent_preserve(obj, parent)
    return obj


def add_wedge(name, location, scale, mat, parent, taper=0.55):
    x, y, z = scale
    verts = [
        (-x, -y, -z), (x, -y, -z), (-x, y, -z), (x, y, -z),
        (-x * taper, -y, z), (x * taper, -y, z), (-x * 0.72, y, z), (x * 0.72, y, z),
    ]
    faces = [
        (0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
        (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3),
    ]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    parent_preserve(obj, parent)
    return obj


def build_leg(root, side, front):
    side_label = "L" if side < 0 else "R"
    leg_label = "F" if front else "R"
    hip_y = -0.82 if front else 0.82
    hip = Vector((side * 0.70, hip_y, 0.66))
    elbow = Vector((side * 1.08, hip_y + (-0.15 if front else 0.13), 0.37))
    wrist = Vector((side * 1.22, hip_y + (-0.38 if front else 0.42), 0.10))
    toe = Vector((side * 1.30, hip_y + (-0.63 if front else 0.66), 0.08))
    pivot = bpy.data.objects.new("LegPivot_%s%s" % (side_label, leg_label), None)
    pivot.location = hip
    bpy.context.collection.objects.link(pivot)
    pivot.parent = root
    cylinder_between("UpperLeg_%s%s" % (side_label, leg_label), hip, elbow, 0.15, SCALE_WARM, pivot, 9)
    cylinder_between("LowerLeg_%s%s" % (side_label, leg_label), elbow, wrist, 0.115, SCALE_DARK, pivot, 8)
    cylinder_between("Foot_%s%s" % (side_label, leg_label), wrist, toe, 0.09, CLAW, pivot, 8)
    for claw_index in (-1, 0, 1):
        claw_start = toe + Vector((claw_index * 0.075, 0, 0.015))
        claw_end = claw_start + Vector((side * 0.03, -0.24 if front else 0.24, -0.015))
        add_cone_between(
            "ToeClaw_%s%s_%d" % (side_label, leg_label, claw_index + 1),
            claw_start, claw_end, 0.035, CLAW, pivot, 7,
        )


def build_basilisk():
    root = bpy.data.objects.new("AshscaleBasiliskRig", None)
    bpy.context.collection.objects.link(root)

    add_ico("Ribcage", (0, 0.22, 0.78), (0.84, 1.28, 0.57), SCALE_WARM, root)
    add_ico("ShoulderArmor", (0, -0.68, 0.87), (0.91, 0.72, 0.59), SCALE_DARK, root)
    add_ico("OchreBelly", (0, 0.05, 0.47), (0.65, 1.13, 0.27), BELLY, root)
    cylinder_between("Neck", (0, -1.05, 0.78), (0, -1.55, 0.72), 0.50, SCALE_WARM, root, 11)
    add_wedge("CrownedHead", (0, -1.82, 0.80), (0.74, 0.58, 0.40), SCALE_DARK, root, 0.64)
    add_wedge("Snout", (0, -2.40, 0.67), (0.58, 0.42, 0.25), SCALE_WARM, root, 0.82)

    jaw = bpy.data.objects.new("JawPivot", None)
    jaw.location = (0, -2.26, 0.52)
    bpy.context.collection.objects.link(jaw)
    jaw.parent = root
    add_wedge("LowerJaw", (0, -2.43, 0.48), (0.48, 0.36, 0.10), BELLY, jaw, 0.86)
    for side in (-1, 1):
        side_label = "L" if side < 0 else "R"
        add_ico("EmberEye_%s" % side_label, (side * 0.36, -2.17, 0.94), (0.09, 0.055, 0.09), EYE, root)
        add_cone_between(
            "BrowHorn_%s" % side_label,
            (side * 0.48, -2.05, 1.03), (side * 0.69, -2.20, 1.22), 0.10, CLAW, root, 8,
        )
    add_ico("EmberThroat", (0, -1.78, 0.43), (0.34, 0.44, 0.22), EMBER, root)

    # Broken basalt plates form a readable crown from third-person height.
    plate_specs = [
        (-0.75, 0.31, 0.88), (-0.24, 0.38, 1.02), (0.34, 0.42, 1.10),
        (0.91, 0.34, 0.96), (1.34, 0.25, 0.72),
    ]
    for index, (y, radius, height) in enumerate(plate_specs):
        add_cone_between(
            "BasaltDorsalPlate_%d" % index,
            (0, y, 1.15), (0, y + 0.03, 1.15 + height), radius, BASALT, root, 7,
        )
        if index in (1, 3):
            add_ico("EmberScale_%d" % index, (0, y - 0.02, 1.35), (0.11, 0.16, 0.07), EMBER, root)

    for side in (-1, 1):
        build_leg(root, side, True)
        build_leg(root, side, False)

    tail_pivot_0 = bpy.data.objects.new("TailPivot_0", None)
    tail_pivot_0.location = (0, 1.38, 0.72)
    bpy.context.collection.objects.link(tail_pivot_0)
    tail_pivot_0.parent = root
    cylinder_between("TailBase", (0, 1.30, 0.70), (0, 2.20, 0.54), 0.42, SCALE_DARK, tail_pivot_0, 11)

    tail_pivot_1 = bpy.data.objects.new("TailPivot_1", None)
    tail_pivot_1.location = (0, 2.16, 0.54)
    bpy.context.collection.objects.link(tail_pivot_1)
    tail_pivot_1.parent = root
    cylinder_between("TailMiddle", (0, 2.10, 0.54), (0.18, 3.02, 0.38), 0.29, SCALE_WARM, tail_pivot_1, 10)
    add_cone_between("TailBlade", (0.18, 2.95, 0.38), (0.34, 3.82, 0.28), 0.28, BASALT, tail_pivot_1, 8)
    return root


clear_scene()
build_basilisk()

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
os.makedirs(os.path.dirname(BLEND_SOURCE), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_SOURCE)
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
)
print("ASHSCALE_BASILISK_EXPORT|%s" % OUTPUT)
