import math
import os

import bpy


OUTPUT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "assets", "world", "eastern_marches_environment_kit_v1.glb"
))
BLEND_SOURCE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "blender", "world", "environment", "eastern_marches_environment_kit_v1.blend"
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


LIMESTONE = material("Marcher pale limestone", (0.61, 0.56, 0.43))
WARM_STONE = material("Marcher warm cut stone", (0.48, 0.39, 0.27))
BASALT = material("Marcher charcoal basalt", (0.42, 0.39, 0.36))
CINDER_STONE = material("Cinderwatch sunwashed basalt", (0.53, 0.44, 0.33))
PLASTER = material("Marcher warm plaster", (0.72, 0.58, 0.36))
TERRACOTTA = material("Marcher terracotta tile", (0.46, 0.16, 0.075))
OAK = material("Marcher dark oak", (0.23, 0.125, 0.055), 0.98)
CANVAS = material("Marcher striped canvas", (0.63, 0.37, 0.10), 0.99)
BRONZE = material("Marcher aged bronze", (0.29, 0.21, 0.08), 0.72, 0.56)
EMBER = material("Marcher beacon ember", (0.90, 0.23, 0.035), 0.48)


def bevel_object(obj, width=0.07, segments=2):
    modifier = obj.modifiers.new("Worn edge", "BEVEL")
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


def cylinder(name, location, radius, depth, mat, vertices=12, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_object(obj, 0.07)
    return obj


def cone(name, location, radius1, radius2, depth, mat, vertices=10, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius1, radius2=radius2, depth=depth,
        location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_object(obj, 0.06)
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


def hipped_roof(pieces, center, width, depth, base_z, rise, mat):
    x, y = center
    roof = cone(
        "JoinedHippedRoof", (x, y, base_z + rise * 0.5),
        1.0, 0.025, rise, mat, vertices=4,
        rotation=(0.0, 0.0, math.pi * 0.25),
    )
    roof.scale = (width * 0.72, depth * 0.72, 1.0)
    bpy.context.view_layer.objects.active = roof
    roof.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    roof.select_set(False)
    pieces.append(roof)


def split_front_wall(pieces, center_x, y, width, height, opening_width, opening_height, thickness, mat):
    side_width = (width - opening_width) * 0.5
    pieces.append(box("OpeningPier", (center_x - (opening_width + side_width) * 0.5, y, height * 0.5),
                      (side_width, thickness, height), mat))
    pieces.append(box("OpeningPier", (center_x + (opening_width + side_width) * 0.5, y, height * 0.5),
                      (side_width, thickness, height), mat))
    pieces.append(box("OpeningLintel", (center_x, y, opening_height + (height - opening_height) * 0.5),
                      (opening_width, thickness, height - opening_height), mat))


def battlements(pieces, center, length, axis, z, mat, spacing=3.2):
    count = max(2, int(length / spacing))
    for index in range(count + 1):
        offset = -length * 0.5 + length * float(index) / float(count)
        if axis == "x":
            location = (center[0] + offset, center[1], z)
            dims = (1.75, 1.35, 1.45)
        else:
            location = (center[0], center[1] + offset, z)
            dims = (1.35, 1.75, 1.45)
        pieces.append(box("GroundedMerlon", location, dims, mat, bevel=0.04))


def build_march_keep():
    pieces = [
        box("CourtyardThreshold", (0, 0, 0.22), (48.0, 42.0, 0.44), WARM_STONE),
        box("RearCurtain", (0, 21.0, 4.0), (48.0, 1.55, 8.0), LIMESTONE),
        box("WestCurtain", (-24.0, 0, 4.0), (1.55, 40.5, 8.0), LIMESTONE),
        box("EastCurtain", (24.0, 0, 4.0), (1.55, 40.5, 8.0), LIMESTONE),
        box("FrontCurtainLeft", (-15.5, -21.0, 4.0), (17.0, 1.55, 8.0), LIMESTONE),
        box("FrontCurtainRight", (15.5, -21.0, 4.0), (17.0, 1.55, 8.0), LIMESTONE),
        box("GateLintel", (0, -21.0, 7.1), (14.0, 1.55, 1.8), WARM_STONE),
    ]
    # Gate towers and their crenellations are connected to real masonry below.
    for x in (-8.7, 8.7):
        pieces.extend([
            cylinder("GateTower", (x, -20.2, 5.4), 4.6, 10.8, WARM_STONE, 12),
            cylinder("GateTowerCap", (x, -20.2, 10.95), 5.05, 0.55, LIMESTONE, 12),
        ])
        for merlon in range(8):
            angle = TAU * float(merlon) / 8.0
            pieces.append(box("TowerMerlon", (x + math.sin(angle) * 4.35, -20.2 + math.cos(angle) * 4.35, 11.8),
                              (1.15, 1.15, 1.45), LIMESTONE, (0.0, 0.0, -angle), 0.04))
    battlements(pieces, (0, 21.0), 46.0, "x", 8.75, LIMESTONE)
    battlements(pieces, (-24.0, 0), 39.0, "y", 8.75, LIMESTONE)
    battlements(pieces, (24.0, 0), 39.0, "y", 8.75, LIMESTONE)

    # A compact inner keep with a genuine open door and connected roof walk.
    keep_y = 8.0
    pieces.extend([
        box("KeepFloor", (0, keep_y, 0.35), (20.0, 15.5, 0.70), WARM_STONE),
        box("KeepRear", (0, keep_y + 7.35, 7.0), (20.0, 0.9, 14.0), WARM_STONE),
        box("KeepWest", (-9.55, keep_y, 7.0), (0.9, 14.0, 14.0), WARM_STONE),
        box("KeepEast", (9.55, keep_y, 7.0), (0.9, 14.0, 14.0), WARM_STONE),
    ])
    split_front_wall(pieces, 0, keep_y - 7.35, 20.0, 14.0, 4.6, 5.1, 0.9, WARM_STONE)
    pieces.append(box("KeepRoofWalk", (0, keep_y, 14.25), (21.0, 16.5, 0.65), LIMESTONE))
    battlements(pieces, (0, keep_y - 7.8), 20.0, "x", 15.25, LIMESTONE, 3.0)
    battlements(pieces, (0, keep_y + 7.8), 20.0, "x", 15.25, LIMESTONE, 3.0)
    battlements(pieces, (-10.1, keep_y), 14.5, "y", 15.25, LIMESTONE, 3.0)
    battlements(pieces, (10.1, keep_y), 14.5, "y", 15.25, LIMESTONE, 3.0)
    # Interior guard tables and exterior hitching rails make the ward usable.
    pieces.extend([
        box("GuardTable", (-4.0, -5.0, 1.25), (4.8, 2.0, 0.34), OAK),
        box("SupplyTable", (5.0, -7.0, 1.25), (4.2, 2.0, 0.34), OAK),
        box("HitchRail", (-15.0, -14.0, 1.25), (8.0, 0.35, 0.35), OAK),
        box("HitchPost", (-18.5, -14.0, 1.1), (0.40, 0.40, 2.2), OAK),
        box("HitchPost", (-11.5, -14.0, 1.1), (0.40, 0.40, 2.2), OAK),
    ])
    return join_objects(pieces, "MarchKeepFortification")


def build_caravanserai():
    pieces = [box("CaravanCourt", (0, 0, 0.22), (42.0, 34.0, 0.44), WARM_STONE)]
    # Three joined wings make an open, legible courtyard instead of a copied house.
    pieces.extend([
        box("RearWing", (0, 12.8, 4.8), (40.0, 7.6, 9.6), PLASTER),
        box("WestWing", (-16.0, 0.5, 4.0), (8.0, 17.5, 8.0), PLASTER),
        box("EastWing", (16.0, 0.5, 4.0), (8.0, 17.5, 8.0), PLASTER),
    ])
    hipped_roof(pieces, (0, 12.8), 42.0, 9.0, 9.6, 3.5, TERRACOTTA)
    hipped_roof(pieces, (-16.0, 0.5), 9.5, 19.0, 8.0, 3.0, TERRACOTTA)
    hipped_roof(pieces, (16.0, 0.5), 9.5, 19.0, 8.0, 3.0, TERRACOTTA)
    # A real open entrance arch assembled around the gap.
    pieces.extend([
        box("GatePier", (-5.7, -14.2, 3.5), (4.0, 1.4, 7.0), LIMESTONE),
        box("GatePier", (5.7, -14.2, 3.5), (4.0, 1.4, 7.0), LIMESTONE),
        box("GateLintel", (0, -14.2, 6.8), (7.4, 1.4, 1.4), LIMESTONE),
        box("GateTileCap", (0, -14.2, 7.8), (15.8, 2.5, 0.55), TERRACOTTA),
    ])
    # Shaded arcade, stable bays, troughs, cargo and merchant awnings.
    for x in (-11.0, -5.5, 0.0, 5.5, 11.0):
        pieces.append(box("ArcadePost", (x, 8.2, 2.25), (0.46, 0.46, 4.5), OAK))
    pieces.append(box("ArcadeBeam", (0, 8.2, 4.4), (25.0, 0.55, 0.55), OAK))
    for side in (-1, 1):
        x = side * 15.8
        for y in (-7.5, -1.5, 4.5):
            pieces.append(box("StableDivider", (x - side * 3.9, y, 1.8), (0.38, 5.0, 3.6), OAK))
    pieces.extend([
        box("WaterTrough", (-7.0, -6.0, 0.75), (6.5, 2.0, 1.5), WARM_STONE),
        box("CargoCrate", (7.2, -5.5, 1.0), (2.4, 2.2, 2.0), OAK),
        box("CargoCrate", (10.0, -4.2, 0.7), (1.8, 1.8, 1.4), OAK),
        box("CanvasAwning", (-10.0, 10.5, 5.4), (8.0, 4.0, 0.25), CANVAS, (0.08, 0.0, 0.0)),
    ])
    return join_objects(pieces, "DawnfordCaravanserai")


def build_windmill():
    pieces = []
    # Twelve wall panels leave a real road-facing door opening.
    panel_count = 12
    radius = 5.2
    for index in range(panel_count):
        if index == 6:
            continue
        angle = TAU * float(index) / float(panel_count)
        pieces.append(box("MillWallPanel", (math.sin(angle) * radius, math.cos(angle) * radius, 5.0),
                          (2.75, 0.72, 10.0), WARM_STONE, (0.0, 0.0, -angle)))
    pieces.extend([
        box("MillDoorLintel", (0, -5.0, 8.6), (4.0, 0.8, 2.8), LIMESTONE),
        cone("MillTileCap", (0, 0, 11.8), 7.0, 0.25, 4.0, TERRACOTTA, 16),
        cylinder("MillAxle", (0, -6.2, 12.0), 0.52, 3.0, BRONZE, 12, (math.pi * 0.5, 0.0, 0.0)),
    ])
    for blade in range(4):
        angle = math.pi * 0.25 + blade * math.pi * 0.5
        dx, dz = math.cos(angle), math.sin(angle)
        pieces.append(box("SailSpar", (dx * 5.0, -7.8, 12.0 + dz * 5.0),
                          (0.32, 0.32, 10.2), OAK, (0.0, angle, 0.0)))
        pieces.append(box("CanvasSail", (dx * 6.4, -7.95, 12.0 + dz * 6.4),
                          (2.1, 0.18, 5.4), CANVAS, (0.0, angle, 0.0)))
    pieces.extend([
        box("FlourLoadingTable", (-7.0, 1.0, 1.1), (4.5, 2.2, 0.34), OAK),
        cylinder("Millstone", (7.0, 1.5, 0.8), 2.2, 1.6, WARM_STONE, 14),
    ])
    return join_objects(pieces, "AmberfieldWindmill")


def build_granary():
    pieces = []
    for x in (-6.8, 6.8):
        for y in (-5.2, 5.2):
            pieces.append(cylinder("GranaryStonePier", (x, y, 1.35), 0.9, 2.7, WARM_STONE, 10))
    pieces.extend([
        box("GranaryFloor", (0, 0, 2.9), (17.0, 13.0, 0.65), OAK),
        box("GranaryRear", (0, 6.1, 7.2), (17.0, 0.75, 8.6), PLASTER),
        box("GranaryWest", (-8.1, 0, 7.2), (0.75, 11.5, 8.6), PLASTER),
        box("GranaryEast", (8.1, 0, 7.2), (0.75, 11.5, 8.6), PLASTER),
    ])
    split_front_wall(pieces, 0, -6.1, 17.0, 8.6, 5.0, 5.4, 0.75, PLASTER)
    hipped_roof(pieces, (0, 0), 19.0, 15.0, 11.5, 3.4, TERRACOTTA)
    # A broad loading ramp is a continuous walkable surface, not oversized stairs.
    pieces.append(box("LoadingRamp", (0, -10.0, 1.65), (6.0, 8.0, 0.55), OAK, (0.30, 0.0, 0.0)))
    for side in (-1, 1):
        pieces.append(box("RampRail", (side * 3.0, -10.0, 2.5), (0.26, 8.0, 0.32), OAK, (0.30, 0.0, 0.0)))
    pieces.extend([
        box("GrainSack", (-3.0, -1.5, 3.7), (1.4, 2.0, 1.2), CANVAS),
        box("GrainSack", (0.0, -1.0, 3.6), (1.4, 2.0, 1.2), CANVAS),
        box("GrainSack", (3.0, -1.5, 3.7), (1.4, 2.0, 1.2), CANVAS),
    ])
    return join_objects(pieces, "SaltwatchGranary")


def build_dawnford_arrival_set():
    """A compact caravan arrival vignette that leaves the realmroad open."""
    pieces = []
    # The wagon is parked on the shoulder, with believable wheels, shafts and
    # cargo instead of an oversized solid block beside the road.
    pieces.extend([
        box("ArrivalWagonBed", (0.0, 0.0, 1.65), (6.8, 3.3, 0.48), OAK),
        box("ArrivalWagonFront", (0.0, -1.5, 2.25), (6.8, 0.28, 1.55), OAK),
        box("ArrivalWagonRear", (0.0, 1.5, 2.25), (6.8, 0.28, 1.55), OAK),
        box("ArrivalShaftLeft", (-1.35, -4.7, 1.15), (0.24, 6.6, 0.24), OAK, (0.06, 0.0, 0.0)),
        box("ArrivalShaftRight", (1.35, -4.7, 1.15), (0.24, 6.6, 0.24), OAK, (0.06, 0.0, 0.0)),
        box("ArrivalCanvasRoll", (-1.7, 0.0, 2.35), (2.4, 2.1, 1.05), CANVAS),
        box("ArrivalCargoChest", (1.8, 0.1, 2.20), (2.0, 1.8, 1.40), WARM_STONE),
    ])
    for x in (-3.0, 3.0):
        for y in (-1.05, 1.05):
            pieces.append(cylinder("ArrivalWagonWheel", (x, y, 1.15), 1.15, 0.34, OAK, 14,
                                   (0.0, math.pi * 0.5, 0.0)))
            pieces.append(cylinder("ArrivalWheelHub", (x, y, 1.15), 0.26, 0.48, BRONZE, 12,
                                   (0.0, math.pi * 0.5, 0.0)))
    # Customs stones frame a person-scale ledger table without becoming a
    # wall or another building silhouette.
    pieces.extend([
        box("ArrivalLedgerTable", (7.2, 0.2, 1.15), (4.2, 1.8, 0.30), OAK),
        box("ArrivalLedgerLegLeft", (5.55, 0.2, 0.58), (0.32, 1.35, 1.16), OAK),
        box("ArrivalLedgerLegRight", (8.85, 0.2, 0.58), (0.32, 1.35, 1.16), OAK),
        cylinder("ArrivalWaystone", (7.1, 4.0, 1.65), 0.72, 3.3, LIMESTONE, 8),
        box("ArrivalWaystoneCap", (7.1, 4.0, 3.35), (1.7, 1.15, 0.42), WARM_STONE),
        cylinder("ArrivalWaterJar", (10.0, 1.6, 0.85), 0.68, 1.7, TERRACOTTA, 12),
    ])
    return join_objects(pieces, "DawnfordArrivalSet")


def build_amberfield_field_set():
    """Field-edge tools and crop handling at player height, not a field wall."""
    pieces = []
    # An open timber gate gives the field a readable entrance. The central
    # opening remains six metres wide and therefore never blocks traversal.
    for x in (-5.0, 5.0):
        pieces.extend([
            box("FieldGateStoneFoot", (x, 0.0, 0.38), (1.2, 1.2, 0.76), WARM_STONE),
            box("FieldGatePost", (x, 0.0, 2.0), (0.42, 0.42, 4.0), OAK),
        ])
    pieces.extend([
        box("FieldGateLintel", (0.0, 0.0, 3.85), (10.4, 0.42, 0.42), OAK),
        box("FieldToolBench", (8.2, 2.5, 1.05), (4.0, 1.6, 0.30), OAK),
        box("FieldToolLegLeft", (6.65, 2.5, 0.53), (0.28, 1.2, 1.06), OAK),
        box("FieldToolLegRight", (9.75, 2.5, 0.53), (0.28, 1.2, 1.06), OAK),
        box("FieldRakeHead", (8.2, 1.6, 1.45), (2.4, 0.22, 0.22), BRONZE),
        box("FieldRakeHandle", (8.2, 3.3, 2.0), (0.20, 3.6, 0.20), OAK, (0.38, 0.0, 0.0)),
    ])
    # Irregular sheaf clusters communicate active grain fields without
    # repeating a row-pattern across the landscape.
    for index, (x, y, scale) in enumerate(((-7.8, 3.0, 1.0), (-9.4, 1.2, 0.82), (-6.2, 4.4, 0.72))):
        pieces.append(cone(f"GrainSheaf{index}", (x, y, 1.05 * scale),
                           0.95 * scale, 0.28 * scale, 2.1 * scale, CANVAS, 9))
        pieces.append(cylinder(f"SheafBinding{index}", (x, y, 1.05 * scale),
                               0.56 * scale, 0.16, OAK, 10))
    return join_objects(pieces, "AmberfieldFieldSet")


def build_march_keep_gate_approach():
    """Paired road furniture that announces the keep while preserving its gate."""
    pieces = []
    for x in (-8.0, 8.0):
        pieces.extend([
            box("GateApproachPlinth", (x, 0.0, 0.50), (3.2, 3.2, 1.0), WARM_STONE),
            cylinder("GateApproachColumn", (x, 0.0, 2.45), 0.78, 3.9, LIMESTONE, 10),
            cylinder("GateApproachBrazier", (x, 0.0, 4.45), 1.18, 0.42, BRONZE, 10),
            cylinder("GateApproachEmbers", (x, 0.0, 4.72), 0.78, 0.14, EMBER, 10),
        ])
    pieces.extend([
        box("GateNoticeBoard", (-12.0, 4.2, 2.15), (4.8, 0.34, 2.6), OAK),
        box("GateNoticePostLeft", (-13.6, 4.2, 1.25), (0.34, 0.34, 2.5), OAK),
        box("GateNoticePostRight", (-10.4, 4.2, 1.25), (0.34, 0.34, 2.5), OAK),
        box("GateGuardBench", (12.0, 4.0, 0.95), (4.8, 1.4, 0.30), OAK),
        box("GateBenchFootLeft", (10.2, 4.0, 0.48), (0.34, 1.0, 0.96), OAK),
        box("GateBenchFootRight", (13.8, 4.0, 0.48), (0.34, 1.0, 0.96), OAK),
    ])
    return join_objects(pieces, "MarchKeepGateApproach")


def build_saltwatch_work_yard():
    """Salt meadow work tables and drying racks with clear walk lanes."""
    pieces = []
    for rack_x in (-5.2, 5.2):
        for y in (-3.1, 3.1):
            pieces.append(box("SaltRackPost", (rack_x, y, 1.75), (0.36, 0.36, 3.5), OAK))
        pieces.extend([
            box("SaltRackBeam", (rack_x, 0.0, 3.35), (0.42, 6.6, 0.42), OAK),
            box("SaltDryingTray", (rack_x, 0.0, 1.65), (4.2, 5.4, 0.24), WARM_STONE),
        ])
    pieces.extend([
        box("SaltSortingTable", (0.0, 6.2, 1.15), (6.2, 2.2, 0.32), OAK),
        box("SaltTableFootLeft", (-2.45, 6.2, 0.58), (0.34, 1.7, 1.16), OAK),
        box("SaltTableFootRight", (2.45, 6.2, 0.58), (0.34, 1.7, 1.16), OAK),
        box("SaltBlockLarge", (-1.6, 6.2, 1.55), (1.7, 1.3, 0.48), LIMESTONE),
        box("SaltBlockSmall", (1.1, 6.2, 1.45), (1.2, 1.0, 0.34), LIMESTONE),
        cylinder("BrineJarLeft", (-8.4, 4.7, 0.95), 0.72, 1.9, TERRACOTTA, 12),
        cylinder("BrineJarRight", (-10.0, 4.0, 0.72), 0.56, 1.44, TERRACOTTA, 12),
    ])
    return join_objects(pieces, "SaltwatchWorkYard")


def build_cinderwatch_survey_set():
    """Compact expedition instruments for the survey camp below Embercrag."""
    pieces = []
    # A proper tripod/theodolite silhouette is readable from the approach.
    for angle in (0.0, TAU / 3.0, TAU * 2.0 / 3.0):
        x, y = math.cos(angle) * 1.55, math.sin(angle) * 1.55
        pieces.append(box("SurveyTripodLeg", (x * 0.55, y * 0.55, 1.55),
                          (0.22, 0.22, 3.5), OAK,
                          (math.sin(angle) * 0.30, -math.cos(angle) * 0.30, angle)))
    pieces.extend([
        cylinder("SurveyInstrumentPivot", (0.0, 0.0, 3.1), 0.62, 0.52, BRONZE, 12),
        cylinder("SurveyInstrumentScope", (0.0, 0.0, 3.35), 0.34, 2.6, BRONZE, 12,
                 (0.0, math.pi * 0.5, 0.0)),
        box("SurveyMapTable", (5.4, 0.8, 1.2), (4.8, 2.4, 0.32), OAK),
        box("SurveyMapLegLeft", (3.55, 0.8, 0.60), (0.34, 1.8, 1.20), OAK),
        box("SurveyMapLegRight", (7.25, 0.8, 0.60), (0.34, 1.8, 1.20), OAK),
        box("SurveyMapBoard", (5.4, 0.8, 1.42), (3.9, 1.7, 0.08), CANVAS),
        box("SurveyPack", (-4.3, 1.5, 0.82), (2.1, 1.6, 1.64), CANVAS),
        cylinder("SurveySampleJar", (8.4, 1.0, 0.78), 0.55, 1.56, TERRACOTTA, 12),
    ])
    for index, (x, y) in enumerate(((-5.6, -3.7), (-2.8, -5.0), (6.6, -4.0))):
        pieces.append(box(f"SurveyMarkerStake{index}", (x, y, 1.25), (0.20, 0.20, 2.5), OAK))
        pieces.append(box(f"SurveyMarkerFlag{index}", (x + 0.55, y, 2.05), (1.1, 0.08, 0.72), CANVAS))
    return join_objects(pieces, "CinderwatchSurveySet")


def build_cinderwatch_beacon():
    pieces = [
        cylinder("BeaconGroundPlinth", (0, 0, 0.65), 7.4, 1.3, BASALT, 12),
        cylinder("BeaconUpperPlinth", (0, 0, 1.55), 6.4, 0.7, WARM_STONE, 12),
    ]
    # Faceted wall panels with one absent panel form a true doorway.
    panel_count = 10
    radius = 5.0
    for index in range(panel_count):
        if index == 5:
            continue
        angle = TAU * float(index) / float(panel_count)
        pieces.append(box("BeaconWallPanel", (math.sin(angle) * radius, math.cos(angle) * radius, 7.0),
                          (3.25, 0.9, 10.5), CINDER_STONE, (0.0, 0.0, -angle)))
        # Pale bonded-stone piers catch the sun and articulate the dark drum
        # at player height. They are attached to the wall, not floating trim.
        joint_angle = angle + TAU / float(panel_count) * 0.5
        pieces.append(box("BeaconLimestonePier",
                          (math.sin(joint_angle) * 5.05, math.cos(joint_angle) * 5.05, 6.8),
                          (0.62, 0.72, 10.0), LIMESTONE, (0.0, 0.0, -joint_angle), 0.045))
    pieces.extend([
        box("BeaconDoorLintel", (0, -5.0, 10.2), (4.2, 0.9, 3.2), WARM_STONE),
        cylinder("BeaconLowerBond", (0, 0, 3.0), 5.48, 0.46, LIMESTONE, 12),
        cylinder("BeaconUpperBond", (0, 0, 10.7), 5.48, 0.52, LIMESTONE, 12),
        cylinder("BeaconCrown", (0, 0, 12.55), 6.2, 0.8, WARM_STONE, 12),
        cylinder("BeaconHearth", (0, 0, 13.25), 3.2, 0.55, BRONZE, 12),
    ])
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        pieces.append(box("BeaconCage", (math.sin(angle) * 2.75, math.cos(angle) * 2.75, 16.0),
                          (0.30, 0.30, 5.2), BRONZE))
        pieces.append(box("BeaconFuel", (math.sin(angle) * 1.2, math.cos(angle) * 1.2, 14.0),
                          (0.38, 3.2, 0.38), OAK, (0.0, 0.0, angle)))
    pieces.append(cylinder("BeaconEmberBed", (0, 0, 14.0), 2.0, 0.36, EMBER, 12))
    return join_objects(pieces, "CinderwatchBeacon")


def build_cinderwatch_signal_yard():
    pieces = []
    # A low crescent windbreak gives the exposed camp a human-scaled edge and
    # leaves a broad opening toward the beacon and approach track.
    for index in range(9):
        angle = math.radians(-112.0 + index * 28.0)
        radius = 11.2
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        height = 1.35 + (index % 3) * 0.18
        pieces.append(box("SignalYardWindbreak", (x, y, height * 0.5),
                          (4.6, 1.25, height), BASALT, (0.0, 0.0, angle + math.pi * 0.5), 0.12))

    # The survey shelter is a joined timber frame with a visibly pitched
    # canvas roof. Every beam terminates in another structural member.
    shelter_y = 2.0
    for x in (-4.6, 4.6):
        for y in (shelter_y - 3.6, shelter_y + 3.6):
            pieces.append(box("SignalShelterPost", (x, y, 2.35), (0.42, 0.42, 4.7), OAK))
    pieces.extend([
        box("SignalShelterFrontBeam", (0, shelter_y - 3.6, 4.55), (9.6, 0.48, 0.48), OAK),
        box("SignalShelterRearBeam", (0, shelter_y + 3.6, 4.55), (9.6, 0.48, 0.48), OAK),
        box("SignalShelterRidge", (0, shelter_y, 5.65), (0.42, 7.8, 0.42), OAK),
        box("SignalCanvasWest", (-2.45, shelter_y, 5.12), (5.5, 8.1, 0.20), CANVAS,
            (0.0, -0.20, 0.0), 0.025),
        box("SignalCanvasEast", (2.45, shelter_y, 5.12), (5.5, 8.1, 0.20), CANVAS,
            (0.0, 0.20, 0.0), 0.025),
        box("SurveyTable", (0, shelter_y + 0.3, 1.15), (5.8, 2.2, 0.32), OAK),
        box("SurveyTableWestLeg", (-2.3, shelter_y + 0.3, 0.58), (0.32, 1.7, 1.16), OAK),
        box("SurveyTableEastLeg", (2.3, shelter_y + 0.3, 0.58), (0.32, 1.7, 1.16), OAK),
        box("SignalSupplyChest", (-6.8, shelter_y + 1.6, 0.85), (2.8, 1.9, 1.7), WARM_STONE),
        cylinder("SignalWaterJar", (6.7, shelter_y + 1.8, 1.0), 0.82, 2.0, TERRACOTTA, 12),
    ])
    # A grounded signal basket provides a warm focal point without adding a
    # second tower or relying on emissive text/markers.
    pieces.extend([
        cylinder("YardSignalBase", (7.4, shelter_y - 5.8, 0.45), 1.55, 0.9, WARM_STONE, 12),
        cylinder("YardSignalBasket", (7.4, shelter_y - 5.8, 1.35), 1.05, 0.9, BRONZE, 10),
        cylinder("YardSignalEmbers", (7.4, shelter_y - 5.8, 1.82), 0.72, 0.16, EMBER, 10),
    ])
    return join_objects(pieces, "CinderwatchSignalYard")


def build_embercrag_crown():
    pieces = []
    # Broken columnar ring gives the dormant crater a distant readable crown.
    for index in range(22):
        angle = TAU * float(index) / 22.0
        radius = 22.0 + math.sin(index * 1.83) * 4.0
        height = 7.0 + (index * 7 % 11) * 1.25
        width = 2.4 + (index % 4) * 0.42
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        lean = (math.sin(index * 2.17) * 0.08, math.cos(index * 1.41) * 0.09, angle)
        pieces.append(cone("BasaltCraterColumn", (x, y, height * 0.5 - 1.8), width * 1.18, width * 0.78,
                           height + 3.6, BASALT, 7, lean))
    # Interior lava plug and fallen slabs prevent the center reading as an empty ring.
    pieces.append(cylinder("DormantCraterPlug", (0, 0, 0.55), 15.0, 1.1, BASALT, 16))
    for index in range(7):
        angle = index * 2.39996323
        pieces.append(box("FallenBasaltSlab", (math.cos(angle) * (8.0 + index), math.sin(angle) * (8.0 + index), 1.0),
                          (5.0 + index * 0.35, 2.2, 1.4), BASALT, (0.12, -0.08, angle), 0.10))
    return join_objects(pieces, "EmbercragBasaltCrown")


TAU = math.pi * 2.0
clear_scene()
build_march_keep()
build_caravanserai()
build_windmill()
build_granary()
build_dawnford_arrival_set()
build_amberfield_field_set()
build_march_keep_gate_approach()
build_saltwatch_work_yard()
build_cinderwatch_beacon()
build_cinderwatch_signal_yard()
build_cinderwatch_survey_set()
build_embercrag_crown()

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
print(f"EASTERN_MARCHES_ENVIRONMENT_EXPORT|{OUTPUT}")
