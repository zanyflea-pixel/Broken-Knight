"""Build the custom Riverwatch starter stable and a rigged riding horse."""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
STABLE_BLEND = os.path.join(ROOT, "blender", "world", "architecture", "riverwatch_stable.blend")
HORSE_BLEND = os.path.join(ROOT, "blender", "world", "animals", "riverwatch_horse.blend")
STABLE_GLB = os.path.join(ROOT, "godot", "assets", "architecture", "riverwatch_stable.glb")
HORSE_GLB = os.path.join(ROOT, "godot", "assets", "animals", "riverwatch_horse.glb")


def clear_scene():
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name, color, roughness=0.7, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def bevel(obj, width=0.035, segments=3):
    modifier = obj.modifiers.new("CraftedEdge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def cube(name, location, size, mat, rotation=(0.0, 0.0, 0.0), edge=0.035):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if edge > 0.0:
        bevel(obj, edge, 3)
    return obj


def sphere(name, location, scale, mat, segments=28, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def cylinder_between(name, start, end, radius, mat, vertices=20, radius2=None):
    start_v, end_v = Vector(start), Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    if radius2 is None or abs(radius2 - radius) < 0.0001:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=direction.length, location=midpoint)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius2, depth=direction.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bevel(obj, min(0.018, radius * 0.14), 2)
    return obj


def torus(name, location, major_radius, minor_radius, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=32,
        minor_segments=8,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def export_static(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_lights=False,
        export_cameras=False,
        export_apply=True,
    )


def build_stable():
    clear_scene()
    timber = material("Riverwatch Dark Oak", (0.16, 0.070, 0.025, 1), 0.78)
    timber_light = material("Riverwatch Hewn Oak", (0.29, 0.135, 0.045, 1), 0.76)
    plaster = material("Riverwatch Limewash", (0.46, 0.39, 0.29, 1), 0.92)
    roof = material("Riverwatch Clay Shingle", (0.22, 0.055, 0.025, 1), 0.86)
    stone = material("Riverwatch Stable Stone", (0.27, 0.27, 0.25, 1), 0.96)
    iron = material("Riverwatch Wrought Iron", (0.035, 0.042, 0.050, 1), 0.42, 0.72)
    hay = material("Riverwatch Hay", (0.52, 0.34, 0.075, 1), 0.96)
    leather = material("Riverwatch Tack Leather", (0.11, 0.030, 0.012, 1), 0.82)

    # Stone sill and packed aisle.
    cube("StableStoneSill", (0, 0.25, 0.18), (18.8, 9.6, 0.36), stone, edge=0.055)
    cube("StablePackedAisle", (0, -2.75, 0.40), (17.6, 3.0, 0.16), plaster, edge=0.025)

    # Heavy post-and-beam frame with three genuine stalls.
    for x in (-8.7, -2.9, 2.9, 8.7):
        for y in (-4.1, 4.1):
            cube("StablePost", (x, y, 2.65), (0.48, 0.48, 5.3), timber, edge=0.045)
    for y in (-4.1, 4.1):
        cube("StableLongWallPlate", (0, y, 5.0), (18.2, 0.48, 0.52), timber, edge=0.045)
        cube("StableLowerWallRail", (0, y, 1.25), (18.2, 0.28, 0.34), timber_light, edge=0.035)
    for x in (-8.7, 8.7):
        cube("StableEndTie", (x, 0, 4.8), (0.48, 8.5, 0.48), timber, edge=0.045)
    cube("StableRidgeBeam", (0, 0, 6.35), (18.8, 0.42, 0.48), timber, edge=0.04)

    # Back infill boards and end-wall limewash panels.
    for x in (-7.25, -4.35, -1.45, 1.45, 4.35, 7.25):
        cube("StableBackBoard", (x, 4.24, 2.78), (2.62, 0.18, 3.0), plaster, edge=0.025)
        cube("StableBackStud", (x + 1.36, 4.05, 2.9), (0.20, 0.26, 3.7), timber_light, edge=0.025)
    for x in (-8.82, 8.82):
        cube("StableSideWall", (x, 1.2, 2.7), (0.22, 5.5, 3.2), plaster, edge=0.025)
        for y in (-1.0, 1.4, 3.5):
            cube("StableSideBrace", (x + (-0.02 if x < 0 else 0.02), y, 2.9), (0.30, 0.24, 3.7), timber_light, rotation=(0.35 if x < 0 else -0.35, 0, 0), edge=0.025)

    # Pitched shingle roof with broad eaves and visible fascia.
    roof_angle = math.radians(27.0)
    cube("StableRoofFront", (0, -2.55, 5.70), (19.6, 6.25, 0.30), roof, rotation=(roof_angle, 0, 0), edge=0.055)
    cube("StableRoofRear", (0, 2.55, 5.70), (19.6, 6.25, 0.30), roof, rotation=(-roof_angle, 0, 0), edge=0.055)
    for y in (-5.25, 5.25):
        cube("StableRoofFascia", (0, y, 4.45), (19.8, 0.22, 0.52), timber_light, edge=0.035)

    # Stall partitions, half-height gates, feed troughs and straw bedding.
    for divider_x in (-2.9, 2.9):
        for y in (-1.5, 0.1, 1.7, 3.3):
            cube("StablePartitionRail", (divider_x, y, 1.45), (0.26, 1.72, 0.24), timber_light, edge=0.025)
        for y in (-2.35, 0.8, 3.75):
            cube("StablePartitionPost", (divider_x, y, 1.55), (0.34, 0.34, 3.1), timber, edge=0.035)
    for stall_x in (-5.8, 0.0, 5.8):
        for z in (0.82, 1.52):
            cube("StableGateRail", (stall_x, -2.25, z), (4.9, 0.22, 0.24), timber_light, edge=0.025)
        for x_offset in (-2.35, 2.35):
            cube("StableGatePost", (stall_x + x_offset, -2.25, 1.25), (0.30, 0.30, 2.5), timber, edge=0.03)
        cube("StableFeedTrough", (stall_x, 3.55, 0.82), (3.4, 0.90, 0.72), timber, edge=0.06)
        cube("StableHayBed", (stall_x, 1.25, 0.50), (4.6, 3.2, 0.22), hay, edge=0.05)
        for bale_index, y in enumerate((2.15, 2.95)):
            cube("StableHayBale", (stall_x + (-1.05 if bale_index == 0 else 1.05), y, 0.86), (1.65, 0.86, 0.78), hay, rotation=(0, 0, 0.08 * (-1 if bale_index == 0 else 1)), edge=0.08)

    # Hitching rail and tack display make the stable readable from the road.
    for x in (-6.5, 0.0, 6.5):
        cube("StableHitchPost", (x, -6.15, 1.15), (0.34, 0.34, 2.3), timber, edge=0.035)
    cube("StableHitchRail", (0, -6.15, 1.55), (13.4, 0.30, 0.32), timber_light, edge=0.035)
    cube("StableSignBoard", (0, -4.46, 4.0), (5.2, 0.24, 1.25), timber_light, edge=0.10)
    torus("StableHorseshoeSign", (0, -4.61, 4.0), 0.37, 0.055, iron, rotation=(math.pi / 2, 0, 0))
    for side in (-1, 1):
        torus("StableHangingBridle", (side * 6.8, -4.55, 2.55), 0.46, 0.035, leather, rotation=(math.pi / 2, 0, 0))

    os.makedirs(os.path.dirname(STABLE_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=STABLE_BLEND)
    export_static(STABLE_GLB)
    print("RIVERWATCH_STABLE_BUILT|blend=%s|glb=%s" % (STABLE_BLEND, STABLE_GLB))


def build_armature():
    bpy.ops.object.armature_add(
        enter_editmode=True,
        location=(0, 0, 0)
    )

    arm = bpy.context.object

    arm.name = "RiverwatchHorseRig"
    arm.data.name = "RiverwatchHorseRigData"

    default = arm.data.edit_bones.get("Bone")

    if default:
        arm.data.edit_bones.remove(default)

    definitions = {
        "root": (
            (0.0, 0.0, 0.02),
            (0.0, 0.0, 0.42),
            None
        ),

        "body": (
            (0.0, 0.0, 0.42),
            (0.0, 0.0, 1.44),
            "root"
        ),

        "neck": (
            (0.0, -0.50, 1.52),
            (0.0, -0.98, 1.80),
            "body"
        ),

        "head": (
            (0.0, -0.98, 1.80),
            (0.0, -1.56, 1.68),
            "neck"
        ),

        "tail.1": (
            (0.0, 0.72, 1.48),
            (0.0, 1.10, 1.18),
            "body"
        ),

        "tail.2": (
            (0.0, 1.10, 1.18),
            (0.0, 1.54, 0.62),
            "tail.1"
        ),
    }

    front_data = (
        ("front.L", -0.28),
        ("front.R", 0.28),
    )

    for prefix, x in front_data:

        definitions[prefix + ".upper"] = (
            (x, -0.42, 1.12),
            (x, -0.47, 0.61),
            "body"
        )

        definitions[prefix + ".lower"] = (
            (x, -0.47, 0.61),
            (x, -0.53, 0.19),
            prefix + ".upper"
        )

        definitions[prefix + ".hoof"] = (
            (x, -0.53, 0.19),
            (x, -0.64, 0.07),
            prefix + ".lower"
        )

    hind_data = (
        ("hind.L", -0.30),
        ("hind.R", 0.30),
    )

    for prefix, x in hind_data:

        definitions[prefix + ".upper"] = (
            (x, 0.52, 1.13),
            (x, 0.59, 0.58),
            "body"
        )

        definitions[prefix + ".lower"] = (
            (x, 0.59, 0.58),
            (x, 0.50, 0.19),
            prefix + ".upper"
        )

        definitions[prefix + ".hoof"] = (
            (x, 0.50, 0.19),
            (x, 0.40, 0.07),
            prefix + ".lower"
        )

    for name, definition in definitions.items():

        head_position, tail_position, parent_name = definition

        bone = arm.data.edit_bones.new(
            name
        )

        bone.head = head_position
        bone.tail = tail_position

        if parent_name:
            bone.parent = arm.data.edit_bones[
                parent_name
            ]

    bpy.ops.object.mode_set(
        mode="OBJECT"
    )

    arm.show_in_front = True

    arm[
        "broken_knight_horse_rig"
    ] = "reference_v10"

    return arm
def rigid_skin(obj, arm, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    obj.parent = arm
    modifier = obj.modifiers.new("HorseRig", "ARMATURE")
    modifier.object = arm
    return obj


def horse_sphere(name, location, scale, mat, arm, bone, segments=28, rings=16):
    return rigid_skin(sphere(name, location, scale, mat, segments, rings), arm, bone)


def horse_cube(name, location, size, mat, arm, bone, rotation=(0, 0, 0), edge=0.025):
    return rigid_skin(cube(name, location, size, mat, rotation, edge), arm, bone)


def horse_cylinder(name, start, end, radius, mat, arm, bone, radius2=None):
    return rigid_skin(cylinder_between(name, start, end, radius, mat, 20, radius2), arm, bone)


def build_horse_model(arm):
    # ========================================================
    # BROKEN KNIGHT
    # RIVERWATCH HORSE V10
    #
    # TARGET:
    #
    # The generated reference-sheet horse:
    #
    # - strong but believable riding / pack horse
    # - broad deep chest
    # - rounded muscular hindquarters
    # - curved substantial neck
    # - smaller tapered horse head
    # - clearly defined knees and hocks
    # - dimensional lower legs
    # - natural hoof proportions
    # - full dark mane
    # - full flowing tail
    # - fitted blue blanket
    # - clean brown medieval saddle
    #
    # NO VOXEL REMESH.
    # NO BODY MADE FROM SPHERES.
    #
    # Body, neck and head now use the same correct
    # perpendicular 3D sweep concept that fixed the legs.
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V10 Warm Bay",
        (0.34, 0.105, 0.030, 1),
        0.55
    )

    coat_dark = material(
        "Riverwatch V10 Dark Points",
        (0.060, 0.020, 0.010, 1),
        0.66
    )

    muzzle_mat = material(
        "Riverwatch V10 Muzzle",
        (0.145, 0.100, 0.085, 1),
        0.73
    )

    mane_mat = material(
        "Riverwatch V10 Mane Tail",
        (0.014, 0.010, 0.008, 1),
        0.66
    )

    hoof_mat = material(
        "Riverwatch V10 Hoof",
        (0.055, 0.045, 0.038, 1),
        0.76
    )

    ivory = material(
        "Riverwatch V10 Blaze",
        (0.83, 0.79, 0.70, 1),
        0.78
    )

    eye_mat = material(
        "Riverwatch V10 Eye",
        (0.055, 0.021, 0.006, 1),
        0.16
    )

    pupil_mat = material(
        "Riverwatch V10 Pupil",
        (0.002, 0.002, 0.002, 1),
        0.10
    )

    glint_mat = material(
        "Riverwatch V10 Eye Glint",
        (0.96, 0.94, 0.88, 1),
        0.10
    )

    leather = material(
        "Riverwatch V10 Saddle Leather",
        (0.105, 0.035, 0.014, 1),
        0.62
    )

    leather_mid = material(
        "Riverwatch V10 Saddle Highlight",
        (0.215, 0.080, 0.027, 1),
        0.58
    )

    leather_dark = material(
        "Riverwatch V10 Saddle Shadow",
        (0.052, 0.015, 0.007, 1),
        0.67
    )

    blanket = material(
        "Riverwatch V10 Blue Blanket",
        (0.030, 0.095, 0.300, 1),
        0.74
    )

    blanket_trim = material(
        "Riverwatch V10 Blanket Trim",
        (0.62, 0.40, 0.10, 1),
        0.55,
        0.18
    )

    brass = material(
        "Riverwatch V10 Brass",
        (0.56, 0.34, 0.07, 1),
        0.30,
        0.75
    )

    iron = material(
        "Riverwatch V10 Iron",
        (0.060, 0.064, 0.070, 1),
        0.34,
        0.65
    )

    # ========================================================
    # BASIC HELPERS
    # ========================================================

    def smooth(obj):

        for polygon in obj.data.polygons:
            polygon.use_smooth = True

        return obj

    def bind_armature(obj):

        obj.parent = arm

        modifier = obj.modifiers.new(
            "HorseRig",
            "ARMATURE"
        )

        modifier.object = arm

        return obj

    def rigid_bind(
        obj,
        bone_name
    ):
        group = obj.vertex_groups.new(
            name=bone_name
        )

        group.add(
            range(
                len(obj.data.vertices)
            ),
            1.0,
            "REPLACE"
        )

        bind_armature(
            obj
        )

        return obj

    def subdivide(
        obj,
        levels=1
    ):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(
            True
        )

        modifier = obj.modifiers.new(
            "HorseSubdivision",
            "SUBSURF"
        )

        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = levels
        modifier.render_levels = levels

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    def bevel_mesh(
        obj,
        amount=0.012,
        segments=3
    ):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(
            True
        )

        modifier = obj.modifiers.new(
            "HorseBevel",
            "BEVEL"
        )

        modifier.width = amount
        modifier.segments = segments

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    # ========================================================
    # TRUE 3D PERPENDICULAR FRAME
    # ========================================================

    def sweep_frame(
        centers,
        index
    ):
        if index == 0:

            tangent = (
                centers[1]
                - centers[0]
            )

        elif index == len(centers) - 1:

            tangent = (
                centers[-1]
                - centers[-2]
            )

        else:

            tangent = (
                centers[index + 1]
                - centers[index - 1]
            )

        if tangent.length < 0.00001:

            tangent = Vector(
                (0.0, 1.0, 0.0)
            )

        tangent.normalize()

        lateral = Vector(
            (1.0, 0.0, 0.0)
        )

        lateral = (
            lateral
            - tangent
            * lateral.dot(tangent)
        )

        if lateral.length < 0.00001:

            lateral = Vector(
                (0.0, 0.0, 1.0)
            )

            lateral = (
                lateral
                - tangent
                * lateral.dot(tangent)
            )

        lateral.normalize()

        depth = tangent.cross(
            lateral
        )

        if depth.length < 0.00001:

            depth = Vector(
                (0.0, 0.0, 1.0)
            )

        depth.normalize()

        # Keep depth oriented generally upward.
        if depth.z < 0.0:
            depth.negate()

        return (
            tangent,
            lateral,
            depth
        )

    # ========================================================
    # REFERENCE BODY
    #
    # Sections:
    #
    # (
    #   x_center,
    #   y_center,
    #   z_center,
    #   half_width,
    #   top_radius,
    #   bottom_radius
    # )
    #
    # Entire body -> neck -> head is one continuous mesh.
    # Rings tilt with the horse's centerline.
    # ========================================================

    def build_reference_core():

        sections = [
            # Tail root.
            (
                0.0,
                1.055,
                1.475,
                0.080,
                0.085,
                0.085
            ),

            # Rear croup.
            (
                0.0,
                0.985,
                1.470,
                0.250,
                0.245,
                0.245
            ),

            (
                0.0,
                0.860,
                1.460,
                0.410,
                0.345,
                0.355
            ),

            # Full hindquarters.
            (
                0.0,
                0.690,
                1.440,
                0.505,
                0.390,
                0.405
            ),

            (
                0.0,
                0.500,
                1.420,
                0.525,
                0.380,
                0.410
            ),

            # Barrel.
            (
                0.0,
                0.285,
                1.400,
                0.515,
                0.345,
                0.405
            ),

            (
                0.0,
                0.060,
                1.395,
                0.505,
                0.330,
                0.410
            ),

            (
                0.0,
                -0.170,
                1.405,
                0.495,
                0.340,
                0.415
            ),

            # Chest.
            (
                0.0,
                -0.360,
                1.440,
                0.475,
                0.375,
                0.420
            ),

            (
                0.0,
                -0.500,
                1.505,
                0.420,
                0.360,
                0.355
            ),

            # Withers.
            (
                0.0,
                -0.595,
                1.585,
                0.355,
                0.310,
                0.290
            ),

            # Lower neck.
            (
                0.0,
                -0.690,
                1.650,
                0.315,
                0.285,
                0.255
            ),

            (
                0.0,
                -0.795,
                1.715,
                0.285,
                0.260,
                0.225
            ),

            # Upper curved neck.
            (
                0.0,
                -0.900,
                1.770,
                0.255,
                0.235,
                0.205
            ),

            (
                0.0,
                -1.005,
                1.810,
                0.225,
                0.205,
                0.185
            ),

            # Poll.
            (
                0.0,
                -1.100,
                1.825,
                0.205,
                0.185,
                0.175
            ),

            # Skull.
            (
                0.0,
                -1.195,
                1.805,
                0.205,
                0.175,
                0.170
            ),

            (
                0.0,
                -1.300,
                1.775,
                0.195,
                0.165,
                0.175
            ),

            # Cheek.
            (
                0.0,
                -1.405,
                1.735,
                0.185,
                0.150,
                0.165
            ),

            # Nasal bridge.
            (
                0.0,
                -1.510,
                1.700,
                0.165,
                0.125,
                0.135
            ),

            # Muzzle.
            (
                0.0,
                -1.615,
                1.680,
                0.145,
                0.105,
                0.115
            ),

            (
                0.0,
                -1.710,
                1.675,
                0.125,
                0.090,
                0.098
            ),

            # Nose tip.
            (
                0.0,
                -1.775,
                1.675,
                0.065,
                0.052,
                0.055
            ),
        ]

        centers = [
            Vector(
                (
                    section[0],
                    section[1],
                    section[2]
                )
            )
            for section in sections
        ]

        rings = 56

        verts = []
        faces = []

        for section_index, section in enumerate(
            sections
        ):

            center = centers[
                section_index
            ]

            tangent, lateral, depth = sweep_frame(
                centers,
                section_index
            )

            width = section[3]
            top_radius = section[4]
            bottom_radius = section[5]

            for ring_index in range(
                rings
            ):

                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                cosine = math.cos(
                    angle
                )

                sine = math.sin(
                    angle
                )

                if sine >= 0.0:

                    depth_amount = (
                        sine
                        * top_radius
                    )

                else:

                    depth_amount = (
                        sine
                        * bottom_radius
                    )

                # Slightly broaden sides without turning body
                # into a sphere/blob.
                lateral_amount = (
                    cosine
                    * width
                )

                point = (
                    center
                    + lateral
                    * lateral_amount
                    + depth
                    * depth_amount
                )

                # --------------------------------------------
                # REFERENCE-SHEET SILHOUETTE ADJUSTMENTS
                # --------------------------------------------

                y = point.y

                # Strong rounded croup.
                croup = math.exp(
                    -((y - 0.66) / 0.29) ** 2
                )

                if abs(cosine) > 0.25:

                    point.x *= (
                        1.0
                        + 0.045
                        * croup
                    )

                # Shoulder mass.
                shoulder = math.exp(
                    -((y + 0.35) / 0.20) ** 2
                )

                if abs(cosine) > 0.30:

                    point.x *= (
                        1.0
                        + 0.040
                        * shoulder
                    )

                # Belly tuck behind ribs.
                flank = math.exp(
                    -((y - 0.30) / 0.18) ** 2
                )

                if sine < -0.20:

                    point.z += (
                        0.055
                        * flank
                        * (-sine)
                    )

                verts.append(
                    tuple(point)
                )

        for section_index in range(
            len(sections) - 1
        ):

            first = (
                section_index
                * rings
            )

            second = (
                section_index + 1
            ) * rings

            for ring_index in range(
                rings
            ):

                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring
                    )
                )

        rear_center = len(
            verts
        )

        verts.append(
            tuple(
                centers[0]
            )
        )

        nose_center = len(
            verts
        )

        verts.append(
            tuple(
                centers[-1]
            )
        )

        for ring_index in range(
            rings
        ):

            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    rear_center,
                    next_ring,
                    ring_index
                )
            )

            last_start = (
                len(sections) - 1
            ) * rings

            faces.append(
                (
                    nose_center,
                    last_start + ring_index,
                    last_start + next_ring
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV10ReferenceCoreMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV10ReferenceCore",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            coat
        )

        subdivide(
            obj,
            1
        )

        smooth(
            obj
        )

        body_group = obj.vertex_groups.new(
            name="body"
        )

        neck_group = obj.vertex_groups.new(
            name="neck"
        )

        head_group = obj.vertex_groups.new(
            name="head"
        )

        for vertex in obj.data.vertices:

            y = vertex.co.y

            if y >= -0.60:

                body_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -0.82:

                blend = (
                    (-0.60 - y)
                    / 0.22
                )

                body_group.add(
                    [vertex.index],
                    1.0 - blend,
                    "REPLACE"
                )

                neck_group.add(
                    [vertex.index],
                    blend,
                    "REPLACE"
                )

            elif y >= -1.04:

                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -1.19:

                blend = (
                    (-1.04 - y)
                    / 0.15
                )

                neck_group.add(
                    [vertex.index],
                    1.0 - blend,
                    "REPLACE"
                )

                head_group.add(
                    [vertex.index],
                    blend,
                    "REPLACE"
                )

            else:

                head_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

        bind_armature(
            obj
        )

        return obj

    build_reference_core()

    # ========================================================
    # TRUE 3D LIMB BUILDER
    # ========================================================

    def build_limb(
        name,
        sections,
        weights,
        dark_below=0.40,
        rings=30
    ):
        centers = [
            Vector(
                (
                    section[0],
                    section[1],
                    section[2]
                )
            )
            for section in sections
        ]

        verts = []
        faces = []

        for section_index, section in enumerate(
            sections
        ):

            center = centers[
                section_index
            ]

            tangent, lateral, depth = sweep_frame(
                centers,
                section_index
            )

            lateral_radius = section[3]
            depth_radius = section[4]

            for ring_index in range(
                rings
            ):

                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                point = (
                    center
                    + lateral
                    * (
                        math.cos(angle)
                        * lateral_radius
                    )
                    + depth
                    * (
                        math.sin(angle)
                        * depth_radius
                    )
                )

                verts.append(
                    tuple(point)
                )

        for section_index in range(
            len(sections) - 1
        ):

            first = (
                section_index
                * rings
            )

            second = (
                section_index + 1
            ) * rings

            for ring_index in range(
                rings
            ):

                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring
                    )
                )

        start_center = len(
            verts
        )

        verts.append(
            tuple(
                centers[0]
            )
        )

        end_center = len(
            verts
        )

        verts.append(
            tuple(
                centers[-1]
            )
        )

        for ring_index in range(
            rings
        ):

            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    start_center,
                    ring_index,
                    next_ring
                )
            )

            last_start = (
                len(sections) - 1
            ) * rings

            faces.append(
                (
                    end_center,
                    last_start + next_ring,
                    last_start + ring_index
                )
            )

        mesh = bpy.data.meshes.new(
            name + "Mesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            name,
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            coat
        )

        obj.data.materials.append(
            coat_dark
        )

        # Dark lower legs like reference horse.
        for polygon in obj.data.polygons:

            average_z = sum(
                obj.data.vertices[
                    index
                ].co.z
                for index in polygon.vertices
            ) / len(
                polygon.vertices
            )

            if average_z < dark_below:

                polygon.material_index = 1

        groups = {}

        for weight_map in weights:

            for group_name in weight_map:

                if group_name not in groups:

                    groups[group_name] = (
                        obj.vertex_groups.new(
                            name=group_name
                        )
                    )

        for section_index, weight_map in enumerate(
            weights
        ):

            indices = list(
                range(
                    section_index * rings,
                    section_index * rings + rings
                )
            )

            for group_name, weight in weight_map.items():

                groups[
                    group_name
                ].add(
                    indices,
                    weight,
                    "REPLACE"
                )

        for group_name, weight in weights[0].items():

            groups[
                group_name
            ].add(
                [start_center],
                weight,
                "REPLACE"
            )

        for group_name, weight in weights[-1].items():

            groups[
                group_name
            ].add(
                [end_center],
                weight,
                "REPLACE"
            )

        subdivide(
            obj,
            1
        )

        smooth(
            obj
        )

        bind_armature(
            obj
        )

        return obj

    # ========================================================
    # FRONT LEGS
    #
    # Reference target:
    #
    # muscular forearm
    # obvious knee
    # slim but not twig cannon
    # visible fetlock
    # sloped pastern
    # ========================================================

    def front_sections(side):

        x = (
            0.285
            * side
        )

        return [
            # Shoulder merge.
            (
                x,
                -0.400,
                1.170,
                0.155,
                0.142
            ),

            # Upper limb.
            (
                x,
                -0.420,
                1.035,
                0.145,
                0.132
            ),

            # Forearm.
            (
                x,
                -0.438,
                0.900,
                0.128,
                0.116
            ),

            (
                x,
                -0.452,
                0.760,
                0.112,
                0.102
            ),

            # Knee.
            (
                x,
                -0.466,
                0.640,
                0.118,
                0.108
            ),

            (
                x,
                -0.474,
                0.580,
                0.112,
                0.102
            ),

            # Cannon.
            (
                x,
                -0.486,
                0.480,
                0.081,
                0.073
            ),

            (
                x,
                -0.498,
                0.365,
                0.074,
                0.067
            ),

            (
                x,
                -0.510,
                0.270,
                0.073,
                0.066
            ),

            # Fetlock.
            (
                x,
                -0.525,
                0.190,
                0.094,
                0.085
            ),

            # Pastern.
            (
                x,
                -0.550,
                0.125,
                0.080,
                0.073
            ),
        ]

    def front_weights(prefix):

        return [
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},

            {
                prefix + ".upper": 0.45,
                prefix + ".lower": 0.55
            },

            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},

            {
                prefix + ".lower": 0.50,
                prefix + ".hoof": 0.50
            },

            {prefix + ".hoof": 1.0},
        ]

    build_limb(
        "RiverwatchV10FrontLeftLeg",
        front_sections(-1),
        front_weights(
            "front.L"
        )
    )

    build_limb(
        "RiverwatchV10FrontRightLeg",
        front_sections(1),
        front_weights(
            "front.R"
        )
    )

    # ========================================================
    # HIND LEGS
    #
    # Reference target:
    #
    # big thigh
    # forward stifle
    # gaskin
    # backward hock
    # straight lower cannon
    # ========================================================

    def hind_sections(side):

        x = (
            0.305
            * side
        )

        return [
            # Hip.
            (
                x,
                0.540,
                1.170,
                0.175,
                0.160
            ),

            # Thigh.
            (
                x,
                0.500,
                1.035,
                0.168,
                0.151
            ),

            # Stifle forward.
            (
                x,
                0.390,
                0.890,
                0.148,
                0.134
            ),

            # Gaskin.
            (
                x,
                0.415,
                0.755,
                0.126,
                0.115
            ),

            # Upper hock moves back.
            (
                x,
                0.530,
                0.650,
                0.116,
                0.106
            ),

            # Hock.
            (
                x,
                0.610,
                0.575,
                0.126,
                0.114
            ),

            # Cannon.
            (
                x,
                0.585,
                0.470,
                0.081,
                0.073
            ),

            (
                x,
                0.555,
                0.360,
                0.074,
                0.067
            ),

            (
                x,
                0.525,
                0.265,
                0.073,
                0.066
            ),

            # Fetlock.
            (
                x,
                0.495,
                0.188,
                0.095,
                0.085
            ),

            # Pastern.
            (
                x,
                0.465,
                0.123,
                0.081,
                0.073
            ),
        ]

    def hind_weights(prefix):

        return [
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},
            {prefix + ".upper": 1.0},

            {
                prefix + ".upper": 0.50,
                prefix + ".lower": 0.50
            },

            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},
            {prefix + ".lower": 1.0},

            {
                prefix + ".lower": 0.50,
                prefix + ".hoof": 0.50
            },

            {prefix + ".hoof": 1.0},
        ]

    build_limb(
        "RiverwatchV10HindLeftLeg",
        hind_sections(-1),
        hind_weights(
            "hind.L"
        )
    )

    build_limb(
        "RiverwatchV10HindRightLeg",
        hind_sections(1),
        hind_weights(
            "hind.R"
        )
    )

    # ========================================================
    # HORSE-SHAPED HOOF
    #
    # Horizontal swept profile.
    # Rounded heel.
    # Broad toe.
    # Natural forward extension.
    # ========================================================

    def build_hoof(
        name,
        x,
        y,
        bone,
        width=0.118,
        length=0.235
    ):

        profiles = [
            # Pastern connection.
            (
                y + 0.060,
                0.122,
                width * 0.64,
                0.044
            ),

            # Heel.
            (
                y + 0.025,
                0.093,
                width * 0.84,
                0.057
            ),

            # Main hoof.
            (
                y - length * 0.22,
                0.074,
                width,
                0.061
            ),

            # Broad toe.
            (
                y - length * 0.52,
                0.065,
                width * 1.08,
                0.056
            ),

            # Toe tip.
            (
                y - length * 0.68,
                0.060,
                width * 0.90,
                0.046
            ),
        ]

        rings = 24

        verts = []
        faces = []

        for py, center_z, radius_x, radius_z in profiles:

            for ring_index in range(
                rings
            ):

                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                verts.append(
                    (
                        x
                        + math.cos(angle)
                        * radius_x,

                        py,

                        center_z
                        + math.sin(angle)
                        * radius_z
                    )
                )

        for profile_index in range(
            len(profiles) - 1
        ):

            first = (
                profile_index
                * rings
            )

            second = (
                profile_index + 1
            ) * rings

            for ring_index in range(
                rings
            ):

                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring
                    )
                )

        start_center = len(
            verts
        )

        verts.append(
            (
                x,
                profiles[0][0],
                profiles[0][1]
            )
        )

        end_center = len(
            verts
        )

        verts.append(
            (
                x,
                profiles[-1][0],
                profiles[-1][1]
            )
        )

        for ring_index in range(
            rings
        ):

            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    start_center,
                    next_ring,
                    ring_index
                )
            )

            last_start = (
                len(profiles) - 1
            ) * rings

            faces.append(
                (
                    end_center,
                    last_start + ring_index,
                    last_start + next_ring
                )
            )

        mesh = bpy.data.meshes.new(
            name + "Mesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            name,
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            hoof_mat
        )

        subdivide(
            obj,
            1
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            bone
        )

        return obj

    build_hoof(
        "RiverwatchV10FrontLeftHoof",
        -0.285,
        -0.555,
        "front.L.hoof"
    )

    build_hoof(
        "RiverwatchV10FrontRightHoof",
        0.285,
        -0.555,
        "front.R.hoof"
    )

    build_hoof(
        "RiverwatchV10HindLeftHoof",
        -0.305,
        0.455,
        "hind.L.hoof",
        0.122,
        0.245
    )

    build_hoof(
        "RiverwatchV10HindRightHoof",
        0.305,
        0.455,
        "hind.R.hoof",
        0.122,
        0.245
    )

    # ========================================================
    # EARS
    # ========================================================

    def build_ear(
        name,
        side
    ):

        sx = side

        verts = [
            (
                sx * 0.055,
                -1.095,
                1.955
            ),

            (
                sx * 0.135,
                -1.090,
                1.960
            ),

            (
                sx * 0.112,
                -1.065,
                2.160
            ),

            (
                sx * 0.064,
                -1.025,
                1.965
            ),

            (
                sx * 0.126,
                -1.020,
                1.970
            ),

            (
                sx * 0.108,
                -1.010,
                2.135
            ),
        ]

        faces = [
            (0, 1, 2),
            (5, 4, 3),
            (0, 3, 4, 1),
            (1, 4, 5, 2),
            (2, 5, 3, 0),
        ]

        mesh = bpy.data.meshes.new(
            name + "Mesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            name,
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            coat
        )

        subdivide(
            obj,
            1
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            "head"
        )

    build_ear(
        "RiverwatchV10LeftEar",
        -1
    )

    build_ear(
        "RiverwatchV10RightEar",
        1
    )

    # ========================================================
    # FACE DETAILS
    # ========================================================

    horse_sphere(
        "RiverwatchV10MuzzlePatch",
        (
            0.0,
            -1.710,
            1.672
        ),
        (
            0.130,
            0.082,
            0.062
        ),
        muzzle_mat,
        arm,
        "head",
        22,
        14
    )

    for side in (
        -1,
        1
    ):

        horse_sphere(
            "RiverwatchV10Eye",
            (
                side * 0.187,
                -1.280,
                1.825
            ),
            (
                0.029,
                0.019,
                0.029
            ),
            eye_mat,
            arm,
            "head",
            18,
            12
        )

        horse_sphere(
            "RiverwatchV10Pupil",
            (
                side * 0.206,
                -1.293,
                1.825
            ),
            (
                0.011,
                0.007,
                0.018
            ),
            pupil_mat,
            arm,
            "head",
            14,
            10
        )

        horse_sphere(
            "RiverwatchV10EyeGlint",
            (
                side * 0.216,
                -1.299,
                1.837
            ),
            (
                0.005,
                0.004,
                0.005
            ),
            glint_mat,
            arm,
            "head",
            10,
            8
        )

        horse_sphere(
            "RiverwatchV10Nostril",
            (
                side * 0.078,
                -1.748,
                1.675
            ),
            (
                0.020,
                0.013,
                0.015
            ),
            coat_dark,
            arm,
            "head",
            14,
            10
        )

    horse_cylinder(
        "RiverwatchV10BlazeUpper",
        (
            0.0,
            -1.140,
            1.915
        ),
        (
            0.0,
            -1.400,
            1.785
        ),
        0.018,
        ivory,
        arm,
        "head",
        0.011
    )

    horse_cylinder(
        "RiverwatchV10BlazeLower",
        (
            0.0,
            -1.400,
            1.785
        ),
        (
            0.0,
            -1.600,
            1.700
        ),
        0.011,
        ivory,
        arm,
        "head",
        0.006
    )

    # ========================================================
    # LAYERED MANE
    #
    # The reference has an actual flowing mane.
    #
    # These are tapered overlapping hair plates, not tubes.
    # ========================================================

    def mane_lock(
        name,
        y,
        root_z,
        tip_z,
        length,
        side,
        bone
    ):

        root_x = (
            0.018
            * side
        )

        tip_x = (
            length
            * side
        )

        thickness = 0.018

        top_y = y - 0.060
        bottom_y = y + 0.080

        verts = [
            (
                root_x - thickness,
                top_y,
                root_z
            ),

            (
                root_x + thickness,
                top_y,
                root_z
            ),

            (
                tip_x + thickness,
                bottom_y,
                tip_z
            ),

            (
                tip_x - thickness,
                bottom_y,
                tip_z
            ),

            (
                root_x - thickness,
                bottom_y,
                root_z - 0.020
            ),

            (
                root_x + thickness,
                bottom_y,
                root_z - 0.020
            ),

            (
                tip_x + thickness,
                bottom_y + 0.025,
                tip_z - 0.025
            ),

            (
                tip_x - thickness,
                bottom_y + 0.025,
                tip_z - 0.025
            ),
        ]

        faces = [
            (0, 1, 2, 3),
            (4, 7, 6, 5),
            (0, 4, 5, 1),
            (1, 5, 6, 2),
            (2, 6, 7, 3),
            (3, 7, 4, 0),
        ]

        mesh = bpy.data.meshes.new(
            name + "Mesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            name,
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            mane_mat
        )

        bevel_mesh(
            obj,
            0.008,
            2
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            bone
        )

        return obj

    mane_data = [
        (
            -1.080,
            2.015,
            1.875,
            0.100,
            "head"
        ),

        (
            -1.020,
            2.005,
            1.835,
            0.120,
            "head"
        ),

        (
            -0.955,
            1.985,
            1.790,
            0.145,
            "neck"
        ),

        (
            -0.890,
            1.955,
            1.745,
            0.165,
            "neck"
        ),

        (
            -0.825,
            1.915,
            1.695,
            0.180,
            "neck"
        ),

        (
            -0.760,
            1.870,
            1.650,
            0.190,
            "neck"
        ),

        (
            -0.695,
            1.820,
            1.605,
            0.185,
            "neck"
        ),

        (
            -0.635,
            1.770,
            1.570,
            0.170,
            "neck"
        ),

        (
            -0.580,
            1.720,
            1.545,
            0.150,
            "neck"
        ),
    ]

    for index, data in enumerate(
        mane_data
    ):

        y, root_z, tip_z, length, bone = data

        mane_lock(
            "RiverwatchV10ManeLock%02d"
            % index,

            y,
            root_z,
            tip_z,
            length,
            -1,
            bone
        )

    # A smaller visible opposite-side layer.
    for index, data in enumerate(
        mane_data[2:8]
    ):

        y, root_z, tip_z, length, bone = data

        mane_lock(
            "RiverwatchV10ManeBackLock%02d"
            % index,

            y + 0.012,
            root_z - 0.010,
            tip_z + 0.025,
            length * 0.45,
            1,
            bone
        )

    # Forelock.
    mane_lock(
        "RiverwatchV10Forelock",
        -1.125,
        2.020,
        1.840,
        0.060,
        -1,
        "head"
    )

    # ========================================================
    # FULL FLOWING TAIL
    #
    # One continuous 3D main tail.
    # No segmented sausage pieces.
    # ========================================================

    tail_sections = [
        (
            0.000,
            1.000,
            1.470,
            0.055,
            0.050
        ),

        (
            0.000,
            1.070,
            1.415,
            0.075,
            0.065
        ),

        (
            -0.005,
            1.150,
            1.335,
            0.100,
            0.078
        ),

        (
            -0.010,
            1.245,
            1.230,
            0.125,
            0.090
        ),

        (
            0.000,
            1.345,
            1.100,
            0.145,
            0.102
        ),

        (
            0.012,
            1.445,
            0.950,
            0.155,
            0.108
        ),

        (
            0.010,
            1.535,
            0.795,
            0.150,
            0.104
        ),

        (
            0.000,
            1.615,
            0.645,
            0.135,
            0.095
        ),

        (
            -0.010,
            1.680,
            0.515,
            0.108,
            0.080
        ),

        (
            -0.018,
            1.725,
            0.410,
            0.070,
            0.057
        ),

        (
            -0.020,
            1.750,
            0.350,
            0.035,
            0.035
        ),
    ]

    tail_weights = [
        {"tail.1": 1.0},
        {"tail.1": 1.0},
        {"tail.1": 1.0},

        {
            "tail.1": 0.70,
            "tail.2": 0.30
        },

        {
            "tail.1": 0.35,
            "tail.2": 0.65
        },

        {"tail.2": 1.0},
        {"tail.2": 1.0},
        {"tail.2": 1.0},
        {"tail.2": 1.0},
        {"tail.2": 1.0},
        {"tail.2": 1.0},
    ]

    def build_tail():

        centers = [
            Vector(
                (
                    section[0],
                    section[1],
                    section[2]
                )
            )
            for section in tail_sections
        ]

        rings = 30

        verts = []
        faces = []

        for index, section in enumerate(
            tail_sections
        ):

            center = centers[
                index
            ]

            tangent, lateral, depth = sweep_frame(
                centers,
                index
            )

            radius_x = section[3]
            radius_depth = section[4]

            for ring_index in range(
                rings
            ):

                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                point = (
                    center
                    + lateral
                    * (
                        math.cos(angle)
                        * radius_x
                    )
                    + depth
                    * (
                        math.sin(angle)
                        * radius_depth
                    )
                )

                verts.append(
                    tuple(point)
                )

        for index in range(
            len(tail_sections) - 1
        ):

            first = (
                index * rings
            )

            second = (
                index + 1
            ) * rings

            for ring_index in range(
                rings
            ):

                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring
                    )
                )

        mesh = bpy.data.meshes.new(
            "RiverwatchV10TailMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV10Tail",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            mane_mat
        )

        tail1 = obj.vertex_groups.new(
            name="tail.1"
        )

        tail2 = obj.vertex_groups.new(
            name="tail.2"
        )

        for section_index, weight_map in enumerate(
            tail_weights
        ):

            indices = list(
                range(
                    section_index * rings,
                    section_index * rings + rings
                )
            )

            for group_name, weight in weight_map.items():

                if group_name == "tail.1":

                    tail1.add(
                        indices,
                        weight,
                        "REPLACE"
                    )

                else:

                    tail2.add(
                        indices,
                        weight,
                        "REPLACE"
                    )

        subdivide(
            obj,
            1
        )

        smooth(
            obj
        )

        bind_armature(
            obj
        )

        return obj

    build_tail()

    # ========================================================
    # BLANKET
    # ========================================================

    def build_blanket():

        x_values = [
            -0.385,
            -0.255,
            -0.125,
            0.000,
            0.125,
            0.255,
            0.385,
        ]

        y_values = [
            -0.365,
            -0.180,
            0.000,
            0.180,
            0.365,
        ]

        verts = []
        faces = []

        for y in y_values:

            for x in x_values:

                side = (
                    abs(x)
                    / 0.385
                )

                end = (
                    abs(y)
                    / 0.365
                )

                z = (
                    1.785
                    - 0.155
                    * (
                        side ** 1.55
                    )
                    - 0.012
                    * end
                )

                verts.append(
                    (
                        x,
                        y,
                        z
                    )
                )

        width = len(
            x_values
        )

        height = len(
            y_values
        )

        for yi in range(
            height - 1
        ):

            for xi in range(
                width - 1
            ):

                a = (
                    yi * width
                    + xi
                )

                b = a + 1
                c = a + width + 1
                d = a + width

                faces.append(
                    (
                        a,
                        d,
                        c,
                        b
                    )
                )

        mesh = bpy.data.meshes.new(
            "RiverwatchV10BlanketMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV10Blanket",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            blanket
        )

        solidify = obj.modifiers.new(
            "BlanketThickness",
            "SOLIDIFY"
        )

        solidify.thickness = 0.020

        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.modifier_apply(
            modifier=solidify.name
        )

        bevel_mesh(
            obj,
            0.008,
            2
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            "body"
        )

        return obj

    build_blanket()

    # Gold blanket trim, simple and readable.
    for side in (
        -1,
        1
    ):

        horse_cylinder(
            "RiverwatchV10BlanketTrim",
            (
                side * 0.385,
                -0.350,
                1.625
            ),
            (
                side * 0.385,
                0.350,
                1.625
            ),
            0.009,
            blanket_trim,
            arm,
            "body"
        )

    # ========================================================
    # CLEAN REFERENCE SADDLE
    # ========================================================

    def build_saddle_seat():

        x_values = [
            -0.250,
            -0.125,
            0.000,
            0.125,
            0.250,
        ]

        y_values = [
            -0.270,
            -0.135,
            0.000,
            0.135,
            0.270,
        ]

        verts = []
        faces = []

        for y in y_values:

            for x in x_values:

                side = (
                    abs(x)
                    / 0.250
                )

                end = (
                    abs(y)
                    / 0.270
                )

                z = (
                    1.805
                    + 0.022
                    * (
                        side ** 1.5
                    )
                    + 0.030
                    * (
                        end ** 1.9
                    )
                )

                verts.append(
                    (
                        x,
                        y,
                        z
                    )
                )

        width = len(
            x_values
        )

        height = len(
            y_values
        )

        for yi in range(
            height - 1
        ):

            for xi in range(
                width - 1
            ):

                a = (
                    yi * width
                    + xi
                )

                b = a + 1
                c = a + width + 1
                d = a + width

                faces.append(
                    (
                        a,
                        d,
                        c,
                        b
                    )
                )

        mesh = bpy.data.meshes.new(
            "RiverwatchV10SaddleSeatMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV10SaddleSeat",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            leather
        )

        solidify = obj.modifiers.new(
            "SaddleThickness",
            "SOLIDIFY"
        )

        solidify.thickness = 0.055

        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.modifier_apply(
            modifier=solidify.name
        )

        bevel_mesh(
            obj,
            0.014,
            3
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            "body"
        )

        return obj

    build_saddle_seat()

    # Pommel.
    horse_cylinder(
        "RiverwatchV10Pommel",
        (
            -0.205,
            -0.245,
            1.855
        ),
        (
            0.205,
            -0.245,
            1.855
        ),
        0.032,
        leather_mid,
        arm,
        "body"
    )

    # Small saddle horn.
    horse_cylinder(
        "RiverwatchV10SaddleHorn",
        (
            0.0,
            -0.245,
            1.870
        ),
        (
            0.0,
            -0.250,
            1.955
        ),
        0.022,
        leather_mid,
        arm,
        "body",
        0.018
    )

    # Cantle.
    horse_cylinder(
        "RiverwatchV10Cantle",
        (
            -0.220,
            0.245,
            1.870
        ),
        (
            0.220,
            0.245,
            1.870
        ),
        0.038,
        leather_mid,
        arm,
        "body"
    )

    # ========================================================
    # SADDLE FLAPS
    # ========================================================

    def saddle_flap(
        name,
        side
    ):

        outer_x = (
            0.300
            * side
        )

        inner_x = (
            0.275
            * side
        )

        outline = [
            (
                -0.205,
                1.735
            ),

            (
                -0.120,
                1.620
            ),

            (
                0.020,
                1.520
            ),

            (
                0.180,
                1.505
            ),

            (
                0.220,
                1.590
            ),

            (
                0.130,
                1.690
            ),
        ]

        verts = []

        for y, z in outline:

            verts.append(
                (
                    outer_x,
                    y,
                    z
                )
            )

        for y, z in outline:

            verts.append(
                (
                    inner_x,
                    y,
                    z
                )
            )

        count = len(
            outline
        )

        faces = [
            tuple(
                range(
                    count
                )
            ),

            tuple(
                reversed(
                    range(
                        count,
                        count * 2
                    )
                )
            ),
        ]

        for index in range(
            count
        ):

            next_index = (
                index + 1
            ) % count

            faces.append(
                (
                    index,
                    next_index,
                    count + next_index,
                    count + index
                )
            )

        mesh = bpy.data.meshes.new(
            name + "Mesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            name,
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            leather
        )

        bevel_mesh(
            obj,
            0.012,
            3
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            "body"
        )

        return obj

    saddle_flap(
        "RiverwatchV10LeftSaddleFlap",
        -1
    )

    saddle_flap(
        "RiverwatchV10RightSaddleFlap",
        1
    )

    # ========================================================
    # SMALL PACK BAGS FROM REFERENCE
    # ========================================================

    for side in (
        -1,
        1
    ):

        horse_cube(
            "RiverwatchV10PackBag",
            (
                side * 0.365,
                0.300,
                1.540
            ),
            (
                0.155,
                0.240,
                0.250
            ),
            leather,
            arm,
            "body",
            edge=0.040
        )

        horse_cube(
            "RiverwatchV10PackBagFlap",
            (
                side * 0.375,
                0.255,
                1.605
            ),
            (
                0.165,
                0.180,
                0.070
            ),
            leather_mid,
            arm,
            "body",
            rotation=(
                0.06,
                0.0,
                0.0
            ),
            edge=0.026
        )

        # Bag buckle.
        buckle = torus(
            "RiverwatchV10BagBuckle",
            (
                side * 0.458,
                0.220,
                1.570
            ),
            0.025,
            0.005,
            brass,
            rotation=(
                0.0,
                math.pi / 2,
                0.0
            )
        )

        rigid_skin(
            buckle,
            arm,
            "body"
        )

    # ========================================================
    # GIRTH / STIRRUPS
    # ========================================================

    girth = torus(
        "RiverwatchV10Girth",
        (
            0.0,
            -0.010,
            1.390
        ),
        0.405,
        0.020,
        leather_dark,
        rotation=(
            math.pi / 2,
            0.0,
            0.0
        )
    )

    rigid_skin(
        girth,
        arm,
        "body"
    )

    for side in (
        -1,
        1
    ):

        horse_cylinder(
            "RiverwatchV10StirrupLeather",
            (
                side * 0.225,
                -0.020,
                1.790
            ),
            (
                side * 0.390,
                -0.010,
                1.055
            ),
            0.009,
            leather_dark,
            arm,
            "body"
        )

        stirrup = torus(
            "RiverwatchV10Stirrup",
            (
                side * 0.400,
                -0.010,
                0.985
            ),
            0.082,
            0.013,
            iron,
            rotation=(
                math.pi / 2,
                0.0,
                0.0
            )
        )

        rigid_skin(
            stirrup,
            arm,
            "body"
        )

    # ========================================================
    # CURVED REIN / BRIDLE HELPER
    # ========================================================

    def curve_tube(
        name,
        points,
        radius,
        mat,
        bone_name
    ):

        curve_data = bpy.data.curves.new(
            name + "Curve",
            type="CURVE"
        )

        curve_data.dimensions = "3D"
        curve_data.resolution_u = 3
        curve_data.bevel_depth = radius
        curve_data.bevel_resolution = 2
        curve_data.fill_mode = "FULL"

        spline = curve_data.splines.new(
            "BEZIER"
        )

        spline.bezier_points.add(
            len(points) - 1
        )

        for index, point in enumerate(
            points
        ):

            bezier_point = spline.bezier_points[
                index
            ]

            bezier_point.co = point
            bezier_point.handle_left_type = "AUTO"
            bezier_point.handle_right_type = "AUTO"

        obj = bpy.data.objects.new(
            name,
            curve_data
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            mat
        )

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(
            True
        )

        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.convert(
            target="MESH"
        )

        obj = bpy.context.object

        smooth(
            obj
        )

        rigid_bind(
            obj,
            bone_name
        )

        return obj

    # ========================================================
    # CLEAN BRIDLE
    # ========================================================

    noseband = torus(
        "RiverwatchV10NoseBand",
        (
            0.0,
            -1.570,
            1.680
        ),
        0.155,
        0.010,
        leather,
        rotation=(
            math.pi / 2,
            0.0,
            0.0
        )
    )

    rigid_skin(
        noseband,
        arm,
        "head"
    )

    horse_cylinder(
        "RiverwatchV10BrowBand",
        (
            -0.160,
            -1.160,
            1.900
        ),
        (
            0.160,
            -1.160,
            1.900
        ),
        0.010,
        leather,
        arm,
        "head"
    )

    for side in (
        -1,
        1
    ):

        horse_cylinder(
            "RiverwatchV10CheekStrap",
            (
                side * 0.150,
                -1.150,
                1.900
            ),
            (
                side * 0.150,
                -1.570,
                1.680
            ),
            0.008,
            leather,
            arm,
            "head"
        )

        bit_ring = torus(
            "RiverwatchV10BitRing",
            (
                side * 0.160,
                -1.620,
                1.640
            ),
            0.032,
            0.006,
            brass,
            rotation=(
                math.pi / 2,
                0.0,
                0.0
            )
        )

        rigid_skin(
            bit_ring,
            arm,
            "head"
        )

        curve_tube(
            "RiverwatchV10Rein",
            [
                (
                    side * 0.160,
                    -1.620,
                    1.640
                ),

                (
                    side * 0.210,
                    -1.260,
                    1.600
                ),

                (
                    side * 0.240,
                    -0.780,
                    1.650
                ),

                (
                    side * 0.235,
                    -0.270,
                    1.715
                ),
            ],
            0.006,
            leather_dark,
            "head"
        )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "reference_sheet_v10"

    arm[
        "broken_knight_horse_target"
    ] = "fantasy_riding_pack_horse_reference"

    arm[
        "broken_knight_horse_core"
    ] = "true_3d_anatomical_centerline_sweep"

    arm[
        "broken_knight_horse_voxel_remesh"
    ] = False

    arm[
        "broken_knight_horse_body_blobs"
    ] = False

    arm[
        "broken_knight_horse_leg_topology"
    ] = "true_3d_perpendicular_sweep"

    arm[
        "broken_knight_horse_proportions"
    ] = "stocky_riding_courser"

    arm[
        "broken_knight_horse_mane"
    ] = "layered_flowing_hair"

    arm[
        "broken_knight_horse_tail"
    ] = "single_flowing_3d_mass"

    arm[
        "broken_knight_horse_saddle"
    ] = "reference_fitted_medieval_pack_saddle"

def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def key_pose(arm, frame, transforms):
    reset_pose(arm)
    for name, values in transforms.items():
        bone = arm.pose.bones[name]
        if "rot" in values:
            bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def make_action(arm, name, keys, end_frame):
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    action.frame_start = 1
    action.frame_end = end_frame
    return action


def make_horse_animations(arm):
    # --------------------------------------------------------
    # IDLE
    # Breathing, head movement and a relaxed tail swish.
    # --------------------------------------------------------

    idle = make_action(
        arm,
        "Idle",
        [
            (
                1,
                {
                    "body": {"loc": (0, 0, 0.0)},
                    "neck": {"rot": (-1.5, 0, 0)},
                    "head": {"rot": (1.0, 0, -1.0)},
                    "tail.1": {"rot": (0, -5, 0)},
                    "tail.2": {"rot": (0, 8, 0)},
                }
            ),
            (
                18,
                {
                    "body": {"loc": (0, 0, 0.012)},
                    "neck": {"rot": (1.5, 0, 1.0)},
                    "head": {"rot": (-2.0, 0, 2.0)},
                    "tail.1": {"rot": (0, 8, 0)},
                    "tail.2": {"rot": (0, -13, 0)},
                }
            ),
            (
                36,
                {
                    "body": {"loc": (0, 0, 0.022)},
                    "neck": {"rot": (3.0, 0, -1.0)},
                    "head": {"rot": (-4.0, 0, -2.0)},
                    "tail.1": {"rot": (0, 2, 0)},
                    "tail.2": {"rot": (0, -5, 0)},
                }
            ),
            (
                54,
                {
                    "body": {"loc": (0, 0, 0.010)},
                    "neck": {"rot": (0.5, 0, -1.5)},
                    "head": {"rot": (-1.0, 0, 1.0)},
                    "tail.1": {"rot": (0, -9, 0)},
                    "tail.2": {"rot": (0, 15, 0)},
                }
            ),
            (
                72,
                {
                    "body": {"loc": (0, 0, 0.0)},
                    "neck": {"rot": (-1.5, 0, 0)},
                    "head": {"rot": (1.0, 0, -1.0)},
                    "tail.1": {"rot": (0, -5, 0)},
                    "tail.2": {"rot": (0, 8, 0)},
                }
            ),
        ],
        72
    )

    # --------------------------------------------------------
    # TROT
    # Smooth diagonal gait with body lift and hoof articulation.
    # --------------------------------------------------------

    trot_keys = []

    frames = (1, 5, 9, 13, 17, 21, 25, 29, 33)

    for frame in frames:

        phase = ((frame - 1) / 32.0) * math.tau

        swing = math.sin(phase)
        bounce = 0.042 * (0.5 - 0.5 * math.cos(phase * 2.0))

        front_left = 34.0 * swing
        front_right = -front_left

        hind_left = -31.0 * swing
        hind_right = -hind_left

        pose = {
            "body": {
                "loc": (0, 0, bounce),
                "rot": (1.8 * math.sin(phase * 2.0), 0, 0)
            },

            "neck": {
                "rot": (-4.2 * math.sin(phase * 2.0), 0, 0)
            },

            "head": {
                "rot": (5.0 * math.sin(phase * 2.0), 0, 0)
            },

            "tail.1": {
                "rot": (0, 10.0 * swing, 0)
            },

            "tail.2": {
                "rot": (0, -15.0 * swing, 0)
            },

            "front.L.upper": {
                "rot": (front_left, 0, 0)
            },

            "front.R.upper": {
                "rot": (front_right, 0, 0)
            },

            "hind.L.upper": {
                "rot": (hind_left, 0, 0)
            },

            "hind.R.upper": {
                "rot": (hind_right, 0, 0)
            },

            "front.L.lower": {
                "rot": (
                    -18.0 * max(0.0, swing)
                    + 7.0 * max(0.0, -swing),
                    0,
                    0
                )
            },

            "front.R.lower": {
                "rot": (
                    -18.0 * max(0.0, -swing)
                    + 7.0 * max(0.0, swing),
                    0,
                    0
                )
            },

            "hind.L.lower": {
                "rot": (
                    -23.0 * max(0.0, -swing)
                    + 8.0 * max(0.0, swing),
                    0,
                    0
                )
            },

            "hind.R.lower": {
                "rot": (
                    -23.0 * max(0.0, swing)
                    + 8.0 * max(0.0, -swing),
                    0,
                    0
                )
            },

            "front.L.hoof": {
                "rot": (-10.0 * swing, 0, 0)
            },

            "front.R.hoof": {
                "rot": (10.0 * swing, 0, 0)
            },

            "hind.L.hoof": {
                "rot": (8.0 * swing, 0, 0)
            },

            "hind.R.hoof": {
                "rot": (-8.0 * swing, 0, 0)
            },
        }

        trot_keys.append((frame, pose))

    trot = make_action(
        arm,
        "Trot",
        trot_keys,
        33
    )

    arm.animation_data.action = None

    for action in (idle, trot):

        track = arm.animation_data.nla_tracks.new()
        track.name = action.name

        strip = track.strips.new(
            action.name,
            int(action.frame_start),
            action
        )

        strip.mute = True

    return idle, trot

def consolidate_horse(arm):
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.parent == arm]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = max(parts, key=lambda obj: len(obj.data.vertices))
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "RiverwatchHorseBody"
    body.data.name = "RiverwatchHorseBodyMesh"
    body.parent = arm
    for modifier in body.modifiers:
        if modifier.type == "ARMATURE":
            modifier.object = arm
    return body


def export_horse(arm):
    os.makedirs(os.path.dirname(HORSE_GLB), exist_ok=True)
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=HORSE_GLB,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_lights=False,
        export_cameras=False,
        export_apply=False,
    )


def build_horse():
    clear_scene()
    bpy.context.scene.render.fps = 30
    arm = build_armature()
    build_horse_model(arm)
    actions = make_horse_animations(arm)
    consolidate_horse(arm)
    os.makedirs(os.path.dirname(HORSE_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=HORSE_BLEND)
    export_horse(arm)
    print("RIVERWATCH_HORSE_BUILT|blend=%s|glb=%s|animations=%s" % (
        HORSE_BLEND, HORSE_GLB, ",".join(action.name for action in actions)))


if __name__ == "__main__":
    build_stable()
    build_horse()