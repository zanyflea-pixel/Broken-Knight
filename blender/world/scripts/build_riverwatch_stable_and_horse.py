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
    # BROKEN KNIGHT - RIVERWATCH COURSER V5
    #
    # USER NOTES ADDRESSED:
    # - add a proper mane
    # - fix flat rump / butt
    # - redesign weird saddle
    # - make tail read as one fuller tail
    # - overall better silhouette
    #
    # MAIN ANATOMY:
    # continuous body / neck / head
    # continuous front and hind legs
    #
    # DETAIL:
    # fuller mane
    # fuller rounded hindquarters
    # cleaner travel saddle
    # single fuller tail mass
    # ========================================================

    # --------------------------------------------------------
    # MATERIALS
    # --------------------------------------------------------

    coat = material(
        "Riverwatch V5 Bay Coat",
        (0.287, 0.093, 0.028, 1),
        0.58
    )

    coat_shadow = material(
        "Riverwatch V5 Coat Shadow",
        (0.095, 0.022, 0.008, 1),
        0.70
    )

    coat_highlight = material(
        "Riverwatch V5 Coat Highlight",
        (0.430, 0.165, 0.060, 1),
        0.56
    )

    mane = material(
        "Riverwatch V5 Black Mane",
        (0.014, 0.010, 0.008, 1),
        0.68
    )

    mane_soft = material(
        "Riverwatch V5 Mane Soft Highlight",
        (0.055, 0.040, 0.030, 1),
        0.64
    )

    ivory = material(
        "Riverwatch V5 Ivory",
        (0.800, 0.758, 0.675, 1),
        0.80
    )

    iris = material(
        "Riverwatch V5 Iris",
        (0.105, 0.040, 0.010, 1),
        0.22
    )

    pupil = material(
        "Riverwatch V5 Pupil",
        (0.001, 0.001, 0.001, 1),
        0.14
    )

    glint = material(
        "Riverwatch V5 Eye Glint",
        (0.95, 0.90, 0.82, 1),
        0.16
    )

    muzzle = material(
        "Riverwatch V5 Muzzle",
        (0.175, 0.118, 0.094, 1),
        0.74
    )

    hoof = material(
        "Riverwatch V5 Hoof",
        (0.032, 0.024, 0.018, 1),
        0.82
    )

    hoof_edge = material(
        "Riverwatch V5 Hoof Edge",
        (0.100, 0.075, 0.050, 1),
        0.76
    )

    leather = material(
        "Riverwatch V5 Dark Leather",
        (0.070, 0.018, 0.008, 1),
        0.66
    )

    leather_mid = material(
        "Riverwatch V5 Warm Leather",
        (0.180, 0.060, 0.020, 1),
        0.62
    )

    leather_edge = material(
        "Riverwatch V5 Leather Edge",
        (0.300, 0.105, 0.030, 1),
        0.60
    )

    blanket = material(
        "Riverwatch V5 Royal Blanket",
        (0.025, 0.070, 0.210, 1),
        0.78
    )

    blanket_light = material(
        "Riverwatch V5 Blanket Highlight",
        (0.050, 0.135, 0.360, 1),
        0.72
    )

    gold = material(
        "Riverwatch V5 Gold Trim",
        (0.600, 0.395, 0.090, 1),
        0.60
    )

    brass = material(
        "Riverwatch V5 Brass",
        (0.560, 0.330, 0.075, 1),
        0.30,
        0.76
    )

    iron = material(
        "Riverwatch V5 Forged Iron",
        (0.040, 0.043, 0.048, 1),
        0.42,
        0.70
    )

    steel = material(
        "Riverwatch V5 Horseshoe Steel",
        (0.115, 0.125, 0.130, 1),
        0.35,
        0.76
    )

    # --------------------------------------------------------
    # HELPERS
    # --------------------------------------------------------

    def smooth_mesh(obj):
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        return obj

    def apply_subdivision(obj, levels=1):
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)

        modifier = obj.modifiers.new("OrganicSubdivision", "SUBSURF")
        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = levels
        modifier.render_levels = levels

        bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj

    def bake_non_armature_modifiers(obj):
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)

        for modifier in list(obj.modifiers):
            if modifier.type == "ARMATURE":
                continue
            bpy.ops.object.modifier_apply(modifier=modifier.name)

        return obj

    def armature_bind(obj):
        obj.parent = arm
        modifier = obj.modifiers.new("HorseRig", "ARMATURE")
        modifier.object = arm
        return obj

    def make_curve_mesh(name, points, radius, mat, bone, resolution=2):
        curve_data = bpy.data.curves.new(name + "Curve", "CURVE")
        curve_data.dimensions = "3D"
        curve_data.resolution_u = resolution
        curve_data.bevel_depth = radius
        curve_data.bevel_resolution = 3
        curve_data.fill_mode = "FULL"

        spline = curve_data.splines.new("BEZIER")
        spline.bezier_points.add(len(points) - 1)

        for index, point in enumerate(points):
            bezier_point = spline.bezier_points[index]
            bezier_point.co = point
            bezier_point.handle_left_type = "AUTO"
            bezier_point.handle_right_type = "AUTO"

        obj = bpy.data.objects.new(name, curve_data)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mat)

        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")

        mesh_obj = bpy.context.object
        mesh_obj.name = name

        smooth_mesh(mesh_obj)
        rigid_skin(mesh_obj, arm, bone)

        return mesh_obj

    def detail_cube(name, location, size, mat, bone, rotation=(0.0, 0.0, 0.0), edge=0.025):
        obj = horse_cube(
            name,
            location,
            size,
            mat,
            arm,
            bone,
            rotation=rotation,
            edge=edge
        )

        bake_non_armature_modifiers(obj)
        return obj

    def detail_cylinder(name, start, end, radius, mat, bone, radius2=None):
        obj = horse_cylinder(
            name,
            start,
            end,
            radius,
            mat,
            arm,
            bone,
            radius2
        )

        bake_non_armature_modifiers(obj)
        return obj

    # ========================================================
    # CORE BODY / NECK / HEAD
    # ========================================================

    def build_core():
        # y, center_z, radius_x, radius_z
        # Hindquarters are intentionally fuller than V4.
        sections = [
            (0.98, 1.360, 0.180, 0.235),
            (0.90, 1.355, 0.265, 0.315),
            (0.82, 1.340, 0.355, 0.410),
            (0.72, 1.315, 0.435, 0.490),
            (0.58, 1.270, 0.490, 0.545),
            (0.40, 1.215, 0.510, 0.560),
            (0.18, 1.165, 0.510, 0.555),
            (-0.06, 1.145, 0.500, 0.540),
            (-0.28, 1.165, 0.475, 0.515),
            (-0.45, 1.225, 0.445, 0.495),
            (-0.58, 1.305, 0.400, 0.450),
            (-0.70, 1.405, 0.350, 0.395),
            (-0.82, 1.505, 0.305, 0.355),
            (-0.94, 1.600, 0.265, 0.315),
            (-1.05, 1.690, 0.225, 0.275),
            (-1.16, 1.770, 0.200, 0.235),
            (-1.27, 1.815, 0.220, 0.245),
            (-1.38, 1.790, 0.215, 0.220),
            (-1.48, 1.740, 0.205, 0.195),
            (-1.58, 1.700, 0.190, 0.165),
            (-1.68, 1.675, 0.172, 0.140),
            (-1.77, 1.665, 0.145, 0.110),
        ]

        rings = 60
        verts = []
        faces = []

        for section_index, section in enumerate(sections):
            y, center_z, radius_x, radius_z = section

            for ring_index in range(rings):
                angle = math.tau * float(ring_index) / float(rings)

                cosine = math.cos(angle)
                sine = math.sin(angle)

                vertical = sine
                if vertical > 0.0:
                    vertical = vertical ** 0.85
                else:
                    vertical = -((-vertical) ** 1.08)

                horizontal = cosine

                side_emphasis = 1.0 + 0.045 * (1.0 - abs(sine))

                x = radius_x * horizontal * side_emphasis
                z = center_z + radius_z * vertical

                # Fuller chest
                chest_factor = math.exp(-((y + 0.38) / 0.22) ** 2)
                x *= 1.0 + chest_factor * 0.060 * (1.0 - abs(sine))

                # Fuller rounded hindquarters
                rump_factor = math.exp(-((y - 0.58) / 0.28) ** 2)
                x *= 1.0 + rump_factor * 0.085 * (1.0 - abs(sine))
                if sine > 0.0:
                    z += rump_factor * 0.030 * sine

                # Slight neck crest
                neck_factor = math.exp(-((y + 0.90) / 0.30) ** 2)
                if sine > 0.0:
                    z += neck_factor * 0.035 * sine

                verts.append((x, y, z))

        section_count = len(sections)

        for section_index in range(section_count - 1):
            first = section_index * rings
            second = (section_index + 1) * rings

            for ring_index in range(rings):
                next_ring = (ring_index + 1) % rings

                faces.append((
                    first + ring_index,
                    second + ring_index,
                    second + next_ring,
                    first + next_ring
                ))

        rear_center = len(verts)
        verts.append((0.0, sections[0][0], sections[0][1]))

        nose_center = len(verts)
        verts.append((0.0, sections[-1][0], sections[-1][1]))

        for ring_index in range(rings):
            next_ring = (ring_index + 1) % rings

            faces.append((rear_center, next_ring, ring_index))

            last_start = (section_count - 1) * rings
            faces.append((
                nose_center,
                last_start + next_ring,
                last_start + ring_index
            ))

        mesh = bpy.data.meshes.new("RiverwatchHorseCoreMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new("RiverwatchHorseCore", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(coat)

        smooth_mesh(obj)

        body_group = obj.vertex_groups.new(name="body")
        neck_group = obj.vertex_groups.new(name="neck")
        head_group = obj.vertex_groups.new(name="head")

        for vertex in obj.data.vertices:
            y = vertex.co.y

            if y >= -0.74:
                body_group.add([vertex.index], 1.0, "REPLACE")

            elif y > -0.88:
                blend = (-0.74 - y) / 0.14
                body_group.add([vertex.index], 1.0 - blend, "REPLACE")
                neck_group.add([vertex.index], blend, "REPLACE")

            elif y >= -1.12:
                neck_group.add([vertex.index], 1.0, "REPLACE")

            elif y > -1.24:
                blend = (-1.12 - y) / 0.12
                neck_group.add([vertex.index], 1.0 - blend, "REPLACE")
                head_group.add([vertex.index], blend, "REPLACE")

            else:
                head_group.add([vertex.index], 1.0, "REPLACE")

        apply_subdivision(obj, 1)
        smooth_mesh(obj)
        armature_bind(obj)

        return obj

    build_core()

    # ========================================================
    # CONTINUOUS LEGS
    # ========================================================

    def build_leg(prefix, sections):
        rings = 28
        verts = []
        faces = []

        # center_x, center_y, center_z, radius_x, radius_y
        for section in sections:
            cx, cy, cz, radius_x, radius_y = section

            for ring_index in range(rings):
                angle = math.tau * float(ring_index) / float(rings)
                x = cx + math.cos(angle) * radius_x
                y = cy + math.sin(angle) * radius_y
                verts.append((x, y, cz))

        section_count = len(sections)

        for section_index in range(section_count - 1):
            first = section_index * rings
            second = (section_index + 1) * rings

            for ring_index in range(rings):
                next_ring = (ring_index + 1) % rings

                faces.append((
                    first + ring_index,
                    second + ring_index,
                    second + next_ring,
                    first + next_ring
                ))

        upper_center = len(verts)
        verts.append((sections[0][0], sections[0][1], sections[0][2]))

        lower_center = len(verts)
        verts.append((sections[-1][0], sections[-1][1], sections[-1][2]))

        for ring_index in range(rings):
            next_ring = (ring_index + 1) % rings
            faces.append((upper_center, ring_index, next_ring))

            last_start = (section_count - 1) * rings
            faces.append((lower_center, last_start + next_ring, last_start + ring_index))

        mesh = bpy.data.meshes.new(prefix + "LegMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()

        obj = bpy.data.objects.new(prefix + "Leg", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(coat)

        smooth_mesh(obj)

        upper_group = obj.vertex_groups.new(name=prefix + ".upper")
        lower_group = obj.vertex_groups.new(name=prefix + ".lower")
        hoof_group = obj.vertex_groups.new(name=prefix + ".hoof")

        for vertex in obj.data.vertices:
            z = vertex.co.z

            if z >= 0.66:
                upper_group.add([vertex.index], 1.0, "REPLACE")

            elif z > 0.54:
                blend = (0.66 - z) / 0.12
                upper_group.add([vertex.index], 1.0 - blend, "REPLACE")
                lower_group.add([vertex.index], blend, "REPLACE")

            elif z >= 0.23:
                lower_group.add([vertex.index], 1.0, "REPLACE")

            elif z > 0.15:
                blend = (0.23 - z) / 0.08
                lower_group.add([vertex.index], 1.0 - blend, "REPLACE")
                hoof_group.add([vertex.index], blend, "REPLACE")

            else:
                hoof_group.add([vertex.index], 1.0, "REPLACE")

        apply_subdivision(obj, 1)
        smooth_mesh(obj)
        armature_bind(obj)

        return obj

    build_leg(
        "front.L",
        [
            (-0.255, -0.440, 1.110, 0.145, 0.155),
            (-0.255, -0.450, 0.970, 0.128, 0.136),
            (-0.255, -0.468, 0.795, 0.108, 0.114),
            (-0.255, -0.485, 0.620, 0.098, 0.104),
            (-0.255, -0.495, 0.555, 0.108, 0.112),
            (-0.255, -0.510, 0.420, 0.073, 0.078),
            (-0.255, -0.525, 0.270, 0.064, 0.070),
            (-0.255, -0.540, 0.165, 0.078, 0.082),
            (-0.255, -0.555, 0.110, 0.086, 0.090),
        ]
    )

    build_leg(
        "front.R",
        [
            (0.255, -0.440, 1.110, 0.145, 0.155),
            (0.255, -0.450, 0.970, 0.128, 0.136),
            (0.255, -0.468, 0.795, 0.108, 0.114),
            (0.255, -0.485, 0.620, 0.098, 0.104),
            (0.255, -0.495, 0.555, 0.108, 0.112),
            (0.255, -0.510, 0.420, 0.073, 0.078),
            (0.255, -0.525, 0.270, 0.064, 0.070),
            (0.255, -0.540, 0.165, 0.078, 0.082),
            (0.255, -0.555, 0.110, 0.086, 0.090),
        ]
    )

    build_leg(
        "hind.L",
        [
            (-0.285, 0.500, 1.115, 0.175, 0.185),
            (-0.285, 0.540, 0.970, 0.150, 0.160),
            (-0.285, 0.590, 0.815, 0.124, 0.132),
            (-0.285, 0.645, 0.665, 0.108, 0.118),
            (-0.285, 0.660, 0.580, 0.116, 0.120),
            (-0.285, 0.615, 0.425, 0.078, 0.084),
            (-0.285, 0.565, 0.275, 0.067, 0.073),
            (-0.285, 0.520, 0.168, 0.078, 0.084),
            (-0.285, 0.490, 0.110, 0.086, 0.092),
        ]
    )

    build_leg(
        "hind.R",
        [
            (0.285, 0.500, 1.115, 0.175, 0.185),
            (0.285, 0.540, 0.970, 0.150, 0.160),
            (0.285, 0.590, 0.815, 0.124, 0.132),
            (0.285, 0.645, 0.665, 0.108, 0.118),
            (0.285, 0.660, 0.580, 0.116, 0.120),
            (0.285, 0.615, 0.425, 0.078, 0.084),
            (0.285, 0.565, 0.275, 0.067, 0.073),
            (0.285, 0.520, 0.168, 0.078, 0.084),
            (0.285, 0.490, 0.110, 0.086, 0.092),
        ]
    )

    # ========================================================
    # HOOVES
    # ========================================================

    def build_hoof(name, x, y, bone):
        verts = [
            (x - 0.082, y + 0.090, 0.115),
            (x + 0.082, y + 0.090, 0.115),
            (x + 0.082, y - 0.120, 0.115),
            (x - 0.082, y - 0.120, 0.115),

            (x - 0.105, y + 0.105, 0.025),
            (x + 0.105, y + 0.105, 0.025),
            (x + 0.105, y - 0.158, 0.025),
            (x - 0.105, y - 0.158, 0.025),
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

        obj.data.materials.append(hoof)

        group = obj.vertex_groups.new(name=bone)
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")

        bevel_modifier = obj.modifiers.new("HoofEdge", "BEVEL")
        bevel_modifier.width = 0.018
        bevel_modifier.segments = 3

        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)

        smooth_mesh(obj)
        armature_bind(obj)

        return obj

    build_hoof("HorseFrontLeftHoof", -0.255, -0.560, "front.L.hoof")
    build_hoof("HorseFrontRightHoof", 0.255, -0.560, "front.R.hoof")
    build_hoof("HorseHindLeftHoof", -0.285, 0.485, "hind.L.hoof")
    build_hoof("HorseHindRightHoof", 0.285, 0.485, "hind.R.hoof")

    for prefix, x, y in [
        ("front.L", -0.255, -0.592),
        ("front.R", 0.255, -0.592),
        ("hind.L", -0.285, 0.452),
        ("hind.R", 0.285, 0.452),
    ]:
        shoe = torus(
            "HorseShoe",
            (x, y, 0.020),
            0.095,
            0.012,
            steel,
            rotation=(0.0, 0.0, 0.0)
        )

        shoe.scale = (1.0, 1.34, 0.45)

        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

        rigid_skin(shoe, arm, prefix + ".hoof")

    # ========================================================
    # MANE - MUCH FULLER
    # ========================================================

    # Crest strip for silhouette.
    make_curve_mesh(
        "HorseManeCrest",
        [
            (0.0, -1.055, 2.010),
            (0.0, -0.955, 1.955),
            (0.0, -0.855, 1.900),
            (0.0, -0.740, 1.830),
            (0.0, -0.620, 1.745),
            (0.0, -0.515, 1.655),
        ],
        0.030,
        mane,
        "neck",
        3
    )

    for index in range(34):
        t = float(index) / 33.0

        root_y = -1.035 + t * 0.560
        root_z = 1.995 - t * 0.370

        side = 1.0 if index % 2 == 0 else -1.0

        swing = 0.075 + 0.030 * math.sin(float(index) * 1.25)
        drop = 0.180 + 0.065 * (0.5 + 0.5 * math.sin(float(index) * 1.55))

        make_curve_mesh(
            "HorseManeLock",
            [
                (0.0, root_y, root_z),
                (side * 0.028, root_y + 0.020, root_z - drop * 0.45),
                (side * swing, root_y + 0.055, root_z - drop),
            ],
            0.018 if index % 4 else 0.022,
            mane if index % 3 else mane_soft,
            "head" if root_y < -0.95 else "neck",
            2
        )

    for index in range(7):
        offset = float(index - 3) * 0.022

        make_curve_mesh(
            "HorseForelock",
            [
                (offset, -1.110, 2.005),
                (offset * 1.1, -1.205, 1.940),
                (offset * 1.25, -1.320, 1.845),
            ],
            0.017,
            mane,
            "head",
            2
        )

    # ========================================================
    # TAIL - READS AS ONE TAIL MASS
    # ========================================================

    # Larger tail dock.
    make_curve_mesh(
        "HorseTailDock",
        [
            (0.0, 0.725, 1.360),
            (0.0, 0.885, 1.255),
            (0.0, 1.045, 1.080),
        ],
        0.070,
        mane,
        "tail.1",
        3
    )

    # Broad tail body to prevent "two part" look.
    make_curve_mesh(
        "HorseTailMassCenter",
        [
            (0.0, 1.000, 1.060),
            (0.0, 1.220, 0.870),
            (0.0, 1.440, 0.560),
        ],
        0.045,
        mane,
        "tail.2",
        3
    )

    for index in range(18):
        side = float(index - 8.5) / 8.5

        start_x = side * 0.030
        mid_x = side * 0.055
        end_x = side * 0.105

        end_z = 0.540 + 0.040 * math.sin(float(index) * 0.9)

        make_curve_mesh(
            "HorseTailLock",
            [
                (start_x, 1.005, 1.065),
                (mid_x, 1.220, 0.860),
                (end_x, 1.455, end_z),
            ],
            0.020 if index not in (0, 17) else 0.017,
            mane if index % 2 else mane_soft,
            "tail.2",
            2
        )

    # ========================================================
    # EARS
    # ========================================================

    def build_ear(name, side):
        sx = side

        verts = [
            (sx * 0.055, -1.085, 1.970),
            (sx * 0.155, -1.085, 1.970),
            (sx * 0.128, -1.055, 2.225),

            (sx * 0.067, -1.020, 1.980),
            (sx * 0.145, -1.020, 1.980),
            (sx * 0.123, -1.010, 2.200),
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

        group = obj.vertex_groups.new(name="head")
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")

        apply_subdivision(obj, 1)
        smooth_mesh(obj)
        armature_bind(obj)

        return obj

    build_ear("HorseLeftEar", -1)
    build_ear("HorseRightEar", 1)

    # ========================================================
    # FACE / EYES / NOSTRILS / BLAZE
    # ========================================================

    for side in (-1, 1):
        horse_sphere(
            "HorseEye",
            (side * 0.205, -1.280, 1.885),
            (0.034, 0.022, 0.034),
            iris,
            arm,
            "head",
            22,
            14
        )

        horse_sphere(
            "HorsePupil",
            (side * 0.226, -1.295, 1.885),
            (0.015, 0.010, 0.022),
            pupil,
            arm,
            "head",
            16,
            10
        )

        horse_sphere(
            "HorseEyeGlint",
            (side * 0.238, -1.302, 1.900),
            (0.006, 0.005, 0.006),
            glint,
            arm,
            "head",
            12,
            8
        )

        make_curve_mesh(
            "HorseUpperEyelid",
            [
                (side * 0.165, -1.277, 1.922),
                (side * 0.205, -1.290, 1.929),
                (side * 0.245, -1.278, 1.919),
            ],
            0.008,
            coat_shadow,
            "head",
            2
        )

        horse_sphere(
            "HorseNostril",
            (side * 0.095, -1.790, 1.670),
            (0.026, 0.016, 0.019),
            coat_shadow,
            arm,
            "head",
            16,
            10
        )

    make_curve_mesh(
        "HorseMouthLine",
        [
            (-0.135, -1.800, 1.620),
            (0.0, -1.812, 1.610),
            (0.135, -1.800, 1.620),
        ],
        0.007,
        coat_shadow,
        "head",
        2
    )

    # Small blaze
    make_curve_mesh(
        "HorseFaceBlaze",
        [
            (0.0, -1.155, 2.000),
            (0.008, -1.270, 1.915),
            (-0.006, -1.390, 1.830),
            (0.010, -1.515, 1.740),
        ],
        0.026,
        ivory,
        "head",
        3
    )

    # Muzzle soft patch
    horse_sphere(
        "HorseMuzzlePatch",
        (0.0, -1.700, 1.640),
        (0.155, 0.120, 0.100),
        muzzle,
        arm,
        "head",
        18,
        12
    )

    # ========================================================
    # SADDLE / BLANKET - CLEANER DESIGN
    # ========================================================

    detail_cube(
        "HorseBlanketBase",
        (0.0, 0.030, 1.565),
        (0.860, 0.980, 0.070),
        blanket,
        "body",
        rotation=(0.018, 0.0, 0.0),
        edge=0.055
    )

    detail_cube(
        "HorseBlanketPad",
        (0.0, 0.020, 1.603),
        (0.700, 0.790, 0.045),
        blanket_light,
        "body",
        edge=0.040
    )

    for y_position in (-0.450, 0.500):
        detail_cube(
            "HorseBlanketGoldEdge",
            (0.0, y_position, 1.580),
            (0.865, 0.030, 0.048),
            gold,
            "body",
            edge=0.010
        )

    for side in (-1, 1):
        detail_cube(
            "HorseBlanketGoldSide",
            (side * 0.410, 0.025, 1.575),
            (0.032, 0.910, 0.048),
            gold,
            "body",
            edge=0.010
        )

    # Cleaner, more believable travel saddle.
    detail_cube(
        "HorseSaddleSeat",
        (0.0, 0.035, 1.655),
        (0.520, 0.620, 0.105),
        leather,
        "body",
        edge=0.070
    )

    detail_cube(
        "HorseSaddlePommel",
        (0.0, -0.240, 1.735),
        (0.360, 0.130, 0.180),
        leather_edge,
        "body",
        edge=0.045
    )

    detail_cube(
        "HorseSaddleCantle",
        (0.0, 0.270, 1.735),
        (0.420, 0.135, 0.230),
        leather_edge,
        "body",
        edge=0.050
    )

    for side in (-1, 1):
        detail_cube(
            "HorseSaddleFlap",
            (side * 0.305, 0.040, 1.470),
            (0.130, 0.530, 0.265),
            leather_mid,
            "body",
            rotation=(0.0, 0.0, side * -0.045),
            edge=0.040
        )

        detail_cube(
            "HorseKneeRoll",
            (side * 0.350, -0.195, 1.525),
            (0.090, 0.160, 0.160),
            leather_edge,
            "body",
            edge=0.050
        )

    # Girth
    girth = torus(
        "HorseGirth",
        (0.0, 0.025, 1.225),
        0.455,
        0.028,
        leather,
        rotation=(math.pi / 2, 0.0, 0.0)
    )
    rigid_skin(girth, arm, "body")

    # Small rear bag only, much cleaner than before.
    for side in (-1, 1):
        detail_cube(
            "HorseRearBag",
            (side * 0.430, 0.380, 1.315),
            (0.155, 0.245, 0.235),
            leather,
            "body",
            edge=0.050
        )

        detail_cube(
            "HorseRearBagFlap",
            (side * 0.435, 0.325, 1.395),
            (0.165, 0.205, 0.085),
            leather_edge,
            "body",
            rotation=(0.08, 0.0, 0.0),
            edge=0.035
        )

    # ========================================================
    # BREAST COLLAR / STIRRUPS / BRIDLE
    # ========================================================

    for side in (-1, 1):
        make_curve_mesh(
            "HorseBreastCollar",
            [
                (side * 0.300, -0.220, 1.495),
                (side * 0.255, -0.455, 1.380),
                (side * 0.175, -0.670, 1.245),
            ],
            0.020,
            leather_mid,
            "body",
            2
        )

    detail_cylinder(
        "HorseBreastCollarCenter",
        (-0.175, -0.670, 1.245),
        (0.175, -0.670, 1.245),
        0.019,
        leather_mid,
        "body"
    )

    breast_medallion = torus(
        "HorseBreastMedallion",
        (0.0, -0.685, 1.245),
        0.065,
        0.014,
        brass,
        rotation=(math.pi / 2, 0.0, 0.0)
    )
    rigid_skin(breast_medallion, arm, "body")

    for side in (-1, 1):
        make_curve_mesh(
            "HorseStirrupLeather",
            [
                (side * 0.255, -0.010, 1.610),
                (side * 0.370, 0.005, 1.285),
                (side * 0.470, 0.005, 0.930),
            ],
            0.011,
            leather,
            "body",
            2
        )

        stirrup = torus(
            "HorseStirrup",
            (side * 0.480, 0.000, 0.875),
            0.110,
            0.018,
            iron,
            rotation=(math.pi / 2, 0.0, 0.0)
        )
        rigid_skin(stirrup, arm, "body")

        detail_cube(
            "HorseStirrupPlate",
            (side * 0.480, -0.050, 0.805),
            (0.170, 0.085, 0.022),
            steel,
            "body",
            edge=0.010
        )

    noseband = torus(
        "HorseNoseBand",
        (0.0, -1.575, 1.675),
        0.180,
        0.015,
        leather,
        rotation=(math.pi / 2, 0.0, 0.0)
    )
    rigid_skin(noseband, arm, "head")

    make_curve_mesh(
        "HorseBrowBand",
        [
            (-0.180, -1.165, 1.965),
            (0.0, -1.145, 1.985),
            (0.180, -1.165, 1.965),
        ],
        0.013,
        leather_mid,
        "head",
        2
    )

    detail_cylinder(
        "HorseBit",
        (-0.180, -1.645, 1.620),
        (0.180, -1.645, 1.620),
        0.012,
        iron,
        "head"
    )

    for side in (-1, 1):
        make_curve_mesh(
            "HorseCheekPiece",
            [
                (side * 0.170, -1.145, 1.950),
                (side * 0.180, -1.355, 1.820),
                (side * 0.180, -1.565, 1.680),
            ],
            0.011,
            leather,
            "head",
            2
        )

        bit_ring = torus(
            "HorseBitRing",
            (side * 0.190, -1.645, 1.620),
            0.042,
            0.009,
            brass,
            rotation=(math.pi / 2, 0.0, 0.0)
        )
        rigid_skin(bit_ring, arm, "head")

        make_curve_mesh(
            "HorseRein",
            [
                (side * 0.190, -1.650, 1.625),
                (side * 0.215, -1.150, 1.620),
                (side * 0.245, -0.620, 1.640),
                (side * 0.255, -0.200, 1.620),
            ],
            0.008,
            leather,
            "head",
            2
        )

    # Small brass saddle studs
    for side in (-1, 1):
        for stud_index in range(6):
            horse_sphere(
                "HorseSaddleStud",
                (
                    side * 0.355,
                    -0.235 + float(stud_index) * 0.090,
                    1.600
                ),
                (0.012, 0.012, 0.012),
                brass,
                arm,
                "body",
                10,
                6
            )

    arm["broken_knight_horse_detail"] = "refined_v5"
    arm["broken_knight_horse_authoring"] = "blender"
    arm["broken_knight_horse_main_mane"] = True
    arm["broken_knight_horse_rump"] = "rounder"
    arm["broken_knight_horse_saddle"] = "clean_travel_saddle"
    arm["broken_knight_horse_tail"] = "single_fuller_mass"

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