import math
import random
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = PROJECT_ROOT / "blender" / "world" / "geology" / "regional_geology_kit_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "world" / "regional_geology_kit_v1.glb"


def material(name, color, roughness=0.96):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def box_project_uv(obj, meters_per_tile=6.0):
    """Give generated rock faces stable world-like UVs for Godot materials."""
    layer = obj.data.uv_layers.new(name="GeologyUV")
    for polygon in obj.data.polygons:
        normal = polygon.normal
        for loop_index in polygon.loop_indices:
            co = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            if abs(normal.z) >= abs(normal.x) and abs(normal.z) >= abs(normal.y):
                uv = (co.x / meters_per_tile, co.y / meters_per_tile)
            elif abs(normal.x) >= abs(normal.y):
                uv = (co.y / meters_per_tile, co.z / meters_per_tile)
            else:
                uv = (co.x / meters_per_tile, co.z / meters_per_tile)
            layer.data[loop_index].uv = uv


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
        strata = math.sin(vertex.co.z * 3.7 + seed * 0.19) * 0.06
        fracture = math.sin(vertex.co.x * 2.3 + vertex.co.y * 3.1 + seed) * 0.045
        vertex.co += direction * (strata + fracture + rng.uniform(-0.045, 0.045))
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def column(name, location, radius, height, rotation, mat, vertices=6):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=height, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Chipped column edges", "BEVEL")
    bevel.width = min(0.11, radius * 0.12)
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def stratified_block(name, location, dimensions, rotation, mat, seed):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = dimensions
    obj.rotation_euler = rotation
    apply_transform(obj)
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        side_break = math.sin(vertex.co.z * 2.1 + seed * 0.23) * dimensions[0] * 0.025
        face_break = math.sin(vertex.co.x * 1.7 + seed) * dimensions[1] * 0.035
        vertex.co.x += side_break + rng.uniform(-0.08, 0.08)
        vertex.co.y += face_break + rng.uniform(-0.055, 0.055)
        vertex.co.z += rng.uniform(-0.045, 0.045)
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Broken strata edges", "BEVEL")
    bevel.width = 0.13
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def eroded_cliff_mesh(name, stone, stone_dark):
    """Build one continuous fractured escarpment instead of a wall of separate blocks."""
    rng = random.Random(8917)
    x_steps = 12
    z_levels = (0.0, 1.25, 2.55, 3.9, 5.15, 6.25)
    vertices = []
    for back in (False, True):
        for row, base_z in enumerate(z_levels):
            for column in range(x_steps + 1):
                x = -8.5 + 17.0 * column / x_steps
                edge_fade = math.sin(math.pi * column / x_steps)
                if back:
                    y = 1.35 + 0.16 * math.sin(column * 1.31 + row * 0.42)
                    z = base_z + 0.12 * math.sin(column * 0.73)
                else:
                    ledge = (0.22 if row in (1, 3, 5) else -0.08) * edge_fade
                    y = -1.30 + ledge + 0.22 * math.sin(column * 1.17 + row * 2.03)
                    z = base_z + 0.16 * math.sin(column * 0.81 + row) + rng.uniform(-0.07, 0.07)
                vertices.append((x, y, z))

    stride = x_steps + 1
    layer_size = stride * len(z_levels)
    faces = []
    material_indices = []

    # Fractured but unbroken front and back faces.
    for back in (0, 1):
        offset = back * layer_size
        for row in range(len(z_levels) - 1):
            for column in range(x_steps):
                a = offset + row * stride + column
                b = a + 1
                c = a + stride + 1
                d = a + stride
                faces.append((a, b, c, d) if not back else (d, c, b, a))
                material_indices.append(1 if row in (0, 2) else 0)

    # Continuous top, base and ends make the formation watertight from every angle.
    for column in range(x_steps):
        front_a = (len(z_levels) - 1) * stride + column
        back_a = layer_size + front_a
        faces.append((front_a, front_a + 1, back_a + 1, back_a))
        material_indices.append(0)
        faces.append((column + 1, column, layer_size + column, layer_size + column + 1))
        material_indices.append(1)
    for column in (0, x_steps):
        for row in range(len(z_levels) - 1):
            front_a = row * stride + column
            front_b = front_a + stride
            back_a = layer_size + front_a
            back_b = layer_size + front_b
            faces.append((front_a, back_a, back_b, front_b) if column == 0 else (front_b, back_b, back_a, front_a))
            material_indices.append(1)

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(stone)
    obj.data.materials.append(stone_dark)
    for polygon, material_index in zip(obj.data.polygons, material_indices):
        polygon.material_index = material_index
        polygon.use_smooth = False
    box_project_uv(obj, 5.5)
    bevel = obj.modifiers.new("Weathered cliff edges", "BEVEL")
    bevel.width = 0.10
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def coastal_arch_mesh(name, slate, slate_wet):
    """Make a recognizable wave-cut arch with an open passage through the rock."""
    segments = 14
    depth = 2.35
    rng = random.Random(4981)
    vertices = []
    for y in (-depth, depth):
        for inner in (False, True):
            for index in range(segments + 1):
                angle = math.pi * index / segments
                if inner:
                    rx, rz = 2.75, 4.05
                else:
                    rx, rz = 5.15, 7.25
                x = math.cos(angle) * rx
                z = math.sin(angle) * rz
                if 0 < index < segments:
                    x += rng.uniform(-0.12, 0.12)
                    z += rng.uniform(-0.13, 0.13)
                vertices.append((x, y + 0.10 * math.sin(index * 1.9), z))

    ring = segments + 1
    plane = ring * 2
    faces = []
    material_indices = []
    # Stone faces around the opening.
    for side in range(2):
        offset = side * plane
        for index in range(segments):
            outer_a = offset + index
            outer_b = outer_a + 1
            inner_a = offset + ring + index
            inner_b = inner_a + 1
            faces.append((outer_a, outer_b, inner_b, inner_a) if side == 0 else (inner_a, inner_b, outer_b, outer_a))
            material_indices.append(1 if index in (0, 1, segments - 2, segments - 1) else 0)
    # Outer weathered shell and inner wave-cut tunnel.
    for index in range(segments):
        faces.append((index, plane + index, plane + index + 1, index + 1))
        material_indices.append(0)
        inner = ring + index
        faces.append((inner + 1, plane + inner + 1, plane + inner, inner))
        material_indices.append(1)
    # Close both feet of the arch.
    for index in (0, segments):
        outer_front = index
        inner_front = ring + index
        outer_back = plane + outer_front
        inner_back = plane + inner_front
        faces.append((outer_front, inner_front, inner_back, outer_back))
        material_indices.append(1)

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(slate)
    obj.data.materials.append(slate_wet)
    for polygon, material_index in zip(obj.data.polygons, material_indices):
        polygon.material_index = material_index
        polygon.use_smooth = False
    box_project_uv(obj, 5.8)
    bevel = obj.modifiers.new("Wave softened edges", "BEVEL")
    bevel.width = 0.14
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def mountain_wall_mesh(name, stone, stone_dark, lichen):
    """Create one broad, watertight cliff wall with a buried talus foot.

    The wall is intentionally landform-sized.  Its ledges and buttresses are
    deformations of one continuous surface, so it cannot read as stacked
    blocks when seen from the road below.
    """
    rng = random.Random(17291)
    columns = 28
    heights = (-2.4, 0.4, 4.2, 8.8, 13.7, 18.6, 23.2, 27.0)
    front_vertices = []
    back_vertices = []
    for row, base_z in enumerate(heights):
        row_fraction = float(row) / float(len(heights) - 1)
        for column_index in range(columns + 1):
            fraction = float(column_index) / float(columns)
            x = -42.0 + 84.0 * fraction
            end_fade = math.sin(math.pi * fraction) ** 0.42
            skyline = 5.2 + 22.5 * end_fade
            skyline += 2.2 * math.sin(fraction * math.pi * 3.0 + 0.35) * end_fade
            skyline += 1.1 * math.sin(fraction * math.pi * 8.0 - 0.5) * end_fade
            broad_buttress = (
                2.15 * math.exp(-((x + 24.0) / 8.0) ** 2)
                + 2.8 * math.exp(-((x - 2.0) / 10.5) ** 2)
                + 1.9 * math.exp(-((x - 27.0) / 7.0) ** 2)
            )
            terrace = 1.15 if row in (2, 4, 6) else 0.0
            fracture = 0.52 * math.sin(column_index * 1.41 + row * 2.17)
            fracture += 0.26 * math.sin(column_index * 3.13 - row * 0.77)
            front_y = -3.2 - broad_buttress * (0.28 + row_fraction * 0.72) - terrace * end_fade + fracture
            if row == 0:
                # The broad buried toe hides small terrain sampling errors and
                # gives the cliff a natural talus transition rather than a gap.
                front_y -= 5.6 * end_fade
            normalized_height = (base_z - heights[0]) / (heights[-1] - heights[0])
            front_z = heights[0] + normalized_height * (skyline - heights[0])
            front_z += 0.46 * math.sin(column_index * 0.71 + row * 0.89) * end_fade
            front_z += rng.uniform(-0.18, 0.18) * end_fade
            if row == 0:
                front_z += 1.05 * math.sin(column_index * 1.27 + 0.4) * end_fade
            front_vertices.append((x, front_y, front_z))

            # Spread the rear shell far uphill.  The resulting broad apron is
            # buried into the mountain slope instead of exposing a model back.
            back_y = 5.8 + row_fraction * 35.0 + 0.36 * math.sin(column_index * 0.83 + row * 0.31)
            back_z = heights[0] + normalized_height * (skyline - heights[0])
            back_z -= 0.45 + row_fraction * 1.15
            back_z += 0.22 * math.sin(column_index * 0.57) * end_fade
            back_vertices.append((x, back_y, back_z))

    vertices = front_vertices + back_vertices
    stride = columns + 1
    layer_size = stride * len(heights)
    faces = []
    material_indices = []
    for back in (0, 1):
        offset = back * layer_size
        for row in range(len(heights) - 1):
            for column_index in range(columns):
                a = offset + row * stride + column_index
                b = a + 1
                c = a + stride + 1
                d = a + stride
                faces.append((a, b, c, d) if back == 0 else (d, c, b, a))
                shadow_patch = row in (0, 2, 5) and (column_index * 7 + row * 3) % 13 in (0, 1, 2, 3)
                material_indices.append(1 if shadow_patch else 0)
    for column_index in range(columns):
        top_front = (len(heights) - 1) * stride + column_index
        top_back = layer_size + top_front
        faces.append((top_front, top_front + 1, top_back + 1, top_back))
        material_indices.append(2 if column_index % 7 in (2, 3, 4) else 0)
        faces.append((column_index + 1, column_index, layer_size + column_index, layer_size + column_index + 1))
        material_indices.append(1)
    for column_index in (0, columns):
        for row in range(len(heights) - 1):
            front_a = row * stride + column_index
            front_b = front_a + stride
            back_a = layer_size + front_a
            back_b = layer_size + front_b
            faces.append((front_a, back_a, back_b, front_b) if column_index == 0 else (front_b, back_b, back_a, front_a))
            material_indices.append(1)

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in (stone, stone_dark, lichen):
        obj.data.materials.append(mat)
    for polygon, material_index in zip(obj.data.polygons, material_indices):
        polygon.material_index = material_index
        polygon.use_smooth = False
    box_project_uv(obj, 7.0)
    bevel = obj.modifiers.new("Weathered wall fractures", "BEVEL")
    bevel.width = 0.18
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj["collision_size"] = (84.0, 29.4, 18.0)
    obj["visual_role"] = "continuous mountain boundary and overlook"
    return obj


def glacial_cirque_wall_mesh(name, granite, granite_blue, snow):
    """Create a broad concave glacial headwall with a real open valley face."""
    rng = random.Random(28403)
    columns = 26
    rows = 7
    front_vertices = []
    back_vertices = []
    for row in range(rows):
        row_fraction = float(row) / float(rows - 1)
        for column_index in range(columns + 1):
            fraction = float(column_index) / float(columns)
            x = -38.0 + 76.0 * fraction
            arc = 1.0 - (x / 38.0) ** 2
            end_fade = math.sin(math.pi * fraction) ** 0.5
            skyline = 6.0 + 27.0 * end_fade + 2.4 * arc
            skyline += 1.7 * math.sin(fraction * math.pi * 4.0 + 0.6) * end_fade
            z = -2.0 + row_fraction * (skyline + 2.0)
            z += 0.42 * math.sin(column_index * 0.66 + row * 1.19) + rng.uniform(-0.14, 0.14) * end_fade
            if row == 0:
                z += 1.10 * math.sin(column_index * 1.16 - 0.3) * end_fade
            bowl = 7.8 * arc
            ledge = 1.0 if row in (2, 4) else 0.0
            y = -1.5 - bowl - ledge * end_fade + 0.42 * math.sin(column_index * 1.53 + row)
            if row == 0:
                y -= 4.4 * end_fade
            front_vertices.append((x, y, z))
            back_vertices.append((x, 6.8 + row_fraction * 38.0 + 0.25 * math.sin(column_index), z - 1.25))

    vertices = front_vertices + back_vertices
    stride = columns + 1
    layer_size = stride * rows
    faces = []
    material_indices = []
    for back in (0, 1):
        offset = back * layer_size
        for row in range(rows - 1):
            for column_index in range(columns):
                a = offset + row * stride + column_index
                b = a + 1
                c = a + stride + 1
                d = a + stride
                faces.append((a, b, c, d) if back == 0 else (d, c, b, a))
                blue_patch = row in (0, 3) and (column_index * 5 + row) % 11 in (0, 1, 2, 3)
                material_indices.append(1 if blue_patch else 0)
    for column_index in range(columns):
        top_front = (rows - 1) * stride + column_index
        top_back = layer_size + top_front
        faces.append((top_front, top_front + 1, top_back + 1, top_back))
        material_indices.append(2)
        faces.append((column_index + 1, column_index, layer_size + column_index, layer_size + column_index + 1))
        material_indices.append(1)
    for column_index in (0, columns):
        for row in range(rows - 1):
            front_a = row * stride + column_index
            front_b = front_a + stride
            back_a = layer_size + front_a
            back_b = layer_size + front_b
            faces.append((front_a, back_a, back_b, front_b) if column_index == 0 else (front_b, back_b, back_a, front_a))
            material_indices.append(1)

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in (granite, granite_blue, snow):
        obj.data.materials.append(mat)
    for polygon, material_index in zip(obj.data.polygons, material_indices):
        polygon.material_index = material_index
        polygon.use_smooth = False
    box_project_uv(obj, 7.0)
    bevel = obj.modifiers.new("Ice softened fractures", "BEVEL")
    bevel.width = 0.16
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj["collision_size"] = (76.0, 34.0, 22.0)
    obj["visual_role"] = "glacial cirque boundary and headwall"
    return obj


def join_named(name, objects, collision_size, visual_role):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    result["collision_size"] = collision_size
    result["visual_role"] = visual_role
    return result


def build_layered_cliff(stone, stone_dark, lichen):
    objects = [eroded_cliff_mesh("Continuous layered escarpment", stone, stone_dark)]
    rng = random.Random(8319)
    for index in range(12):
        x = -7.2 + index * 1.28 + rng.uniform(-0.35, 0.35)
        objects.append(rock(
            f"Cliff talus {index:02d}", (x, -2.05 + rng.uniform(-0.65, 0.55), rng.uniform(0.25, 0.62)),
            (rng.uniform(0.42, 0.90), rng.uniform(0.44, 0.92), rng.uniform(0.30, 0.64)),
            (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(-0.5, 0.5)),
            stone_dark if index % 2 else stone, 1400 + index,
        ))
    return join_named("LayeredCliffFace", objects, (17.0, 7.8, 5.2), "stratified regional cliff")


def build_basalt_escarpment(basalt, basalt_light, ember_lichen):
    objects = []
    heights = (5.8, 7.4, 8.8, 6.7, 10.1, 8.2, 6.1, 9.0, 7.2, 5.4, 7.8)
    for index, height in enumerate(heights):
        x = (index - 5) * 1.18
        y = 0.24 * math.sin(index * 1.7)
        objects.append(column(
            f"Basalt column {index:02d}", (x, y, height * 0.5), 0.76 + 0.06 * (index % 3), height,
            (math.radians((index % 3 - 1) * 2.5), math.radians((index % 2) * 2.0), index * 0.19),
            basalt_light if index in (2, 7) else basalt,
        ))
    for index in range(10):
        angle = index * 2.399963
        objects.append(rock(
            f"Basalt fall block {index:02d}",
            (math.cos(angle) * (3.0 + index * 0.34), -1.6 + math.sin(angle) * 1.1, 0.42 + 0.12 * (index % 3)),
            (0.72 + 0.14 * (index % 3), 0.60 + 0.10 * (index % 2), 0.48 + 0.13 * (index % 4)),
            (0.14 * index, -0.08 * index, angle), basalt, 2100 + index,
        ))
    for index, x in enumerate((-4.4, -0.4, 3.7)):
        objects.append(rock(
            f"Ember lichen {index:02d}", (x, -0.80, 3.6 + index * 1.2), (0.48, 0.08, 0.32),
            (math.radians(88.0), 0.0, index * 0.4), ember_lichen, 2300 + index,
        ))
    return join_named("BasaltColumnEscarpment", objects, (14.0, 10.4, 5.0), "volcanic columnar escarpment")


def build_glacial_crag(granite, granite_blue, snow):
    objects = []
    specs = [
        ((-3.5, 0.4, 3.0), (3.2, 2.4, 3.5), (0.08, -0.18, -0.28)),
        ((0.1, 0.0, 4.1), (3.7, 2.7, 4.8), (-0.05, 0.14, 0.10)),
        ((3.5, 0.2, 2.8), (2.8, 2.1, 3.3), (0.12, -0.12, 0.32)),
        ((-0.9, 1.5, 2.0), (2.2, 1.6, 2.5), (0.16, 0.05, -0.24)),
    ]
    for index, (location, scale, rotation) in enumerate(specs):
        objects.append(rock(f"Blue granite crag {index:02d}", location, scale, rotation, granite_blue if index % 2 else granite, 3000 + index, 2))
        cap_z = location[2] + scale[2] * 0.92
        objects.append(rock(
            f"Wind snow cap {index:02d}", (location[0] - 0.15, location[1] - 0.08, cap_z),
            (scale[0] * 0.78, scale[1] * 0.68, 0.20 + 0.05 * index),
            (rotation[0] * 0.35, rotation[1] * 0.35, rotation[2]), snow, 3200 + index,
        ))
    for index in range(8):
        angle = index * 1.47
        objects.append(rock(
            f"Glacial erratic {index:02d}", (math.cos(angle) * 5.3, math.sin(angle) * 2.2, 0.45),
            (0.65 + 0.13 * (index % 3), 0.58 + 0.11 * (index % 2), 0.52 + 0.10 * (index % 4)),
            (0.14 * index, -0.09 * index, angle), granite_blue, 3400 + index,
        ))
    return join_named("GlacialCrownCrag", objects, (12.5, 9.5, 6.5), "snow-capped glacial crag")


def build_coastal_stack(slate, slate_wet, salt_lichen):
    objects = [coastal_arch_mesh("Wave cut sea arch", slate, slate_wet)]
    for index in range(9):
        angle = index * 2.399963
        objects.append(rock(
            f"Tide stone {index:02d}", (math.cos(angle) * (3.0 + .25 * index), math.sin(angle) * 2.3, 0.30 + .09 * (index % 3)),
            (.52 + .14 * (index % 3), .48 + .10 * (index % 2), .36 + .09 * (index % 4)),
            (.12 * index, -.08 * index, angle), slate_wet, 4200 + index,
        ))
    return join_named("CoastalSeaStack", objects, (10.0, 12.0, 7.0), "weathered coastal sea stack")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    stone = material("Warm layered stone", (0.18, 0.16, 0.12, 1.0))
    stone_dark = material("Layered stone shadow", (0.075, 0.072, 0.062, 1.0))
    lichen = material("Cliff lichen", (0.19, 0.22, 0.09, 1.0))
    basalt = material("Charcoal basalt", (0.035, 0.042, 0.048, 1.0))
    basalt_light = material("Basalt fracture", (0.085, 0.092, 0.095, 1.0))
    ember_lichen = material("Ember lichen", (0.35, 0.13, 0.025, 1.0))
    granite = material("Cold granite", (0.16, 0.18, 0.20, 1.0))
    granite_blue = material("Blue glacial granite", (0.08, 0.13, 0.17, 1.0))
    snow = material("Wind packed snow", (0.72, 0.78, 0.80, 1.0), 0.90)
    slate = material("Salt weathered slate", (0.10, 0.13, 0.14, 1.0))
    slate_wet = material("Wet shore slate", (0.035, 0.055, 0.065, 1.0), 0.76)
    salt_lichen = material("Salt lichen", (0.31, 0.35, 0.24, 1.0))

    build_layered_cliff(stone, stone_dark, lichen)
    build_basalt_escarpment(basalt, basalt_light, ember_lichen)
    build_glacial_crag(granite, granite_blue, snow)
    build_coastal_stack(slate, slate_wet, salt_lichen)
    mountain_wall_mesh("StratifiedMountainWall", stone, stone_dark, lichen)
    glacial_cirque_wall_mesh("GlacialCirqueWall", granite, granite_blue, snow)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    print(f"REGIONAL_GEOLOGY_KIT_EXPORT|blend={BLEND_PATH}|glb={GLB_PATH}|meshes=6")


if __name__ == "__main__":
    main()
