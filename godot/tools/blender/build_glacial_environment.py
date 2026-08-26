import math
import os
import random

import bpy
from mathutils import Vector


OUTPUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "world", "glacial_environment_kit_v1.glb")
)
BLEND_SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "blender", "world", "environment", "glacial_environment_kit_v1.blend")
)
random.seed(91827)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        pass


def material(name, color, roughness=0.88, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


ICE = material("Deep compressed blue ice", (0.20, 0.46, 0.58), 0.28)
ICE_LIGHT = material("Weathered pale ice", (0.56, 0.73, 0.78), 0.42)
SNOW = material("Wind packed snow", (0.78, 0.83, 0.82), 0.92)
STONE = material("Cold moraine stone", (0.25, 0.29, 0.30), 0.98)
STONE_LIGHT = material("Frosted moraine face", (0.43, 0.46, 0.45), 0.96)
BARK = material("Frozen deadwood bark", (0.19, 0.15, 0.11), 1.0)
BRASS = material("Weathered observatory brass", (0.43, 0.29, 0.08), 0.52, 0.62)
LENS = material("Frozen observatory lens", (0.12, 0.42, 0.58), 0.24, 0.08)
NEST_CHITIN = material("Rimecrawler shed chitin", (0.12, 0.22, 0.25), 0.88)
NEST_CHITIN_EDGE = material("Rimecrawler weathered shell", (0.38, 0.55, 0.57), 0.76)
NEST_EGG = material("Rimecrawler frost egg", (0.36, 0.66, 0.70), 0.36)


def custom_mesh(name, verts, faces, materials, face_materials=None):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    if face_materials:
        for poly, index in zip(mesh.polygons, face_materials):
            poly.material_index = index
    return obj


def build_ice_spire():
    segments = 9
    rings = [
        (0.0, 2.6, (0.0, 0.0)),
        (2.8, 2.25, (0.20, -0.14)),
        (6.1, 1.62, (-0.30, 0.18)),
        (9.4, 0.92, (0.15, 0.04)),
    ]
    verts = []
    for ring_index, (height, radius, drift) in enumerate(rings):
        for i in range(segments):
            angle = math.tau * i / segments
            jitter = 0.86 + 0.18 * math.sin(i * 2.31 + ring_index * 1.17)
            verts.append((
                drift[0] + math.cos(angle) * radius * jitter,
                drift[1] + math.sin(angle) * radius * jitter,
                height,
            ))
    tip = len(verts)
    verts.append((0.62, -0.34, 13.4))
    faces = []
    for r in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((r * segments + i, r * segments + j, (r + 1) * segments + j, (r + 1) * segments + i))
    for i in range(segments):
        faces.append(((len(rings) - 1) * segments + i, (len(rings) - 1) * segments + (i + 1) % segments, tip))
    faces.append(tuple(reversed(range(segments))))
    obj = custom_mesh("IceSpire", verts, faces, [ICE, ICE_LIGHT], [i % 3 == 0 for i in range(len(faces))])
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def add_ico(name, location, scale, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for vertex in obj.data.vertices:
        direction = vertex.co.normalized()
        vertex.co += direction * (0.08 * math.sin(vertex.index * 4.13))
    obj.data.materials.append(mat)
    return obj


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    return objects[0]


def build_moraine_cluster():
    pieces = []
    specs = [
        ((-2.8, 0.3, 1.1), (3.1, 2.1, 1.7)),
        ((1.2, 0.5, 1.4), (3.7, 2.6, 2.1)),
        ((3.7, -0.6, 0.9), (2.5, 1.8, 1.35)),
        ((-0.4, -2.1, 0.65), (2.4, 1.5, 1.15)),
        ((-4.7, -1.6, 0.52), (1.65, 1.15, 0.92)),
    ]
    for i, (location, scale) in enumerate(specs):
        pieces.append(add_ico("MorainePiece", location, scale, STONE if i % 2 == 0 else STONE_LIGHT))
    return join_objects(pieces, "MoraineCluster")


def cylinder_between(name, start, end, radius, mat, vertices=9):
    start_v, end_v = Vector(start), Vector(end)
    delta = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    obj.data.materials.append(mat)
    return obj


def build_frozen_deadfall():
    pieces = [
        cylinder_between("DeadfallTrunk", (-5.8, 0.0, 0.7), (5.5, 0.35, 1.25), 0.72, BARK, 11),
        cylinder_between("DeadfallBranch", (-1.2, 0.1, 1.0), (-3.9, 3.2, 2.1), 0.29, BARK, 8),
        cylinder_between("DeadfallBranch", (1.1, 0.2, 1.15), (3.6, -2.4, 2.7), 0.25, BARK, 8),
        cylinder_between("DeadfallBranch", (3.2, 0.3, 1.2), (5.0, 2.0, 1.95), 0.18, BARK, 7),
    ]
    return join_objects(pieces, "FrozenDeadfall")


def build_glacier_terminus():
    # Layered terminal face: lower compressed ice, a weathered upper band and
    # a wind-packed crown. The extra vertical row prevents the silhouette from
    # reading as one faceted boulder when seen from the river valley.
    x_steps = [-48, -43, -37, -30, -22, -13, -4, 6, 16, 25, 33, 40, 46, 50]
    front_y = [10.0, 5.7, 1.4, -2.8, -5.9, -7.8, -6.7, -8.4, -6.9, -4.0, -0.7, 3.2, 7.4, 11.0]
    heights = [4.0, 7.4, 12.0, 16.2, 19.5, 22.8, 24.8, 23.5, 21.9, 19.4, 15.8, 11.5, 7.0, 3.8]
    verts = []
    for x, y, h in zip(x_steps, front_y, heights):
        back_y = 23.0 + abs(x) * 0.17 + 1.6 * math.sin(x * 0.13)
        middle_y = y - 0.8 + 0.9 * math.sin(x * 0.19)
        verts.extend([
            (x, y, 0.0),
            (x, middle_y, h * 0.53),
            (x, y + 0.6 * math.sin(x * 0.27), h),
            (x, back_y, h + 2.2 + 0.8 * math.sin(x * 0.21)),
            (x, back_y, 0.8),
        ])
    faces = []
    mats = []
    for i in range(len(x_steps) - 1):
        a, b = i * 5, (i + 1) * 5
        faces.extend([
            (a, b, b + 1, a + 1),
            (a + 1, b + 1, b + 2, a + 2),
            (a + 2, b + 2, b + 3, a + 3),
            (a + 3, b + 3, b + 4, a + 4),
        ])
        mats.extend([0, 1 if i % 3 else 0, 2, 1])
    end = (len(x_steps) - 1) * 5
    faces.extend([(0, 1, 2, 3, 4), (end, end + 4, end + 3, end + 2, end + 1)])
    mats.extend([1, 1])
    wall = custom_mesh("GlacierTerminus", verts, faces, [ICE, ICE_LIGHT, SNOW], mats)

    # Broken ice toes and shallow seracs obscure the mathematically exact
    # river join and give the face recognizable glacial structure.
    terminus_pieces = [wall]
    toe_specs = [
        ((-34, -4.8, 2.6), (5.8, 3.1, 3.5), ICE_LIGHT),
        ((-21, -8.1, 3.8), (4.8, 3.0, 5.2), ICE),
        ((-8, -9.0, 4.4), (5.2, 3.4, 6.2), ICE_LIGHT),
        ((7, -9.8, 4.0), (5.6, 3.1, 5.5), ICE),
        ((21, -7.0, 3.3), (4.7, 3.0, 4.6), ICE_LIGHT),
        ((34, -2.0, 2.5), (5.6, 3.2, 3.3), ICE),
    ]
    for index, (location, scale, mat) in enumerate(toe_specs):
        toe = add_ico("TerminalIceToe", location, scale, mat)
        toe.rotation_euler[2] = (index - 2) * 0.08
        terminus_pieces.append(toe)
    wall = join_objects(terminus_pieces, "GlacierTerminus")

    # Curved, narrowing tongue. Each cross-section has independent width,
    # center drift and crown height, removing the old triangular white wedge.
    tongue_sections = [
        (-6.0, 0.0, 22.0, 4.1),
        (-14.0, 1.0, 20.5, 3.5),
        (-24.0, -0.8, 17.2, 2.7),
        (-34.0, 0.7, 13.7, 1.9),
        (-43.0, -0.2, 10.0, 1.25),
        (-49.0, 0.1, 7.6, 0.72),
    ]
    tongue_verts = []
    for y, center_x, half_width, height in tongue_sections:
        tongue_verts.extend([
            (center_x - half_width, y, 0.15),
            (center_x - half_width * 0.96, y, height),
            (center_x + half_width * 0.96, y, height * 0.94),
            (center_x + half_width, y, 0.15),
        ])
    tongue_faces = []
    tongue_mats = []
    for i in range(len(tongue_sections) - 1):
        a, b = i * 4, (i + 1) * 4
        tongue_faces.extend([
            (a + 1, b + 1, b + 2, a + 2),
            (a, b, b + 1, a + 1),
            (a + 2, b + 2, b + 3, a + 3),
            (a, a + 3, b + 3, b),
        ])
        tongue_mats.extend([2 if i % 3 else 1, 0, 0, 0])
    tongue_faces.extend([(0, 1, 2, 3), ((len(tongue_sections)-1)*4, (len(tongue_sections)-1)*4+3, (len(tongue_sections)-1)*4+2, (len(tongue_sections)-1)*4+1)])
    tongue_mats.extend([0, 0])
    tongue = custom_mesh("GlacierTongue", tongue_verts, tongue_faces, [ICE, ICE_LIGHT, SNOW], tongue_mats)
    tongue_pieces = [tongue]
    for index, (location, scale) in enumerate([
        ((-8.0, -14.0, 3.5), (5.0, 3.0, 1.5)),
        ((6.5, -24.0, 2.6), (4.0, 3.8, 1.2)),
        ((-3.0, -35.0, 1.8), (3.6, 3.0, 0.9)),
    ]):
        tongue_pieces.append(add_ico("TonguePressureRidge", location, scale, SNOW if index != 1 else ICE_LIGHT))
    tongue = join_objects(tongue_pieces, "GlacierTongue")
    return wall, tongue


def add_box(name, location, scale, rotation_z, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=(0.0, 0.0, rotation_z))
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def add_box_rotated(name, location, scale, rotation, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_frostline_refuge():
    pieces = []
    # Stone plinth and floor are buried slightly so the building seats cleanly
    # into uneven terrain instead of hovering at the downhill corners.
    pieces.append(add_box("RefugeFloor", (0, 0, -0.2), (13.6, 17.2, 0.7), 0.0, STONE_LIGHT))
    pieces.append(add_box("RefugeRearWall", (0, 8.0, 3.0), (13.2, 1.0, 6.2), 0.0, STONE))
    # Front wall is deliberately split around a 3.2 m physical doorway.
    pieces.append(add_box("RefugeFrontPier", (-4.9, -8.0, 3.0), (3.5, 1.0, 6.2), 0.0, STONE))
    pieces.append(add_box("RefugeFrontPier", (4.9, -8.0, 3.0), (3.5, 1.0, 6.2), 0.0, STONE))
    pieces.append(add_box("RefugeDoorLintel", (0, -8.0, 5.65), (3.2, 1.0, 0.9), 0.0, STONE_LIGHT))
    # Side walls have true window gaps framed by lower, upper and end pieces.
    for side in (-1, 1):
        x = side * 6.1
        pieces.append(add_box("RefugeSideLower", (x, 0, 1.15), (1.0, 15.0, 2.3), 0.0, STONE))
        pieces.append(add_box("RefugeSideUpper", (x, 0, 5.15), (1.0, 15.0, 1.8), 0.0, STONE))
        pieces.append(add_box("RefugeWindowEnd", (x, -6.8, 3.4), (1.0, 2.2, 2.2), 0.0, STONE_LIGHT))
        pieces.append(add_box("RefugeWindowEnd", (x, 6.8, 3.4), (1.0, 2.2, 2.2), 0.0, STONE_LIGHT))
        pieces.append(add_box("RefugeWindowMullion", (x, 0, 3.4), (1.0, 0.75, 2.2), 0.0, BARK))

    roof_angle = math.radians(31.0)
    pieces.append(add_box_rotated("RefugeRoof", (-3.3, 0, 8.2), (7.8, 18.2, 0.55), (0, -roof_angle, 0), BARK))
    pieces.append(add_box_rotated("RefugeRoof", (3.3, 0, 8.2), (7.8, 18.2, 0.55), (0, roof_angle, 0), BARK))
    pieces.append(add_box_rotated("RefugeSnowRoof", (-3.3, 0, 8.53), (7.5, 17.9, 0.16), (0, -roof_angle, 0), SNOW))
    pieces.append(add_box_rotated("RefugeSnowRoof", (3.3, 0, 8.53), (7.5, 17.9, 0.16), (0, roof_angle, 0), SNOW))
    pieces.append(add_box("RefugeRidgeBeam", (0, 0, 10.1), (0.7, 18.4, 0.7), 0.0, BARK))
    pieces.append(add_box("RefugeChimney", (3.8, 3.2, 9.2), (1.5, 1.5, 5.1), 0.0, STONE))
    pieces.append(add_box("RefugeChimneyCap", (3.8, 3.2, 11.8), (2.1, 2.1, 0.45), 0.0, STONE_LIGHT))

    # Useful interior silhouettes: stove, expedition table, benches and racks.
    pieces.append(add_box("RefugeStove", (3.8, 3.2, 1.35), (2.2, 2.0, 2.7), 0.0, STONE))
    pieces.append(add_box("RefugeTableTop", (0, 1.0, 1.8), (5.4, 2.8, 0.35), 0.0, BARK))
    for x in (-2.2, 2.2):
        pieces.append(add_box("RefugeTableLeg", (x, 1.0, 0.85), (0.45, 0.45, 1.7), 0.0, BARK))
    for x in (-4.5, 4.5):
        pieces.append(add_box("RefugeBench", (x, 0.4, 1.0), (1.1, 7.0, 0.4), 0.0, BARK))
        pieces.append(add_box("RefugeBenchLeg", (x, -2.0, 0.45), (0.45, 0.55, 0.9), 0.0, BARK))
        pieces.append(add_box("RefugeBenchLeg", (x, 2.8, 0.45), (0.45, 0.55, 0.9), 0.0, BARK))
    pieces.append(add_box("RefugeSupplyRack", (-4.8, 5.9, 2.7), (1.0, 3.0, 5.0), 0.0, BARK))
    return join_objects(pieces, "FrostlineRefuge")


def build_survey_shelter():
    pieces = [
        add_box("SurveyShelterFloor", (0, 0, -0.15), (8.8, 10.8, 0.55), 0.0, STONE_LIGHT),
        add_box("SurveyShelterRear", (0, 5.0, 2.25), (8.8, 0.8, 4.8), 0.0, STONE),
        add_box("SurveyShelterSide", (-4.0, 0.5, 2.25), (0.8, 9.0, 4.8), 0.0, STONE),
        add_box("SurveyShelterSide", (4.0, 0.5, 2.25), (0.8, 9.0, 4.8), 0.0, STONE),
        add_box_rotated("SurveyShelterRoof", (0, 0.6, 5.45), (9.6, 11.8, 0.5), (math.radians(-7.0), 0, 0), BARK),
        add_box_rotated("SurveyShelterSnow", (0, 0.45, 5.72), (9.3, 11.4, 0.14), (math.radians(-7.0), 0, 0), SNOW),
        add_box("SurveyTable", (0, 1.1, 1.45), (4.2, 2.2, 0.35), 0.0, BARK),
        add_box("SurveySupplyChest", (2.6, 3.7, 0.85), (2.6, 1.5, 1.7), 0.0, BARK),
    ]
    for x in (-1.6, 1.6):
        pieces.append(add_box("SurveyTableLeg", (x, 1.1, 0.7), (0.35, 0.35, 1.4), 0.0, BARK))
    return join_objects(pieces, "SurveyShelter")


def build_frozen_observatory():
    pieces = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=14.0, depth=1.0, location=(0, 0, 0.45))
    base = bpy.context.object
    base.name = "ObservatoryFoundation"
    base.data.materials.append(STONE_LIGHT)
    pieces.append(base)

    # Broken, uneven curtain wall with several actual routes through it.
    wall_segments = 24
    missing = {0, 1, 6, 7, 13, 18, 19}
    for i in range(wall_segments):
        if i in missing:
            continue
        angle = math.tau * i / wall_segments
        height = 3.3 + ((i * 7) % 6) * 0.72
        radius = 12.3 + 0.45 * math.sin(i * 1.81)
        pieces.append(add_box(
            "BrokenObservatoryWall",
            (math.cos(angle) * radius, math.sin(angle) * radius, height * 0.5 + 0.8),
            (3.5, 1.05, height),
            angle + math.pi * 0.5,
            STONE if i % 3 else STONE_LIGHT,
        ))

    # One split tower remnant gives the ruin a long-distance silhouette.
    for location, scale in [((-6.5, 3.6, 5.4), (4.8, 4.4, 10.8)), ((-2.7, 6.0, 3.1), (2.8, 2.0, 6.2))]:
        pieces.append(add_box("ObservatoryTowerRemnant", location, scale, -0.12, STONE))
    pieces.append(add_box("BrokenTowerCrown", (-6.5, 3.6, 11.0), (5.5, 5.0, 0.65), -0.12, STONE_LIGHT))

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=2.4, depth=2.0, location=(2.4, -1.6, 1.45))
    plinth = bpy.context.object
    plinth.name = "ArmillaryPlinth"
    plinth.data.materials.append(STONE)
    pieces.append(plinth)
    for rotation in [(0.0, 0.0, 0.0), (math.pi * 0.5, 0.0, 0.38), (0.62, 0.48, -0.28)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=3.6, minor_radius=0.13, major_segments=32, minor_segments=7, location=(2.4, -1.6, 5.8), rotation=rotation)
        ring = bpy.context.object
        ring.name = "ArmillaryRing"
        ring.data.materials.append(BRASS)
        pieces.append(ring)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.95, location=(2.4, -1.6, 5.8))
    lens = bpy.context.object
    lens.name = "FrozenSkyLens"
    lens.scale = (0.68, 0.68, 1.35)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    lens.data.materials.append(LENS)
    pieces.append(lens)
    return join_objects(pieces, "FrozenObservatory")


def build_rimecrawler_nest():
    pieces = []
    # A broken moraine ring gives the lair a readable perimeter while two wide
    # gaps keep it traversable and prevent the encounter from becoming an
    # accidental arena wall.
    for index in range(13):
        if index in (0, 1, 7):
            continue
        angle = math.tau * index / 13.0
        radius = 6.2 + 0.55 * math.sin(index * 2.37)
        pieces.append(add_ico(
            "NestMoraine",
            (math.cos(angle) * radius, math.sin(angle) * radius, 0.44 + 0.12 * (index % 3)),
            (1.25 + 0.22 * (index % 4), 0.82 + 0.16 * (index % 3), 0.56 + 0.10 * (index % 2)),
            STONE if index % 2 else STONE_LIGHT,
        ))

    # Pods are low and asymmetrical rather than fantasy eggs standing upright.
    for index, (location, scale, yaw) in enumerate([
        ((-1.7, 0.8, 0.48), (0.68, 1.02, 0.48), -0.42),
        ((0.0, -0.5, 0.55), (0.78, 1.18, 0.55), 0.16),
        ((1.65, 1.0, 0.45), (0.64, 0.94, 0.44), 0.58),
        ((0.7, 2.25, 0.38), (0.54, 0.82, 0.38), -0.22),
    ]):
        pod = add_ico("RimecrawlerBroodPod", location, scale, NEST_EGG if index % 2 else NEST_CHITIN_EDGE)
        pod.rotation_euler[2] = yaw
        pieces.append(pod)

    # Shed plates and broken mandibles make the ecology legible even after the
    # resident crawlers have been defeated.
    for index, (x, y, yaw) in enumerate([
        (-3.4, -1.9, -0.28), (-2.2, 2.8, 0.56), (2.8, -2.2, -0.72),
        (3.6, 1.8, 0.32), (0.2, 3.8, -0.10),
    ]):
        plate = add_ico("ShedCarapacePlate", (x, y, 0.15), (0.95, 0.58, 0.14), NEST_CHITIN if index % 2 else NEST_CHITIN_EDGE)
        plate.rotation_euler[2] = yaw
        pieces.append(plate)
    for index, (x, y, lean, yaw) in enumerate([
        (-2.0, 4.2, -0.26, -0.16), (0.0, 4.8, 0.18, 0.04), (2.1, 4.0, 0.28, 0.22),
    ]):
        husk = add_ico(
            "StandingCarapaceHusk", (x, y, 1.65),
            (1.05 + index * 0.10, 0.34, 2.15 - index * 0.16),
            NEST_CHITIN if index != 1 else NEST_CHITIN_EDGE,
        )
        husk.rotation_euler = (lean, 0.0, yaw)
        pieces.append(husk)
    pieces.append(cylinder_between("BrokenCrawlerMandible", (-3.0, 0.1, 0.20), (-4.2, -0.5, 0.16), 0.10, NEST_CHITIN, 7))
    pieces.append(cylinder_between("BrokenCrawlerMandible", (2.5, 3.1, 0.22), (3.8, 3.5, 0.16), 0.09, NEST_CHITIN, 7))
    return join_objects(pieces, "RimecrawlerNest")


clear_scene()
build_ice_spire()
build_moraine_cluster()
build_frozen_deadfall()
build_glacier_terminus()
build_frostline_refuge()
build_survey_shelter()
build_frozen_observatory()
build_rimecrawler_nest()

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
print(f"GLACIAL_ENVIRONMENT_EXPORT|{OUTPUT}")
