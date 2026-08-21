"""Major topology-preserving strong-hero pass for the canonical rigged master.

The body keeps its vertex order, vertex groups, armature, and action set.  This
script reshapes the accepted dense surface, seats face/chest details, improves
the cloth fit, and saves only after every operation succeeds.
"""

from math import cos, exp, pi, sin

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree


MARKER = "strong_lifelike_hero_v3"
HEAD_CENTER = Vector((0.0, -0.004, 1.790))


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def smoothstep(edge0, edge1, value):
    if edge1 == edge0:
        return 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def set_rest_pose(rig):
    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def reshape_body(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        side = 1.0 if x >= 0.0 else -1.0

        # Preserve the accepted cranium size. Only the lower face is narrowed
        # and planed into a masculine cheek-jaw-chin rhythm; broad head scaling
        # was rejected because it produced an inflated cartoon face.
        if z > 1.625 and ax < 0.145:
            lower_face = bell(z, 1.700, 0.065)
            chin_taper = bell(z, 1.657, 0.030)
            point.x *= 1.0 - 0.085 * lower_face - 0.045 * chin_taper
            x, y, z = point
            ax = abs(x)
            front = smoothstep(-0.035, -0.082, y)
            jaw_corner = bell(ax, 0.078, 0.025) * bell(z, 1.687, 0.034)
            chin = bell(ax, 0.0, 0.047) * bell(z, 1.650, 0.024)
            cheek = bell(ax, 0.064, 0.026) * bell(z, 1.764, 0.034)
            cheek_hollow = bell(ax, 0.055, 0.025) * bell(z, 1.720, 0.027)
            eye_socket = bell(ax, 0.034, 0.023) * bell(z, 1.802, 0.016)
            brow_ridge = bell(ax, 0.035, 0.028) * bell(z, 1.824, 0.015)
            nose_bridge = bell(ax, 0.0, 0.012) * bell(z, 1.775, 0.035)
            nose_tip = bell(ax, 0.0, 0.020) * bell(z, 1.742, 0.014)
            nose_wing = bell(ax, 0.012, 0.009) * bell(z, 1.741, 0.012)
            muzzle = bell(ax, 0.0, 0.040) * bell(z, 1.718, 0.020)
            point.x += side * (0.0060 * jaw_corner + 0.0030 * cheek)
            point.y -= front * (
                0.0040 * jaw_corner
                + 0.0085 * cheek
                + 0.0050 * brow_ridge
                + 0.0190 * nose_bridge
                + 0.0300 * nose_tip
                + 0.0080 * nose_wing
                + 0.0060 * muzzle
                + 0.0090 * chin
            )
            point.y += front * (0.0050 * eye_socket + 0.0045 * cheek_hollow)
            point.z -= 0.0065 * chin

        # A thicker neck and rising trapezius remove the long doll-like stem
        # between head and torso. Outer shoulder vertices rise into a clear cap.
        neck = bell(z, 1.625, 0.080) * bell(ax, 0.070, 0.090)
        if 1.515 < z < 1.705 and ax < 0.170:
            point.x *= 1.0 + 0.135 * neck
            point.y *= 1.0 + 0.090 * neck
        shoulder_shelf = bell(z, 1.480, 0.085) * bell(ax, 0.205, 0.105)
        deltoid_cap = bell(z, 1.425, 0.090) * bell(ax, 0.270, 0.070)
        if ax > 0.095:
            point.x += side * (0.0160 * shoulder_shelf + 0.0130 * deltoid_cap)
            point.z += 0.0140 * shoulder_shelf * smoothstep(0.125, 0.245, ax)
            if y < 0.0:
                point.y -= 0.0070 * deltoid_cap
            else:
                point.y += 0.0080 * deltoid_cap

        # High, broad male pectorals with a sternum division and a firm lower
        # edge. Volume is concentrated above the old breast-like low bulge.
        front_surface = smoothstep(-0.020, -0.105, y)
        if front_surface > 0.0 and ax < 0.245 and 1.285 < z < 1.555:
            pec_pair = bell(ax, 0.108, 0.098) * bell(z, 1.447, 0.073)
            upper_pec = bell(ax, 0.115, 0.115) * bell(z, 1.490, 0.050)
            lower_edge = bell(ax, 0.108, 0.105) * bell(z, 1.370, 0.026)
            sternum = bell(ax, 0.0, 0.018) * bell(z, 1.430, 0.115)
            under_pec = bell(ax, 0.105, 0.110) * bell(z, 1.335, 0.032)
            clavicle = bell(ax, 0.115, 0.095) * bell(z, 1.525, 0.018)
            point.y -= front_surface * (0.0230 * pec_pair + 0.0100 * upper_pec + 0.0060 * lower_edge)
            point.y += front_surface * (0.0080 * sternum + 0.0070 * under_pec + 0.0040 * clavicle)

        # Strong V-taper: lats flare below the shoulders while the waist keeps
        # an athletic inward break above a stable pelvis.
        lat = bell(z, 1.285, 0.150) * bell(ax, 0.185, 0.090)
        waist = bell(z, 1.095, 0.115) * bell(ax, 0.165, 0.070)
        pelvis = bell(z, 0.955, 0.090) * bell(ax, 0.150, 0.090)
        if 0.080 < ax < 0.285 and 0.930 < z < 1.470:
            point.x += side * (0.0140 * lat - 0.0090 * waist + 0.0040 * pelvis)

        # Readable but flesh-like abdominal pairs, linea alba, obliques, and
        # serratus. Grooves stay shallow; the lobes carry most of the form.
        if front_surface > 0.0 and ax < 0.190 and 1.000 < z < 1.340:
            abs_pair = bell(ax, 0.048, 0.032)
            rows = bell(z, 1.278, 0.032) + 0.92 * bell(z, 1.190, 0.033) + 0.78 * bell(z, 1.105, 0.036)
            linea = bell(ax, 0.0, 0.012) * bell(z, 1.190, 0.175)
            cross = (bell(z, 1.238, 0.011) + bell(z, 1.149, 0.011)) * bell(ax, 0.0, 0.100)
            oblique = bell(ax, 0.125, 0.040) * bell(z, 1.135, 0.105)
            serratus = bell(ax, 0.150, 0.025) * (
                bell(z, 1.300, 0.018) + 0.8 * bell(z, 1.255, 0.019) + 0.6 * bell(z, 1.212, 0.020)
            )
            point.y -= front_surface * (0.0095 * abs_pair * rows + 0.0045 * oblique)
            point.y += front_surface * (0.0060 * linea + 0.0045 * cross + 0.0030 * serratus)

        # Arm rhythm: shoulder cap, biceps/triceps fullness, elbow pinch, then
        # a forearm flexor mass tapering to the wrist instead of one cylinder.
        if ax > 0.225 and 0.865 < z < 1.475:
            biceps = bell(z, 1.265, 0.092)
            triceps = bell(z, 1.300, 0.110)
            elbow = bell(z, 1.105, 0.040)
            forearm = bell(z, 0.995, 0.088)
            radial = bell(ax, 0.335, 0.090)
            point.x += side * radial * (0.0100 * biceps - 0.0060 * elbow + 0.0070 * forearm)
            if y < 0.0:
                point.y -= radial * (0.0110 * biceps + 0.0060 * forearm)
                point.y += radial * 0.0045 * elbow
            else:
                point.y += radial * (0.0100 * triceps + 0.0040 * forearm)
                point.y -= radial * 0.0030 * elbow

        # Back landmarks: trapezius kite, lat planes, spinal channel, and
        # glutes with a real cleft and lower fold.
        back_surface = smoothstep(0.020, 0.110, y)
        if back_surface > 0.0 and ax < 0.270 and 1.120 < z < 1.590:
            traps = bell(ax, 0.095, 0.085) * bell(z, 1.495, 0.090)
            back_lat = bell(ax, 0.165, 0.085) * bell(z, 1.300, 0.145)
            spine = bell(ax, 0.0, 0.018) * bell(z, 1.320, 0.230)
            point.y += back_surface * (0.0100 * traps + 0.0100 * back_lat)
            point.y -= back_surface * 0.0050 * spine
        if back_surface > 0.0 and ax < 0.260 and 0.780 < z < 1.010:
            glute = bell(ax, 0.115, 0.100) * bell(z, 0.900, 0.082)
            cleft = bell(ax, 0.0, 0.018) * bell(z, 0.910, 0.110)
            fold = bell(ax, 0.115, 0.100) * bell(z, 0.805, 0.020)
            point.y += 0.0120 * glute
            point.y -= 0.0080 * cleft + 0.0045 * fold

        # Athletic legs with joint breaks. The old uniformly inflated thighs
        # and calves are narrowed first, then deliberate muscle bellies return.
        if 0.045 < ax < 0.300 and 0.145 < z < 1.000:
            center = 0.132 * side
            local_x = point.x - center
            thigh_slim = bell(z, 0.760, 0.230)
            knee_pin = bell(z, 0.565, 0.052)
            ankle_pin = bell(z, 0.165, 0.055)
            calf_belly = bell(z, 0.405, 0.110)
            scale = 1.0 - 0.070 * thigh_slim - 0.105 * knee_pin - 0.105 * ankle_pin + 0.035 * calf_belly
            point.x = center + local_x * scale
            quad = bell(z, 0.770, 0.145)
            hamstring = bell(z, 0.730, 0.155)
            if y < -0.005:
                point.y -= 0.0120 * quad
                point.y *= 1.0 - 0.055 * knee_pin
            elif y > 0.005:
                point.y += 0.0100 * hamstring + 0.0140 * calf_belly
                point.y *= 1.0 - 0.040 * knee_pin

        # Cap the extreme front peaks left by older chest/ab passes. A male
        # chest reads as a broad shelf in profile, not two pointed domes, and
        # the abdominal wall should undulate only a few millimeters.
        if point.y < -0.070 and ax < 0.235 and 1.335 < z < 1.535:
            outer_falloff = 0.010 * (ax / 0.235) ** 2
            upper_falloff = 0.016 * bell(z, 1.525, 0.032)
            lower_falloff = 0.014 * bell(z, 1.342, 0.032)
            chest_plane = -0.158 + outer_falloff + upper_falloff + lower_falloff
            if point.y < chest_plane:
                point.y = chest_plane + 0.12 * (point.y - chest_plane)
        if point.y < -0.060 and ax < 0.155 and 1.015 < z < 1.325:
            pair = bell(ax, 0.048, 0.032)
            rows = bell(z, 1.278, 0.035) + 0.90 * bell(z, 1.190, 0.036) + 0.75 * bell(z, 1.105, 0.039)
            abdominal_plane = -0.126 - 0.0060 * pair * rows
            if point.y < abdominal_plane:
                point.y = abdominal_plane + 0.15 * (point.y - abdominal_plane)

        vertex.co = inverse @ point

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body.data.update()


def transform_head_attachment(obj):
    if obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    for vertex in obj.data.vertices:
        point = world @ vertex.co
        point.x = HEAD_CENTER.x + (point.x - HEAD_CENTER.x) * 1.095
        point.y = HEAD_CENTER.y + (point.y - HEAD_CENTER.y) * 1.060
        point.z = HEAD_CENTER.z + (point.z - HEAD_CENTER.z) * 1.018
        vertex.co = inverse @ point
    obj.data.update()


def scale_attachment_surface(obj, scale_x, scale_z):
    if obj is None or obj.type != "MESH" or not obj.data.vertices:
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    points = [world @ vertex.co for vertex in obj.data.vertices]
    center = sum(points, Vector()) / len(points)
    for vertex, point in zip(obj.data.vertices, points):
        point.x = center.x + (point.x - center.x) * scale_x
        point.z = center.z + (point.z - center.z) * scale_z
        vertex.co = inverse @ point
    obj.data.update()


def offset_attachment_surface(obj, delta):
    if obj is None or obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    for vertex in obj.data.vertices:
        vertex.co = inverse @ (world @ vertex.co + delta)
    obj.data.update()


def body_tree(body):
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return BVHTree.FromObject(body, depsgraph)


def seat_chest_details(body, tree):
    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            continue
        world = obj.matrix_world.copy()
        inverse = world.inverted()
        points = [world @ vertex.co for vertex in obj.data.vertices]
        center = sum(points, Vector()) / len(points)
        hit = tree.ray_cast(Vector((center.x, -0.55, center.z + 0.014)), Vector((0.0, 1.0, 0.0)), 1.1)
        if hit[0] is None:
            continue
        target_y = hit[0].y - (0.0012 if name.startswith("Areola") else 0.0020)
        delta = Vector((0.0, target_y - center.y, 0.014))
        for vertex, point in zip(obj.data.vertices, points):
            vertex.co = inverse @ (point + delta)
        obj.data.update()


def seat_nostrils(tree):
    for side in (-1, 1):
        obj = bpy.data.objects.get(f"Nostril.{side}")
        if obj is None or obj.type != "MESH":
            continue
        world = obj.matrix_world.copy()
        inverse = world.inverted()
        points = [world @ vertex.co for vertex in obj.data.vertices]
        center = sum(points, Vector()) / len(points)
        target_z = 1.742
        hit = tree.ray_cast(Vector((center.x, -0.45, target_z)), Vector((0.0, 1.0, 0.0)), 0.9)
        target_y = hit[0].y - 0.00065 if hit[0] is not None else -0.149
        delta = Vector((0.0, target_y - center.y, target_z - center.z))
        for vertex, point in zip(obj.data.vertices, points):
            vertex.co = inverse @ (point + delta)
        obj.data.update()


def refine_hairline():
    hair = bpy.data.objects.get("Hair")
    if hair is None or hair.type != "MESH":
        return
    world = hair.matrix_world.copy()
    inverse = world.inverted()
    mesh = bmesh.new()
    mesh.from_mesh(hair.data)
    for vertex in mesh.verts:
        if not any(edge.is_boundary for edge in vertex.link_edges):
            continue
        point = world @ vertex.co
        # A controlled mature hairline: low enough at center to remove the
        # white forehead spike, receding slightly at the temples, and joined
        # continuously into the sideburns rather than forming a bowl edge.
        if point.y < 0.035:
            center = bell(point.x, 0.0, 0.034)
            temples = bell(abs(point.x), 0.075, 0.022)
            front_target = 1.838 - 0.0045 * center + 0.0110 * temples
            front_weight = smoothstep(0.035, -0.035, point.y)
            point.z = point.z * (1.0 - front_weight) + front_target * front_weight
            point.x *= 0.992
            vertex.co = inverse @ point
    mesh.to_mesh(hair.data)
    mesh.free()
    hair.data.update()


def build_body_weight_tree(body):
    world = body.matrix_world.copy()
    tree = KDTree(len(body.data.vertices))
    for vertex in body.data.vertices:
        tree.insert(world @ vertex.co, vertex.index)
    tree.balance()
    return tree


def bind_to_body_surface(obj, rig, body, weight_tree):
    # Copy the nearest skin vertex's complete weight blend. A pure head-bone
    # assignment does not match this model's authored head/jaw/neck field and
    # visibly drifts away from the face when Idle becomes active.
    obj.parent = None
    groups = {}
    world = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        _, nearest_index, _ = weight_tree.find(world @ vertex.co)
        nearest = body.data.vertices[nearest_index]
        for assignment in nearest.groups:
            name = body.vertex_groups[assignment.group].name
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([vertex.index], assignment.weight, "REPLACE")
    modifier = obj.modifiers.new("HeroFaceDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True


def rebuild_loincloth(rig, tree):
    collection = bpy.data.collections["04_LOINCLOTH"]
    material = bpy.data.materials["PlainLoincloth"]
    for name in ("Loincloth.Front", "Loincloth.Back"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)

    columns = (-1.0, -0.75, -0.50, -0.25, 0.0, 0.25, 0.50, 0.75, 1.0)
    panels = {
        "Loincloth.Front": [
            (0.990, 0.150), (0.945, 0.151), (0.895, 0.146),
            (0.840, 0.137), (0.785, 0.125), (0.735, 0.110), (0.690, 0.095),
        ],
        "Loincloth.Back": [
            (0.990, 0.160), (0.945, 0.165), (0.895, 0.160),
            (0.840, 0.149), (0.790, 0.135), (0.745, 0.119), (0.705, 0.103),
        ],
    }
    for name, rows in panels.items():
        front = name.endswith("Front")
        vertices = []
        weights = []
        for row_index, (z, half_width) in enumerate(rows):
            t = row_index / (len(rows) - 1)
            for column in columns:
                x = column * half_width
                if front:
                    base_y = -0.150 - 0.012 * t
                    hit = tree.ray_cast(Vector((x, -0.65, z)), Vector((0.0, 1.0, 0.0)), 1.3)
                    if hit[0] is not None and z > 0.805:
                        base_y = min(base_y, hit[0].y - 0.008)
                    fold = -0.0045 * cos(column * 3.0 * pi) * (0.20 + 0.80 * t)
                else:
                    base_y = 0.185 - 0.026 * t
                    hit = tree.ray_cast(Vector((x, 0.65, z)), Vector((0.0, -1.0, 0.0)), 1.3)
                    if hit[0] is not None and z > 0.770:
                        base_y = max(base_y, hit[0].y + 0.008)
                    fold = 0.0040 * cos(column * 3.0 * pi) * (0.20 + 0.80 * t)
                hem = 0.006 * sin((column + 1.0) * 2.7 * pi + (0.3 if front else 0.9)) if row_index == len(rows) - 1 else 0.0
                vertices.append((x, base_y + fold, z + hem))
                weights.append((t, column))

        faces = []
        width = len(columns)
        for row in range(len(rows) - 1):
            for column_index in range(width - 1):
                a = row * width + column_index
                faces.append((a, a + 1, a + width + 1, a + width))
        mesh = bpy.data.meshes.new(f"{name}.Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(material)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.parent = rig
        pelvis = obj.vertex_groups.new(name="pelvis")
        left = obj.vertex_groups.new(name="thigh.L")
        right = obj.vertex_groups.new(name="thigh.R")
        for index, (t, column) in enumerate(weights):
            leg_weight = 0.22 * smoothstep(0.25, 1.0, t) * min(1.0, abs(column) * 1.6)
            pelvis.add([index], 1.0 - leg_weight, "REPLACE")
            if column < -0.05:
                left.add([index], leg_weight, "REPLACE")
            elif column > 0.05:
                right.add([index], leg_weight, "REPLACE")
            else:
                pelvis.add([index], 1.0, "REPLACE")
        armature = obj.modifiers.new("HeroDeform", "ARMATURE")
        armature.object = rig
        subdivision = obj.modifiers.new("ClothDrape", "SUBSURF")
        subdivision.levels = 1
        subdivision.render_levels = 1
        solidify = obj.modifiers.new("ClothThickness", "SOLIDIFY")
        solidify.thickness = 0.0020
        bevel = obj.modifiers.new("SoftClothEdge", "BEVEL")
        bevel.width = 0.0015
        bevel.segments = 2
        for polygon in mesh.polygons:
            polygon.use_smooth = True


def rebuild_brows(rig, body, weight_tree, tree):
    material = bpy.data.materials["BrowBrown"]
    collection = bpy.data.collections["02_HERO_FACE"]
    for side in (-1, 1):
        name = f"Brow.{side}"
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        curve = bpy.data.curves.new(f"{name}.Curve", "CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 3
        curve.bevel_depth = 0.00145
        curve.bevel_resolution = 2
        spline = curve.splines.new("BEZIER")
        xs = (0.013, 0.026, 0.040, 0.054)
        zs = (1.787, 1.792, 1.790, 1.784)
        spline.bezier_points.add(3)
        for point, x, z in zip(spline.bezier_points, xs, zs):
            world_x = x * side
            hit = tree.ray_cast(Vector((world_x, -0.42, z)), Vector((0.0, 1.0, 0.0)), 0.84)
            y = hit[0].y - 0.00055 if hit[0] is not None else -0.085
            point.co = (world_x, y, z)
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        obj = bpy.data.objects.new(name, curve)
        collection.objects.link(obj)
        obj.data.materials.append(material)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        bind_to_body_surface(obj, rig, body, weight_tree)
        obj.select_set(False)


def rebuild_lips(rig, body, weight_tree, tree):
    collection = bpy.data.collections["02_HERO_FACE"]
    for name in ("LipSurface", "MouthCrease"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    lip = bpy.data.materials.get("LipTone") or bpy.data.materials.new("LipTone")
    lip.use_nodes = True
    lip.diffuse_color = (0.205, 0.050, 0.038, 1.0)
    lip.roughness = 0.82
    lip_bsdf = next(node for node in lip.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    lip_bsdf.inputs["Base Color"].default_value = lip.diffuse_color
    lip_bsdf.inputs["Roughness"].default_value = 0.82

    xs = (-0.036, -0.025, -0.012, 0.0, 0.012, 0.025, 0.036)
    rows = [
        (1.665, 1.669, 1.673, 1.669, 1.673, 1.669, 1.665),
        (1.661, 1.662, 1.663, 1.662, 1.663, 1.662, 1.661),
        (1.659, 1.656, 1.653, 1.652, 1.653, 1.656, 1.659),
    ]
    vertices = []
    for row in rows:
        for x, z in zip(xs, row):
            hit = tree.ray_cast(Vector((x, -0.45, z)), Vector((0.0, 1.0, 0.0)), 0.9)
            y = hit[0].y - 0.00062 if hit[0] is not None else -0.121
            vertices.append((x, y, z))
    faces = []
    width = len(xs)
    for row in range(len(rows) - 1):
        for column in range(width - 1):
            a = row * width + column
            faces.append((a, a + 1, a + width + 1, a + width))
    mesh = bpy.data.meshes.new("LipSurface.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(lip)
    mesh.update()
    lips = bpy.data.objects.new("LipSurface", mesh)
    collection.objects.link(lips)
    bind_to_body_surface(lips, rig, body, weight_tree)
    subdivision = lips.modifiers.new("SoftLipSurface", "SUBSURF")
    subdivision.levels = 2
    subdivision.render_levels = 2

    crease_material = bpy.data.materials.get("MouthCreaseTone") or bpy.data.materials.new("MouthCreaseTone")
    crease_material.use_nodes = True
    crease_material.diffuse_color = (0.090, 0.012, 0.009, 1.0)
    crease_bsdf = next(node for node in crease_material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    crease_bsdf.inputs["Base Color"].default_value = crease_material.diffuse_color
    crease_bsdf.inputs["Roughness"].default_value = 0.90
    curve = bpy.data.curves.new("MouthCrease.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = 0.00048
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(xs) - 1)
    for point, x, z in zip(spline.bezier_points, xs, rows[1]):
        hit = tree.ray_cast(Vector((x, -0.45, z)), Vector((0.0, 1.0, 0.0)), 0.9)
        y = hit[0].y - 0.0010 if hit[0] is not None else -0.122
        point.co = (x, y, z)
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    crease = bpy.data.objects.new("MouthCrease", curve)
    collection.objects.link(crease)
    crease.data.materials.append(crease_material)
    bpy.context.view_layer.objects.active = crease
    crease.select_set(True)
    bpy.ops.object.convert(target="MESH")
    bind_to_body_surface(crease, rig, body, weight_tree)
    crease.select_set(False)


def tune_material(name, color, roughness, specular=0.28, subsurface=0.0):
    material = bpy.data.materials.get(name)
    if material is None:
        return
    material.diffuse_color = color
    material.roughness = roughness
    material["export_roughness"] = roughness
    if not material.use_nodes:
        return
    bsdf = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface


def tune_materials():
    tune_material("Skin", (0.42, 0.215, 0.140, 1.0), 0.72, 0.27, 0.045)
    tune_material("Eyes", (0.56, 0.54, 0.49, 1.0), 0.62, 0.34)
    tune_material("IrisBrown", (0.115, 0.037, 0.012, 1.0), 0.58, 0.32)
    tune_material("BrowBrown", (0.018, 0.005, 0.002, 1.0), 0.90, 0.20)
    tune_material("HairBrown", (0.040, 0.010, 0.0035, 1.0), 0.86, 0.24)
    tune_material("AreolaTone", (0.245, 0.080, 0.052, 1.0), 0.84, 0.22)
    tune_material("NippleTone", (0.155, 0.040, 0.028, 1.0), 0.84, 0.22)
    tune_material("PlainLoincloth", (0.165, 0.048, 0.020, 1.0), 0.96, 0.18)
    tune_material("LoinCord", (0.070, 0.018, 0.006, 1.0), 0.92, 0.20)
    tune_material("BodyHairBrown", (0.020, 0.005, 0.002, 1.0), 0.92, 0.18)
    for material_name, dark_color, light_color in (
        ("HairBrown", (0.012, 0.0025, 0.001, 1.0), (0.055, 0.012, 0.004, 1.0)),
        ("PlainLoincloth", (0.055, 0.010, 0.004, 1.0), (0.180, 0.042, 0.014, 1.0)),
    ):
        material = bpy.data.materials.get(material_name)
        if material is None or not material.use_nodes:
            continue
        bsdf = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        for link in material.node_tree.links:
            if link.to_node == bsdf and link.to_socket.name == "Base Color" and link.from_node.type == "VALTORGB":
                link.from_node.color_ramp.elements[0].color = dark_color
                link.from_node.color_ramp.elements[-1].color = light_color


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("Canonical ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("STRONG_HERO_PASS|already_applied")
        return

    set_rest_pose(rig)
    reshape_body(body)
    for suffix in ("-1", "1"):
        scale_attachment_surface(bpy.data.objects.get(f"Eye.{suffix}"), 0.98, 0.86)
        scale_attachment_surface(bpy.data.objects.get(f"Iris.{suffix}"), 1.16, 0.98)
        scale_attachment_surface(bpy.data.objects.get(f"Pupil.{suffix}"), 1.10, 0.98)
        scale_attachment_surface(bpy.data.objects.get(f"UpperLid.{suffix}"), 0.98, 0.90)
        scale_attachment_surface(bpy.data.objects.get(f"Brow.{suffix}"), 1.14, 1.08)
        offset_attachment_surface(bpy.data.objects.get(f"Brow.{suffix}"), Vector((0.0, -0.00035, -0.0035)))

    tree = body_tree(body)
    seat_chest_details(body, tree)
    seat_nostrils(tree)
    rebuild_loincloth(rig, tree)
    tune_materials()

    body[MARKER] = True
    body["hero_visual_rating_internal"] = 64
    body["hero_visual_pass_notes"] = "Major head, neck, torso, limbs, muscle landmarks, skin, and fitted loincloth pass"
    rig.data.pose_position = "POSE"
    if rig.animation_data:
        rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("STRONG_HERO_PASS|head_neck_torso_arms_legs_face_skin_loincloth|applied")


main()
