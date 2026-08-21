import math
import importlib.util
from pathlib import Path

import bpy

_BASE_PATH = Path(__file__).with_name("build_architecture_detail_kit.py")
_BASE_SPEC = importlib.util.spec_from_file_location("broken_knight_architecture_v1", _BASE_PATH)
base = importlib.util.module_from_spec(_BASE_SPEC)
_BASE_SPEC.loader.exec_module(base)


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = PROJECT_ROOT / "blender" / "world" / "architecture"
ASSET_DIR = PROJECT_ROOT / "godot" / "assets" / "architecture"


def build_window_surround(wood, stone):
    parts = [
        base.cube("Left jamb", (-0.79, 0.0, 0.0), (0.18, 0.24, 1.92), wood, 0.035),
        base.cube("Right jamb", (0.79, 0.0, 0.0), (0.18, 0.24, 1.92), wood, 0.035),
        base.cube("Lintel", (0.0, 0.0, 0.91), (1.76, 0.26, 0.18), wood, 0.035),
        base.cube("Stone sill", (0.0, -0.06, -0.91), (1.98, 0.42, 0.18), stone, 0.055),
        base.cube("Center mullion", (0.0, -0.03, 0.0), (0.10, 0.18, 1.62), wood, 0.02),
        base.cube("Cross rail", (0.0, -0.03, 0.0), (1.46, 0.18, 0.10), wood, 0.02),
    ]
    # Open shutters sit against the wall instead of covering the real opening.
    for side in (-1.0, 1.0):
        sx = 1.17 * side
        parts.append(base.cube("Open shutter", (sx, 0.02, 0.0), (0.56, 0.11, 1.55), wood, 0.04, (0.0, 0.0, math.radians(2.5 * side))))
        for z in (-0.52, 0.0, 0.52):
            parts.append(base.cube("Shutter batten", (sx, -0.055, z), (0.50, 0.08, 0.09), stone, 0.018))
    return base.join_objects("HouseWindowSurround", parts)


def build_door_canopy(wood, tile, iron):
    parts = [
        base.cube("Canopy wall plate", (0.0, 0.0, 0.0), (2.9, 0.22, 0.28), wood, 0.045),
        base.cube("Canopy roof", (0.0, -1.05, 0.42), (3.25, 2.35, 0.24), tile, 0.06, (math.radians(-9.0), 0.0, 0.0)),
        base.cube("Canopy front fascia", (0.0, -2.13, 0.25), (3.28, 0.18, 0.32), wood, 0.04),
    ]
    for side in (-1.0, 1.0):
        parts.append(base.cube("Canopy bracket", (1.15 * side, -0.82, -0.40), (0.16, 1.85, 0.16), wood, 0.035, (math.radians(-42.0), 0.0, 0.0)))
        parts.append(base.cylinder("Canopy nail", (1.15 * side, -0.14, -0.02), 0.055, 0.10, iron, (math.pi * 0.5, 0.0, 0.0), 8))
    return base.join_objects("HouseDoorCanopy", parts)


def build_wall_lantern(iron, brass, glow):
    parts = [
        base.cube("Lantern wall plate", (0.0, 0.0, 0.25), (0.28, 0.14, 0.72), iron, 0.04),
        base.cube("Lantern arm", (0.0, -0.52, 0.52), (0.13, 1.0, 0.13), iron, 0.025, (math.radians(-12.0), 0.0, 0.0)),
        base.cube("Lantern cap", (0.0, -1.03, 0.47), (0.62, 0.62, 0.12), iron, 0.045),
        base.cube("Lantern glow", (0.0, -1.03, 0.03), (0.42, 0.42, 0.72), glow, 0.05),
        base.cube("Lantern base", (0.0, -1.03, -0.39), (0.58, 0.58, 0.12), brass, 0.04),
    ]
    for x in (-0.23, 0.23):
        for y in (-1.26, -0.80):
            parts.append(base.cylinder("Lantern cage", (x, y, 0.03), 0.025, 0.82, iron, vertices=7))
    return base.join_objects("HouseWallLantern", parts)


def build_flower_box(wood, iron, foliage):
    parts = [
        base.cube("Planter body", (0.0, -0.18, 0.0), (1.72, 0.62, 0.48), wood, 0.06),
        base.cube("Planter rim", (0.0, -0.18, 0.27), (1.90, 0.70, 0.13), iron, 0.03),
    ]
    for x in (-0.58, -0.18, 0.22, 0.60):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.24, location=(x, -0.20, 0.48 + 0.08 * math.sin(x * 7.0)))
        leaf = bpy.context.object
        leaf.name = "Planter foliage"
        leaf.scale = (1.0, 0.72, 0.72)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        leaf.data.materials.append(foliage)
        parts.append(leaf)
    return base.join_objects("HouseFlowerBox", parts)


def build_table(wood, iron):
    parts = [base.cube("Table top", (0.0, 0.0, 1.20), (3.2, 1.48, 0.24), wood, 0.075)]
    for x in (-1.27, 1.27):
        for y in (-0.52, 0.52):
            parts.append(base.cylinder("Turned table leg", (x, y, 0.57), 0.085, 1.12, wood, vertices=10))
    parts.append(base.cube("Table stretcher", (0.0, 0.0, 0.56), (2.65, 0.12, 0.13), iron, 0.025))
    return base.join_objects("FurnitureTable", parts)


def build_bed(wood, cloth, linen):
    parts = [
        base.cube("Bed frame", (0.0, 0.0, 0.46), (2.55, 3.85, 0.40), wood, 0.08),
        base.cube("Mattress", (0.0, -0.08, 0.78), (2.28, 3.34, 0.30), linen, 0.12),
        base.cube("Blanket", (0.0, -0.62, 0.98), (2.18, 2.00, 0.14), cloth, 0.09),
        base.cube("Headboard", (0.0, 1.78, 1.30), (2.62, 0.20, 2.20), wood, 0.07),
        base.cube("Pillow", (0.0, 1.15, 1.03), (1.72, 0.74, 0.24), linen, 0.12),
    ]
    for x in (-1.17, 1.17):
        parts.append(base.cylinder("Bed post", (x, 1.78, 1.40), 0.09, 2.75, wood, vertices=10))
    return base.join_objects("FurnitureBed", parts)


def build_chest(wood, iron):
    parts = [
        base.cube("Chest body", (0.0, 0.0, 0.52), (2.05, 1.18, 0.96), wood, 0.10),
        base.cube("Chest lid", (0.0, 0.0, 1.06), (2.16, 1.28, 0.18), wood, 0.08),
        base.cube("Chest band left", (-0.72, -0.61, 0.58), (0.12, 0.08, 1.05), iron, 0.02),
        base.cube("Chest band right", (0.72, -0.61, 0.58), (0.12, 0.08, 1.05), iron, 0.02),
        base.cube("Chest lock", (0.0, -0.68, 0.67), (0.28, 0.12, 0.40), iron, 0.035),
    ]
    return base.join_objects("FurnitureChest", parts)


def main():
    base.clear_scene()
    wood = base.material("Aged oak", (0.28, 0.14, 0.055), 0.92)
    iron = base.material("Blackened iron", (0.055, 0.06, 0.065), 0.70, 0.32)
    brass = base.material("Old brass", (0.45, 0.25, 0.055), 0.58, 0.52)
    stone = base.material("Dressed limestone", (0.42, 0.40, 0.34), 0.96)
    tile = base.material("Weathered clay tile", (0.34, 0.10, 0.045), 0.94)
    foliage = base.material("Window herbs", (0.12, 0.29, 0.08), 0.96)
    cloth = base.material("Dyed wool", (0.35, 0.055, 0.04), 0.96)
    linen = base.material("Natural linen", (0.66, 0.57, 0.42), 0.98)
    glow = base.material("Warm lantern glass", (0.82, 0.35, 0.06), 0.42)
    glow.use_nodes = True
    principled = glow.node_tree.nodes.get("Principled BSDF")
    if principled:
        principled.inputs["Base Color"].default_value = (0.82, 0.35, 0.06, 1.0)
        principled.inputs["Emission Color"].default_value = (1.0, 0.18, 0.025, 1.0)
        principled.inputs["Emission Strength"].default_value = 2.2

    base.WOOD, base.IRON, base.BRASS = wood, iron, brass
    base.build_sign_bracket()
    base.build_sign_board()
    base.build_chair()
    base.build_barrel()
    base.build_bookshelf()
    base.build_chandelier()
    base.build_weapon_rack()
    build_window_surround(wood, stone)
    build_door_canopy(wood, tile, iron)
    build_wall_lantern(iron, brass, glow)
    build_flower_box(wood, iron, foliage)
    build_table(wood, iron)
    build_bed(wood, cloth, linen)
    build_chest(wood, iron)

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    blend_path = SOURCE_DIR / "architecture_detail_kit_v2.blend"
    glb_path = ASSET_DIR / "architecture_detail_kit_v2.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"ARCHITECTURE_DETAIL_V2_EXPORT|blend={blend_path}|glb={glb_path}")


if __name__ == "__main__":
    main()
