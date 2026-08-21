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
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "RiverwatchHorseRig"
    arm.data.name = "RiverwatchHorseRigData"
    default = arm.data.edit_bones.get("Bone")
    arm.data.edit_bones.remove(default)
    definitions = {
        "root": ((0, 0, 0), (0, 0, 0.42), None),
        "body": ((0, 0, 0.42), (0, 0, 1.28), "root"),
        "neck": ((0, -0.48, 1.34), (0, -0.96, 1.72), "body"),
        "head": ((0, -0.96, 1.72), (0, -1.46, 1.68), "neck"),
        "tail.1": ((0, 0.68, 1.28), (0, 1.05, 1.02), "body"),
        "tail.2": ((0, 1.05, 1.02), (0, 1.34, 0.70), "tail.1"),
    }
    for prefix, x, y in (
        ("front.L", -0.25, -0.43), ("front.R", 0.25, -0.43),
        ("hind.L", -0.27, 0.43), ("hind.R", 0.27, 0.43),
    ):
        definitions[prefix + ".upper"] = ((x, y, 1.02), (x, y, 0.58), "body")
        definitions[prefix + ".lower"] = ((x, y, 0.58), (x, y, 0.18), prefix + ".upper")
        definitions[prefix + ".hoof"] = ((x, y, 0.18), (x, y - 0.12, 0.08), prefix + ".lower")
    for name, (head, tail, parent) in definitions.items():
        bone = arm.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
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
    # RIVERWATCH HEAVY COURSER V7
    #
    # This pass deliberately fixes proportions instead of
    # adding more decorative pieces.
    #
    # Main goals:
    #
    # - MUCH thicker legs
    # - longer visible legs
    # - shallower barrel / higher belly
    # - powerful forearms
    # - powerful thighs and gaskins
    # - proper visible knees
    # - proper visible hocks
    # - thicker cannons
    # - substantial fetlocks and pasterns
    # - larger hooves
    # - rounded croup without muscle balls
    # - smaller cleaner saddle
    # - simplified tack
    # - coherent mane and tail
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V7 Deep Bay",
        (0.305, 0.092, 0.025, 1),
        0.57
    )

    coat_shadow = material(
        "Riverwatch V7 Coat Shadow",
        (0.075, 0.020, 0.008, 1),
        0.70
    )

    coat_highlight = material(
        "Riverwatch V7 Coat Highlight",
        (0.430, 0.150, 0.045, 1),
        0.55
    )

    mane = material(
        "Riverwatch V7 Mane",
        (0.012, 0.008, 0.006, 1),
        0.70
    )

    mane_highlight = material(
        "Riverwatch V7 Mane Highlight",
        (0.050, 0.033, 0.023, 1),
        0.64
    )

    muzzle = material(
        "Riverwatch V7 Muzzle",
        (0.175, 0.110, 0.087, 1),
        0.74
    )

    ivory = material(
        "Riverwatch V7 Ivory",
        (0.805, 0.770, 0.690, 1),
        0.80
    )

    eye = material(
        "Riverwatch V7 Eye",
        (0.035, 0.012, 0.005, 1),
        0.18
    )

    pupil = material(
        "Riverwatch V7 Pupil",
        (0.002, 0.002, 0.002, 1),
        0.10
    )

    eye_glint = material(
        "Riverwatch V7 Eye Glint",
        (0.95, 0.94, 0.90, 1),
        0.10
    )

    hoof = material(
        "Riverwatch V7 Hoof",
        (0.038, 0.028, 0.020, 1),
        0.80
    )

    leather = material(
        "Riverwatch V7 Saddle Leather",
        (0.070, 0.020, 0.009, 1),
        0.66
    )

    leather_mid = material(
        "Riverwatch V7 Warm Leather",
        (0.170, 0.060, 0.020, 1),
        0.62
    )

    leather_edge = material(
        "Riverwatch V7 Leather Edge",
        (0.275, 0.105, 0.035, 1),
        0.58
    )

    blanket = material(
        "Riverwatch V7 Royal Blanket",
        (0.026, 0.080, 0.250, 1),
        0.78
    )

    brass = material(
        "Riverwatch V7 Brass",
        (0.570, 0.335, 0.075, 1),
        0.30,
        0.76
    )

    iron = material(
        "Riverwatch V7 Iron",
        (0.045, 0.048, 0.055, 1),
        0.38,
        0.72
    )

    # --------------------------------------------------------
    # GENERAL HELPERS
    # --------------------------------------------------------

    def smooth(obj):
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        return obj

    def armature_bind(obj):
        obj.parent = arm

        modifier = obj.modifiers.new(
            "HorseRig",
            "ARMATURE"
        )

        modifier.object = arm

        return obj

    def rigid_group(obj, bone_name):
        group = obj.vertex_groups.new(
            name=bone_name
        )

        group.add(
            range(len(obj.data.vertices)),
            1.0,
            "REPLACE"
        )

        armature_bind(obj)

        return obj

    def subdivide(obj, levels=1):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(True)

        modifier = obj.modifiers.new(
            "HorseSubsurf",
            "SUBSURF"
        )

        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = levels
        modifier.render_levels = levels

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    def bevel(obj, width=0.015, segments=3):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(True)

        modifier = obj.modifiers.new(
            "HorseBevel",
            "BEVEL"
        )

        modifier.width = width
        modifier.segments = segments

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    # --------------------------------------------------------
    # GENERAL LOFT
    #
    # Each section:
    #
    # x center
    # y center
    # z center
    # x radius
    # z radius
    #
    # Rings are connected into one continuous surface.
    # --------------------------------------------------------

    def build_loft(
        name,
        sections,
        mat,
        rings=32,
        subdivision=1
    ):
        verts = []
        faces = []

        for section in sections:
            cx, cy, cz, rx, rz = section

            for ring_index in range(rings):
                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                verts.append(
                    (
                        cx
                        + math.cos(angle)
                        * rx,

                        cy,

                        cz
                        + math.sin(angle)
                        * rz,
                    )
                )

        for section_index in range(
            len(sections) - 1
        ):
            first = section_index * rings
            second = (
                section_index + 1
            ) * rings

            for ring_index in range(rings):
                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring,
                    )
                )

        first_center = len(verts)

        verts.append(
            (
                sections[0][0],
                sections[0][1],
                sections[0][2],
            )
        )

        last_center = len(verts)

        verts.append(
            (
                sections[-1][0],
                sections[-1][1],
                sections[-1][2],
            )
        )

        for ring_index in range(rings):
            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    first_center,
                    next_ring,
                    ring_index,
                )
            )

            last_ring_start = (
                len(sections) - 1
            ) * rings

            faces.append(
                (
                    last_center,
                    last_ring_start + ring_index,
                    last_ring_start + next_ring,
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
            mat
        )

        if subdivision > 0:
            subdivide(
                obj,
                subdivision
            )

        smooth(obj)

        return obj

    # ========================================================
    # BODY / NECK / HEAD
    #
    # V6 had a very deep barrel.
    #
    # V7 keeps nearly the same topline but RAISES THE BELLY.
    # This gives the horse substantially more visible leg.
    # ========================================================

    def build_core():
        sections = [
            # rear taper
            (1.170, 1.430, 0.035, 0.040),
            (1.130, 1.430, 0.090, 0.105),
            (1.070, 1.430, 0.175, 0.205),

            # croup
            (0.990, 1.425, 0.285, 0.315),
            (0.895, 1.415, 0.400, 0.405),
            (0.775, 1.400, 0.500, 0.465),
            (0.635, 1.385, 0.550, 0.485),
            (0.480, 1.365, 0.565, 0.480),

            # flank / barrel
            (0.300, 1.345, 0.555, 0.455),
            (0.100, 1.335, 0.545, 0.450),
            (-0.100, 1.340, 0.535, 0.455),

            # chest
            (-0.285, 1.370, 0.515, 0.485),
            (-0.440, 1.425, 0.475, 0.500),

            # withers
            (-0.575, 1.500, 0.410, 0.445),

            # lower neck
            (-0.700, 1.575, 0.350, 0.385),
            (-0.815, 1.650, 0.305, 0.335),
            (-0.925, 1.720, 0.265, 0.290),
            (-1.030, 1.785, 0.230, 0.255),

            # poll / skull
            (-1.130, 1.825, 0.215, 0.235),
            (-1.235, 1.820, 0.220, 0.225),
            (-1.340, 1.790, 0.215, 0.205),

            # cheek / jaw
            (-1.445, 1.745, 0.205, 0.185),

            # muzzle
            (-1.550, 1.700, 0.190, 0.155),
            (-1.650, 1.675, 0.165, 0.125),
            (-1.735, 1.665, 0.130, 0.095),
            (-1.800, 1.662, 0.075, 0.055),
            (-1.835, 1.662, 0.030, 0.025),
        ]

        rings = 60

        verts = []
        faces = []

        for section_index, section in enumerate(
            sections
        ):
            y, center_z, width, height = section

            for ring_index in range(rings):
                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                cosine = math.cos(angle)
                sine = math.sin(angle)

                vertical = sine

                # Slightly flatter topline and firmer belly.
                if vertical >= 0.0:
                    vertical = vertical ** 0.82
                else:
                    vertical = -((-vertical) ** 1.06)

                x = width * cosine
                z = center_z + height * vertical

                # Rounded croup.
                croup = math.exp(
                    -((y - 0.66) / 0.30) ** 2
                )

                x *= (
                    1.0
                    + 0.075
                    * croup
                    * (1.0 - abs(sine))
                )

                if sine > 0.0:
                    z += (
                        0.055
                        * croup
                        * sine
                    )

                # Shoulder breadth.
                shoulder = math.exp(
                    -((y + 0.38) / 0.22) ** 2
                )

                x *= (
                    1.0
                    + 0.060
                    * shoulder
                    * (1.0 - abs(sine))
                )

                # Defined withers.
                withers = math.exp(
                    -((y + 0.56) / 0.16) ** 2
                )

                if sine > 0.20:
                    z += (
                        0.070
                        * withers
                        * sine
                    )

                # Belly tuck behind barrel.
                flank = math.exp(
                    -((y - 0.34) / 0.20) ** 2
                )

                if sine < 0.0:
                    z += (
                        0.060
                        * flank
                        * (-sine)
                    )

                # Neck crest.
                neck = math.exp(
                    -((y + 0.86) / 0.26) ** 2
                )

                if sine > 0.0:
                    z += (
                        0.045
                        * neck
                        * sine
                    )

                # Jaw depth.
                jaw = math.exp(
                    -((y + 1.40) / 0.18) ** 2
                )

                if sine < 0.0:
                    z -= (
                        0.026
                        * jaw
                        * (-sine)
                    )

                verts.append(
                    (
                        x,
                        y,
                        z
                    )
                )

        section_count = len(sections)

        for section_index in range(
            section_count - 1
        ):
            first = section_index * rings

            second = (
                section_index + 1
            ) * rings

            for ring_index in range(rings):
                next_ring = (
                    ring_index + 1
                ) % rings

                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring,
                    )
                )

        rear_center = len(verts)

        verts.append(
            (
                0.0,
                sections[0][0],
                sections[0][1],
            )
        )

        front_center = len(verts)

        verts.append(
            (
                0.0,
                sections[-1][0],
                sections[-1][1],
            )
        )

        for ring_index in range(rings):
            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    rear_center,
                    ring_index,
                    next_ring,
                )
            )

            last = (
                section_count - 1
            ) * rings

            faces.append(
                (
                    front_center,
                    last + next_ring,
                    last + ring_index,
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV7CoreMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV7Core",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            coat
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

            if y >= -0.70:
                body_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -0.90:
                blend = (
                    (-0.70 - y)
                    / 0.20
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

            elif y >= -1.10:
                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -1.23:
                blend = (
                    (-1.10 - y)
                    / 0.13
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

        subdivide(
            obj,
            1
        )

        smooth(obj)

        armature_bind(obj)

        return obj

    build_core()

    # ========================================================
    # LEGS
    #
    # THIS IS THE BIG V7 CHANGE.
    #
    # V6 lower front radius:
    # roughly 0.065 - 0.072
    #
    # V7 lower front radius:
    # roughly 0.100 - 0.125
    #
    # The horse should now look supported by its legs instead
    # of balancing on sticks.
    # ========================================================

    def build_leg(
        prefix,
        sections
    ):
        obj = build_loft(
            prefix + "V7Leg",
            sections,
            coat,
            rings=30,
            subdivision=1
        )

        upper_group = obj.vertex_groups.new(
            name=prefix + ".upper"
        )

        lower_group = obj.vertex_groups.new(
            name=prefix + ".lower"
        )

        hoof_group = obj.vertex_groups.new(
            name=prefix + ".hoof"
        )

        for vertex in obj.data.vertices:
            z = vertex.co.z

            if z >= 0.68:
                upper_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif z > 0.56:
                blend = (
                    (0.68 - z)
                    / 0.12
                )

                upper_group.add(
                    [vertex.index],
                    1.0 - blend,
                    "REPLACE"
                )

                lower_group.add(
                    [vertex.index],
                    blend,
                    "REPLACE"
                )

            elif z >= 0.22:
                lower_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif z > 0.13:
                blend = (
                    (0.22 - z)
                    / 0.09
                )

                lower_group.add(
                    [vertex.index],
                    1.0 - blend,
                    "REPLACE"
                )

                hoof_group.add(
                    [vertex.index],
                    blend,
                    "REPLACE"
                )

            else:
                hoof_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

        armature_bind(obj)

        return obj

    # --------------------------------------------------------
    # FRONT LEGS
    #
    # Big upper arm.
    # Thick forearm.
    # Defined knee.
    # Cannon is no longer a straw.
    # Fetlock expands again.
    # --------------------------------------------------------

    front_left = [
        (-0.300, -0.440, 1.145, 0.195, 0.205),
        (-0.300, -0.450, 1.025, 0.185, 0.195),
        (-0.300, -0.462, 0.900, 0.170, 0.180),
        (-0.300, -0.474, 0.780, 0.150, 0.160),

        # knee
        (-0.300, -0.484, 0.660, 0.138, 0.145),
        (-0.300, -0.490, 0.585, 0.150, 0.155),

        # cannon
        (-0.300, -0.500, 0.485, 0.120, 0.125),
        (-0.300, -0.512, 0.365, 0.105, 0.112),
        (-0.300, -0.525, 0.260, 0.100, 0.108),

        # fetlock / pastern
        (-0.300, -0.540, 0.190, 0.120, 0.125),
        (-0.300, -0.555, 0.135, 0.115, 0.120),
    ]

    front_right = [
        (
            -x,
            y,
            z,
            rx,
            rz
        )
        for x, y, z, rx, rz in front_left
    ]

    build_leg(
        "front.L",
        front_left
    )

    build_leg(
        "front.R",
        front_right
    )

    # --------------------------------------------------------
    # HIND LEGS
    #
    # Thick thigh and gaskin.
    # Angled hock.
    # Strong cannon.
    # Much bigger fetlock / pastern.
    # --------------------------------------------------------

    hind_left = [
        (-0.325, 0.500, 1.155, 0.225, 0.230),
        (-0.325, 0.535, 1.045, 0.218, 0.220),
        (-0.325, 0.580, 0.925, 0.200, 0.205),
        (-0.325, 0.625, 0.810, 0.180, 0.185),

        # gaskin
        (-0.325, 0.670, 0.700, 0.160, 0.168),

        # hock - clearly wider
        (-0.325, 0.715, 0.610, 0.155, 0.162),
        (-0.325, 0.720, 0.545, 0.165, 0.170),

        # cannon angles forward again
        (-0.325, 0.680, 0.455, 0.125, 0.132),
        (-0.325, 0.630, 0.355, 0.110, 0.118),
        (-0.325, 0.585, 0.260, 0.105, 0.112),

        # fetlock / pastern
        (-0.325, 0.545, 0.190, 0.125, 0.130),
        (-0.325, 0.515, 0.135, 0.120, 0.125),
    ]

    hind_right = [
        (
            -x,
            y,
            z,
            rx,
            rz
        )
        for x, y, z, rx, rz in hind_left
    ]

    build_leg(
        "hind.L",
        hind_left
    )

    build_leg(
        "hind.R",
        hind_right
    )

    # ========================================================
    # BIGGER HOOF WEDGES
    # ========================================================

    def build_hoof(
        name,
        x,
        y,
        bone,
        width=0.135,
        rear=0.115,
        front=0.190
    ):
        top_width = width * 0.78

        verts = [
            (
                x - top_width,
                y + rear * 0.72,
                0.135
            ),
            (
                x + top_width,
                y + rear * 0.72,
                0.135
            ),
            (
                x + top_width * 1.02,
                y - front * 0.68,
                0.125
            ),
            (
                x - top_width * 1.02,
                y - front * 0.68,
                0.125
            ),

            (
                x - width,
                y + rear,
                0.028
            ),
            (
                x + width,
                y + rear,
                0.028
            ),
            (
                x + width * 1.08,
                y - front,
                0.028
            ),
            (
                x - width * 1.08,
                y - front,
                0.028
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
            hoof
        )

        rigid_group(
            obj,
            bone
        )

        bevel(
            obj,
            0.020,
            3
        )

        smooth(obj)

        return obj

    build_hoof(
        "HorseV7FrontLeftHoof",
        -0.300,
        -0.565,
        "front.L.hoof",
        0.135,
        0.115,
        0.195
    )

    build_hoof(
        "HorseV7FrontRightHoof",
        0.300,
        -0.565,
        "front.R.hoof",
        0.135,
        0.115,
        0.195
    )

    build_hoof(
        "HorseV7HindLeftHoof",
        -0.325,
        0.500,
        "hind.L.hoof",
        0.142,
        0.120,
        0.205
    )

    build_hoof(
        "HorseV7HindRightHoof",
        0.325,
        0.500,
        "hind.R.hoof",
        0.142,
        0.120,
        0.205
    )

    # ========================================================
    # MANE
    #
    # One broad flowing silhouette.
    # ========================================================

    def build_mane():
        stations = [
            (-1.145, 2.025, 1.885),
            (-1.090, 2.015, 1.850),
            (-1.030, 1.995, 1.810),
            (-0.965, 1.965, 1.765),
            (-0.900, 1.925, 1.715),
            (-0.830, 1.880, 1.665),
            (-0.760, 1.825, 1.615),
            (-0.690, 1.765, 1.570),
            (-0.620, 1.705, 1.530),
            (-0.555, 1.650, 1.500),
            (-0.505, 1.610, 1.485),
        ]

        verts = []
        faces = []

        thickness = 0.024

        for index, station in enumerate(
            stations
        ):
            y, root_z, tip_z = station

            wave = (
                0.020
                * math.sin(
                    float(index)
                    * 1.35
                )
            )

            root_x = -0.015
            tip_x = -0.135 + wave

            verts.extend(
                [
                    (
                        root_x - thickness,
                        y,
                        root_z
                    ),
                    (
                        root_x + thickness,
                        y,
                        root_z
                    ),
                    (
                        tip_x - thickness,
                        y + 0.025,
                        tip_z
                    ),
                    (
                        tip_x + thickness,
                        y + 0.025,
                        tip_z
                    ),
                ]
            )

        for index in range(
            len(stations) - 1
        ):
            a = index * 4
            b = (index + 1) * 4

            faces.append(
                (
                    a,
                    b,
                    b + 2,
                    a + 2
                )
            )

            faces.append(
                (
                    a + 1,
                    a + 3,
                    b + 3,
                    b + 1
                )
            )

            faces.append(
                (
                    a,
                    a + 1,
                    b + 1,
                    b
                )
            )

            faces.append(
                (
                    a + 2,
                    b + 2,
                    b + 3,
                    a + 3
                )
            )

        faces.append(
            (
                0,
                2,
                3,
                1
            )
        )

        end = (
            len(stations) - 1
        ) * 4

        faces.append(
            (
                end,
                end + 1,
                end + 3,
                end + 2
            )
        )

        mesh = bpy.data.meshes.new(
            "RiverwatchV7ManeMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV7Mane",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            mane
        )

        neck_group = obj.vertex_groups.new(
            name="neck"
        )

        head_group = obj.vertex_groups.new(
            name="head"
        )

        for vertex in obj.data.vertices:
            if vertex.co.y < -1.05:
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

        subdivide(
            obj,
            1
        )

        smooth(obj)

        armature_bind(obj)

    build_mane()

    # Forelock
    horse_cylinder(
        "HorseV7Forelock",
        (0.0, -1.160, 2.020),
        (-0.055, -1.350, 1.860),
        0.025,
        mane,
        arm,
        "head",
        0.010
    )

    # ========================================================
    # SINGLE TAIL
    # ========================================================

    tail = build_loft(
        "RiverwatchV7Tail",
        [
            (0.000, 1.000, 1.430, 0.075, 0.085),
            (0.000, 1.080, 1.370, 0.110, 0.125),
            (-0.005, 1.175, 1.280, 0.140, 0.155),
            (-0.010, 1.285, 1.155, 0.165, 0.175),
            (0.000, 1.395, 1.010, 0.175, 0.185),
            (0.010, 1.505, 0.850, 0.170, 0.180),
            (0.005, 1.605, 0.705, 0.155, 0.165),
            (-0.005, 1.690, 0.580, 0.125, 0.140),
            (0.000, 1.755, 0.480, 0.085, 0.100),
            (0.000, 1.790, 0.430, 0.040, 0.050),
        ],
        mane,
        rings=30,
        subdivision=1
    )

    tail1 = tail.vertex_groups.new(
        name="tail.1"
    )

    tail2 = tail.vertex_groups.new(
        name="tail.2"
    )

    for vertex in tail.data.vertices:
        y = vertex.co.y

        if y <= 1.18:
            tail1.add(
                [vertex.index],
                1.0,
                "REPLACE"
            )

        elif y < 1.38:
            blend = (
                (y - 1.18)
                / 0.20
            )

            tail1.add(
                [vertex.index],
                1.0 - blend,
                "REPLACE"
            )

            tail2.add(
                [vertex.index],
                blend,
                "REPLACE"
            )

        else:
            tail2.add(
                [vertex.index],
                1.0,
                "REPLACE"
            )

    armature_bind(
        tail
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
                sx * 0.060,
                -1.105,
                1.990
            ),
            (
                sx * 0.145,
                -1.098,
                1.990
            ),
            (
                sx * 0.122,
                -1.070,
                2.205
            ),

            (
                sx * 0.070,
                -1.035,
                2.000
            ),
            (
                sx * 0.137,
                -1.030,
                2.000
            ),
            (
                sx * 0.118,
                -1.020,
                2.185
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

        rigid_group(
            obj,
            "head"
        )

        subdivide(
            obj,
            1
        )

        smooth(obj)

    build_ear(
        "HorseV7LeftEar",
        -1
    )

    build_ear(
        "HorseV7RightEar",
        1
    )

    # ========================================================
    # FACE
    # ========================================================

    horse_sphere(
        "HorseV7MuzzlePatch",
        (0.0, -1.725, 1.665),
        (0.145, 0.095, 0.075),
        muzzle,
        arm,
        "head",
        22,
        14
    )

    for side in (-1, 1):

        horse_sphere(
            "HorseV7Eye",
            (
                side * 0.202,
                -1.285,
                1.885
            ),
            (
                0.032,
                0.021,
                0.032
            ),
            eye,
            arm,
            "head",
            20,
            12
        )

        horse_sphere(
            "HorseV7Pupil",
            (
                side * 0.224,
                -1.300,
                1.885
            ),
            (
                0.013,
                0.009,
                0.021
            ),
            pupil,
            arm,
            "head",
            14,
            10
        )

        horse_sphere(
            "HorseV7EyeGlint",
            (
                side * 0.235,
                -1.307,
                1.898
            ),
            (
                0.005,
                0.004,
                0.005
            ),
            eye_glint,
            arm,
            "head",
            10,
            8
        )

        horse_sphere(
            "HorseV7Nostril",
            (
                side * 0.088,
                -1.800,
                1.670
            ),
            (
                0.024,
                0.014,
                0.017
            ),
            coat_shadow,
            arm,
            "head",
            14,
            10
        )

    horse_cylinder(
        "HorseV7Blaze",
        (0.0, -1.160, 1.995),
        (0.0, -1.570, 1.725),
        0.022,
        ivory,
        arm,
        "head",
        0.010
    )

    # ========================================================
    # CLEANER / SMALLER BLANKET
    # ========================================================

    def build_blanket():
        y_values = [
            -0.365,
            -0.180,
            0.000,
            0.180,
            0.365,
        ]

        x_values = [
            -0.390,
            -0.260,
            -0.130,
            0.000,
            0.130,
            0.260,
            0.390,
        ]

        verts = []
        faces = []

        top_count = (
            len(y_values)
            * len(x_values)
        )

        for layer in range(2):
            for y in y_values:
                for x in x_values:
                    side = (
                        abs(x)
                        / 0.390
                    )

                    z = (
                        1.790
                        - 0.145
                        * (side ** 1.55)
                        - float(layer)
                        * 0.022
                    )

                    verts.append(
                        (
                            x,
                            y,
                            z
                        )
                    )

        width = len(x_values)
        height = len(y_values)

        for layer in range(2):
            base = (
                layer
                * top_count
            )

            for yi in range(
                height - 1
            ):
                for xi in range(
                    width - 1
                ):
                    a = (
                        base
                        + yi * width
                        + xi
                    )

                    b = a + 1
                    c = a + width + 1
                    d = a + width

                    if layer == 0:
                        faces.append(
                            (
                                a,
                                d,
                                c,
                                b
                            )
                        )
                    else:
                        faces.append(
                            (
                                a,
                                b,
                                c,
                                d
                            )
                        )

        for yi in range(
            height - 1
        ):
            left_a = yi * width
            left_b = (
                yi + 1
            ) * width

            faces.append(
                (
                    left_a,
                    top_count + left_a,
                    top_count + left_b,
                    left_b
                )
            )

            right_a = (
                yi * width
                + width - 1
            )

            right_b = (
                (yi + 1)
                * width
                + width - 1
            )

            faces.append(
                (
                    right_a,
                    right_b,
                    top_count + right_b,
                    top_count + right_a
                )
            )

        mesh = bpy.data.meshes.new(
            "HorseV7BlanketMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "HorseV7Blanket",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            blanket
        )

        rigid_group(
            obj,
            "body"
        )

        smooth(obj)

    build_blanket()

    # ========================================================
    # LOWER-PROFILE SADDLE
    # ========================================================

    def build_saddle():
        y_values = [
            -0.270,
            -0.140,
            0.000,
            0.140,
            0.270,
        ]

        x_values = [
            -0.265,
            -0.130,
            0.000,
            0.130,
            0.265,
        ]

        verts = []
        faces = []

        top_count = (
            len(y_values)
            * len(x_values)
        )

        for layer in range(2):

            for y in y_values:

                for x in x_values:

                    side = (
                        abs(x)
                        / 0.265
                    )

                    ends = (
                        abs(y)
                        / 0.270
                    )

                    z = (
                        1.815
                        + 0.025
                        * side
                        + 0.035
                        * (ends ** 1.8)
                        - float(layer)
                        * 0.060
                    )

                    verts.append(
                        (
                            x,
                            y,
                            z
                        )
                    )

        width = len(x_values)
        height = len(y_values)

        for layer in range(2):

            base = (
                layer
                * top_count
            )

            for yi in range(
                height - 1
            ):

                for xi in range(
                    width - 1
                ):
                    a = (
                        base
                        + yi * width
                        + xi
                    )

                    b = a + 1
                    c = a + width + 1
                    d = a + width

                    if layer == 0:
                        faces.append(
                            (
                                a,
                                d,
                                c,
                                b
                            )
                        )
                    else:
                        faces.append(
                            (
                                a,
                                b,
                                c,
                                d
                            )
                        )

        mesh = bpy.data.meshes.new(
            "HorseV7SaddleMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "HorseV7Saddle",
            mesh
        )

        bpy.context.collection.objects.link(
            obj
        )

        obj.data.materials.append(
            leather
        )

        rigid_group(
            obj,
            "body"
        )

        bevel(
            obj,
            0.018,
            3
        )

        smooth(obj)

    build_saddle()

    # Pommel.
    horse_cube(
        "HorseV7Pommel",
        (
            0.0,
            -0.255,
            1.875
        ),
        (
            0.330,
            0.095,
            0.120
        ),
        leather_edge,
        arm,
        "body",
        edge=0.035
    )

    # Cantle.
    horse_cube(
        "HorseV7Cantle",
        (
            0.0,
            0.255,
            1.890
        ),
        (
            0.350,
            0.095,
            0.145
        ),
        leather_edge,
        arm,
        "body",
        edge=0.038
    )

    # Saddle flaps.
    for side in (-1, 1):

        horse_cube(
            "HorseV7SaddleFlap",
            (
                side * 0.315,
                0.015,
                1.605
            ),
            (
                0.070,
                0.390,
                0.280
            ),
            leather_mid,
            arm,
            "body",
            edge=0.035
        )

    # Girth.
    girth = torus(
        "HorseV7Girth",
        (
            0.0,
            0.010,
            1.330
        ),
        0.425,
        0.025,
        leather,
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

    # ========================================================
    # STIRRUPS
    # ========================================================

    for side in (-1, 1):

        horse_cylinder(
            "HorseV7StirrupLeather",
            (
                side * 0.240,
                0.000,
                1.790
            ),
            (
                side * 0.430,
                0.000,
                1.050
            ),
            0.010,
            leather,
            arm,
            "body"
        )

        stirrup = torus(
            "HorseV7Stirrup",
            (
                side * 0.440,
                0.000,
                0.980
            ),
            0.095,
            0.015,
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
    # SIMPLE BRIDLE
    # ========================================================

    noseband = torus(
        "HorseV7NoseBand",
        (
            0.0,
            -1.560,
            1.690
        ),
        0.170,
        0.012,
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
        "HorseV7BrowBand",
        (
            -0.170,
            -1.170,
            1.955
        ),
        (
            0.170,
            -1.170,
            1.955
        ),
        0.011,
        leather_mid,
        arm,
        "head"
    )

    horse_cylinder(
        "HorseV7Bit",
        (
            -0.170,
            -1.620,
            1.630
        ),
        (
            0.170,
            -1.620,
            1.630
        ),
        0.010,
        iron,
        arm,
        "head"
    )

    for side in (-1, 1):

        horse_cylinder(
            "HorseV7CheekPiece",
            (
                side * 0.165,
                -1.165,
                1.945
            ),
            (
                side * 0.175,
                -1.560,
                1.685
            ),
            0.009,
            leather,
            arm,
            "head"
        )

        ring = torus(
            "HorseV7BitRing",
            (
                side * 0.180,
                -1.625,
                1.630
            ),
            0.036,
            0.007,
            brass,
            rotation=(
                math.pi / 2,
                0.0,
                0.0
            )
        )

        rigid_skin(
            ring,
            arm,
            "head"
        )

        horse_cylinder(
            "HorseV7Rein",
            (
                side * 0.180,
                -1.625,
                1.630
            ),
            (
                side * 0.240,
                -0.210,
                1.690
            ),
            0.007,
            leather,
            arm,
            "head"
        )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "heavy_courser_v7"

    arm[
        "broken_knight_horse_authoring"
    ] = "blender"

    arm[
        "broken_knight_horse_leg_pass"
    ] = "major_thickness_redesign"

    arm[
        "broken_knight_horse_body_pass"
    ] = "raised_belly_shallower_barrel"

    arm[
        "broken_knight_horse_front_legs"
    ] = "thick_forearm_knee_cannon_fetlock"

    arm[
        "broken_knight_horse_hind_legs"
    ] = "thick_thigh_gaskin_hock_cannon"

    arm[
        "broken_knight_horse_hooves"
    ] = "large_gameplay_readable_wedges"

    arm[
        "broken_knight_horse_tack"
    ] = "simplified_lower_profile"

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