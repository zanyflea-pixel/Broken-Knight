import math
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = PROJECT_ROOT / "blender" / "world" / "architecture"
ASSET_DIR = PROJECT_ROOT / "godot" / "assets" / "architecture"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.82, metallic=0.0):
    rgba = (*color, 1.0)

    mat = bpy.data.materials.new(name)

    # Blender viewport color
    mat.diffuse_color = rgba
    mat.roughness = roughness
    mat.metallic = metallic

    # GLB / glTF export color
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")

    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

    return mat


WOOD = None
IRON = None
BRASS = None


def cube(name, location, scale, mat, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0] * 0.5, scale[1] * 0.5, scale[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft dressed edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, location, radius, depth, mat, rotation=(0.0, 0.0, 0.0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def torus(name, location, major_radius, minor_radius, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=12,
        minor_segments=5,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def join_objects(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return result


def build_sign_bracket():
    parts = [
        cube("Wall plate", (0.0, 0.0, 0.72), (0.34, 0.16, 1.25), IRON, 0.04),
        cube("Upper arm", (0.0, -0.76, 1.24), (0.18, 1.65, 0.18), IRON, 0.035),
        cube("Diagonal brace", (0.0, -0.46, 0.88), (0.14, 1.02, 0.14), IRON, 0.025, (math.radians(-46), 0.0, 0.0)),
        cube("Outer crossbar", (0.0, -1.52, 1.24), (1.25, 0.16, 0.16), IRON, 0.035),
        torus("Outer curl", (0.0, -1.52, 1.24), 0.20, 0.045, IRON, (math.pi * 0.5, 0.0, 0.0)),
    ]
    for x in (-0.44, 0.44):
        parts.append(torus("Hanging ring", (x, -1.52, 1.06), 0.10, 0.032, IRON, (math.pi * 0.5, 0.0, 0.0)))
        parts.append(cylinder("Short chain", (x, -1.52, 0.78), 0.028, 0.50, IRON, vertices=8))
    return join_objects("HouseSignBracket", parts)


def build_sign_board():
    parts = [
        cube("Sign face", (0.0, 0.0, 0.0), (1.55, 0.15, 1.03), WOOD, 0.12),
        cube("Lower point", (0.0, 0.0, -0.58), (0.72, 0.15, 0.55), WOOD, 0.10, (0.0, math.pi * 0.25, 0.0)),
        cylinder("Sign boss", (0.0, -0.10, 0.0), 0.13, 0.08, BRASS, (math.pi * 0.5, 0.0, 0.0), 10),
    ]
    return join_objects("HouseSignBoard", parts)


def build_chair():
    parts = [cube("Seat", (0.0, 0.0, 0.82), (0.92, 0.92, 0.18), WOOD, 0.05)]
    for x in (-0.34, 0.34):
        for y in (-0.34, 0.34):
            parts.append(cylinder("Turned chair leg", (x, y, 0.39), 0.065, 0.78, WOOD, vertices=8))
    for x in (-0.38, 0.38):
        parts.append(cylinder("Chair back post", (x, 0.39, 1.52), 0.075, 1.50, WOOD, vertices=8))
    for z in (1.16, 1.52, 1.88):
        parts.append(cube("Chair back rail", (0.0, 0.39, z), (0.82, 0.10, 0.12), WOOD, 0.025))
    return join_objects("FurnitureChair", parts)


def build_barrel():
    parts = [cylinder("Barrel body", (0.0, 0.0, 0.65), 0.50, 1.30, WOOD, vertices=16)]
    for z in (0.18, 0.62, 1.12):
        parts.append(torus("Barrel hoop", (0.0, 0.0, z), 0.49, 0.045, IRON))
    return join_objects("FurnitureBarrel", parts)


def build_bookshelf():
    parts = [
        cube("Shelf left", (-0.92, 0.0, 1.55), (0.18, 0.50, 3.10), WOOD, 0.035),
        cube("Shelf right", (0.92, 0.0, 1.55), (0.18, 0.50, 3.10), WOOD, 0.035),
        cube("Shelf back", (0.0, 0.19, 1.55), (2.0, 0.12, 3.10), WOOD, 0.025),
    ]
    for z in (0.12, 0.86, 1.60, 2.34, 3.02):
        parts.append(cube("Shelf plank", (0.0, -0.05, z), (2.02, 0.58, 0.16), WOOD, 0.035))
    return join_objects("FurnitureBookshelf", parts)


def build_chandelier():
    parts = [
        torus("Chandelier ring", (0.0, 0.0, 0.0), 1.15, 0.07, IRON),
        cylinder("Chandelier stem", (0.0, 0.0, 0.70), 0.055, 1.45, IRON, vertices=8),
    ]
    for i in range(8):
        angle = math.tau * i / 8.0
        x = math.cos(angle) * 1.15
        y = math.sin(angle) * 1.15
        parts.append(cylinder("Candle cup", (x, y, 0.15), 0.10, 0.30, BRASS, vertices=10))
    return join_objects("CastleChandelier", parts)


def build_weapon_rack():
    parts = [
        cube("Weapon rack base", (0.0, 0.0, 0.12), (3.5, 0.85, 0.24), WOOD, 0.05),
        cube("Weapon rack rail", (0.0, 0.0, 1.62), (3.6, 0.32, 0.24), WOOD, 0.04),
    ]
    for x in (-1.50, 1.50):
        parts.append(cube("Weapon rack upright", (x, 0.0, 0.88), (0.24, 0.30, 1.76), WOOD, 0.04))
    for x in (-1.12, -0.38, 0.38, 1.12):
        parts.append(cylinder("Spear shaft", (x, 0.0, 1.72), 0.035, 3.20, WOOD, vertices=7))
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.13, radius2=0.0, depth=0.38, location=(x, 0.0, 3.49))
        tip = bpy.context.object
        tip.name = "Spear head"
        tip.data.materials.append(IRON)
        parts.append(tip)
    return join_objects("CastleWeaponRack", parts)


def main():
    global WOOD, IRON, BRASS
    clear_scene()
    WOOD = material("Aged oak", (0.28, 0.14, 0.055), 0.92)
    IRON = material("Blackened iron", (0.055, 0.06, 0.065), 0.70, 0.32)
    BRASS = material("Old brass", (0.45, 0.25, 0.055), 0.58, 0.52)
    build_sign_bracket()
    build_sign_board()
    build_chair()
    build_barrel()
    build_bookshelf()
    build_chandelier()
    build_weapon_rack()
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    blend_path = SOURCE_DIR / "architecture_detail_kit_v1.blend"
    glb_path = ASSET_DIR / "architecture_detail_kit_v1.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"ARCHITECTURE_DETAIL_EXPORT|blend={blend_path}|glb={glb_path}")


if __name__ == "__main__":
    main()
