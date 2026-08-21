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


def build_horse_model_v11_base(arm):
    # ========================================================
    # BROKEN KNIGHT
    # RIVERWATCH HORSE V11
    #
    # ANATOMY CONTROL-CAGE REBUILD
    #
    # This deliberately abandons:
    #
    # - voxel-remeshed blobs
    # - smooth procedural torso tubes
    # - sphere-built anatomy
    # - decorative tack hiding bad proportions
    #
    # V11 is built like a manually box-modeled Blender horse.
    #
    # The major anatomical landmarks are explicitly authored:
    #
    # - tail root
    # - croup
    # - point of hip
    # - loin
    # - rib cage
    # - flank tuck
    # - chest
    # - shoulder
    # - withers
    # - neck crest
    # - throat
    # - poll
    # - forehead
    # - cheek
    # - jaw
    # - nasal bridge
    # - muzzle
    #
    # The control cage is then subdivided once.
    #
    # Legs are also low-poly joint cages rather than
    # high-resolution tubes.
    #
    # IMPORTANT:
    #
    # V11 intentionally has NO saddle, blanket, packs or reins.
    # We need to make the horse itself good first.
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V11 Warm Bay",
        (0.33, 0.100, 0.028, 1),
        0.55
    )

    dark_points = material(
        "Riverwatch V11 Dark Points",
        (0.052, 0.017, 0.008, 1),
        0.67
    )

    mane_mat = material(
        "Riverwatch V11 Mane Tail",
        (0.012, 0.008, 0.006, 1),
        0.68
    )

    muzzle_mat = material(
        "Riverwatch V11 Muzzle",
        (0.150, 0.095, 0.074, 1),
        0.73
    )

    hoof_mat = material(
        "Riverwatch V11 Hoof",
        (0.050, 0.040, 0.033, 1),
        0.77
    )

    ivory = material(
        "Riverwatch V11 Blaze",
        (0.82, 0.78, 0.69, 1),
        0.78
    )

    eye_mat = material(
        "Riverwatch V11 Eye",
        (0.050, 0.018, 0.006, 1),
        0.16
    )

    pupil_mat = material(
        "Riverwatch V11 Pupil",
        (0.002, 0.002, 0.002, 1),
        0.10
    )

    glint_mat = material(
        "Riverwatch V11 Eye Glint",
        (0.96, 0.95, 0.91, 1),
        0.10
    )

    # ========================================================
    # HELPERS
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

    def apply_subdivision(
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
            "HorseControlCageSubdivision",
            "SUBSURF"
        )

        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = levels
        modifier.render_levels = levels

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    def apply_bevel(
        obj,
        width=0.015,
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
            "HorseControlCageBevel",
            "BEVEL"
        )

        modifier.width = width
        modifier.segments = segments

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    # ========================================================
    # MAIN HORSE CONTROL CAGE
    #
    # Each station is manually authored.
    #
    # Format:
    #
    # (
    #   y,
    #   top_z,
    #   upper_z,
    #   middle_z,
    #   lower_z,
    #   belly_z,
    #   top_half_width,
    #   upper_half_width,
    #   middle_half_width,
    #   lower_half_width,
    #   belly_half_width
    # )
    #
    # Ten vertices are built around each cross section.
    #
    # Unlike the old procedural ring system, these are
    # explicitly placed cage bands intended to behave like
    # hand-modeled topology.
    # ========================================================

    def build_anatomy_cage():

        stations = [
            # ------------------------------------------------
            # TAIL ROOT
            # ------------------------------------------------
            (
                1.075,
                1.590,
                1.545,
                1.470,
                1.385,
                1.320,
                0.050,
                0.095,
                0.125,
                0.105,
                0.055
            ),

            # ------------------------------------------------
            # REAR CROUP
            # ------------------------------------------------
            (
                0.970,
                1.755,
                1.695,
                1.515,
                1.320,
                1.185,
                0.110,
                0.330,
                0.445,
                0.395,
                0.210
            ),

            # ------------------------------------------------
            # FULL CROUP / POINT OF HIP
            # ------------------------------------------------
            (
                0.800,
                1.820,
                1.735,
                1.510,
                1.285,
                1.115,
                0.145,
                0.410,
                0.515,
                0.465,
                0.255
            ),

            # ------------------------------------------------
            # HIP / LOIN TRANSITION
            # ------------------------------------------------
            (
                0.610,
                1.810,
                1.710,
                1.475,
                1.245,
                1.095,
                0.140,
                0.405,
                0.520,
                0.470,
                0.265
            ),

            # ------------------------------------------------
            # REAR BARREL
            # ------------------------------------------------
            (
                0.390,
                1.775,
                1.675,
                1.440,
                1.215,
                1.070,
                0.130,
                0.385,
                0.505,
                0.465,
                0.265
            ),

            # ------------------------------------------------
            # MID BARREL
            # ------------------------------------------------
            (
                0.150,
                1.755,
                1.655,
                1.420,
                1.185,
                1.035,
                0.125,
                0.375,
                0.495,
                0.465,
                0.270
            ),

            # ------------------------------------------------
            # FRONT BARREL
            # ------------------------------------------------
            (
                -0.080,
                1.750,
                1.655,
                1.425,
                1.185,
                1.025,
                0.125,
                0.380,
                0.495,
                0.465,
                0.265
            ),

            # ------------------------------------------------
            # CHEST
            # ------------------------------------------------
            (
                -0.285,
                1.775,
                1.685,
                1.455,
                1.205,
                1.045,
                0.135,
                0.395,
                0.490,
                0.450,
                0.245
            ),

            # ------------------------------------------------
            # SHOULDER
            # ------------------------------------------------
            (
                -0.455,
                1.845,
                1.735,
                1.505,
                1.285,
                1.120,
                0.120,
                0.355,
                0.440,
                0.400,
                0.220
            ),

            # ------------------------------------------------
            # WITHERS
            # ------------------------------------------------
            (
                -0.580,
                1.950,
                1.805,
                1.590,
                1.390,
                1.235,
                0.075,
                0.280,
                0.350,
                0.320,
                0.185
            ),

            # ------------------------------------------------
            # NECK BASE
            # ------------------------------------------------
            (
                -0.680,
                1.995,
                1.860,
                1.660,
                1.470,
                1.325,
                0.065,
                0.245,
                0.305,
                0.280,
                0.165
            ),

            # ------------------------------------------------
            # LOWER NECK
            # ------------------------------------------------
            (
                -0.790,
                2.030,
                1.915,
                1.725,
                1.545,
                1.400,
                0.060,
                0.220,
                0.275,
                0.250,
                0.145
            ),

            # ------------------------------------------------
            # UPPER NECK
            # ------------------------------------------------
            (
                -0.905,
                2.060,
                1.955,
                1.790,
                1.620,
                1.480,
                0.055,
                0.200,
                0.245,
                0.225,
                0.130
            ),

            # ------------------------------------------------
            # POLL
            # ------------------------------------------------
            (
                -1.015,
                2.055,
                1.975,
                1.845,
                1.700,
                1.575,
                0.045,
                0.165,
                0.205,
                0.190,
                0.110
            ),

            # ------------------------------------------------
            # BACK OF SKULL
            # ------------------------------------------------
            (
                -1.120,
                2.015,
                1.950,
                1.840,
                1.715,
                1.610,
                0.040,
                0.160,
                0.205,
                0.185,
                0.095
            ),

            # ------------------------------------------------
            # FOREHEAD / CHEEK
            # ------------------------------------------------
            (
                -1.235,
                1.965,
                1.910,
                1.805,
                1.690,
                1.595,
                0.035,
                0.165,
                0.205,
                0.185,
                0.090
            ),

            # ------------------------------------------------
            # JAW
            # ------------------------------------------------
            (
                -1.350,
                1.905,
                1.860,
                1.760,
                1.655,
                1.575,
                0.030,
                0.155,
                0.195,
                0.175,
                0.082
            ),

            # ------------------------------------------------
            # NASAL BRIDGE
            # ------------------------------------------------
            (
                -1.465,
                1.845,
                1.815,
                1.730,
                1.645,
                1.585,
                0.025,
                0.135,
                0.170,
                0.150,
                0.070
            ),

            # ------------------------------------------------
            # MUZZLE ROOT
            # ------------------------------------------------
            (
                -1.575,
                1.785,
                1.765,
                1.695,
                1.630,
                1.585,
                0.020,
                0.110,
                0.145,
                0.125,
                0.060
            ),

            # ------------------------------------------------
            # MUZZLE
            # ------------------------------------------------
            (
                -1.675,
                1.740,
                1.725,
                1.670,
                1.620,
                1.585,
                0.015,
                0.095,
                0.125,
                0.105,
                0.050
            ),

            # ------------------------------------------------
            # NOSE TIP
            # ------------------------------------------------
            (
                -1.755,
                1.705,
                1.695,
                1.660,
                1.625,
                1.600,
                0.008,
                0.050,
                0.075,
                0.055,
                0.025
            ),
        ]

        verts = []
        faces = []

        vertices_per_station = 10

        # ----------------------------------------------------
        # CREATE EXPLICIT CONTROL RINGS
        # ----------------------------------------------------

        for station in stations:

            (
                y,
                top_z,
                upper_z,
                middle_z,
                lower_z,
                belly_z,
                top_width,
                upper_width,
                middle_width,
                lower_width,
                belly_width
            ) = station

            # Clockwise around the horse:
            #
            # left dorsal
            # left upper
            # left middle
            # left lower
            # left belly
            # right belly
            # right lower
            # right middle
            # right upper
            # right dorsal

            verts.extend(
                [
                    (
                        -top_width,
                        y,
                        top_z
                    ),

                    (
                        -upper_width,
                        y,
                        upper_z
                    ),

                    (
                        -middle_width,
                        y,
                        middle_z
                    ),

                    (
                        -lower_width,
                        y,
                        lower_z
                    ),

                    (
                        -belly_width,
                        y,
                        belly_z
                    ),

                    (
                        belly_width,
                        y,
                        belly_z
                    ),

                    (
                        lower_width,
                        y,
                        lower_z
                    ),

                    (
                        middle_width,
                        y,
                        middle_z
                    ),

                    (
                        upper_width,
                        y,
                        upper_z
                    ),

                    (
                        top_width,
                        y,
                        top_z
                    ),
                ]
            )

        # ----------------------------------------------------
        # CONNECT THE CAGE
        # ----------------------------------------------------

        for station_index in range(
            len(stations) - 1
        ):

            current_start = (
                station_index
                * vertices_per_station
            )

            next_start = (
                station_index + 1
            ) * vertices_per_station

            for vertex_index in range(
                vertices_per_station
            ):

                next_vertex = (
                    vertex_index + 1
                ) % vertices_per_station

                faces.append(
                    (
                        current_start + vertex_index,
                        next_start + vertex_index,
                        next_start + next_vertex,
                        current_start + next_vertex
                    )
                )

        # ----------------------------------------------------
        # REAR CAP
        # ----------------------------------------------------

        rear_center = len(
            verts
        )

        rear_station = stations[0]

        verts.append(
            (
                0.0,
                rear_station[0],
                (
                    rear_station[1]
                    + rear_station[5]
                )
                * 0.5
            )
        )

        for vertex_index in range(
            vertices_per_station
        ):

            next_vertex = (
                vertex_index + 1
            ) % vertices_per_station

            faces.append(
                (
                    rear_center,
                    next_vertex,
                    vertex_index
                )
            )

        # ----------------------------------------------------
        # NOSE CAP
        # ----------------------------------------------------

        nose_center = len(
            verts
        )

        nose_station = stations[-1]

        verts.append(
            (
                0.0,
                nose_station[0],
                (
                    nose_station[1]
                    + nose_station[5]
                )
                * 0.5
            )
        )

        nose_start = (
            len(stations) - 1
        ) * vertices_per_station

        for vertex_index in range(
            vertices_per_station
        ):

            next_vertex = (
                vertex_index + 1
            ) % vertices_per_station

            faces.append(
                (
                    nose_center,
                    nose_start + vertex_index,
                    nose_start + next_vertex
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV11AnatomyControlCageMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV11AnatomyControlCage",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            coat
        )

        # ----------------------------------------------------
        # RIG GROUPS BEFORE SUBDIVISION
        # ----------------------------------------------------

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

            if y >= -0.600:

                body_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -0.820:

                blend = (
                    (-0.600 - y)
                    / 0.220
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

            elif y >= -1.040:

                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -1.190:

                blend = (
                    (-1.040 - y)
                    / 0.150
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

        # One subdivision level:
        #
        # enough to turn the explicit cage into a smooth horse,
        # but not enough to melt all of our anatomy landmarks.

        apply_subdivision(
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

    build_anatomy_cage()

    # ========================================================
    # LIMB CONTROL CAGE
    #
    # Eight-sided low-poly joint loops.
    #
    # This keeps the good V8/V10 3D orientation idea,
    # but makes the topology act more like box modeling.
    # ========================================================

    def limb_frame(
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
                (
                    0.0,
                    0.0,
                    -1.0
                )
            )

        tangent.normalize()

        lateral = Vector(
            (
                1.0,
                0.0,
                0.0
            )
        )

        lateral = (
            lateral
            - tangent
            * lateral.dot(
                tangent
            )
        )

        if lateral.length < 0.00001:

            lateral = Vector(
                (
                    0.0,
                    1.0,
                    0.0
                )
            )

            lateral = (
                lateral
                - tangent
                * lateral.dot(
                    tangent
                )
            )

        lateral.normalize()

        depth = tangent.cross(
            lateral
        )

        if depth.length < 0.00001:

            depth = Vector(
                (
                    0.0,
                    1.0,
                    0.0
                )
            )

        depth.normalize()

        return (
            lateral,
            depth
        )

    def build_limb_cage(
        name,
        sections,
        weights,
        dark_below
    ):

        # Each section:
        #
        # (
        #   x,
        #   y,
        #   z,
        #   lateral_radius,
        #   front_back_radius
        # )

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

        rings = 8

        verts = []
        faces = []

        for section_index, section in enumerate(
            sections
        ):

            center = centers[
                section_index
            ]

            lateral, depth = limb_frame(
                centers,
                section_index
            )

            rx = section[3]
            rd = section[4]

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
                        * rx
                    )
                    + depth
                    * (
                        math.sin(angle)
                        * rd
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
            dark_points
        )

        # Dark lower legs.
        for polygon in obj.data.polygons:

            average_z = (
                sum(
                    obj.data.vertices[
                        index
                    ].co.z
                    for index in polygon.vertices
                )
                / len(
                    polygon.vertices
                )
            )

            if average_z <= dark_below:

                polygon.material_index = 1

        groups = {}

        for weight_map in weights:

            for group_name in weight_map.keys():

                if group_name not in groups:

                    groups[
                        group_name
                    ] = obj.vertex_groups.new(
                        name=group_name
                    )

        for section_index, weight_map in enumerate(
            weights
        ):

            section_vertices = list(
                range(
                    section_index * rings,
                    section_index * rings + rings
                )
            )

            for group_name, weight in weight_map.items():

                groups[
                    group_name
                ].add(
                    section_vertices,
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

        apply_subdivision(
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
    # Hand-authored landmarks:
    #
    # shoulder
    # elbow
    # forearm
    # knee
    # cannon
    # fetlock
    # pastern
    # ========================================================

    def front_sections(
        side
    ):

        x = (
            side
            * 0.285
        )

        return [
            # Shoulder merge.
            (
                x,
                -0.405,
                1.205,
                0.155,
                0.142
            ),

            # Upper arm.
            (
                x,
                -0.425,
                1.075,
                0.142,
                0.130
            ),

            # Elbow / upper forearm.
            (
                x,
                -0.440,
                0.940,
                0.125,
                0.115
            ),

            # Forearm.
            (
                x,
                -0.452,
                0.790,
                0.105,
                0.097
            ),

            # Knee top.
            (
                x,
                -0.465,
                0.665,
                0.112,
                0.103
            ),

            # Knee bottom.
            (
                x,
                -0.475,
                0.605,
                0.108,
                0.098
            ),

            # Upper cannon.
            (
                x,
                -0.486,
                0.505,
                0.078,
                0.070
            ),

            # Cannon.
            (
                x,
                -0.497,
                0.390,
                0.069,
                0.062
            ),

            # Lower cannon.
            (
                x,
                -0.508,
                0.285,
                0.068,
                0.061
            ),

            # Fetlock.
            (
                x,
                -0.522,
                0.205,
                0.090,
                0.081
            ),

            # Pastern.
            (
                x,
                -0.548,
                0.135,
                0.075,
                0.068
            ),
        ]

    def front_weights(
        prefix
    ):

        return [
            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 0.55,
                prefix + ".lower": 0.45
            },

            {
                prefix + ".upper": 0.25,
                prefix + ".lower": 0.75
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 0.55,
                prefix + ".hoof": 0.45
            },

            {
                prefix + ".hoof": 1.0
            },
        ]

    build_limb_cage(
        "RiverwatchV11FrontLeftLeg",
        front_sections(
            -1
        ),
        front_weights(
            "front.L"
        ),
        0.410
    )

    build_limb_cage(
        "RiverwatchV11FrontRightLeg",
        front_sections(
            1
        ),
        front_weights(
            "front.R"
        ),
        0.410
    )

    # ========================================================
    # HIND LEGS
    #
    # Explicit S-curve:
    #
    # hip
    # stifle forward
    # gaskin
    # hock backward
    # cannon
    # fetlock
    # pastern
    # ========================================================

    def hind_sections(
        side
    ):

        x = (
            side
            * 0.305
        )

        return [
            # Hip merge.
            (
                x,
                0.555,
                1.210,
                0.180,
                0.165
            ),

            # Thigh.
            (
                x,
                0.510,
                1.080,
                0.170,
                0.155
            ),

            # Stifle forward.
            (
                x,
                0.395,
                0.935,
                0.147,
                0.135
            ),

            # Gaskin.
            (
                x,
                0.405,
                0.800,
                0.127,
                0.116
            ),

            # Upper hock begins backward.
            (
                x,
                0.515,
                0.690,
                0.114,
                0.105
            ),

            # Hock.
            (
                x,
                0.615,
                0.600,
                0.125,
                0.115
            ),

            # Upper cannon.
            (
                x,
                0.600,
                0.495,
                0.080,
                0.072
            ),

            # Cannon.
            (
                x,
                0.570,
                0.385,
                0.071,
                0.064
            ),

            # Lower cannon.
            (
                x,
                0.540,
                0.285,
                0.069,
                0.062
            ),

            # Fetlock.
            (
                x,
                0.505,
                0.205,
                0.091,
                0.082
            ),

            # Pastern.
            (
                x,
                0.475,
                0.135,
                0.076,
                0.069
            ),
        ]

    def hind_weights(
        prefix
    ):

        return [
            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 1.0
            },

            {
                prefix + ".upper": 0.55,
                prefix + ".lower": 0.45
            },

            {
                prefix + ".upper": 0.25,
                prefix + ".lower": 0.75
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 1.0
            },

            {
                prefix + ".lower": 0.55,
                prefix + ".hoof": 0.45
            },

            {
                prefix + ".hoof": 1.0
            },
        ]

    build_limb_cage(
        "RiverwatchV11HindLeftLeg",
        hind_sections(
            -1
        ),
        hind_weights(
            "hind.L"
        ),
        0.410
    )

    build_limb_cage(
        "RiverwatchV11HindRightLeg",
        hind_sections(
            1
        ),
        hind_weights(
            "hind.R"
        ),
        0.410
    )

    # ========================================================
    # HOOF CONTROL CAGE
    #
    # Four explicit longitudinal slices:
    #
    # pastern connection
    # heel
    # hoof body
    # toe
    #
    # This is closer to box-modeling a hoof than using a
    # sphere or torus.
    # ========================================================

    def build_hoof_cage(
        name,
        x,
        y,
        bone_name,
        width=0.118,
        length=0.235
    ):

        slices = [
            # y offset, top z, bottom z, half width
            (
                0.055,
                0.145,
                0.080,
                width * 0.68
            ),

            (
                0.010,
                0.125,
                0.045,
                width * 0.90
            ),

            (
                -length * 0.32,
                0.110,
                0.030,
                width * 1.05
            ),

            (
                -length * 0.63,
                0.095,
                0.028,
                width * 1.12
            ),

            (
                -length * 0.78,
                0.083,
                0.032,
                width * 0.88
            ),
        ]

        verts = []
        faces = []

        vertices_per_slice = 4

        for (
            y_offset,
            top_z,
            bottom_z,
            half_width
        ) in slices:

            py = (
                y
                + y_offset
            )

            verts.extend(
                [
                    (
                        x - half_width,
                        py,
                        top_z
                    ),

                    (
                        x + half_width,
                        py,
                        top_z
                    ),

                    (
                        x + half_width,
                        py,
                        bottom_z
                    ),

                    (
                        x - half_width,
                        py,
                        bottom_z
                    ),
                ]
            )

        for slice_index in range(
            len(slices) - 1
        ):

            first = (
                slice_index
                * vertices_per_slice
            )

            second = (
                slice_index + 1
            ) * vertices_per_slice

            for vertex_index in range(
                vertices_per_slice
            ):

                next_vertex = (
                    vertex_index + 1
                ) % vertices_per_slice

                faces.append(
                    (
                        first + vertex_index,
                        second + vertex_index,
                        second + next_vertex,
                        first + next_vertex
                    )
                )

        # Heel cap.
        faces.append(
            (
                0,
                3,
                2,
                1
            )
        )

        last = (
            len(slices) - 1
        ) * vertices_per_slice

        # Toe cap.
        faces.append(
            (
                last,
                last + 1,
                last + 2,
                last + 3
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

        apply_bevel(
            obj,
            0.018,
            3
        )

        smooth(
            obj
        )

        rigid_bind(
            obj,
            bone_name
        )

        return obj

    build_hoof_cage(
        "RiverwatchV11FrontLeftHoof",
        -0.285,
        -0.550,
        "front.L.hoof",
        0.115,
        0.225
    )

    build_hoof_cage(
        "RiverwatchV11FrontRightHoof",
        0.285,
        -0.550,
        "front.R.hoof",
        0.115,
        0.225
    )

    build_hoof_cage(
        "RiverwatchV11HindLeftHoof",
        -0.305,
        0.470,
        "hind.L.hoof",
        0.120,
        0.235
    )

    build_hoof_cage(
        "RiverwatchV11HindRightHoof",
        0.305,
        0.470,
        "hind.R.hoof",
        0.120,
        0.235
    )

    # ========================================================
    # EARS
    #
    # Smaller tapered ear cages.
    # ========================================================

    def build_ear(
        name,
        side
    ):

        sx = side

        verts = [
            (
                sx * 0.055,
                -1.060,
                2.005
            ),

            (
                sx * 0.132,
                -1.055,
                2.000
            ),

            (
                sx * 0.110,
                -1.040,
                2.190
            ),

            (
                sx * 0.065,
                -1.005,
                2.005
            ),

            (
                sx * 0.124,
                -1.000,
                2.000
            ),

            (
                sx * 0.106,
                -0.990,
                2.165
            ),
        ]

        faces = [
            (
                0,
                1,
                2
            ),

            (
                5,
                4,
                3
            ),

            (
                0,
                3,
                4,
                1
            ),

            (
                1,
                4,
                5,
                2
            ),

            (
                2,
                5,
                3,
                0
            ),
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

        apply_subdivision(
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

        return obj

    build_ear(
        "RiverwatchV11LeftEar",
        -1
    )

    build_ear(
        "RiverwatchV11RightEar",
        1
    )

    # ========================================================
    # FACE DETAILS
    # ========================================================

    horse_sphere(
        "RiverwatchV11MuzzlePatch",
        (
            0.0,
            -1.700,
            1.655
        ),
        (
            0.118,
            0.074,
            0.053
        ),
        muzzle_mat,
        arm,
        "head",
        20,
        12
    )

    for side in (
        -1,
        1
    ):

        horse_sphere(
            "RiverwatchV11Eye",
            (
                side * 0.185,
                -1.245,
                1.835
            ),
            (
                0.027,
                0.018,
                0.027
            ),
            eye_mat,
            arm,
            "head",
            18,
            12
        )

        horse_sphere(
            "RiverwatchV11Pupil",
            (
                side * 0.203,
                -1.257,
                1.835
            ),
            (
                0.010,
                0.007,
                0.017
            ),
            pupil_mat,
            arm,
            "head",
            14,
            10
        )

        horse_sphere(
            "RiverwatchV11EyeGlint",
            (
                side * 0.212,
                -1.263,
                1.846
            ),
            (
                0.0045,
                0.0035,
                0.0045
            ),
            glint_mat,
            arm,
            "head",
            10,
            8
        )

        horse_sphere(
            "RiverwatchV11Nostril",
            (
                side * 0.075,
                -1.730,
                1.665
            ),
            (
                0.019,
                0.012,
                0.014
            ),
            dark_points,
            arm,
            "head",
            14,
            10
        )

    # Narrow blaze so the head remains easy to read.
    horse_cylinder(
        "RiverwatchV11BlazeUpper",
        (
            0.0,
            -1.115,
            1.925
        ),
        (
            0.0,
            -1.390,
            1.785
        ),
        0.017,
        ivory,
        arm,
        "head",
        0.010
    )

    horse_cylinder(
        "RiverwatchV11BlazeLower",
        (
            0.0,
            -1.390,
            1.785
        ),
        (
            0.0,
            -1.590,
            1.690
        ),
        0.010,
        ivory,
        arm,
        "head",
        0.005
    )

    # ========================================================
    # MANE
    #
    # One coherent ribbon hanging mostly to the left.
    #
    # The root follows the crest.
    # The lower edge is intentionally irregular.
    # ========================================================

    def build_mane():

        stations = [
            # y, root z, tip x, tip z, bone
            (
                -1.060,
                2.050,
                -0.060,
                1.905,
                "head"
            ),

            (
                -1.000,
                2.055,
                -0.080,
                1.875,
                "head"
            ),

            (
                -0.935,
                2.060,
                -0.115,
                1.835,
                "neck"
            ),

            (
                -0.870,
                2.045,
                -0.145,
                1.785,
                "neck"
            ),

            (
                -0.805,
                2.020,
                -0.165,
                1.730,
                "neck"
            ),

            (
                -0.740,
                1.985,
                -0.180,
                1.675,
                "neck"
            ),

            (
                -0.680,
                1.945,
                -0.180,
                1.625,
                "neck"
            ),

            (
                -0.625,
                1.895,
                -0.165,
                1.585,
                "neck"
            ),

            (
                -0.580,
                1.850,
                -0.145,
                1.560,
                "neck"
            ),
        ]

        thickness = 0.018

        verts = []
        faces = []

        for station in stations:

            (
                y,
                root_z,
                tip_x,
                tip_z,
                bone
            ) = station

            verts.extend(
                [
                    (
                        -thickness,
                        y,
                        root_z
                    ),

                    (
                        thickness,
                        y,
                        root_z
                    ),

                    (
                        tip_x - thickness,
                        y + 0.020,
                        tip_z
                    ),

                    (
                        tip_x + thickness,
                        y + 0.020,
                        tip_z
                    ),
                ]
            )

        for index in range(
            len(stations) - 1
        ):

            a = (
                index * 4
            )

            b = (
                index + 1
            ) * 4

            faces.extend(
                [
                    (
                        a,
                        b,
                        b + 2,
                        a + 2
                    ),

                    (
                        a + 1,
                        a + 3,
                        b + 3,
                        b + 1
                    ),

                    (
                        a,
                        a + 1,
                        b + 1,
                        b
                    ),

                    (
                        a + 2,
                        b + 2,
                        b + 3,
                        a + 3
                    ),
                ]
            )

        faces.append(
            (
                0,
                2,
                3,
                1
            )
        )

        last = (
            len(stations) - 1
        ) * 4

        faces.append(
            (
                last,
                last + 1,
                last + 3,
                last + 2
            )
        )

        mesh = bpy.data.meshes.new(
            "RiverwatchV11ManeMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV11Mane",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            mane_mat
        )

        neck_group = obj.vertex_groups.new(
            name="neck"
        )

        head_group = obj.vertex_groups.new(
            name="head"
        )

        for vertex in obj.data.vertices:

            if vertex.co.y <= -0.975:

                head_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            else:

                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

        apply_subdivision(
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

    build_mane()

    # Simple forelock.
    horse_cylinder(
        "RiverwatchV11Forelock",
        (
            0.0,
            -1.080,
            2.055
        ),
        (
            -0.040,
            -1.260,
            1.890
        ),
        0.020,
        mane_mat,
        arm,
        "head",
        0.007
    )

    # ========================================================
    # TAIL CONTROL CAGE
    #
    # Broad at the upper-middle.
    # Narrow root.
    # Natural tapered end.
    # ========================================================

    def build_tail():

        sections = [
            (
                0.000,
                1.040,
                1.495,
                0.055,
                0.048
            ),

            (
                0.000,
                1.100,
                1.445,
                0.070,
                0.058
            ),

            (
                -0.005,
                1.175,
                1.370,
                0.090,
                0.068
            ),

            (
                -0.010,
                1.265,
                1.270,
                0.115,
                0.078
            ),

            (
                0.000,
                1.360,
                1.145,
                0.135,
                0.086
            ),

            (
                0.010,
                1.455,
                1.000,
                0.145,
                0.090
            ),

            (
                0.010,
                1.545,
                0.850,
                0.142,
                0.087
            ),

            (
                0.000,
                1.625,
                0.705,
                0.125,
                0.080
            ),

            (
                -0.010,
                1.690,
                0.575,
                0.100,
                0.070
            ),

            (
                -0.015,
                1.735,
                0.465,
                0.070,
                0.055
            ),

            (
                -0.018,
                1.765,
                0.385,
                0.035,
                0.034
            ),
        ]

        weights = [
            {
                "tail.1": 1.0
            },

            {
                "tail.1": 1.0
            },

            {
                "tail.1": 1.0
            },

            {
                "tail.1": 0.75,
                "tail.2": 0.25
            },

            {
                "tail.1": 0.45,
                "tail.2": 0.55
            },

            {
                "tail.1": 0.20,
                "tail.2": 0.80
            },

            {
                "tail.2": 1.0
            },

            {
                "tail.2": 1.0
            },

            {
                "tail.2": 1.0
            },

            {
                "tail.2": 1.0
            },

            {
                "tail.2": 1.0
            },
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

        rings = 8

        verts = []
        faces = []

        for section_index, section in enumerate(
            sections
        ):

            center = centers[
                section_index
            ]

            lateral, depth = limb_frame(
                centers,
                section_index
            )

            rx = section[3]
            rd = section[4]

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
                        * rx
                    )
                    + depth
                    * (
                        math.sin(angle)
                        * rd
                    )
                )

                verts.append(
                    tuple(point)
                )

        for section_index in range(
            len(sections) - 1
        ):

            first = (
                section_index * rings
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

        mesh = bpy.data.meshes.new(
            "RiverwatchV11TailMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV11Tail",
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
            weights
        ):

            section_vertices = list(
                range(
                    section_index * rings,
                    section_index * rings + rings
                )
            )

            for group_name, weight in weight_map.items():

                if group_name == "tail.1":

                    tail1.add(
                        section_vertices,
                        weight,
                        "REPLACE"
                    )

                else:

                    tail2.add(
                        section_vertices,
                        weight,
                        "REPLACE"
                    )

        apply_subdivision(
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
    # V11 METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "anatomy_control_cage_v11"

    arm[
        "broken_knight_horse_modeling_method"
    ] = "hand_authored_low_poly_control_cage"

    arm[
        "broken_knight_horse_body"
    ] = "explicit_anatomical_cage"

    arm[
        "broken_knight_horse_head"
    ] = "explicit_skull_jaw_muzzle_cage"

    arm[
        "broken_knight_horse_legs"
    ] = "eight_sided_joint_control_cages"

    arm[
        "broken_knight_horse_hooves"
    ] = "manual_longitudinal_control_cage"

    arm[
        "broken_knight_horse_tack"
    ] = "removed_for_anatomy_review"

    arm[
        "broken_knight_horse_reference_goal"
    ] = "clean_stocky_fantasy_riding_horse"

    arm[
        "broken_knight_horse_voxel_remesh"
    ] = False

    arm[
        "broken_knight_horse_procedural_body_tube"
    ] = False



def build_horse_model_v12_base(arm):
    # ========================================================
    # BROKEN KNIGHT HORSE V12
    #
    # MAJOR PROPORTION RESCUE
    #
    # V11 topology is retained, but its proportions are
    # aggressively sculpted after creation.
    #
    # The goal is NOT subtle:
    #
    # wider croup
    # fuller rump
    # broad shoulder
    # deeper chest
    # substantial barrel
    # visible flank tuck
    # shorter neck
    # much shorter head
    # fuller cheek
    # tapered muzzle
    # thicker upper legs
    # slim lower cannons
    # larger hooves
    # fuller mane
    # fuller tail
    # ========================================================

    build_horse_model_v11_base(arm)

    def gauss(value, center, spread):
        return math.exp(
            -((value - center) / spread) ** 2
        )

    def clamp01(value):
        return max(
            0.0,
            min(
                1.0,
                value
            )
        )

    def compress_front(y):
        # Head is shortened strongly.
        if y < -1.04:
            return -1.04 + (y + 1.04) * 0.70

        # Neck is shortened moderately.
        if y < -0.58:
            return -0.58 + (y + 0.58) * 0.84

        return y

    # ========================================================
    # BODY
    # ========================================================

    core = bpy.data.objects.get(
        "RiverwatchV11AnatomyControlCage"
    )

    if core is None:
        raise RuntimeError(
            "V12 could not locate V11 anatomy cage"
        )

    for vertex in core.data.vertices:

        x = vertex.co.x
        y = vertex.co.y
        z = vertex.co.z

        croup = gauss(
            y,
            0.72,
            0.34
        )

        loin = gauss(
            y,
            0.40,
            0.33
        )

        barrel = gauss(
            y,
            0.05,
            0.43
        )

        chest = gauss(
            y,
            -0.27,
            0.22
        )

        shoulder = gauss(
            y,
            -0.43,
            0.20
        )

        withers = gauss(
            y,
            -0.57,
            0.15
        )

        neck = gauss(
            y,
            -0.82,
            0.26
        )

        cheek = gauss(
            y,
            -1.27,
            0.18
        )

        muzzle = gauss(
            y,
            -1.60,
            0.17
        )

        # ----------------------------------------------------
        # WIDTH
        # ----------------------------------------------------

        width = 1.0

        width += 0.205 * croup
        width += 0.105 * loin
        width += 0.105 * barrel
        width += 0.155 * chest
        width += 0.165 * shoulder

        # Slim neck.
        width -= 0.105 * neck

        # Full cheek / jaw.
        if (
            y < -1.08
            and y > -1.46
            and z < 1.86
        ):
            width += 0.105 * cheek

        # Taper muzzle.
        if y < -1.43:
            width -= 0.175 * muzzle

        vertex.co.x = x * width

        # ----------------------------------------------------
        # ROUND RUMP
        # ----------------------------------------------------

        if y > 0.36:

            upper = clamp01(
                (z - 1.30) / 0.50
            )

            vertex.co.z += (
                0.105
                * croup
                * upper
            )

        # Lower quarter gets more mass.
        if (
            y > 0.45
            and z > 1.05
            and z < 1.42
        ):
            vertex.co.x *= (
                1.0
                + 0.085 * croup
            )

        # ----------------------------------------------------
        # BELLY / FLANK
        # ----------------------------------------------------

        flank = gauss(
            y,
            0.30,
            0.21
        )

        if z < 1.22:
            vertex.co.z += (
                0.110
                * flank
            )

        # ----------------------------------------------------
        # DEEP CHEST
        # ----------------------------------------------------

        if (
            y < -0.10
            and y > -0.50
            and z < 1.32
        ):
            vertex.co.z -= (
                0.045
                * chest
            )

        # ----------------------------------------------------
        # SHOULDER MASS
        # ----------------------------------------------------

        if (
            z > 1.22
            and z < 1.72
        ):
            vertex.co.x *= (
                1.0
                + 0.060 * shoulder
            )

        # ----------------------------------------------------
        # REDUCE POINTY WITHERS
        # ----------------------------------------------------

        if (
            z > 1.82
            and y > -0.68
            and y < -0.42
        ):
            vertex.co.z -= (
                0.065
                * withers
            )

        # ----------------------------------------------------
        # NECK SILHOUETTE
        # ----------------------------------------------------

        if (
            y < -0.60
            and y > -1.05
        ):

            if z > 1.89:
                vertex.co.z -= (
                    0.060
                    * neck
                )

            if z < 1.62:
                vertex.co.z += (
                    0.035
                    * neck
                )

        # ----------------------------------------------------
        # HORSE HEAD ANGLE
        # ----------------------------------------------------

        if y < -1.12:

            progress = clamp01(
                (-y - 1.12) / 0.62
            )

            vertex.co.z -= (
                0.050
                * progress
            )

        # ----------------------------------------------------
        # SHORTER FRONT END
        # ----------------------------------------------------

        vertex.co.y = compress_front(
            y
        )

    # ========================================================
    # LEGS
    # ========================================================

    def reshape_leg(
        name,
        center_x,
        center_y,
        hind=False
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        for vertex in obj.data.vertices:

            z = vertex.co.z

            if z > 0.90:
                x_scale = 1.18 if hind else 1.15
                depth_scale = 1.14 if hind else 1.11

            elif z > 0.58:
                x_scale = 1.13
                depth_scale = 1.11

            elif z > 0.25:
                x_scale = 1.055
                depth_scale = 1.050

            else:
                x_scale = 1.075
                depth_scale = 1.070

            vertex.co.x = (
                center_x
                + (
                    vertex.co.x
                    - center_x
                )
                * x_scale
            )

            vertex.co.y = (
                center_y
                + (
                    vertex.co.y
                    - center_y
                )
                * depth_scale
            )

            if hind:

                # Forward stifle.
                if (
                    z > 0.82
                    and z < 1.00
                ):
                    vertex.co.y -= 0.055

                # Hock backward.
                if (
                    z > 0.52
                    and z < 0.68
                ):
                    vertex.co.y += 0.075

                # Cannon comes back underneath.
                if (
                    z > 0.25
                    and z < 0.48
                ):
                    vertex.co.y -= 0.025

            else:

                # A little more knee definition.
                if (
                    z > 0.57
                    and z < 0.70
                ):
                    vertex.co.y += 0.018

    reshape_leg(
        "RiverwatchV11FrontLeftLeg",
        -0.285,
        -0.485,
        False
    )

    reshape_leg(
        "RiverwatchV11FrontRightLeg",
        0.285,
        -0.485,
        False
    )

    reshape_leg(
        "RiverwatchV11HindLeftLeg",
        -0.305,
        0.515,
        True
    )

    reshape_leg(
        "RiverwatchV11HindRightLeg",
        0.305,
        0.515,
        True
    )

    # ========================================================
    # HOOF RESHAPE
    # ========================================================

    def reshape_hoof(
        name,
        center_x,
        center_y
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        for vertex in obj.data.vertices:

            vertex.co.x = (
                center_x
                + (
                    vertex.co.x
                    - center_x
                )
                * 1.16
            )

            vertex.co.y = (
                center_y
                + (
                    vertex.co.y
                    - center_y
                )
                * 1.18
            )

            vertex.co.z = (
                0.028
                + (
                    vertex.co.z
                    - 0.028
                )
                * 0.91
            )

    reshape_hoof(
        "RiverwatchV11FrontLeftHoof",
        -0.285,
        -0.550
    )

    reshape_hoof(
        "RiverwatchV11FrontRightHoof",
        0.285,
        -0.550
    )

    reshape_hoof(
        "RiverwatchV11HindLeftHoof",
        -0.305,
        0.470
    )

    reshape_hoof(
        "RiverwatchV11HindRightHoof",
        0.305,
        0.470
    )

    # ========================================================
    # MANE
    # ========================================================

    mane = bpy.data.objects.get(
        "RiverwatchV11Mane"
    )

    if mane is not None:

        for vertex in mane.data.vertices:

            vertex.co.y = compress_front(
                vertex.co.y
            )

            if vertex.co.x < -0.025:
                vertex.co.x *= 1.60

            elif vertex.co.x > 0.025:
                vertex.co.x *= 1.20

            if (
                vertex.co.z < 1.82
                and vertex.co.y > -0.95
            ):
                vertex.co.z -= 0.065

    # ========================================================
    # TAIL
    # ========================================================

    tail = bpy.data.objects.get(
        "RiverwatchV11Tail"
    )

    if tail is not None:

        for vertex in tail.data.vertices:

            vertex.co.x *= 1.45

            if vertex.co.z < 1.25:

                factor = clamp01(
                    (1.25 - vertex.co.z) / 0.85
                )

                vertex.co.y += (
                    0.090
                    * factor
                )

    # ========================================================
    # EARS
    # ========================================================

    for name in (
        "RiverwatchV11LeftEar",
        "RiverwatchV11RightEar",
    ):

        ear = bpy.data.objects.get(
            name
        )

        if ear is None:
            continue

        for vertex in ear.data.vertices:

            vertex.co.y = compress_front(
                vertex.co.y
            )

            if vertex.co.z > 2.00:

                vertex.co.z = (
                    2.00
                    + (
                        vertex.co.z
                        - 2.00
                    )
                    * 0.68
                )

    # ========================================================
    # FACE DETAILS
    # ========================================================

    movable_prefixes = (
        "RiverwatchV11MuzzlePatch",
        "RiverwatchV11Eye",
        "RiverwatchV11Pupil",
        "RiverwatchV11EyeGlint",
        "RiverwatchV11Nostril",
        "RiverwatchV11Forelock",
    )

    for obj in bpy.context.scene.objects:

        should_move = any(
            obj.name.startswith(prefix)
            for prefix in movable_prefixes
        )

        if not should_move:
            continue

        old_y = obj.location.y

        obj.location.y = compress_front(
            old_y
        )

        if old_y < -1.15:

            progress = clamp01(
                (-old_y - 1.15) / 0.55
            )

            obj.location.z -= (
                0.035
                * progress
            )

    # Remove the old long blaze cylinders for this anatomy pass.
    # They distort the visual read of the shortened head.

    for name in (
        "RiverwatchV11BlazeUpper",
        "RiverwatchV11BlazeLower",
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is not None:

            bpy.data.objects.remove(
                obj,
                do_unlink=True
            )

    # ========================================================
    # MATERIAL / OBJECT VERSION NAMES
    # ========================================================

    for mat in bpy.data.materials:

        if mat.name.startswith(
            "Riverwatch V11"
        ):

            mat.name = mat.name.replace(
                "Riverwatch V11",
                "Riverwatch V12",
                1
            )

    for obj in bpy.context.scene.objects:

        if obj.name.startswith(
            "RiverwatchV11"
        ):

            obj.name = obj.name.replace(
                "RiverwatchV11",
                "RiverwatchV12",
                1
            )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "major_proportion_rescue_v12"

    arm[
        "broken_knight_horse_body"
    ] = "wider_rounder_stocky_body"

    arm[
        "broken_knight_horse_rump"
    ] = "full_round_croup"

    arm[
        "broken_knight_horse_head"
    ] = "shorter_tapered_head"

    arm[
        "broken_knight_horse_legs"
    ] = "muscular_upper_slim_cannon"

    arm[
        "broken_knight_horse_animation_acceptance"
    ] = "ignored_for_anatomy_pass"



def build_horse_model_v13_base(arm):
    # ========================================================
    # BROKEN KNIGHT HORSE V13
    #
    # SILHOUETTE BALANCE PASS
    #
    # V12 successfully made a substantial visible change,
    # but width expanded too aggressively.
    #
    # V13 focuses on SHAPE rather than raw bulk:
    #
    # - reduce excessive overall width
    # - preserve powerful croup
    # - round rump vertically rather than sideways
    # - cleaner topline
    # - deeper rib cage
    # - natural flank tuck
    # - stronger chest
    # - clear neck/body transition
    # - curved neck crest / throat relationship
    # - more downward horse-like head angle
    # - smaller tapered muzzle
    # - defined cheek and jaw
    # - better hind leg S curve
    # - mane hangs DOWN rather than sticking sideways
    # - tail hangs with more vertical weight
    # ========================================================

    build_horse_model_v12_base(
        arm
    )

    def gauss(
        value,
        center,
        spread
    ):
        return math.exp(
            -((value - center) / spread) ** 2
        )

    def clamp01(value):
        return max(
            0.0,
            min(
                1.0,
                value
            )
        )

    def rotate_head_point(
        y,
        z,
        angle=math.radians(8.5)
    ):
        # Pivot near the poll.
        pivot_y = -0.995
        pivot_z = 1.825

        dy = y - pivot_y
        dz = z - pivot_z

        cosine = math.cos(
            angle
        )

        sine = math.sin(
            angle
        )

        new_y = (
            pivot_y
            + dy * cosine
            - dz * sine
        )

        new_z = (
            pivot_z
            + dy * sine
            + dz * cosine
        )

        return (
            new_y,
            new_z
        )

    # ========================================================
    # MAIN BODY
    # ========================================================

    core = bpy.data.objects.get(
        "RiverwatchV12AnatomyControlCage"
    )

    if core is None:
        raise RuntimeError(
            "V13 could not locate the V12 anatomy mesh"
        )

    for vertex in core.data.vertices:

        x = vertex.co.x
        y = vertex.co.y
        z = vertex.co.z

        croup = gauss(
            y,
            0.67,
            0.34
        )

        loin = gauss(
            y,
            0.36,
            0.31
        )

        barrel = gauss(
            y,
            0.03,
            0.40
        )

        flank = gauss(
            y,
            0.29,
            0.21
        )

        chest = gauss(
            y,
            -0.25,
            0.22
        )

        shoulder = gauss(
            y,
            -0.42,
            0.20
        )

        withers = gauss(
            y,
            -0.56,
            0.16
        )

        neck = gauss(
            y,
            -0.78,
            0.25
        )

        poll = gauss(
            y,
            -1.00,
            0.16
        )

        cheek = gauss(
            y,
            -1.22,
            0.16
        )

        muzzle = gauss(
            y,
            -1.43,
            0.16
        )

        # ----------------------------------------------------
        # CONTROL V12 WIDTH OVERCORRECTION
        # ----------------------------------------------------

        scale_x = 1.0

        # Bring torso width back toward believable.
        scale_x -= 0.045 * croup
        scale_x -= 0.065 * loin
        scale_x -= 0.070 * barrel
        scale_x -= 0.055 * chest
        scale_x -= 0.040 * shoulder

        # Neck gets slimmer.
        scale_x -= 0.065 * neck

        # Cheek remains strong.
        if (
            y < -1.05
            and y > -1.38
            and z < 1.84
        ):
            scale_x += (
                0.035
                * cheek
            )

        # Muzzle becomes clearly smaller than jaw.
        if y < -1.30:
            scale_x -= (
                0.085
                * muzzle
            )

        vertex.co.x *= scale_x

        # ====================================================
        # RUMP / CROUP
        # ====================================================

        if y > 0.34:

            # V12 got wide; V13 makes the croup round through
            # height instead.

            if z > 1.68:

                vertex.co.z -= (
                    0.035
                    * croup
                )

            elif (
                z > 1.35
                and z <= 1.68
            ):

                vertex.co.z += (
                    0.028
                    * croup
                )

            elif (
                z > 1.12
                and z <= 1.35
            ):

                vertex.co.x *= (
                    1.0
                    + 0.020 * croup
                )

        # ====================================================
        # TOPLINE
        # ====================================================

        # Smooth overly humped loin.
        if (
            y > 0.12
            and y < 0.48
            and z > 1.70
        ):

            vertex.co.z -= (
                0.030
                * loin
            )

        # Slight lift behind withers keeps the back from
        # collapsing visually.
        if (
            y < -0.05
            and y > -0.32
            and z > 1.67
        ):

            vertex.co.z += (
                0.015
                * barrel
            )

        # ====================================================
        # RIB CAGE
        # ====================================================

        # Add depth instead of simply adding width.
        if (
            y > -0.15
            and y < 0.28
            and z < 1.27
        ):

            vertex.co.z -= (
                0.045
                * barrel
            )

        # ====================================================
        # FLANK TUCK
        # ====================================================

        if (
            y > 0.17
            and y < 0.48
            and z < 1.18
        ):

            vertex.co.z += (
                0.030
                * flank
            )

        # ====================================================
        # CHEST
        # ====================================================

        if (
            y > -0.46
            and y < -0.10
            and z < 1.28
        ):

            vertex.co.z -= (
                0.035
                * chest
            )

        # Fuller lower front chest.
        if (
            y > -0.43
            and y < -0.18
            and z > 1.18
            and z < 1.48
        ):

            vertex.co.x *= (
                1.0
                + 0.025 * chest
            )

        # ====================================================
        # SHOULDER
        # ====================================================

        # Pull upper shoulder slightly back into torso,
        # avoiding a round front-end blob.

        if (
            y > -0.56
            and y < -0.26
            and z > 1.42
            and z < 1.73
        ):

            vertex.co.y += (
                0.025
                * shoulder
            )

        # ====================================================
        # WITHERS
        # ====================================================

        if (
            z > 1.79
            and y > -0.66
            and y < -0.45
        ):

            vertex.co.z -= (
                0.025
                * withers
            )

        # ====================================================
        # NECK S CURVE
        # ====================================================

        if (
            y < -0.56
            and y > -1.03
        ):

            # Upper crest moves slightly toward head.
            if z > 1.78:

                vertex.co.y -= (
                    0.035
                    * neck
                )

                vertex.co.z += (
                    0.020
                    * neck
                )

            # Throat returns toward chest.
            if z < 1.63:

                vertex.co.y += (
                    0.035
                    * neck
                )

                vertex.co.z += (
                    0.010
                    * neck
                )

        # Narrow poll.
        if (
            y < -0.90
            and y > -1.08
        ):

            vertex.co.x *= (
                1.0
                - 0.030 * poll
            )

        # ====================================================
        # HEAD ROTATION
        # ====================================================

        if y < -1.00:

            new_y, new_z = rotate_head_point(
                vertex.co.y,
                vertex.co.z
            )

            vertex.co.y = new_y
            vertex.co.z = new_z

        # ====================================================
        # CHEEK / JAW
        # ====================================================

        if (
            vertex.co.y < -1.08
            and vertex.co.y > -1.34
            and vertex.co.z < 1.78
        ):

            vertex.co.z -= (
                0.018
                * cheek
            )

            vertex.co.x *= (
                1.0
                + 0.020 * cheek
            )

        # ====================================================
        # MUZZLE TAPER
        # ====================================================

        if vertex.co.y < -1.30:

            amount = clamp01(
                (
                    -vertex.co.y
                    - 1.30
                )
                / 0.35
            )

            vertex.co.x *= (
                1.0
                - 0.080 * amount
            )

            vertex.co.z = (
                1.62
                + (
                    vertex.co.z
                    - 1.62
                )
                * (
                    1.0
                    - 0.035 * amount
                )
            )

    # ========================================================
    # LEGS
    # ========================================================

    def refine_front_leg(
        name,
        center_x
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        center_y = -0.485

        for vertex in obj.data.vertices:

            z = vertex.co.z

            # V12 upper legs were deliberately enlarged.
            # Pull them back just enough to read as anatomy.

            if z > 0.88:

                sx = 0.955
                sy = 0.965

            elif z > 0.58:

                sx = 0.970
                sy = 0.975

            elif z > 0.26:

                sx = 0.980
                sy = 0.985

            else:

                sx = 0.985
                sy = 0.990

            vertex.co.x = (
                center_x
                + (
                    vertex.co.x
                    - center_x
                )
                * sx
            )

            vertex.co.y = (
                center_y
                + (
                    vertex.co.y
                    - center_y
                )
                * sy
            )

            # Straighten cannon.
            if (
                z > 0.26
                and z < 0.53
            ):

                vertex.co.y = (
                    center_y
                    + (
                        vertex.co.y
                        - center_y
                    )
                    * 0.96
                )

    def refine_hind_leg(
        name,
        center_x
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        center_y = 0.515

        for vertex in obj.data.vertices:

            z = vertex.co.z

            # Thigh remains muscular.
            if z > 0.90:

                sx = 0.975
                sy = 0.980

            elif z > 0.67:

                sx = 0.970
                sy = 0.975

            else:

                sx = 0.980
                sy = 0.985

            vertex.co.x = (
                center_x
                + (
                    vertex.co.x
                    - center_x
                )
                * sx
            )

            vertex.co.y = (
                center_y
                + (
                    vertex.co.y
                    - center_y
                )
                * sy
            )

            # Stronger stifle-forward shape.
            if (
                z > 0.82
                and z < 1.00
            ):

                vertex.co.y -= 0.028

            # Hock projects rearward.
            if (
                z > 0.52
                and z < 0.69
            ):

                vertex.co.y += 0.038

            # Cannon returns beneath hock.
            if (
                z > 0.26
                and z < 0.49
            ):

                vertex.co.y -= 0.020

    refine_front_leg(
        "RiverwatchV12FrontLeftLeg",
        -0.285
    )

    refine_front_leg(
        "RiverwatchV12FrontRightLeg",
        0.285
    )

    refine_hind_leg(
        "RiverwatchV12HindLeftLeg",
        -0.305
    )

    refine_hind_leg(
        "RiverwatchV12HindRightLeg",
        0.305
    )

    # ========================================================
    # HOOF BALANCE
    # ========================================================

    for name, center_x, center_y in (
        (
            "RiverwatchV12FrontLeftHoof",
            -0.285,
            -0.550
        ),
        (
            "RiverwatchV12FrontRightHoof",
            0.285,
            -0.550
        ),
        (
            "RiverwatchV12HindLeftHoof",
            -0.305,
            0.470
        ),
        (
            "RiverwatchV12HindRightHoof",
            0.305,
            0.470
        ),
    ):

        hoof = bpy.data.objects.get(
            name
        )

        if hoof is None:
            continue

        for vertex in hoof.data.vertices:

            # V12 hooves were enlarged.
            # Preserve size but make them less paddle-like.

            vertex.co.x = (
                center_x
                + (
                    vertex.co.x
                    - center_x
                )
                * 0.94
            )

            vertex.co.y = (
                center_y
                + (
                    vertex.co.y
                    - center_y
                )
                * 1.03
            )

    # ========================================================
    # MANE
    # ========================================================

    mane = bpy.data.objects.get(
        "RiverwatchV12Mane"
    )

    if mane is not None:

        for vertex in mane.data.vertices:

            # V12 spread the mane sideways.
            # V13 makes it hang downward instead.

            vertex.co.x *= 0.73

            if vertex.co.z < 1.90:

                drop = clamp01(
                    (
                        1.90
                        - vertex.co.z
                    )
                    / 0.45
                )

                vertex.co.z -= (
                    0.075
                    * drop
                )

            # Front mane follows new head angle.
            if vertex.co.y < -1.00:

                new_y, new_z = rotate_head_point(
                    vertex.co.y,
                    vertex.co.z
                )

                vertex.co.y = new_y
                vertex.co.z = new_z

    # ========================================================
    # TAIL
    # ========================================================

    tail = bpy.data.objects.get(
        "RiverwatchV12Tail"
    )

    if tail is not None:

        for vertex in tail.data.vertices:

            # Less sideways width, more hanging hair mass.
            vertex.co.x *= 0.82

            if vertex.co.z < 1.22:

                amount = clamp01(
                    (
                        1.22
                        - vertex.co.z
                    )
                    / 0.86
                )

                vertex.co.z -= (
                    0.055
                    * amount
                )

                vertex.co.y += (
                    0.025
                    * amount
                )

    # ========================================================
    # EARS
    # ========================================================

    for name in (
        "RiverwatchV12LeftEar",
        "RiverwatchV12RightEar",
    ):

        ear = bpy.data.objects.get(
            name
        )

        if ear is None:
            continue

        for vertex in ear.data.vertices:

            # Pull ears slightly closer to center.
            vertex.co.x *= 0.90

            new_y, new_z = rotate_head_point(
                vertex.co.y,
                vertex.co.z
            )

            vertex.co.y = new_y
            vertex.co.z = new_z

    # ========================================================
    # FACE DETAILS FOLLOW HEAD
    # ========================================================

    face_prefixes = (
        "RiverwatchV12MuzzlePatch",
        "RiverwatchV12Eye",
        "RiverwatchV12Pupil",
        "RiverwatchV12EyeGlint",
        "RiverwatchV12Nostril",
        "RiverwatchV12Forelock",
    )

    for obj in bpy.context.scene.objects:

        if not any(
            obj.name.startswith(prefix)
            for prefix in face_prefixes
        ):
            continue

        new_y, new_z = rotate_head_point(
            obj.location.y,
            obj.location.z
        )

        obj.location.y = new_y
        obj.location.z = new_z

    # ========================================================
    # MATERIAL TONE
    # ========================================================

    for mat in bpy.data.materials:

        if mat.name == "Riverwatch V12 Warm Bay":

            mat.diffuse_color = (
                0.285,
                0.075,
                0.020,
                1.0
            )

            if mat.use_nodes:

                bsdf = mat.node_tree.nodes.get(
                    "Principled BSDF"
                )

                if bsdf:

                    bsdf.inputs[
                        "Base Color"
                    ].default_value = (
                        0.285,
                        0.075,
                        0.020,
                        1.0
                    )

                    bsdf.inputs[
                        "Roughness"
                    ].default_value = 0.60

    # ========================================================
    # VERSION NAMES
    # ========================================================

    for mat in bpy.data.materials:

        if mat.name.startswith(
            "Riverwatch V12"
        ):

            mat.name = mat.name.replace(
                "Riverwatch V12",
                "Riverwatch V13",
                1
            )

    for obj in bpy.context.scene.objects:

        if obj.name.startswith(
            "RiverwatchV12"
        ):

            obj.name = obj.name.replace(
                "RiverwatchV12",
                "RiverwatchV13",
                1
            )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "silhouette_balance_v13"

    arm[
        "broken_knight_horse_v13_goal"
    ] = "reference_silhouette_over_raw_width"

    arm[
        "broken_knight_horse_v13_rump"
    ] = "round_vertical_croup"

    arm[
        "broken_knight_horse_v13_neck"
    ] = "defined_s_curve"

    arm[
        "broken_knight_horse_v13_head"
    ] = "angled_down_tapered_muzzle"

    arm[
        "broken_knight_horse_v13_mane"
    ] = "vertical_hanging_mass"

    arm[
        "broken_knight_horse_v13_tail"
    ] = "vertical_weighted_mass"



def build_horse_model(arm):
    # ========================================================
    # BROKEN KNIGHT HORSE V14
    #
    # ANATOMICAL DEFINITION
    #
    # V12 fixed bulk.
    # V13 fixed balance.
    #
    # V14 concentrates on recognizable horse anatomy:
    #
    # HEAD
    #   forehead
    #   cheek
    #   jaw
    #   throat latch
    #   nasal bridge
    #   muzzle
    #
    # BODY
    #   shoulder
    #   rib cage
    #   loin
    #   rounded croup
    #
    # LEGS
    #   forearm
    #   knee
    #   cannon
    #   fetlock
    #   pastern
    #   thigh
    #   stifle
    #   gaskin
    #   hock
    #
    # HOOF
    #   narrow heel
    #   broader toe
    #   lower profile
    #
    # This is deliberately a definition pass rather than
    # another global proportion swing.
    # ========================================================

    build_horse_model_v13_base(
        arm
    )

    def gauss(
        value,
        center,
        spread
    ):
        return math.exp(
            -((value - center) / spread) ** 2
        )

    def clamp01(value):

        return max(
            0.0,
            min(
                1.0,
                value
            )
        )

    # ========================================================
    # MAIN ANATOMY
    # ========================================================

    core = bpy.data.objects.get(
        "RiverwatchV13AnatomyControlCage"
    )

    if core is None:
        raise RuntimeError(
            "V14 could not locate V13 anatomy mesh"
        )

    for vertex in core.data.vertices:

        x = vertex.co.x
        y = vertex.co.y
        z = vertex.co.z

        croup = gauss(
            y,
            0.66,
            0.29
        )

        loin = gauss(
            y,
            0.34,
            0.25
        )

        barrel = gauss(
            y,
            0.02,
            0.34
        )

        chest = gauss(
            y,
            -0.27,
            0.19
        )

        shoulder = gauss(
            y,
            -0.43,
            0.16
        )

        neck = gauss(
            y,
            -0.79,
            0.22
        )

        poll = gauss(
            y,
            -1.01,
            0.12
        )

        cheek = gauss(
            y,
            -1.20,
            0.14
        )

        jaw = gauss(
            y,
            -1.26,
            0.16
        )

        muzzle = gauss(
            y,
            -1.43,
            0.14
        )

        # ----------------------------------------------------
        # KEEP BODY FROM GETTING TOO WIDE AGAIN
        # ----------------------------------------------------

        if (
            y > -0.30
            and y < 0.42
        ):

            vertex.co.x *= (
                1.0
                - 0.018 * barrel
            )

        # ----------------------------------------------------
        # CROUP
        #
        # Build a rounded slope from loin into rump rather
        # than a square or flat rear.
        # ----------------------------------------------------

        if (
            y > 0.40
            and z > 1.40
        ):

            rear_amount = clamp01(
                (
                    y - 0.40
                )
                / 0.48
            )

            vertex.co.z -= (
                0.020
                * rear_amount
            )

        if (
            y > 0.48
            and z > 1.24
            and z < 1.58
        ):

            vertex.co.x *= (
                1.0
                + 0.020 * croup
            )

        # Lower rump rounds inward near the tail root.
        if (
            y > 0.78
            and z < 1.42
        ):

            vertex.co.x *= 0.975

        # ----------------------------------------------------
        # LOIN
        # ----------------------------------------------------

        if (
            y > 0.12
            and y < 0.48
            and z > 1.66
        ):

            vertex.co.z -= (
                0.018
                * loin
            )

        # ----------------------------------------------------
        # RIB CAGE DEPTH
        # ----------------------------------------------------

        if (
            y > -0.14
            and y < 0.24
            and z < 1.26
        ):

            vertex.co.z -= (
                0.025
                * barrel
            )

        # ----------------------------------------------------
        # FLANK
        #
        # More recognizable rising underline behind ribs.
        # ----------------------------------------------------

        if (
            y > 0.22
            and y < 0.49
            and z < 1.22
        ):

            tuck = gauss(
                y,
                0.34,
                0.16
            )

            vertex.co.z += (
                0.035
                * tuck
            )

        # ----------------------------------------------------
        # CHEST
        # ----------------------------------------------------

        if (
            y > -0.43
            and y < -0.12
            and z < 1.31
        ):

            vertex.co.z -= (
                0.028
                * chest
            )

        # ----------------------------------------------------
        # SHOULDER BLADE SHAPE
        # ----------------------------------------------------

        if (
            y > -0.53
            and y < -0.28
            and z > 1.34
            and z < 1.70
        ):

            upper = clamp01(
                (
                    z - 1.34
                )
                / 0.36
            )

            # Upper shoulder lays backward.
            vertex.co.y += (
                0.028
                * upper
                * shoulder
            )

            vertex.co.x *= (
                1.0
                + 0.018
                * shoulder
            )

        # ====================================================
        # NECK
        # ====================================================

        if (
            y < -0.58
            and y > -1.01
        ):

            # Crest.
            if z > 1.76:

                crest = clamp01(
                    (
                        z - 1.76
                    )
                    / 0.27
                )

                vertex.co.z += (
                    0.018
                    * crest
                    * neck
                )

                vertex.co.y -= (
                    0.018
                    * crest
                    * neck
                )

            # Throat.
            if z < 1.64:

                throat = clamp01(
                    (
                        1.64
                        - z
                    )
                    / 0.25
                )

                vertex.co.y += (
                    0.032
                    * throat
                    * neck
                )

                vertex.co.x *= (
                    1.0
                    - 0.030
                    * throat
                    * neck
                )

        # ----------------------------------------------------
        # THROATLATCH
        #
        # Narrow just behind jaw.
        # ----------------------------------------------------

        if (
            y < -0.94
            and y > -1.10
            and z < 1.72
        ):

            vertex.co.x *= (
                1.0
                - 0.055 * poll
            )

            vertex.co.y += (
                0.020 * poll
            )

        # ====================================================
        # SKULL
        # ====================================================

        # Forehead / poll width retained.
        if (
            y < -1.01
            and y > -1.17
            and z > 1.76
        ):

            vertex.co.x *= (
                1.0
                + 0.018 * cheek
            )

        # Cheek bone becomes fuller.
        if (
            y < -1.10
            and y > -1.30
            and z > 1.64
            and z < 1.80
        ):

            vertex.co.x *= (
                1.0
                + 0.055 * cheek
            )

        # ----------------------------------------------------
        # JAW
        # ----------------------------------------------------

        if (
            y < -1.08
            and y > -1.34
            and z < 1.70
        ):

            vertex.co.z -= (
                0.030 * jaw
            )

            vertex.co.x *= (
                1.0
                + 0.035 * jaw
            )

        # ====================================================
        # NASAL BRIDGE
        # ====================================================

        if (
            y < -1.25
            and y > -1.43
            and z > 1.64
        ):

            bridge = clamp01(
                (
                    -y
                    - 1.25
                )
                / 0.18
            )

            vertex.co.x *= (
                1.0
                - 0.045 * bridge
            )

        # ====================================================
        # MUZZLE
        # ====================================================

        if y < -1.34:

            amount = clamp01(
                (
                    -y
                    - 1.34
                )
                / 0.28
            )

            # Shorter nose.
            vertex.co.y += (
                0.035
                * amount
            )

            # Noticeably narrower.
            vertex.co.x *= (
                1.0
                - 0.060
                * amount
            )

            # Slightly deeper at nostril end.
            if z < 1.69:

                vertex.co.z -= (
                    0.012
                    * amount
                )

        # ====================================================
        # HEAD ANGLE
        #
        # A small additional downward rotation.
        # ====================================================

        if y < -1.02:

            pivot_y = -1.01
            pivot_z = 1.82

            angle = math.radians(
                3.5
            )

            dy = vertex.co.y - pivot_y
            dz = vertex.co.z - pivot_z

            cosine = math.cos(
                angle
            )

            sine = math.sin(
                angle
            )

            vertex.co.y = (
                pivot_y
                + dy * cosine
                - dz * sine
            )

            vertex.co.z = (
                pivot_z
                + dy * sine
                + dz * cosine
            )

    # ========================================================
    # LEG HELPERS
    # ========================================================

    def scale_around(
        vertex,
        center_x,
        center_y,
        scale_x,
        scale_y
    ):

        vertex.co.x = (
            center_x
            + (
                vertex.co.x
                - center_x
            )
            * scale_x
        )

        vertex.co.y = (
            center_y
            + (
                vertex.co.y
                - center_y
            )
            * scale_y
        )

    # ========================================================
    # FRONT LEGS
    # ========================================================

    def refine_front(
        name,
        center_x
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        center_y = -0.485

        for vertex in obj.data.vertices:

            z = vertex.co.z

            # Forearm muscle.
            if z > 0.76:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.045,
                    1.070
                )

            # Knee.
            elif z > 0.56:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.055,
                    1.070
                )

                vertex.co.y += 0.012

            # Cannon.
            elif z > 0.27:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    0.955,
                    0.970
                )

            # Fetlock / pastern.
            else:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.035,
                    1.025
                )

            # Create a straighter cannon line.
            if (
                z > 0.29
                and z < 0.52
            ):

                vertex.co.y = (
                    center_y
                    + (
                        vertex.co.y
                        - center_y
                    )
                    * 0.94
                )

    refine_front(
        "RiverwatchV13FrontLeftLeg",
        -0.285
    )

    refine_front(
        "RiverwatchV13FrontRightLeg",
        0.285
    )

    # ========================================================
    # HIND LEGS
    # ========================================================

    def refine_hind(
        name,
        center_x
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        center_y = 0.515

        for vertex in obj.data.vertices:

            z = vertex.co.z

            # Thigh.
            if z > 0.91:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.055,
                    1.095
                )

            # Gaskin / stifle.
            elif z > 0.68:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.035,
                    1.060
                )

                # Stifle forward.
                vertex.co.y -= 0.018

            # Hock.
            elif z > 0.51:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.070,
                    1.095
                )

                vertex.co.y += 0.030

            # Cannon.
            elif z > 0.27:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    0.950,
                    0.965
                )

                vertex.co.y -= 0.010

            # Fetlock / pastern.
            else:

                scale_around(
                    vertex,
                    center_x,
                    center_y,
                    1.035,
                    1.025
                )

    refine_hind(
        "RiverwatchV13HindLeftLeg",
        -0.305
    )

    refine_hind(
        "RiverwatchV13HindRightLeg",
        0.305
    )

    # ========================================================
    # HOOF SHAPING
    # ========================================================

    def refine_hoof(
        name,
        center_x,
        center_y
    ):

        obj = bpy.data.objects.get(
            name
        )

        if obj is None:
            return

        for vertex in obj.data.vertices:

            local_y = (
                vertex.co.y
                - center_y
            )

            # Heel is narrower.
            if local_y > 0.0:

                vertex.co.x = (
                    center_x
                    + (
                        vertex.co.x
                        - center_x
                    )
                    * 0.94
                )

            # Toe is broader and slightly longer.
            if local_y < -0.055:

                vertex.co.x = (
                    center_x
                    + (
                        vertex.co.x
                        - center_x
                    )
                    * 1.075
                )

                vertex.co.y = (
                    center_y
                    + local_y
                    * 1.075
                )

            # Lower hoof profile.
            vertex.co.z = (
                0.025
                + (
                    vertex.co.z
                    - 0.025
                )
                * 0.94
            )

    refine_hoof(
        "RiverwatchV13FrontLeftHoof",
        -0.285,
        -0.550
    )

    refine_hoof(
        "RiverwatchV13FrontRightHoof",
        0.285,
        -0.550
    )

    refine_hoof(
        "RiverwatchV13HindLeftHoof",
        -0.305,
        0.470
    )

    refine_hoof(
        "RiverwatchV13HindRightHoof",
        0.305,
        0.470
    )

    # ========================================================
    # MANE
    # ========================================================

    mane = bpy.data.objects.get(
        "RiverwatchV13Mane"
    )

    if mane is not None:

        for vertex in mane.data.vertices:

            # Keep mane close to neck.
            vertex.co.x *= 0.90

            # More hanging length near middle/lower neck.
            middle = gauss(
                vertex.co.y,
                -0.75,
                0.20
            )

            if vertex.co.z < 1.92:

                vertex.co.z -= (
                    0.045
                    * middle
                )

    # ========================================================
    # FORELOCK
    # ========================================================

    forelock = bpy.data.objects.get(
        "RiverwatchV13Forelock"
    )

    if forelock is not None:

        forelock.scale.x *= 0.90
        forelock.scale.z *= 1.12

    # ========================================================
    # TAIL
    # ========================================================

    tail = bpy.data.objects.get(
        "RiverwatchV13Tail"
    )

    if tail is not None:

        for vertex in tail.data.vertices:

            if vertex.co.z < 1.12:

                amount = clamp01(
                    (
                        1.12
                        - vertex.co.z
                    )
                    / 0.75
                )

                # Longer lower tail.
                vertex.co.z -= (
                    0.035
                    * amount
                )

                # Keep it hanging instead of projecting far back.
                vertex.co.y -= (
                    0.018
                    * amount
                )

    # ========================================================
    # FACIAL DETAILS
    #
    # Match extra head rotation + shortening.
    # ========================================================

    face_prefixes = (
        "RiverwatchV13MuzzlePatch",
        "RiverwatchV13Eye",
        "RiverwatchV13Pupil",
        "RiverwatchV13EyeGlint",
        "RiverwatchV13Nostril",
        "RiverwatchV13Forelock",
    )

    for obj in bpy.context.scene.objects:

        if not any(
            obj.name.startswith(prefix)
            for prefix in face_prefixes
        ):
            continue

        if obj.location.y < -1.02:

            old_y = obj.location.y
            old_z = obj.location.z

            pivot_y = -1.01
            pivot_z = 1.82

            angle = math.radians(
                3.5
            )

            dy = old_y - pivot_y
            dz = old_z - pivot_z

            cosine = math.cos(
                angle
            )

            sine = math.sin(
                angle
            )

            obj.location.y = (
                pivot_y
                + dy * cosine
                - dz * sine
            )

            obj.location.z = (
                pivot_z
                + dy * sine
                + dz * cosine
            )

            if obj.location.y < -1.34:
                obj.location.y += 0.025

    # ========================================================
    # EARS
    # ========================================================

    for name in (
        "RiverwatchV13LeftEar",
        "RiverwatchV13RightEar",
    ):

        ear = bpy.data.objects.get(
            name
        )

        if ear is None:
            continue

        for vertex in ear.data.vertices:

            # Slightly narrower and more upright.
            vertex.co.x *= 0.94

            if vertex.co.z > 1.98:
                vertex.co.z += 0.012

    # ========================================================
    # VERSION NAMES
    # ========================================================

    for mat in bpy.data.materials:

        if mat.name.startswith(
            "Riverwatch V13"
        ):

            mat.name = mat.name.replace(
                "Riverwatch V13",
                "Riverwatch V14",
                1
            )

    for obj in bpy.context.scene.objects:

        if obj.name.startswith(
            "RiverwatchV13"
        ):

            obj.name = obj.name.replace(
                "RiverwatchV13",
                "RiverwatchV14",
                1
            )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "anatomical_definition_v14"

    arm[
        "broken_knight_horse_v14_head"
    ] = "defined_skull_cheek_jaw_muzzle"

    arm[
        "broken_knight_horse_v14_neck"
    ] = "crest_throat_throatlatch"

    arm[
        "broken_knight_horse_v14_front_leg"
    ] = "forearm_knee_cannon_fetlock"

    arm[
        "broken_knight_horse_v14_hind_leg"
    ] = "thigh_stifle_gaskin_hock_cannon"

    arm[
        "broken_knight_horse_v14_hoof"
    ] = "narrow_heel_broad_toe"

    arm[
        "broken_knight_horse_v14_goal"
    ] = "recognizable_horse_anatomy"

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