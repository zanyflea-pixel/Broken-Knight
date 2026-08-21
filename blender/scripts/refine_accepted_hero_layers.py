"""Replace only hair, loincloth, and Walk on the accepted continuous hero.

The accepted ConnectedBody mesh is treated as immutable. This pass authors a
volumetric short groom, a narrow cord-suspended loincloth, and a restrained
human gait into separate candidate files for review before promotion.
"""

from hashlib import sha256
from math import cos, pi, radians, sin
import os
import random
import struct

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT_BLEND = os.environ.get(
    "BK_REFINED_HERO_OUTPUT_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_LayerRefinementCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_REFINED_HERO_OUTPUT_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_refinement_candidate.glb"),
)
TEXTURE_DIR = os.path.join(ROOT, "blender", "textures")
ACCEPTED_PRE_REFINEMENT_HAIR_BLEND = os.path.join(
    ROOT, "blender", "backups", "hero_layer_refinement_20260812_133518",
    "BrokenKnight_Hero_Master.before_layer_refinement.blend",
)


def body_digest(body):
    digest = sha256()
    for vertex in body.data.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
    for polygon in body.data.polygons:
        digest.update(struct.pack("<I", len(polygon.vertices)))
        for index in polygon.vertices:
            digest.update(struct.pack("<I", index))
    return digest.hexdigest()


def material(name, color, roughness):
    result = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    result.diffuse_color = color
    result.roughness = roughness
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return result


def create_hair_textures():
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    size = 512
    albedo = bpy.data.images.new("HeroHairFlowAlbedo.Refined", width=size, height=size, alpha=True)
    normal = bpy.data.images.new("HeroHairFlowNormal.Refined", width=size, height=size, alpha=True)
    albedo_pixels = []
    normal_pixels = []
    for y in range(size):
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            phase = 2.0 * pi * (u * 92.0 + v * 2.0 + sin(v * pi * 5.0) * 0.28)
            secondary = 2.0 * pi * (u * 47.0 - v * 1.3)
            strand = 0.5 + 0.5 * sin(phase)
            breakup = 0.5 + 0.5 * sin(secondary)
            # Low-contrast warm brown grain.  The previous bright strand
            # ribbons read as painted plugs in Godot; the sculpted volume now
            # supplies the silhouette while this texture supplies only grain.
            shade = 0.88 + 0.07 * strand + 0.05 * breakup
            albedo_pixels.extend((0.060 * shade, 0.023 * shade, 0.010 * shade, 1.0))
            nx = 0.075 * cos(phase) + 0.025 * cos(secondary)
            ny = 0.018 * sin(phase + secondary)
            nz = 1.0
            length = (nx * nx + ny * ny + nz * nz) ** 0.5
            normal_pixels.extend((0.5 + 0.5 * nx / length, 0.5 + 0.5 * ny / length, 0.5 + 0.5 * nz / length, 1.0))
    albedo.pixels.foreach_set(albedo_pixels)
    normal.pixels.foreach_set(normal_pixels)
    albedo.filepath_raw = os.path.join(TEXTURE_DIR, "hero_hair_flow_albedo_v1.png")
    normal.filepath_raw = os.path.join(TEXTURE_DIR, "hero_hair_flow_normal_v1.png")
    albedo.file_format = "PNG"
    normal.file_format = "PNG"
    normal.colorspace_settings.name = "Non-Color"
    albedo.save()
    normal.save()
    return albedo, normal


def add_planar_scalp_uv(mesh):
    uv_layer = mesh.uv_layers.new(name="HeroHairFlowUV")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            u = max(0.0, min(1.0, 0.5 + vertex.co.x / 0.22))
            v = max(0.0, min(1.0, (vertex.co.y + 0.19) / 0.31))
            uv_layer.data[loop_index].uv = (u, v)


def connect_hair_textures(hair_material, albedo, normal):
    nodes = hair_material.node_tree.nodes
    links = hair_material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.name = "DirectionalHairAlbedo"
    albedo_node.image = albedo
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.name = "DirectionalHairNormal"
    normal_node.image = normal
    normal_node.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    # Fine grain only. A stronger normal made the short hair flash blue/grey
    # under moving lights and reinforced the plastic helmet appearance.
    normal_map.inputs["Strength"].default_value = 0.08
    links.new(albedo_node.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])


def create_cloth_textures():
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    size = 256
    albedo = bpy.data.images.new("HeroLoinclothWovenAlbedo.Refined", width=size, height=size, alpha=True)
    normal = bpy.data.images.new("HeroLoinclothWovenNormal.Refined", width=size, height=size, alpha=True)
    albedo_pixels = []
    normal_pixels = []
    for y in range(size):
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            warp = sin(2.0 * pi * u * 76.0)
            weft = sin(2.0 * pi * v * 68.0)
            weave = 0.86 + 0.07 * warp + 0.07 * weft
            edge = min(u, 1.0 - u, v, 1.0 - v)
            stitch = 0.64 if edge < 0.026 else 1.0
            # Values are stored in Blender's linear image buffer.  Keep enough
            # luminance that the embedded glTF textile reads as warm chestnut
            # leather/cloth rather than the rejected nearly-black panel.
            albedo_pixels.extend((0.300 * weave * stitch, 0.105 * weave * stitch, 0.035 * weave * stitch, 1.0))
            nx = 0.055 * cos(2.0 * pi * u * 76.0)
            ny = 0.055 * cos(2.0 * pi * v * 68.0)
            length = (nx * nx + ny * ny + 1.0) ** 0.5
            normal_pixels.extend((0.5 + 0.5 * nx / length, 0.5 + 0.5 * ny / length, 0.5 + 0.5 / length, 1.0))
    albedo.pixels.foreach_set(albedo_pixels)
    normal.pixels.foreach_set(normal_pixels)
    albedo.filepath_raw = os.path.join(TEXTURE_DIR, "hero_loincloth_woven_albedo_v1.png")
    normal.filepath_raw = os.path.join(TEXTURE_DIR, "hero_loincloth_woven_normal_v1.png")
    albedo.file_format = "PNG"
    normal.file_format = "PNG"
    normal.colorspace_settings.name = "Non-Color"
    albedo.save()
    normal.save()
    return albedo, normal


def connect_cloth_textures(cloth_material, albedo, normal):
    nodes = cloth_material.node_tree.nodes
    links = cloth_material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.name = "WovenClothAlbedo"
    albedo_node.image = albedo
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.name = "WovenClothNormal"
    normal_node.image = normal
    normal_node.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.28
    links.new(albedo_node.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])


def rigid_bone_parent(obj, rig, bone_name):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


def scalp_threshold(x, y):
    ax = abs(x)
    center_peak = 0.0060 * max(0.0, 1.0 - ax / 0.040) ** 2
    temple = 0.0065 * max(0.0, min(1.0, (ax - 0.050) / 0.042))
    frontal = 1.791 - center_peak + temple
    if y < -0.055:
        return frontal
    if y < 0.035:
        transition = (y + 0.055) / 0.090
        side = 1.729 + 0.006 * max(0.0, min(1.0, (ax - 0.045) / 0.045))
        return frontal * (1.0 - transition) + side * transition
    back_drop = 0.042 * max(0.0, min(1.0, (y - 0.035) / 0.120))
    nape_taper = 0.020 * max(0.0, min(1.0, ax / 0.100)) ** 1.45
    # Lower at the centre and higher behind the ears: a tapered natural nape,
    # not the straight bowl-cut line visible in the previous groom.
    return 1.729 - back_drop + nape_taper


def extract_clean_scalp(body):
    source = body.data
    selected = []
    for polygon in source.polygons:
        center = polygon.center
        if center.z <= scalp_threshold(center.x, center.y):
            continue
        if abs(center.x) > 0.105 or center.y < -0.185 or center.y > 0.115:
            continue
        selected.append(polygon)
    if not selected:
        raise RuntimeError("Accepted head produced no clean scalp faces")
    used = sorted({index for polygon in selected for index in polygon.vertices})
    mapping = {old: new for new, old in enumerate(used)}
    mesh = bpy.data.meshes.new("AcceptedHeadCleanScalp.Mesh")
    mesh.from_pydata(
        [tuple(source.vertices[index].co) for index in used], [],
        [tuple(mapping[index] for index in polygon.vertices) for polygon in selected],
    )
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # The accepted head is intentionally left untouched.  Relax the extracted
    # border much more strongly, however, so its polygon boundary reads as a
    # natural hairline instead of the rejected saw-toothed cap edge.
    for _iteration in range(8):
        boundary = {
            vertex for edge in bm.edges if len(edge.link_faces) == 1
            for vertex in edge.verts
        }
        bmesh.ops.smooth_vert(
            bm, verts=list(boundary), factor=0.34,
            use_axis_x=True, use_axis_y=True, use_axis_z=True,
        )
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return mesh


def build_laid_hair_groom(source_mesh, rig, hair_material):
    """Build one dense, head-attached mesh of swept short hair ribbons.

    The ribbons lie along the scalp rather than poking away from it.  They are
    deliberately sub-millimetre thin and share one object, avoiding both the
    old sparse plug look and the solid helmet silhouette.
    """
    vertices = []
    faces = []
    samples = (
        (0.48, 0.18, 0.17, 0.17),
        (0.17, 0.48, 0.18, 0.17),
        (0.17, 0.17, 0.48, 0.18),
        (0.18, 0.17, 0.17, 0.48),
    )
    # Mesh edges do not expose boundary state directly; derive it from polygon
    # incidence so groom ribbons stop before the hairline rather than hanging
    # over the forehead as tiny spikes.
    incidence = {}
    adjacency = {vertex.index: set() for vertex in source_mesh.vertices}
    for polygon in source_mesh.polygons:
        keys = [tuple(sorted((polygon.vertices[index], polygon.vertices[(index + 1) % len(polygon.vertices)]))) for index in range(len(polygon.vertices))]
        for key in keys:
            incidence[key] = incidence.get(key, 0) + 1
            adjacency[key[0]].add(key[1])
            adjacency[key[1]].add(key[0])
    boundary_vertices = {vertex for edge, count in incidence.items() if count == 1 for vertex in edge}
    boundary_guard = set(boundary_vertices)
    for _ring in range(2):
        boundary_guard.update(neighbor for vertex in tuple(boundary_guard) for neighbor in adjacency[vertex])
    for polygon_index, polygon in enumerate(source_mesh.polygons):
        if any(vertex in boundary_guard for vertex in polygon.vertices):
            continue
        poly_vertices = [source_mesh.vertices[index] for index in polygon.vertices]
        if len(poly_vertices) < 3:
            continue
        while len(poly_vertices) < 4:
            poly_vertices.append(poly_vertices[-1])
        normal = polygon.normal.normalized()
        for sample_index, weights in enumerate(samples):
            point = Vector((0.0, 0.0, 0.0))
            weight_total = 0.0
            for vertex, weight in zip(poly_vertices[:4], weights):
                point += vertex.co * weight
                weight_total += weight
            point /= max(weight_total, 0.0001)
            radial = Vector((point.x, point.y + 0.010, 0.0))
            if radial.length < 0.001:
                radial = Vector((0.0, -1.0, 0.0))
            radial.normalize()
            # Hair grows away from the crown and is combed down around the
            # skull.  A restrained rightward bias prevents a dead centre cap.
            flow_noise = sin((polygon_index * 11 + sample_index * 29) * 0.913)
            desired = radial * 0.66 + Vector((0.16 + 0.10 * flow_noise, 0.06 * flow_noise, -0.48))
            tangent = desired - normal * desired.dot(normal)
            if tangent.length < 0.001:
                tangent = normal.cross(Vector((1.0, 0.0, 0.0)))
            tangent.normalize()
            side = normal.cross(tangent).normalized()
            crown = max(0.0, min(1.0, (point.z - 1.735) / 0.155))
            jitter = 0.5 + 0.5 * sin((polygon_index * 17 + sample_index * 43) * 1.713)
            length = 0.0055 + 0.0070 * crown + 0.0018 * jitter
            width = 0.00046 + 0.00018 * jitter
            base = len(vertices)
            for step in range(4):
                t = step / 3.0
                center = (
                    point
                    + normal * (0.00105 + 0.00072 * sin(t * pi))
                    + tangent * length * t
                    + side * (0.00042 * sin(t * pi) * sin(polygon_index * 0.77))
                )
                taper = max(0.08, 1.0 - t * 0.88)
                vertices.append(tuple(center - side * width * taper))
                vertices.append(tuple(center + side * width * taper))
            for step in range(3):
                index = base + step * 2
                faces.append((index, index + 1, index + 3, index + 2))
    mesh = bpy.data.meshes.new("HeroHairGroom.Refined.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(hair_material)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    groom = bpy.data.objects.new("HeroHairGroom.Refined", mesh)
    bpy.context.collection.objects.link(groom)
    rigid_bone_parent(groom, rig, "head")
    return groom


def mesh_boundary_distances(mesh):
    """Return topological distance from an open mesh boundary for each vertex."""
    incidence = {}
    adjacency = {vertex.index: set() for vertex in mesh.vertices}
    for polygon in mesh.polygons:
        vertices = list(polygon.vertices)
        for index, first in enumerate(vertices):
            second = vertices[(index + 1) % len(vertices)]
            key = tuple(sorted((first, second)))
            incidence[key] = incidence.get(key, 0) + 1
            adjacency[first].add(second)
            adjacency[second].add(first)
    boundary = {vertex for edge, count in incidence.items() if count == 1 for vertex in edge}
    distances = {vertex: 0 for vertex in boundary}
    frontier = set(boundary)
    for distance in range(1, 13):
        next_frontier = {
            neighbor for vertex in frontier for neighbor in adjacency[vertex]
            if neighbor not in distances
        }
        for vertex in next_frontier:
            distances[vertex] = distance
        frontier = next_frontier
    return distances, adjacency


def smooth_open_boundary(mesh, iterations=7, factor=0.28):
    """Relax only the outer hairline so it reads as a cut edge, not teeth."""
    distances, adjacency = mesh_boundary_distances(mesh)
    affected = {index for index, distance in distances.items() if distance <= 4}
    for _iteration in range(iterations):
        original = [vertex.co.copy() for vertex in mesh.vertices]
        for index in affected:
            neighbors = adjacency[index]
            if not neighbors:
                continue
            average = sum((original[neighbor] for neighbor in neighbors), Vector()) / len(neighbors)
            # The falloff preserves the authored crown and smooths the hard,
            # scalloped side/back perimeter most strongly.
            distance = distances.get(index, 4)
            weight = factor * (1.0 - 0.16 * distance)
            mesh.vertices[index].co = original[index].lerp(average, weight)
    mesh.update()


def build_flush_hair_fibers(foundation, rig, hair_material):
    """Create fine swept fibers that remain embedded in the connected scalp.

    Roots sit only 0.2 mm above the shell and tips return to the surface.  This
    avoids the old upright plug forest while breaking up the cap-like material
    response at both face-inspection and game distance.
    """
    mesh = foundation.data
    distances, adjacency = mesh_boundary_distances(mesh)
    boundary = {vertex for vertex, distance in distances.items() if distance == 0}
    boundary_guard = set(boundary)
    for _ring in range(1):
        boundary_guard.update(neighbor for vertex in tuple(boundary_guard) for neighbor in adjacency[vertex])
    interior = [polygon for polygon in mesh.polygons if not any(vertex in boundary_guard for vertex in polygon.vertices)]
    random.seed(20260812)
    sample_count = min(6000, len(interior))
    selected = random.sample(interior, sample_count)
    curve_data = bpy.data.curves.new("HeroHairFlushFibers.Refined.Curve", "CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 1
    curve_data.bevel_depth = 0.000095
    curve_data.bevel_resolution = 1
    curve_data.use_fill_caps = True
    for polygon_index, polygon in enumerate(selected):
        vertices = [mesh.vertices[index] for index in polygon.vertices]
        root = sum((vertex.co for vertex in vertices), Vector()) / len(vertices)
        normal = sum((vertex.normal for vertex in vertices), Vector()).normalized()
        topness = max(0.0, normal.z)
        sideness = max(0.0, min(1.0, abs(normal.x) * 1.45))
        # A subtle left part prevents the perfectly radial plastic-cap look.
        # Side fibers still comb downward into the short fade.
        flow = Vector((0.24 * topness, 1.0, -0.52 * sideness))
        flow += Vector((random.uniform(-0.15, 0.15), random.uniform(-0.055, 0.055), random.uniform(-0.030, 0.030)))
        flow -= normal * flow.dot(normal)
        if flow.length_squared < 1e-8:
            continue
        flow.normalize()
        length = (0.008 + 0.030 * topness ** 1.5) * random.uniform(0.80, 1.17)
        side = normal.cross(flow).normalized()
        sway = side * random.uniform(-0.00048, 0.00048)
        lift = 0.00075 + 0.0031 * topness ** 1.55
        spline = curve_data.splines.new("POLY")
        spline.points.add(3)
        centers = (
            root + normal * 0.00028,
            root + flow * (length * 0.34) + normal * (lift * 0.72) + sway * 0.35,
            root + flow * (length * 0.70) + normal * lift + sway,
            root + flow * length + normal * 0.00035 + sway * 0.40,
        )
        for point_index, center in enumerate(centers):
            point = spline.points[point_index]
            point.co = (*center, 1.0)
            point.radius = (0.62, 0.88, 0.70, 0.05)[point_index]
    fibers = bpy.data.objects.new("HeroHairFlushFibers.Refined", curve_data)
    bpy.context.collection.objects.link(fibers)
    curve_data.materials.append(hair_material)
    fibers.matrix_world = foundation.matrix_world.copy()
    rigid_bone_parent(fibers, rig, "head")
    return fibers


def build_swept_top_locks(foundation, rig, hair_material):
    """Add coherent laid locks across the crown to break the solid-cap read."""
    mesh = foundation.data
    candidates = [
        polygon for polygon in mesh.polygons
        if polygon.center.z > 1.765 and polygon.normal.z > 0.30
    ]
    random.seed(20260815)
    selected = random.sample(candidates, min(1050, len(candidates)))
    curve_data = bpy.data.curves.new("HeroHairSweptLocks.Refined.Curve", "CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 1
    curve_data.bevel_depth = 0.00026
    curve_data.bevel_resolution = 1
    curve_data.use_fill_caps = True
    for polygon in selected:
        vertices = [mesh.vertices[index] for index in polygon.vertices]
        root = sum((vertex.co for vertex in vertices), Vector()) / len(vertices)
        normal = sum((vertex.normal for vertex in vertices), Vector()).normalized()
        side_from_part = 1.0 if root.x > -0.024 else -0.45
        flow = Vector((0.20 * side_from_part, 1.0, -0.11))
        flow += Vector((random.uniform(-0.08, 0.08), random.uniform(-0.04, 0.04), random.uniform(-0.025, 0.025)))
        flow -= normal * flow.dot(normal)
        if flow.length_squared < 1e-9:
            continue
        flow.normalize()
        length = random.uniform(0.020, 0.039) * (0.90 + 0.20 * max(0.0, normal.z))
        side = normal.cross(flow).normalized()
        sway = side * random.uniform(-0.0009, 0.0009)
        lift = random.uniform(0.0022, 0.0048)
        spline = curve_data.splines.new("POLY")
        spline.points.add(4)
        centers = (
            root + normal * 0.00022,
            root + flow * (length * 0.24) + normal * (lift * 0.55) + sway * 0.20,
            root + flow * (length * 0.50) + normal * lift + sway * 0.65,
            root + flow * (length * 0.76) + normal * (lift * 0.62) + sway,
            root + flow * length + normal * 0.00028 + sway * 0.38,
        )
        for point_index, center in enumerate(centers):
            spline.points[point_index].co = (*center, 1.0)
            spline.points[point_index].radius = (0.52, 0.92, 1.0, 0.62, 0.08)[point_index]
    curve_data.materials.append(hair_material)
    locks = bpy.data.objects.new("HeroHairSweptLocks.Refined", curve_data)
    bpy.context.collection.objects.link(locks)
    locks.matrix_world = foundation.matrix_world.copy()
    rigid_bone_parent(locks, rig, "head")
    return locks


def build_hairline_fibers(foundation, rig, hair_material):
    """Feather the perimeter with short scalp-hugging hairs."""
    mesh = foundation.data
    distances, adjacency = mesh_boundary_distances(mesh)
    boundary = [index for index, distance in distances.items() if distance == 0]
    curve_data = bpy.data.curves.new("HeroHairHairline.Refined.Curve", "CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 1
    curve_data.bevel_depth = 0.000115
    curve_data.bevel_resolution = 1
    curve_data.use_fill_caps = True
    random.seed(20260814)
    for index in boundary:
        root_vertex = mesh.vertices[index]
        inward_neighbors = [
            neighbor for neighbor in adjacency[index]
            if distances.get(neighbor, 0) > 0
        ]
        if not inward_neighbors:
            continue
        inward_target = sum((mesh.vertices[neighbor].co for neighbor in inward_neighbors), Vector()) / len(inward_neighbors)
        direction = inward_target - root_vertex.co
        normal = root_vertex.normal.normalized()
        direction -= normal * direction.dot(normal)
        if direction.length_squared < 1e-10:
            continue
        direction.normalize()
        for duplicate in range(2):
            length = random.uniform(0.0042, 0.0074)
            tangent = direction + normal.cross(direction) * random.uniform(-0.14, 0.14)
            tangent.normalize()
            root = root_vertex.co + normal * (0.00018 + duplicate * 0.00005)
            spline = curve_data.splines.new("POLY")
            spline.points.add(2)
            centers = (
                root,
                root + tangent * (length * 0.48) + normal * 0.00052,
                root + tangent * length + normal * 0.00030,
            )
            for point_index, center in enumerate(centers):
                spline.points[point_index].co = (*center, 1.0)
                spline.points[point_index].radius = (0.32, 0.92, 0.10)[point_index]
    curve_data.materials.append(hair_material)
    hairline = bpy.data.objects.new("HeroHairHairline.Refined", curve_data)
    bpy.context.collection.objects.link(hairline)
    hairline.matrix_world = foundation.matrix_world.copy()
    rigid_bone_parent(hairline, rig, "head")
    return hairline


def rebuild_hair(body, rig):
    for obj in list(bpy.data.objects):
        if obj.name.startswith("HeroHair"):
            bpy.data.objects.remove(obj, do_unlink=True)
    if not os.path.exists(ACCEPTED_PRE_REFINEMENT_HAIR_BLEND):
        raise RuntimeError("Accepted pre-refinement hair source is missing")
    with bpy.data.libraries.load(ACCEPTED_PRE_REFINEMENT_HAIR_BLEND, link=False) as (source, target):
        if "HeroHairFoundation.Mesh" not in source.meshes:
            raise RuntimeError("Accepted hair foundation is missing from backup")
        # Append only the mesh datablock. Appending the object also follows its
        # old armature dependency and silently duplicates every animation.
        target.meshes = ["HeroHairFoundation.Mesh"]
    source_hair = bpy.data.objects.new("HeroHairFoundation.Refined", target.meshes[0])
    bpy.context.collection.objects.link(source_hair)
    source_hair.matrix_world = bpy.context.scene.cursor.matrix.copy()

    foundation_material = material("HeroHair.Foundation.Refined", (0.012, 0.0038, 0.0017, 1.0), 0.94)
    fade_material = material("HeroHair.Fade.Refined", (0.030, 0.0100, 0.0045, 1.0), 0.97)
    hair_material = material("HeroHair.Surface.Refined", (0.026, 0.0075, 0.0030, 1.0), 0.94)
    hair_material.use_backface_culling = False
    albedo, normal = create_hair_textures()
    connect_hair_textures(hair_material, albedo, normal)

    foundation = source_hair
    foundation.name = "HeroHairFoundation.Refined"
    foundation.data = foundation.data.copy()
    foundation.data.name = "HeroHairFoundation.Refined.Mesh"
    # Taper only the open hairline boundary into the skin. Uniformly sinking the
    # shell exposed the dense grid underneath as rows; a 10-ring falloff keeps
    # the smooth crown while removing the helmet-like ledge at its perimeter.
    smooth_open_boundary(foundation.data, iterations=9, factor=0.31)
    distances, _adjacency = mesh_boundary_distances(foundation.data)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    head_surface = BVHTree.FromObject(body, depsgraph)
    for vertex in foundation.data.vertices:
        distance = distances.get(vertex.index, 12)
        if distance <= 10:
            nearest = head_surface.find_nearest(vertex.co, 0.050)
            if nearest[0] is not None:
                ratio = distance / 10.0
                target = nearest[0] + nearest[1] * (0.00006 + 0.00125 * ratio ** 1.6)
                vertex.co = vertex.co.lerp(target, 1.0 - ratio)
    foundation.data.update()
    foundation.data.materials.clear()
    foundation.data.materials.append(foundation_material)
    foundation.data.materials.append(fade_material)
    for polygon in foundation.data.polygons:
        polygon.use_smooth = True
        if min(distances.get(index, 12) for index in polygon.vertices) <= 4:
            polygon.material_index = 1
    subdivision = foundation.modifiers.new("HairFoundationSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    breakup = bpy.data.textures.get("HeroHairFoundationBreakup.Refined") or bpy.data.textures.new("HeroHairFoundationBreakup.Refined", type="CLOUDS")
    breakup.noise_scale = 0.0048
    breakup.noise_depth = 1
    displace = foundation.modifiers.new("HairFoundationMicroBreakup", "DISPLACE")
    displace.texture = breakup
    displace.strength = 0.00010
    displace.mid_level = 0.51
    rigid_bone_parent(foundation, rig, "head")

    fiber_material = material("HeroHair.Fibers.Refined", (0.028, 0.0080, 0.0030, 1.0), 0.96)
    fibers = build_flush_hair_fibers(foundation, rig, fiber_material)
    locks = build_swept_top_locks(foundation, rig, fiber_material)
    return foundation, fibers, locks


def rebuild_brows(body, rig):
    """Build dark matte brow beds with embedded individual hairs."""
    for obj in list(bpy.data.objects):
        if obj.name.startswith("ProfessionalBrows"):
            bpy.data.objects.remove(obj, do_unlink=True)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    brow_material = material("HeroBrows.Matte.Refined", (0.018, 0.0042, 0.0015, 1.0), 1.0)
    vertices = []
    faces = []
    # Inner-to-outer authored brow arc. Wider medially, gently tapered at the
    # temple. Both surfaces sit 0.65 mm above the accepted forehead.
    x_abs = (0.012, 0.020, 0.029, 0.038, 0.046, 0.053)
    z_center = (1.7635, 1.7660, 1.7677, 1.7670, 1.7647, 1.7616)
    half_height = (0.00100, 0.00128, 0.00146, 0.00134, 0.00102, 0.00058)
    for side in (-1.0, 1.0):
        start = len(vertices)
        for index, absolute_x in enumerate(x_abs):
            x = side * absolute_x
            center_z = z_center[index]
            for z in (center_z - half_height[index], center_z + half_height[index]):
                hit = tree.ray_cast(Vector((x, -0.30, z)), Vector((0.0, 1.0, 0.0)), 0.50)
                if hit[0] is None:
                    raise RuntimeError("Could not fit matte brow to accepted face")
                vertices.append((x, hit[0].y - 0.00065, z))
        for index in range(len(x_abs) - 1):
            base = start + index * 2
            faces.append((base, base + 2, base + 3, base + 1))
    mesh = bpy.data.meshes.new("ProfessionalBrows.Matte.Refined.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(brow_material)
    mesh.update()
    brows = bpy.data.objects.new("ProfessionalBrows", mesh)
    bpy.context.collection.objects.link(brows)
    solid = brows.modifiers.new("BrowThickness", "SOLIDIFY")
    solid.thickness = 0.00022
    solid.offset = 0.0
    bevel = brows.modifiers.new("BrowEdgeSoftness", "BEVEL")
    bevel.width = 0.00014
    bevel.segments = 2
    rigid_bone_parent(brows, rig, "head")

    # The hair layer supplies the visible brow mass without a shiny broad slab.
    random.seed(20260813)
    strand_data = bpy.data.curves.new("ProfessionalBrows.Strands.Refined.Curve", "CURVE")
    strand_data.dimensions = "3D"
    strand_data.resolution_u = 1
    strand_data.bevel_depth = 0.000155
    strand_data.bevel_resolution = 1
    strand_data.use_fill_caps = True
    for side in (-1.0, 1.0):
        for strand_index in range(170):
            u = (strand_index + random.uniform(0.08, 0.92)) / 170.0
            position = u * (len(x_abs) - 1)
            index = min(len(x_abs) - 2, int(position))
            blend = position - index
            absolute_x = x_abs[index] * (1.0 - blend) + x_abs[index + 1] * blend
            center_z = z_center[index] * (1.0 - blend) + z_center[index + 1] * blend
            height = half_height[index] * (1.0 - blend) + half_height[index + 1] * blend
            z = center_z + random.uniform(-0.78, 0.78) * height
            x = side * absolute_x
            root_hit = tree.ray_cast(Vector((x, -0.30, z)), Vector((0.0, 1.0, 0.0)), 0.50)
            if root_hit[0] is None:
                continue
            outward = side * random.uniform(0.0030, 0.0048)
            tip_x = x + outward
            tip_z = z + random.uniform(0.00035, 0.00145) * (1.0 - 0.7 * u)
            tip_hit = tree.ray_cast(Vector((tip_x, -0.30, tip_z)), Vector((0.0, 1.0, 0.0)), 0.50)
            if tip_hit[0] is None:
                continue
            spline = strand_data.splines.new("POLY")
            spline.points.add(2)
            middle_x = (x + tip_x) * 0.5
            middle_z = (z + tip_z) * 0.5 + 0.00018
            middle_hit = tree.ray_cast(Vector((middle_x, -0.30, middle_z)), Vector((0.0, 1.0, 0.0)), 0.50)
            middle_y = middle_hit[0].y if middle_hit[0] is not None else (root_hit[0].y + tip_hit[0].y) * 0.5
            points = (
                (x, root_hit[0].y - 0.00078, z),
                (middle_x, middle_y - 0.00092, middle_z),
                (tip_x, tip_hit[0].y - 0.00072, tip_z),
            )
            for point_index, coordinate in enumerate(points):
                spline.points[point_index].co = (*coordinate, 1.0)
                spline.points[point_index].radius = (0.58, 0.92, 0.18)[point_index]
    strand_data.materials.append(brow_material)
    strands = bpy.data.objects.new("ProfessionalBrows.Strands", strand_data)
    bpy.context.collection.objects.link(strands)
    rigid_bone_parent(strands, rig, "head")
    return brows, strands


def ray_surface_y(tree, x, z, front):
    origin = Vector((x, -0.55 if front else 0.55, z))
    direction = Vector((0.0, 1.0 if front else -1.0, 0.0))
    hit = tree.ray_cast(origin, direction, 1.1)
    if hit[0] is not None:
        return hit[0].y
    return -0.12 if front else 0.12


def ray_surface_y_optional(tree, x, z, front):
    origin = Vector((x, -0.55 if front else 0.55, z))
    direction = Vector((0.0, 1.0 if front else -1.0, 0.0))
    hit = tree.ray_cast(origin, direction, 1.1)
    return hit[0].y if hit[0] is not None else None


def skin_rear_cloth_to_body(obj, body, rig):
    """Copy the accepted body's nearest deform weights onto the rear wrap."""
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.parent_bone = ""
    obj.matrix_world = world
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    cloth_groups = {
        name: obj.vertex_groups.new(name=name)
        for name in deform_names if body.vertex_groups.get(name) is not None
    }
    nearest_tree = KDTree(len(body.data.vertices))
    for vertex in body.data.vertices:
        nearest_tree.insert(vertex.co, vertex.index)
    nearest_tree.balance()
    for cloth_vertex in obj.data.vertices:
        _coordinate, body_index, _distance = nearest_tree.find(cloth_vertex.co)
        body_vertex = body.data.vertices[body_index]
        weights = []
        for assignment in body_vertex.groups:
            name = body.vertex_groups[assignment.group].name
            if name in cloth_groups and assignment.weight > 0.0001:
                weights.append((name, assignment.weight))
        total = sum(weight for _name, weight in weights)
        if total <= 0.0001:
            cloth_groups["pelvis"].add((cloth_vertex.index,), 1.0, "REPLACE")
            continue
        for name, weight in weights:
            cloth_groups[name].add((cloth_vertex.index,), weight / total, "REPLACE")
    armature = obj.modifiers.new("RearClothArmature", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    obj.modifiers.move(len(obj.modifiers) - 1, 0)


def build_rear_side_wrap(name, side, rows, tree, cloth_material, body, rig):
    """Build a fitted side gusset overlapping the stable central rear panel."""
    vertices = []
    columns = (0.0, 0.125, 0.25, 0.375, 0.50, 0.625, 0.75, 0.875, 1.0)
    for z, inner_x, outer_x in rows:
        for blend in columns:
            x = side * (inner_x * (1.0 - blend) + outer_x * blend)
            # Fit explicitly to the rear surface. A nearest-point query from
            # the middle of the body can select the flank or front surface and
            # create apparently random holes once the thigh moves.
            y = ray_surface_y_optional(tree, x, z, False)
            if y is None:
                target = Vector((x, 0.025, z))
                nearest = tree.find_nearest(target, 0.25)
                if nearest[0] is None:
                    raise RuntimeError(f"Could not fit rear side wrap at x={x}, z={z}")
                point = nearest[0] + nearest[1] * 0.0070
            else:
                point = Vector((x, y + 0.0070, z))
            vertices.append(tuple(point))
    width = len(columns)
    faces = []
    for row in range(len(rows) - 1):
        for column in range(width - 1):
            index = row * width + column
            if side < 0:
                faces.append((index, index + width, index + width + 1, index + 1))
            else:
                faces.append((index, index + 1, index + width + 1, index + width))
    mesh = bpy.data.meshes.new(name + ".Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(cloth_material)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="RearWrapUV")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            row_index = vertex_index // width
            column_index = vertex_index % width
            uv_layer.data[loop_index].uv = (
                column_index / max(1, width - 1),
                1.0 - row_index / max(1, len(rows) - 1),
            )
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    solid = obj.modifiers.new("WovenThickness", "SOLIDIFY")
    solid.thickness = 0.0018
    solid.offset = 0.0
    bevel = obj.modifiers.new("SoftClothEdge", "BEVEL")
    bevel.width = 0.0010
    bevel.segments = 2
    # Each side follows its glute/thigh, while its broad inner section remains
    # hidden below the stable centre panel. The overlap prevents the two body-
    # weighted halves from ever exposing a center or side gap during a stride.
    skin_rear_cloth_to_body(obj, body, rig)
    return obj


def build_fitted_rear_seat(name, body, rig, cloth_material):
    """Duplicate the accepted rear body surface as a fitted cloth underlayer.

    This is the reliable coverage layer: it shares the body's exact topology
    and exact deform weights, so Walk and Jump cannot expose skin through a
    drifting cloth edge. The visible central panel remains above it and keeps
    the silhouette reading as a loincloth rather than plain shorts.
    """
    source_mesh = body.data
    selected = []
    for polygon in source_mesh.polygons:
        center = polygon.center
        if not (0.705 <= center.z <= 1.038 and abs(center.x) <= 0.228):
            continue
        # Retain the rear and rear-side surface while excluding the belly and
        # groin. The negative allowance wraps the cloth around both cheeks.
        if center.y < -0.058:
            continue
        selected.append(polygon)
    source_indices = sorted({index for polygon in selected for index in polygon.vertices})
    remap = {source_index: new_index for new_index, source_index in enumerate(source_indices)}
    vertices = []
    for source_index in source_indices:
        source_vertex = source_mesh.vertices[source_index]
        # Four millimetres above the skin avoids z-fighting while remaining
        # visibly skin-tight against the corrected glute anatomy.
        coordinate = source_vertex.co + source_vertex.normal * 0.0030
        # Selected source faces can contain vertices above their face-centre
        # cutoff. Clamp that irregular boundary below the rear waistband so no
        # small topology tabs poke above the finished belt.
        coordinate.z = min(coordinate.z, 1.026)
        vertices.append(tuple(coordinate))
    faces = [tuple(remap[index] for index in polygon.vertices) for polygon in selected]
    mesh = bpy.data.meshes.new(name + ".Mesh")
    mesh.from_pydata(vertices, (), faces)
    mesh.materials.append(cloth_material)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="RearSeatUV")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            coordinate = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (
                0.5 + coordinate.x / 0.48,
                (coordinate.z - 0.695) / 0.35,
            )
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = True

    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.parent_bone = ""
    obj.matrix_world = world
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    groups = {
        group.name: obj.vertex_groups.new(name=group.name)
        for group in body.vertex_groups if group.name in deform_names
    }
    for new_index, source_index in enumerate(source_indices):
        for assignment in source_mesh.vertices[source_index].groups:
            group_name = body.vertex_groups[assignment.group].name
            if group_name in groups and assignment.weight > 0.0001:
                groups[group_name].add((new_index,), assignment.weight, "REPLACE")
    armature = obj.modifiers.new("RearSeatArmature", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    solid = obj.modifiers.new("WovenThickness", "SOLIDIFY")
    solid.thickness = 0.0012
    solid.offset = 0.0
    bevel = obj.modifiers.new("SoftClothEdge", "BEVEL")
    bevel.width = 0.0008
    bevel.segments = 2
    return obj


def cloth_panel(name, rows, columns, tree, front, cloth_material, body, rig):
    vertices = []
    top_samples = {
        column: ray_surface_y(tree, rows[0][1] * column, rows[0][0], front)
        for column in columns
    }
    center_top = ray_surface_y(tree, 0.0, rows[0][0], front)
    back_samples = {}
    if not front:
        for z, half_width in rows:
            raw = {
                column: ray_surface_y_optional(tree, half_width * column, z, False)
                for column in columns
            }
            valid = [value for value in raw.values() if value is not None]
            if not valid:
                raise RuntimeError(f"No accepted body surface behind rear cloth at z={z}")
            row_surface = max(valid)
            back_samples[z] = {
                column: (value + 0.0040 if value is not None else row_surface - 0.020)
                for column, value in raw.items()
            }
    for row_index, (z, half_width) in enumerate(rows):
        t = row_index / max(1, len(rows) - 1)
        for column in columns:
            x = half_width * column
            vertex_z = z
            if front:
                # Fitted only at the cord, then hanging as a narrow trapezoid.
                fitted = top_samples[column] - 0.0045
                hanging = center_top - 0.010 - 0.003 * sin(t * pi)
                y = fitted * (1.0 - t) + hanging * t
                # Three shallow folds give the panel fabric volume without
                # turning it into the previous clam-shell slab.
                y -= 0.0026 * cos(column * pi * 3.0) * (0.25 + 0.75 * t)
            else:
                fitted = back_samples[z][column]
                # Sit 4-6 mm from the glute surface. Bridge only the central
                # cleft using the row's outer surface; the rejected version was
                # 4-7 cm behind the body and made the butt appear misplaced.
                row_surface = max(back_samples[z].values())
                cleft_bridge = row_surface + 0.0045 - 0.010 * abs(column) ** 1.35
                y = max(fitted, cleft_bridge)
                # Below the glute fold the cloth releases into a short natural
                # drape rather than shrink-wrapping between the legs.
                release = max(0.0, min(1.0, (0.758 - z) / 0.064))
                y += 0.0060 * release * (1.0 - 0.45 * abs(column))
                y += 0.0007 * cos(column * pi * 2.0) * t
            if row_index == len(rows) - 1:
                # The centre hangs lowest, producing a cloth hem rather than
                # the rejected square flap.
                hem = (-0.013 if front else -0.009) * (1.0 - column * column)
            else:
                hem = 0.0
            vertices.append((x, y, vertex_z + hem))
    width = len(columns)
    faces = []
    for row in range(len(rows) - 1):
        for column in range(width - 1):
            index = row * width + column
            faces.append((index, index + 1, index + width + 1, index + width))
    mesh = bpy.data.meshes.new(name + ".Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(cloth_material)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="WovenPanelUV")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            row_index = vertex_index // width
            column_index = vertex_index % width
            uv_layer.data[loop_index].uv = (
                column_index / max(1, width - 1),
                1.0 - row_index / max(1, len(rows) - 1),
            )
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    solid = obj.modifiers.new("WovenThickness", "SOLIDIFY")
    solid.thickness = 0.0020
    solid.offset = 0.0
    bevel = obj.modifiers.new("SoftClothEdge", "BEVEL")
    bevel.width = 0.0011
    bevel.segments = 2
    if front:
        rigid_bone_parent(obj, rig, "pelvis")
    else:
        rigid_bone_parent(obj, rig, "pelvis")
    return obj


def rebuild_loincloth(body, rig):
    for obj in list(bpy.data.objects):
        if obj.name.startswith(("Loincloth", "LoinTie", "LoinKnot", "LoinTail", "ClothWaistCord")):
            bpy.data.objects.remove(obj, do_unlink=True)
    cloth_material = material("Loincloth.Woven.Refined", (0.120, 0.041, 0.016, 1.0), 0.97)
    cord_material = material("Loincloth.Cord.Refined", (0.041, 0.012, 0.005, 1.0), 0.94)
    cloth_albedo, cloth_normal = create_cloth_textures()
    connect_cloth_textures(cloth_material, cloth_albedo, cloth_normal)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    columns = (-1.0, -0.8, -0.60, -0.40, -0.20, 0.0, 0.20, 0.40, 0.60, 0.8, 1.0)
    front_rows = (
        (0.982, 0.106), (0.948, 0.103), (0.911, 0.098), (0.872, 0.090),
        (0.833, 0.081), (0.794, 0.070), (0.757, 0.058), (0.725, 0.047),
    )
    back_rows = (
        # The corrected glute mass sits lower, so this panel no longer climbs
        # up the lumbar region to disguise it. The previous narrow strip left
        # most of both cheeks exposed; this masculine rear panel spans the
        # glute mass beneath the cord, then tapers below the glute fold.
        (1.036, 0.131), (1.024, 0.135), (1.012, 0.140), (0.994, 0.145),
        (0.973, 0.151), (0.951, 0.157), (0.929, 0.162),
        (0.907, 0.166), (0.885, 0.168), (0.863, 0.168), (0.841, 0.166),
        (0.819, 0.162), (0.797, 0.157), (0.775, 0.150), (0.753, 0.141),
        (0.731, 0.130), (0.710, 0.118), (0.696, 0.106), (0.690, 0.095),
    )
    front = cloth_panel("Loincloth.Front.Refined", front_rows, columns, tree, True, cloth_material, body, rig)
    back = cloth_panel("Loincloth.Back.Refined", back_rows, columns, tree, False, cloth_material, body, rig)
    seat = build_fitted_rear_seat("Loincloth.RearSeat.Refined", body, rig, cloth_material)

    segments = 96
    vertices = []
    for z in (0.974, 0.990):
        for index in range(segments):
            angle = 2.0 * pi * index / segments
            radial = Vector((cos(angle), sin(angle), 0.0))
            backness = max(0.0, radial.y)
            # High-backed support curve: the front remains at its accepted
            # height, while the rear rises 46 mm to cover the upper glute cleft.
            waist_lift = 0.046 * backness ** 1.7
            sample_z = z + waist_lift
            origin = Vector((radial.x * 0.55, radial.y * 0.55, sample_z))
            hit = tree.ray_cast(origin, -radial, 1.0)
            surface = hit[0] if hit[0] is not None else Vector((radial.x * 0.16, radial.y * 0.13, sample_z))
            # Proud enough to conceal the fitted seat layer's irregular
            # topology boundary; this is the visible finished waistband.
            point = surface + radial * 0.0068
            point.z = sample_z
            vertices.append(tuple(point))
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    mesh = bpy.data.meshes.new("Loincloth.WaistCord.Refined.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(cord_material)
    mesh.update()
    cord = bpy.data.objects.new("Loincloth.WaistCord.Refined", mesh)
    bpy.context.collection.objects.link(cord)
    solid = cord.modifiers.new("CordBody", "SOLIDIFY")
    solid.thickness = 0.0030
    solid.offset = 0.0
    bevel = cord.modifiers.new("CordRoundness", "BEVEL")
    bevel.width = 0.0015
    bevel.segments = 3
    rigid_bone_parent(cord, rig, "pelvis")

    # A small tied knot and two cord tails make the support construction
    # readable; every piece touches the fitted waist cord at the left hip.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.010, location=(-0.143, -0.055, 0.994))
    knot = bpy.context.object
    knot.name = "Loincloth.HipKnot.Refined"
    knot.scale = (1.0, 0.70, 1.0)
    knot.data.materials.append(cord_material)
    bpy.context.view_layer.objects.active = knot
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    rigid_bone_parent(knot, rig, "pelvis")
    for index, points in enumerate((
        ((-0.143, -0.055, 0.991), (-0.151, -0.061, 0.958), (-0.145, -0.058, 0.924)),
        ((-0.140, -0.053, 0.990), (-0.133, -0.062, 0.956), (-0.137, -0.060, 0.932)),
    )):
        curve_data = bpy.data.curves.new(f"Loincloth.TieTail.{index}.Refined.Curve", "CURVE")
        curve_data.dimensions = "3D"
        curve_data.bevel_depth = 0.0018
        curve_data.bevel_resolution = 2
        spline = curve_data.splines.new("BEZIER")
        spline.bezier_points.add(len(points) - 1)
        for point, coordinate in zip(spline.bezier_points, points):
            point.co = coordinate
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        tail = bpy.data.objects.new(f"Loincloth.TieTail.{index}.Refined", curve_data)
        bpy.context.collection.objects.link(tail)
        curve_data.materials.append(cord_material)
        rigid_bone_parent(tail, rig, "pelvis")
    return front, back, seat, cord


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def key_pose(rig, frame, transforms):
    reset_pose(rig)
    for name, values in transforms.items():
        bone = rig.pose.bones.get(name)
        if bone is None:
            continue
        if "rot" in values:
            bone.rotation_euler = tuple(radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
    for bone in rig.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def make_action(rig, name, frames, length):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame, transforms in frames:
        key_pose(rig, frame, transforms)
    action.frame_start = 1
    action.frame_end = length
    action.use_frame_range = True
    action.use_cyclic = True
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    if bag.slot_handle == slot.handle:
                        for curve in bag.fcurves:
                            for point in curve.keyframe_points:
                                point.interpolation = "BEZIER"
    return action


def restrained_walk_frames():
    def phase(lt, rt, lk, rk, lf, rf, ltoe, rtoe, la, ra, le, re, height, twist, shift):
        return {
            "root": {"loc": (0.0, 0.0, height)},
            "pelvis": {"loc": (shift, 0.0, 0.0), "rot": (0.7, 1.4 * twist, 0.8 * twist)},
            "spine": {"rot": (0.65, -0.35 * twist, -0.25 * twist)},
            "chest": {"rot": (0.45, -0.90 * twist, -0.35 * twist)},
            "neck": {"rot": (-0.25, 0.12 * twist, 0.06 * twist)},
            "head": {"rot": (-0.35, 0.10 * twist, -0.04 * twist)},
            "thigh.L": {"rot": (lt, 0.0, 0.48 * lt)},
            "thigh.R": {"rot": (rt, 0.0, -0.48 * rt)},
            "shin.L": {"rot": (lk, 0.0, 0.0)}, "shin.R": {"rot": (rk, 0.0, 0.0)},
            "foot.L": {"rot": (lf, 0.0, 0.0)}, "foot.R": {"rot": (rf, 0.0, 0.0)},
            "toe.L": {"rot": (ltoe, 0.0, 0.0)}, "toe.R": {"rot": (rtoe, 0.0, 0.0)},
            "upper_arm.L": {"rot": (la, 0.0, 19.0)}, "upper_arm.R": {"rot": (ra, 0.0, -19.0)},
            "forearm.L": {"rot": (le, 0.0, 4.0)}, "forearm.R": {"rot": (re, 0.0, -4.0)},
            "hand.L": {"rot": (-1.0 + 0.05 * la, -0.5, 1.0)},
            "hand.R": {"rot": (1.0 + 0.05 * ra, 0.5, -1.0)},
        }

    # Arms counter-swing the legs.  The previous ipsilateral motion was the
    # principal robotic tell; the swing knee now flexes enough to clear its toe
    # during passing and up poses.
    left_contact = phase(-9, 13, 3, 15, -5, 8, 0, 8, 13, -11, 14, 14, 0.002, 1.0, -0.002)
    left_down = phase(-7, 9, 7, 15, -1, 9, 1, 10, 10, -8, 16, 15, -0.0015, 0.65, -0.003)
    left_pass = phase(1, -1, 6, 30, 2, -5, 3, 2, 2, -2, 14, 18, 0.003, 0.0, -0.0008)
    left_up = phase(6, -7, 5, 35, 7, -7, 7, 1, -9, 11, 14, 20, 0.005, -0.65, 0.002)
    right_contact = phase(13, -9, 15, 3, 8, -5, 8, 0, -11, 13, 14, 14, 0.002, -1.0, 0.002)
    right_down = phase(9, -7, 15, 7, 9, -1, 10, 1, -8, 10, 15, 16, -0.0015, -0.65, 0.003)
    right_pass = phase(-1, 1, 30, 6, -5, 2, 2, 3, -2, 2, 18, 14, 0.003, 0.0, 0.0008)
    right_up = phase(-7, 6, 35, 5, -7, 7, 1, 7, 11, -9, 20, 14, 0.005, 0.65, -0.002)
    return (
        (1, left_contact), (4, left_down), (7, left_pass), (10, left_up),
        (13, right_contact), (16, right_down), (19, right_pass), (22, right_up),
        (25, left_contact),
    )


def ground_action(rig, body, action):
    rig.animation_data.action = action
    root = rig.pose.bones["root"]
    scene = bpy.context.scene
    for frame in range(1, 26):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        minimum = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)
        root.location.z -= minimum
        root.keyframe_insert("location", frame=frame, group=root.name)


def rebuild_walk(body, rig):
    names = {"Walk", "TorchWalk", "StaffWalk", "WarriorWalk"}
    for track in list(rig.animation_data.nla_tracks):
        if track.name in names:
            rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    for action in list(bpy.data.actions):
        if action.name in names:
            bpy.data.actions.remove(action)
    walk = make_action(rig, "Walk", restrained_walk_frames(), 25)
    ground_action(rig, body, walk)
    actions = [walk]
    for name in ("TorchWalk", "StaffWalk", "WarriorWalk"):
        alias = walk.copy()
        alias.name = name
        actions.append(alias)
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_start), action)
        track.mute = True
    rig.animation_data.action = None
    reset_pose(rig)
    bpy.context.scene.frame_set(0)
    return walk


def export(rig):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and (
            obj.name == "ConnectedBody"
            or obj.name.startswith(("Professional", "HeroHair", "Loincloth.", "RoyalArmor_", "RoyalStaff_"))
        ):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB, export_format="GLB", use_selection=True, export_apply=False,
        export_animations=True, export_nla_strips=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=True,
        export_materials="EXPORT", export_cameras=False, export_lights=False, export_yup=True,
    )


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    rig.data.pose_position = "POSE"
    before = body_digest(body)
    rebuild_hair(body, rig)
    rebuild_brows(body, rig)
    rebuild_loincloth(body, rig)
    # The accepted locomotion is intentionally left untouched by this visual
    # layer correction. The master already contains the non-freezing Walk.
    after = body_digest(body)
    if before != after:
        raise RuntimeError("Accepted ConnectedBody changed during layer-only refinement")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"LAYER_REFINEMENT_DONE|body_sha256={after}|blend={OUTPUT_BLEND}|glb={OUTPUT_GLB}")


if __name__ == "__main__":
    main()
