"""Build a coherent reference-led royal plate harness on the locked hero.

This pass deliberately does not reuse the barrel cuirass or the body-copy
"metal muscles" from older candidates.  It authors a tapered, closed cuirass
and an overlapping plate system around the accepted rig.  Every decorative
edge is seated into its supporting plate and every major section overlaps the
next section of protection.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_ARTICULATED_ARMOR_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_ArticulatedRoyalCandidate.blend"),
))
PASS_ID = "RomanSovereignAnatomicalHarness20260821V16"
PREFIX = "RoyalArmor_"
RIG = bpy.data.objects["HeroRig"]
BODY = bpy.data.objects["ConnectedBody"]


def material(name, create=False):
    result = bpy.data.materials.get(name)
    if result is None and create:
        result = bpy.data.materials.new(name=name)
        result.use_nodes = True
    if result is None:
        raise RuntimeError("Missing material: " + name)
    return result


COBALT = material("Royal Cobalt Filigree Plate")
STEEL = material("Royal Blued Steel")
DARK = material("Royal Blackened Steel")
INTERIOR = material("Helmet Interior", True)
BRASS = material("Royal Gilt Brass")
BRIGHT = material("Royal Planished Edge Steel", True)
MAIL = material("Riveted Mail")
LEATHER = material("Harness Leather", True)
CRIMSON = material("Ducal Crimson Horsehair")
CRIMSON_DARK = material("Ducal Horsehair Shadow")


def tune_materials():
    palette = {
        COBALT: ((0.025, 0.065, 0.140, 1.0), 0.46, 0.68),
        STEEL: ((0.035, 0.055, 0.090, 1.0), 0.44, 0.72),
        DARK: ((0.028, 0.045, 0.075, 1.0), 0.58, 0.52),
        INTERIOR: ((0.002, 0.003, 0.006, 1.0), 0.90, 0.04),
        BRASS: ((0.34, 0.170, 0.040, 1.0), 0.46, 0.74),
        BRIGHT: ((0.100, 0.130, 0.180, 1.0), 0.43, 0.70),
        MAIL: ((0.040, 0.055, 0.075, 1.0), 0.64, 0.58),
        LEATHER: ((0.055, 0.022, 0.008, 1.0), 0.78, 0.02),
        CRIMSON: ((0.28, 0.010, 0.017, 1.0), 0.72, 0.00),
        CRIMSON_DARK: ((0.055, 0.003, 0.006, 1.0), 0.76, 0.00),
    }
    for mat, (color, roughness, metallic) in palette.items():
        mat.diffuse_color = color
        mat.use_nodes = True
        bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            # Old armor drafts referenced external texture images. Missing or
            # slow-loading images produced magenta/white armor and runtime
            # hitches, so this authored harness uses stable PBR constants.
            for input_name in ("Base Color", "Metallic", "Roughness", "Normal"):
                socket = bsdf.inputs.get(input_name)
                if socket:
                    for link in list(socket.links):
                        mat.node_tree.links.remove(link)
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic
            if bsdf.inputs.get("Weight"):
                bsdf.inputs["Weight"].default_value = 1.0
            if bsdf.inputs.get("Coat Weight"):
                bsdf.inputs["Coat Weight"].default_value = 0.08 if metallic > 0.5 else 0.0
            if bsdf.inputs.get("Coat Roughness"):
                bsdf.inputs["Coat Roughness"].default_value = 0.34


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
    result = bpy.data.collections.get(name)
    if result is None:
        result = bpy.data.collections.new(name)
        root.children.link(result)
    return result


def remove_old_armor():
    # This builder authors the complete harness, including its articulated
    # gauntlets.  Preserving an older hand slot here produced two coincident
    # sets of cuffs, palms and fingers in every subsequent candidate.
    for obj in list(bpy.data.objects):
        if obj.name.startswith(PREFIX):
            bpy.data.objects.remove(obj, do_unlink=True)


def mesh_object(slot, part, vertices, faces, materials, smooth=False):
    name = f"{PREFIX}{slot}_{part}"
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    armor_collection(slot).objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_connected_harness"] = True
    return obj


def rigid_skin(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG
    return obj


def bevel(obj, width=0.0025, segments=3):
    modifier = obj.modifiers.new("ForgedRolledEdges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def tube(slot, part, points, radius, mat, bone, sides=8):
    if len(points) < 2:
        raise RuntimeError("Tube needs at least two points: " + part)
    radii = [radius] * len(points) if isinstance(radius, (int, float)) else list(radius)
    vertices = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
        if normal.length < 0.00001:
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
    return rigid_skin(mesh_object(slot, part, vertices, faces, [mat], True), bone)


def swept_plume_vane(part, points, half_widths, thickness, mat):
    """Create one broad, tapered horsehair/feather lock following a soft arc.

    The visible width lies in the crest's sagittal plane and the narrow
    thickness lies across the helmet.  Adjacent vanes overlap at their bases,
    producing one planted plume instead of disconnected cylindrical spikes.
    """
    if len(points) < 2 or len(points) != len(half_widths):
        raise RuntimeError("Plume vane needs matching point and width arrays: " + part)
    vertices = []
    x_axis = Vector((1.0, 0.0, 0.0))
    for index, raw_point in enumerate(points):
        point = Vector(raw_point)
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(x_axis)
        if normal.length < 0.0001:
            normal = Vector((0.0, 0.0, 1.0))
        normal.normalize()
        across = tangent.cross(normal).normalized()
        width = half_widths[index]
        vertices.extend((
            tuple(point - normal * width - across * thickness * 0.5),
            tuple(point + normal * width - across * thickness * 0.5),
            tuple(point + normal * width + across * thickness * 0.5),
            tuple(point - normal * width + across * thickness * 0.5),
        ))
    faces = [(0, 1, 2, 3)]
    for ring in range(len(points) - 1):
        base = ring * 4
        nxt = (ring + 1) * 4
        faces.extend((
            (base, nxt, nxt + 1, base + 1),
            (base + 1, nxt + 1, nxt + 2, base + 2),
            (base + 2, nxt + 2, nxt + 3, base + 3),
            (base + 3, nxt + 3, nxt, base),
        ))
    end = (len(points) - 1) * 4
    faces.append((end, end + 3, end + 2, end + 1))
    obj = rigid_skin(mesh_object("head", part, vertices, faces, [mat, CRIMSON_DARK], True), "head")
    for polygon in obj.data.polygons:
        if polygon.index % 4 in (1, 2):
            polygon.material_index = 1
    bevel(obj, min(0.0022, thickness * 0.42), 3)
    return obj


def harness_strap(slot, part, points, width, thickness, mat, bone, outward_side=1.0):
    """Sweep a flat leather strap around a plate boundary.

    Width remains vertical while thickness follows the horizontal curve.  The
    strap therefore reads as cut leather rather than a decorative cable, and
    its centreline can be buried slightly inside both plates at its ends.
    """
    if len(points) < 2:
        raise RuntimeError("Harness strap needs at least two points: " + part)
    z_axis = Vector((0.0, 0.0, 1.0))
    vertices = []
    for index, raw_point in enumerate(points):
        point = Vector(raw_point)
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.z = 0.0
        if tangent.length < 0.0001:
            tangent = Vector((0.0, 1.0, 0.0))
        tangent.normalize()
        normal = tangent.cross(z_axis).normalized()
        if normal.x * outward_side < 0.0:
            normal.negate()
        vertices.extend((
            tuple(point - z_axis * width * 0.5 - normal * thickness * 0.5),
            tuple(point + z_axis * width * 0.5 - normal * thickness * 0.5),
            tuple(point + z_axis * width * 0.5 + normal * thickness * 0.5),
            tuple(point - z_axis * width * 0.5 + normal * thickness * 0.5),
        ))
    faces = [(0, 3, 2, 1)]
    for ring in range(len(points) - 1):
        base = ring * 4
        nxt = (ring + 1) * 4
        faces.extend((
            (base, nxt, nxt + 3, base + 3),
            (base + 1, base + 2, nxt + 2, nxt + 1),
            (base, base + 1, nxt + 1, nxt),
            (base + 3, nxt + 3, nxt + 2, base + 2),
        ))
    last = (len(points) - 1) * 4
    faces.append((last, last + 1, last + 2, last + 3))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat], False), bone)
    bevel(obj, min(0.0018, thickness * 0.28), 2)
    return obj


TORSO_RINGS = [
    (0.985, 0.190, 0.150, 0.125),
    (1.055, 0.180, 0.154, 0.116),
    (1.155, 0.177, 0.158, 0.105),
    (1.270, 0.210, 0.174, 0.122),
    (1.390, 0.296, 0.193, 0.132),
    (1.490, 0.326, 0.180, 0.130),
    (1.555, 0.262, 0.145, 0.112),
]

# Rounded armored skirt envelope.  The previous tassets were extruded from
# flat X/Z outlines, which read as a box around the hips in every oblique view.
HIP_RINGS = [
    (0.535, 0.205, 0.132, 0.112),
    (0.650, 0.224, 0.148, 0.124),
    (0.780, 0.238, 0.160, 0.136),
    (0.900, 0.240, 0.166, 0.142),
    (0.985, 0.218, 0.158, 0.140),
]


def interpolate_ring(rings, z):
    lower, upper = rings[0], rings[-1]
    for index in range(len(rings) - 1):
        if rings[index][0] <= z <= rings[index + 1][0]:
            lower, upper = rings[index], rings[index + 1]
            break
    ratio = (z - lower[0]) / max(0.0001, upper[0] - lower[0])
    return tuple(lower[index] + (upper[index] - lower[index]) * ratio for index in range(1, 4))


def torso_y(x, z, front=True, outward=0.0):
    half_x, front_depth, rear_depth = interpolate_ring(TORSO_RINGS, z)
    normalized = min(0.999, abs(x) / max(0.001, half_x))
    depth = front_depth if front else rear_depth
    value = depth * math.sqrt(max(0.001, 1.0 - normalized * normalized))
    if front:
        # A restrained central keel gives the cuirass a forged center line,
        # not the twin ballooned pectorals of the old body-copy armor.
        value += 0.010 * math.exp(-((x / 0.045) ** 2)) * math.sin(max(0.0, min(1.0, (z - 1.02) / 0.53)) * math.pi)
        return -value - outward
    return value + outward


def oval_shell(slot, part, rings, mat, bone, segments=72, keel=False):
    vertices = []
    for z, half_x, front, rear in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            x = half_x * math.cos(angle)
            depth = rear if math.sin(angle) >= 0 else front
            y = depth * math.sin(angle)
            if keel and y < 0.0:
                y -= 0.010 * math.exp(-((x / 0.045) ** 2)) * math.sin(max(0.0, min(1.0, (z - rings[0][0]) / max(0.001, rings[-1][0] - rings[0][0]))) * math.pi)
            vertices.append((x, y, z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
    faces.append(tuple(reversed(tuple(range(segments)))))
    faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, STEEL, DARK, BRASS], True), bone)
    # Front is the royal cobalt face, sides are blued steel, and the rear is
    # blackened plate.  These are connected faces of one closed shell.
    for polygon in obj.data.polygons[:-2]:
        center = polygon.center
        if center.y < -0.040:
            polygon.material_index = 0
        elif center.y > 0.035:
            polygon.material_index = 2
        else:
            polygon.material_index = 1
    bevel(obj, 0.0035, 4)
    return obj


def front_patch(slot, part, rows, mat, bone, outward=0.008, columns=13, crown=0.004, thickness=0.008):
    points_by_row = []
    vertices = []
    for z, left, right in rows:
        row_points = []
        for column in range(columns):
            ratio = column / (columns - 1)
            x = left + (right - left) * ratio
            y = torso_y(x, z, True, outward + crown * math.sin(math.pi * ratio))
            point = (x, y, z)
            row_points.append(point)
            vertices.append(point)
        points_by_row.append(row_points)
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            index = row * columns + column
            # Rows run crown-to-waist while columns run left-to-right. This
            # winding points the visible breastplate surface toward -Y.
            faces.append((index, index + columns, index + columns + 1, index + 1))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], True), bone)
    solid = obj.modifiers.new("BuriedPlateThickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 1.0
    solid.material_offset_rim = 1
    bevel(obj, 0.0022, 3)
    outline = list(points_by_row[0])
    outline.extend(row[-1] for row in points_by_row[1:])
    outline.extend(reversed(points_by_row[-1][:-1]))
    outline.extend(row[0] for row in reversed(points_by_row[1:-1]))
    outline.append(outline[0])
    outline = [(x, y - 0.0008, z) for x, y, z in outline]
    tube(slot, part + "SeatedGiltEdge", outline, 0.0034, BRASS, bone, 7)
    return obj


def back_patch(slot, part, rows, mat, bone, outward=0.008, columns=13, crown=0.003, thickness=0.008):
    points_by_row = []
    vertices = []
    for z, left, right in rows:
        row_points = []
        for column in range(columns):
            ratio = column / (columns - 1)
            x = left + (right - left) * ratio
            y = torso_y(x, z, False, outward + crown * math.sin(math.pi * ratio))
            point = (x, y, z)
            row_points.append(point)
            vertices.append(point)
        points_by_row.append(row_points)
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            index = row * columns + column
            # Back armor faces +Y, opposite the breastplate surface.
            faces.append((index, index + 1, index + columns + 1, index + columns))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], True), bone)
    solid = obj.modifiers.new("BuriedBackPlateThickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 1.0
    solid.material_offset_rim = 1
    bevel(obj, 0.0022, 3)
    outline = list(points_by_row[0])
    outline.extend(row[-1] for row in points_by_row[1:])
    outline.extend(reversed(points_by_row[-1][:-1]))
    outline.extend(row[0] for row in reversed(points_by_row[1:-1]))
    outline.append(outline[0])
    outline = [(x, y + 0.0008, z) for x, y, z in outline]
    tube(slot, part + "SeatedGiltEdge", outline, 0.0034, BRASS, bone, 7)
    return obj


def limb_basis(bone_name):
    bone = RIG.data.bones[bone_name]
    start = Vector(bone.head_local)
    end = Vector(bone.tail_local)
    axis = (end - start).normalized()
    u = axis.cross(Vector((0.0, 1.0, 0.0)))
    if u.length < 0.001:
        u = axis.cross(Vector((1.0, 0.0, 0.0)))
    u.normalize()
    v = axis.cross(u).normalized()
    return start, end, axis, u, v


def limb_shell(slot, part, bone_name, rings, mat, segments=40, edge_mode="both", edge_radius=0.0030, edge_mat=BRASS):
    start, end, axis, u, v = limb_basis(bone_name)
    vertices = []
    ring_points = []
    for t, radius_u, radius_v in rings:
        center = start.lerp(end, t)
        points = []
        for column in range(segments):
            angle = math.tau * column / segments
            point = center + u * math.cos(angle) * radius_u + v * math.sin(angle) * radius_v
            vertices.append(tuple(point))
            points.append(tuple(point))
        ring_points.append(points)
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
    faces.append(tuple(reversed(tuple(range(segments)))))
    faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], True), bone_name)
    for polygon in obj.data.polygons:
        if polygon.index < len(faces) - 2 and polygon.center.y > 0.015:
            polygon.material_index = 2
    bevel(obj, 0.0032, 4)
    edge_rows=[]
    if edge_mode in ("both","upper"):edge_rows.append(("UpperIntegralEdge",ring_points[0]))
    if edge_mode in ("both","lower"):edge_rows.append(("LowerIntegralEdge",ring_points[-1]))
    for edge_name,points in edge_rows:
        closed=points+[points[0]]
        tube(slot,part+edge_name,closed,edge_radius,edge_mat,bone_name,7)
    return obj


def limb_surface_path(slot, part, bone_name, samples, mat=BRASS, radius=0.0028):
    """Seat a forged ridge on an existing limb shell.

    Samples are ``(t, lateral_offset, front_depth)`` in the bone's own basis,
    keeping flutes attached when the limb rotates and avoiding world-axis
    rods that appeared detached in oblique views.
    """
    start,end,axis,u,v=limb_basis(bone_name)
    points=[]
    for t,lateral,depth in samples:
        center=start.lerp(end,t)
        points.append(tuple(center+u*lateral+v*depth))
    return tube(slot,part,points,radius,mat,bone_name,8)


def shoulder_cap(side):
    suffix = "L" if side < 0 else "R"
    center_x = side * 0.302
    center_z = 1.414
    radius_x, radius_y, radius_z = 0.155, 0.140, 0.158
    u_segments, v_segments = 34, 14
    vertices = []
    rows = []
    for row in range(v_segments):
        # Converge almost completely at the crown so the pauldron is a closed
        # continuous dome instead of ending in a visible upper shelf.
        beta = (math.pi * 0.495) * row / (v_segments - 1)
        radial = math.cos(beta)
        z = center_z + radius_z * math.sin(beta)
        points = []
        for column in range(u_segments):
            arc = -math.pi * 0.52 + math.pi * 1.04 * column / (u_segments - 1)
            x = center_x + side * radius_x * radial * math.cos(arc)
            y = radius_y * radial * math.sin(arc) - 0.006
            point = (x, y, z)
            vertices.append(point)
            points.append(point)
        rows.append(points)
    faces = []
    for row in range(v_segments - 1):
        for column in range(u_segments - 1):
            index = row * u_segments + column
            faces.append((index, index + 1, index + u_segments + 1, index + u_segments))
    bone = f"upper_arm.{suffix}"
    obj = rigid_skin(mesh_object("shoulders", f"SovereignSeatedPauldron{suffix}", vertices, faces, [STEEL, COBALT, BRASS, DARK], True), bone)
    for polygon in obj.data.polygons:
        if polygon.center.y < -0.02:
            polygon.material_index = 1
        elif polygon.center.y > 0.055:
            polygon.material_index = 3
    solid = obj.modifiers.new("PauldronPlateBody", "SOLIDIFY")
    solid.thickness = 0.009
    solid.offset = -0.25
    solid.material_offset_rim = 2
    bevel(obj, 0.0040, 4)
    # The lower articulation is bright rolled steel. Gold is reserved for the
    # heraldic fan and the two structural border ridges.
    tube("shoulders", f"PauldronLowerRolledEdge{suffix}", rows[0], 0.0036, BRIGHT, bone, 8)
    tube("shoulders", f"PauldronFrontRidge{suffix}", [row[0] for row in rows], 0.0035, BRASS, bone, 7)
    tube("shoulders", f"PauldronRearRidge{suffix}", [row[-1] for row in rows], 0.0035, BRASS, bone, 7)
    # Continue the fan language around the rear quarter so the pauldron is
    # authored from every view, not only decorated on its front face.
    for rear_index, column in enumerate((u_segments - 4, u_segments - 8)):
        tube("shoulders", f"PauldronRearFanFlute{suffix}{rear_index}",
             [row[column] for row in rows], 0.0024, BRIGHT, bone, 7)


def shoulder_lame(side, index, z_center, radius_x, radius_y, height, mat):
    """A curved lower pauldron lame seated under the crown plate."""
    suffix = "L" if side < 0 else "R"
    center_x = side * 0.337
    columns, rows_count = 30, 5
    vertices = []
    rows = []
    for row in range(rows_count):
        vertical = row / (rows_count - 1)
        z = z_center + height * (vertical - 0.5)
        scale = 1.0 - 0.08 * abs(vertical - 0.5)
        points = []
        for column in range(columns):
            arc = -math.pi * 0.54 + math.pi * 1.08 * column / (columns - 1)
            x = center_x + side * radius_x * scale * math.cos(arc)
            y = radius_y * scale * math.sin(arc) - 0.006
            point = (x, y, z)
            points.append(point)
            vertices.append(point)
        rows.append(points)
    faces = []
    for row in range(rows_count - 1):
        for column in range(columns - 1):
            i = row * columns + column
            faces.append((i, i + 1, i + columns + 1, i + columns))
    bone = f"upper_arm.{suffix}"
    obj = rigid_skin(mesh_object("shoulders", f"SovereignPauldronLame{suffix}{index}", vertices, faces, [mat, BRASS, DARK], True), bone)
    solid = obj.modifiers.new("OverlappingLameBody", "SOLIDIFY")
    solid.thickness = 0.008
    solid.offset = -0.2
    solid.material_offset_rim = 1
    bevel(obj, 0.0035, 4)
    tube("shoulders", f"PauldronLameLowerEdge{suffix}{index}", rows[0], 0.0030, BRIGHT, bone, 7)
    return obj


def shoulder_front_y(side, x, z, outward=0.0):
    """Return the forged front surface of the seated pauldron dome."""
    center_x=side*0.302
    normalized_x=(x-center_x)/0.155
    normalized_z=(z-1.414)/0.158
    depth=0.140*math.sqrt(max(0.025,1.0-normalized_x*normalized_x-normalized_z*normalized_z))
    return -0.006-depth-outward


def shoulder_heraldic_plate(side):
    """Curved, intersecting pauldron reinforcement replacing the flat plaque."""
    suffix="L" if side<0 else "R"
    bone=f"upper_arm.{suffix}"
    raw_rows=[
        (1.518,side*0.265,side*0.410),
        (1.480,side*0.248,side*0.435),
        (1.438,side*0.255,side*0.438),
        (1.404,side*0.276,side*0.416),
    ]
    rows=[];vertices=[];columns=17
    for z,a,b in raw_rows:
        left,right=min(a,b),max(a,b)
        points=[]
        for column in range(columns):
            ratio=column/(columns-1)
            x=left+(right-left)*ratio
            point=(x,shoulder_front_y(side,x,z,0.006),z)
            points.append(point);vertices.append(point)
        rows.append(points)
    faces=[]
    for row in range(len(rows)-1):
        for column in range(columns-1):
            i=row*columns+column
            faces.append((i,i+columns,i+columns+1,i+1))
    obj=rigid_skin(mesh_object("shoulders",f"SovereignCurvedPauldronHeraldicFace{suffix}",vertices,faces,[COBALT,BRASS,DARK],True),bone)
    solid=obj.modifiers.new("PauldronHeraldicForgedBody","SOLIDIFY")
    solid.thickness=0.009;solid.offset=-1.0;solid.material_offset_rim=1
    bevel(obj,0.0036,4)
    outline=list(rows[0]);outline.extend(row[-1] for row in rows[1:]);outline.extend(reversed(rows[-1][:-1]));outline.extend(row[0] for row in reversed(rows[1:-1]));outline.append(outline[0])
    tube("shoulders",f"SovereignCurvedPauldronHeraldicEdge{suffix}",outline,0.0032,BRASS,bone,8)
    return obj


def ellipsoid(slot, part, center, scales, mat, bone, rings=12, segments=36):
    vertices = []
    for row in range(rings + 1):
        latitude = -math.pi * 0.5 + math.pi * row / rings
        for column in range(segments):
            angle = math.tau * column / segments
            vertices.append((
                center[0] + scales[0] * math.cos(latitude) * math.cos(angle),
                center[1] + scales[1] * math.cos(latitude) * math.sin(angle),
                center[2] + scales[2] * math.sin(latitude),
            ))
    faces = []
    for row in range(rings):
        for column in range(segments):
            nxt = (column + 1) % segments
            index = row * segments + column
            faces.append((index, index + segments, (row + 1) * segments + nxt, row * segments + nxt))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], True), bone)
    bevel(obj, 0.0018, 2)
    return obj


def solid_plate(slot, part, outline, front_y, thickness, mat, bone, edge_mat=BRASS, edge_radius=0.0032):
    count = len(outline)
    vertices = [(x, front_y, z) for x, z in outline] + [(x, front_y + thickness, z) for x, z in outline]
    faces = [tuple(range(count)), tuple(reversed(tuple(range(count, count * 2))))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], False), bone)
    for polygon in obj.data.polygons[2:]:
        polygon.material_index = 1
    bevel(obj, 0.0042, 4)
    # The visible face is the first plane for front-facing (-Y) plates and the
    # extruded second plane for rear-facing (+Y) plates. Put trim on that true
    # outer surface; otherwise rear lames visually merge into one blank slab.
    visible_y = front_y - 0.0008 if front_y < 0.0 else front_y + thickness + 0.0008
    perimeter = [(x, visible_y, z) for x, z in outline]
    perimeter.append(perimeter[0])
    if edge_radius>0.0:
        tube(slot, part + "IntegralPerimeter", perimeter, edge_radius, edge_mat, bone, 7)
    return obj


def side_plate(slot, part, outline_yz, outer_x, thickness, mat, bone):
    """Forge a shaped plate on the left/right side of the harness.

    The inner face is driven toward the body, while the gilt perimeter stays
    on the outer face. This lets side tassets overlap both front and rear skirt
    plates instead of leaving a flat, unprotected hip wall.
    """
    count = len(outline_yz)
    inward = -math.copysign(thickness, outer_x)
    vertices = [(outer_x, y, z) for y, z in outline_yz]
    vertices.extend((outer_x + inward, y, z) for y, z in outline_yz)
    outer_face = tuple(range(count)) if outer_x < 0.0 else tuple(reversed(tuple(range(count))))
    inner_face = tuple(reversed(outer_face))
    inner_face = tuple(index + count for index in inner_face)
    faces = [outer_face, inner_face]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, count + index, count + nxt, nxt))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, BRASS, DARK], False), bone)
    for polygon in obj.data.polygons[2:]:
        polygon.material_index = 1
    bevel(obj, 0.0040, 4)
    perimeter = [(outer_x + math.copysign(0.0008, outer_x), y, z) for y, z in outline_yz]
    perimeter.append(perimeter[0])
    tube(slot, part + "IntegralPerimeter", perimeter, 0.0032, BRASS, bone, 7)
    return obj


def hip_y(x, z, front=True, outward=0.0):
    half_x,front_depth,rear_depth=interpolate_ring(HIP_RINGS,z)
    normalized=min(0.998,abs(x)/max(0.001,half_x))
    depth=front_depth if front else rear_depth
    value=depth*math.sqrt(max(0.002,1.0-normalized*normalized))
    return (-value-outward) if front else (value+outward)


def curved_hip_patch(part, rows, mat, front=True, outward=0.009, columns=19,
                     thickness=0.009, edge_mat=BRIGHT, edge_radius=0.0024):
    """Forge a tasset/culet plate directly on the rounded pelvis envelope."""
    vertices=[];row_points=[]
    for z,left,right in rows:
        points=[]
        for column in range(columns):
            ratio=column/(columns-1)
            x=left+(right-left)*ratio
            crown=0.0028*math.sin(math.pi*ratio)
            point=(x,hip_y(x,z,front,outward+crown),z)
            vertices.append(point);points.append(point)
        row_points.append(points)
    faces=[]
    for row in range(len(rows)-1):
        for column in range(columns-1):
            index=row*columns+column
            faces.append((index,index+columns,index+columns+1,index+1) if front else
                         (index,index+1,index+columns+1,index+columns))
    obj=rigid_skin(mesh_object("chest",part,vertices,faces,[mat,edge_mat,DARK],True),"pelvis")
    solid=obj.modifiers.new("RoundedArticulatedPlateBody","SOLIDIFY")
    solid.thickness=thickness;solid.offset=0.15;solid.material_offset_rim=1
    bevel(obj,0.0033,4)
    outline=list(row_points[0]);outline.extend(row[-1] for row in row_points[1:])
    outline.extend(reversed(row_points[-1][:-1]));outline.extend(row[0] for row in reversed(row_points[1:-1]));outline.append(outline[0])
    direction=-1.0 if front else 1.0
    outline=[(x,y+direction*0.0015,z) for x,y,z in outline]
    if edge_radius>0.0:tube("chest",part+"SeatedEdge",outline,edge_radius,edge_mat,"pelvis",8)
    return obj


def curved_side_tasset(part, side, z_top, z_bottom, mat, outward=0.010,
                       edge_mat=BRIGHT, edge_radius=0.0024):
    """Wrap one articulated hip lame continuously from front to rear."""
    rows_count=5;columns=27;vertices=[];row_points=[]
    for row in range(rows_count):
        t=row/(rows_count-1)
        z=z_top+(z_bottom-z_top)*t
        half_x,front_depth,rear_depth=interpolate_ring(HIP_RINGS,z)
        points=[]
        for column in range(columns):
            theta=math.radians(-58.0+116.0*column/(columns-1))
            depth=front_depth if theta<0.0 else rear_depth
            x=side*(half_x+outward)*math.cos(theta)
            y=(depth+outward)*math.sin(theta)
            point=(x,y,z)
            vertices.append(point);points.append(point)
        row_points.append(points)
    faces=[]
    for row in range(rows_count-1):
        for column in range(columns-1):
            index=row*columns+column
            face=(index,index+columns,index+columns+1,index+1)
            if side>0.0:face=tuple(reversed(face))
            faces.append(face)
    obj=rigid_skin(mesh_object("chest",part,vertices,faces,[mat,edge_mat,DARK],True),"pelvis")
    solid=obj.modifiers.new("RoundedSideTassetBody","SOLIDIFY")
    solid.thickness=0.009;solid.offset=-0.15;solid.material_offset_rim=1
    bevel(obj,0.0033,4)
    outline=list(row_points[0]);outline.extend(row[-1] for row in row_points[1:])
    outline.extend(reversed(row_points[-1][:-1]));outline.extend(row[0] for row in reversed(row_points[1:-1]));outline.append(outline[0])
    if edge_radius>0.0:tube("chest",part+"SeatedEdge",outline,edge_radius,edge_mat,"pelvis",8)
    return obj


def curved_hip_outline_patch(part, outline_xz, mat, front=True, outward=0.012,
                             thickness=0.009, edge_mat=BRIGHT,
                             edge_radius=0.0024):
    """Create a shield/chevron plate whose entire face follows the hip."""
    perimeter=[(x,hip_y(x,z,front,outward),z) for x,z in outline_xz]
    center_x=sum(x for x,z in outline_xz)/len(outline_xz)
    center_z=sum(z for x,z in outline_xz)/len(outline_xz)
    center=(center_x,hip_y(center_x,center_z,front,outward+0.0025),center_z)
    vertices=perimeter+[center]
    center_index=len(perimeter)
    faces=[]
    for index in range(len(perimeter)):
        nxt=(index+1)%len(perimeter)
        faces.append((center_index,nxt,index) if front else (center_index,index,nxt))
    obj=rigid_skin(mesh_object("chest",part,vertices,faces,[mat,edge_mat,DARK],True),"pelvis")
    solid=obj.modifiers.new("HipFormedPlateBody","SOLIDIFY")
    solid.thickness=thickness;solid.offset=0.15;solid.material_offset_rim=1
    bevel(obj,0.0032,4)
    direction=-1.0 if front else 1.0
    edge=[(x,y+direction*0.0015,z) for x,y,z in perimeter]+[
        (perimeter[0][0],perimeter[0][1]+direction*0.0015,perimeter[0][2])]
    if edge_radius>0.0:tube("chest",part+"SeatedEdge",edge,edge_radius,edge_mat,"pelvis",8)
    return obj


def curved_side_shield(part, side, mat, outward=0.014,
                       edge_mat=BRASS, edge_radius=0.0028):
    """Forge one long cupped tasset around the outside of the thigh."""
    row_specs=(
        (0.940,-48.0,48.0),
        (0.845,-58.0,58.0),
        (0.710,-54.0,54.0),
        (0.605,-32.0,32.0),
        (0.565,-8.0,8.0),
    )
    columns=29;vertices=[];rows=[]
    for z,theta_left,theta_right in row_specs:
        half_x,front_depth,rear_depth=interpolate_ring(HIP_RINGS,z)
        points=[]
        for column in range(columns):
            ratio=column/(columns-1)
            theta=math.radians(theta_left+(theta_right-theta_left)*ratio)
            depth=front_depth if theta<0.0 else rear_depth
            point=(side*(half_x+outward)*math.cos(theta),
                   (depth+outward)*math.sin(theta),z)
            vertices.append(point);points.append(point)
        rows.append(points)
    faces=[]
    for row in range(len(rows)-1):
        for column in range(columns-1):
            index=row*columns+column
            face=(index,index+columns,index+columns+1,index+1)
            if side>0.0:face=tuple(reversed(face))
            faces.append(face)
    obj=rigid_skin(mesh_object("chest",part,vertices,faces,[mat,edge_mat,DARK],True),"pelvis")
    solid=obj.modifiers.new("CuppedSideTassetBody","SOLIDIFY")
    solid.thickness=0.010;solid.offset=-0.12;solid.material_offset_rim=1
    bevel(obj,0.0035,4)
    outline=list(rows[0]);outline.extend(row[-1] for row in rows[1:])
    outline.extend(reversed(rows[-1][:-1]));outline.extend(row[0] for row in reversed(rows[1:-1]));outline.append(outline[0])
    if edge_radius>0.0:tube("chest",part+"SeatedEdge",outline,edge_radius,edge_mat,"pelvis",8)
    return obj


def forged_panel_3d(slot, part, outline, thickness, mat, bone, edge_mat=BRASS,
                    edge_radius=0.0030):
    """Create a shallow forged plate from a curved 3D perimeter.

    The rear surface is driven into the support along +Y, so the visible front
    can sit proud by a few millimeters without becoming a floating appliqué.
    """
    count = len(outline)
    vertices = [tuple(point) for point in outline]
    vertices.extend((point[0], point[1] + thickness, point[2]) for point in outline)
    faces = [tuple(range(count)), tuple(reversed(tuple(range(count, count * 2))))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    obj = rigid_skin(mesh_object(slot, part, vertices, faces, [mat, edge_mat, DARK], False), bone)
    for polygon in obj.data.polygons[2:]:
        polygon.material_index = 1
    bevel(obj, 0.0038, 4)
    perimeter = [tuple(point) for point in outline] + [tuple(outline[0])]
    if edge_radius>0.0:
        tube(slot, part + "IntegralRolledEdge", perimeter, edge_radius, edge_mat, bone, 7)
    return obj


def seated_rivet(slot, part, x, y, z, bone, radius=0.006):
    # Centre lies behind the plate surface, leaving a low embossed rivet head.
    direction = -1.0 if y < 0.0 else 1.0
    return ellipsoid(slot, part, (x, y - direction * radius * 0.52, z), (radius, radius * 0.55, radius), BRASS, bone, 7, 18)


def chest_path(part, coordinates, front=True, radius=0.0037, outward=None):
    points = []
    surface_offset = (0.038 if front else 0.036) if outward is None else outward
    for x, z in coordinates:
        y = torso_y(x, z, front, surface_offset)
        points.append((x, y, z))
    return tube("chest", part, points, radius, BRASS, "chest", 7)


def build_face_patch():
    for obj in list(bpy.data.objects):
        if obj.name.startswith("ProfessionalHelmetFace"):
            bpy.data.objects.remove(obj, do_unlink=True)
    group_indices = {BODY.vertex_groups[name].index for name in ("head", "neck") if BODY.vertex_groups.get(name)}
    keep = [
        1.575 < vertex.co.z < 1.845 and abs(vertex.co.x) < 0.105 and vertex.co.y < -0.045
        and any(item.group in group_indices and item.weight > 0.003 for item in vertex.groups)
        for vertex in BODY.data.vertices
    ]
    polygons = [tuple(poly.vertices) for poly in BODY.data.polygons if all(keep[index] for index in poly.vertices)]
    used = sorted({index for polygon in polygons for index in polygon})
    if not used:
        raise RuntimeError("Helmet face patch selected no body surface")
    remap = {source: target for target, source in enumerate(used)}
    vertices = [tuple(BODY.data.vertices[index].co + BODY.data.vertices[index].normal * 0.0005) for index in used]
    faces = [tuple(remap[index] for index in polygon) for polygon in polygons]
    mesh = bpy.data.meshes.new("ProfessionalHelmetFace_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(); mesh.update()
    obj = bpy.data.objects.new("ProfessionalHelmetFace", mesh)
    BODY.users_collection[0].objects.link(obj)
    skin = next((mat for mat in BODY.data.materials if mat and "skin" in mat.name.lower()), BODY.data.materials[0])
    mesh.materials.append(skin)
    for source_group in BODY.vertex_groups:
        obj.vertex_groups.new(name=source_group.name)
    for source, target in remap.items():
        for assignment in BODY.data.vertices[source].groups:
            obj.vertex_groups[assignment.group].add([target], assignment.weight, "REPLACE")
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorFaceRig", "ARMATURE")
    modifier.object = RIG
    obj.hide_render = True
    obj["bk_helmet_face_patch"] = True


def helmet_y(rings, x, z):
    lower, upper = rings[0], rings[-1]
    for index in range(len(rings) - 1):
        if rings[index][0] <= z <= rings[index + 1][0]:
            lower, upper = rings[index], rings[index + 1]
            break
    ratio = (z - lower[0]) / max(0.0001, upper[0] - lower[0])
    half_x = lower[1] + (upper[1] - lower[1]) * ratio
    front = lower[2] + (upper[2] - lower[2]) * ratio
    normalized = min(0.999, abs(x) / max(0.001, half_x))
    return -front * math.sqrt(max(0.001, 1.0 - normalized * normalized))


def helmet_rear_y(rings, x, z):
    lower,upper=rings[0],rings[-1]
    for index in range(len(rings)-1):
        if rings[index][0]<=z<=rings[index+1][0]:
            lower,upper=rings[index],rings[index+1];break
    ratio=(z-lower[0])/max(0.0001,upper[0]-lower[0])
    half_x=lower[1]+(upper[1]-lower[1])*ratio
    rear=lower[3]+(upper[3]-lower[3])*ratio
    normalized=min(0.999,abs(x)/max(0.001,half_x))
    return rear*math.sqrt(max(0.001,1.0-normalized*normalized))


def helmet_front_patch(part, rings, rows, mat, outward=0.010, columns=15, thickness=0.009, edge_radius=0.0034, edge_mat=BRASS):
    """Forge a visor plate that follows the helmet dome instead of an N-gon.

    Each row is ``(z, left_x, right_x)``. The quad grid preserves curvature
    through glTF triangulation, preventing the flat mask/faceted result that
    appeared in Godot with the former five-sided plates.
    """
    vertices=[]
    row_points=[]
    for z,left,right in rows:
        points=[]
        for column in range(columns):
            ratio=column/(columns-1)
            x=left+(right-left)*ratio
            y=helmet_y(rings,x,z)-outward-0.0025*math.sin(math.pi*ratio)
            point=(x,y,z)
            vertices.append(point)
            points.append(point)
        row_points.append(points)
    faces=[]
    for row in range(len(rows)-1):
        for column in range(columns-1):
            index=row*columns+column
            # Helmet front is -Y. Correct outward normals are essential here:
            # Godot otherwise lights these as backfaces and the visor becomes
            # a featureless black rectangle despite looking fine in Blender.
            faces.append((index,index+columns,index+columns+1,index+1))
    obj=rigid_skin(mesh_object("head",part,vertices,faces,[mat,BRASS,DARK],True),"head")
    solid=obj.modifiers.new("CurvedForgedPlateBody","SOLIDIFY")
    solid.thickness=thickness
    solid.offset=0.35
    solid.material_offset_rim=1
    bevel(obj,0.0038,4)
    outline=list(row_points[0])
    outline.extend(row[-1] for row in row_points[1:])
    outline.extend(reversed(row_points[-1][:-1]))
    outline.extend(row[0] for row in reversed(row_points[1:-1]))
    outline.append(outline[0])
    if edge_radius > 0.0:
        tube("head",part+"IntegralRolledEdge",outline,edge_radius,edge_mat,"head",8)
    return obj


def build_helmet():
    """Build the closed Broken Knight logo helm as a wearable armet."""
    rings = [
        (1.555, 0.102, 0.132, 0.106),
        (1.610, 0.116, 0.150, 0.112),
        (1.680, 0.126, 0.170, 0.116),
        (1.745, 0.130, 0.176, 0.116),
        (1.805, 0.128, 0.158, 0.112),
        (1.855, 0.114, 0.126, 0.104),
        (1.900, 0.078, 0.082, 0.076),
        (1.925, 0.026, 0.028, 0.026),
    ]
    segments = 80
    vertices = []
    for z, half_x, front, rear in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            vertices.append((half_x * math.cos(angle), (rear if math.sin(angle) >= 0 else front) * math.sin(angle), z))
    faces = []
    face_materials = []
    for row in range(len(rings) - 1):
        z_mid = (rings[row][0] + rings[row + 1][0]) * 0.5
        for column in range(segments):
            nxt = (column + 1) % segments
            angle = math.tau * (column + 0.5) / segments
            front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
            if front_delta < 0.95 and z_mid < 1.815:
                face_materials.append(2)
            elif front_delta < 1.40:
                face_materials.append(0)
            else:
                face_materials.append(1)
    faces.append(tuple(reversed(tuple(range(segments)))))
    face_materials.append(2)
    faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
    face_materials.append(1)
    shell = rigid_skin(mesh_object("head", "CrownlessSovereignClosedArmet", vertices, faces, [COBALT, STEEL, DARK, BRASS], True), "head")
    for polygon, index in zip(shell.data.polygons, face_materials):
        polygon.material_index = index
    dome_smoothing = shell.modifiers.new("ForgedDomeSmoothing", "SUBSURF")
    dome_smoothing.levels = 1
    dome_smoothing.render_levels = 1
    solid = shell.modifiers.new("HistoricallyForgedHelmetBody", "SOLIDIFY")
    solid.thickness = 0.008
    solid.offset = -1.0
    solid.material_offset_rim = 3
    bevel(shell, 0.0024, 3)

    lower_ring = []
    z, half_x, front, rear = rings[0]
    for index in range(65):
        angle = math.tau * index / 64
        lower_ring.append((half_x * math.cos(angle), (rear if math.sin(angle) >= 0 else front) * math.sin(angle), z))
    tube("head", "CrownlessArmetLowerRolledRim", lower_ring, 0.0042, BRASS, "head", 8)

    # The logo helmet is fully enclosed. Two brow plates overlap a narrow,
    # black-backed eye slit; the pointed bevor then protects the whole lower
    # face. No flesh or separate face patch can appear through this assembly.
    upper_left_rows = [
        (1.798, -0.124, -0.010),
        (1.760, -0.128, -0.009),
        (1.725, -0.121, -0.008),
        (1.710, -0.108, -0.008),
    ]
    upper_right_rows = [(z, -right, -left) for z,left,right in upper_left_rows]
    helmet_front_patch("SovereignCurvedUpperVisorL", rings, upper_left_rows, STEEL, 0.011, 17, 0.010, 0.0027, BRIGHT)
    helmet_front_patch("SovereignCurvedUpperVisorR", rings, upper_right_rows, STEEL, 0.011, 17, 0.010, 0.0027, BRIGHT)

    lower_left_rows = [
        (1.670, -0.116, -0.008),
        (1.638, -0.119, -0.007),
        (1.594, -0.106, -0.007),
        (1.558, -0.072, -0.007),
        (1.532, -0.030, -0.007),
    ]
    lower_right_rows = [(z, -right, -left) for z,left,right in lower_left_rows]
    helmet_front_patch("SovereignCurvedPointedBevorL", rings, lower_left_rows, STEEL, 0.012, 17, 0.011)
    helmet_front_patch("SovereignCurvedPointedBevorR", rings, lower_right_rows, STEEL, 0.012, 17, 0.011)

    # A genuinely recessed black eye band is visible between the visor and
    # bevor. It follows the dome and sits behind both overlapping plate lips,
    # so it reads as a sight rather than a face-shaped floating mask.
    eye_left_rows = [
        (1.710, -0.119, -0.012),
        (1.690, -0.116, -0.010),
        (1.674, -0.102, -0.010),
    ]
    eye_right_rows = [(z, -right, -left) for z,left,right in eye_left_rows]
    helmet_front_patch("SovereignRecessedEyeSlitL", rings, eye_left_rows, INTERIOR, 0.007, 17, 0.004, 0.0)
    helmet_front_patch("SovereignRecessedEyeSlitR", rings, eye_right_rows, INTERIOR, 0.007, 17, 0.004, 0.0)

    # Flush dark vent insets are backed by the continuous skull shell.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        for index, x_abs in enumerate((0.030, 0.054, 0.078)):
            x = side * x_abs
            outline = [
                (x - 0.0075, helmet_y(rings, x - 0.0075, 1.653) - 0.0200, 1.653),
                (x + 0.0075, helmet_y(rings, x + 0.0075, 1.653) - 0.0200, 1.653),
                (x + 0.0055, helmet_y(rings, x + 0.0055, 1.574) - 0.0200, 1.574),
                (x - 0.0055, helmet_y(rings, x - 0.0055, 1.574) - 0.0200, 1.574),
            ]
            # The deep back intersects the bevor while the dark face and gilt
            # lip remain readable, so this is an integrated vent boss rather
            # than a disconnected decoration.
            forged_panel_3d("head", f"CrownlessArmetBreathSlot{suffix}{index}",
                            outline,0.0070,INTERIOR,"head",BRIGHT,0.0015)
            # The recessed centre remains readable under dark runtime
            # lighting; it is half-buried into the inset rather than laid on
            # the helmet as a separate bar.
            tube("head",f"CrownlessArmetBreathGroove{suffix}{index}",[
                (x,helmet_y(rings,x,1.644)-0.0210,1.644),
                (x,helmet_y(rings,x,1.584)-0.0210,1.584),
            ],0.0038,INTERIOR,"head",8)

        # Angular cheek borders visually separate the bevor from the skull
        # and give the closed face the strong pointed geometry of the logo.
        cheek=[]
        for x,z in ((side*0.112,1.670),(side*0.108,1.625),
                    (side*0.082,1.575),(side*0.030,1.536)):
            cheek.append((x,helmet_y(rings,x,z)-0.0165,z))
        tube("head",f"SovereignAngularCheekBorder{suffix}",cheek,
             0.0027,BRIGHT,"head",8)

    # Keep this first version pristine. A single clean central ridge closes the
    # seam from brow to chin; battle cracks can be added as a later variant.
    ridge_points=[]
    for z in (1.798,1.756,1.714,1.675,1.632,1.590,1.550,1.532):
        ridge_points.append((0.0,helmet_y(rings,0.0,z)-0.016,z))
    tube("head","DucalUnbrokenCenterRidge",ridge_points,0.0050,BRASS,"head",10)

    # Ear pivots and visor hinge pins intersect the skull shell and visor edges.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        boss = ellipsoid("head", f"CrownlessArmetVisorPivot{suffix}", (side * 0.126, -0.002, 1.700), (0.025, 0.030, 0.038), STEEL, "head", 9, 30)
        for polygon in boss.data.polygons:
            polygon.material_index = 0
        seated_rivet("head", f"CrownlessArmetPivotPin{suffix}", side * 0.134, -0.024, 1.700, "head", 0.008)
        # Planished temple-to-jaw ribs add structure without outlining every
        # facial plate in gold. They remain seated against the curved shell.
        temple=[]
        for x,z in ((side*0.112,1.785),(side*0.119,1.735),(side*0.110,1.675),(side*0.090,1.615),(side*0.058,1.565)):
            temple.append((x,helmet_y(rings,x,z)-0.017,z))
        tube("head",f"SovereignPlanishedCheekRib{suffix}",temple,0.0025,BRIGHT,"head",8)
        for rivet_index,(x,z) in enumerate(((side*0.103,1.748),(side*0.093,1.635))):
            seated_rivet("head",f"SovereignCheekRivet{suffix}{rivet_index}",x,
                         helmet_y(rings,x,z)-0.019,z,"head",0.0043)

    # Crownless forged dome: shallow longitudinal flutes are seated directly
    # into the skull curvature. They strengthen and visually lengthen the helm
    # without adding a crest, prongs, plume, or any hovering ornament.
    tube("head", "CrownlessArmetDomeCenterFlute", [
        (0.0, helmet_y(rings, 0.0, 1.798) - 0.006, 1.798),
        (0.0, helmet_y(rings, 0.0, 1.855) - 0.005, 1.855),
        (0.0, helmet_y(rings, 0.0, 1.900) - 0.004, 1.900),
        (0.0, helmet_y(rings, 0.0, 1.923) - 0.003, 1.923),
    ], 0.0030, BRASS, "head", 8)
    for side in (-1.0, 1.0):
        suffix="L" if side<0 else "R"
        flute=[]
        for x,z in ((side*0.095,1.804),(side*0.086,1.848),(side*0.060,1.888),(side*0.023,1.918)):
            flute.append((x,helmet_y(rings,x,z)-0.0045,z))
        tube("head",f"CrownlessArmetDomeFlute{suffix}",flute,0.0026,BRASS,"head",8)
        for index,(x,z) in enumerate(((side*0.112,1.815),(side*0.073,1.875))):
            seated_rivet("head",f"CrownlessArmetDomeRivet{suffix}{index}",x,helmet_y(rings,x,z)-0.006,z,"head",0.0042)

    # Rear construction mirrors the front's forged logic: one seated centre
    # seam and two converging flutes, all following the shell rather than
    # floating behind it.
    rear_center=[]
    for z in (1.570,1.650,1.735,1.815,1.875,1.920):
        rear_center.append((0.0,helmet_rear_y(rings,0.0,z)+0.004,z))
    tube("head","CrownlessArmetRearCenterSeam",rear_center,0.0028,BRASS,"head",8)
    for side in (-1.0,1.0):
        suffix="L" if side<0 else "R"
        rear_flute=[]
        for x,z in ((side*0.080,1.590),(side*0.092,1.690),(side*0.082,1.790),(side*0.050,1.875),(side*0.018,1.918)):
            rear_flute.append((x,helmet_rear_y(rings,x,z)+0.0035,z))
        tube("head",f"CrownlessArmetRearFlute{suffix}",rear_flute,0.0025,BRASS,"head",8)
        for rivet_index,(x,z) in enumerate(((side*0.098,1.620),(side*0.110,1.700),(side*0.095,1.780),(side*0.060,1.860))):
            seated_rivet("head",f"CrownlessArmetRearRivet{suffix}{rivet_index}",
                         x,helmet_rear_y(rings,x,z)+0.008,z,"head",0.0047)

    # A low, riveted crest rail is forged into the dome and carries the red
    # feather plume directly. This restores the heroic feather silhouette
    # without reintroducing the rejected crown or a floating crest block.
    crest_rail=[
        (0.0,-0.052,1.914),(0.0,-0.025,1.929),(0.0,0.010,1.934),
        (0.0,0.050,1.925),(0.0,0.085,1.904),
    ]
    tube("head","SovereignIntegratedCrestRail",crest_rail,[0.0070,0.0080,0.0085,0.0080,0.0065],BRASS,"head",10)
    tube("head","SovereignCrestRailRecess",[(x,y,z+0.001) for x,y,z in crest_rail],[0.0035,0.0045,0.0048,0.0043,0.0032],DARK,"head",9)
    # Roman-style horsehair crest: narrow overlapping vanes create the mass,
    # while finer irregular strands break up the former solid comb silhouette.
    for vane_index in range(-8,9):
        edge=abs(vane_index)/8.0;order=vane_index+8
        x=vane_index*0.0046;root_y=-0.052+order*0.0085
        tail_bias=vane_index*0.006;drop=edge*0.022
        points=[
            (x*.78,root_y,1.922),(x*.88,root_y+.024,1.992-drop*.06),
            (x,root_y+.064,2.055-drop*.12),(x*.98,root_y+.115,2.105-drop*.18),
            (x*.90,root_y+.175,2.128-drop*.28),(x*.72,root_y+.245+tail_bias*.15,2.112-drop*.42),
            (x*.52,root_y+.315+tail_bias*.35,2.065-drop*.58),(x*.32,root_y+.385+tail_bias*.65,1.990-drop*.78),
            (x*.12,root_y+.450+tail_bias,1.885-drop),
        ]
        widths=[.0048,.0078,.0108,.0122,.0118,.0100,.0076,.0048,.0010]
        swept_plume_vane(f"SovereignRomanPlumeVane{order:02d}",points,widths,
                         .0045 if abs(vane_index)<=1 else .0038,
                         CRIMSON if order%3 else CRIMSON_DARK)
    for strand_index in range(37):
        t=strand_index/36.0;offset=strand_index-18
        x=offset*.00215+math.sin(strand_index*1.71)*.0014
        root_y=-.052+t*.132
        length_bias=(t-.5)*.026
        strand=[
            (x*.70,root_y,1.925),(x*.82,root_y+.035,1.997),
            (x,root_y+.090,2.070),(x*.92,root_y+.155,2.112),
            (x*.70,root_y+.235,2.097),(x*.46,root_y+.315+length_bias*.30,2.040),
            (x*.22,root_y+.395+length_bias*.65,1.965),(0.0,root_y+.462+length_bias,1.875-abs(offset)*.0018),
        ]
        tube("head",f"SovereignRomanHorsehair{strand_index:02d}",strand,
             [.0017,.0020,.0021,.0019,.0016,.0012,.00075,.00025],
             CRIMSON_DARK if strand_index%4==0 else CRIMSON,"head",8)


def build_chest():
    oval_shell("chest", "SovereignTaperedClosedCuirass", TORSO_RINGS, DARK, "chest", 80, True)
    # One continuous, strongly curved heart breastplate replaces the former
    # twin smooth pectoral slabs. Its pointed lower keel overlaps the abdomen
    # while the broad upper rows remain buried beneath the armholes/gorget.
    front_patch("chest", "SovereignForgedHeartBreastplate", [
        (1.525, -0.205, 0.205), (1.480, -0.285, 0.285),
        (1.405, -0.300, 0.300), (1.325, -0.276, 0.276),
        (1.245, -0.235, 0.235), (1.165, -0.186, 0.186),
        (1.090, -0.112, 0.112), (1.025, -0.025, 0.025),
    ], STEEL, "chest", 0.011, 25, 0.010, 0.011)
    # A shallow lower reinforcement is visibly seated underneath the heart
    # point and above the wrap fauld, giving the torso real plate hierarchy.
    front_patch("chest", "SovereignLowerBreastReinforcement", [
        (1.245, -0.245, 0.245), (1.175, -0.226, 0.226),
        (1.105, -0.196, 0.196), (1.035, -0.168, 0.168),
    ], COBALT, "chest", 0.0065, 21, 0.003, 0.007)
    back_patch("chest", "SovereignArticulatedBackplate", [(1.525, -0.245, 0.245), (1.405, -0.295, 0.295), (1.270, -0.255, 0.255), (1.080, -0.205, 0.205)], STEEL, "chest", 0.008, 15, 0.003, 0.008)
    back_patch("chest", "SovereignBackplateInset", [
        (1.465, -0.170, 0.170), (1.385, -0.205, 0.205),
        (1.295, -0.195, 0.195), (1.205, -0.162, 0.162),
        (1.115, -0.112, 0.112),
    ], COBALT, "chest", 0.016, 15, 0.004, 0.011)

    # Nested gorget rings overlap both the cuirass and lower helmet edge.
    oval_shell("chest", "SovereignGorgetLower", [(1.515, 0.224, 0.130, 0.108), (1.565, 0.193, 0.118, 0.100)], STEEL, "chest", 64)
    oval_shell("chest", "SovereignGorgetUpper", [(1.552, 0.190, 0.116, 0.098), (1.615, 0.145, 0.096, 0.085)], DARK, "chest", 64)
    for z, width, front, rear, name in (
        (1.010, 0.195, 0.151, 0.126, "Upper"),
        (0.955, 0.205, 0.154, 0.132, "Middle"),
        (0.895, 0.216, 0.157, 0.140, "Lower"),
    ):
        oval_shell("chest", f"SovereignWrapFauld{name}", [(z - 0.045, width, front, rear), (z + 0.032, width - 0.010, front - 0.006, rear - 0.004)], COBALT if name == "Middle" else STEEL, "pelvis", 64)
    # Reference-led hip construction: three centered chevron lames protect the
    # groin while one long cupped tasset wraps each outer thigh. This leaves
    # real movement gaps between the legs and removes the rectangular skirt
    # made by six front tiles, six side tiles and three rear slabs.
    front_chevrons=(
        ("Upper", [(-0.170,.948),(0.170,.948),(0.158,.885),(0.0,.825),(-0.158,.885)], STEEL, .010),
        ("Middle",[(-0.160,.870),(0.160,.870),(0.145,.795),(0.0,.725),(-0.145,.795)], COBALT,.014),
        ("Lower", [(-0.145,.765),(0.145,.765),(0.128,.685),(0.0,.605),(-0.128,.685)], STEEL, .018),
    )
    rear_chevrons=(
        ("Upper", [(-0.165,.945),(0.165,.945),(0.150,.885),(0.0,.835),(-0.150,.885)], STEEL, .010),
        ("Middle",[(-0.155,.875),(0.155,.875),(0.140,.805),(0.0,.745),(-0.140,.805)], COBALT,.014),
        ("Lower", [(-0.140,.785),(0.140,.785),(0.124,.710),(0.0,.640),(-0.124,.710)], STEEL, .018),
    )
    for name,outline,material_value,outward in front_chevrons:
        curved_hip_outline_patch(f"SovereignFrontChevronTasset{name}",outline,
                                 material_value,True,outward,.009,BRIGHT,.0024)
    for name,outline,material_value,outward in rear_chevrons:
        curved_hip_outline_patch(f"SovereignRearChevronCulet{name}",outline,
                                 material_value,False,outward,.009,BRIGHT,.0023)
    for side in (-1.0,1.0):
        suffix="L" if side<0 else "R"
        curved_side_shield(f"SovereignCuppedSideTasset{suffix}",side,DARK,.016,BRASS,.0028)
        # One top hinge and one low emboss pin state how the shield tasset is
        # attached without covering it in rows of decorative dots.
        for rivet_index,z in enumerate((.905,.650)):
            half_x,front_depth,rear_depth=interpolate_ring(HIP_RINGS,z)
            ellipsoid("chest",f"SovereignHipPivot{suffix}{rivet_index}",
                      (side*(half_x+.016),0.0,z),(.0065,.0060,.0065),BRASS,"pelvis",7,18)
    # Rolled flutes are formed into the plate itself; there is no separate
    # badge or escutcheon hovering over the cuirass.
    chest_path("SovereignBreastCentralKeel", [(0.0, 1.515), (0.0, 1.035)], True, 0.0045)
    chest_path("SovereignBreastFluteL", [(-0.015,1.492),(-0.095,1.455),(-0.185,1.370),(-0.225,1.270),(-0.165,1.170),(-0.060,1.070)], True, 0.0030)
    chest_path("SovereignBreastFluteR", [(0.015,1.492),(0.095,1.455),(0.185,1.370),(0.225,1.270),(0.165,1.170),(0.060,1.070)], True, 0.0030)
    chest_path("SovereignBreastInnerFluteL", [(-0.020,1.455),(-0.072,1.390),(-0.105,1.300),(-0.082,1.205),(-0.035,1.115)], True, 0.0024)
    chest_path("SovereignBreastInnerFluteR", [(0.020,1.455),(0.072,1.390),(0.105,1.300),(0.082,1.205),(0.035,1.115)], True, 0.0024)
    # Nested V-shaped collar edges echo the reference's articulated gorget and
    # break up the large upper chest without adding a hovering emblem.
    chest_path("SovereignCollarChevronUpper", [(-0.190,1.515),(0.0,1.465),(0.190,1.515)], True, 0.0033)
    chest_path("SovereignCollarChevronLower", [(-0.225,1.478),(0.0,1.420),(0.225,1.478)], True, 0.0030)
    for index, (x, z) in enumerate(((-0.245, 1.500), (-0.285, 1.425), (-0.235, 1.320), (0.245, 1.500), (0.285, 1.425), (0.235, 1.320))):
        seated_rivet("chest", f"SovereignBreastRivet{index}", x, torso_y(x, z, True, 0.039), z, "chest", 0.0065)
    for index,(x,z) in enumerate(((-0.135,1.405),(-0.188,1.300),(-0.142,1.190),(0.135,1.405),(0.188,1.300),(0.142,1.190))):
        seated_rivet("chest",f"SovereignBreastInnerRivet{index}",x,
                     torso_y(x,z,True,0.041),z,"chest",0.0052)
    # Connected embossed chevrons articulate the broad back instead of leaving
    # it as one undecorated black plane.
    for index, z in enumerate((1.415, 1.285, 1.155)):
        points = [(-0.205 + index * 0.012, torso_y(-0.205 + index * 0.012, z, False, 0.036), z),
                  (0.0, torso_y(0.0, z - 0.045, False, 0.036), z - 0.045),
                  (0.205 - index * 0.012, torso_y(0.205 - index * 0.012, z, False, 0.036), z)]
        tube("chest", f"SovereignBackChevron{index}", points, 0.0038, BRASS, "chest", 7)
    chest_path("SovereignBackSpineKeel", [(0.0, 1.510), (0.0, 1.085)], False, 0.0040)
    chest_path("SovereignBackContourL", [(-0.180,1.500),(-0.235,1.420),(-0.220,1.320),(-0.180,1.220),(-0.105,1.105)], False, 0.0030)
    chest_path("SovereignBackContourR", [(0.180,1.500),(0.235,1.420),(0.220,1.320),(0.180,1.220),(0.105,1.105)], False, 0.0030)
    for index, (x, z) in enumerate(((-0.230, 1.455), (0.230, 1.455), (-0.205, 1.260), (0.205, 1.260), (-0.170, 1.105), (0.170, 1.105))):
        seated_rivet("chest", f"SovereignBackRivet{index}", x, torso_y(x, z, False, 0.036), z, "chest", 0.0058)

    # The breast and back plates are visibly harnessed together around the
    # flanks. Each strap terminates beneath both plate edges.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        for index, z in enumerate((1.365, 1.185)):
            half_x, front_depth, rear_depth = interpolate_ring(TORSO_RINGS, z)
            x_edge = side * (half_x + 0.010)
            path = [
                (side * (half_x - 0.030), -front_depth * 0.55, z),
                (x_edge, -0.040, z),
                (x_edge, 0.040, z),
                (side * (half_x - 0.028), rear_depth * 0.58, z),
            ]
            harness_strap("chest", f"SovereignCuirassSideStrap{suffix}{index}", path, 0.027, 0.007, LEATHER, "chest", side)
            buckle_x = x_edge + side * 0.004
            buckle = [
                (buckle_x, -0.028, z - 0.020), (buckle_x, 0.028, z - 0.020),
                (buckle_x, 0.028, z + 0.020), (buckle_x, -0.028, z + 0.020),
                (buckle_x, -0.028, z - 0.020),
            ]
            tube("chest", f"SovereignCuirassSideBuckle{suffix}{index}", buckle, 0.0034, BRASS, "chest", 7)

    # Rolled armhole edges disappear beneath the pauldrons instead of ending
    # in an exposed shoulder gap.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        armhole = []
        for x, z in ((side * 0.205, 1.548), (side * 0.278, 1.505), (side * 0.315, 1.435), (side * 0.292, 1.345)):
            armhole.append((x, torso_y(x, z, True, 0.018), z))
        tube("chest", f"SovereignRolledArmhole{suffix}", armhole, 0.0042, BRASS, "chest", 8)

    # Closed war belt and interlocked codpiece bridge the fauld and tassets.
    oval_shell("chest", "SovereignClosedWarBelt", [(0.945, 0.218, 0.160, 0.143), (0.985, 0.208, 0.157, 0.137)], DARK, "pelvis", 64)
    solid_plate("chest", "SovereignBeltBuckle", [(-0.038, 0.986), (0.038, 0.986), (0.046, 0.930), (0.0, 0.902), (-0.046, 0.930)], -0.166, 0.012, COBALT, "pelvis", BRIGHT, 0.0025)
    # Only the small hinge heads remain visible. Their foundation is buried
    # beneath the belt and first tasset lame instead of hanging as a brown,
    # box-forming strap over the finished armor.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        x = side * 0.132
        for index, z in enumerate((0.953, 0.862)):
            seated_rivet("chest", f"SovereignFrontTassetRivet{suffix}{index}", x, hip_y(x, z, True, 0.025), z, "pelvis", 0.0053)


def build_arms_and_shoulders():
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        shoulder_cap(side)
        upper = f"upper_arm.{suffix}"
        fore = f"forearm.{suffix}"
        # Two narrow bell lames are aligned to the actual upper-arm bone. They
        # slide below the pauldron dome instead of forming world-aligned boxes
        # across the arm in the warrior stance.
        limb_shell("shoulders", f"SovereignShoulderBellLame{suffix}1", upper,
                   [(0.025, 0.132, 0.126), (0.155, 0.128, 0.121)],
                   COBALT, 40, "lower", 0.0027, BRIGHT)
        limb_shell("shoulders", f"SovereignShoulderBellLame{suffix}2", upper,
                   [(0.135, 0.129, 0.122), (0.285, 0.123, 0.116)],
                   STEEL, 40, "lower", 0.0026, BRIGHT)
        # A restrained forged fan is seated into the pauldron itself.  It is
        # the shoulder accent from the reference, not another armor plate.
        shoulder_bone = f"upper_arm.{suffix}"
        for flute_index, lateral in enumerate((-0.045, 0.0, 0.045)):
            flute_points=[]
            for x_abs,z in ((0.273+lateral*0.28,1.535),(0.300+lateral*0.68,1.472),(0.332+lateral,1.405)):
                x=side*x_abs
                flute_points.append((x,shoulder_front_y(side,x,z,0.007),z))
            tube("shoulders",f"SovereignPauldronFanFlute{suffix}{flute_index}",flute_points,0.0026,BRASS,shoulder_bone,8)
        for rivet_index,(x_abs,z) in enumerate(((0.248,1.492),(0.365,1.455),(0.392,1.404))):
            x=side*x_abs
            seated_rivet("shoulders",f"SovereignPauldronRivet{suffix}{rivet_index}",
                         x,shoulder_front_y(side,x,z,0.008),z,shoulder_bone,0.0052)
        limb_shell("shoulders", f"SovereignArmpitMail{suffix}", upper,
                   [(0.02, 0.116, 0.111), (0.30, 0.112, 0.107)],
                   MAIL, 36, "none")
        # One continuous rerebrace replaces the two bulging shells and their
        # separate suspension/gilt bands.  Its upper edge is buried under the
        # lowest pauldron lame and its lower edge overlaps the couter.
        limb_shell("shoulders", f"SovereignContinuousRerebrace{suffix}", upper,
                   [(0.255, 0.124, 0.117), (0.46, 0.116, 0.109),
                    (0.72, 0.104, 0.098), (0.94, 0.092, 0.088)],
                   STEEL, 40, "lower", 0.0027, BRIGHT)
        limb_shell("hands", f"SovereignElbowMail{suffix}", fore,
                   [(-0.07, 0.097, 0.092), (0.15, 0.092, 0.087)],
                   CRIMSON_DARK, 36, "none")
        limb_shell("hands", f"SovereignVambrace{suffix}", fore,
                   [(0.11, 0.096, 0.091), (0.48, 0.087, 0.081),
                    (0.88, 0.071, 0.066)],
                   COBALT, 40, "both", 0.0026, BRIGHT)
        limb_surface_path("shoulders",f"SovereignRerebraceKeel{suffix}",upper,[(0.27,0.0,0.120),(0.46,0.0,0.112),(0.71,0.0,0.101),(0.92,0.0,0.090)],BRASS,0.0027)
        limb_surface_path("hands",f"SovereignVambraceKeel{suffix}",fore,[(0.12,0.0,0.098),(0.50,0.0,0.084),(0.88,0.0,0.070)],BRASS,0.0028)
        elbow = Vector(RIG.data.bones[fore].head_local) + Vector((0.0, -0.050, 0.0))
        ellipsoid("hands", f"SovereignPoleynCouter{suffix}", elbow, (0.098, 0.060, 0.103), STEEL, fore, 10, 32)
        # A wing catches blows at the elbow and overlaps the couter boss.
        outer = side * 0.075
        solid_plate("hands", f"SovereignCouterWing{suffix}", [
            (elbow.x + outer * 0.20, elbow.z + 0.070),
            (elbow.x + outer, elbow.z + 0.035),
            (elbow.x + outer * 1.15, elbow.z - 0.030),
            (elbow.x + outer * 0.30, elbow.z - 0.060),
        ], -0.108, 0.014, COBALT, fore, BRIGHT, 0.0025)
        for index, z_offset in enumerate((0.034, -0.034)):
            seated_rivet("hands", f"SovereignCouterHingePin{suffix}{index}", elbow.x + outer * 0.28, -0.114, elbow.z + z_offset, fore, 0.0058)

        # The cuff belongs to the forearm; the fitted backhand belongs to the
        # hand.  This prevents the old mitten-shaped wrist from stretching
        # across the joint and leaves the finger lames visually distinct.
        hand_bone=f"hand.{suffix}"
        limb_shell("hands",f"SovereignGauntletCuff{suffix}",fore,[(0.78,0.080,0.073),(0.96,0.074,0.067),(1.04,0.070,0.063)],COBALT,32,"lower",0.0025,BRIGHT)
        limb_shell("hands",f"SovereignFittedBackhand{suffix}",hand_bone,
                   [(-0.18,0.069,0.050),(0.75,0.067,0.047),
                    (1.70,0.061,0.042),(2.65,0.052,0.036),
                    (3.45,0.044,0.031)],
                   STEEL,36,"both",0.0021,BRIGHT)
        limb_surface_path("hands",f"SovereignGauntletKeel{suffix}",hand_bone,
                          [(0.0,0.0,0.051),(0.9,0.0,0.048),
                           (1.9,0.0,0.041),(3.25,0.0,0.033)],BRASS,0.0023)
        # MPFB's finger-chain suffix is mirrored relative to this rig's hand
        # suffix: negative-X hand.L owns the _r fingers, and vice versa.
        finger_side="r" if side<0 else "l"
        digit_scale={"thumb":1.05,"index":1.00,"middle":1.04,"ring":0.98,"pinky":0.84}
        for digit,scale in digit_scale.items():
            for phalanx in (1,2,3):
                bone_name=f"{digit}_0{phalanx}_{finger_side}"
                if RIG.data.bones.get(bone_name) is None:continue
                taper=1.0-0.10*(phalanx-1)
                radius_u=0.0185*scale*taper
                radius_v=0.0152*scale*taper
                if phalanx==1:
                    finger_bone=RIG.data.bones[bone_name]
                    knuckle=Vector(finger_bone.head_local).lerp(Vector(finger_bone.tail_local),0.10)
                    ellipsoid("hands",f"SovereignKnucklePlate{suffix}{digit.title()}",
                              knuckle,(radius_u*1.16,radius_v*1.02,radius_u*1.05),
                              COBALT,bone_name,8,24)
                limb_shell("hands",f"SovereignFingerLame{suffix}{digit.title()}{phalanx}",bone_name,
                           [(-0.18,radius_u,radius_v),(0.72,radius_u*0.94,radius_v*0.92),(1.05,radius_u*0.80,radius_v*0.78)],
                           STEEL if phalanx%2 else COBALT,20,"lower",0.0015,BRIGHT)
                if phalanx==3:
                    finger_bone=RIG.data.bones[bone_name]
                    fingertip=Vector(finger_bone.head_local).lerp(Vector(finger_bone.tail_local),0.92)
                    ellipsoid("hands",f"SovereignFingertip{suffix}{digit.title()}",
                              fingertip,(radius_u*0.80,radius_v*0.76,radius_u*0.78),
                              STEEL,bone_name,8,22)


def build_legs_and_feet():
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        thigh = f"thigh.{suffix}"
        shin = f"shin.{suffix}"
        foot = f"foot.{suffix}"
        limb_shell("pants", f"SovereignCuisseUpper{suffix}", thigh,
                   [(0.03, 0.125, 0.145), (0.38, 0.116, 0.135), (0.68, 0.102, 0.118)],
                   STEEL, 40, "lower", 0.0027, BRIGHT)
        limb_shell("pants", f"SovereignCuisseLower{suffix}", thigh,
                   [(0.60, 0.106, 0.120), (0.88, 0.092, 0.103)],
                   COBALT, 40, "lower", 0.0026, BRIGHT)
        # Long formed cuisse flutes replace the old flat shield appliqué.
        limb_surface_path("pants",f"SovereignCuisseKeel{suffix}",thigh,[(0.06,0.0,0.147),(0.36,0.0,0.137),(0.66,0.0,0.121),(0.88,0.0,0.105)],BRASS,0.0028)
        for flute_index,lateral in enumerate((-0.048,0.048)):
            limb_surface_path("pants",f"SovereignCuisseFlute{suffix}{flute_index}",thigh,[(0.10,lateral,0.144),(0.38,lateral*0.90,0.134),(0.65,lateral*0.72,0.119)],BRASS,0.0023)
        knee = Vector(RIG.data.bones[shin].head_local)
        center_x = knee.x
        solid_plate("feet", f"SovereignAngularPoleyn{suffix}", [(center_x - 0.092, knee.z + 0.055), (center_x, knee.z + 0.098), (center_x + 0.092, knee.z + 0.055), (center_x + 0.078, knee.z - 0.052), (center_x, knee.z - 0.092), (center_x - 0.078, knee.z - 0.052)], knee.y - 0.097, 0.023, COBALT, shin, BRIGHT, 0.0028)
        solid_plate("feet", f"SovereignPoleynInset{suffix}", [(center_x - 0.057, knee.z + 0.040), (center_x, knee.z + 0.070), (center_x + 0.057, knee.z + 0.040), (center_x + 0.047, knee.z - 0.038), (center_x, knee.z - 0.063), (center_x - 0.047, knee.z - 0.038)], knee.y - 0.108, 0.015, DARK, shin, BRIGHT, 0.0018)
        limb_shell("feet", f"SovereignKneeMail{suffix}", shin,
                   [(-0.10, 0.094, 0.095), (0.15, 0.090, 0.090)],
                   MAIL, 36, "none")
        # An outward swept poleyn wing is the deliberate knee accent from the
        # reference. It enters the couter body at the inner edge, so it reads
        # as one forged knee defense rather than an emblem hovering nearby.
        outer_x = center_x + side * 0.142
        inner_x = center_x + side * 0.055
        solid_plate("feet", f"SovereignPoleynWing{suffix}", [
            (inner_x, knee.z + 0.050),
            (center_x + side * 0.112, knee.z + 0.078),
            (outer_x, knee.z + 0.028),
            (center_x + side * 0.122, knee.z - 0.032),
            (inner_x, knee.z - 0.048),
        ], knee.y - 0.103, 0.017, STEEL, shin, BRIGHT, 0.0025)
        tube("feet", f"SovereignPoleynWingSpine{suffix}", [
            (inner_x, knee.y - 0.122, knee.z + 0.038),
            (center_x + side * 0.110, knee.y - 0.122, knee.z + 0.015),
            (outer_x - side * 0.010, knee.y - 0.122, knee.z + 0.026),
        ], 0.0026, BRASS, shin, 8)
        # Sliding lames overlap the cuisse, poleyn and greave so a bent knee
        # never exposes a single unsupported ring of mail.
        solid_plate("feet", f"SovereignPoleynUpperLame{suffix}", [(center_x - 0.075, knee.z + 0.130), (center_x + 0.075, knee.z + 0.130), (center_x + 0.083, knee.z + 0.055), (center_x - 0.083, knee.z + 0.055)], knee.y - 0.090, 0.015, STEEL, shin, BRIGHT, 0.0022)
        solid_plate("feet", f"SovereignPoleynLowerLame{suffix}", [(center_x - 0.080, knee.z - 0.052), (center_x + 0.080, knee.z - 0.052), (center_x + 0.069, knee.z - 0.132), (center_x - 0.069, knee.z - 0.132)], knee.y - 0.089, 0.015, COBALT, shin, BRIGHT, 0.0022)
        solid_plate("feet", f"SovereignRearKneeStrap{suffix}", [(center_x - 0.082, knee.z + 0.025), (center_x + 0.082, knee.z + 0.025), (center_x + 0.082, knee.z - 0.005), (center_x - 0.082, knee.z - 0.005)], knee.y + 0.073, 0.008, LEATHER, shin)
        for index, x_offset in enumerate((-0.067, 0.067)):
            seated_rivet("feet", f"SovereignPoleynPivot{suffix}{index}", center_x + x_offset, knee.y - 0.116, knee.z + 0.005, shin, 0.0060)
        limb_shell("feet", f"SovereignGreaveUpper{suffix}", shin,
                   [(0.08, 0.097, 0.105), (0.45, 0.088, 0.095)],
                   STEEL, 40, "lower", 0.0027, BRIGHT)
        limb_shell("feet", f"SovereignGreaveLower{suffix}", shin,
                   [(0.38, 0.091, 0.097), (0.92, 0.074, 0.077)],
                   COBALT, 40, "lower", 0.0026, BRIGHT)
        shin_center = Vector(RIG.data.bones[shin].head_local).lerp(Vector(RIG.data.bones[shin].tail_local), 0.60)
        limb_surface_path("feet",f"SovereignGreaveKeel{suffix}",shin,[(0.10,0.0,0.107),(0.40,0.0,0.098),(0.68,0.0,0.087),(0.91,0.0,0.078)],BRASS,0.0028)
        for flute_index,lateral in enumerate((-0.038,0.038)):
            limb_surface_path("feet",f"SovereignGreaveFlute{suffix}{flute_index}",shin,[(0.16,lateral,0.104),(0.45,lateral*0.86,0.095),(0.76,lateral*0.60,0.083)],BRASS,0.0022)
        # Rear closure straps and an outer hinge line give the greave a
        # plausible way to open, close, and remain attached to the calf.
        for index, z_offset in enumerate((0.105, -0.090)):
            z = shin_center.z + z_offset
            solid_plate("feet", f"SovereignGreaveRearStrap{suffix}{index}", [(shin_center.x - 0.072, z + 0.014), (shin_center.x + 0.072, z + 0.014), (shin_center.x + 0.072, z - 0.014), (shin_center.x - 0.072, z - 0.014)], 0.070, 0.008, LEATHER, shin)
        hinge_x = shin_center.x + side * 0.082
        for index, z_offset in enumerate((0.105, 0.010, -0.085)):
            z = shin_center.z + z_offset
            tube("feet", f"SovereignGreaveHingeBarrel{suffix}{index}", [(hinge_x, -0.004, z - 0.025), (hinge_x, -0.004, z + 0.025)], 0.0055, BRASS, shin, 8)
        # The ankle collar overlaps the greave and sabaton, making the foot a
        # continuation of the leg harness instead of a shoe stuck underneath.
        limb_shell("feet", f"SovereignAnkleArticulation{suffix}", foot,
                   [(-0.22, 0.083, 0.085), (0.04, 0.101, 0.078), (0.18, 0.104, 0.073)],
                   STEEL, 40, "lower", 0.0027, BRIGHT)
        limb_shell("feet", f"SovereignClosedSabaton{suffix}", foot,
                   [(-0.10, 0.090, 0.079), (0.18, 0.104, 0.074),
                    (0.58, 0.109, 0.061), (0.98, 0.101, 0.048),
                    (1.26, 0.074, 0.032)],
                   DARK, 44, "none")
        lame_specs = (
            (0.06, 0.30, 0.107, 0.078),
            (0.25, 0.49, 0.111, 0.071),
            (0.44, 0.68, 0.112, 0.064),
            (0.63, 0.87, 0.108, 0.057),
            (0.82, 1.08, 0.099, 0.049),
        )
        for index, (start_t, end_t, radius_u, radius_v) in enumerate(lame_specs):
            limb_shell("feet", f"SovereignSabatonLame{suffix}{index}", foot,
                       [(start_t, radius_u, radius_v), (end_t, radius_u * 0.96, radius_v * 0.91)],
                       COBALT if index % 2 else STEEL, 36, "lower", 0.0020, BRIGHT)
        limb_surface_path("feet", f"SovereignSabatonKeel{suffix}", foot,
                          [(0.02, 0.0, 0.082), (0.32, 0.0, 0.074),
                           (0.63, 0.0, 0.062), (0.94, 0.0, 0.048),
                           (1.20, 0.0, 0.034)], BRASS, 0.0025)
        limb_shell("feet", f"SovereignPointedToeCap{suffix}", foot,
                   [(0.98, 0.101, 0.048), (1.22, 0.081, 0.035),
                    (1.34, 0.046, 0.020)],
                   STEEL, 36, "upper", 0.0018, BRIGHT)


def ensure_uvs():
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.name.startswith(PREFIX):
            continue
        if obj.data.uv_layers:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.012, correct_aspect=True, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")


def validate():
    for slot in ("head", "chest", "shoulders", "hands", "pants", "feet"):
        objects = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name.startswith(f"{PREFIX}{slot}_")]
        if not objects:
            raise RuntimeError("Empty armor slot: " + slot)
        if any(not any(mod.type == "ARMATURE" for mod in obj.modifiers) for obj in objects):
            raise RuntimeError("Unrigged armor object in slot: " + slot)


def main():
    RIG.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    tune_materials()
    remove_old_armor()
    build_face_patch()
    build_helmet()
    build_chest()
    build_arms_and_shoulders()
    build_legs_and_feet()
    ensure_uvs()
    validate()
    face_patch = bpy.data.objects.get("ProfessionalHelmetFace")
    if face_patch:
        face_patch.hide_render = True
    BODY.hide_render = True
    for obj in bpy.data.objects:
        if obj.name.startswith("HeroHair"):
            obj.hide_render = True
        elif obj.name.startswith("ProfessionalEyes") or obj.name.startswith("ProfessionalBrows"):
            obj.hide_render = True
    RIG.data.pose_position = "POSE"
    RIG.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.scene["bk_armor_visual_pass"] = PASS_ID
    bpy.context.scene["bk_armor_construction"] = "closed_tapered_overlapping_articulated_harness"
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print("ARTICULATED_ROYAL_HARNESS|file=%s|pass=%s" % (OUTPUT, PASS_ID))


if __name__ == "__main__":
    main()
