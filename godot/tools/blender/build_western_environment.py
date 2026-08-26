import math
import os

import bpy


OUTPUT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "assets", "world", "western_environment_kit_v1.glb"
))
BLEND_SOURCE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "blender", "world", "environment", "western_environment_kit_v1.blend"
))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.92, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


STONE = material("Rainward weathered stone", (0.31, 0.33, 0.29))
STONE_LIGHT = material("Rainward cut stone", (0.48, 0.49, 0.42))
TIMBER = material("Rainward dark oak", (0.20, 0.12, 0.055), 0.98)
TIMBER_LIGHT = material("Rainward wet timber", (0.34, 0.22, 0.10), 0.96)
SLATE = material("Rainward moss slate", (0.16, 0.20, 0.17), 0.94)
COPPER = material("Rainward aged copper", (0.24, 0.31, 0.22), 0.62, 0.38)


def box(name, location, scale, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, location, radius, depth, mat, vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
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


def build_galehorn_watch():
    pieces = []
    # A broad stone base visually seats the tower into the ridge rather than
    # leaving four posts hovering on independently sampled terrain.
    pieces.append(cylinder("WatchStonePlinth", (0, 0, 0.55), 5.8, 1.1, STONE, 12))
    pieces.append(cylinder("WatchLowerDrum", (0, 0, 2.6), 4.5, 3.3, STONE, 12))
    # True doorway gap: split the front of the drum with flanking stone piers.
    pieces.append(box("WatchDoorPier", (-2.2, -4.05, 2.35), (1.6, 0.8, 3.1), STONE_LIGHT))
    pieces.append(box("WatchDoorPier", (2.2, -4.05, 2.35), (1.6, 0.8, 3.1), STONE_LIGHT))
    pieces.append(box("WatchDoorLintel", (0, -4.05, 4.4), (2.8, 0.8, 0.8), STONE_LIGHT))
    for x in (-3.45, 3.45):
        for y in (-3.45, 3.45):
            pieces.append(box("WatchTimberPost", (x, y, 10.0), (0.62, 0.62, 14.8), TIMBER))
    for z, size in ((5.4, 9.4), (10.2, 9.8), (15.1, 10.6)):
        pieces.append(box("WatchPlatform", (0, 0, z), (size, size, 0.58), TIMBER_LIGHT))
    for z in (7.7, 12.6):
        for side in (-1, 1):
            pieces.append(box("WatchCrossBrace", (side * 3.45, 0, z),
                              (0.34, 8.4, 0.42), TIMBER, (math.radians(side * 27), 0, 0)))
            pieces.append(box("WatchCrossBrace", (0, side * 3.45, z),
                              (8.4, 0.34, 0.42), TIMBER, (0, math.radians(-side * 27), 0)))
    for side in (-1, 1):
        pieces.append(box("WatchRail", (side * 4.8, 0, 16.15), (0.28, 10.0, 1.45), TIMBER))
        pieces.append(box("WatchRail", (0, side * 4.8, 16.15), (10.0, 0.28, 1.45), TIMBER))
    pitched_roof(pieces, "WatchSlateRoof", 0.0, 13.0, 12.0, 17.2, 4.4, SLATE)
    pieces.append(cylinder("WatchCopperFinial", (0, 0, 22.6), 0.22, 2.4, COPPER, 8))
    return join_objects(pieces, "GalehornWatch")


def split_wall_with_opening(pieces, y, width, height, opening_width, opening_height, thickness, mat):
    side_width = (width - opening_width) * 0.5
    pieces.append(box("AbbeyWallPier", (-(opening_width + side_width) * 0.5, y, height * 0.5),
                      (side_width, thickness, height), mat))
    pieces.append(box("AbbeyWallPier", ((opening_width + side_width) * 0.5, y, height * 0.5),
                      (side_width, thickness, height), mat))
    pieces.append(box("AbbeyWallLintel", (0, y, opening_height + (height - opening_height) * 0.5),
                      (opening_width, thickness, height - opening_height), mat))


def build_rainward_abbey():
    pieces = [box("AbbeyNaveFloor", (0, 0, 0.18), (18.0, 30.0, 0.36), STONE_LIGHT)]
    # The west end and transept are deliberately broken; broad physical gaps
    # create exploration routes instead of a solid decorative block.
    split_wall_with_opening(pieces, -14.6, 18.0, 10.5, 4.2, 5.3, 0.75, STONE)
    split_wall_with_opening(pieces, 14.6, 18.0, 11.8, 3.2, 7.0, 0.75, STONE)
    for side in (-1, 1):
        x = side * 8.55
        for y in (-11.0, -4.0, 4.0, 11.0):
            # Buttresses and wall bays, with actual open windows between bays.
            pieces.append(box("AbbeyButtress", (x + side * 0.55, y, 3.5), (1.15, 1.7, 7.0), STONE_LIGHT))
        for y in (-7.5, 0.0, 7.5):
            pieces.append(box("AbbeyLowerWall", (x, y, 1.2), (0.72, 5.0, 2.4), STONE))
            pieces.append(box("AbbeyUpperWall", (x, y, 8.3), (0.72, 5.0, 3.0), STONE))
    # One surviving square bell tower and one ruined stair tower make the ruin
    # readable from the road without a glowing fantasy marker.
    pieces.append(box("AbbeyBellTower", (-5.2, 9.0, 8.0), (7.2, 7.2, 16.0), STONE))
    for face_y in (5.35, 12.65):
        split_wall_with_opening(pieces, face_y, 5.8, 15.0, 1.4, 11.8, 0.42, STONE_LIGHT)
    for x in (-8.0, -2.4):
        pieces.append(box("AbbeyCrenel", (x, 9.0, 16.5), (1.2, 1.0, 1.8), STONE_LIGHT))
    pieces.append(box("AbbeyBrokenTower", (6.0, 9.5, 5.6), (6.0, 6.2, 11.2), STONE))
    pieces.append(box("AbbeyBrokenCrown", (6.8, 9.4, 11.8), (3.1, 3.4, 2.2), STONE_LIGHT, (0, 0.08, 0.06)))
    # Interior altar, benches and chapter table survive as useful silhouettes.
    pieces.append(box("AbbeyAltar", (0, 10.8, 1.4), (5.2, 2.2, 2.8), STONE_LIGHT))
    for y in (-8.0, -3.5, 1.0, 5.5):
        pieces.append(box("AbbeyBench", (-3.0, y, 0.85), (4.8, 1.0, 1.0), TIMBER_LIGHT))
        pieces.append(box("AbbeyBench", (3.0, y, 0.85), (4.8, 1.0, 1.0), TIMBER_LIGHT))
    return join_objects(pieces, "OldRainwardAbbey")


def build_rainward_waystation():
    pieces = [
        box("WaystationStoneFloor", (0, 0, 0.25), (13.0, 10.0, 0.5), STONE_LIGHT),
        box("WaystationRearWall", (0, 4.55, 3.5), (12.0, 0.7, 7.0), TIMBER_LIGHT),
        box("WaystationFrontPier", (-4.5, -4.55, 3.4), (3.0, 0.7, 6.8), TIMBER_LIGHT),
        box("WaystationFrontPier", (4.5, -4.55, 3.4), (3.0, 0.7, 6.8), TIMBER_LIGHT),
        box("WaystationDoorLintel", (0, -4.55, 6.0), (3.0, 0.7, 1.4), TIMBER),
    ]
    for side in (-1, 1):
        x = side * 5.65
        pieces.append(box("WaystationSideLow", (x, 0, 1.2), (0.7, 8.4, 2.4), TIMBER_LIGHT))
        pieces.append(box("WaystationSideHigh", (x, 0, 5.7), (0.7, 8.4, 2.0), TIMBER_LIGHT))
        pieces.append(box("WaystationWindowPost", (x, 0, 3.5), (0.7, 0.7, 2.5), TIMBER))
    pitched_roof(pieces, "WaystationSlateRoof", 0, 13.8, 11.5, 7.0, 3.8, SLATE)
    pieces.append(box("WaystationCounter", (0, 1.5, 1.6), (7.5, 2.0, 0.45), TIMBER))
    pieces.append(box("WaystationBench", (-3.8, 3.3, 0.9), (1.1, 5.0, 0.45), TIMBER_LIGHT))
    pieces.append(box("WaystationBench", (3.8, 3.3, 0.9), (1.1, 5.0, 0.45), TIMBER_LIGHT))
    pieces.append(cylinder("WaystationRainBell", (0, -5.4, 7.9), 0.48, 0.9, COPPER, 10))
    return join_objects(pieces, "RainwardWaystation")


clear_scene()
build_galehorn_watch()
build_rainward_abbey()
build_rainward_waystation()

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
print(f"WESTERN_ENVIRONMENT_EXPORT|{OUTPUT}")
