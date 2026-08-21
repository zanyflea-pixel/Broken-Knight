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
    # BROKEN KNIGHT - RIVERWATCH HORSE V9
    #
    # NEW MODELING APPROACH:
    #
    # Body / chest / croup / neck / head are created from
    # overlapping sculpt forms and VOXEL REMESHED into ONE
    # continuous anatomical surface.
    #
    # V8's true 3D swept-leg solution is retained and refined.
    # ========================================================

    coat = material(
        "Riverwatch V9 Bay",
        (0.300, 0.085, 0.022, 1),
        0.56
    )

    coat_dark = material(
        "Riverwatch V9 Bay Dark",
        (0.065, 0.016, 0.006, 1),
        0.70
    )

    muzzle_mat = material(
        "Riverwatch V9 Muzzle",
        (0.160, 0.098, 0.076, 1),
        0.74
    )

    ivory = material(
        "Riverwatch V9 Ivory",
        (0.810, 0.775, 0.700, 1),
        0.79
    )

    mane_mat = material(
        "Riverwatch V9 Mane",
        (0.012, 0.008, 0.006, 1),
        0.68
    )

    hoof_mat = material(
        "Riverwatch V9 Hoof",
        (0.038, 0.028, 0.020, 1),
        0.79
    )

    eye_mat = material(
        "Riverwatch V9 Eye",
        (0.055, 0.018, 0.006, 1),
        0.17
    )

    pupil_mat = material(
        "Riverwatch V9 Pupil",
        (0.002, 0.002, 0.002, 1),
        0.10
    )

    glint_mat = material(
        "Riverwatch V9 Eye Glint",
        (0.960, 0.950, 0.910, 1),
        0.10
    )

    leather = material(
        "Riverwatch V9 Leather",
        (0.072, 0.020, 0.009, 1),
        0.65
    )

    leather_mid = material(
        "Riverwatch V9 Warm Leather",
        (0.165, 0.058, 0.019, 1),
        0.61
    )

    leather_edge = material(
        "Riverwatch V9 Leather Edge",
        (0.270, 0.100, 0.032, 1),
        0.58
    )

    blanket = material(
        "Riverwatch V9 Royal Blanket",
        (0.025, 0.075, 0.230, 1),
        0.78
    )

    iron = material(
        "Riverwatch V9 Iron",
        (0.045, 0.048, 0.055, 1),
        0.38,
        0.72
    )

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

    def apply_smooth(
        obj,
        factor=0.30,
        iterations=3
    ):
        bpy.context.view_layer.objects.active = obj

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        obj.select_set(True)

        modifier = obj.modifiers.new(
            "HorseSculptSmooth",
            "SMOOTH"
        )

        modifier.factor = factor
        modifier.iterations = iterations

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
    # ANATOMICAL SCULPT FORM
    # ========================================================

    def ellipsoid(
        name,
        location,
        scale,
        rotation=(0.0, 0.0, 0.0)
    ):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=32,
            ring_count=20,
            location=location,
            rotation=rotation
        )

        obj = bpy.context.object
        obj.name = name
        obj.scale = scale

        bpy.ops.object.transform_apply(
            location=False,
            rotation=True,
            scale=True
        )

        obj.data.materials.append(
            coat
        )

        smooth(obj)

        return obj

    # ========================================================
    # FUSED BODY / NECK / HEAD
    # ========================================================

    def build_fused_core():
        parts = []

        # Main rib cage.
        parts.append(
            ellipsoid(
                "V9Barrel",
                (0.0, 0.03, 1.39),
                (0.50, 0.76, 0.40)
            )
        )

        # Chest / shoulder.
        parts.append(
            ellipsoid(
                "V9Chest",
                (0.0, -0.39, 1.44),
                (0.46, 0.38, 0.45)
            )
        )

        # Croup / hindquarter.
        parts.append(
            ellipsoid(
                "V9Croup",
                (0.0, 0.56, 1.44),
                (0.52, 0.43, 0.46)
            )
        )

        # Withers.
        parts.append(
            ellipsoid(
                "V9Withers",
                (0.0, -0.50, 1.62),
                (0.35, 0.27, 0.31)
            )
        )

        # Lower neck.
        parts.append(
            ellipsoid(
                "V9NeckLower",
                (0.0, -0.69, 1.66),
                (0.30, 0.45, 0.27),
                (-0.50, 0.0, 0.0)
            )
        )

        # Upper neck.
        parts.append(
            ellipsoid(
                "V9NeckUpper",
                (0.0, -0.91, 1.79),
                (0.255, 0.37, 0.235),
                (-0.47, 0.0, 0.0)
            )
        )

        # Poll.
        parts.append(
            ellipsoid(
                "V9Poll",
                (0.0, -1.07, 1.84),
                (0.22, 0.24, 0.22)
            )
        )

        # Skull.
        parts.append(
            ellipsoid(
                "V9Skull",
                (0.0, -1.24, 1.80),
                (0.215, 0.30, 0.205),
                (0.08, 0.0, 0.0)
            )
        )

        # Cheek and jaw.
        parts.append(
            ellipsoid(
                "V9Cheek",
                (0.0, -1.42, 1.74),
                (0.195, 0.25, 0.175),
                (0.10, 0.0, 0.0)
            )
        )

        # Nasal bridge.
        parts.append(
            ellipsoid(
                "V9Face",
                (0.0, -1.57, 1.70),
                (0.165, 0.24, 0.140),
                (0.10, 0.0, 0.0)
            )
        )

        # Muzzle.
        parts.append(
            ellipsoid(
                "V9MuzzleCore",
                (0.0, -1.72, 1.67),
                (0.145, 0.16, 0.110)
            )
        )

        bpy.ops.object.select_all(
            action="DESELECT"
        )

        for obj in parts:
            obj.select_set(True)

        bpy.context.view_layer.objects.active = parts[0]

        bpy.ops.object.join()

        core = bpy.context.object
        core.name = "RiverwatchV9FusedCore"

        # ----------------------------------------------------
        # THIS IS THE MAJOR V9 CHANGE.
        #
        # Actually fuse the forms into ONE manifold surface.
        # ----------------------------------------------------

        core.data.remesh_mode = "VOXEL"
        core.data.remesh_voxel_size = 0.035
        core.data.remesh_voxel_adaptivity = 0.0

        bpy.context.view_layer.objects.active = core

        result = bpy.ops.object.voxel_remesh()

        if "FINISHED" not in result:
            raise RuntimeError(
                "Horse V9 voxel remesh failed"
            )

        core.data.materials.clear()

        core.data.materials.append(
            coat
        )

        # ----------------------------------------------------
        # SHAPE THE RESULT AFTER FUSION.
        # ----------------------------------------------------

        for vertex in core.data.vertices:
            x = vertex.co.x
            y = vertex.co.y
            z = vertex.co.z

            # Tuck the belly behind the rib cage.
            flank = math.exp(
                -((y - 0.34) / 0.24) ** 2
            )

            side_center = max(
                0.0,
                1.0 - abs(x) / 0.55
            )

            if z < 1.34:
                vertex.co.z += (
                    0.070
                    * flank
                    * side_center
                )

            # Raise and define the withers.
            withers = math.exp(
                -((y + 0.47) / 0.16) ** 2
            )

            if z > 1.55:
                vertex.co.z += (
                    0.040
                    * withers
                    * side_center
                )

            # Give croup a gentle slope into tail root.
            if (
                y > 0.48
                and z > 1.55
            ):
                vertex.co.z -= (
                    0.025
                    * min(
                        1.0,
                        (y - 0.48) / 0.45
                    )
                )

            # Narrow the poll slightly.
            poll = math.exp(
                -((y + 1.02) / 0.16) ** 2
            )

            if abs(x) > 0.05:
                vertex.co.x *= (
                    1.0
                    - 0.055
                    * poll
                )

        apply_smooth(
            core,
            0.25,
            2
        )

        apply_subdivision(
            core,
            1
        )

        smooth(core)

        body_group = core.vertex_groups.new(
            name="body"
        )

        neck_group = core.vertex_groups.new(
            name="neck"
        )

        head_group = core.vertex_groups.new(
            name="head"
        )

        for vertex in core.data.vertices:
            y = vertex.co.y
            z = vertex.co.z

            if y <= -1.06:
                head_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif y < -0.90:
                blend = (
                    (-0.90 - y)
                    / 0.16
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

            elif (
                y < -0.48
                and z > 1.34
            ):
                neck_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

            elif (
                y < -0.36
                and z > 1.40
            ):
                blend = min(
                    1.0,
                    max(
                        0.0,
                        (-0.36 - y)
                        / 0.12
                    )
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

            else:
                body_group.add(
                    [vertex.index],
                    1.0,
                    "REPLACE"
                )

        armature_bind(core)

        return core

    build_fused_core()

    # ========================================================
    # TRUE 3D SWEPT LIMBS
    # ========================================================

    def build_swept_tube(
        name,
        sections,
        mat,
        weights,
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
                    (0.0, 0.0, 1.0)
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
                    (0.0, 1.0, 0.0)
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
                    (0.0, 1.0, 0.0)
                )

            depth.normalize()

            radius_x = section[3]
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
                        * radius_x
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
                        first + next_ring
                    )
                )

        start_center = len(verts)

        verts.append(
            tuple(
                centers[0]
            )
        )

        end_center = len(verts)

        verts.append(
            tuple(
                centers[-1]
            )
        )

        for ring_index in range(rings):
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
            mat
        )

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
                groups[group_name].add(
                    indices,
                    weight,
                    "REPLACE"
                )

        for group_name, weight in weights[0].items():
            groups[group_name].add(
                [start_center],
                weight,
                "REPLACE"
            )

        for group_name, weight in weights[-1].items():
            groups[group_name].add(
                [end_center],
                weight,
                "REPLACE"
            )

        apply_subdivision(
            obj,
            1
        )

        smooth(obj)

        armature_bind(obj)

        return obj

    # ========================================================
    # FRONT LEGS
    # ========================================================

    def front_sections(side):
        x = (
            0.270
            * side
        )

        return [
            # shoulder
            (x, -0.405, 1.205, 0.155, 0.140),

            # upper arm
            (x, -0.425, 1.070, 0.145, 0.128),

            # forearm
            (x, -0.445, 0.925, 0.128, 0.113),

            (x, -0.463, 0.780, 0.112, 0.100),

            # knee
            (x, -0.478, 0.650, 0.120, 0.108),

            (x, -0.486, 0.590, 0.116, 0.104),

            # cannon
            (x, -0.495, 0.490, 0.082, 0.072),

            (x, -0.505, 0.380, 0.074, 0.066),

            (x, -0.516, 0.275, 0.072, 0.064),

            # fetlock
            (x, -0.530, 0.195, 0.094, 0.084),

            # pastern
            (x, -0.555, 0.125, 0.080, 0.073),
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
                prefix + ".lower": 0.55,
                prefix + ".hoof": 0.45
            },

            {prefix + ".hoof": 1.0},
        ]

    build_swept_tube(
        "RiverwatchV9FrontLeftLeg",
        front_sections(-1),
        coat,
        front_weights(
            "front.L"
        )
    )

    build_swept_tube(
        "RiverwatchV9FrontRightLeg",
        front_sections(1),
        coat,
        front_weights(
            "front.R"
        )
    )

    # ========================================================
    # HIND LEGS
    #
    # More obvious horse-shaped stifle -> gaskin -> hock.
    # ========================================================

    def hind_sections(side):
        x = (
            0.290
            * side
        )

        return [
            # hip
            (x, 0.505, 1.205, 0.185, 0.165),

            # thigh
            (x, 0.455, 1.070, 0.175, 0.155),

            # stifle comes forward
            (x, 0.350, 0.920, 0.150, 0.138),

            # gaskin
            (x, 0.390, 0.775, 0.130, 0.118),

            # upper hock moves backward
            (x, 0.525, 0.655, 0.118, 0.108),

            # hock
            (x, 0.620, 0.575, 0.128, 0.115),

            # cannon
            (x, 0.595, 0.470, 0.084, 0.075),

            (x, 0.565, 0.360, 0.076, 0.068),

            (x, 0.535, 0.265, 0.074, 0.066),

            # fetlock
            (x, 0.505, 0.190, 0.096, 0.086),

            # pastern
            (x, 0.475, 0.125, 0.082, 0.074),
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
                prefix + ".lower": 0.55,
                prefix + ".hoof": 0.45
            },

            {prefix + ".hoof": 1.0},
        ]

    build_swept_tube(
        "RiverwatchV9HindLeftLeg",
        hind_sections(-1),
        coat,
        hind_weights(
            "hind.L"
        )
    )

    build_swept_tube(
        "RiverwatchV9HindRightLeg",
        hind_sections(1),
        coat,
        hind_weights(
            "hind.R"
        )
    )

    # ========================================================
    # ROUNDED 3D HOOVES
    #
    # No more box/wedge feet.
    # ========================================================

    def build_hoof(
        name,
        x,
        y,
        bone,
        width=0.120,
        length=0.220
    ):
        profiles = [
            (
                y + length * 0.22,
                0.110,
                width * 0.72,
                0.052
            ),

            (
                y + length * 0.04,
                0.082,
                width * 0.94,
                0.064
            ),

            (
                y - length * 0.28,
                0.066,
                width * 1.06,
                0.058
            ),

            (
                y - length * 0.52,
                0.052,
                width,
                0.045
            ),
        ]

        rings = 24

        verts = []
        faces = []

        for profile in profiles:
            py, center_z, rx, rz = profile

            for ring_index in range(rings):
                angle = (
                    math.tau
                    * float(ring_index)
                    / float(rings)
                )

                verts.append(
                    (
                        x
                        + math.cos(angle)
                        * rx,

                        py,

                        center_z
                        + math.sin(angle)
                        * rz
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

            for ring_index in range(rings):
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

        start_center = len(verts)

        verts.append(
            (
                x,
                profiles[0][0],
                profiles[0][1]
            )
        )

        end_center = len(verts)

        verts.append(
            (
                x,
                profiles[-1][0],
                profiles[-1][1]
            )
        )

        for ring_index in range(rings):
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

        rigid_group(
            obj,
            bone
        )

        apply_subdivision(
            obj,
            1
        )

        smooth(obj)

        return obj

    build_hoof(
        "RiverwatchV9FrontLeftHoof",
        -0.270,
        -0.575,
        "front.L.hoof",
        0.118,
        0.225
    )

    build_hoof(
        "RiverwatchV9FrontRightHoof",
        0.270,
        -0.575,
        "front.R.hoof",
        0.118,
        0.225
    )

    build_hoof(
        "RiverwatchV9HindLeftHoof",
        -0.290,
        0.455,
        "hind.L.hoof",
        0.122,
        0.235
    )

    build_hoof(
        "RiverwatchV9HindRightHoof",
        0.290,
        0.455,
        "hind.R.hoof",
        0.122,
        0.235
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
                1.970
            ),

            (
                sx * 0.135,
                -1.090,
                1.975
            ),

            (
                sx * 0.112,
                -1.065,
                2.170
            ),

            (
                sx * 0.064,
                -1.030,
                1.980
            ),

            (
                sx * 0.128,
                -1.025,
                1.985
            ),

            (
                sx * 0.108,
                -1.015,
                2.150
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

        apply_subdivision(
            obj,
            1
        )

        smooth(obj)

    build_ear(
        "RiverwatchV9LeftEar",
        -1
    )

    build_ear(
        "RiverwatchV9RightEar",
        1
    )

    # ========================================================
    # FACE
    # ========================================================

    horse_sphere(
        "RiverwatchV9MuzzlePatch",
        (
            0.0,
            -1.740,
            1.662
        ),
        (
            0.138,
            0.090,
            0.068
        ),
        muzzle_mat,
        arm,
        "head",
        22,
        14
    )

    for side in (-1, 1):

        horse_sphere(
            "RiverwatchV9Eye",
            (
                side * 0.202,
                -1.245,
                1.855
            ),
            (
                0.029,
                0.020,
                0.029
            ),
            eye_mat,
            arm,
            "head",
            18,
            12
        )

        horse_sphere(
            "RiverwatchV9Pupil",
            (
                side * 0.221,
                -1.258,
                1.855
            ),
            (
                0.011,
                0.008,
                0.018
            ),
            pupil_mat,
            arm,
            "head",
            14,
            10
        )

        horse_sphere(
            "RiverwatchV9EyeGlint",
            (
                side * 0.231,
                -1.264,
                1.867
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
            "RiverwatchV9Nostril",
            (
                side * 0.082,
                -1.800,
                1.667
            ),
            (
                0.021,
                0.013,
                0.016
            ),
            coat_dark,
            arm,
            "head",
            14,
            10
        )

    # Narrow face marking.
    horse_cylinder(
        "RiverwatchV9BlazeUpper",
        (
            0.0,
            -1.115,
            1.960
        ),
        (
            0.0,
            -1.410,
            1.790
        ),
        0.019,
        ivory,
        arm,
        "head",
        0.012
    )

    horse_cylinder(
        "RiverwatchV9BlazeLower",
        (
            0.0,
            -1.410,
            1.790
        ),
        (
            0.0,
            -1.605,
            1.700
        ),
        0.012,
        ivory,
        arm,
        "head",
        0.006
    )

    # ========================================================
    # MANE
    #
    # Full mane on one side with a smaller opposite-side layer
    # so it does not disappear from half the camera angles.
    # ========================================================

    def build_mane_sheet(
        name,
        side,
        drop_scale
    ):
        stations = [
            (-1.060, 2.020, 1.915),
            (-1.000, 2.000, 1.875),
            (-0.935, 1.965, 1.825),
            (-0.870, 1.920, 1.770),
            (-0.800, 1.870, 1.715),
            (-0.730, 1.815, 1.660),
            (-0.660, 1.760, 1.610),
            (-0.590, 1.700, 1.565),
            (-0.530, 1.650, 1.530),
        ]

        verts = []
        faces = []

        root_offset = (
            0.012
            * side
        )

        thickness = 0.016

        for index, station in enumerate(
            stations
        ):
            y, root_z, tip_z = station

            wave = (
                0.014
                * math.sin(
                    index * 1.55
                )
            )

            tip_x = (
                side
                * (
                    0.105
                    * drop_scale
                )
                + wave
            )

            verts.extend(
                [
                    (
                        root_offset - thickness,
                        y,
                        root_z
                    ),

                    (
                        root_offset + thickness,
                        y,
                        root_z
                    ),

                    (
                        tip_x - thickness,
                        y + 0.018,
                        tip_z
                    ),

                    (
                        tip_x + thickness,
                        y + 0.018,
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

        neck_group = obj.vertex_groups.new(
            name="neck"
        )

        head_group = obj.vertex_groups.new(
            name="head"
        )

        for vertex in obj.data.vertices:

            if vertex.co.y < -0.98:
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

        smooth(obj)

        armature_bind(obj)

    build_mane_sheet(
        "RiverwatchV9ManeLeft",
        -1,
        1.0
    )

    build_mane_sheet(
        "RiverwatchV9ManeRight",
        1,
        0.48
    )

    horse_cylinder(
        "RiverwatchV9Forelock",
        (
            0.0,
            -1.075,
            2.020
        ),
        (
            -0.045,
            -1.290,
            1.860
        ),
        0.022,
        mane_mat,
        arm,
        "head",
        0.008
    )

    # ========================================================
    # FLATTER / HAIR-LIKE TAIL
    #
    # The V8 tail was still too round and sausage-like.
    # This one spreads sideways like a mass of hair.
    # ========================================================

    tail_sections = [
        (
            0.000,
            0.995,
            1.455,
            0.052,
            0.044
        ),

        (
            0.000,
            1.070,
            1.395,
            0.068,
            0.052
        ),

        (
            -0.004,
            1.155,
            1.315,
            0.090,
            0.060
        ),

        (
            -0.008,
            1.255,
            1.205,
            0.118,
            0.068
        ),

        (
            0.000,
            1.360,
            1.075,
            0.140,
            0.074
        ),

        (
            0.010,
            1.465,
            0.925,
            0.150,
            0.078
        ),

        (
            0.010,
            1.560,
            0.775,
            0.145,
            0.074
        ),

        (
            0.000,
            1.645,
            0.635,
            0.125,
            0.066
        ),

        (
            -0.010,
            1.710,
            0.515,
            0.090,
            0.055
        ),

        (
            -0.015,
            1.750,
            0.425,
            0.048,
            0.036
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
            "tail.1": 0.70,
            "tail.2": 0.30
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
        "RiverwatchV9Tail",
        tail_sections,
        mane_mat,
        tail_weights,
        rings=28
    )

    # ========================================================
    # FITTED SADDLE BLANKET
    # ========================================================

    def build_blanket():
        x_values = [
            -0.345,
            -0.230,
            -0.115,
            0.000,
            0.115,
            0.230,
            0.345,
        ]

        y_values = [
            -0.315,
            -0.155,
            0.000,
            0.155,
            0.315,
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
                        / 0.345
                    )

                    z = (
                        1.790
                        - 0.120
                        * (
                            side ** 1.65
                        )
                        - float(layer)
                        * 0.018
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

            left_a = (
                yi * width
            )

            left_b = (
                (yi + 1)
                * width
            )

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

        for xi in range(
            width - 1
        ):

            front_a = xi
            front_b = xi + 1

            faces.append(
                (
                    front_a,
                    front_b,
                    top_count + front_b,
                    top_count + front_a
                )
            )

            rear_a = (
                (height - 1)
                * width
                + xi
            )

            rear_b = rear_a + 1

            faces.append(
                (
                    rear_a,
                    top_count + rear_a,
                    top_count + rear_b,
                    rear_b
                )
            )

        mesh = bpy.data.meshes.new(
            "RiverwatchV9BlanketMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV9Blanket",
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
    # LOW PROFILE SADDLE
    # ========================================================

    def build_saddle():
        x_values = [
            -0.245,
            -0.120,
            0.000,
            0.120,
            0.245,
        ]

        y_values = [
            -0.255,
            -0.125,
            0.000,
            0.125,
            0.255,
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
                        / 0.245
                    )

                    end = (
                        abs(y)
                        / 0.255
                    )

                    z = (
                        1.815
                        + 0.018
                        * (
                            side ** 1.6
                        )
                        + 0.024
                        * (
                            end ** 1.8
                        )
                        - float(layer)
                        * 0.050
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

            left_a = (
                yi * width
            )

            left_b = (
                (yi + 1)
                * width
            )

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
            "RiverwatchV9SaddleMesh"
        )

        mesh.from_pydata(
            verts,
            [],
            faces
        )

        mesh.update()

        obj = bpy.data.objects.new(
            "RiverwatchV9Saddle",
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
            0.012,
            3
        )

        smooth(obj)

    build_saddle()

    # Low pommel.
    horse_cylinder(
        "RiverwatchV9Pommel",
        (
            -0.205,
            -0.235,
            1.840
        ),
        (
            0.205,
            -0.235,
            1.840
        ),
        0.030,
        leather_edge,
        arm,
        "body"
    )

    # Low cantle.
    horse_cylinder(
        "RiverwatchV9Cantle",
        (
            -0.220,
            0.235,
            1.855
        ),
        (
            0.220,
            0.235,
            1.855
        ),
        0.034,
        leather_edge,
        arm,
        "body"
    )

    # Smaller saddle flaps.
    for side in (-1, 1):

        horse_cube(
            "RiverwatchV9SaddleFlap",
            (
                side * 0.285,
                0.010,
                1.620
            ),
            (
                0.045,
                0.330,
                0.250
            ),
            leather_mid,
            arm,
            "body",
            edge=0.030
        )

    # Girth.
    girth = torus(
        "RiverwatchV9Girth",
        (
            0.0,
            0.0,
            1.370
        ),
        0.405,
        0.020,
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

    # Stirrups.
    for side in (-1, 1):

        horse_cylinder(
            "RiverwatchV9StirrupLeather",
            (
                side * 0.215,
                0.0,
                1.790
            ),
            (
                side * 0.385,
                0.0,
                1.090
            ),
            0.008,
            leather,
            arm,
            "body"
        )

        stirrup = torus(
            "RiverwatchV9Stirrup",
            (
                side * 0.395,
                0.0,
                1.020
            ),
            0.080,
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
    # V9 METADATA
    # ========================================================

    arm[
        "broken_knight_horse_detail"
    ] = "fused_sculpt_v9"

    arm[
        "broken_knight_horse_authoring"
    ] = "blender"

    arm[
        "broken_knight_horse_core"
    ] = "voxel_fused_anatomical_forms"

    arm[
        "broken_knight_horse_legs"
    ] = "true_3d_sweep_refined"

    arm[
        "broken_knight_horse_hooves"
    ] = "rounded_3d_profile"

    arm[
        "broken_knight_horse_tail"
    ] = "flattened_hair_mass"

    arm[
        "broken_knight_horse_tack"
    ] = "minimal_fitted"

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