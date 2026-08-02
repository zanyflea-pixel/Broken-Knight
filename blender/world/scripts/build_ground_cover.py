import bpy
import math
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
OUTPUT = PROJECT_ROOT / "godot" / "assets" / "vegetation" / "meadow_grass_clump.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)

vertices = []
faces = []
for index in range(9):
    angle = index * math.tau / 9.0 + (index % 2) * 0.13
    direction = (math.cos(angle), math.sin(angle))
    side = (-direction[1], direction[0])
    height = 0.30 + (index % 4) * 0.055
    root_width = 0.046 + (index % 3) * 0.008
    mid_width = root_width * 0.72
    root = (direction[0] * 0.025, direction[1] * 0.025)
    middle = (direction[0] * (0.09 + (index % 3) * 0.018), direction[1] * (0.09 + (index % 3) * 0.018))
    tip = (direction[0] * (0.19 + (index % 2) * 0.04), direction[1] * (0.19 + (index % 2) * 0.04))
    base = len(vertices)
    vertices.extend([
        (root[0] + side[0] * root_width, root[1] + side[1] * root_width, 0.0),
        (root[0] - side[0] * root_width, root[1] - side[1] * root_width, 0.0),
        (middle[0] + side[0] * mid_width, middle[1] + side[1] * mid_width, height * 0.52),
        (middle[0] - side[0] * mid_width, middle[1] - side[1] * mid_width, height * 0.52),
        (tip[0], tip[1], height),
    ])
    faces.extend([
        (base, base + 1, base + 3),
        (base, base + 3, base + 2),
        (base + 2, base + 3, base + 4),
    ])

mesh = bpy.data.meshes.new("MeadowGrassClumpMesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
clump = bpy.data.objects.new("Meadow Grass Clump", mesh)
bpy.context.collection.objects.link(clump)

material = bpy.data.materials.new("Meadow leaf")
material.use_nodes = True
bsdf = material.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.16, 0.31, 0.095, 1.0)
bsdf.inputs["Roughness"].default_value = 0.96
clump.data.materials.append(material)

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
clump.select_set(True)
bpy.context.view_layer.objects.active = clump
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
print("GROUND_COVER_BUILT", OUTPUT)
