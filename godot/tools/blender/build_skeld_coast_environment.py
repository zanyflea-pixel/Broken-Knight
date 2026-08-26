import math
import os

import bpy


OUTPUT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "assets", "world", "skeld_coast_environment_kit_v1.glb"
))
BLEND_SOURCE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "blender", "world", "environment", "skeld_coast_environment_kit_v1.blend"
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


SEA_STONE = material("Skeld sea stone", (0.34, 0.39, 0.40))
CUT_STONE = material("Skeld pale cut stone", (0.57, 0.59, 0.56))
TARRED_TIMBER = material("Skeld tarred timber", (0.16, 0.105, 0.065), 0.98)
WEATHERED_OAK = material("Skeld weathered oak", (0.32, 0.21, 0.115), 0.98)
SLATE = material("Skeld blue slate", (0.16, 0.22, 0.24))
IRON = material("Skeld forged iron", (0.08, 0.10, 0.11), 0.70, 0.72)
LANTERN = material("Skeld lighthouse lantern", (0.86, 0.42, 0.08), 0.42)
BONE = material("Skeld whalebone", (0.68, 0.64, 0.52))
HULL = material("Skeld tarred boat hull", (0.105, 0.16, 0.17), 0.91)
SAIL_CANVAS = material("Skeld sail canvas", (0.62, 0.57, 0.43), 0.99)
ROPE = material("Skeld rope", (0.37, 0.27, 0.13), 1.0)


def bevel_object(obj, width=0.07, segments=2):
    modifier = obj.modifiers.new("Weathered edge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def box(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0), bevel=0.06):
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


def pitched_roof(pieces, center_y, width, depth, base_z, rise, mat, overhang=0.7):
    angle = math.atan2(rise, width * 0.5)
    slope = math.sqrt((width * 0.5) ** 2 + rise ** 2)
    pieces.append(box("RoofSlope", (-width * 0.25, center_y, base_z + rise * 0.5),
                      (slope * 0.53, depth + overhang, 0.34), mat, (0.0, -angle, 0.0)))
    pieces.append(box("RoofSlope", (width * 0.25, center_y, base_z + rise * 0.5),
                      (slope * 0.53, depth + overhang, 0.34), mat, (0.0, angle, 0.0)))


def build_lighthouse():
    pieces = [
        cylinder("LighthouseRockPlinth", (0, 0, 0.6), 6.8, 1.2, SEA_STONE, 12),
        cylinder("LighthouseLowerTower", (0, 0, 6.2), 4.55, 10.4, SEA_STONE, 12),
        cylinder("LighthouseUpperTower", (0, 0, 13.0), 3.75, 4.2, CUT_STONE, 12),
        cylinder("LanternGallery", (0, 0, 15.55), 4.7, 0.65, IRON, 16),
        cylinder("LanternFloor", (0, 0, 16.0), 3.25, 0.35, CUT_STONE, 16),
    ]
    # Deep door frame and narrow sea-facing window surrounds make the tower
    # read as architecture rather than a stacked cylinder.
    pieces.extend([
        box("DoorLeft", (-1.75, -4.36, 2.85), (1.25, 0.62, 4.6), CUT_STONE),
        box("DoorRight", (1.75, -4.36, 2.85), (1.25, 0.62, 4.6), CUT_STONE),
        box("DoorLintel", (0, -4.36, 5.55), (2.25, 0.62, 0.8), CUT_STONE),
    ])
    for level, angle in ((8.3, 0.0), (11.5, math.pi * 0.5), (13.9, math.pi)):
        x, y = math.sin(angle) * 3.95, math.cos(angle) * 3.95
        pieces.append(box("WindowSill", (x, y, level), (1.35, 0.42, 0.38), CUT_STONE,
                          (0.0, 0.0, -angle)))
        pieces.append(box("WindowHead", (x, y, level + 2.15), (1.35, 0.42, 0.38), CUT_STONE,
                          (0.0, 0.0, -angle)))
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        pieces.append(box("LanternPost", (math.sin(angle) * 2.8, math.cos(angle) * 2.8, 18.25),
                          (0.25, 0.25, 4.5), IRON))
    pieces.append(cylinder("LanternGlow", (0, 0, 17.25), 1.25, 2.15, LANTERN, 12))
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=3.9, radius2=0.25, depth=3.0, location=(0, 0, 20.0))
    roof = bpy.context.object
    roof.name = "LanternSlateCap"
    roof.data.materials.append(SLATE)
    pieces.append(roof)
    return join_objects(pieces, "CapeKeldLighthouse")


def build_dock():
    pieces = []
    # Local +Y points seaward. Individual planks, diagonal braces and a crane
    # give the pier a working silhouette while staying one efficient mesh.
    for row in range(22):
        y = -8.0 + row * 1.35
        pieces.append(box("PierPlank", (0, y, 4.2), (9.2, 1.15, 0.34), WEATHERED_OAK, bevel=0.035))
    for y in (-7.0, 0.0, 7.0, 14.0, 21.0):
        for x in (-4.1, 4.1):
            pieces.append(box("PierPile", (x, y, 1.9), (0.62, 0.62, 7.6), TARRED_TIMBER))
            pieces.append(box("PierBrace", (x * 0.55, y + 1.0, 2.5), (0.38, 5.1, 0.38), TARRED_TIMBER,
                              (0.48 if x < 0 else -0.48, 0.0, 0.0)))
    for y in (-5.5, 3.0, 11.5, 20.0):
        for x in (-5.3, 5.3):
            pieces.append(cylinder("MooringPost", (x, y, 5.1), 0.34, 2.7, TARRED_TIMBER, 10))
    pieces.extend([
        box("CraneMast", (3.0, 7.0, 8.1), (0.58, 0.58, 8.3), TARRED_TIMBER),
        box("CraneArm", (1.0, 7.0, 11.7), (5.0, 0.52, 0.52), TARRED_TIMBER, (0.0, -0.12, 0.0)),
        box("CraneIron", (-1.4, 7.0, 8.8), (0.12, 0.12, 5.7), IRON),
        box("FishCrate", (-2.6, 1.0, 5.0), (2.4, 1.7, 1.3), WEATHERED_OAK),
        box("NetRack", (2.7, -1.5, 6.3), (4.4, 0.42, 0.42), TARRED_TIMBER),
    ])
    return join_objects(pieces, "FrostharborDock")


def build_fishing_boat():
    # A real tapered hull mesh, not a scaled box. Five cross-sections form a
    # shallow clinker-style working boat with a visible keel and rising bow.
    rings = [
        (-10.0, 0.20, 1.25, -0.25),
        (-6.8, 2.15, 1.85, -1.25),
        (0.0, 3.05, 2.10, -1.65),
        (6.4, 2.55, 1.90, -1.10),
        (9.0, 0.65, 1.45, -0.30),
    ]
    vertices = []
    for y, half_width, gunwale_z, keel_z in rings:
        vertices.extend([
            (-half_width, y, gunwale_z),
            (0.0, y, keel_z),
            (half_width, y, gunwale_z),
        ])
    faces = []
    for index in range(len(rings) - 1):
        here = index * 3
        after = (index + 1) * 3
        faces.append((here, after, after + 1, here + 1))
        faces.append((here + 1, after + 1, after + 2, here + 2))
    faces.extend([(0, 1, 2), (12, 14, 13)])
    hull_mesh = bpy.data.meshes.new("SkeldFishingHullMesh")
    hull_mesh.from_pydata(vertices, [], faces)
    hull_mesh.update()
    hull = bpy.data.objects.new("TaperedClinkerHull", hull_mesh)
    bpy.context.collection.objects.link(hull)
    hull.data.materials.append(HULL)
    pieces = [hull]

    # Ribs, gunwales, central deck, rudder and practical cargo make the small
    # craft readable from dock and shore without excessive geometry.
    for y, half_width, gunwale_z, _keel_z in rings[1:-1]:
        pieces.append(box("BoatRib", (0, y, gunwale_z - 0.40),
                          (half_width * 1.82, 0.18, 0.22), WEATHERED_OAK, bevel=0.025))
    pieces.extend([
        box("PortGunwale", (-2.55, -0.2, 2.05), (0.30, 13.6, 0.28), WEATHERED_OAK),
        box("StarboardGunwale", (2.55, -0.2, 2.05), (0.30, 13.6, 0.28), WEATHERED_OAK),
        box("CenterDeck", (0, 3.5, 1.28), (4.4, 5.8, 0.28), WEATHERED_OAK),
        box("Rudder", (0, 9.25, 0.35), (0.30, 0.34, 3.0), WEATHERED_OAK, (0.12, 0.0, 0.0)),
        cylinder("BoatMast", (0, -1.2, 6.1), 0.24, 9.0, TARRED_TIMBER, 12),
        box("YardArm", (0, -1.2, 8.4), (7.4, 0.22, 0.22), TARRED_TIMBER, (0.0, 0.13, 0.0)),
        box("PortOar", (-4.2, 1.3, 1.45), (6.6, 0.18, 0.18), WEATHERED_OAK, (0.0, 0.15, -0.10)),
        box("StarboardOar", (4.2, -0.3, 1.45), (6.6, 0.18, 0.18), WEATHERED_OAK, (0.0, -0.15, 0.10)),
        box("FishCrate", (-1.2, 4.0, 1.80), (1.7, 1.5, 0.9), WEATHERED_OAK),
        box("NetBasket", (1.2, 4.1, 1.78), (1.2, 1.2, 0.75), ROPE),
    ])
    sail_mesh = bpy.data.meshes.new("SkeldFishingSailMesh")
    sail_mesh.from_pydata([
        (-0.15, -1.28, 9.75), (-0.15, -1.28, 3.10), (-4.9, -1.28, 8.15),
        (0.15, -1.16, 9.75), (0.15, -1.16, 3.10), (4.9, -1.16, 8.15),
    ], [], [(0, 1, 2), (3, 5, 4)])
    sail_mesh.update()
    sail = bpy.data.objects.new("WeatheredSplitSail", sail_mesh)
    bpy.context.collection.objects.link(sail)
    sail.data.materials.append(SAIL_CANVAS)
    pieces.append(sail)
    return join_objects(pieces, "SkeldFishingBoat")


def build_longhouse():
    pieces = [
        box("LonghouseStoneFloor", (0, 0, 0.28), (17.5, 25.0, 0.56), SEA_STONE),
        box("LonghouseRear", (0, 11.8, 4.0), (16.4, 0.72, 8.0), SEA_STONE),
    ]
    # Front has a true opening; side walls are divided by real narrow windows.
    pieces.extend([
        box("FrontLeft", (-5.5, -11.8, 3.9), (5.0, 0.72, 7.8), SEA_STONE),
        box("FrontRight", (5.5, -11.8, 3.9), (5.0, 0.72, 7.8), SEA_STONE),
        box("FrontLintel", (0, -11.8, 6.8), (6.0, 0.72, 2.0), CUT_STONE),
    ])
    for side in (-1, 1):
        x = side * 8.1
        for y in (-8.5, -2.8, 2.8, 8.5):
            pieces.append(box("SideWallLow", (x, y, 1.25), (0.72, 4.1, 2.5), SEA_STONE))
            pieces.append(box("SideWallHigh", (x, y, 6.8), (0.72, 4.1, 2.4), SEA_STONE))
    pitched_roof(pieces, 0, 18.0, 26.0, 7.9, 5.6, SLATE, 1.0)
    # Hearth, feast tables, benches, drying racks and loft supplies fill the interior.
    pieces.extend([
        box("CentralHearth", (0, 2.0, 0.85), (3.8, 5.2, 1.2), CUT_STONE),
        box("FeastTable", (-4.4, 1.0, 1.35), (2.7, 12.0, 0.35), WEATHERED_OAK),
        box("FeastTable", (4.4, 1.0, 1.35), (2.7, 12.0, 0.35), WEATHERED_OAK),
        box("Bench", (-6.4, 1.0, 0.78), (0.75, 12.0, 0.36), WEATHERED_OAK),
        box("Bench", (6.4, 1.0, 0.78), (0.75, 12.0, 0.36), WEATHERED_OAK),
        box("DryingRack", (0, 8.8, 4.5), (7.5, 0.48, 0.48), TARRED_TIMBER),
    ])
    return join_objects(pieces, "SkeldLonghouse")


def build_chapel():
    pieces = [box("ChapelFloor", (0, 0, 0.22), (16.0, 22.0, 0.44), CUT_STONE)]
    # Open west door, slit windows, broken east end and partial slate roof.
    pieces.extend([
        box("ChapelDoorLeft", (-5.4, -10.6, 4.0), (4.1, 0.72, 8.0), SEA_STONE),
        box("ChapelDoorRight", (5.4, -10.6, 4.0), (4.1, 0.72, 8.0), SEA_STONE),
        box("ChapelDoorLintel", (0, -10.6, 7.0), (6.7, 0.72, 2.0), CUT_STONE),
    ])
    for side in (-1, 1):
        x = side * 7.55
        for y in (-7.0, -1.5, 4.0):
            pieces.append(box("ChapelLowerBay", (x, y, 1.4), (0.72, 3.9, 2.8), SEA_STONE))
            pieces.append(box("ChapelUpperBay", (x, y, 7.1), (0.72, 3.9, 2.0), SEA_STONE))
            pieces.append(box("ChapelButtress", (x + side * 0.5, y + 2.1, 3.0), (1.1, 1.0, 6.0), CUT_STONE))
    pieces.extend([
        box("BrokenEastPier", (-5.8, 10.0, 3.4), (2.1, 1.25, 6.8), SEA_STONE, (0.03, 0.08, -0.04)),
        box("BrokenEastPier", (5.6, 9.8, 2.5), (2.2, 1.3, 5.0), SEA_STONE, (-0.04, -0.10, 0.05)),
        box("FallenLintel", (0.4, 10.0, 0.9), (7.4, 1.0, 1.2), CUT_STONE, (0.12, 0.05, 0.20)),
        box("StoneAltar", (0, 6.8, 1.2), (4.8, 2.0, 2.4), CUT_STONE),
    ])
    pitched_roof(pieces, -4.4, 17.0, 11.2, 8.0, 4.6, SLATE, 0.8)
    # Curved whalebone ribs arch over the exposed eastern choir.
    for side in (-1, 1):
        for index in range(5):
            angle = math.radians(18 + index * 13)
            pieces.append(box("WhaleboneRib", (side * (5.9 - index * 0.85), 6.0, 3.0 + index * 1.1),
                              (0.34, 0.34, 4.2), BONE, (0.0, side * angle, 0.0)))
    return join_objects(pieces, "WhaleboneChapel")


clear_scene()
build_lighthouse()
build_dock()
build_fishing_boat()
build_longhouse()
build_chapel()

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
print(f"SKELD_COAST_ENVIRONMENT_EXPORT|{OUTPUT}")
