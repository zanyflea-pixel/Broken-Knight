import bpy
import math
import os


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ITEMS = os.path.join(ROOT, "assets", "items")


def material(name, color, metallic=0.0, roughness=0.7):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.metallic = metallic
    mat.roughness = roughness
    # glTF exports the node material, not Blender's viewport-only diffuse
    # swatch. Keep the Principled shader in sync so the tools retain their
    # wood, leather and forged-metal colours in Godot.
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def bevel(obj, width=0.025, segments=2):
    modifier = obj.modifiers.new("Soft forged edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def cylinder(name, radius, depth, location, mat, rotation=(0.0, 0.0, 0.0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel(obj, min(radius * 0.22, 0.018), 2)
    return obj


def cube(name, scale, location, mat, rotation=(0.0, 0.0, 0.0), bevel_width=0.02):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    bevel(obj, bevel_width, 2)
    return obj


def axe_blade(mat):
    # One closed forged wedge: every blade vertex meets the eye block, so the
    # head cannot look like disconnected floating pieces.
    verts = []
    profile = [
        (-0.04, 0.47),
        (0.34, 0.42),
        (0.62, 0.30),
        (0.62, 0.90),
        (0.34, 0.83),
        (-0.04, 0.77),
    ]
    for y in (-0.075, 0.075):
        verts.extend((x, y, z) for x, z in profile)
    faces = []
    faces.append(tuple(range(6)))
    faces.append(tuple(range(11, 5, -1)))
    for i in range(6):
        j = (i + 1) % 6
        faces.append((i, j, j + 6, i + 6))
    mesh = bpy.data.meshes.new("ConnectedAxeBladeMesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Connected forged axe blade", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bevel(obj, 0.018, 2)
    return obj


def build_axe():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = material("Oiled ash handle", (0.27, 0.105, 0.035), roughness=0.72)
    grip = material("Dark leather grip", (0.075, 0.027, 0.014), roughness=0.88)
    steel = material("Forged steel", (0.30, 0.36, 0.40), metallic=0.72, roughness=0.28)
    edge = material("Honed edge", (0.62, 0.70, 0.74), metallic=0.84, roughness=0.18)

    cylinder("Continuous ash haft", 0.052, 1.52, (0, 0, -0.02), wood, vertices=14)
    cylinder("Steel head eye", 0.115, 0.34, (0.0, 0.0, 0.65), steel, rotation=(0, math.pi / 2, 0), vertices=14)
    axe_blade(steel)
    cube("Hardened cutting edge", (0.024, 0.087, 0.285), (0.615, 0, 0.60), edge, bevel_width=0.012)
    cube("Balanced rear poll", (0.18, 0.095, 0.11), (-0.24, 0, 0.65), steel, bevel_width=0.025)
    for z in (-0.54, -0.43, -0.32):
        cylinder("Leather wrap", 0.060, 0.065, (0, 0, z), grip, vertices=14)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ITEMS, "axe_v2.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )


def build_pickaxe():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = material("Oiled hickory handle", (0.31, 0.13, 0.045), roughness=0.72)
    grip = material("Leather hand wrap", (0.085, 0.032, 0.015), roughness=0.88)
    steel = material("Mining steel", (0.28, 0.34, 0.38), metallic=0.76, roughness=0.27)
    tip = material("Hardened pick tips", (0.58, 0.65, 0.69), metallic=0.86, roughness=0.17)

    cylinder("Continuous hickory haft", 0.050, 1.56, (0, 0, -0.03), wood, vertices=14)
    cylinder("Pick head eye", 0.118, 0.36, (0, 0, 0.67), steel, rotation=(0, math.pi / 2, 0), vertices=14)
    bpy.ops.mesh.primitive_cone_add(
        vertices=12, radius1=0.125, radius2=0.026, depth=0.72,
        location=(0.36, 0, 0.67), rotation=(0, math.pi / 2, 0)
    )
    right = bpy.context.object
    right.name = "Right tapered mining pick"
    right.data.materials.append(steel)
    bevel(right, 0.012, 2)
    bpy.ops.mesh.primitive_cone_add(
        vertices=12, radius1=0.125, radius2=0.026, depth=0.72,
        location=(-0.36, 0, 0.67), rotation=(0, -math.pi / 2, 0)
    )
    left = bpy.context.object
    left.name = "Left tapered mining pick"
    left.data.materials.append(steel)
    bevel(left, 0.012, 2)
    cylinder("Right hardened tip", 0.030, 0.13, (0.755, 0, 0.67), tip, rotation=(0, math.pi / 2, 0), vertices=10)
    cylinder("Left hardened tip", 0.030, 0.13, (-0.755, 0, 0.67), tip, rotation=(0, math.pi / 2, 0), vertices=10)
    for z in (-0.58, -0.47, -0.36):
        cylinder("Leather wrap", 0.059, 0.062, (0, 0, z), grip, vertices=14)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ITEMS, "pickaxe.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )


os.makedirs(ITEMS, exist_ok=True)
build_axe()
build_pickaxe()
print("HAND_TOOLS_BUILT", os.path.join(ITEMS, "axe_v2.glb"), os.path.join(ITEMS, "pickaxe.glb"))
