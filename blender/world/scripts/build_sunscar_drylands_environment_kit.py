"""Build the authored Sunscar Drylands environment kit for Broken Knight.

The kit uses modeled branches, leaves, palm fronds, layered rock strata, and
architectural details. It deliberately avoids single-cone trees and blob
canopies so the dryland silhouette remains credible at player height.
"""

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BLEND_PATH = PROJECT_ROOT / "blender" / "world" / "environment" / "sunscar_drylands_environment_kit_v1.blend"
GLB_PATH = PROJECT_ROOT / "godot" / "assets" / "world" / "sunscar_drylands_environment_kit_v1.glb"
PREVIEW_PATH = PROJECT_ROOT / "godot" / "artifacts" / "sunscar_drylands_environment_kit_v1.png"


def material(name, color, roughness=0.92, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.use_backface_culling = False
    return mat


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def box_uv(obj, tile=1.4):
    if not hasattr(obj.data, "uv_layers"):
        return
    layer = obj.data.uv_layers.new(name="SunscarUV")
    for polygon in obj.data.polygons:
        normal = polygon.normal
        for loop_index in polygon.loop_indices:
            co = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            if abs(normal.z) >= abs(normal.x) and abs(normal.z) >= abs(normal.y):
                uv = (co.x / tile, co.y / tile)
            elif abs(normal.x) >= abs(normal.y):
                uv = (co.y / tile, co.z / tile)
            else:
                uv = (co.x / tile, co.z / tile)
            layer.data[loop_index].uv = uv


def cube(name, location, scale, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    obj.data.materials.append(mat)
    box_uv(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Worn edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def cylinder(name, location, radius, depth, mat, vertices=10, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    box_uv(obj, 0.8)
    return obj


def branch_between(name, start, end, start_radius, mat, vertices=8):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    length = delta.length
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=start_radius,
        radius2=max(start_radius * 0.54, 0.012),
        depth=length,
        location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    obj.rotation_mode = "XYZ"
    apply_transform(obj)
    obj.data.materials.append(mat)
    box_uv(obj, 0.7)
    return obj


def leaf(name, center, length, width, yaw, pitch, mat):
    forward = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
    side = Vector((-math.sin(yaw), math.cos(yaw), 0.0)).normalized()
    center_v = Vector(center)
    tip = center_v + forward * length * 0.55
    base = center_v - forward * length * 0.45
    fold = Vector((0.0, 0.0, width * 0.12))
    vertices = [
        tuple(base), tuple(center_v - side * width * 0.52 + fold), tuple(tip),
        tuple(center_v + side * width * 0.52 + fold), tuple(center_v),
    ]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def palm_frond(name, origin, yaw, length, droop, mat):
    origin_v = Vector(origin)
    forward = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    side = Vector((-math.sin(yaw), math.cos(yaw), 0.0))
    segments = 7
    spine = []
    for index in range(segments + 1):
        t = index / segments
        point = origin_v + forward * length * t + Vector((0.0, 0.0, 0.38 * math.sin(t * math.pi) - droop * t * t))
        spine.append(point)
    vertices = []
    faces = []
    # Narrow modeled rachis.
    for point_index, point in enumerate(spine):
        taper = 0.065 * (1.0 - point_index / (segments + 2))
        vertices.extend([tuple(point - side * taper), tuple(point + side * taper)])
    for index in range(segments):
        a = index * 2
        faces.append((a, a + 1, a + 3, a + 2))
    # Separate leaflets make the palm read as foliage, not a green paddle.
    for index in range(1, segments):
        t = index / segments
        point = spine[index]
        leaflet_length = length * (0.19 + 0.09 * math.sin(t * math.pi))
        for sign in (-1.0, 1.0):
            outward = side * sign
            leaflet_tip = point + outward * leaflet_length + forward * length * 0.035 - Vector((0.0, 0.0, droop * 0.10 * t))
            half = 0.035 + 0.020 * math.sin(t * math.pi)
            idx = len(vertices)
            vertices.extend([
                tuple(point - forward * half), tuple(point + forward * half),
                tuple(leaflet_tip + forward * half * 0.15), tuple(leaflet_tip - forward * half * 0.15),
            ])
            faces.append((idx, idx + 1, idx + 2, idx + 3))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def irregular_mass(name, location, scale, mat, seed, sides=11, rings=4):
    rng = random.Random(seed)
    vertices = []
    for ring_index in range(rings):
        t = ring_index / (rings - 1)
        radius = (1.02 - 0.22 * t) * (0.96 + 0.06 * math.sin(t * math.pi))
        z = t
        for index in range(sides):
            angle = math.tau * index / sides + 0.08 * ring_index
            broken = 1.0 + rng.uniform(-0.10, 0.10) + 0.07 * math.sin(index * 2.37 + seed)
            vertices.append((math.cos(angle) * radius * broken, math.sin(angle) * radius * broken, z + rng.uniform(-0.025, 0.025)))
    faces = [tuple(reversed(range(sides)))]
    for ring_index in range(rings - 1):
        lower = ring_index * sides
        upper = (ring_index + 1) * sides
        for index in range(sides):
            nxt = (index + 1) % sides
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    faces.append(tuple(range((rings - 1) * sides, rings * sides)))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.scale = scale
    apply_transform(obj)
    obj.data.materials.append(mat)
    box_uv(obj, 1.8)
    bevel = obj.modifiers.new("Wind rounded edges", "BEVEL")
    bevel.width = 0.025
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def join_asset(name, parts, display_location, role):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    result["biome_id"] = "semi_arid_drylands"
    result["visual_role"] = role
    result.location = display_location
    return result


def build_acacia(bark, twig, leaves_dark, leaves_light):
    rng = random.Random(1201)
    parts = []
    trunk_top = (0.0, 0.0, 3.5)
    parts.append(branch_between("Acacia trunk", (0.0, 0.0, 0.0), trunk_top, 0.32, bark, 10))
    branch_tips = []
    for index in range(9):
        yaw = math.tau * index / 9.0 + 0.24 * math.sin(index)
        start = Vector(trunk_top) + Vector((0.0, 0.0, -0.22 + 0.11 * (index % 3)))
        elbow = start + Vector((math.cos(yaw) * 1.25, math.sin(yaw) * 1.25, 0.55 + 0.16 * (index % 2)))
        tip = elbow + Vector((math.cos(yaw + 0.20 * math.sin(index)) * 1.45, math.sin(yaw + 0.20 * math.sin(index)) * 1.45, 0.10 - 0.12 * (index % 3)))
        parts.append(branch_between(f"Acacia bough {index}a", start, elbow, 0.18, bark, 8))
        parts.append(branch_between(f"Acacia bough {index}b", elbow, tip, 0.11, twig, 7))
        branch_tips.append(tip)
        for fork in (-1.0, 1.0):
            fork_yaw = yaw + fork * (0.34 + 0.06 * (index % 2))
            fork_tip = tip + Vector((math.cos(fork_yaw) * 0.72, math.sin(fork_yaw) * 0.72, 0.14 + 0.08 * fork))
            parts.append(branch_between(f"Acacia fork {index} {fork}", tip - Vector((math.cos(yaw) * 0.35, math.sin(yaw) * 0.35, 0.0)), fork_tip, 0.055, twig, 6))
            branch_tips.append(fork_tip)
    for tip_index, tip in enumerate(branch_tips):
        for leaf_index in range(5):
            yaw = tip_index * 1.73 + leaf_index * 1.17
            center = tip + Vector((math.cos(yaw) * 0.22, math.sin(yaw) * 0.22, rng.uniform(-0.12, 0.15)))
            parts.append(leaf(f"Acacia leaf {tip_index}-{leaf_index}", center, 0.52, 0.18, yaw, rng.uniform(-0.20, 0.24), leaves_light if (tip_index + leaf_index) % 4 == 0 else leaves_dark))
    return join_asset("DryAcaciaCluster", parts, (-18.0, 0.0, 0.0), "modeled dryland acacia with individual branches and leaves")


def build_palms(bark, bark_light, palm_dark, palm_light, dates):
    parts = []
    for palm_index, (x, y, height, lean) in enumerate(((-1.4, 0.2, 5.2, -0.12), (1.1, -0.5, 4.4, 0.10), (0.2, 1.25, 3.7, 0.04))):
        base = Vector((x, y, 0.0))
        top = Vector((x + lean * height, y + 0.04 * palm_index, height))
        segments = 9
        for segment in range(segments):
            t0 = segment / segments
            t1 = (segment + 1) / segments
            start = base.lerp(top, t0)
            end = base.lerp(top, t1)
            radius = (0.23 - 0.085 * t0) * (1.0 + 0.08 * math.sin(segment * 2.2))
            parts.append(branch_between(f"Palm {palm_index} trunk {segment}", start, end, radius, bark_light if segment % 3 == 0 else bark, 9))
        for frond_index in range(12):
            yaw = math.tau * frond_index / 12.0 + 0.32 * palm_index
            parts.append(palm_frond(f"Palm {palm_index} frond {frond_index}", top, yaw, 2.4 + 0.18 * (frond_index % 3), 0.72 + 0.10 * (frond_index % 2), palm_light if frond_index % 4 == 0 else palm_dark))
        for cluster_index in range(3):
            yaw = 1.1 + cluster_index * 2.05 + palm_index * 0.4
            cluster_center = top + Vector((math.cos(yaw) * 0.32, math.sin(yaw) * 0.32, -0.48))
            for date_index in range(7):
                angle = date_index * 2.399963
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.075, location=cluster_center + Vector((math.cos(angle) * 0.16, math.sin(angle) * 0.13, -0.05 * (date_index % 3))))
                fruit = bpy.context.object
                fruit.name = f"Palm date {palm_index}-{cluster_index}-{date_index}"
                fruit.scale.z = 1.35
                apply_transform(fruit)
                fruit.data.materials.append(dates)
                parts.append(fruit)
    return join_asset("DatePalmCluster", parts, (-6.0, 0.0, 0.0), "three modeled oasis palms with individual fronds and fruit")


def build_scrub(twig, leaf_green, leaf_sage, flower):
    rng = random.Random(1409)
    parts = []
    for shrub in range(7):
        angle = shrub * 2.399963
        base = Vector((math.cos(angle) * (0.6 + 0.16 * (shrub % 3)), math.sin(angle) * (0.5 + 0.12 * (shrub % 2)), 0.0))
        for stem in range(6):
            yaw = angle + stem * 0.78 + rng.uniform(-0.24, 0.24)
            tip = base + Vector((math.cos(yaw) * rng.uniform(0.30, 0.75), math.sin(yaw) * rng.uniform(0.30, 0.75), rng.uniform(0.45, 1.25)))
            parts.append(branch_between(f"Scrub stem {shrub}-{stem}", base, tip, 0.035 + 0.012 * (stem % 2), twig, 6))
            for leaf_index in range(3):
                center = base.lerp(tip, 0.45 + 0.20 * leaf_index)
                parts.append(leaf(f"Scrub leaf {shrub}-{stem}-{leaf_index}", center, 0.20, 0.065, yaw + math.pi * 0.5 * (leaf_index % 2), -0.12, leaf_sage if (shrub + stem) % 3 == 0 else leaf_green))
            if stem % 3 == 0:
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.055, location=tip)
                blossom = bpy.context.object
                blossom.name = f"Desert bloom {shrub}-{stem}"
                blossom.data.materials.append(flower)
                parts.append(blossom)
    return join_asset("DesertScrubCluster", parts, (6.0, 0.0, 0.0), "flowering sage and thorn scrub with modeled stems")


def build_mesa(sandstone, sandstone_light, sandstone_dark):
    parts = []
    parts.append(irregular_mass("Mesa lower plinth", (0.0, 0.0, 0.0), (4.9, 3.5, 1.5), sandstone_dark, 2101, 13, 4))
    parts.append(irregular_mass("Mesa middle wall", (-0.25, 0.1, 1.35), (4.15, 3.05, 1.55), sandstone, 2102, 12, 4))
    parts.append(irregular_mass("Mesa upper crown", (0.2, -0.05, 2.76), (3.25, 2.45, 1.35), sandstone_light, 2103, 11, 4))
    # Thin, irregular strata break up the cliff face at middle distance.
    for band_index in range(8):
        z = 0.55 + band_index * 0.47
        radius_x = 4.65 - band_index * 0.18
        radius_y = 3.30 - band_index * 0.14
        bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.025 + 0.008 * (band_index % 2), major_segments=20, minor_segments=4, location=(0.0, 0.0, z))
        band = bpy.context.object
        band.name = f"Mesa weathering stratum {band_index}"
        band.scale = (radius_x, radius_y, 1.0)
        apply_transform(band)
        band.data.materials.append(sandstone_light if band_index % 3 else sandstone_dark)
        parts.append(band)
    for toe_index in range(9):
        angle = toe_index * 2.399963
        parts.append(irregular_mass(f"Mesa talus {toe_index}", (math.cos(angle) * 4.5, math.sin(angle) * 3.1, 0.0), (0.50 + 0.08 * (toe_index % 3), 0.38, 0.42), sandstone_dark, 2150 + toe_index, 7, 3))
    return join_asset("SunspireMesa", parts, (19.0, 0.0, 0.0), "layered sandstone landmark with talus and weathering strata")


def build_source_formation(sandstone, dark, wet):
    parts = []
    for index, spec in enumerate(((-2.0, 0.3, 2.8, 0.8), (-0.8, 0.0, 4.1, 1.0), (0.6, 0.15, 3.5, 0.9), (1.8, -0.1, 2.5, 0.72))):
        x, y, height, width = spec
        parts.append(irregular_mass(f"Source buttress {index}", (x, y, 0.0), (width, 0.78 + 0.12 * index, height), sandstone, 2300 + index, 8, 4))
    parts.append(cube("Wet spring cleft", (0.0, -0.78, 1.25), (0.52, 0.08, 1.28), wet, rotation=(0.0, 0.0, 0.08), bevel=0.04))
    for index in range(7):
        angle = index * 2.399963
        parts.append(irregular_mass(f"Source fallstone {index}", (math.cos(angle) * (1.5 + 0.18 * (index % 3)), -1.3 + math.sin(angle) * 0.55, 0.0), (0.40, 0.34, 0.32), dark, 2340 + index, 7, 3))
    return join_asset("SunrunSourceFormation", parts, (31.0, 0.0, 0.0), "sandstone headwater cleft and waterfall buttresses")


def build_mine(stone, stone_light, timber, iron, darkness):
    parts = []
    # Recessed black opening first, then a cut-stone and timber portal around it.
    parts.append(cube("Mine darkness", (0.0, 0.42, 1.8), (1.65, 0.22, 1.82), darkness, bevel=0.08))
    for side in (-1.0, 1.0):
        for course in range(4):
            parts.append(cube(f"Mine jamb {side} {course}", (side * (1.85 - 0.10 * course), 0.0, 0.48 + course * 0.62), (0.46, 0.68, 0.31), stone_light if course % 2 else stone, rotation=(0.0, side * 0.05, side * 0.025), bevel=0.055))
    wedge_positions = [(-1.30, 2.95, -0.48), (-0.72, 3.34, -0.28), (0.0, 3.52, 0.0), (0.72, 3.34, 0.28), (1.30, 2.95, 0.48)]
    for index, (x, z, tilt) in enumerate(wedge_positions):
        parts.append(cube(f"Mine arch voussoir {index}", (x, 0.0, z), (0.46, 0.70, 0.30), stone_light, rotation=(0.0, tilt, 0.0), bevel=0.05))
    parts.append(cube("Mine timber left", (-1.38, -0.76, 1.65), (0.14, 0.14, 1.65), timber, bevel=0.025))
    parts.append(cube("Mine timber right", (1.38, -0.76, 1.65), (0.14, 0.14, 1.65), timber, bevel=0.025))
    parts.append(cube("Mine timber lintel", (0.0, -0.76, 3.15), (1.52, 0.14, 0.16), timber, bevel=0.025))
    # Rails and sleepers lead into the darkness and visually explain entry.
    for rail_x in (-0.48, 0.48):
        parts.append(cube(f"Mine rail {rail_x}", (rail_x, -2.0, 0.09), (0.055, 2.45, 0.055), iron, bevel=0.01))
    for sleeper_index in range(7):
        parts.append(cube(f"Mine sleeper {sleeper_index}", (0.0, -0.25 - sleeper_index * 0.62, 0.04), (0.82, 0.09, 0.055), timber, bevel=0.015))
    parts.append(cube("Ore cart body", (1.95, -2.0, 0.62), (0.68, 0.92, 0.48), iron, rotation=(0.0, 0.0, -0.08), bevel=0.06))
    for wheel_index, (x, y) in enumerate(((1.30, -1.55), (2.60, -1.55), (1.30, -2.45), (2.60, -2.45))):
        parts.append(cylinder(f"Ore cart wheel {wheel_index}", (x, y, 0.30), 0.24, 0.12, iron, 10, rotation=(math.pi * 0.5, 0.0, 0.0)))
    return join_asset("CopperShelfMineEntrance", parts, (43.0, 0.0, 0.0), "recessed mine portal with rails, cart, stone arch, and timber frame")


def build_waystation(stucco, sandstone, timber, cloth, ceramic):
    parts = [
        cube("Waystation body", (0.0, 0.0, 1.45), (2.45, 1.72, 1.45), stucco, bevel=0.08),
        cube("Waystation stone plinth", (0.0, 0.0, 0.27), (2.62, 1.86, 0.28), sandstone, bevel=0.055),
        cube("Waystation flat roof", (0.0, 0.0, 3.08), (2.72, 1.96, 0.18), sandstone, bevel=0.05),
        cube("Waystation doorway", (0.0, -1.73, 1.28), (0.62, 0.08, 1.28), timber, bevel=0.035),
    ]
    for beam_x in (-2.15, 2.15):
        parts.append(cube(f"Awning post {beam_x}", (beam_x, -3.15, 1.30), (0.10, 0.10, 1.30), timber, bevel=0.02))
    parts.append(cube("Awning beam", (0.0, -3.15, 2.55), (2.28, 0.11, 0.11), timber, bevel=0.02))
    parts.append(cube("Woven shade", (0.0, -2.40, 2.52), (2.30, 0.82, 0.055), cloth, rotation=(0.04, 0.0, 0.0)))
    for jar_index in range(4):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.34 + 0.06 * (jar_index % 2), location=(-1.35 + jar_index * 0.88, -2.25, 0.42))
        jar = bpy.context.object
        jar.name = f"Waystation water jar {jar_index}"
        jar.scale.z = 1.32
        apply_transform(jar)
        jar.data.materials.append(ceramic)
        parts.append(jar)
    parts.append(cube("Waystation bench", (0.0, -2.72, 0.60), (1.25, 0.32, 0.12), timber, bevel=0.025))
    for x in (-1.05, 1.05):
        parts.append(cube(f"Bench leg {x}", (x, -2.72, 0.30), (0.09, 0.22, 0.30), timber, bevel=0.015))
    return join_asset("SunscarWaystation", parts, (55.0, 0.0, 0.0), "detailed flat-roof caravan shelter with shade, jars, and bench")


def build_arch(sandstone, sandstone_light, dark):
    parts = []
    # Unequal weathered blocks form a genuine opening rather than a black decal.
    for side in (-1.0, 1.0):
        for course in range(5):
            parts.append(cube(f"Natural arch pier {side}-{course}", (side * (2.15 - 0.11 * course), 0.0, 0.48 + course * 0.76), (0.62, 1.02, 0.40), sandstone if course % 2 else sandstone_light, rotation=(0.0, side * 0.035 * course, side * 0.028), bevel=0.08))
    for crown_index in range(7):
        angle = math.pi * (0.16 + 0.68 * crown_index / 6.0)
        x = math.cos(angle) * 2.25
        z = 3.55 + math.sin(angle) * 1.35
        parts.append(cube(f"Natural arch crown {crown_index}", (x, 0.0, z), (0.58, 1.02, 0.38), sandstone_light if crown_index % 2 else sandstone, rotation=(0.0, angle - math.pi * 0.5, 0.0), bevel=0.08))
    parts.append(cube("Arch inner shadow", (0.0, 0.72, 2.0), (1.48, 0.08, 1.86), dark, bevel=0.05))
    return join_asset("SunscarNaturalArch", parts, (67.0, 0.0, 0.0), "weathered sandstone arch landmark with a true open silhouette")


def setup_preview(assets, ground_mat):
    review_positions = (
        (-15.0, 3.5, 0.0), (-5.0, 3.5, 0.0), (5.0, 3.5, 0.0), (15.0, 3.5, 0.0),
        (-15.0, -7.5, 0.0), (-5.0, -7.5, 0.0), (5.0, -7.5, 0.0), (15.0, -7.5, 0.0),
    )
    for asset, review_position in zip(assets, review_positions):
        asset.location = review_position
    bpy.ops.mesh.primitive_plane_add(size=64.0, location=(0.0, 0.0, -0.045))
    ground = bpy.context.object
    ground.name = "Preview ground (not exported)"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("Sunscar preview world")
        bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.21, 0.31, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.50

    bpy.ops.object.light_add(type="SUN", location=(18.0, -18.0, 26.0))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(36), 0.0, math.radians(28))
    sun.data.energy = 3.1
    sun.data.angle = math.radians(18)
    sun.data.color = (1.0, 0.82, 0.58)
    bpy.ops.object.light_add(type="AREA", location=(20.0, -18.0, 18.0))
    fill = bpy.context.object
    fill.data.energy = 1600
    fill.data.shape = "DISK"
    fill.data.size = 18.0
    fill.data.color = (0.62, 0.76, 1.0)
    fill.rotation_euler = (math.radians(58), 0.0, 0.0)

    bpy.ops.object.camera_add(location=(0.0, -52.0, 33.0))
    camera = bpy.context.object
    camera.data.lens = 45
    direction = Vector((0.0, -1.5, 2.0)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bark = material("Dry acacia bark", (0.18, 0.105, 0.052, 1.0))
    bark_light = material("Palm scar bark", (0.31, 0.20, 0.10, 1.0))
    twig = material("Weathered twigs", (0.13, 0.085, 0.044, 1.0))
    leaf_dark = material("Acacia olive leaves", (0.12, 0.22, 0.075, 1.0))
    leaf_light = material("Sunlit acacia leaves", (0.28, 0.34, 0.10, 1.0))
    palm_dark = material("Date palm fronds", (0.08, 0.25, 0.095, 1.0))
    palm_light = material("Sunlit palm fronds", (0.22, 0.38, 0.11, 1.0))
    date_mat = material("Dates", (0.30, 0.075, 0.025, 1.0))
    sage = material("Sage leaves", (0.34, 0.39, 0.22, 1.0))
    scrub_green = material("Thorn scrub leaves", (0.18, 0.28, 0.095, 1.0))
    bloom = material("Desert flowers", (0.62, 0.20, 0.08, 1.0))
    sandstone = material("Sunscar red sandstone", (0.39, 0.19, 0.075, 1.0))
    sandstone_light = material("Sunscar sunlit strata", (0.58, 0.34, 0.14, 1.0))
    sandstone_dark = material("Sunscar shadow strata", (0.245, 0.12, 0.055, 1.0))
    wet_stone = material("Wet spring sandstone", (0.12, 0.11, 0.075, 1.0), 0.48)
    cut_stone = material("Dryland cut stone", (0.52, 0.39, 0.24, 1.0))
    stucco = material("Sunscar lime stucco", (0.64, 0.49, 0.29, 1.0))
    timber = material("Caravan dark timber", (0.20, 0.105, 0.045, 1.0))
    iron = material("Mine iron", (0.11, 0.105, 0.095, 1.0), 0.66, 0.44)
    darkness = material("Recessed interior darkness", (0.008, 0.006, 0.004, 1.0), 1.0)
    cloth = material("Ochre woven shade", (0.45, 0.18, 0.055, 1.0))
    ceramic = material("Blue water ceramic", (0.08, 0.28, 0.34, 1.0))
    ground_mat = material("Preview sand", (0.27, 0.19, 0.105, 1.0))

    assets = [
        build_acacia(bark, twig, leaf_dark, leaf_light),
        build_palms(bark, bark_light, palm_dark, palm_light, date_mat),
        build_scrub(twig, scrub_green, sage, bloom),
        build_mesa(sandstone, sandstone_light, sandstone_dark),
        build_source_formation(sandstone, sandstone_dark, wet_stone),
        build_mine(cut_stone, sandstone_light, timber, iron, darkness),
        build_waystation(stucco, cut_stone, timber, cloth, ceramic),
        build_arch(sandstone, sandstone_light, darkness),
    ]
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for asset in assets:
        asset.select_set(True)
    bpy.context.view_layer.objects.active = assets[0]
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_lights=False, export_cameras=False,
    )
    setup_preview(assets, ground_mat)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"SUNSCAR_DRYLANDS_KIT_EXPORT|blend={BLEND_PATH}|glb={GLB_PATH}|preview={PREVIEW_PATH}|meshes={len(assets)}")


if __name__ == "__main__":
    main()
