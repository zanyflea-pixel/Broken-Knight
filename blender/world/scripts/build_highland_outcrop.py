import bpy
import math
import random
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = Path(__file__).resolve().parents[1] / "vegetation" / "highland_outcrop_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "vegetation" / "highland_outcrop_v1.glb"


def material(name, color, roughness=0.98):
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return value


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def add_rock(name, location, scale, rotation, rock_material, seed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    apply_transform(obj)
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        direction = vertex.co.normalized()
        stratum = math.sin(vertex.co.z * 4.7 + seed * 0.31) * 0.055
        fracture = math.sin(vertex.co.x * 3.1 + vertex.co.y * 4.3 + seed) * 0.045
        vertex.co += direction * (stratum + fracture + rng.uniform(-0.035, 0.035))
    obj.data.materials.append(rock_material)
    bevel = obj.modifiers.new("Weathered edges", "BEVEL")
    bevel.width = 0.075
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def add_moss_patch(name, location, scale, moss_material, seed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = (0.08 * math.sin(seed), 0.11 * math.cos(seed), seed * 0.73)
    apply_transform(obj)
    obj.data.materials.append(moss_material)
    return obj


def add_lichen_disc(name, location, radius, lichen_material, yaw):
    bpy.ops.mesh.primitive_circle_add(vertices=9, radius=radius, fill_type="TRIFAN", location=location)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (0.0, 0.0, yaw)
    obj.data.materials.append(lichen_material)
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(42071)
    # Blender stores these node colors in linear space; deliberately low
    # values import into Godot as weathered stone instead of chalk-white rock.
    stone_dark = material("Outcrop Stone Dark", (0.035, 0.038, 0.033, 1.0))
    stone_mid = material("Outcrop Stone Mid", (0.065, 0.062, 0.052, 1.0))
    stone_warm = material("Outcrop Stone Warm", (0.090, 0.070, 0.042, 1.0))
    moss = material("Outcrop Moss", (0.025, 0.065, 0.012, 1.0))
    lichen = material("Outcrop Lichen", (0.16, 0.18, 0.065, 1.0))

    objects = []
    rock_specs = [
        ((-2.45, 0.10, 1.05), (2.50, 1.60, 1.12), (0.05, -0.12, -0.18), stone_dark),
        ((0.05, -0.20, 1.48), (2.95, 1.95, 1.58), (-0.08, 0.12, 0.08), stone_mid),
        ((2.60, 0.25, 0.92), (2.12, 1.42, 1.02), (0.12, -0.08, 0.24), stone_warm),
        ((-0.85, 1.15, 0.72), (1.55, 1.10, 0.78), (0.18, 0.04, -0.32), stone_warm),
        ((1.15, 1.20, 0.62), (1.35, 1.02, 0.68), (0.03, 0.16, 0.41), stone_dark),
        ((-3.55, 1.05, 0.48), (1.02, 0.88, 0.53), (-0.15, 0.09, 0.15), stone_mid),
        ((3.70, -0.38, 0.40), (0.92, 0.78, 0.46), (0.10, -0.17, -0.28), stone_mid),
    ]
    for index, (location, scale, rotation, rock_material) in enumerate(rock_specs):
        objects.append(add_rock(f"WeatheredRock_{index:02d}", location, scale, rotation, rock_material, 870 + index * 31))

    moss_specs = [
        ((-2.15, -0.05, 2.10), (1.18, 0.72, 0.085)),
        ((-0.20, -0.15, 2.96), (1.28, 0.82, 0.10)),
        ((2.48, 0.30, 1.82), (0.86, 0.58, 0.075)),
        ((-0.65, 1.18, 1.43), (0.64, 0.42, 0.06)),
    ]
    for index, (location, scale) in enumerate(moss_specs):
        objects.append(add_moss_patch(f"MossPatch_{index:02d}", location, scale, moss, 310 + index))

    lichen_specs = [
        ((0.20, -1.83, 1.64), 0.25, 0.2),
        ((-1.05, -1.48, 1.35), 0.18, 0.7),
        ((2.35, -1.12, 1.04), 0.16, -0.4),
        ((-2.78, -1.18, 1.08), 0.20, 0.1),
    ]
    for index, (location, radius, yaw) in enumerate(lichen_specs):
        disc = add_lichen_disc(f"Lichen_{index:02d}", location, radius, lichen, yaw)
        disc.rotation_euler.x = math.radians(78.0)
        objects.append(disc)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    outcrop = bpy.context.object
    outcrop.name = "HighlandOutcrop"
    outcrop["collision_radius"] = 4.7
    outcrop["visual_role"] = "highland landmark"

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    print(f"HIGHLAND_OUTCROP_BUILT|blend={BLEND_PATH}|glb={GLB_PATH}|objects={len(objects)}")


if __name__ == "__main__":
    main()
