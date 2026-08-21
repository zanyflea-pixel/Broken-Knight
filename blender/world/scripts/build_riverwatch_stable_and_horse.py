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
    # RIVERWATCH COURSER V8
    #
    # V8 is a topology / anatomy correction.
    #
    # Critical change:
    #
    # V7 used a body-oriented loft for the vertical legs.
    # That meant limb cross sections remained in the X/Z
    # plane and produced flattened geometry.
    #
    # V8 sweeps each limb along a TRUE 3D centerline.
    # Every cross section is perpendicular to the local
    # direction of the limb.
    #
    # Result:
    #
    # - genuinely round legs from every viewing angle
    # - proper front knees
    # - proper hind hocks
    # - thinner but dimensional cannons
    # - substantial fetlocks / pasterns
    # - stronger thighs / forearms
    # - cleaner body silhouette
    # - less oversized barrel
    # - better neck/head proportions
    # - coherent croup
    # - one continuous 3D tail
    # - coherent mane
    # - smaller believable saddle and blanket
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V8 Bay",
        (0.300, 0.088, 0.024, 1),
        0.56
    )

    coat_dark = material(
        "Riverwatch V8 Bay Dark",
        (0.070, 0.018, 0.007, 1),
        0.70
    )

    coat_light = material(
        "Riverwatch V8 Bay Light",
        (0.420, 0.145, 0.045, 1),
        0.55
    )

    mane_mat = material(
        "Riverwatch V8 Mane",
        (0.012, 0.008, 0.006, 1),
        0.68
    )

    mane_light = material(
        "Riverwatch V8 Mane Light",
        (0.050, 0.032, 0.021, 1),
        0.63
    )

    muzzle_mat = material(
        "Riverwatch V8 Muzzle",
        (0.165, 0.100, 0.078, 1),
        0.74
    )

    ivory = material(
        "Riverwatch V8 Ivory",
        (0.810, 0.775, 0.700, 1),
        0.79
    )

    eye_mat = material(
        "Riverwatch V8 Eye",
        (0.060, 0.020, 0.006, 1),
        0.17
    )

    pupil_mat = material(
        "Riverwatch V8 Pupil",
        (0.002, 0.002, 0.002, 1),
        0.10
    )

    glint_mat = material(
        "Riverwatch V8 Eye Glint",
        (0.960, 0.950, 0.910, 1),
        0.10
    )

    hoof_mat = material(
        "Riverwatch V8 Hoof",
        (0.038, 0.028, 0.020, 1),
        0.79
    )

    leather = material(
        "Riverwatch V8 Leather",
        (0.075, 0.021, 0.009, 1),
        0.65
    )

    leather_mid = material(
        "Riverwatch V8 Warm Leather",
        (0.165, 0.058, 0.019, 1),
        0.61
    )

    leather_edge = material(
        "Riverwatch V8 Leather Edge",
        (0.270, 0.100, 0.032, 1),
        0.58
    )

    blanket = material(
        "Riverwatch V8 Royal Blanket",
        (0.025, 0.075, 0.230, 1),
        0.78
    )

    brass = material(
        "Riverwatch V8 Brass",
        (0.570, 0.330, 0.072, 1),
        0.30,
        0.76
    )

    iron = material(
        "Riverwatch V8 Iron",
        (0.045, 0.048, 0.055, 1),
        0.38,
        0.72
    )

    # ========================================================
    # HELPERS
    # ========================================================

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

    def apply_subdivision(
        obj,
        levels=1
    ):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(True)

        modifier = obj.modifiers.new(
            "HorseOrganicSubdivision",
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

        obj.select_set(True)

        modifier = obj.modifiers.new(
            "HorseDetailBevel",
            "BEVEL"
        )

        modifier.width = width
        modifier.segments = segments

        bpy.ops.object.modifier_apply(
            modifier=modifier.name
        )

        return obj

    # ========================================================
    # TRUE 3D SWEPT TUBE
    #
    # Unlike the V7 loft, every ring here is perpendicular to
    # the local direction of the path.
    #
    # This is what fixes the flat-leg problem.
    #
    # sections:
    # (
    #     x,
    #     y,
    #     z,
    #     lateral_radius,
    #     depth_radius
    # )
    # ========================================================

    def build_swept_tube(
        name,
        sections,
        mat,
        weights,
        rings=28,
        subdivision=1
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

            if section_index == 0:
                tangent = (
                    centers[1]
                    - centers[0]
                )

            elif section_index == len(sections) - 1:
                tangent = (
                    centers[-1]
                    - centers[-2]
                )

            else:
                tangent = (
                    centers[section_index + 1]
                    - centers[section_index - 1]
                )

            if tangent.length < 0.00001:
                tangent = Vector(
                    (
                        0.0,
                        0.0,
                        1.0
                    )
                )

            tangent.normalize()

            # Keep lateral direction stable in world X,
            # projected into the ring plane.

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
                * lateral.dot(tangent)
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
                    * lateral.dot(tangent)
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

            radius_lateral = section[3]
            radius_depth = section[4]

            for ring_index in range(rings):
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
                        * radius_lateral
                    )
                    + depth
                    * (
                        math.sin(angle)
                        * radius_depth
                    )
                )

                verts.append(
                    (
                        point.x,
                        point.y,
                        point.z
                    )
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

        start_center_index = len(
            verts
        )

        verts.append(
            (
                centers[0].x,
                centers[0].y,
                centers[0].z
            )
        )

        end_center_index = len(
            verts
        )

        verts.append(
            (
                centers[-1].x,
                centers[-1].y,
                centers[-1].z
            )
        )

        for ring_index in range(rings):
            next_ring = (
                ring_index + 1
            ) % rings

            faces.append(
                (
                    start_center_index,
                    ring_index,
                    next_ring,
                )
            )

            last_start = (
                len(sections) - 1
            ) * rings

            faces.append(
                (
                    end_center_index,
                    last_start + next_ring,
                    last_start + ring_index,
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

        group_names = []

        for weight_map in weights:
            for group_name in weight_map.keys():
                if group_name not in group_names:
                    group_names.append(
                        group_name
                    )

        groups = {}

        for group_name in group_names:
            groups[group_name] = (
                obj.vertex_groups.new(
                    name=group_name
                )
            )

        for section_index, weight_map in enumerate(
            weights
        ):
            first_vertex = (
                section_index
                * rings
            )

            section_vertices = list(
                range(
                    first_vertex,
                    first_vertex + rings
                )
            )

            for group_name, weight in weight_map.items():
                groups[group_name].add(
                    section_vertices,
                    weight,
                    "REPLACE"
                )

        for group_name, weight in weights[0].items():
            groups[group_name].add(
                [start_center_index],
                weight,
                "REPLACE"
            )

        for group_name, weight in weights[-1].items():
            groups[group_name].add(
                [end_center_index],
                weight,
                "REPLACE"
            )

        if subdivision > 0:
            apply_subdivision(
                obj,
                subdivision
            )

        smooth(obj)

        armature_bind(obj)

        return obj

    # ========================================================
    # CONTINUOUS BODY / NECK / HEAD
    # ========================================================

    def build_core():

        # y, center_z, width, height

        sections = [
            # Rounded tail-root / croup end.
            (1.100, 1.425, 0.050, 0.060),
            (1.055, 1.425, 0.125, 0.145),
            (0.990, 1.425, 0.240, 0.265),

            # Croup.
            (0.900, 1.420, 0.365, 0.375),
            (0.790, 1.410, 0.465, 0.440),
            (0.660, 1.400, 0.525, 0.465),
            (0.510, 1.390, 0.545, 0.465),

            # Barrel / flank.
            (0.330, 1.370, 0.535, 0.435),
            (0.140, 1.360, 0.525, 0.425),
            (-0.050, 1.365, 0.515, 0.430),

            # Chest.
            (-0.230, 1.390, 0.500, 0.450),
            (-0.390, 1.435, 0.470, 0.470),

            # Withers.
            (-0.530, 1.510, 0.410, 0.430),

            # Neck.
            (-0.655, 1.590, 0.350, 0.365),
            (-0.770, 1.665, 0.305, 0.320),
            (-0.875, 1.730, 0.265, 0.280),
            (-0.975, 1.785, 0.235, 0.250),

            # Poll.
            (-1.075, 1.825, 0.215, 0.230),

            # Skull.
            (-1.170, 1.825, 0.220, 0.225),
            (-1.270, 1.805, 0.220, 0.215),
            (-1.370, 1.770, 0.210, 0.200),

            # Cheek / jaw.
            (-1.470, 1.730, 0.200, 0.180),

            # Face.
            (-1.565, 1.695, 0.185, 0.155),
            (-1.655, 1.675, 0.160, 0.125),

            # Muzzle.
            (-1.735, 1.665, 0.130, 0.095),
            (-1.795, 1.662, 0.080, 0.060),
            (-1.830, 1.662, 0.030, 0.025),
        ]

        rings = 64
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

                cosine = math.cos(
                    angle
                )

                sine = math.sin(
                    angle
                )

                vertical = sine

                # Flatter topline.
                if vertical >= 0.0:
                    vertical = (
                        vertical ** 0.84
                    )

                # Firm belly rather than giant round blob.
                else:
                    vertical = -(
                        (-vertical) ** 1.04
                    )

                x = (
                    width
                    * cosine
                )

                z = (
                    center_z
                    + height
                    * vertical
                )

                # --------------------------
                # CROUP / HINDQUARTER
                # --------------------------

                croup = math.exp(
                    -(
                        (
                            y - 0.64
                        )
                        / 0.30
                    ) ** 2
                )

                x *= (
                    1.0
                    + 0.075
                    * croup
                    * (
                        1.0
                        - abs(sine)
                    )
                )

                if sine > 0.0:
                    z += (
                        0.060
                        * croup
                        * sine
                    )

                # --------------------------
                # SHOULDER
                # --------------------------

                shoulder = math.exp(
                    -(
                        (
                            y + 0.35
                        )
                        / 0.22
                    ) ** 2
                )

                x *= (
                    1.0
                    + 0.070
                    * shoulder
                    * (
                        1.0
                        - abs(sine)
                    )
                )

                # --------------------------
                # WITHERS
                # --------------------------

                withers = math.exp(
                    -(
                        (
                            y + 0.52
                        )
                        / 0.17
                    ) ** 2
                )

                if sine > 0.20:
                    z += (
                        0.075
                        * withers
                        * sine
                    )

                # --------------------------
                # FLANK TUCK
                # --------------------------

                flank = math.exp(
                    -(
                        (
                            y - 0.35
                        )
                        / 0.19
                    ) ** 2
                )

                if sine < 0.0:
                    z += (
                        0.065
                        * flank
                        * (-sine)
                    )

                # --------------------------
                # NECK CREST
                # --------------------------

                neck_crest = math.exp(
                    -(
                        (
                            y + 0.82
                        )
                        / 0.26
                    ) ** 2
                )

                if sine > 0.0:
                    z += (
                        0.045
                        * neck_crest
                        * sine
                    )

                # --------------------------
                # JAW
                # --------------------------

                jaw = math.exp(
                    -(
                        (
                            y + 1.40
                        )
                        / 0.19
                    ) ** 2
                )

                if sine < 0.0:
                    z -= (
                        0.030
                        * jaw
                        * (-sine)
                    )

                if (
                    abs(sine) < 0.70
                    and jaw > 0.05
                ):
                    x *= (
                        1.0
                        + 0.055
                        * jaw
                    )

                verts.append(
                    (
                        x,
                        y,
                        z
                    )
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

        rear_center = len(
            verts
        )

        verts.append(
            (
                0.0,
                sections[0][0],
                sections[0][1]
            )
        )

        nose_center = len(
            verts
        )

        verts.append(
            (
                0.0,
                sections[-1][0],
                sections[-1][1]
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
                    next_ring
                )
            )

            last_start = (
                len(sections) - 1
            ) * rings

            faces.append(
                (
                    nose_center,
                    last_start + next_ring,
                    last_start + ring_index
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV8CoreMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV8Core",
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

            if y >= -0.68:
                body_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -0.88:
                blend = (
                    (-0.68 - y)
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

            elif y >= -1.08:
                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y > -1.22:
                blend = (
                    (-1.08 - y)
                    / 0.14
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

        apply_subdivision(
            obj,
            1
        )

        smooth(
            obj
        )

        armature_bind(
            obj
        )

        return obj

    build_core()

    # ========================================================
    # FRONT LIMBS
    #
    # Horse-like proportions:
    #
    # muscular upper limb
    # narrower forearm
    # distinct knee
    # narrower cannon
    # wider fetlock
    # angled pastern
    #
    # The important part is that all of this is ROUND in 3D.
    # ========================================================

    def front_sections(
        side
    ):
        x = (
            0.285
            * side
        )

        return [
            # shoulder merge
            (
                x,
                -0.420,
                1.175,
                0.165,
                0.145
            ),

            # upper forelimb
            (
                x,
                -0.440,
                1.035,
                0.150,
                0.132
            ),

            (
                x,
                -0.458,
                0.880,
                0.135,
                0.118
            ),

            (
                x,
                -0.472,
                0.730,
                0.118,
                0.105
            ),

            # knee
            (
                x,
                -0.483,
                0.610,
                0.125,
                0.112
            ),

            # upper cannon
            (
                x,
                -0.493,
                0.510,
                0.090,
                0.078
            ),

            # cannon
            (
                x,
                -0.505,
                0.390,
                0.080,
                0.071
            ),

            (
                x,
                -0.518,
                0.275,
                0.077,
                0.069
            ),

            # fetlock
            (
                x,
                -0.533,
                0.195,
                0.100,
                0.090
            ),

            # pastern
            (
                x,
                -0.558,
                0.125,
                0.087,
                0.080
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
                prefix + ".upper": 0.45,
                prefix + ".lower": 0.55
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

    build_swept_tube(
        "RiverwatchV8FrontLeftLeg",
        front_sections(-1),
        coat,
        front_weights(
            "front.L"
        ),
        rings=28,
        subdivision=1
    )

    build_swept_tube(
        "RiverwatchV8FrontRightLeg",
        front_sections(1),
        coat,
        front_weights(
            "front.R"
        ),
        rings=28,
        subdivision=1
    )

    # ========================================================
    # HIND LIMBS
    #
    # Notice the actual S-shaped centerline:
    #
    # hip -> stifle forward
    #     -> hock backward
    #     -> cannon forward/down
    #
    # This is substantially more horse-like than a straight
    # post.
    # ========================================================

    def hind_sections(
        side
    ):
        x = (
            0.305
            * side
        )

        return [
            # hip / thigh merge
            (
                x,
                0.500,
                1.180,
                0.190,
                0.170
            ),

            # thigh
            (
                x,
                0.455,
                1.045,
                0.180,
                0.160
            ),

            # stifle moves forward
            (
                x,
                0.380,
                0.905,
                0.160,
                0.145
            ),

            # gaskin
            (
                x,
                0.410,
                0.765,
                0.138,
                0.125
            ),

            # upper hock shifts backward
            (
                x,
                0.535,
                0.655,
                0.125,
                0.115
            ),

            # hock
            (
                x,
                0.635,
                0.575,
                0.135,
                0.123
            ),

            # cannon
            (
                x,
                0.610,
                0.470,
                0.088,
                0.080
            ),

            (
                x,
                0.580,
                0.355,
                0.080,
                0.073
            ),

            (
                x,
                0.550,
                0.260,
                0.078,
                0.071
            ),

            # fetlock
            (
                x,
                0.520,
                0.190,
                0.102,
                0.092
            ),

            # pastern
            (
                x,
                0.495,
                0.125,
                0.088,
                0.080
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
                prefix + ".lower": 1.0
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

    build_swept_tube(
        "RiverwatchV8HindLeftLeg",
        hind_sections(-1),
        coat,
        hind_weights(
            "hind.L"
        ),
        rings=28,
        subdivision=1
    )

    build_swept_tube(
        "RiverwatchV8HindRightLeg",
        hind_sections(1),
        coat,
        hind_weights(
            "hind.R"
        ),
        rings=28,
        subdivision=1
    )

    # ========================================================
    # HOOF WEDGES
    # ========================================================

    def build_hoof(
        name,
        x,
        y,
        bone,
        width=0.125,
        length=0.225
    ):
        top_width = (
            width
            * 0.76
        )

        top_length = (
            length
            * 0.75
        )

        verts = [
            (
                x - top_width,
                y + top_length * 0.38,
                0.130
            ),
            (
                x + top_width,
                y + top_length * 0.38,
                0.130
            ),
            (
                x + top_width * 1.03,
                y - top_length * 0.62,
                0.120
            ),
            (
                x - top_width * 1.03,
                y - top_length * 0.62,
                0.120
            ),

            (
                x - width,
                y + length * 0.40,
                0.028
            ),
            (
                x + width,
                y + length * 0.40,
                0.028
            ),
            (
                x + width * 1.08,
                y - length * 0.60,
                0.028
            ),
            (
                x - width * 1.08,
                y - length * 0.60,
                0.028
            ),
        ]

        faces = [
            (
                0,
                1,
                2,
                3
            ),
            (
                4,
                7,
                6,
                5
            ),
            (
                0,
                4,
                5,
                1
            ),
            (
                1,
                5,
                6,
                2
            ),
            (
                2,
                6,
                7,
                3
            ),
            (
                3,
                7,
                4,
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
            hoof_mat
        )

        rigid_group(
            obj,
            bone
        )

        apply_bevel(
            obj,
            0.018,
            3
        )

        smooth(
            obj
        )

        return obj

    build_hoof(
        "RiverwatchV8FrontLeftHoof",
        -0.285,
        -0.570,
        "front.L.hoof",
        0.120,
        0.225
    )

    build_hoof(
        "RiverwatchV8FrontRightHoof",
        0.285,
        -0.570,
        "front.R.hoof",
        0.120,
        0.225
    )

    build_hoof(
        "RiverwatchV8HindLeftHoof",
        -0.305,
        0.485,
        "hind.L.hoof",
        0.125,
        0.235
    )

    build_hoof(
        "RiverwatchV8HindRightHoof",
        0.305,
        0.485,
        "hind.R.hoof",
        0.125,
        0.235
    )

    # ========================================================
    # MANE
    #
    # Continuous curtain with irregular lower edge.
    # No collection of ball-shaped locks.
    # ========================================================

    def build_mane():
        stations = [
            (-1.145, 2.015, 1.900),
            (-1.095, 2.010, 1.865),
            (-1.040, 1.995, 1.830),
            (-0.980, 1.970, 1.780),
            (-0.915, 1.935, 1.735),
            (-0.850, 1.895, 1.680),
            (-0.780, 1.845, 1.635),
            (-0.710, 1.790, 1.580),
            (-0.640, 1.730, 1.545),
            (-0.575, 1.675, 1.505),
            (-0.520, 1.630, 1.490),
        ]

        verts = []
        faces = []

        thickness = 0.018

        for index, station in enumerate(
            stations
        ):
            y = station[0]
            root_z = station[1]
            tip_z = station[2]

            irregular = (
                0.018
                * math.sin(
                    float(index)
                    * 1.70
                )
            )

            tip_x = (
                -0.120
                + irregular
            )

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
                index
                * 4
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
            "RiverwatchV8ManeMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV8Mane",
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
            if vertex.co.y < -1.06:
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

        armature_bind(
            obj
        )

    build_mane()

    # Forelock.
    horse_cylinder(
        "RiverwatchV8Forelock",
        (
            0.0,
            -1.145,
            2.015
        ),
        (
            -0.045,
            -1.335,
            1.865
        ),
        0.023,
        mane_mat,
        arm,
        "head",
        0.008
    )

    # ========================================================
    # TRUE 3D TAIL
    #
    # Same swept-tube solution as the legs.
    # This prevents the tail from becoming a flat loft.
    # ========================================================

    tail_sections = [
        (
            0.000,
            0.995,
            1.430,
            0.075,
            0.070
        ),
        (
            0.000,
            1.075,
            1.365,
            0.105,
            0.095
        ),
        (
            -0.005,
            1.170,
            1.275,
            0.135,
            0.115
        ),
        (
            -0.010,
            1.280,
            1.155,
            0.155,
            0.130
        ),
        (
            0.000,
            1.390,
            1.010,
            0.165,
            0.135
        ),
        (
            0.012,
            1.500,
            0.850,
            0.160,
            0.130
        ),
        (
            0.010,
            1.600,
            0.700,
            0.145,
            0.115
        ),
        (
            -0.005,
            1.685,
            0.570,
            0.115,
            0.095
        ),
        (
            -0.018,
            1.745,
            0.465,
            0.075,
            0.065
        ),
        (
            -0.020,
            1.775,
            0.395,
            0.035,
            0.032
        ),
    ]

    tail_weights = [
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
            "tail.1": 0.65,
            "tail.2": 0.35
        },
        {
            "tail.1": 0.35,
            "tail.2": 0.65
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

    build_swept_tube(
        "RiverwatchV8Tail",
        tail_sections,
        mane_mat,
        tail_weights,
        rings=28,
        subdivision=1
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
                sx * 0.058,
                -1.100,
                1.985
            ),
            (
                sx * 0.142,
                -1.095,
                1.985
            ),
            (
                sx * 0.120,
                -1.070,
                2.190
            ),

            (
                sx * 0.068,
                -1.030,
                1.995
            ),
            (
                sx * 0.135,
                -1.025,
                1.995
            ),
            (
                sx * 0.116,
                -1.018,
                2.170
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

        rigid_group(
            obj,
            "head"
        )

        apply_subdivision(
            obj,
            1
        )

        smooth(
            obj
        )

    build_ear(
        "RiverwatchV8LeftEar",
        -1
    )

    build_ear(
        "RiverwatchV8RightEar",
        1
    )

    # ========================================================
    # FACE
    # ========================================================

    horse_sphere(
        "RiverwatchV8MuzzlePatch",
        (
            0.0,
            -1.730,
            1.660
        ),
        (
            0.140,
            0.090,
            0.068
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
            "RiverwatchV8Eye",
            (
                side * 0.202,
                -1.280,
                1.885
            ),
            (
                0.030,
                0.020,
                0.030
            ),
            eye_mat,
            arm,
            "head",
            18,
            12
        )

        horse_sphere(
            "RiverwatchV8Pupil",
            (
                side * 0.222,
                -1.294,
                1.885
            ),
            (
                0.012,
                0.008,
                0.019
            ),
            pupil_mat,
            arm,
            "head",
            14,
            10
        )

        horse_sphere(
            "RiverwatchV8EyeGlint",
            (
                side * 0.233,
                -1.300,
                1.898
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
            "RiverwatchV8Nostril",
            (
                side * 0.085,
                -1.795,
                1.667
            ),
            (
                0.022,
                0.013,
                0.016
            ),
            coat_dark,
            arm,
            "head",
            14,
            10
        )

    # Narrow natural blaze.
    horse_cylinder(
        "RiverwatchV8BlazeUpper",
        (
            0.0,
            -1.155,
            1.990
        ),
        (
            0.0,
            -1.430,
            1.805
        ),
        0.021,
        ivory,
        arm,
        "head",
        0.014
    )

    horse_cylinder(
        "RiverwatchV8BlazeLower",
        (
            0.0,
            -1.430,
            1.805
        ),
        (
            0.0,
            -1.615,
            1.705
        ),
        0.014,
        ivory,
        arm,
        "head",
        0.007
    )

    # ========================================================
    # SMALL FITTED BLANKET
    # ========================================================

    def build_blanket():
        x_values = [
            -0.370,
            -0.245,
            -0.120,
            0.000,
            0.120,
            0.245,
            0.370,
        ]

        y_values = [
            -0.350,
            -0.175,
            0.000,
            0.175,
            0.350,
        ]

        verts = []
        faces = []

        top_count = (
            len(x_values)
            * len(y_values)
        )

        for layer in range(2):
            for y in y_values:
                for x in x_values:
                    side = (
                        abs(x)
                        / 0.370
                    )

                    front_rear = (
                        abs(y)
                        / 0.350
                    )

                    z = (
                        1.785
                        - 0.135
                        * (
                            side ** 1.55
                        )
                        - 0.010
                        * front_rear
                        - float(layer)
                        * 0.020
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
                        + yi
                        * width
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

        # Left/right perimeter.
        for yi in range(
            height - 1
        ):
            a = yi * width
            b = (
                yi + 1
            ) * width

            faces.append(
                (
                    a,
                    top_count + a,
                    top_count + b,
                    b
                )
            )

            a = (
                yi * width
                + width - 1
            )

            b = (
                (
                    yi + 1
                )
                * width
                + width - 1
            )

            faces.append(
                (
                    a,
                    b,
                    top_count + b,
                    top_count + a
                )
            )

        # Front/back perimeter.
        for xi in range(
            width - 1
        ):
            a = xi
            b = xi + 1

            faces.append(
                (
                    a,
                    b,
                    top_count + b,
                    top_count + a
                )
            )

            a = (
                (
                    height - 1
                )
                * width
                + xi
            )

            b = a + 1

            faces.append(
                (
                    a,
                    top_count + a,
                    top_count + b,
                    b
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV8BlanketMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV8Blanket",
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

        smooth(
            obj
        )

    build_blanket()

    # ========================================================
    # CUSTOM LOWER-PROFILE SADDLE
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

        top_count = (
            len(x_values)
            * len(y_values)
        )

        for layer in range(2):
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
                        1.815
                        + 0.020
                        * (
                            side ** 1.6
                        )
                        + 0.030
                        * (
                            end ** 1.8
                        )
                        - float(layer)
                        * 0.055
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
                        + yi
                        * width
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

        # Perimeter.
        for yi in range(
            height - 1
        ):
            a = (
                yi
                * width
            )

            b = (
                (
                    yi + 1
                )
                * width
            )

            faces.append(
                (
                    a,
                    top_count + a,
                    top_count + b,
                    b
                )
            )

            a = (
                yi
                * width
                + width - 1
            )

            b = (
                (
                    yi + 1
                )
                * width
                + width - 1
            )

            faces.append(
                (
                    a,
                    b,
                    top_count + b,
                    top_count + a
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV8SaddleSeatMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV8SaddleSeat",
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

        apply_bevel(
            obj,
            0.014,
            3
        )

        smooth(
            obj
        )

    build_saddle_seat()

    # ========================================================
    # POMMEL / CANTLE ARCHES
    # ========================================================

    def build_saddle_arch(
        name,
        y_center,
        half_width,
        base_z,
        height,
        depth
    ):
        samples = 11

        verts = []
        faces = []

        for depth_side in (
            -0.5,
            0.5
        ):
            y = (
                y_center
                + depth
                * depth_side
            )

            for index in range(samples):
                t = (
                    float(index)
                    / float(
                        samples - 1
                    )
                )

                x = (
                    -half_width
                    + 2.0
                    * half_width
                    * t
                )

                normalized = (
                    x
                    / half_width
                )

                arch = (
                    max(
                        0.0,
                        1.0
                        - normalized
                        * normalized
                    ) ** 0.65
                )

                verts.append(
                    (
                        x,
                        y,
                        base_z
                        + height
                        * arch
                    )
                )

        lower_start = len(
            verts
        )

        for depth_side in (
            -0.5,
            0.5
        ):
            y = (
                y_center
                + depth
                * depth_side
            )

            for index in range(samples):
                t = (
                    float(index)
                    / float(
                        samples - 1
                    )
                )

                x = (
                    -half_width
                    + 2.0
                    * half_width
                    * t
                )

                verts.append(
                    (
                        x,
                        y,
                        base_z - 0.025
                    )
                )

        for surface in range(2):
            upper = (
                surface
                * samples
            )

            lower = (
                lower_start
                + surface
                * samples
            )

            for index in range(
                samples - 1
            ):
                faces.append(
                    (
                        upper + index,
                        upper + index + 1,
                        lower + index + 1,
                        lower + index
                    )
                )

        for index in range(
            samples - 1
        ):
            faces.append(
                (
                    index,
                    samples + index,
                    samples + index + 1,
                    index + 1
                )
            )

            a = (
                lower_start
                + index
            )

            b = (
                lower_start
                + samples
                + index
            )

            faces.append(
                (
                    a,
                    a + 1,
                    b + 1,
                    b
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
            leather_edge
        )

        rigid_group(
            obj,
            "body"
        )

        apply_bevel(
            obj,
            0.010,
            2
        )

        smooth(
            obj
        )

    build_saddle_arch(
        "RiverwatchV8Pommel",
        -0.245,
        0.225,
        1.835,
        0.105,
        0.080
    )

    build_saddle_arch(
        "RiverwatchV8Cantle",
        0.245,
        0.245,
        1.838,
        0.135,
        0.090
    )

    # ========================================================
    # SADDLE FLAPS
    # ========================================================

    def build_flap(
        name,
        side
    ):
        outer_x = (
            side
            * 0.300
        )

        inner_x = (
            side
            * 0.278
        )

        outline = [
            (
                -0.210,
                1.750
            ),
            (
                -0.115,
                1.635
            ),
            (
                0.045,
                1.525
            ),
            (
                0.200,
                1.500
            ),
            (
                0.235,
                1.590
            ),
            (
                0.135,
                1.700
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

        for index in range(count):
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
            leather_mid
        )

        rigid_group(
            obj,
            "body"
        )

        apply_bevel(
            obj,
            0.012,
            3
        )

        smooth(
            obj
        )

    build_flap(
        "RiverwatchV8LeftSaddleFlap",
        -1
    )

    build_flap(
        "RiverwatchV8RightSaddleFlap",
        1
    )

    # ========================================================
    # GIRTH / STIRRUPS
    # ========================================================

    girth = torus(
        "RiverwatchV8Girth",
        (
            0.0,
            0.0,
            1.350
        ),
        0.415,
        0.022,
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

    for side in (
        -1,
        1
    ):
        horse_cylinder(
            "RiverwatchV8StirrupLeather",
            (
                side * 0.225,
                0.0,
                1.800
            ),
            (
                side * 0.400,
                0.0,
                1.075
            ),
            0.009,
            leather,
            arm,
            "body"
        )

        stirrup = torus(
            "RiverwatchV8Stirrup",
            (
                side * 0.410,
                0.0,
                1.005
            ),
            0.085,
            0.014,
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
    # SIMPLE CLEAN BRIDLE
    # ========================================================

    noseband = torus(
        "RiverwatchV8NoseBand",
        (
            0.0,
            -1.560,
            1.685
        ),
        0.165,
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
        "RiverwatchV8BrowBand",
        (
            -0.165,
            -1.160,
            1.950
        ),
        (
            0.165,
            -1.160,
            1.950
        ),
        0.010,
        leather_mid,
        arm,
        "head"
    )

    horse_cylinder(
        "RiverwatchV8Bit",
        (
            -0.165,
            -1.610,
            1.628
        ),
        (
            0.165,
            -1.610,
            1.628
        ),
        0.009,
        iron,
        arm,
        "head"
    )

    for side in (
        -1,
        1
    ):
        horse_cylinder(
            "RiverwatchV8CheekPiece",
            (
                side * 0.160,
                -1.155,
                1.945
            ),
            (
                side * 0.170,
                -1.550,
                1.680
            ),
            0.008,
            leather,
            arm,
            "head"
        )

        bit_ring = torus(
            "RiverwatchV8BitRing",
            (
                side * 0.175,
                -1.615,
                1.628
            ),
            0.034,
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

        horse_cylinder(
            "RiverwatchV8Rein",
            (
                side * 0.175,
                -1.615,
                1.628
            ),
            (
                side * 0.225,
                -0.205,
                1.700
            ),
            0.006,
            leather,
            arm,
            "head"
        )

    # ========================================================
    # METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "anatomy_v8"

    arm[
        "broken_knight_horse_authoring"
    ] = "blender"

    arm[
        "broken_knight_horse_leg_topology"
    ] = "true_3d_perpendicular_sweep"

    arm[
        "broken_knight_horse_flat_legs"
    ] = False

    arm[
        "broken_knight_horse_body"
    ] = "shallower_anatomical_barrel"

    arm[
        "broken_knight_horse_hind_leg"
    ] = "stifle_hock_cannon_centerline"

    arm[
        "broken_knight_horse_tail"
    ] = "true_3d_continuous_sweep"

    arm[
        "broken_knight_horse_tack"
    ] = "small_fitted_medieval_saddle"

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