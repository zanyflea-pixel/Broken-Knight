"""Build authored intact and depleted mining outcrops for Broken Knight.

Each ore family has a distinct silhouette rather than a recolored sphere. The
depleted variants are low fractured remnants intended to remain briefly after
mining, then disappear when the intact resource respawns.
"""

import math
import random
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = PROJECT_ROOT / "blender" / "world" / "geology" / "mineable_geology_kit_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "world" / "mineable_geology_kit_v1.glb"


def make_material(name, color, roughness=0.94, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return material


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def box_project_uv(obj, meters_per_tile=1.4):
    layer = obj.data.uv_layers.new(name="MineableGeologyUV")
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


def outcrop_mass(name, location, scale, rotation, material, seed, sides=9):
    """Create a grounded angular mass with a broken shoulder and crown."""
    rng = random.Random(seed)
    vertices = []
    ring_specs = ((1.0, 0.02), (1.05, 0.34), (0.67, 0.82))
    angle_offsets = (0.0, 0.10, -0.08)
    for ring_index, (radius, height) in enumerate(ring_specs):
        for index in range(sides):
            angle = math.tau * index / sides + angle_offsets[ring_index]
            radial_break = 1.0 + 0.14 * math.sin(index * 2.17 + seed * 0.13 + ring_index)
            radial_break += rng.uniform(-0.085, 0.085)
            y_break = 0.90 + 0.15 * math.sin(index * 1.73 - seed * 0.09)
            z = height + (rng.uniform(-0.035, 0.035) if ring_index > 0 else 0.0)
            vertices.append((math.cos(angle) * radius * radial_break, math.sin(angle) * radius * y_break, z))
    crown_index = len(vertices)
    vertices.append((0.10 * math.sin(seed), -0.08 * math.cos(seed), 1.02))
    faces = []
    faces.append(tuple(reversed(range(sides))))
    for ring_index in range(2):
        lower = ring_index * sides
        upper = (ring_index + 1) * sides
        for index in range(sides):
            nxt = (index + 1) % sides
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    top = sides * 2
    for index in range(sides):
        faces.append((top + index, top + (index + 1) % sides, crown_index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.scale = scale
    obj.rotation_euler = rotation
    apply_transform(obj)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    box_project_uv(obj)
    bevel = obj.modifiers.new("Weathered mass edges", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def fractured_rock(name, location, scale, rotation, material, seed, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    apply_transform(obj)
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        direction = vertex.co.normalized()
        band = math.sin(vertex.co.z * 5.7 + seed * 0.31) * 0.055
        cleave = math.sin(vertex.co.x * 4.1 - vertex.co.y * 3.3 + seed) * 0.04
        vertex.co += direction * (band + cleave + rng.uniform(-0.055, 0.055))
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    box_project_uv(obj)
    bevel = obj.modifiers.new("Worn fractured edges", "BEVEL")
    bevel.width = 0.025
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def mineral_rib(name, location, scale, rotation, material, vertices=6):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=1.0,
        depth=2.0,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    obj.data.materials.append(material)
    bevel = obj.modifiers.new("Chipped mineral edge", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    box_project_uv(obj, 0.75)
    return obj


def mineral_seam(name, location, length, width, yaw, material, seed):
    """Create a low jagged mineral seam embedded across an exposed face."""
    rng = random.Random(seed)
    segments = 5
    vertices = []
    for upper in (False, True):
        z = 0.018 if upper else -0.018
        for index in range(segments + 1):
            progress = float(index) / segments
            center_y = (progress - 0.5) * length
            center_x = math.sin(progress * math.pi * 2.7 + seed) * width * 0.34
            center_x += rng.uniform(-width * 0.14, width * 0.14)
            half_width = width * (0.34 + 0.20 * math.sin(progress * math.pi))
            vertices.append((center_x - half_width, center_y, z))
            vertices.append((center_x + half_width, center_y, z))
    stride = (segments + 1) * 2
    faces = []
    for index in range(segments):
        a = index * 2
        b = a + 2
        faces.append((a, a + 1, b + 1, b))
        top = stride + a
        faces.append((top + 1, top, top + 2, top + 3))
    for index in range(segments + 1):
        lower = index * 2
        upper = stride + lower
        faces.append((lower, upper, upper + 1, lower + 1))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (0.05 * math.sin(seed), 0.07 * math.cos(seed), yaw)
    apply_transform(obj)
    obj.data.materials.append(material)
    box_project_uv(obj, 0.5)
    bevel = obj.modifiers.new("Weathered seam edge", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def join_named(name, objects, state, ore_id):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    result["ore_id"] = ore_id
    result["resource_state"] = state
    result["visual_role"] = "mineable outcrop" if state == "intact" else "depleted fractured remnant"
    return result


def build_iron(stone, ore, depleted_stone):
    intact = [
        outcrop_mass("Iron layered base", (-0.34, 0.0, 0.0), (1.15, 0.80, 0.67), (0.04, 0.16, -0.06), stone, 101, 10),
        outcrop_mass("Iron cleft shoulder", (0.78, 0.08, 0.0), (0.66, 0.55, 0.46), (-0.08, -0.14, 0.12), stone, 102, 8),
        outcrop_mass("Iron broken toe", (-0.82, 0.32, 0.0), (0.46, 0.42, 0.31), (0.10, 0.08, -0.20), depleted_stone, 103, 7),
    ]
    for index, x in enumerate((-0.66, -0.08, 0.48)):
        intact.append(mineral_seam(
            f"Iron hematite band {index}", (x, -0.16 + index * 0.08, 0.60 + index * 0.045),
            0.72, 0.15, math.radians(-22 + index * 19), ore, 130 + index,
        ))
    join_named("IronOutcropIntact", intact, "intact", "iron")
    build_depleted("IronOutcropDepleted", "iron", depleted_stone, ore, 110)


def build_copper(stone, ore, patina, depleted_stone):
    intact = [
        outcrop_mass("Copper fractured host", (-0.28, 0.0, 0.0), (0.94, 0.88, 0.76), (0.06, -0.18, 0.04), stone, 201, 9),
        outcrop_mass("Copper split lobe", (0.72, 0.14, 0.0), (0.60, 0.52, 0.48), (-0.10, 0.20, 0.20), stone, 202, 8),
        outcrop_mass("Copper weathered foot", (-0.72, 0.54, 0.0), (0.47, 0.38, 0.29), (0.05, -0.08, -0.14), depleted_stone, 203, 7),
    ]
    for index, angle in enumerate((0.15, 1.70, 3.35, 4.85)):
        material = patina if index in (1, 3) else ore
        intact.append(mineral_seam(
            f"Copper vein {index}", (math.cos(angle) * 0.48, math.sin(angle) * 0.38, 0.60 + 0.045 * (index % 2)),
            0.58, 0.12, angle + 0.35, material, 230 + index,
        ))
    join_named("CopperOutcropIntact", intact, "intact", "copper")
    build_depleted("CopperOutcropDepleted", "copper", depleted_stone, patina, 210)


def build_silver(stone, quartz, ore, depleted_stone):
    intact = [
        outcrop_mass("Silver cleft base", (0.0, 0.0, 0.0), (1.12, 0.72, 0.44), (-0.04, 0.22, 0.02), stone, 301, 10),
    ]
    for index, (x, y, height, lean) in enumerate(((-0.62, 0.02, 1.28, -0.20), (-0.08, -0.06, 1.58, 0.08), (0.46, 0.08, 1.12, 0.23))):
        intact.append(mineral_rib(
            f"Silver quartz rib {index}", (x, y, height * 0.48),
            (0.30, 0.25, height * 0.50), (lean, 0.12 * index, -0.10 * index), quartz, vertices=7,
        ))
        intact.append(mineral_rib(
            f"Silver seam {index}", (x - 0.12, y - 0.20, height * 0.55),
            (0.055, 0.045, height * 0.34), (lean + 0.08, 0.12 * index, -0.10 * index), ore,
        ))
    join_named("SilverOutcropIntact", intact, "intact", "silver")
    build_depleted("SilverOutcropDepleted", "silver", depleted_stone, quartz, 310)


def build_gold(stone, quartz, ore, depleted_stone):
    intact = [
        outcrop_mass("Gold quartz host left", (-0.54, 0.0, 0.0), (0.86, 0.80, 0.58), (0.08, -0.18, -0.10), stone, 401, 9),
        outcrop_mass("Gold quartz host right", (0.58, 0.10, 0.0), (0.72, 0.66, 0.51), (-0.06, 0.22, 0.15), quartz, 402, 8),
    ]
    for index, (x, y, angle) in enumerate(((-0.72, -0.64, -0.22), (-0.16, -0.73, 0.10), (0.48, -0.55, 0.31), (0.78, 0.18, -0.40))):
        intact.append(mineral_seam(
            f"Gold seam {index}", (x, y * 0.42, 0.58 + 0.045 * (index % 2)),
            0.62, 0.13, angle + 0.28, ore, 430 + index,
        ))
    join_named("GoldOutcropIntact", intact, "intact", "gold")
    build_depleted("GoldOutcropDepleted", "gold", depleted_stone, ore, 410)


def build_depleted(name, ore_id, stone, trace, seed):
    rng = random.Random(seed)
    fragments = []
    for index in range(7):
        angle = index * 2.399963 + rng.uniform(-0.18, 0.18)
        distance = 0.35 + 0.16 * (index % 3)
        scale = 0.24 + 0.055 * (index % 4)
        fragments.append(fractured_rock(
            f"{ore_id.title()} depleted fragment {index}",
            (math.cos(angle) * distance, math.sin(angle) * distance, scale * 0.48),
            (scale * 1.35, scale, scale * 0.72),
            (rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), angle),
            stone, seed + index, subdivisions=1,
        ))
    fragments.append(mineral_rib(
        f"{ore_id.title()} remnant trace", (-0.12, -0.16, 0.17),
        (0.12, 0.08, 0.18), (math.radians(78), 0.2, -0.3), trace,
    ))
    join_named(name, fragments, "depleted", ore_id)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    iron_stone = make_material("Iron banded host", (0.105, 0.115, 0.11, 1.0))
    iron_ore = make_material("Hematite seams", (0.255, 0.115, 0.055, 1.0), 0.78, 0.24)
    copper_stone = make_material("Copper brown host", (0.15, 0.095, 0.055, 1.0))
    copper_ore = make_material("Native copper seams", (0.38, 0.12, 0.035, 1.0), 0.70, 0.42)
    copper_patina = make_material("Copper patina", (0.025, 0.20, 0.145, 1.0), 0.86, 0.10)
    silver_stone = make_material("Silver slate host", (0.095, 0.11, 0.13, 1.0))
    pale_quartz = make_material("Pale quartz", (0.34, 0.38, 0.39, 1.0), 0.82, 0.04)
    silver_ore = make_material("Silver seams", (0.40, 0.44, 0.46, 1.0), 0.52, 0.62)
    gold_stone = make_material("Gold ochre host", (0.17, 0.12, 0.055, 1.0))
    warm_quartz = make_material("Warm quartz", (0.36, 0.29, 0.16, 1.0), 0.84, 0.03)
    gold_ore = make_material("Native gold seams", (0.48, 0.28, 0.025, 1.0), 0.58, 0.62)
    depleted = make_material("Fresh broken stone", (0.11, 0.115, 0.105, 1.0))

    build_iron(iron_stone, iron_ore, depleted)
    build_copper(copper_stone, copper_ore, copper_patina, depleted)
    build_silver(silver_stone, pale_quartz, silver_ore, depleted)
    build_gold(gold_stone, warm_quartz, gold_ore, depleted)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    print(f"MINEABLE_GEOLOGY_KIT_EXPORT|blend={BLEND_PATH}|glb={GLB_PATH}|meshes=8")


if __name__ == "__main__":
    main()
