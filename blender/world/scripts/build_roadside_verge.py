import bpy
import math
import random
from pathlib import Path
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = Path(__file__).resolve().parents[1] / "vegetation" / "roadside_verge_cluster_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "vegetation" / "roadside_verge_cluster_v1.glb"


def material(name, color, roughness=1.0):
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


def tapered_leaf(name, root, yaw, length, width, lean, mat):
    direction = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    side = Vector((-direction.y, direction.x, 0.0))
    base = Vector(root)
    middle = base + direction * (length * 0.42) + Vector((0, 0, length * 0.36))
    tip = base + direction * (length * lean) + Vector((0, 0, length))
    vertices = [
        base - side * width * 0.32,
        base + side * width * 0.32,
        middle + side * width * 0.50,
        tip,
        middle - side * width * 0.50,
    ]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3, 4)])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # A real paper-thin volume gives both sides reliable normals in Godot;
    # single foliage planes turned almost black when viewed from behind.
    solidify = obj.modifiers.new("Leaf thickness", "SOLIDIFY")
    solidify.thickness = 0.006
    solidify.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    obj.select_set(False)
    return obj


def cylinder_between(name, start, end, radius, mat, vertices=7):
    start_v, end_v = Vector(start), Vector(end)
    delta = end_v - start_v
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=(start_v + end_v) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    obj.data.materials.append(mat)
    return obj


def weathered_stone(name, location, scale, yaw, mat, seed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = (0.08 * math.sin(seed), 0.11 * math.cos(seed * 0.7), yaw)
    apply_transform(obj)
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        vertex.co += vertex.co.normalized() * rng.uniform(-0.06, 0.045)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def flower(name, location, height, color_material, stem_material, seed):
    objects = []
    rng = random.Random(seed)
    lean = Vector((rng.uniform(-0.10, 0.10), rng.uniform(-0.10, 0.10), height))
    base = Vector(location)
    top = base + lean
    objects.append(cylinder_between(name + "Stem", base, top, 0.018, stem_material, 6))
    for petal in range(5):
        angle = petal * math.tau / 5.0 + rng.uniform(-0.08, 0.08)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.10, location=top + Vector((math.cos(angle) * 0.105, math.sin(angle) * 0.105, 0.0)))
        obj = bpy.context.object
        obj.name = name + f"Petal{petal}"
        obj.scale = (1.15, 0.48, 0.25)
        obj.rotation_euler.z = angle
        apply_transform(obj)
        obj.data.materials.append(color_material)
        objects.append(obj)
    return objects


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rng = random.Random(71239)
    grass = material("Verge Broad Grass", (0.018, 0.070, 0.010, 1.0))
    grass_stem = material("Verge Stems", (0.035, 0.085, 0.012, 1.0))
    stone = material("Verge Weathered Stone", (0.085, 0.080, 0.065, 1.0))
    bark = material("Verge Deadwood", (0.050, 0.025, 0.010, 1.0))
    flower_gold = material("Verge Gold Flowers", (0.55, 0.22, 0.015, 1.0), 0.9)
    flower_white = material("Verge White Flowers", (0.48, 0.48, 0.35, 1.0), 0.9)

    objects = []
    # Three irregular colonies of broad, curved leaves. Their silhouettes are
    # intentionally wide enough to read as grass instead of upright green rods.
    colony_centers = [(-1.75, -0.45, 0.0), (0.10, 0.36, 0.0), (1.82, -0.10, 0.0)]
    for colony_index, center in enumerate(colony_centers):
        leaf_count = (8, 11, 7)[colony_index]
        for leaf_index in range(leaf_count):
            angle = rng.uniform(0.0, math.tau)
            radial = rng.uniform(0.02, 0.42)
            root = (center[0] + math.cos(angle) * radial, center[1] + math.sin(angle) * radial, 0.018)
            objects.append(tapered_leaf(
                f"BroadGrass_{colony_index}_{leaf_index}", root, angle + rng.uniform(-0.25, 0.25),
                rng.uniform(0.42, 0.83), rng.uniform(0.075, 0.13), rng.uniform(0.38, 0.64), grass,
            ))

    stone_specs = [
        ((-0.82, -0.63, 0.12), (0.34, 0.23, 0.14), 0.4),
        ((0.83, 0.65, 0.10), (0.28, 0.22, 0.12), -0.8),
        ((2.42, -0.50, 0.08), (0.22, 0.17, 0.10), 0.2),
        ((-2.32, 0.27, 0.075), (0.20, 0.16, 0.09), -0.3),
    ]
    for index, (location, scale, yaw) in enumerate(stone_specs):
        objects.append(weathered_stone(f"LowStone_{index}", location, scale, yaw, stone, 930 + index * 17))

    # One short fallen branch breaks the plant rhythm without becoming a
    # collision obstacle on the walkable shoulder.
    objects.append(cylinder_between("DeadwoodMain", (-0.45, 0.74, 0.09), (0.72, 0.88, 0.13), 0.075, bark, 8))
    objects.append(cylinder_between("DeadwoodTwig", (0.18, 0.82, 0.12), (0.48, 1.05, 0.22), 0.030, bark, 7))

    for index, location in enumerate([(-1.23, 0.18, 0.02), (1.22, -0.49, 0.02), (2.05, 0.42, 0.02), (-2.18, -0.42, 0.02)]):
        flower_mat = flower_gold if index % 3 else flower_white
        objects.extend(flower(f"SmallFlower_{index}", location, rng.uniform(0.34, 0.55), flower_mat, grass_stem, 460 + index))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    verge = bpy.context.object
    verge.name = "RoadsideVergeCluster"
    verge["visual_role"] = "roadside verge detail"
    verge["step_over"] = True

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    print(f"ROADSIDE_VERGE_BUILT|blend={BLEND_PATH}|glb={GLB_PATH}|objects={len(objects)}")


if __name__ == "__main__":
    main()
