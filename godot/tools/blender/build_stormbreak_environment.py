import math
import os

import bpy


OUTPUT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "assets", "world", "stormbreak_environment_kit_v1.glb"
))
BLEND_SOURCE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "blender", "world", "environment", "stormbreak_environment_kit_v1.blend"
))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.94, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


SLATE = material("Stormbreak dark slate", (0.19, 0.22, 0.23))
CUT_STONE = material("Stormbreak cut stone", (0.46, 0.47, 0.43))
FIELD_STONE = material("Stormbreak field stone", (0.29, 0.31, 0.29))
OAK = material("Stormbreak weathered oak", (0.25, 0.15, 0.075), 0.98)
IRON = material("Stormbreak black iron", (0.09, 0.10, 0.10), 0.70, 0.72)
EMBER = material("Stormbreak beacon ember", (0.74, 0.20, 0.035), 0.54)


def bevel_object(obj, width=0.08, segments=2):
    modifier = obj.modifiers.new("Weathered edge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def box(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0), bevel=0.07):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        bevel_object(obj, bevel)
    return obj


def cylinder(name, location, radius, depth, mat, vertices=16, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_object(obj, 0.07)
    return obj


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    root = objects[0]
    root.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    return root


def pitched_roof(pieces, name, center_y, width, depth, base_z, rise, mat):
    angle = math.atan2(rise, width * 0.5)
    slope = math.sqrt((width * 0.5) ** 2 + rise ** 2)
    pieces.append(box(name, (-width * 0.25, center_y, base_z + rise * 0.5),
                      (slope * 0.53, depth * 1.08, 0.34), mat, (0.0, -angle, 0.0)))
    pieces.append(box(name, (width * 0.25, center_y, base_z + rise * 0.5),
                      (slope * 0.53, depth * 1.08, 0.34), mat, (0.0, angle, 0.0)))


def split_wall(pieces, y, width, height, opening_width, opening_height, thickness, mat):
    side = (width - opening_width) * 0.5
    pieces.append(box("WallPier", (-(opening_width + side) * 0.5, y, height * 0.5),
                      (side, thickness, height), mat))
    pieces.append(box("WallPier", ((opening_width + side) * 0.5, y, height * 0.5),
                      (side, thickness, height), mat))
    pieces.append(box("WallLintel", (0, y, opening_height + (height - opening_height) * 0.5),
                      (opening_width, thickness, height - opening_height), mat))


def build_beacon():
    pieces = [
        cylinder("BeaconLowerPlinth", (0, 0, 0.65), 7.6, 1.3, FIELD_STONE, 16),
        cylinder("BeaconUpperPlinth", (0, 0, 1.55), 6.6, 0.7, CUT_STONE, 16),
        cylinder("BeaconTower", (0, 0, 7.0), 5.15, 10.2, FIELD_STONE, 16),
        cylinder("BeaconCrown", (0, 0, 12.55), 6.15, 1.1, CUT_STONE, 16),
    ]
    # Four projecting buttresses and a readable road-facing doorway frame.
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        pieces.append(box(
            "BeaconButtress",
            (math.sin(angle) * 5.35, math.cos(angle) * 5.35, 4.0),
            (1.45, 1.45, 6.4), CUT_STONE, (0.0, 0.0, -angle)
        ))
    pieces.extend([
        box("BeaconDoorPier", (-1.9, -5.05, 3.3), (1.45, 0.72, 4.7), CUT_STONE),
        box("BeaconDoorPier", (1.9, -5.05, 3.3), (1.45, 0.72, 4.7), CUT_STONE),
        box("BeaconDoorLintel", (0, -5.05, 6.25), (2.45, 0.72, 1.0), CUT_STONE),
    ])
    # Open timber beacon basket, unmistakable on the skyline without a giant glow cube.
    pieces.append(cylinder("BeaconHearth", (0, 0, 13.45), 3.2, 0.55, IRON, 12))
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        pieces.append(box("BeaconIronCage", (math.sin(angle) * 2.75, math.cos(angle) * 2.75, 16.0),
                          (0.28, 0.28, 5.1), IRON))
    for angle in (math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75):
        pieces.append(box("BeaconFuel", (math.sin(angle) * 1.25, math.cos(angle) * 1.25, 14.15),
                          (0.38, 3.4, 0.38), OAK, (0.0, 0.0, angle)))
    pieces.append(cylinder("BeaconEmberBed", (0, 0, 14.05), 2.15, 0.34, EMBER, 12))
    return join_objects(pieces, "StormbreakBeacon")


def build_shelter():
    pieces = [
        box("ShelterStoneFloor", (0, 0, 0.28), (14.5, 11.0, 0.56), CUT_STONE),
        box("ShelterRearWall", (0, 5.1, 3.9), (13.4, 0.8, 7.8), FIELD_STONE),
        box("ShelterFrontPier", (-5.1, -5.1, 3.7), (3.2, 0.8, 7.4), FIELD_STONE),
        box("ShelterFrontPier", (5.1, -5.1, 3.7), (3.2, 0.8, 7.4), FIELD_STONE),
        box("ShelterFrontLintel", (0, -5.1, 6.6), (4.0, 0.8, 1.6), CUT_STONE),
    ]
    for side in (-1, 1):
        x = side * 6.35
        pieces.extend([
            box("ShelterSideLow", (x, 0, 1.25), (0.8, 8.6, 2.5), FIELD_STONE),
            box("ShelterSideHigh", (x, 0, 6.5), (0.8, 8.6, 1.8), FIELD_STONE),
            box("ShelterWindowPier", (x, -2.85, 4.0), (0.8, 1.0, 2.8), CUT_STONE),
            box("ShelterWindowPier", (x, 2.85, 4.0), (0.8, 1.0, 2.8), CUT_STONE),
        ])
    pitched_roof(pieces, "ShelterSlateRoof", 0, 15.3, 12.0, 7.7, 4.5, SLATE)
    # Useful interior rather than an empty shell.
    pieces.extend([
        box("ShelterHearth", (0, 3.7, 1.15), (3.0, 1.8, 2.3), CUT_STONE),
        box("ShelterTable", (0, 0.8, 1.5), (5.5, 2.4, 0.35), OAK),
        box("ShelterBench", (-4.25, 1.0, 0.9), (0.9, 5.4, 0.42), OAK),
        box("ShelterBench", (4.25, 1.0, 0.9), (0.9, 5.4, 0.42), OAK),
        box("ShelterWoodRack", (4.5, 4.25, 1.8), (2.2, 0.65, 3.2), OAK),
    ])
    return join_objects(pieces, "StormbreakShelter")


def build_ruin():
    pieces = [box("ChoirStoneFloor", (0, 0, 0.22), (19.0, 28.0, 0.44), CUT_STONE)]
    # A broken nave made from readable bays, actual window gaps, and two open ends.
    for side in (-1, 1):
        x = side * 8.75
        for y in (-11.0, -4.0, 3.0, 10.0):
            pieces.append(box("ChoirButtress", (x + side * 0.55, y, 3.3), (1.15, 1.45, 6.6), CUT_STONE))
        for y in (-7.5, -0.5, 6.5):
            pieces.append(box("ChoirLowerBay", (x, y, 1.25), (0.72, 4.7, 2.5), FIELD_STONE))
            pieces.append(box("ChoirUpperBay", (x, y, 8.0), (0.72, 4.7, 2.7), FIELD_STONE))
    split_wall(pieces, -13.55, 18.0, 10.5, 5.0, 6.3, 0.75, FIELD_STONE)
    # Eastern end deliberately collapsed into walkable fragments.
    pieces.extend([
        box("ChoirBrokenPier", (-6.6, 13.2, 3.8), (2.0, 1.4, 7.6), FIELD_STONE, (0.04, 0.08, -0.03)),
        box("ChoirBrokenPier", (6.4, 13.0, 2.7), (2.2, 1.5, 5.4), FIELD_STONE, (-0.02, -0.09, 0.05)),
        box("ChoirFallenLintel", (1.4, 13.1, 1.05), (7.8, 1.2, 1.4), CUT_STONE, (0.15, 0.06, 0.22)),
        box("ChoirAltar", (0, 9.5, 1.35), (5.2, 2.3, 2.7), CUT_STONE),
    ])
    for y in (-8.0, -3.5, 1.0, 5.5):
        pieces.append(box("ChoirBench", (-3.0, y, 0.8), (4.6, 0.9, 0.9), OAK))
        pieces.append(box("ChoirBench", (3.0, y, 0.8), (4.6, 0.9, 0.9), OAK))
    return join_objects(pieces, "ShatteredChoir")


clear_scene()
build_beacon()
build_shelter()
build_ruin()

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
os.makedirs(os.path.dirname(BLEND_SOURCE), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_SOURCE)
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_yup=True,
)
print(f"STORMBREAK_ENVIRONMENT_EXPORT|{OUTPUT}")
