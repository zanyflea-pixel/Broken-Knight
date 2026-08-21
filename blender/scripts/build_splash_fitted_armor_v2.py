"""Build the splash-reference royal armor from the locked hero's own surface.

Every wearable plate is a weighted extraction of ConnectedBody, expanded by a
few millimeters and overlapped with its neighbors.  This produces continuous,
body-fitted protection without loose panels, barrel primitives, or floating
trim.  The helmet and plume are the only fully authored meshes.
"""

from hashlib import sha256
import math
import os
import struct

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_SPLASH_FITTED_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_SplashFittedCandidate.blend"),
))
PASS_ID = "RoyalArmorSplashFittedSurface20260813V2"
PREFIX = "RoyalArmor_"
PRESERVE_SLOTS = {
    value.strip() for value in os.environ.get("BK_SPLASH_PRESERVE_SLOTS", "").split(",")
    if value.strip()
}
REFERENCE = os.path.join(
    ROOT, "blender", "references", "royal_armor_splash_target",
    "broken_knight_royal_armor_full_body_v1.png",
)

BODY = bpy.data.objects.get("ConnectedBody")
RIG = bpy.data.objects.get("HeroRig")
if BODY is None or RIG is None:
    raise RuntimeError("ConnectedBody or HeroRig is missing")


def digest(mesh):
    result = sha256()
    result.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for vertex in mesh.vertices:
        result.update(struct.pack("<3f", *vertex.co))
    return result.hexdigest()


def mat(name):
    material = bpy.data.materials.get(name)
    if material is None:
        raise RuntimeError(f"Required armor material missing: {name}")
    return material


COBALT = mat("Royal Cobalt Filigree Plate")
STEEL = mat("Royal Blued Steel")
DARK = mat("Royal Blackened Steel")
BRASS = mat("Royal Gilt Brass")
BRIGHT = mat("Royal Planished Edge Steel")
MAIL = mat("Riveted Mail")
LEATHER = mat("Harness Leather")
CRIMSON = mat("Ducal Crimson Horsehair")
CRIMSON_DARK = mat("Ducal Horsehair Shadow")


def tune_materials():
    palette = {
        COBALT: ((0.018, 0.045, 0.105, 1.0), 0.37, 0.86),
        STEEL: ((0.012, 0.026, 0.052, 1.0), 0.34, 0.91),
        DARK: ((0.006, 0.009, 0.015, 1.0), 0.47, 0.90),
        BRASS: ((0.31, 0.145, 0.032, 1.0), 0.41, 0.84),
        BRIGHT: ((0.14, 0.18, 0.24, 1.0), 0.33, 0.91),
        MAIL: ((0.035, 0.045, 0.065, 1.0), 0.58, 0.74),
        LEATHER: ((0.045, 0.020, 0.010, 1.0), 0.72, 0.04),
        CRIMSON: ((0.26, 0.012, 0.018, 1.0), 0.62, 0.01),
        CRIMSON_DARK: ((0.070, 0.004, 0.007, 1.0), 0.70, 0.01),
    }
    for material, (color, roughness, metallic) in palette.items():
        material.diffuse_color = color
        material.use_nodes = True
        bsdf = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic


def remove_old_armor():
    for obj in list(bpy.data.objects):
        if obj.name.startswith(PREFIX):
            slot = obj.name[len(PREFIX):].split("_", 1)[0]
            if slot in PRESERVE_SLOTS:
                continue
            bpy.data.objects.remove(obj, do_unlink=True)


def armor_collection(slot):
    root = bpy.data.collections.get("10_ROYAL_ARMOR")
    if root is None:
        root = bpy.data.collections.new("10_ROYAL_ARMOR")
        bpy.context.scene.collection.children.link(root)
    name = {
        "head": "10A_ARMOR_HEAD", "chest": "10B_ARMOR_CHEST",
        "shoulders": "10C_ARMOR_SHOULDERS", "hands": "10D_ARMOR_HANDS",
        "pants": "10E_ARMOR_PANTS", "feet": "10F_ARMOR_FEET",
    }[slot]
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        root.children.link(collection)
    return collection


def source_group_indices(names):
    result = set()
    for name in names:
        group = BODY.vertex_groups.get(name)
        if group is not None:
            result.add(group.index)
    if not result:
        raise RuntimeError(f"No ConnectedBody groups found for {names}")
    return result


def weighted(vertex, indices, minimum):
    return any(assignment.group in indices and assignment.weight >= minimum for assignment in vertex.groups)


def copy_weights(obj, remap):
    for group in BODY.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    for old_index, new_index in remap.items():
        for assignment in BODY.data.vertices[old_index].groups:
            obj.vertex_groups[assignment.group].add([new_index], assignment.weight, "REPLACE")


def fitted_piece(slot, part, groups, keep, material, outward, thickness=0.005, bevel=0.0022, minimum=0.01, smooth=True):
    indices = source_group_indices(groups)
    keep_flags = [
        keep(vertex.co) and weighted(vertex, indices, minimum)
        for vertex in BODY.data.vertices
    ]
    polygons = [
        tuple(polygon.vertices)
        for polygon in BODY.data.polygons
        if all(keep_flags[index] for index in polygon.vertices)
    ]
    used = sorted({index for polygon in polygons for index in polygon})
    if not used:
        raise RuntimeError(f"No fitted surface selected for {slot}/{part}")
    remap = {old: new for new, old in enumerate(used)}
    vertices = [
        tuple(BODY.data.vertices[index].co + BODY.data.vertices[index].normal * outward)
        for index in used
    ]
    faces = [tuple(remap[index] for index in polygon) for polygon in polygons]
    name = f"{PREFIX}{slot}_{part}"
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    armor_collection(slot).objects.link(obj)
    obj.matrix_world = BODY.matrix_world.copy()
    mesh.materials.append(material)
    mesh.materials.append(BRASS)
    mesh.materials.append(DARK)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    copy_weights(obj, remap)
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG
    if thickness > 0.0:
        solidify = obj.modifiers.new("ForgedThickness", "SOLIDIFY")
        solidify.thickness = thickness
        solidify.offset = -0.30
        solidify.material_offset_rim = 1
    if bevel > 0.0:
        edge = obj.modifiers.new("RolledPlateEdge", "BEVEL")
        edge.width = bevel
        edge.segments = 3
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_reference"] = REFERENCE
    obj["bk_overlap_fitted"] = True
    return obj


def planish(obj, iterations=3, factor=0.08):
    modifier = obj.modifiers.new("HandPlanishedSurface", "LAPLACIANSMOOTH")
    modifier.iterations = iterations
    modifier.lambda_factor = factor
    modifier.use_volume_preserve = True
    return obj


def add_center_ridges(obj, center_x, z_min, z_max, amount=0.0045, width=0.024):
    for vertex in obj.data.vertices:
        z = vertex.co.z
        if not (z_min <= z <= z_max):
            continue
        fade = math.sin(max(0.0, min(1.0, (z - z_min) / max(1e-6, z_max - z_min))) * math.pi)
        ridge = math.exp(-(((vertex.co.x - center_x) / width) ** 2))
        vertex.co += vertex.normal * amount * ridge * fade


def set_plate_bands(obj, z_bands=(), dark_below=None):
    for polygon in obj.data.polygons:
        z = polygon.center.z
        # Plate separation is created by real overlapping pieces and their
        # solidified gilt rims. Assigning whole body-derived polygons to gold
        # produced jagged zig-zag bands around the anatomy.
        if dark_below is not None and z < dark_below:
            polygon.material_index = 2


def shaped_plate(slot, part, outline, groups, material, outward, thickness=0.010, center_bulge=0.005, front=True, minimum=0.003):
    """Build a rigid forged plate whose perimeter is seated in the body shell.

    The plate samples the locked body along its outline, uses a triangulated
    center that is only a few millimeters more convex, and sinks its rear face
    back through the fitted foundation.  It therefore reads as hard plate but
    cannot hover away from the hero.
    """
    indices = source_group_indices(groups)
    direction = -1.0 if front else 1.0

    def surface_point(x, z):
        candidates = []
        for vertex in BODY.data.vertices:
            if not weighted(vertex, indices, minimum):
                continue
            dx = (vertex.co.x - x) / 0.065
            dz = (vertex.co.z - z) / 0.065
            distance = dx * dx + dz * dz
            candidates.append((distance, vertex))
        if not candidates:
            raise RuntimeError(f"No surface point for {part} at x={x}, z={z}")
        candidates.sort(key=lambda item: item[0])
        nearest_band = [item[1] for item in candidates[:32]]
        nearest = min(nearest_band, key=lambda vertex: vertex.co.y) if front else max(nearest_band, key=lambda vertex: vertex.co.y)
        return Vector((x, nearest.co.y, z)), nearest

    rim = []
    source_vertices = []
    for x, z in outline:
        point, source_vertex = surface_point(x, z)
        point.y += direction * outward
        rim.append(point)
        source_vertices.append(source_vertex)
    center = sum(rim, Vector()) / len(rim)
    center.y += direction * center_bulge
    outer = [center] + rim
    inner = [Vector((point.x, point.y - direction * thickness, point.z)) for point in outer]
    vertices = [tuple(point) for point in outer + inner]
    count = len(outer)
    faces = []
    # Triangle fan avoids the n-gon edge artifacts that made earlier panels
    # look like giant loose diamonds.
    for index in range(len(rim)):
        nxt = (index + 1) % len(rim)
        faces.append((0, index + 1, nxt + 1))
        faces.append((count, count + nxt + 1, count + index + 1))
    for index in range(len(rim)):
        nxt = (index + 1) % len(rim)
        faces.append((index + 1, count + index + 1, count + nxt + 1, nxt + 1))

    name = f"{PREFIX}{slot}_{part}"
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    armor_collection(slot).objects.link(obj)
    mesh.materials.append(material)
    mesh.materials.append(BRASS)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
        if polygon.index >= len(rim) * 2:
            polygon.material_index = 1

    # Blend the center from all perimeter weights; each rim pair receives the
    # exact weight set of its sampled body vertex.
    for group in BODY.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    center_weights = {}
    for source_vertex in source_vertices:
        for assignment in source_vertex.groups:
            center_weights[assignment.group] = center_weights.get(assignment.group, 0.0) + assignment.weight
    total = max(1e-6, sum(center_weights.values()))
    for group_index, value in center_weights.items():
        obj.vertex_groups[group_index].add([0, count], value / total, "REPLACE")
    for local_index, source_vertex in enumerate(source_vertices, start=1):
        for assignment in source_vertex.groups:
            obj.vertex_groups[assignment.group].add([local_index, count + local_index], assignment.weight, "REPLACE")
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG
    bevel = obj.modifiers.new("PlanishedPlateEdges", "BEVEL")
    bevel.width = 0.0030
    bevel.segments = 3
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_reference"] = REFERENCE
    obj["bk_seated_rigid_plate"] = True
    return obj


def rigid_plate_layers():
    torso = ("pelvis", "spine", "spine.001", "spine.002", "chest", "clavicle.L", "clavicle.R")
    # Interlocking breastplate quarters and a deep plackart create the hard,
    # fitted silhouette from the reference instead of a metallic bodysuit.
    shaped_plate("chest", "SplashForgedPectoralL", ((-0.010, 1.520), (-0.105, 1.565), (-0.300, 1.475), (-0.292, 1.300), (-0.045, 1.270)), torso, STEEL, 0.027, 0.012, 0.010)
    shaped_plate("chest", "SplashForgedPectoralR", ((0.010, 1.520), (0.105, 1.565), (0.300, 1.475), (0.292, 1.300), (0.045, 1.270)), torso, STEEL, 0.027, 0.012, 0.010)
    shaped_plate("chest", "SplashForgedPlackart", ((-0.270, 1.300), (0.0, 1.345), (0.270, 1.300), (0.252, 1.065), (0.0, 1.010), (-0.252, 1.065)), torso, COBALT, 0.031, 0.011, 0.008)
    # The rear foundation already follows the back correctly. Keep that fitted
    # surface instead of extending a planar backplate around the side profile.

    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        # The fitted cuisse/poleyn/greave layers below already follow the limb
        # circumference. Do not place planar shields across curved legs.


def make_authored(slot, name, vertices, faces, materials, bone, smooth=True):
    full_name = f"{PREFIX}{slot}_{name}"
    mesh = bpy.data.meshes.new(full_name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(full_name, mesh)
    armor_collection(slot).objects.link(obj)
    for material in materials:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_reference"] = REFERENCE
    return obj


def ring_shell(name, rings, segments=72):
    vertices = []
    for z, half_x, front, rear, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear if sine >= 0.0 else front
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            frontness = max(0.0, -sine) ** 8
            if 1.56 < z < 1.76:
                central = math.exp(-((x / 0.040) ** 2))
                y -= 0.020 * central * frontness
            if 1.75 < z < 1.82:
                y -= 0.010 * max(0.0, 1.0 - abs(x) / 0.135) * frontness
            if z < 1.63:
                # Pointed integrated bevor rather than a horizontal bucket hem.
                y -= 0.020 * math.exp(-((x / 0.085) ** 2)) * frontness
            if z > 1.80:
                fade = math.sin(max(0.0, min(1.0, (z - 1.80) / 0.14)) * math.pi)
                radial = 0.0055 * (0.5 + 0.5 * math.cos(angle * 6.0)) * fade
                length = max(1e-6, math.hypot(x, y))
                x += radial * x / length
                y += radial * y / length
            vertices.append((x, y, z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((
                row * segments + column,
                row * segments + nxt,
                (row + 1) * segments + nxt,
                (row + 1) * segments + column,
            ))
    faces.append(tuple((len(rings) - 1) * segments + column for column in range(segments)))
    obj = make_authored("head", name, vertices, faces, [STEEL, COBALT, DARK, BRASS, BRIGHT], "head")
    for polygon in obj.data.polygons[:-1]:
        row = polygon.index // segments
        column = polygon.index % segments
        z = (rings[row][0] + rings[row + 1][0]) * 0.5
        angle = math.tau * (column + 0.5) / segments
        front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
        back_delta = abs((angle - 0.5 * math.pi + math.pi) % math.tau - math.pi)
        if z < 1.62:
            polygon.material_index = 2
        elif front_delta < 0.78 and z < 1.79:
            polygon.material_index = 1
            polygon.use_smooth = False
        elif z > 1.81:
            polygon.material_index = 0
        elif back_delta < 0.85:
            polygon.material_index = 2
        else:
            polygon.material_index = 0
        if any(abs(z - band) < 0.010 for band in (1.545, 1.775, 1.905)):
            polygon.material_index = 3
        if front_delta < 0.035 and 1.58 < z < 1.80:
            polygon.material_index = 4
    solid = obj.modifiers.new("ForgedHelmetThickness", "SOLIDIFY")
    solid.thickness = 0.010
    solid.offset = -1.0
    bevel = obj.modifiers.new("RolledHelmetEdges", "BEVEL")
    bevel.width = 0.0028
    bevel.segments = 3
    return obj


def tube(name, points, radii, material, slot="head", bone="head"):
    sides = 7
    vertices = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
        if normal.length < 1e-5:
            normal = tangent.cross(Vector((0.0, 1.0, 0.0)))
        normal.normalize()
        binormal = tangent.cross(normal).normalized()
        for side in range(sides):
            angle = math.tau * side / sides
            offset = normal * math.cos(angle) * radii[index] + binormal * math.sin(angle) * radii[index]
            vertices.append(tuple(Vector(point) + offset))
    faces = []
    for ring in range(len(points) - 1):
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((ring * sides + side, ring * sides + nxt, (ring + 1) * sides + nxt, (ring + 1) * sides + side))
    return make_authored(slot, name, vertices, faces, [material], bone)


def body_surface_y(groups, x, z, front=True, minimum=0.003):
    indices = source_group_indices(groups)
    candidates = []
    for vertex in BODY.data.vertices:
        if not weighted(vertex, indices, minimum):
            continue
        distance = ((vertex.co.x - x) / 0.055) ** 2 + ((vertex.co.z - z) / 0.055) ** 2
        candidates.append((distance, vertex.co.y))
    if not candidates:
        raise RuntimeError(f"No body surface near x={x}, z={z}")
    candidates.sort(key=lambda item: item[0])
    nearby = [item[1] for item in candidates[:28]]
    return min(nearby) if front else max(nearby)


def build_embedded_chest_relief(groups):
    paths = (
        ("SplashReliefKeel", ((0.0, 1.105), (0.0, 1.520)), 0.0052),
        ("SplashReliefPectoralL", ((-0.010, 1.470), (-0.105, 1.510), (-0.205, 1.455), (-0.285, 1.370)), 0.0046),
        ("SplashReliefPectoralR", ((0.010, 1.470), (0.105, 1.510), (0.205, 1.455), (0.285, 1.370)), 0.0046),
        ("SplashReliefCrownL", ((0.0, 1.430), (-0.042, 1.468), (-0.074, 1.505), (-0.105, 1.455)), 0.0042),
        ("SplashReliefCrownR", ((0.0, 1.430), (0.042, 1.468), (0.074, 1.505), (0.105, 1.455)), 0.0042),
        ("SplashReliefLowerL", ((0.0, 1.175), (-0.100, 1.205), (-0.205, 1.170), (-0.270, 1.125)), 0.0038),
        ("SplashReliefLowerR", ((0.0, 1.175), (0.100, 1.205), (0.205, 1.170), (0.270, 1.125)), 0.0038),
    )
    for name, path_2d, radius in paths:
        points = []
        for x, z in path_2d:
            y = body_surface_y(groups, x, z, True) - 0.027
            points.append((x, y, z))
        tube(name, points, tuple(radius for _ in points), BRASS, "chest", "chest")


def build_helmet():
    helmet = ring_shell("SplashConnectedArmet", [
        (1.515, 0.126, 0.150, 0.172, 2.60),
        (1.550, 0.140, 0.166, 0.166, 2.65),
        (1.590, 0.151, 0.184, 0.156, 2.66),
        (1.635, 0.158, 0.194, 0.146, 2.64),
        (1.685, 0.163, 0.198, 0.140, 2.60),
        (1.735, 0.165, 0.192, 0.136, 2.52),
        (1.775, 0.164, 0.180, 0.134, 2.42),
        (1.805, 0.160, 0.163, 0.132, 2.32),
        (1.840, 0.151, 0.145, 0.127, 2.20),
        (1.875, 0.137, 0.127, 0.118, 2.10),
        (1.905, 0.112, 0.102, 0.098, 2.04),
        (1.928, 0.072, 0.065, 0.064, 2.00),
        (1.940, 0.018, 0.017, 0.017, 2.00),
    ])
    plume = []
    for index in range(38):
        row = index % 8
        layer = index // 8
        x = -0.042 + row * 0.012 + 0.004 * math.sin(index * 1.63)
        root_y = -0.070 + layer * 0.028
        variance = 0.018 * math.sin(index * 1.27)
        sweep = 0.018 * math.sin(index * 0.91)
        points = (
            (x, root_y, 1.922),
            (x + sweep * 0.15, root_y + 0.015, 1.995),
            (x + sweep * 0.40, root_y + 0.065, 2.090 + variance),
            (x + sweep * 0.75, root_y + 0.145, 2.150 + variance * 0.5),
            (x + sweep, root_y + 0.240, 2.105 - layer * 0.006),
            (x + sweep * 1.15, root_y + 0.330, 2.005 - row * 0.004),
        )
        plume.append(tube(
            f"SplashPlumeStrand{index:02d}", points,
            (0.0055, 0.0062, 0.0057, 0.0044, 0.0026, 0.0008),
            CRIMSON if index % 3 else CRIMSON_DARK,
        ))
    bpy.ops.object.select_all(action="DESELECT")
    helmet.select_set(True)
    for strand in plume:
        strand.select_set(True)
    bpy.context.view_layer.objects.active = helmet
    bpy.ops.object.join()
    helmet.name = f"{PREFIX}head_SplashConnectedArmet"
    helmet.data.name = helmet.name + "_Mesh"


def build_chest():
    torso_groups = ("pelvis", "spine", "spine.001", "spine.002", "chest", "clavicle.L", "clavicle.R")
    fitted_piece("chest", "SplashMailFoundation", torso_groups, lambda co: 0.88 < co.z < 1.64 and abs(co.x) < 0.43, MAIL, 0.008, 0.0025, 0.0015, 0.004)

    upper = fitted_piece("chest", "SplashAnatomicalBreastplate", torso_groups, lambda co: 1.155 < co.z < 1.585 and abs(co.x) < 0.35, DARK, 0.025, 0.009, 0.003, 0.004)
    planish(upper, 4, 0.09)
    add_center_ridges(upper, 0.0, 1.17, 1.56, 0.008, 0.035)
    set_plate_bands(upper, (1.175, 1.565))

    # Distinct left/right pectoral plates seat into the dark foundation and
    # overlap the central keel. Their increased offset is only 12–15 mm beyond
    # the foundation, enough to read as plate without becoming a body shell.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        pec = fitted_piece(
            "chest", f"SplashPectoralPlate{suffix}", torso_groups,
            lambda co, s=side: 1.275 < co.z < 1.565 and co.x * s > 0.005 and abs(co.x) < 0.31 and co.y < 0.045,
            COBALT, 0.039, 0.010, 0.0030, 0.003,
        )
        planish(pec, 5, 0.10)

    plackart = fitted_piece("chest", "SplashOverlappingPlackart", torso_groups, lambda co: 0.985 < co.z < 1.250 and abs(co.x) < 0.32, STEEL, 0.037, 0.009, 0.0030, 0.004)
    planish(plackart, 4, 0.09)
    add_center_ridges(plackart, 0.0, 1.00, 1.23, 0.006, 0.032)
    set_plate_bands(plackart, (1.005, 1.215))
    build_embedded_chest_relief(torso_groups)

    fitted_piece("chest", "SplashNestedGorgetLower", ("chest", "head"), lambda co: 1.485 < co.z < 1.590 and abs(co.x) < 0.25, STEEL, 0.032, 0.007, 0.0025, 0.004)
    fitted_piece("chest", "SplashNestedGorgetUpper", ("chest", "head"), lambda co: 1.545 < co.z < 1.650 and abs(co.x) < 0.20, DARK, 0.038, 0.006, 0.0025, 0.004)

    for index, (bottom, top, outward) in enumerate(((0.915, 1.010, 0.024), (0.875, 0.950, 0.027), (0.835, 0.910, 0.030))):
        lame = fitted_piece("chest", f"SplashWrapFauld{index}", ("pelvis", "chest"), lambda co, b=bottom, t=top: b < co.z < t and abs(co.x) < 0.31, STEEL if index != 1 else COBALT, outward, 0.007, 0.0025, 0.003)
        set_plate_bands(lame, (bottom + 0.010, top - 0.010))

    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        groups = ("pelvis", f"thigh.{suffix}")
        for index, (bottom, top, outward) in enumerate(((0.715, 0.955, 0.034), (0.595, 0.765, 0.037))):
            piece = fitted_piece(
                "chest", f"SplashTasset{suffix}{index}", groups,
                lambda co, s=side, b=bottom, t=top: b < co.z < t and co.x * s > 0.015 and co.y < 0.095,
                COBALT if index == 0 else STEEL, outward, 0.007, 0.0025, 0.003,
            )
            set_plate_bands(piece, (bottom + 0.015, top - 0.015))
        for index, (bottom, top, outward) in enumerate(((0.720, 0.955, 0.033), (0.600, 0.770, 0.036))):
            piece = fitted_piece(
                "chest", f"SplashRearCulet{suffix}{index}", groups,
                lambda co, s=side, b=bottom, t=top: b < co.z < t and co.x * s > 0.010 and co.y > -0.040,
                DARK if index == 0 else STEEL, outward, 0.007, 0.0025, 0.003,
            )
            set_plate_bands(piece, (bottom + 0.015, top - 0.015))


def build_shoulders_and_arms():
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        shoulder_groups = (f"clavicle.{suffix}", f"upper_arm.{suffix}", "chest")
        arm_group = (f"upper_arm.{suffix}",)
        fore_group = (f"forearm.{suffix}", f"upper_arm.{suffix}")
        hand_group = (f"hand.{suffix}",)
        region = lambda co, s=side: 0.16 < co.x * s < 0.53
        fitted_piece("shoulders", f"SplashMailGusset{suffix}", shoulder_groups, lambda co, r=region: r(co) and 1.20 < co.z < 1.59, MAIL, 0.010, 0.002, 0.0015, 0.003)
        cap = fitted_piece("shoulders", f"SplashPauldronCrown{suffix}", shoulder_groups, lambda co, r=region: r(co) and 1.390 < co.z < 1.610, STEEL, 0.050, 0.009, 0.0032, 0.004)
        set_plate_bands(cap, (1.410, 1.590))
        lame1 = fitted_piece("shoulders", f"SplashPauldronLame{suffix}1", arm_group, lambda co, r=region: r(co) and 1.305 < co.z < 1.445, COBALT, 0.042, 0.007, 0.0025, 0.005)
        lame2 = fitted_piece("shoulders", f"SplashPauldronLame{suffix}2", arm_group, lambda co, r=region: r(co) and 1.225 < co.z < 1.350, STEEL, 0.035, 0.007, 0.0025, 0.005)
        set_plate_bands(lame1, (1.325, 1.425))
        set_plate_bands(lame2, (1.245, 1.330))

        rerebrace = fitted_piece("shoulders", f"SplashRerebrace{suffix}", arm_group, lambda co: 1.185 < co.z < 1.345, COBALT, 0.022, 0.006, 0.0025, 0.006)
        set_plate_bands(rerebrace, (1.205, 1.325))
        couter = fitted_piece("hands", f"SplashCouter{suffix}", fore_group, lambda co: 1.120 < co.z < 1.245, STEEL, 0.032, 0.008, 0.003, 0.004)
        set_plate_bands(couter, (1.140, 1.225))
        vambrace = fitted_piece("hands", f"SplashVambrace{suffix}", (f"forearm.{suffix}",), lambda co: 1.105 < co.z < 1.355, COBALT, 0.020, 0.006, 0.0025, 0.005)
        set_plate_bands(vambrace, (1.125, 1.335))
        gauntlet = fitted_piece("hands", f"SplashGauntlet{suffix}", hand_group, lambda co: 1.055 < co.z < 1.235, DARK, 0.014, 0.0045, 0.002, 0.004)
        set_plate_bands(gauntlet, (1.085, 1.210))


def build_legs_and_feet():
    if "pants" not in PRESERVE_SLOTS:
        fitted_piece("pants", "SplashArmingFoundation", ("pelvis", "thigh.L", "thigh.R"), lambda co: 0.40 < co.z < 1.05 and abs(co.x) < 0.31, MAIL, 0.008, 0.002, 0.0012, 0.003)
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        thigh = (f"thigh.{suffix}",)
        shin = (f"shin.{suffix}", f"thigh.{suffix}")
        foot = (f"foot.{suffix}",)
        center_x = -0.131 if side < 0 else 0.131
        if "pants" not in PRESERVE_SLOTS:
            upper = fitted_piece("pants", f"SplashCuisse{suffix}Upper", thigh, lambda co: 0.665 < co.z < 0.955, STEEL, 0.024, 0.007, 0.0027, 0.004)
            lower = fitted_piece("pants", f"SplashCuisse{suffix}Lower", thigh, lambda co: 0.480 < co.z < 0.720, COBALT, 0.028, 0.007, 0.0027, 0.004)
            add_center_ridges(upper, center_x, 0.69, 0.93, 0.005, 0.026)
            add_center_ridges(lower, center_x, 0.50, 0.70, 0.005, 0.024)
            set_plate_bands(upper, (0.685, 0.935))
            set_plate_bands(lower, (0.500, 0.700))

        if "feet" not in PRESERVE_SLOTS:
            knee = fitted_piece("feet", f"SplashPoleyn{suffix}", shin, lambda co: 0.405 < co.z < 0.625, STEEL, 0.035, 0.008, 0.003, 0.003)
            set_plate_bands(knee, (0.430, 0.600))
            greave_upper = fitted_piece("feet", f"SplashGreave{suffix}Upper", (f"shin.{suffix}",), lambda co: 0.250 < co.z < 0.505, COBALT, 0.023, 0.007, 0.0025, 0.004)
            greave_lower = fitted_piece("feet", f"SplashGreave{suffix}Lower", (f"shin.{suffix}",), lambda co: 0.075 < co.z < 0.300, STEEL, 0.026, 0.007, 0.0025, 0.004)
            add_center_ridges(greave_upper, center_x, 0.27, 0.49, 0.005, 0.022)
            add_center_ridges(greave_lower, center_x, 0.095, 0.285, 0.005, 0.020)
            set_plate_bands(greave_upper, (0.270, 0.485))
            set_plate_bands(greave_lower, (0.095, 0.280))

            sabaton = fitted_piece("feet", f"SplashSabaton{suffix}", foot, lambda co: -0.01 < co.z < 0.235, DARK, 0.020, 0.006, 0.0022, 0.003)
            for polygon in sabaton.data.polygons:
                y = polygon.center.y
                if any(abs(y - band) < 0.018 for band in (-0.205, -0.145, -0.085, -0.025)):
                    polygon.material_index = 1


def ensure_uvs():
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.name.startswith(PREFIX):
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015, area_weight=0.35, correct_aspect=True, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")


def validate(body_before):
    if digest(BODY.data) != body_before:
        raise RuntimeError("Splash fitted build changed ConnectedBody")
    slots = {}
    for slot in ("head", "chest", "shoulders", "hands", "pants", "feet"):
        objects = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name.startswith(f"{PREFIX}{slot}_")]
        if not objects:
            raise RuntimeError(f"Armor slot is empty: {slot}")
        if any(not any(modifier.type == "ARMATURE" for modifier in obj.modifiers) for obj in objects):
            raise RuntimeError(f"Armor slot contains an unskinned object: {slot}")
        slots[slot] = len(objects)
    minimum_z = min(vertex.co.z for obj in bpy.data.objects if obj.name.startswith(f"{PREFIX}feet_") for vertex in obj.data.vertices)
    if minimum_z < -0.035 or minimum_z > 0.040:
        raise RuntimeError(f"Armor feet are not planted: min_z={minimum_z:.4f}")
    return slots


def main():
    if not os.path.exists(REFERENCE):
        raise RuntimeError(f"Approved reference is missing: {REFERENCE}")
    body_before = digest(BODY.data)
    RIG.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    tune_materials()
    remove_old_armor()
    if "head" not in PRESERVE_SLOTS:
        build_helmet()
    build_chest()
    if "shoulders" not in PRESERVE_SLOTS or "hands" not in PRESERVE_SLOTS:
        build_shoulders_and_arms()
    if "pants" not in PRESERVE_SLOTS or "feet" not in PRESERVE_SLOTS:
        build_legs_and_feet()
    ensure_uvs()
    slots = validate(body_before)
    RIG.data.pose_position = "POSE"
    RIG.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.scene["bk_armor_visual_pass"] = PASS_ID
    bpy.context.scene["bk_armor_reference_full_body"] = REFERENCE
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print(f"SPLASH_FITTED_ARMOR|file={OUTPUT}|body_unchanged=true|slots={slots}|pass={PASS_ID}")


if __name__ == "__main__":
    main()
