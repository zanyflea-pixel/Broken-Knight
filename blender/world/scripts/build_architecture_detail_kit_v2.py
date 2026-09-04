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


def build_filled_bookcase(wood, iron, book_red, book_blue, book_green, parchment):
    parts = [
        base.cube("Bookcase left", (-0.94, 0.0, 1.58), (0.18, 0.54, 3.16), wood, 0.035),
        base.cube("Bookcase right", (0.94, 0.0, 1.58), (0.18, 0.54, 3.16), wood, 0.035),
        base.cube("Bookcase back", (0.0, 0.20, 1.58), (2.05, 0.12, 3.16), wood, 0.025),
        base.cube("Bookcase crown", (0.0, 0.0, 3.18), (2.25, 0.62, 0.22), wood, 0.05),
    ]
    book_materials = (book_red, book_blue, book_green, parchment)
    shelf_levels = (0.12, 0.86, 1.60, 2.34, 3.02)
    for shelf_z in shelf_levels:
        parts.append(base.cube("Book shelf", (0.0, -0.05, shelf_z), (2.06, 0.60, 0.16), wood, 0.035))
    for row, shelf_z in enumerate(shelf_levels[:-1]):
        cursor = -0.76
        for book_index in range(7):
            width = 0.15 + 0.035 * ((book_index + row) % 3)
            height = 0.45 + 0.06 * ((book_index * 2 + row) % 4)
            lean = math.radians((-4.0, 0.0, 3.0)[(book_index + row) % 3])
            parts.append(base.cube(
                "Bound readable volume",
                (cursor + width * 0.5, -0.23, shelf_z + 0.10 + height * 0.5),
                (width, 0.34, height),
                book_materials[(book_index + row) % len(book_materials)],
                0.018,
                (0.0, lean, 0.0),
            ))
            cursor += width + 0.055
    for x in (-0.55, 0.55):
        parts.append(base.cube("Iron shelf strap", (x, -0.34, 1.58), (0.055, 0.05, 3.02), iron, 0.012))
    return base.join_objects("FurnitureBookcaseFull", parts)


def build_kitchen_set(wood, iron, brass, stone, ceramic, herb):
    parts = [
        base.cube("Kitchen worktop", (0.0, 0.0, 1.12), (3.65, 1.18, 0.22), wood, 0.065),
        base.cube("Kitchen lower cupboard", (-0.96, 0.18, 0.54), (1.45, 0.82, 1.02), wood, 0.055),
        base.cube("Stone chopping block", (0.78, -0.05, 1.30), (0.92, 0.62, 0.16), stone, 0.045),
        base.cube("Kitchen wall shelf", (0.0, 0.40, 2.30), (3.30, 0.62, 0.16), wood, 0.04),
        base.cube("Kitchen shelf rail", (0.0, 0.62, 2.62), (3.30, 0.10, 0.56), wood, 0.025),
    ]
    for x in (-1.45, 1.45):
        parts.append(base.cube("Kitchen leg", (x, 0.0, 0.54), (0.17, 0.86, 1.08), wood, 0.035))
    for x in (-1.05, -0.35, 0.35, 1.05):
        parts.append(base.cylinder("Glazed bowl", (x, 0.14, 2.47), 0.20, 0.16, ceramic, vertices=12))
    parts.extend([
        base.cylinder("Cooking pot", (-0.20, -0.15, 1.36), 0.33, 0.34, iron, vertices=14),
        base.torus("Cooking pot handle", (-0.20, -0.15, 1.62), 0.25, 0.035, brass, (math.pi * 0.5, 0.0, 0.0)),
        base.cylinder("Herb bundle", (1.45, 0.50, 1.78), 0.055, 0.72, herb, vertices=7),
        base.cylinder("Herb bundle", (1.18, 0.50, 1.68), 0.048, 0.58, herb, (0.0, math.radians(8.0), 0.0), 7),
    ])
    return base.join_objects("FurnitureKitchenSet", parts)


def build_workshop_set(wood, iron, stone):
    parts = [
        base.cube("Workshop bench top", (0.0, 0.0, 1.10), (4.05, 1.45, 0.28), wood, 0.065),
        base.cube("Workshop tool board", (0.0, 0.58, 2.18), (3.92, 0.16, 1.90), wood, 0.045),
        base.cube("Workshop lower stretcher", (0.0, 0.0, 0.46), (3.42, 0.16, 0.16), iron, 0.025),
        base.cube("Stone vise base", (1.35, -0.12, 1.42), (0.66, 0.72, 0.32), stone, 0.045),
        base.cube("Vise jaw", (1.35, -0.42, 1.61), (0.72, 0.16, 0.42), iron, 0.025),
    ]
    for x in (-1.60, 1.60):
        parts.append(base.cube("Workshop leg", (x, 0.0, 0.52), (0.24, 1.02, 1.04), wood, 0.045))
    for index, x in enumerate((-1.35, -0.72, 0.0, 0.68)):
        angle = math.radians((-10.0, 8.0, -5.0, 12.0)[index])
        parts.append(base.cube("Hanging tool", (x, 0.43, 2.20), (0.10, 0.14, 1.12), iron, 0.018, (0.0, angle, 0.0)))
        parts.append(base.cube("Tool handle", (x, 0.40, 1.58), (0.13, 0.13, 0.45), wood, 0.02, (0.0, angle, 0.0)))
    parts.append(base.cube("Bench hammer handle", (-0.82, -0.18, 1.43), (0.12, 0.12, 1.02), wood, 0.025, (0.0, math.radians(64.0), 0.0)))
    parts.append(base.cube("Bench hammer head", (-0.38, -0.18, 1.56), (0.58, 0.22, 0.24), iron, 0.035, (0.0, math.radians(64.0), 0.0)))
    return base.join_objects("FurnitureWorkshopSet", parts)


def build_tavern_set(wood, iron, brass, ceramic):
    parts = [
        base.cube("Tavern bar front", (0.0, 0.18, 0.62), (4.80, 0.66, 1.24), wood, 0.065),
        base.cube("Tavern bar top", (0.0, -0.10, 1.33), (5.10, 1.20, 0.22), wood, 0.075),
        base.cube("Tavern foot rail", (0.0, -0.52, 0.28), (4.55, 0.12, 0.12), brass, 0.025),
    ]
    for x in (-1.82, -0.62, 0.62, 1.82):
        parts.append(base.cylinder("Tankard", (x, -0.24, 1.57), 0.14, 0.34, ceramic, vertices=10))
        parts.append(base.torus("Tankard handle", (x + 0.16, -0.24, 1.57), 0.11, 0.028, brass, (math.pi * 0.5, 0.0, 0.0)))
    for x in (-1.75, 1.75):
        parts.append(base.cylinder("Small ale keg", (x, 0.58, 0.58), 0.48, 1.05, wood, (0.0, math.pi * 0.5, 0.0), 14))
        parts.append(base.torus("Keg hoop", (x - 0.34, 0.58, 0.58), 0.47, 0.04, iron, (0.0, math.pi * 0.5, 0.0)))
        parts.append(base.torus("Keg hoop", (x + 0.34, 0.58, 0.58), 0.47, 0.04, iron, (0.0, math.pi * 0.5, 0.0)))
    return base.join_objects("FurnitureTavernSet", parts)


def build_guard_post(wood, iron, cloth, brass):
    parts = [
        base.cube("Guard bench seat", (0.0, 0.0, 0.72), (3.25, 1.02, 0.22), wood, 0.055),
        base.cube("Guard bench back", (0.0, 0.42, 1.38), (3.25, 0.18, 1.18), wood, 0.045),
        base.cylinder("Guard stand", (0.0, 0.16, 2.15), 0.10, 2.65, wood, vertices=10),
        base.cube("Guard cross arm", (0.0, 0.16, 2.78), (1.72, 0.14, 0.14), wood, 0.025),
        base.cylinder("Round watch shield", (0.0, -0.18, 2.10), 0.72, 0.16, cloth, (math.pi * 0.5, 0.0, 0.0), 18),
        base.cylinder("Shield boss", (0.0, -0.29, 2.10), 0.18, 0.16, brass, (math.pi * 0.5, 0.0, 0.0), 12),
    ]
    for x in (-1.38, 1.38):
        parts.append(base.cube("Guard bench leg", (x, 0.0, 0.34), (0.24, 0.76, 0.68), wood, 0.035))
        parts.append(base.cylinder("Guard spear", (x, 0.46, 1.86), 0.042, 3.55, wood, (0.0, math.radians(4.0 * x), 0.0), 8))
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.15, radius2=0.0, depth=0.42, location=(x, 0.46, 3.83))
        spear_head = bpy.context.object
        spear_head.name = "Guard spear head"
        spear_head.data.materials.append(iron)
        parts.append(spear_head)
    return base.join_objects("FurnitureGuardPost", parts)


def build_reading_desk(wood, iron, parchment, ink):
    parts = [
        base.cube("Writing desk top", (0.0, 0.0, 1.08), (2.85, 1.45, 0.24), wood, 0.065),
        base.cube("Writing desk back rail", (0.0, 0.58, 1.45), (2.85, 0.18, 0.78), wood, 0.045),
        base.cube("Open book left", (-0.36, -0.20, 1.28), (0.72, 0.56, 0.06), parchment, 0.025, (0.0, math.radians(-8.0), math.radians(3.0))),
        base.cube("Open book right", (0.36, -0.20, 1.28), (0.72, 0.56, 0.06), parchment, 0.025, (0.0, math.radians(8.0), math.radians(-3.0))),
        base.cylinder("Ink pot", (0.94, -0.24, 1.37), 0.13, 0.22, ink, vertices=10),
        base.cube("Quill", (1.03, -0.24, 1.66), (0.055, 0.055, 0.78), parchment, 0.015, (0.0, math.radians(18.0), 0.0)),
    ]
    for x in (-1.12, 1.12):
        for y in (-0.46, 0.46):
            parts.append(base.cube("Writing desk leg", (x, y, 0.52), (0.18, 0.18, 1.04), wood, 0.035))
    parts.append(base.cube("Desk stretcher", (0.0, 0.0, 0.44), (2.30, 0.12, 0.12), iron, 0.02))
    return base.join_objects("FurnitureReadingDesk", parts)


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
    book_red = base.material("Ox-blood book leather", (0.31, 0.045, 0.025), 0.88)
    book_blue = base.material("Indigo book cloth", (0.045, 0.12, 0.26), 0.90)
    book_green = base.material("Moss book cloth", (0.08, 0.22, 0.09), 0.92)
    parchment = base.material("Written parchment", (0.70, 0.57, 0.34), 0.94)
    ceramic = base.material("Glazed earthenware", (0.27, 0.37, 0.40), 0.72)
    herb = base.material("Dried kitchen herbs", (0.20, 0.29, 0.08), 0.96)
    ink = base.material("Black ink", (0.018, 0.020, 0.024), 0.50)
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
    build_filled_bookcase(wood, iron, book_red, book_blue, book_green, parchment)
    build_kitchen_set(wood, iron, brass, stone, ceramic, herb)
    build_workshop_set(wood, iron, stone)
    build_tavern_set(wood, iron, brass, ceramic)
    build_guard_post(wood, iron, cloth, brass)
    build_reading_desk(wood, iron, parchment, ink)

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
