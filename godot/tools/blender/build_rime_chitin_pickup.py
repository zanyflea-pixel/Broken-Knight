import math
import os

import bpy


OUTPUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "items", "rime_chitin_pickup_v1.glb")
)
BLEND_SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "blender", "items", "rime_chitin_pickup_v1.blend")
)


def material(name, color, roughness, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def add_plate(name, location, scale, rotation, mat, parent):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location, rotation=rotation)
    plate = bpy.context.object
    plate.name = name
    plate.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for vertex in plate.data.vertices:
        direction = vertex.co.normalized()
        vertex.co += direction * (0.025 * math.sin(vertex.index * 4.31))
    plate.data.materials.append(mat)
    plate.parent = parent
    return plate


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

root = bpy.data.objects.new("RimeChitinPickup", None)
bpy.context.collection.objects.link(root)
dark = material("Rime Chitin slate", (0.16, 0.24, 0.27), 0.88)
weathered = material("Rime Chitin weathered edge", (0.38, 0.52, 0.55), 0.78)
ice = material("Rime Chitin frost vein", (0.19, 0.66, 0.78), 0.30, 0.08)

# A low, asymmetric pile reads as discarded armor plates instead of another
# ore rock. Its footprint is deliberately flat so it rests naturally on land.
add_plate("BroadCarapacePlate", (0.00, 0.00, 0.17), (0.58, 0.42, 0.13), (0.10, 0.16, -0.12), dark, root)
add_plate("WeatheredSidePlate", (-0.38, 0.12, 0.13), (0.38, 0.27, 0.095), (-0.05, -0.12, 0.42), weathered, root)
add_plate("NarrowCarapacePlate", (0.37, -0.12, 0.12), (0.40, 0.23, 0.085), (0.02, 0.10, -0.48), dark, root)
add_plate("FrostVein", (0.04, -0.03, 0.29), (0.37, 0.075, 0.035), (0.10, 0.08, -0.15), ice, root)

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
os.makedirs(os.path.dirname(BLEND_SOURCE), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_SOURCE)
bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format="GLB", export_apply=True, export_yup=True)
print("RIME_CHITIN_PICKUP_EXPORT|%s" % OUTPUT)
