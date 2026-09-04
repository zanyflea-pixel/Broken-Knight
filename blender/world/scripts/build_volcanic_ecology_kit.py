import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = PROJECT_ROOT / "blender" / "world" / "geology" / "volcanic_ecology_kit_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "world" / "volcanic_ecology_kit_v1.glb"


def material(name, color, roughness=0.96, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def rock(name, location, scale, rotation, mat, seed, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    apply_transform(obj)
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        direction = vertex.co.normalized()
        fracture = math.sin(vertex.co.x * 3.1 + vertex.co.y * 2.4 + seed) * 0.08
        vertex.co += direction * (fracture + rng.uniform(-0.06, 0.06))
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def cone(name, location, radius1, radius2, depth, mat, vertices=7, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius1, radius2=radius2, depth=depth,
        location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Fractured edge", "BEVEL")
    bevel.width = min(0.10, radius1 * 0.12)
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def torus(name, location, major_radius, minor_radius, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius, minor_radius=minor_radius,
        major_segments=12, minor_segments=5, location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def rope_curve(name, points, radius, mat):
    curve_data = bpy.data.curves.new(f"{name}Curve", "CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 2
    curve_data.bevel_depth = radius
    curve_data.bevel_resolution = 1
    curve_data.resolution_u = 2
    spline = curve_data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1.0)
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def irregular_plate(name, center, size, height, mat, seed, vertices=7):
    rng = random.Random(seed)
    verts = []
    for z in (0.0, height):
        for index in range(vertices):
            angle = math.tau * float(index) / vertices + rng.uniform(-0.13, 0.13)
            radius = rng.uniform(0.72, 1.08)
            verts.append((
                center[0] + math.cos(angle) * size[0] * radius,
                center[1] + math.sin(angle) * size[1] * radius,
                center[2] + z + rng.uniform(-0.025, 0.025),
            ))
    faces = []
    faces.append(tuple(range(vertices - 1, -1, -1)))
    faces.append(tuple(range(vertices, vertices * 2)))
    for index in range(vertices):
        next_index = (index + 1) % vertices
        faces.append((index, next_index, vertices + next_index, vertices + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def obsidian_shard(name, location, radius, height, lean, mat, seed):
    rng = random.Random(seed)
    sides = 6
    verts = []
    rings = [
        (0.0, radius, (0.0, 0.0)),
        (height * 0.58, radius * 0.68, (lean[0] * 0.42, lean[1] * 0.42)),
        (height * 0.88, radius * 0.31, (lean[0] * 0.78, lean[1] * 0.78)),
    ]
    for z, ring_radius, offset in rings:
        for side in range(sides):
            angle = math.tau * float(side) / sides + rng.uniform(-0.055, 0.055)
            verts.append((
                location[0] + offset[0] + math.cos(angle) * ring_radius * rng.uniform(0.82, 1.12),
                location[1] + offset[1] + math.sin(angle) * ring_radius * rng.uniform(0.82, 1.12),
                location[2] + z,
            ))
    tip_index = len(verts)
    verts.append((location[0] + lean[0], location[1] + lean[1], location[2] + height))
    faces = [tuple(range(sides - 1, -1, -1))]
    for ring in range(len(rings) - 1):
        offset = ring * sides
        next_offset = (ring + 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((offset + side, offset + nxt, next_offset + nxt, next_offset + side))
    last_offset = (len(rings) - 1) * sides
    for side in range(sides):
        faces.append((last_offset + side, last_offset + (side + 1) % sides, tip_index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    bevel = obj.modifiers.new("Natural chipped edges", "BEVEL")
    bevel.width = min(0.045, radius * 0.055)
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def fumarole_mound(name, location, radius, height, basalt, sulfur, seed):
    rng = random.Random(seed)
    sides = 11
    verts = []
    rings = [
        (radius, 0.00),
        (radius * 0.62, height * 0.62),
        (radius * 0.30, height),
        (radius * 0.17, height * 0.48),
    ]
    for ring_index, (ring_radius, z) in enumerate(rings):
        for side in range(sides):
            angle = math.tau * float(side) / sides
            wobble = 1.0 + rng.uniform(-0.14, 0.14)
            verts.append((
                location[0] + math.cos(angle) * ring_radius * wobble,
                location[1] + math.sin(angle) * ring_radius * wobble,
                location[2] + z + rng.uniform(-0.035, 0.035),
            ))
    faces = []
    for ring in range(len(rings) - 1):
        offset = ring * sides
        next_offset = (ring + 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((offset + side, offset + nxt, next_offset + nxt, next_offset + side))
    faces.append(tuple(range((len(rings) - 1) * sides, len(rings) * sides)))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(basalt)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False

    # Mineral deposits are deliberately incomplete patches, not a toy-like ring.
    patches = [obj]
    for patch_index in range(4):
        angle = rng.uniform(0.0, math.tau)
        distance = radius * rng.uniform(0.27, 0.53)
        patches.append(irregular_plate(
            f"{name} mineral patch {patch_index:02d}",
            (location[0] + math.cos(angle) * distance,
             location[1] + math.sin(angle) * distance,
             location[2] + height * rng.uniform(0.72, 0.96)),
            (radius * rng.uniform(0.12, 0.25), radius * rng.uniform(0.07, 0.16)),
            0.025, sulfur, seed * 100 + patch_index, vertices=6,
        ))
    return patches


def branch_segment(name, start, end, radius_start, radius_end, mat, vertices=8):
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    length = direction.length
    midpoint = (start_vector + end_vector) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius_start, radius2=radius_end,
        depth=length, location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    obj.data.materials.append(mat)
    if radius_start > 0.09:
        rng = random.Random(sum(ord(character) for character in name) + int(length * 100.0))
        for vertex in obj.data.vertices:
            radial_scale = 1.0 + rng.uniform(-0.075, 0.075)
            vertex.co.x *= radial_scale
            vertex.co.y *= radial_scale
    bevel = obj.modifiers.new("Weathered branch edge", "BEVEL")
    bevel.width = min(0.035, radius_end * 0.35)
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def leaf_blade(name, location, length, width, rotation, mat, seed):
    rng = random.Random(seed)
    thickness = max(0.018, width * 0.055)
    outline = [
        (0.0, -length * 0.50, 0.0),
        (width * 0.48, -length * 0.12, rng.uniform(-0.025, 0.025)),
        (width * 0.40, length * 0.22, rng.uniform(-0.025, 0.025)),
        (0.0, length * 0.52, 0.0),
        (-width * 0.40, length * 0.22, rng.uniform(-0.025, 0.025)),
        (-width * 0.48, -length * 0.12, rng.uniform(-0.025, 0.025)),
    ]
    verts = [(x, y, z + thickness) for x, y, z in outline]
    verts.extend((x, y, z - thickness) for x, y, z in outline)
    sides = len(outline)
    faces = [tuple(range(sides)), tuple(range(sides * 2 - 1, sides - 1, -1))]
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((index, nxt, sides + nxt, sides + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    obj.data.materials.append(mat)
    return obj


def build_charred_snag(charcoal_bark, ember_bark):
    objects = []
    trunk_points = [
        (0.0, 0.0, 0.0), (0.12, -0.08, 2.7), (-0.18, 0.10, 5.4),
        (0.22, 0.06, 8.1), (0.04, -0.12, 10.7),
    ]
    radii = [(0.66, 0.55), (0.57, 0.44), (0.46, 0.30), (0.31, 0.10)]
    for index in range(len(trunk_points) - 1):
        objects.append(branch_segment(
            f"Snag trunk {index:02d}", trunk_points[index], trunk_points[index + 1],
            radii[index][0], radii[index][1], charcoal_bark, 10,
        ))
    # Two broken splinters prevent a manufactured flat-cut crown.
    objects.append(branch_segment("Snag broken crown A", (0.04, -0.12, 10.55), (-0.18, 0.04, 11.35), 0.09, 0.012, charcoal_bark, 6))
    objects.append(branch_segment("Snag broken crown B", (0.02, -0.08, 10.52), (0.28, -0.18, 11.02), 0.07, 0.010, charcoal_bark, 6))
    branch_specs = [
        ((-0.05, 0.02, 3.3), (-2.4, 0.5, 5.2), 0.22, 0.08),
        ((0.03, -0.02, 4.5), (2.1, -0.9, 6.0), 0.20, 0.07),
        ((-0.08, 0.08, 5.8), (-1.7, -1.5, 7.2), 0.17, 0.055),
        ((0.12, 0.05, 6.8), (1.8, 1.3, 8.3), 0.15, 0.045),
        ((0.10, -0.03, 7.7), (1.2, -1.6, 9.0), 0.13, 0.035),
        ((-0.02, -0.06, 8.6), (-1.2, 0.8, 9.7), 0.10, 0.025),
    ]
    for index, (start, end, radius_start, radius_end) in enumerate(branch_specs):
        objects.append(branch_segment(f"Snag branch {index:02d}", start, end, radius_start, radius_end, charcoal_bark, 7))
        branch_vector = Vector(end) - Vector(start)
        fork_start = Vector(start) + branch_vector * 0.63
        fork_end = Vector(end) + Vector(((-1) ** index * 0.55, 0.32 * math.sin(index * 1.7), 0.62))
        objects.append(branch_segment(
            f"Snag fork {index:02d}", fork_start, fork_end,
            radius_start * 0.52, max(0.018, radius_end * 0.40), charcoal_bark, 6,
        ))
    # Narrow vertical weathering seams add bark variation without a horizontal
    # material band or root-like sticks around the base.
    for index, (angle, z0, z1) in enumerate([
        (0.25, 0.9, 2.5), (2.15, 1.6, 3.8), (4.1, 2.9, 5.1),
        (1.25, 4.4, 6.2), (3.35, 5.7, 7.5),
    ]):
        radius = 0.44 - z0 * 0.025
        start = (math.cos(angle) * radius, math.sin(angle) * radius, z0)
        end = (math.cos(angle) * max(0.22, radius - 0.07), math.sin(angle) * max(0.22, radius - 0.07), z1)
        objects.append(branch_segment(f"Snag bark seam {index:02d}", start, end, 0.035, 0.018, ember_bark, 5))
    return join_named("CharredVolcanicSnag", objects, "weathered charred volcanic tree snag")


def build_ash_scrub(branch_mat, leaf_mat, dry_leaf_mat):
    rng = random.Random(11221)
    objects = []
    for stem_index in range(16):
        angle = stem_index * 2.399963 + rng.uniform(-0.22, 0.22)
        height = rng.uniform(1.2, 2.8)
        reach = rng.uniform(0.8, 2.1)
        start = (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0.06)
        end = (math.cos(angle) * reach, math.sin(angle) * reach, height)
        objects.append(branch_segment(
            f"Ash scrub stem {stem_index:02d}", start, end,
            rng.uniform(0.045, 0.075), rng.uniform(0.014, 0.027), branch_mat, 6,
        ))
        for leaf_index in range(4):
            t = 0.42 + leaf_index * 0.15
            location = Vector(start).lerp(Vector(end), t)
            leaf_angle = angle + (math.pi * 0.5 if leaf_index % 2 == 0 else -math.pi * 0.5)
            leaf_mat_choice = dry_leaf_mat if (stem_index + leaf_index) % 7 == 0 else leaf_mat
            objects.append(leaf_blade(
                f"Ash scrub leaf {stem_index:02d} {leaf_index:02d}", location,
                rng.uniform(0.38, 0.66), rng.uniform(0.16, 0.28),
                (rng.uniform(-0.25, 0.25), rng.uniform(-0.35, 0.35), leaf_angle),
                leaf_mat_choice, 11300 + stem_index * 10 + leaf_index,
            ))
    return join_named("AshScrubCluster", objects, "hardy volcanic ash scrub")


def build_fireweed_patch(stem_mat, leaf_mat, flower_mat):
    rng = random.Random(12491)
    objects = []
    for stem_index in range(22):
        angle = stem_index * 2.399963
        distance = 0.18 + math.sqrt(float(stem_index) / 22.0) * 2.3
        base = (math.cos(angle) * distance + rng.uniform(-0.18, 0.18),
                math.sin(angle) * distance * 0.72 + rng.uniform(-0.16, 0.16), 0.02)
        height = rng.uniform(0.72, 1.55)
        tip = (base[0] + rng.uniform(-0.10, 0.10), base[1] + rng.uniform(-0.10, 0.10), height)
        objects.append(branch_segment(
            f"Fireweed stem {stem_index:02d}", base, tip, 0.020, 0.010, stem_mat, 5,
        ))
        for leaf_index in range(3):
            location = Vector(base).lerp(Vector(tip), 0.30 + leaf_index * 0.18)
            objects.append(leaf_blade(
                f"Fireweed leaf {stem_index:02d} {leaf_index:02d}", location,
                rng.uniform(0.24, 0.39), rng.uniform(0.07, 0.11),
                (rng.uniform(-0.22, 0.22), rng.uniform(-0.25, 0.25), angle + leaf_index * 2.1),
                leaf_mat, 12600 + stem_index * 10 + leaf_index,
            ))
        for blossom_index in range(3):
            blossom_z = height - 0.08 - blossom_index * 0.105
            blossom_angle = angle + blossom_index * 2.2
            blossom_location = (
                tip[0] + math.cos(blossom_angle) * 0.055,
                tip[1] + math.sin(blossom_angle) * 0.055,
                blossom_z,
            )
            objects.append(rock(
                f"Fireweed blossom {stem_index:02d} {blossom_index:02d}", blossom_location,
                (0.075, 0.055, 0.060), (0.0, 0.0, blossom_angle),
                flower_mat, 12900 + stem_index * 10 + blossom_index, subdivisions=1,
            ))
    return join_named("FireweedPatch", objects, "hardy fireweed ground patch")


def join_named(name, objects, visual_role):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    result["visual_role"] = visual_role
    return result


def lava_shelf_mesh(name, basalt, cooled_crust):
    rng = random.Random(17531)
    segments = 18
    across = 5
    vertices = []
    for row in range(2):
        for segment in range(segments + 1):
            t = float(segment) / segments
            center_x = -10.0 + 20.0 * t
            center_y = math.sin(t * math.pi * 1.65) * 2.0 + math.sin(t * math.pi * 4.1) * 0.42
            tangent = (1.0, math.cos(t * math.pi * 1.65) * 0.52)
            tangent_length = math.sqrt(tangent[0] ** 2 + tangent[1] ** 2)
            normal = (-tangent[1] / tangent_length, tangent[0] / tangent_length)
            width = (3.2 + math.sin(t * math.pi) * 2.1) * (0.88 + math.sin(t * 17.0) * 0.06)
            for cross in range(across):
                lateral = (float(cross) / (across - 1) - 0.5) * width * 2.0
                x = center_x + normal[0] * lateral
                y = center_y + normal[1] * lateral
                edge = abs(float(cross) / (across - 1) - 0.5) * 2.0
                if row == 0:
                    z = -0.30 - edge * 0.10
                else:
                    z = 0.24 + math.sin(segment * 1.73 + cross * 2.1) * 0.12 - edge * 0.18
                vertices.append((x, y, z))

    row_stride = (segments + 1) * across
    faces = []
    material_indices = []
    # Top and bottom continuous flow skin.
    for layer in range(2):
        offset = layer * row_stride
        for segment in range(segments):
            for cross in range(across - 1):
                a = offset + segment * across + cross
                b = a + across
                c = b + 1
                d = a + 1
                faces.append((a, b, c, d) if layer == 1 else (d, c, b, a))
                material_indices.append(1 if layer == 1 and (segment * 3 + cross) % 9 == 0 else 0)
    # Close both banks and the source/toe ends.
    for cross in (0, across - 1):
        for segment in range(segments):
            bottom_a = segment * across + cross
            bottom_b = bottom_a + across
            top_a = row_stride + bottom_a
            top_b = row_stride + bottom_b
            faces.append((bottom_a, bottom_b, top_b, top_a) if cross == 0 else (top_a, top_b, bottom_b, bottom_a))
            material_indices.append(0)
    for segment in (0, segments):
        for cross in range(across - 1):
            bottom_a = segment * across + cross
            bottom_b = bottom_a + 1
            top_a = row_stride + bottom_a
            top_b = top_a + 1
            faces.append((bottom_a, top_a, top_b, bottom_b) if segment == 0 else (bottom_b, top_b, top_a, bottom_a))
            material_indices.append(0)

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(basalt)
    obj.data.materials.append(cooled_crust)
    for polygon, index in zip(obj.data.polygons, material_indices):
        polygon.material_index = index
        polygon.use_smooth = False
    bevel = obj.modifiers.new("Cooled flow edge", "BEVEL")
    bevel.width = 0.08
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    # Long, low ropes and fractured plates follow the flow direction.  They read
    # as a cooled lava field without the artificial hoops of the first pass.
    surface = [obj]
    for rope_index in range(5):
        points = []
        lateral = -2.3 + rope_index * 1.12
        for point_index in range(13):
            t = 0.07 + float(point_index) / 14.0
            x = -10.0 + 20.0 * t
            center_y = math.sin(t * math.pi * 1.65) * 2.0 + math.sin(t * math.pi * 4.1) * 0.42
            y = center_y + lateral + math.sin(t * 18.0 + rope_index * 1.7) * 0.22
            points.append((x, y, 0.38 + 0.035 * math.sin(point_index * 1.3)))
        surface.append(rope_curve(f"Lava flow rope {rope_index:02d}", points, 0.085, cooled_crust))
    for plate_index in range(22):
        t = 0.07 + float(plate_index) / 24.0
        x = -10.0 + 20.0 * t
        center_y = math.sin(t * math.pi * 1.65) * 2.0 + math.sin(t * math.pi * 4.1) * 0.42
        width = 2.4 + math.sin(t * math.pi) * 1.7
        y = center_y + rng.uniform(-width * 0.78, width * 0.78)
        surface.append(irregular_plate(
            f"Broken lava plate {plate_index:02d}", (x, y, 0.30),
            (rng.uniform(0.45, 1.05), rng.uniform(0.28, 0.72)),
            rng.uniform(0.05, 0.13), cooled_crust if plate_index % 5 == 0 else basalt,
            7100 + plate_index, vertices=rng.choice((6, 7, 8)),
        ))
    return join_named("RopeyLavaShelf", surface, "broad fractured cooled lava shelf")


def build_obsidian_cluster(obsidian, basalt):
    objects = [irregular_plate("Obsidian fractured base", (0.0, 0.0, 0.02), (4.5, 3.1), 0.24, basalt, 8021, 10)]
    specs = [
        ((-2.7, 0.3, 0.22), 1.00, 5.2, (-0.45, 0.25)),
        ((-0.9, -0.4, 0.22), 1.22, 7.2, (0.32, -0.18)),
        ((1.1, 0.1, 0.22), 1.06, 6.0, (-0.30, 0.32)),
        ((2.8, -0.2, 0.22), 0.78, 3.9, (0.25, -0.12)),
        ((0.0, 1.65, 0.22), 0.68, 3.5, (-0.22, 0.35)),
        ((-1.8, 1.7, 0.22), 0.48, 2.4, (0.15, 0.18)),
        ((2.0, 1.45, 0.22), 0.42, 2.0, (-0.12, 0.13)),
    ]
    for index, (location, radius, height, lean) in enumerate(specs):
        objects.append(obsidian_shard(f"Obsidian shard {index:02d}", location, radius, height, lean, obsidian, 8200 + index))
    for index in range(13):
        angle = index * 2.399963
        objects.append(rock(
            f"Obsidian base fall {index:02d}",
            (math.cos(angle) * (2.6 + 0.13 * index), math.sin(angle) * (2.0 + 0.06 * index), 0.28 + 0.05 * (index % 3)),
            (0.46 + 0.11 * (index % 3), 0.38 + 0.09 * (index % 2), 0.26 + 0.08 * (index % 4)),
            (0.12 * index, -0.08 * index, angle), basalt, 5100 + index,
        ))
    return join_named("ObsidianShardCluster", objects, "fractured obsidian landmark")


def build_vent_cluster(basalt, sulfur):
    objects = []
    specs = [(-2.8, -0.4, 0.95, 1.85), (0.0, 0.0, 1.35, 2.25), (2.8, 0.7, 0.72, 1.52), (1.1, 2.5, 0.52, 1.18)]
    for index, (x, y, height, radius) in enumerate(specs):
        objects.extend(fumarole_mound(f"Eroded vent {index:02d}", (x, y, 0.0), radius, height, basalt, sulfur, 9300 + index))
    for index in range(16):
        angle = index * 2.399963
        distance = 2.3 + 0.28 * index
        objects.append(rock(
            f"Sulfur crust {index:02d}",
            (math.cos(angle) * distance, math.sin(angle) * distance * 0.72, 0.08),
            (0.42 + 0.15 * (index % 3), 0.34 + 0.10 * (index % 2), 0.055),
            (0.0, 0.0, angle), sulfur, 6200 + index,
        ))
    return join_named("FumaroleVentCluster", objects, "mineral fumarole field")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    basalt = material("Cooled charcoal basalt", (0.030, 0.028, 0.026, 1.0))
    cooled_crust = material("Oxidized lava crust", (0.105, 0.052, 0.030, 1.0))
    obsidian = material("Obsidian glass", (0.010, 0.016, 0.028, 1.0), 0.22, 0.20)
    sulfur = material("Sulfur mineral crust", (0.32, 0.25, 0.045, 1.0))
    charcoal_bark = material("Charred split bark", (0.025, 0.021, 0.019, 1.0), 0.98)
    ember_bark = material("Weathered ember bark", (0.115, 0.047, 0.026, 1.0), 0.97)
    scrub_branch = material("Ash scrub branch", (0.10, 0.075, 0.052, 1.0), 0.96)
    ash_leaf = material("Ash scrub olive leaf", (0.13, 0.18, 0.085, 1.0), 0.94)
    dry_leaf = material("Ash scrub dry leaf", (0.26, 0.16, 0.065, 1.0), 0.96)
    fireweed_stem = material("Fireweed stem", (0.12, 0.21, 0.075, 1.0), 0.92)
    fireweed_leaf = material("Fireweed leaf", (0.15, 0.28, 0.09, 1.0), 0.92)
    fireweed_flower = material("Fireweed flower", (0.50, 0.075, 0.19, 1.0), 0.86)

    lava_shelf_mesh("RopeyLavaShelf", basalt, cooled_crust)
    build_obsidian_cluster(obsidian, basalt)
    build_vent_cluster(basalt, sulfur)
    build_charred_snag(charcoal_bark, ember_bark)
    build_ash_scrub(scrub_branch, ash_leaf, dry_leaf)
    build_fireweed_patch(fireweed_stem, fireweed_leaf, fireweed_flower)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    print(f"VOLCANIC_ECOLOGY_KIT_EXPORT|blend={BLEND_PATH}|glb={GLB_PATH}|meshes=6")


if __name__ == "__main__":
    main()
