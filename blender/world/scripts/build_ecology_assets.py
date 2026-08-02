import bpy
import math
import random
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = Path(__file__).resolve().parents[1] / "vegetation"
ASSET_DIR = PROJECT_ROOT / "godot" / "assets" / "vegetation"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, roughness=0.96):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def mesh_object(name, vertices, faces, material):
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def add_tapered_segment(vertices, faces, start, end, r0, r1, sides=7):
    sx, sy, sz = start
    ex, ey, ez = end
    dx, dy, dz = ex - sx, ey - sy, ez - sz
    length = max(0.0001, math.sqrt(dx * dx + dy * dy + dz * dz))
    axis = (dx / length, dy / length, dz / length)
    reference = (0.0, 0.0, 1.0) if abs(axis[2]) < 0.92 else (1.0, 0.0, 0.0)
    ux = axis[1] * reference[2] - axis[2] * reference[1]
    uy = axis[2] * reference[0] - axis[0] * reference[2]
    uz = axis[0] * reference[1] - axis[1] * reference[0]
    u_len = max(0.0001, math.sqrt(ux * ux + uy * uy + uz * uz))
    u = (ux / u_len, uy / u_len, uz / u_len)
    v = (
        axis[1] * u[2] - axis[2] * u[1],
        axis[2] * u[0] - axis[0] * u[2],
        axis[0] * u[1] - axis[1] * u[0],
    )
    base = len(vertices)
    for ring_center, radius in ((start, r0), (end, r1)):
        for side in range(sides):
            angle = math.tau * side / sides
            offset = tuple((u[i] * math.cos(angle) + v[i] * math.sin(angle)) * radius for i in range(3))
            vertices.append(tuple(ring_center[i] + offset[i] for i in range(3)))
    for side in range(sides):
        nxt = (side + 1) % sides
        faces.append((base + side, base + nxt, base + sides + nxt, base + sides + side))
    faces.append(tuple(base + side for side in reversed(range(sides))))
    faces.append(tuple(base + sides + side for side in range(sides)))


def add_leaf_strip(vertices, faces, root, direction, height, width, lean=0.0, segments=4):
    dx, dy = direction
    side = (-dy, dx)
    left_indices = []
    right_indices = []
    for step in range(segments + 1):
        t = step / segments
        arc = math.sin(t * math.pi * 0.72)
        center = (
            root[0] + dx * (lean * t + 0.12 * arc),
            root[1] + dy * (lean * t + 0.12 * arc),
            root[2] + height * t,
        )
        local_width = width * (1.0 - t) ** 0.65 + 0.004
        left_indices.append(len(vertices))
        vertices.append((center[0] + side[0] * local_width, center[1] + side[1] * local_width, center[2]))
        right_indices.append(len(vertices))
        vertices.append((center[0] - side[0] * local_width, center[1] - side[1] * local_width, center[2]))
    for step in range(segments):
        faces.append((left_indices[step], right_indices[step], right_indices[step + 1], left_indices[step + 1]))


def export_asset(filename, source_name):
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_DIR / source_name))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(ASSET_DIR / filename),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"ECOLOGY_ASSET_BUILT|{filename}")


def build_bracken():
    clear_scene()
    random.seed(14731)
    leaf_material = make_material("Bracken Leaves", (0.075, 0.19, 0.045, 1.0))
    stem_material = make_material("Bracken Stems", (0.10, 0.13, 0.035, 1.0))
    leaf_vertices, leaf_faces = [], []
    stem_vertices, stem_faces = [], []
    # Five readable fern crowns are more convincing than hundreds of tiny
    # overlapping leaflets, which collapsed into a bright geometric tangle.
    for plant in range(5):
        angle = plant * 2.39996323
        radius = 0.08 + (plant % 3) * 0.22
        root = (math.cos(angle) * radius, math.sin(angle) * radius, 0.0)
        plant_height = 0.44 + (plant % 4) * 0.075
        for frond in range(7):
            yaw = angle + frond * math.tau / 7.0 + random.uniform(-0.16, 0.16)
            direction = (math.cos(yaw), math.sin(yaw))
            reach = 0.30 + (frond % 3) * 0.075
            tip = (
                root[0] + direction[0] * reach,
                root[1] + direction[1] * reach,
                plant_height + (frond % 2) * 0.045,
            )
            add_tapered_segment(stem_vertices, stem_faces, root, tip, 0.012, 0.003, 5)
            add_leaf_strip(
                leaf_vertices,
                leaf_faces,
                root,
                direction,
                plant_height,
                0.075 + (frond % 3) * 0.009,
                reach,
                5,
            )
    mesh_object("BrackenLeaves", leaf_vertices, leaf_faces, leaf_material)
    mesh_object("BrackenStems", stem_vertices, stem_faces, stem_material)
    export_asset("bracken_patch_v1.glb", "bracken_patch_v1.blend")


def build_cattails():
    clear_scene()
    random.seed(28319)
    leaf_material = make_material("Cattail Leaves", (0.10, 0.30, 0.095, 1.0))
    stem_material = make_material("Cattail Stems", (0.18, 0.32, 0.075, 1.0))
    head_material = make_material("Cattail Heads", (0.235, 0.105, 0.035, 1.0))
    leaf_vertices, leaf_faces = [], []
    stem_vertices, stem_faces = [], []
    head_vertices, head_faces = [], []
    for plant in range(9):
        angle = plant * 2.39996323
        radius = 0.10 + (plant % 4) * 0.18
        root = (math.cos(angle) * radius, math.sin(angle) * radius, 0.0)
        height = 1.0 + (plant % 5) * 0.14
        yaw = angle + random.uniform(-0.25, 0.25)
        direction = (math.cos(yaw), math.sin(yaw))
        stem_top = (root[0] + direction[0] * 0.035, root[1] + direction[1] * 0.035, height)
        add_tapered_segment(stem_vertices, stem_faces, root, stem_top, 0.018, 0.011, 6)
        head_start = (stem_top[0], stem_top[1], height - 0.15)
        head_end = (stem_top[0], stem_top[1], height + 0.18)
        add_tapered_segment(head_vertices, head_faces, head_start, head_end, 0.065, 0.052, 8)
        for leaf in range(4):
            leaf_yaw = yaw + leaf * math.tau / 4.0 + random.uniform(-0.15, 0.15)
            leaf_direction = (math.cos(leaf_yaw), math.sin(leaf_yaw))
            add_leaf_strip(
                leaf_vertices,
                leaf_faces,
                root,
                leaf_direction,
                height * (0.56 + leaf * 0.07),
                0.035 + leaf * 0.004,
                0.10 + leaf * 0.025,
                5,
            )
    mesh_object("CattailLeaves", leaf_vertices, leaf_faces, leaf_material)
    mesh_object("CattailStems", stem_vertices, stem_faces, stem_material)
    mesh_object("CattailHeads", head_vertices, head_faces, head_material)
    export_asset("cattail_cluster_v1.glb", "cattail_cluster_v1.blend")


def build_dry_stone_wall():
    clear_scene()
    random.seed(39427)
    stone_material = make_material("Weathered Field Stone", (0.31, 0.30, 0.265, 1.0), 1.0)
    stones = []
    course_specs = [
        (0.24, 5, 0.48, 0.44),
        (0.66, 5, 0.44, 0.39),
        (1.02, 6, 0.35, 0.30),
    ]
    for course_index, (z_center, count, height, depth) in enumerate(course_specs):
        stone_length = 4.15 / count
        offset = stone_length * 0.32 if course_index % 2 else 0.0
        for index in range(count):
            x = -2.075 + (index + 0.5) * stone_length + offset
            if x > 2.12:
                x -= 4.15
            length = stone_length * random.uniform(0.82, 1.13)
            bpy.ops.mesh.primitive_cube_add(location=(x, random.uniform(-0.035, 0.035), z_center))
            stone = bpy.context.object
            stone.name = f"FieldStone_{course_index}_{index}"
            stone.scale = (length * 0.50, depth * random.uniform(0.88, 1.12), height * random.uniform(0.44, 0.54))
            stone.rotation_euler = (
                random.uniform(-0.035, 0.035),
                random.uniform(-0.055, 0.055),
                random.uniform(-0.045, 0.045),
            )
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            bevel = stone.modifiers.new("Worn edges", "BEVEL")
            bevel.width = 0.075
            bevel.segments = 2
            bpy.context.view_layer.objects.active = stone
            bpy.ops.object.modifier_apply(modifier=bevel.name)
            stone.data.materials.append(stone_material)
            stones.append(stone)
    bpy.ops.object.select_all(action="DESELECT")
    for stone in stones:
        stone.select_set(True)
    bpy.context.view_layer.objects.active = stones[0]
    bpy.ops.object.join()
    stones[0].name = "WallStones"
    export_asset("dry_stone_wall_segment_v1.glb", "dry_stone_wall_segment_v1.blend")


def build_roadside_cairn():
    clear_scene()
    random.seed(61403)
    material = make_material("Roadside Cairn Stone", (0.42, 0.405, 0.36, 1.0), 1.0)
    stones = []
    # An irregular field-stone pile reads much more naturally than the old
    # seven perfect slabs. The broad three-stone base keeps the silhouette
    # stable while the upper stones lean and narrow independently.
    stone_specs = [
        (-0.34, 0.02, 0.23, 0.72, 0.58, 0.46),
        (0.34, -0.03, 0.24, 0.70, 0.54, 0.48),
        (0.00, 0.12, 0.30, 0.76, 0.61, 0.52),
        (-0.22, -0.01, 0.67, 0.62, 0.49, 0.43),
        (0.25, 0.04, 0.69, 0.60, 0.47, 0.42),
        (-0.03, -0.05, 1.02, 0.58, 0.43, 0.42),
        (0.05, 0.02, 1.34, 0.43, 0.34, 0.40),
    ]
    for index, (x, y, z, width, depth, height) in enumerate(stone_specs):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5, location=(x, y, z))
        stone = bpy.context.object
        stone.name = f"CairnStone_{index}"
        stone.scale = (width, depth, height)
        stone.rotation_euler = (
            random.uniform(-0.12, 0.12),
            random.uniform(-0.12, 0.12),
            random.uniform(-0.24, 0.24),
        )
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        stone.data.materials.append(material)
        stones.append(stone)
    bpy.ops.object.select_all(action="DESELECT")
    for stone in stones:
        stone.select_set(True)
    bpy.context.view_layer.objects.active = stones[0]
    bpy.ops.object.join()
    stones[0].name = "CairnStones"
    export_asset("roadside_cairn_v1.glb", "roadside_cairn_v1.blend")


def build_forest_deadwood():
    clear_scene()
    random.seed(82117)
    bark_material = make_material("Mossed Deadwood Bark", (0.16, 0.085, 0.032, 1.0), 1.0)
    end_material = make_material("Weathered Broken Wood", (0.40, 0.255, 0.105, 1.0), 1.0)
    moss_material = make_material("Deadwood Moss", (0.105, 0.205, 0.045, 1.0), 1.0)
    fungus_material = make_material("Bracket Fungus", (0.53, 0.34, 0.13, 1.0), 1.0)

    bark_vertices, bark_faces = [], []
    branch_vertices, branch_faces = [], []
    # A crooked, grounded trunk with a visibly broken profile. This is small
    # forest-floor deadwood, not a second full felled harvestable tree.
    spine = [
        (-2.25, 0.00, 0.32),
        (-1.15, 0.10, 0.39),
        (0.05, -0.08, 0.35),
        (1.18, 0.07, 0.29),
        (2.18, -0.02, 0.24),
    ]
    radii = [0.34, 0.42, 0.39, 0.31, 0.19]
    for index in range(len(spine) - 1):
        add_tapered_segment(
            bark_vertices,
            bark_faces,
            spine[index],
            spine[index + 1],
            radii[index],
            radii[index + 1],
            9,
        )
    for index, (start_index, direction, length) in enumerate([
        (1, (-0.10, 0.72, 0.54), 0.88),
        (2, (0.15, -0.68, 0.48), 0.72),
        (3, (0.30, 0.46, 0.42), 0.54),
    ]):
        start = spine[start_index]
        end = tuple(start[axis] + direction[axis] * length for axis in range(3))
        add_tapered_segment(branch_vertices, branch_faces, start, end, 0.10 - index * 0.015, 0.025, 7)
    mesh_object("DeadwoodBark", bark_vertices, bark_faces, bark_material)
    mesh_object("DeadwoodBranches", branch_vertices, branch_faces, bark_material)

    # Pale, irregular end grain makes the broken ends readable at walking
    # distance without turning them into bright circular plugs.
    ends = []
    for index, (location, scale, rotation) in enumerate([
        ((-2.27, 0.0, 0.32), (0.035, 0.31, 0.29), (0.0, math.pi * 0.5, 0.0)),
        ((2.20, -0.02, 0.24), (0.025, 0.18, 0.16), (0.0, math.pi * 0.5, 0.0)),
    ]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=9, radius=1.0, depth=1.0, location=location, rotation=rotation)
        end = bpy.context.object
        end.name = f"DeadwoodEnd_{index}"
        end.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        end.data.materials.append(end_material)
        ends.append(end)
    join_objects(ends, "DeadwoodEnds")

    # Low moss pads and a handful of shelf fungi break the cylinder silhouette.
    mosses = []
    for index in range(7):
        x = -1.65 + index * 0.52
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.5, location=(x, 0.03 + math.sin(index) * 0.10, 0.61 - abs(x) * 0.035))
        moss = bpy.context.object
        moss.name = f"DeadwoodMoss_{index}"
        moss.scale = (0.42 + (index % 2) * 0.12, 0.26, 0.075)
        moss.rotation_euler[2] = index * 0.71
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        moss.data.materials.append(moss_material)
        mosses.append(moss)
    join_objects(mosses, "DeadwoodMoss")
    fungi = []
    for index in range(5):
        x = -0.85 + index * 0.43
        side = -1.0 if index % 2 else 1.0
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.5, location=(x, side * 0.35, 0.42 + (index % 3) * 0.05))
        fungus = bpy.context.object
        fungus.name = f"DeadwoodFungus_{index}"
        fungus.scale = (0.20, 0.11, 0.055)
        fungus.rotation_euler[2] = side * 0.30
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        fungus.data.materials.append(fungus_material)
        fungi.append(fungus)
    join_objects(fungi, "DeadwoodFungi")

    export_asset("forest_deadwood_cluster_v1.glb", "forest_deadwood_cluster_v1.blend")


def build_woodland_flowers():
    clear_scene()
    random.seed(93841)
    leaf_material = make_material("Woodland Flower Leaves", (0.10, 0.255, 0.065, 1.0), 1.0)
    stem_material = make_material("Woodland Flower Stems", (0.12, 0.31, 0.075, 1.0), 1.0)
    petal_material = make_material("Woodland Flower Petals", (0.66, 0.46, 0.12, 1.0), 0.92)
    center_material = make_material("Woodland Flower Centers", (0.25, 0.13, 0.025, 1.0), 1.0)
    leaf_vertices, leaf_faces = [], []
    stem_vertices, stem_faces = [], []
    petal_vertices, petal_faces = [], []
    center_vertices, center_faces = [], []
    for plant in range(8):
        angle = plant * 2.39996323 + random.uniform(-0.24, 0.24)
        radius = 0.12 + (plant % 4) * 0.21
        root = (math.cos(angle) * radius, math.sin(angle) * radius, 0.0)
        height = 0.30 + (plant % 5) * 0.055
        sway = (math.cos(angle) * 0.04, math.sin(angle) * 0.04, height)
        top = (root[0] + sway[0], root[1] + sway[1], height)
        add_tapered_segment(stem_vertices, stem_faces, root, top, 0.012, 0.006, 5)
        for leaf_index in range(3):
            leaf_angle = angle + leaf_index * math.tau / 3.0
            add_leaf_strip(
                leaf_vertices,
                leaf_faces,
                root,
                (math.cos(leaf_angle), math.sin(leaf_angle)),
                0.12 + leaf_index * 0.035,
                0.045,
                0.16 + leaf_index * 0.025,
                3,
            )
        # Six broad petals lie in a gently cupped ring; unlike the old sticks,
        # every plant reads as a flower even from an oblique camera angle.
        center_base = len(center_vertices)
        center_vertices.extend([
            (top[0] - 0.035, top[1] - 0.035, top[2] + 0.012),
            (top[0] + 0.035, top[1] - 0.035, top[2] + 0.012),
            (top[0] + 0.035, top[1] + 0.035, top[2] + 0.012),
            (top[0] - 0.035, top[1] + 0.035, top[2] + 0.012),
        ])
        center_faces.append((center_base, center_base + 1, center_base + 2, center_base + 3))
        for petal in range(6):
            petal_angle = petal * math.tau / 6.0 + angle * 0.23
            direction = (math.cos(petal_angle), math.sin(petal_angle))
            side = (-direction[1], direction[0])
            inner = 0.025
            outer = 0.115 + (petal % 2) * 0.018
            half_width = 0.046
            base = len(petal_vertices)
            petal_vertices.extend([
                (top[0] + direction[0] * inner - side[0] * half_width, top[1] + direction[1] * inner - side[1] * half_width, top[2]),
                (top[0] + direction[0] * outer - side[0] * half_width * 0.35, top[1] + direction[1] * outer - side[1] * half_width * 0.35, top[2] + 0.025),
                (top[0] + direction[0] * outer + side[0] * half_width * 0.35, top[1] + direction[1] * outer + side[1] * half_width * 0.35, top[2] + 0.025),
                (top[0] + direction[0] * inner + side[0] * half_width, top[1] + direction[1] * inner + side[1] * half_width, top[2]),
            ])
            petal_faces.append((base, base + 1, base + 2, base + 3))
    mesh_object("FlowerLeaves", leaf_vertices, leaf_faces, leaf_material)
    mesh_object("FlowerStems", stem_vertices, stem_faces, stem_material)
    mesh_object("FlowerPetals", petal_vertices, petal_faces, petal_material)
    mesh_object("FlowerCenters", center_vertices, center_faces, center_material)
    export_asset("woodland_flower_patch_v1.glb", "woodland_flower_patch_v1.blend")


if __name__ == "__main__":
    build_bracken()
    build_cattails()
    build_dry_stone_wall()
    build_roadside_cairn()
    build_forest_deadwood()
    build_woodland_flowers()
