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
    # BROKEN KNIGHT - RIVERWATCH HORSE V6
    #
    # Goals of this pass:
    # - stronger horse silhouette
    # - fuller rounded croup instead of flat butt
    # - mane that reads as a real mane, not random tubes
    # - tail that reads as one continuous tail
    # - cleaner custom saddle and blanket
    # - better head, jaw, neck, shoulders and topline
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V6 Bay Coat",
        (0.300, 0.095, 0.028, 1),
        0.58
    )

    coat_dark = material(
        "Riverwatch V6 Bay Shadow",
        (0.082, 0.025, 0.010, 1),
        0.72
    )

    coat_light = material(
        "Riverwatch V6 Bay Highlight",
        (0.435, 0.160, 0.055, 1),
        0.56
    )

    mane_mat = material(
        "Riverwatch V6 Mane",
        (0.015, 0.010, 0.008, 1),
        0.70
    )

    mane_light = material(
        "Riverwatch V6 Mane Light",
        (0.060, 0.040, 0.030, 1),
        0.64
    )

    muzzle_mat = material(
        "Riverwatch V6 Muzzle",
        (0.185, 0.115, 0.090, 1),
        0.76
    )

    ivory = material(
        "Riverwatch V6 Ivory",
        (0.790, 0.755, 0.675, 1),
        0.80
    )

    hoof_mat = material(
        "Riverwatch V6 Hoof",
        (0.038, 0.028, 0.020, 1),
        0.82
    )

    leather = material(
        "Riverwatch V6 Saddle Leather",
        (0.078, 0.022, 0.010, 1),
        0.66
    )

    leather_mid = material(
        "Riverwatch V6 Leather Mid",
        (0.160, 0.060, 0.020, 1),
        0.63
    )

    leather_light = material(
        "Riverwatch V6 Leather Light",
        (0.265, 0.105, 0.040, 1),
        0.60
    )

    blanket = material(
        "Riverwatch V6 Blanket",
        (0.030, 0.095, 0.290, 1),
        0.78
    )

    blanket_light = material(
        "Riverwatch V6 Blanket Light",
        (0.070, 0.170, 0.410, 1),
        0.74
    )

    brass = material(
        "Riverwatch V6 Brass",
        (0.580, 0.360, 0.090, 1),
        0.32,
        0.78
    )

    iron = material(
        "Riverwatch V6 Iron",
        (0.055, 0.060, 0.070, 1),
        0.35,
        0.72
    )

    eye_brown = material(
        "Riverwatch V6 Eye Brown",
        (0.115, 0.045, 0.012, 1),
        0.24
    )

    eye_black = material(
        "Riverwatch V6 Eye Black",
        (0.004, 0.004, 0.004, 1),
        0.12
    )

    eye_glint = material(
        "Riverwatch V6 Eye Glint",
        (0.940, 0.930, 0.890, 1),
        0.10
    )

    # --------------------------------------------------------
    # HELPERS
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

    def subdivide(obj, levels=1):
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
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

    def bevel_object(obj, width=0.018, segments=3):
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
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

    def rigid_group(obj, bone):
        group = obj.vertex_groups.new(name=bone)
        group.add(
            range(len(obj.data.vertices)),
            1.0,
            "REPLACE"
        )
        armature_bind(obj)
        return obj

    def build_tube_mesh(name, sections, material_obj, group_names, group_rule, rings=26, subdiv=1):
        verts = []
        faces = []

        for section in sections:
            if len(section) == 5:
                cx, cy, cz, rx, rz = section
                tilt_x = 0.0
                tilt_z = 0.0
            else:
                cx, cy, cz, rx, rz, tilt_x, tilt_z = section

            for ring_index in range(rings):
                angle = math.tau * float(ring_index) / float(rings)
                cosine = math.cos(angle)
                sine = math.sin(angle)

                x = cx + cosine * rx + sine * tilt_x
                y = cy
                z = cz + sine * rz + cosine * tilt_z

                verts.append((x, y, z))

        for section_index in range(len(sections) - 1):
            first = section_index * rings
            second = (section_index + 1) * rings

            for ring_index in range(rings):
                next_ring = (ring_index + 1) % rings
                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring,
                    )
                )

        start_center = len(verts)
        verts.append(
            (
                sections[0][0],
                sections[0][1],
                sections[0][2],
            )
        )

        end_center = len(verts)
        verts.append(
            (
                sections[-1][0],
                sections[-1][1],
                sections[-1][2],
            )
        )

        for ring_index in range(rings):
            next_ring = (ring_index + 1) % rings

            faces.append(
                (
                    start_center,
                    ring_index,
                    next_ring,
                )
            )

            last_start = (len(sections) - 1) * rings

            faces.append(
                (
                    end_center,
                    last_start + next_ring,
                    last_start + ring_index,
                )
            )

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(material_obj)

        groups = {}
        for group_name in group_names:
            groups[group_name] = obj.vertex_groups.new(name=group_name)

        for vertex in obj.data.vertices:
            assignments = group_rule(vertex.co)
            for group_name, weight in assignments.items():
                if weight > 0.0:
                    groups[group_name].add(
                        [vertex.index],
                        weight,
                        "REPLACE"
                    )

        subdivide(obj, subdiv)
        smooth(obj)
        armature_bind(obj)
        return obj

    # ========================================================
    # CORE BODY MESH
    # ========================================================

    def build_core():
        # Each section:
        # (y, center_z, half_width, half_height)
        #
        # Rear is deliberately rounded over multiple sections so
        # it does not end in a flat butt.

        sections = [
            (1.180, 1.405, 0.035, 0.040),
            (1.145, 1.405, 0.080, 0.095),
            (1.095, 1.410, 0.155, 0.180),
            (1.030, 1.405, 0.255, 0.300),
            (0.935, 1.390, 0.380, 0.450),
            (0.820, 1.360, 0.480, 0.540),
            (0.685, 1.325, 0.540, 0.590),
            (0.525, 1.285, 0.565, 0.610),
            (0.335, 1.230, 0.570, 0.610),
            (0.110, 1.170, 0.545, 0.585),
            (-0.125, 1.155, 0.520, 0.560),
            (-0.335, 1.190, 0.490, 0.535),
            (-0.505, 1.255, 0.455, 0.500),
            (-0.655, 1.360, 0.400, 0.455),
            (-0.790, 1.485, 0.340, 0.395),
            (-0.915, 1.600, 0.285, 0.340),
            (-1.030, 1.700, 0.245, 0.295),
            (-1.135, 1.780, 0.220, 0.255),
            (-1.235, 1.825, 0.220, 0.235),
            (-1.340, 1.820, 0.215, 0.215),
            (-1.455, 1.780, 0.205, 0.190),
            (-1.565, 1.730, 0.190, 0.160),
            (-1.675, 1.690, 0.165, 0.125),
            (-1.770, 1.670, 0.130, 0.090),
            (-1.840, 1.665, 0.070, 0.050),
            (-1.875, 1.665, 0.028, 0.020),
        ]

        rings = 64
        verts = []
        faces = []

        for section_index, section in enumerate(sections):
            y, center_z, width, height = section

            for ring_index in range(rings):
                angle = math.tau * float(ring_index) / float(rings)
                cosine = math.cos(angle)
                sine = math.sin(angle)

                vertical = sine

                if vertical >= 0.0:
                    vertical = vertical ** 0.84
                else:
                    vertical = -((-vertical) ** 1.10)

                x = width * cosine
                z = center_z + height * vertical

                barrel_factor = math.exp(-((y - 0.05) / 0.45) ** 2)
                shoulder_factor = math.exp(-((y + 0.42) / 0.20) ** 2)
                rump_factor = math.exp(-((y - 0.62) / 0.30) ** 2)
                withers_factor = math.exp(-((y + 0.52) / 0.18) ** 2)
                neck_factor = math.exp(-((y + 0.92) / 0.26) ** 2)
                jaw_factor = math.exp(-((y + 1.36) / 0.23) ** 2)
                muzzle_factor = math.exp(-((y + 1.70) / 0.15) ** 2)

                if abs(sine) < 0.70:
                    x *= 1.0 + 0.035 * barrel_factor

                x *= 1.0 + 0.060 * shoulder_factor * (1.0 - abs(sine))
                x *= 1.0 + 0.105 * rump_factor * (1.0 - abs(sine))

                if sine > 0.0:
                    z += 0.080 * withers_factor * sine
                    z += 0.060 * neck_factor * sine
                    z += 0.055 * rump_factor * sine

                if sine < -0.08:
                    z -= 0.028 * barrel_factor * (-sine) * 0.35
                    z -= 0.034 * jaw_factor * (-sine)

                if jaw_factor > 0.05 and abs(sine) < 0.80:
                    x *= 1.0 + 0.080 * jaw_factor

                if muzzle_factor > 0.05:
                    x *= 1.0 - 0.080 * muzzle_factor
                    if sine < 0.0:
                        z -= 0.015 * muzzle_factor * (-sine)

                verts.append((x, y, z))

        section_count = len(sections)

        for section_index in range(section_count - 1):
            first = section_index * rings
            second = (section_index + 1) * rings

            for ring_index in range(rings):
                next_ring = (ring_index + 1) % rings
                faces.append(
                    (
                        first + ring_index,
                        second + ring_index,
                        second + next_ring,
                        first + next_ring,
                    )
                )

        rear_center = len(verts)
        verts.append((0.0, sections[0][0], sections[0][1]))

        nose_center = len(verts)
        verts.append((0.0, sections[-1][0], sections[-1][1]))

        for ring_index in range(rings):
            next_ring = (ring_index + 1) % rings

            faces.append(
                (
                    rear_center,
                    ring_index,
                    next_ring,
                )
            )

            last_start = (section_count - 1) * rings
            faces.append(
                (
                    nose_center,
                    last_start + next_ring,
                    last_start + ring_index,
                )
            )

        mesh = bpy.data.meshes.new("RiverwatchHorseV6CoreMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new("RiverwatchHorseV6Core", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(coat)

        body_group = obj.vertex_groups.new(name="body")
        neck_group = obj.vertex_groups.new(name="neck")
        head_group = obj.vertex_groups.new(name="head")

        for vertex in obj.data.vertices:
            y = vertex.co.y

            if y >= -0.74:
                body_group.add([vertex.index], 1.0, "REPLACE")

            elif y > -0.92:
                blend = (-0.74 - y) / 0.18
                body_group.add([vertex.index], 1.0 - blend, "REPLACE")
                neck_group.add([vertex.index], blend, "REPLACE")

            elif y >= -1.12:
                neck_group.add([vertex.index], 1.0, "REPLACE")

            elif y > -1.25:
                blend = (-1.12 - y) / 0.13
                neck_group.add([vertex.index], 1.0 - blend, "REPLACE")
                head_group.add([vertex.index], blend, "REPLACE")

            else:
                head_group.add([vertex.index], 1.0, "REPLACE")

        subdivide(obj, 1)
        smooth(obj)
        armature_bind(obj)

        return obj

    build_core()

    # ========================================================
    # LEGS
    # ========================================================

    def build_leg(prefix, sections):
        def group_rule(co):
            z = co.z

            if z >= 0.70:
                return {
                    prefix + ".upper": 1.0
                }

            if z > 0.56:
                blend = (0.70 - z) / 0.14
                return {
                    prefix + ".upper": 1.0 - blend,
                    prefix + ".lower": blend
                }

            if z >= 0.24:
                return {
                    prefix + ".lower": 1.0
                }

            if z > 0.14:
                blend = (0.24 - z) / 0.10
                return {
                    prefix + ".lower": 1.0 - blend,
                    prefix + ".hoof": blend
                }

            return {
                prefix + ".hoof": 1.0
            }

        build_tube_mesh(
            prefix + "RiverwatchV6Leg",
            sections,
            coat,
            [
                prefix + ".upper",
                prefix + ".lower",
                prefix + ".hoof",
            ],
            group_rule,
            rings=28,
            subdiv=1
        )

    build_leg(
        "front.L",
        [
            (-0.275, -0.445, 1.135, 0.160, 0.168),
            (-0.275, -0.455, 1.010, 0.146, 0.152),
            (-0.275, -0.470, 0.870, 0.125, 0.132),
            (-0.275, -0.482, 0.715, 0.108, 0.114),
            (-0.275, -0.492, 0.600, 0.112, 0.116),
            (-0.275, -0.505, 0.535, 0.100, 0.105),
            (-0.275, -0.518, 0.390, 0.072, 0.076),
            (-0.275, -0.530, 0.250, 0.065, 0.069),
            (-0.275, -0.545, 0.162, 0.079, 0.084),
            (-0.275, -0.560, 0.108, 0.088, 0.093),
        ]
    )

    build_leg(
        "front.R",
        [
            (0.275, -0.445, 1.135, 0.160, 0.168),
            (0.275, -0.455, 1.010, 0.146, 0.152),
            (0.275, -0.470, 0.870, 0.125, 0.132),
            (0.275, -0.482, 0.715, 0.108, 0.114),
            (0.275, -0.492, 0.600, 0.112, 0.116),
            (0.275, -0.505, 0.535, 0.100, 0.105),
            (0.275, -0.518, 0.390, 0.072, 0.076),
            (0.275, -0.530, 0.250, 0.065, 0.069),
            (0.275, -0.545, 0.162, 0.079, 0.084),
            (0.275, -0.560, 0.108, 0.088, 0.093),
        ]
    )

    build_leg(
        "hind.L",
        [
            (-0.305, 0.535, 1.145, 0.195, 0.200),
            (-0.305, 0.565, 1.030, 0.180, 0.185),
            (-0.305, 0.615, 0.905, 0.152, 0.158),
            (-0.305, 0.665, 0.770, 0.125, 0.132),
            (-0.305, 0.695, 0.640, 0.108, 0.116),
            (-0.305, 0.692, 0.575, 0.118, 0.123),
            (-0.305, 0.640, 0.438, 0.078, 0.085),
            (-0.305, 0.585, 0.300, 0.067, 0.073),
            (-0.305, 0.535, 0.182, 0.080, 0.085),
            (-0.305, 0.505, 0.112, 0.090, 0.095),
        ]
    )

    build_leg(
        "hind.R",
        [
            (0.305, 0.535, 1.145, 0.195, 0.200),
            (0.305, 0.565, 1.030, 0.180, 0.185),
            (0.305, 0.615, 0.905, 0.152, 0.158),
            (0.305, 0.665, 0.770, 0.125, 0.132),
            (0.305, 0.695, 0.640, 0.108, 0.116),
            (0.305, 0.692, 0.575, 0.118, 0.123),
            (0.305, 0.640, 0.438, 0.078, 0.085),
            (0.305, 0.585, 0.300, 0.067, 0.073),
            (0.305, 0.535, 0.182, 0.080, 0.085),
            (0.305, 0.505, 0.112, 0.090, 0.095),
        ]
    )

    # ========================================================
    # CUSTOM HOOVES
    # ========================================================

    def build_hoof(name, x, y, bone):
        verts = [
            (x - 0.082, y + 0.090, 0.118),
            (x + 0.082, y + 0.090, 0.118),
            (x + 0.087, y - 0.122, 0.115),
            (x - 0.087, y - 0.122, 0.115),

            (x - 0.108, y + 0.104, 0.028),
            (x + 0.108, y + 0.104, 0.028),
            (x + 0.115, y - 0.168, 0.028),
            (x - 0.115, y - 0.168, 0.028),
        ]

        faces = [
            (0, 1, 2, 3),
            (4, 7, 6, 5),
            (0, 4, 5, 1),
            (1, 5, 6, 2),
            (2, 6, 7, 3),
            (3, 7, 4, 0),
        ]

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(hoof_mat)

        rigid_group(obj, bone)
        bevel_object(obj, 0.017, 3)
        smooth(obj)

        return obj

    build_hoof("HorseFrontLeftHoofV6", -0.275, -0.568, "front.L.hoof")
    build_hoof("HorseFrontRightHoofV6", 0.275, -0.568, "front.R.hoof")
    build_hoof("HorseHindLeftHoofV6", -0.305, 0.502, "hind.L.hoof")
    build_hoof("HorseHindRightHoofV6", 0.305, 0.502, "hind.R.hoof")

    # ========================================================
    # MANE
    #
    # Built as layered broad strips so it reads like a mane.
    # ========================================================

    def build_mane_strip(name, x_root, x_tip, z_root_base, z_tip_base, y_start, y_end, waveshift, bone_mode):
        station_count = 10
        verts = []
        faces = []

        for i in range(station_count):
            t = float(i) / float(station_count - 1)
            y = y_start + (y_end - y_start) * t

            neck_curve = math.sin(t * math.pi) * 0.020
            wave = math.sin((t * 2.7 + waveshift) * math.pi) * 0.030

            root_x_left = x_root - 0.018
            root_x_right = x_root + 0.018

            tip_x_left = x_tip - 0.020 + wave
            tip_x_right = x_tip + 0.020 + wave

            root_z = z_root_base - 0.040 * t + neck_curve
            tip_z = z_tip_base - 0.180 * t + wave * 0.15

            verts.extend(
                [
                    (root_x_left, y, root_z),
                    (root_x_right, y, root_z),
                    (tip_x_left, y + 0.018, tip_z),
                    (tip_x_right, y + 0.018, tip_z),
                ]
            )

        for i in range(station_count - 1):
            a = i * 4
            b = (i + 1) * 4

            faces.append((a + 0, b + 0, b + 2, a + 2))
            faces.append((a + 1, a + 3, b + 3, b + 1))
            faces.append((a + 0, a + 1, b + 1, b + 0))
            faces.append((a + 2, b + 2, b + 3, a + 3))

        faces.append((0, 2, 3, 1))
        end = (station_count - 1) * 4
        faces.append((end, end + 1, end + 3, end + 2))

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mane_mat)

        neck_group = obj.vertex_groups.new(name="neck")
        head_group = obj.vertex_groups.new(name="head")

        for vertex in obj.data.vertices:
            if bone_mode == "head":
                head_group.add([vertex.index], 1.0, "REPLACE")
            else:
                y = vertex.co.y
                if y < -1.05:
                    head_group.add([vertex.index], 1.0, "REPLACE")
                else:
                    neck_group.add([vertex.index], 1.0, "REPLACE")

        subdivide(obj, 1)
        smooth(obj)
        armature_bind(obj)
        return obj

    build_mane_strip(
        "HorseV6MainManeStripA",
        -0.012,
        -0.105,
        2.015,
        1.925,
        -1.150,
        -0.530,
        0.00,
        "mixed"
    )

    build_mane_strip(
        "HorseV6MainManeStripB",
        0.008,
        -0.070,
        1.995,
        1.885,
        -1.080,
        -0.555,
        0.35,
        "mixed"
    )

    build_mane_strip(
        "HorseV6ForelockStrip",
        -0.008,
        -0.095,
        2.010,
        1.900,
        -1.220,
        -1.360,
        0.15,
        "head"
    )

    horse_cylinder(
        "HorseV6ManeCrest",
        (0.0, -1.100, 2.020),
        (0.0, -0.560, 1.605),
        0.035,
        mane_light,
        arm,
        "neck",
        0.020
    )

    # ========================================================
    # TAIL
    #
    # One continuous tail mass + small top volume so it reads as
    # one tail instead of split pieces.
    # ========================================================

    def tail_group_rule(co):
        y = co.y

        if y <= 1.18:
            return {"tail.1": 1.0}

        if y < 1.38:
            blend = (y - 1.18) / 0.20
            return {
                "tail.1": 1.0 - blend,
                "tail.2": blend
            }

        return {"tail.2": 1.0}

    build_tube_mesh(
        "HorseV6TailMass",
        [
            (0.000, 1.010, 1.420, 0.065, 0.075, 0.000, 0.000),
            (0.000, 1.085, 1.365, 0.105, 0.118, 0.000, 0.000),
            (-0.006, 1.180, 1.275, 0.135, 0.150, 0.000, 0.000),
            (-0.012, 1.295, 1.150, 0.155, 0.170, 0.000, 0.000),
            (0.000, 1.410, 1.000, 0.165, 0.180, 0.000, 0.000),
            (0.010, 1.520, 0.835, 0.158, 0.172, 0.000, 0.000),
            (0.004, 1.615, 0.700, 0.140, 0.155, 0.000, 0.000),
            (-0.004, 1.700, 0.575, 0.110, 0.125, 0.000, 0.000),
            (0.000, 1.760, 0.470, 0.070, 0.082, 0.000, 0.000),
            (0.000, 1.790, 0.425, 0.032, 0.040, 0.000, 0.000),
        ],
        mane_mat,
        ["tail.1", "tail.2"],
        tail_group_rule,
        rings=28,
        subdiv=1
    )

    horse_cylinder(
        "HorseV6TailTopVolume",
        (0.0, 0.970, 1.445),
        (0.0, 1.130, 1.320),
        0.060,
        mane_light,
        arm,
        "tail.1",
        0.015
    )

    # ========================================================
    # EARS
    # ========================================================

    def build_ear(name, side):
        sx = side

        verts = [
            (sx * 0.060, -1.105, 1.985),
            (sx * 0.150, -1.098, 1.985),
            (sx * 0.125, -1.072, 2.230),

            (sx * 0.072, -1.030, 1.995),
            (sx * 0.140, -1.025, 1.995),
            (sx * 0.120, -1.018, 2.205),
        ]

        faces = [
            (0, 1, 2),
            (5, 4, 3),
            (0, 3, 4, 1),
            (1, 4, 5, 2),
            (2, 5, 3, 0),
        ]

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(coat)

        rigid_group(obj, "head")
        subdivide(obj, 1)
        smooth(obj)

        return obj

    build_ear("HorseV6LeftEar", -1)
    build_ear("HorseV6RightEar", 1)

    # ========================================================
    # FACE DETAILS
    # ========================================================

    horse_sphere(
        "HorseV6MuzzlePatch",
        (0.0, -1.770, 1.662),
        (0.145, 0.092, 0.070),
        muzzle_mat,
        arm,
        "head",
        24,
        14
    )

    for side in (-1, 1):
        horse_sphere(
            "HorseV6EyeBrown",
            (side * 0.205, -1.290, 1.892),
            (0.033, 0.021, 0.033),
            eye_brown,
            arm,
            "head",
            20,
            14
        )

        horse_sphere(
            "HorseV6EyeBlack",
            (side * 0.226, -1.304, 1.892),
            (0.014, 0.009, 0.022),
            eye_black,
            arm,
            "head",
            16,
            10
        )

        horse_sphere(
            "HorseV6EyeGlint",
            (side * 0.238, -1.310, 1.905),
            (0.006, 0.005, 0.006),
            eye_glint,
            arm,
            "head",
            12,
            8
        )

        horse_sphere(
            "HorseV6Nostril",
            (side * 0.090, -1.840, 1.670),
            (0.025, 0.014, 0.018),
            coat_dark,
            arm,
            "head",
            16,
            10
        )

    horse_cylinder(
        "HorseV6FaceBlazeUpper",
        (0.0, -1.170, 1.995),
        (0.0, -1.430, 1.815),
        0.027,
        ivory,
        arm,
        "head",
        0.018
    )

    horse_cylinder(
        "HorseV6FaceBlazeLower",
        (0.0, -1.430, 1.815),
        (0.0, -1.640, 1.705),
        0.018,
        ivory,
        arm,
        "head",
        0.010
    )

    # ========================================================
    # BLANKET
    # ========================================================

    def build_blanket():
        y_values = [-0.430, -0.220, 0.000, 0.220, 0.430]
        x_values = [-0.440, -0.300, -0.150, 0.000, 0.150, 0.300, 0.440]

        verts = []
        faces = []

        top_count = len(y_values) * len(x_values)

        for layer in range(2):
            for y in y_values:
                for x in x_values:
                    side = abs(x) / 0.440
                    length_factor = abs(y) / 0.430

                    top_z = 1.700 - 0.020 * length_factor
                    drape = 0.175 * (side ** 1.70)
                    z = top_z - drape - float(layer) * 0.024

                    verts.append((x, y, z))

        width = len(x_values)
        height = len(y_values)

        for layer in range(2):
            base = layer * top_count

            for yi in range(height - 1):
                for xi in range(width - 1):
                    a = base + yi * width + xi
                    b = a + 1
                    c = a + width + 1
                    d = a + width

                    if layer == 0:
                        faces.append((a, d, c, b))
                    else:
                        faces.append((a, b, c, d))

        top = 0
        bottom = top_count

        for yi in range(height - 1):
            left_a = yi * width
            left_b = (yi + 1) * width
            faces.append((top + left_a, bottom + left_a, bottom + left_b, top + left_b))

            right_a = yi * width + width - 1
            right_b = (yi + 1) * width + width - 1
            faces.append((top + right_a, top + right_b, bottom + right_b, bottom + right_a))

        for xi in range(width - 1):
            front_a = xi
            front_b = xi + 1
            faces.append((top + front_a, top + front_b, bottom + front_b, bottom + front_a))

            rear_a = (height - 1) * width + xi
            rear_b = rear_a + 1
            faces.append((top + rear_a, bottom + rear_a, bottom + rear_b, top + rear_b))

        mesh = bpy.data.meshes.new("HorseV6BlanketMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new("HorseV6Blanket", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(blanket)

        rigid_group(obj, "body")
        smooth(obj)

        return obj

    build_blanket()

    # ========================================================
    # SADDLE
    #
    # Curved custom seat instead of awkward chunky block look.
    # ========================================================

    def build_saddle_seat():
        y_values = [-0.305, -0.180, -0.060, 0.060, 0.180, 0.305]
        x_norm_values = [-1.0, -0.50, 0.0, 0.50, 1.0]
        widths = [0.265, 0.305, 0.328, 0.328, 0.300, 0.265]

        verts = []
        faces = []

        width_count = len(x_norm_values)
        row_count = len(y_values)
        top_count = width_count * row_count

        for layer in range(2):
            for row, y in enumerate(y_values):
                saddle_width = widths[row]
                end_raise = (abs(y) / 0.305) ** 1.8

                for x_norm in x_norm_values:
                    x = saddle_width * x_norm
                    side_raise = (abs(x_norm) ** 1.65)

                    z = (
                        1.718
                        + 0.052 * end_raise
                        + 0.020 * side_raise
                        - float(layer) * 0.070
                    )

                    verts.append((x, y, z))

        for layer in range(2):
            base = layer * top_count

            for row in range(row_count - 1):
                for column in range(width_count - 1):
                    a = base + row * width_count + column
                    b = a + 1
                    c = a + width_count + 1
                    d = a + width_count

                    if layer == 0:
                        faces.append((a, d, c, b))
                    else:
                        faces.append((a, b, c, d))

        for row in range(row_count - 1):
            left_a = row * width_count
            left_b = (row + 1) * width_count
            faces.append((left_a, top_count + left_a, top_count + left_b, left_b))

            right_a = row * width_count + width_count - 1
            right_b = (row + 1) * width_count + width_count - 1
            faces.append((right_a, right_b, top_count + right_b, top_count + right_a))

        for column in range(width_count - 1):
            front_a = column
            front_b = column + 1
            faces.append((front_a, front_b, top_count + front_b, top_count + front_a))

            rear_a = (row_count - 1) * width_count + column
            rear_b = rear_a + 1
            faces.append((rear_a, top_count + rear_a, top_count + rear_b, rear_b))

        mesh = bpy.data.meshes.new("HorseV6SaddleSeatMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new("HorseV6SaddleSeat", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(leather)

        rigid_group(obj, "body")
        bevel_object(obj, 0.018, 3)
        smooth(obj)

        return obj

    build_saddle_seat()

    def build_saddle_arch(name, y_center, width, base_z, height, depth):
        samples = 11
        verts = []
        faces = []

        for side_y in (-depth * 0.5, depth * 0.5):
            for index in range(samples):
                t = float(index) / float(samples - 1)
                x = -width + 2.0 * width * t
                normalized = x / width

                arch = max(0.0, 1.0 - normalized * normalized) ** 0.60

                verts.append(
                    (
                        x,
                        y_center + side_y,
                        base_z + height * arch
                    )
                )

        lower_start = len(verts)

        for side_y in (-depth * 0.5, depth * 0.5):
            for index in range(samples):
                t = float(index) / float(samples - 1)
                x = -width + 2.0 * width * t
                verts.append((x, y_center + side_y, base_z - 0.030))

        for surface in range(2):
            top_base = surface * samples
            lower_base = lower_start + surface * samples

            for index in range(samples - 1):
                faces.append(
                    (
                        top_base + index,
                        top_base + index + 1,
                        lower_base + index + 1,
                        lower_base + index,
                    )
                )

        for index in range(samples - 1):
            faces.append(
                (
                    index,
                    samples + index,
                    samples + index + 1,
                    index + 1,
                )
            )

            a = lower_start + index
            b = lower_start + samples + index
            faces.append((a, a + 1, b + 1, b))

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(leather_light)

        rigid_group(obj, "body")
        bevel_object(obj, 0.012, 2)
        smooth(obj)

        return obj

    build_saddle_arch("HorseV6Pommel", -0.285, 0.255, 1.748, 0.150, 0.100)
    build_saddle_arch("HorseV6Cantle", 0.285, 0.285, 1.752, 0.185, 0.110)

    def build_flap(name, side):
        x_outer = side * 0.356
        x_inner = side * 0.326

        outline = [
            (-0.240, 1.620),
            (-0.145, 1.535),
            (0.045, 1.435),
            (0.235, 1.395),
            (0.290, 1.505),
            (0.185, 1.600),
        ]

        verts = []

        for y, z in outline:
            verts.append((x_outer, y, z))

        for y, z in outline:
            verts.append((x_inner, y, z))

        count = len(outline)
        faces = []

        faces.append(tuple(range(count)))
        faces.append(tuple(reversed(range(count, count * 2))))

        for index in range(count):
            next_index = (index + 1) % count
            faces.append(
                (
                    index,
                    next_index,
                    count + next_index,
                    count + index,
                )
            )

        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(leather_mid)

        rigid_group(obj, "body")
        bevel_object(obj, 0.015, 3)
        smooth(obj)

        return obj

    build_flap("HorseV6LeftSaddleFlap", -1)
    build_flap("HorseV6RightSaddleFlap", 1)

    # ========================================================
    # GIRTH / STIRRUPS / BAGS
    # ========================================================

    girth = torus(
        "HorseV6Girth",
        (0.0, 0.015, 1.245),
        0.462,
        0.028,
        leather,
        rotation=(math.pi / 2, 0.0, 0.0)
    )

    rigid_skin(girth, arm, "body")

    for side in (-1, 1):
        horse_cylinder(
            "HorseV6StirrupLeather",
            (side * 0.252, -0.020, 1.658),
            (side * 0.468, 0.000, 0.948),
            0.012,
            leather,
            arm,
            "body",
            0.010
        )

        stirrup = torus(
            "HorseV6Stirrup",
            (side * 0.478, 0.0, 0.878),
            0.105,
            0.017,
            iron,
            rotation=(math.pi / 2, 0.0, 0.0)
        )

        rigid_skin(stirrup, arm, "body")

        bag = horse_cube(
            "HorseV6RearBag",
            (side * 0.425, 0.360, 1.388),
            (0.145, 0.220, 0.225),
            leather,
            arm,
            "body",
            edge=0.040
        )

        flap = horse_cube(
            "HorseV6RearBagFlap",
            (side * 0.432, 0.300, 1.455),
            (0.155, 0.180, 0.075),
            leather_light,
            arm,
            "body",
            rotation=(0.08, 0.0, 0.0),
            edge=0.028
        )

    # ========================================================
    # BRIDLE / REINS / BREAST COLLAR
    # ========================================================

    noseband = torus(
        "HorseV6NoseBand",
        (0.0, -1.600, 1.692),
        0.180,
        0.014,
        leather,
        rotation=(math.pi / 2, 0.0, 0.0)
    )

    rigid_skin(noseband, arm, "head")

    horse_cylinder(
        "HorseV6BrowBand",
        (-0.180, -1.180, 1.967),
        (0.180, -1.180, 1.967),
        0.013,
        leather_mid,
        arm,
        "head"
    )

    horse_cylinder(
        "HorseV6Bit",
        (-0.180, -1.675, 1.632),
        (0.180, -1.675, 1.632),
        0.011,
        iron,
        arm,
        "head"
    )

    for side in (-1, 1):
        horse_cylinder(
            "HorseV6CheekPiece",
            (side * 0.175, -1.170, 1.950),
            (side * 0.180, -1.590, 1.692),
            0.010,
            leather,
            arm,
            "head"
        )

        bit_ring = torus(
            "HorseV6BitRing",
            (side * 0.190, -1.675, 1.632),
            0.040,
            0.008,
            brass,
            rotation=(math.pi / 2, 0.0, 0.0)
        )

        rigid_skin(bit_ring, arm, "head")

        horse_cylinder(
            "HorseV6Rein",
            (side * 0.190, -1.675, 1.632),
            (side * 0.255, -0.210, 1.635),
            0.008,
            leather,
            arm,
            "head"
        )

    for side in (-1, 1):
        horse_cylinder(
            "HorseV6BreastCollar",
            (side * 0.300, -0.230, 1.535),
            (side * 0.175, -0.680, 1.270),
            0.019,
            leather_mid,
            arm,
            "body"
        )

    horse_cylinder(
        "HorseV6BreastCollarCenter",
        (-0.175, -0.680, 1.270),
        (0.175, -0.680, 1.270),
        0.018,
        leather_mid,
        arm,
        "body"
    )

    medallion = torus(
        "HorseV6BreastMedallion",
        (0.0, -0.695, 1.270),
        0.060,
        0.013,
        brass,
        rotation=(math.pi / 2, 0.0, 0.0)
    )

    rigid_skin(medallion, arm, "body")

    # ========================================================
    # BODY ACCENTS
    # ========================================================

    horse_sphere(
        "HorseV6WithersHighlight",
        (0.0, -0.520, 1.830),
        (0.160, 0.120, 0.055),
        coat_light,
        arm,
        "body",
        18,
        10
    )

    horse_sphere(
        "HorseV6RumpMuscleLeft",
        (-0.250, 0.760, 1.430),
        (0.135, 0.160, 0.115),
        coat_light,
        arm,
        "body",
        18,
        10
    )

    horse_sphere(
        "HorseV6RumpMuscleRight",
        (0.250, 0.760, 1.430),
        (0.135, 0.160, 0.115),
        coat_light,
        arm,
        "body",
        18,
        10
    )

    # ========================================================
    # METADATA
    # ========================================================

    arm["broken_knight_horse_detail"] = "capture_driven_v6"
    arm["broken_knight_horse_authoring"] = "blender"
    arm["broken_knight_horse_focus"] = "mane_rump_saddle_tail"
    arm["broken_knight_horse_mane"] = "layered_sheet_mane"
    arm["broken_knight_horse_tail"] = "single_continuous_tail_mass"
    arm["broken_knight_horse_saddle"] = "curved_custom_saddle"
    arm["broken_knight_horse_croup"] = "rounded_multi_section_croup"

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