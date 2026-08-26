import bpy
import math
import os
from mathutils import Vector


ROOT = r"C:\Users\Jimmy\Desktop\Broken Knight\godot"
OUT = os.path.join(ROOT, "assets", "enemies", "frost_troll_v1.glb")


def material(name, color, roughness=0.9, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.location = location
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def smooth(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def sphere(name, location, scale, mat, parent, segments=24, rings=14):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    smooth(obj)
    obj.parent = parent
    return obj


def cone(name, location, radius1, radius2, depth, mat, parent, rotation=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    obj.parent = parent
    smooth(obj)
    return obj


def beam(name, start, end, radius, mat, parent, vertices=12, end_radius=None):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    radius2 = radius if end_radius is None else end_radius
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius,
        radius2=radius2,
        depth=direction.length,
        location=(start + end) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.data.materials.append(mat)
    obj.parent = parent
    smooth(obj)
    return obj


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    skin = material("Frost Troll blue grey hide", (0.20, 0.285, 0.31), 0.97)
    skin_dark = material("Frost Troll weathered hide", (0.105, 0.15, 0.17), 0.98)
    fur = material("Frost Troll winter fur", (0.46, 0.50, 0.48), 1.0)
    ice = material("Old blue glacial ice", (0.31, 0.62, 0.69), 0.46)
    stone = material("Moraine stone armor", (0.19, 0.205, 0.20), 0.99)
    wood = material("Frozen club timber", (0.14, 0.085, 0.045), 0.96)
    tooth = material("Troll tusk", (0.68, 0.62, 0.48), 0.88)
    eye = material("Troll amber eyes", (0.95, 0.34, 0.035), 0.31)

    root = empty("FrostTroll")
    visual = empty("FrostTrollVisual", parent=root)

    # Heavy, forward-hunched silhouette: short legs, barrel torso, huge arms.
    sphere("Pelvis", (0, 0.10, 1.12), (0.67, 0.48, 0.52), skin_dark, visual)
    sphere("HunchedTorso", (0, 0.03, 2.05), (0.91, 0.60, 1.02), skin, visual, 28, 16)
    sphere("ShoulderMass", (0, -0.02, 2.63), (1.22, 0.59, 0.55), skin_dark, visual, 28, 14)
    sphere("Belly", (0, -0.49, 1.86), (0.69, 0.24, 0.72), skin, visual, 22, 13)
    sphere("BackFur", (0, 0.47, 2.35), (0.88, 0.20, 0.84), fur, visual, 22, 12)

    neck = empty("NeckPivot", (0, -0.31, 2.63), visual)
    sphere("Head", (0, -0.18, 0.42), (0.56, 0.48, 0.51), skin, neck, 26, 15)
    sphere("Brow", (0, -0.57, 0.52), (0.52, 0.18, 0.18), skin_dark, neck, 22, 11)
    sphere("Muzzle", (0, -0.62, 0.20), (0.42, 0.31, 0.27), skin_dark, neck, 22, 12)
    sphere("Nose", (0, -0.88, 0.30), (0.25, 0.13, 0.14), stone, neck, 18, 9)
    for side in (-1, 1):
        sphere("EyeL" if side < 0 else "EyeR", (side * .23, -.70, .52), (.067, .045, .060), eye, neck, 14, 8)
        cone("TuskL" if side < 0 else "TuskR", (side * .27, -.84, .04), .09, .012, .52, tooth, neck, (math.pi * .56, 0, side * .18), 12)
        cone("EarL" if side < 0 else "EarR", (side * .57, -.17, .40), .16, .025, .43, skin_dark, neck, (0, side * .48, side * .30), 12)

    # Uneven moraine slabs and ice shards break up the torso without recoloring
    # an existing enemy. They make the model readable at gameplay distance.
    sphere("ChestArmor", (0, -.57, 2.40), (.62, .13, .48), stone, visual, 16, 10)
    for index, (x, z, rot) in enumerate(((-.52, 2.62, -.22), (.46, 2.71, .26), (-.26, 2.96, -.08))):
        shard = cone("ShoulderIce%02d" % index, (x, -.10, z), .19, .018, .73, ice, visual, (rot, .18 * x, rot), 9)
        shard.scale.y = .70

    for side in (-1, 1):
        # All limb geometry is local to named pivots for cheap Godot procedural animation.
        arm = empty("ArmPivotL" if side < 0 else "ArmPivotR", (side * .83, -.02, 2.62), visual)
        beam("UpperArm", (0, 0, 0), (side * .29, -.05, -.82), .27, skin, arm, 14, .23)
        beam("Forearm", (side * .29, -.05, -.82), (side * .36, -.34, -1.67), .25, skin_dark, arm, 14, .20)
        sphere("Fist", (side * .36, -.40, -1.83), (.32, .29, .28), skin_dark, arm, 20, 12)
        for claw in range(3):
            cone("Claw%02d" % claw, (side * (.22 + claw * .08), -.66, -1.91), .045, .006, .27, tooth, arm, (math.pi * .52, 0, 0), 9)

        leg = empty("LegPivotL" if side < 0 else "LegPivotR", (side * .40, .07, 1.14), visual)
        beam("Thigh", (0, 0, 0), (side * .06, -.02, -.56), .28, skin_dark, leg, 14, .24)
        beam("Shin", (side * .06, -.02, -.56), (side * .04, -.12, -1.02), .23, skin, leg, 14, .19)
        sphere("Foot", (side * .04, -.31, -1.12), (.35, .51, .19), skin_dark, leg, 20, 10)
        for toe in range(3):
            cone("Toe%02d" % toe, (side * (.00 + (toe - 1) * .10), -.73, -1.13), .045, .006, .25, tooth, leg, (math.pi * .5, 0, 0), 9)

    club_pivot = empty("ClubPivot", (.95, -.37, .82), visual)
    beam("ClubHandle", (0, 0, 0), (.08, .15, 2.25), .115, wood, club_pivot, 12, .09)
    beam("ClubHead", (-.12, .12, 1.98), (.25, .18, 2.72), .30, stone, club_pivot, 10, .23)
    for index, (x, y, z) in enumerate(((-.19, .06, 2.20), (.31, .13, 2.37), (-.06, .04, 2.62))):
        cone("ClubIceSpike%02d" % index, (x, y, z), .10, .012, .47, ice, club_pivot, (0, .75 if x > 0 else -.75, 0), 9)

    # Ragged fur skirt is made from overlapping tapered panels rather than a
    # single skirt cone, leaving the legs and grounded stance readable.
    for index in range(9):
        angle = -1.12 + index * .28
        x = math.sin(angle) * .55
        y = -.06 + math.cos(angle) * .42
        cone("FurPanel%02d" % index, (x, y, 1.12), .18, .055, .73, fur, visual, (0, .18 * math.sin(angle), angle * .12), 9)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print("Exported", OUT)


build()
