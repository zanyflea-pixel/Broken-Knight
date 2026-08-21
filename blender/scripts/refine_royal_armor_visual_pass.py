"""Forge the editable Royal Vanguard armor into a more cohesive knightly set.

This pass replaces only outer armor shells. The accepted hero body, rig,
weights, animations, staff, materials, and deformation-safe underlayers remain
untouched. All dimensions are grouped near the top-level builder functions so
the armor can be adjusted without hunting through unrelated hero code.
"""

import math
import os

import bpy
from mathutils import Euler, Matrix, Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MASTER = os.path.abspath(os.environ.get(
    "BK_ARMOR_OUTPUT_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_Master.blend"),
))
REFERENCE_ARMOR = os.path.abspath(os.environ.get(
    "BK_ARMOR_REFERENCE_BLEND",
    os.path.join(ROOT, "blender", "royal_armor_apex_editable_shoulders_improved.blend"),
))
PASS_ID = "RoyalArmor_LockedBodySovereignPanoply_2026_08_13"
REFERENCE_FULL_BODY = os.path.join(
    ROOT, "blender", "references", "royal_armor_splash_target",
    "broken_knight_royal_armor_full_body_v1.png",
)
REFERENCE_FACE = os.path.join(
    ROOT, "blender", "references", "royal_armor_splash_target",
    "broken_knight_hero_face_v1.png",
)

COLLECTIONS = {
    "head": "10A_ARMOR_HEAD",
    "chest": "10B_ARMOR_CHEST",
    "shoulders": "10C_ARMOR_SHOULDERS",
    "hands": "10D_ARMOR_HANDS",
    "pants": "10E_ARMOR_PANTS",
    "feet": "10F_ARMOR_FEET",
}


def ensure_build_prerequisites():
    """Bootstrap the accepted unarmored master without importing an old body."""
    if not os.path.exists(REFERENCE_ARMOR):
        raise RuntimeError(f"Armor reference file is missing: {REFERENCE_ARMOR}")
    required_materials = {
        "Royal Blued Steel", "Royal Planished Edge Steel", "Royal Blackened Steel",
        "Royal Gilt Brass", "Royal Cobalt Filigree Plate", "Helmet Interior",
        "Ducal Crimson Horsehair", "Ducal Horsehair Shadow", "Riveted Mail",
        "Harness Leather",
    }
    missing = sorted(name for name in required_materials if bpy.data.materials.get(name) is None)
    if missing:
        with bpy.data.libraries.load(REFERENCE_ARMOR, link=False) as (data_from, data_to):
            data_to.materials = [name for name in missing if name in data_from.materials]
    still_missing = sorted(name for name in required_materials if bpy.data.materials.get(name) is None)
    if still_missing:
        raise RuntimeError(f"Armor materials could not be bootstrapped: {still_missing}")

    root_collection = bpy.data.collections.get("10_ROYAL_ARMOR")
    if root_collection is None:
        root_collection = bpy.data.collections.new("10_ROYAL_ARMOR")
        bpy.context.scene.collection.children.link(root_collection)
    for collection_name in COLLECTIONS.values():
        collection = bpy.data.collections.get(collection_name)
        if collection is None:
            collection = bpy.data.collections.new(collection_name)
            root_collection.children.link(collection)


ensure_build_prerequisites()


def mat(name):
    material = bpy.data.materials.get(name)
    if material is None:
        raise RuntimeError(f"Required armor material was not found: {name}")
    return material


STEEL = mat("Royal Blued Steel")
BRIGHT = mat("Royal Planished Edge Steel")
DARK = mat("Royal Blackened Steel")
BRASS = mat("Royal Gilt Brass")
COBALT = mat("Royal Cobalt Filigree Plate")
BLACK = mat("Helmet Interior")
CRIMSON = mat("Ducal Crimson Horsehair")
CRIMSON_DARK = bpy.data.materials.get("Ducal Horsehair Shadow") or CRIMSON
MAIL = mat("Riveted Mail")

ARM = bpy.data.objects.get("HeroRig")
if ARM is None:
    raise RuntimeError("HeroRig was not found")


def remove_object(name):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)


def remove_prefix(prefix):
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefix):
            bpy.data.objects.remove(obj, do_unlink=True)


def link_only(obj, slot):
    destination = bpy.data.collections.get(COLLECTIONS[slot])
    if destination is None:
        raise RuntimeError(f"Armor collection is missing: {COLLECTIONS[slot]}")
    if destination.objects.get(obj.name) is None:
        destination.objects.link(obj)
    for collection in list(obj.users_collection):
        if collection != destination:
            collection.objects.unlink(obj)


def skin_uniform(obj, weights):
    """Attach an authored rigid/fractional plate to named deformation bones."""
    if isinstance(weights, str):
        weights = {weights: 1.0}
    total = sum(weights.values())
    if total <= 0:
        raise ValueError("Armor weights must have a positive total")
    indices = list(range(len(obj.data.vertices)))
    for bone, value in weights.items():
        group = obj.vertex_groups.new(name=bone)
        group.add(indices, value / total, "REPLACE")
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = ARM
    obj.parent = ARM


def skin_tasset(obj, thigh_bone):
    pelvis = obj.vertex_groups.new(name="pelvis")
    thigh = obj.vertex_groups.new(name=thigh_bone)
    for vertex in obj.data.vertices:
        height = max(0.0, min(1.0, (vertex.co.z - 0.62) / 0.34))
        pelvis_weight = 0.10 + 0.58 * height
        thigh_weight = 1.0 - pelvis_weight
        pelvis.add([vertex.index], pelvis_weight, "REPLACE")
        thigh.add([vertex.index], thigh_weight, "REPLACE")
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = ARM
    obj.parent = ARM


def remap_appended_materials(obj):
    """Reuse canonical materials instead of leaving .001 library duplicates."""
    for index, material in enumerate(obj.data.materials):
        if material is None:
            continue
        base_name = material.name
        if len(base_name) > 4 and base_name[-4] == "." and base_name[-3:].isdigit():
            base_name = base_name[:-4]
        canonical = bpy.data.materials.get(base_name)
        if canonical is not None and canonical != material:
            obj.data.materials[index] = canonical


def attach_appended_plate(obj, slot, rigid_bone=None):
    """Move an authored reference plate onto the canonical rig and collection."""
    link_only(obj, slot)
    remap_appended_materials(obj)
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    obj.parent = ARM
    if rigid_bone:
        obj.vertex_groups.clear()
        skin_uniform(obj, rigid_bone)
    else:
        modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
        modifier.object = ARM
    obj["bk_edit_group"] = slot
    obj["bk_visual_pass"] = PASS_ID
    obj["bk_editable"] = True


def append_reference_objects(predicate, slot, rigid_bone=None):
    """Append selected editable pieces from the previous authored armor set."""
    if not os.path.exists(REFERENCE_ARMOR):
        raise RuntimeError(f"Armor reference file is missing: {REFERENCE_ARMOR}")
    with bpy.data.libraries.load(REFERENCE_ARMOR, link=False) as (data_from, data_to):
        names = [name for name in data_from.objects if predicate(name)]
        data_to.objects = names
    result = []
    for obj in data_to.objects:
        if obj is None or obj.type != "MESH":
            continue
        attach_appended_plate(obj, slot, rigid_bone=rigid_bone)
        result.append(obj)
    return result


def bootstrap_reference_harness():
    """Bring the fitted underlayers onto the locked hero before rebuilding.

    The accepted body master intentionally contains no armor.  Appending only
    RoyalArmor-prefixed objects preserves that body while supplying the fitted
    greaves, sabatons, gauntlets, mail voids and other deformation-safe layers
    which the sovereign outer-shell builders refine or replace below.
    """
    if any(obj.name.startswith("RoyalArmor_") for obj in bpy.data.objects):
        return
    with bpy.data.libraries.load(REFERENCE_ARMOR, link=False) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name.startswith("RoyalArmor_")]
    imported = 0
    for obj in data_to.objects:
        if obj is None or obj.type != "MESH":
            continue
        remainder = obj.name[len("RoyalArmor_"):]
        slot = remainder.split("_", 1)[0]
        if slot not in COLLECTIONS:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        attach_appended_plate(obj, slot)
        imported += 1
    if imported < 100:
        raise RuntimeError(f"Reference harness bootstrap was incomplete: {imported}")
    print(f"ROYAL_ARMOR_BOOTSTRAP|objects={imported}|reference={REFERENCE_ARMOR}")


def refine_horsehair_material():
    """Give the crest a dry fibrous surface instead of polished plastic."""
    CRIMSON.use_nodes = True
    nodes = CRIMSON.node_tree.nodes
    links = CRIMSON.node_tree.links
    for node in list(nodes):
        if node.name.startswith("BK_Horsehair"):
            nodes.remove(node)
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    bsdf.inputs["Roughness"].default_value = 0.68
    coordinates = nodes.new("ShaderNodeTexCoord")
    coordinates.name = "BK_HorsehairCoordinates"
    noise = nodes.new("ShaderNodeTexNoise")
    noise.name = "BK_HorsehairNoise"
    noise.inputs["Scale"].default_value = 72.0
    noise.inputs["Detail"].default_value = 3.0
    noise.inputs["Roughness"].default_value = 0.72
    bump = nodes.new("ShaderNodeBump")
    bump.name = "BK_HorsehairBump"
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.018
    links.new(coordinates.outputs["Generated"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def refine_mail_material():
    """Make articulated joint protection read as blackened mail, not gaps."""
    MAIL.diffuse_color = (0.012, 0.018, 0.030, 1.0)
    MAIL.use_nodes = True
    bsdf = next(
        (node for node in MAIL.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if bsdf is None:
        return
    bsdf.inputs["Base Color"].default_value = (0.012, 0.018, 0.030, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.42
    bsdf.inputs["Roughness"].default_value = 0.66

    leather = bpy.data.materials.get("Harness Leather")
    if leather is not None:
        leather.diffuse_color = (0.028, 0.016, 0.012, 1.0)
        leather.use_nodes = True
        leather_bsdf = next(
            (node for node in leather.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
            None,
        )
        if leather_bsdf is not None:
            leather_bsdf.inputs["Base Color"].default_value = (0.028, 0.016, 0.012, 1.0)
            leather_bsdf.inputs["Roughness"].default_value = 0.68


def mesh_object(
    slot,
    part,
    vertices,
    faces,
    materials,
    weights,
    bevel=0.0,
    bevel_segments=2,
    solidify=0.0,
    smooth=False,
    custom_skin=None,
):
    name = f"RoyalArmor_{slot}_{part}"
    remove_object(name)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    link_only(obj, slot)
    for material in materials:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    if custom_skin:
        custom_skin(obj)
    else:
        skin_uniform(obj, weights)
    if solidify > 0:
        modifier = obj.modifiers.new("ForgedThickness", "SOLIDIFY")
        modifier.thickness = solidify
        modifier.offset = -1.0
    if bevel > 0:
        modifier = obj.modifiers.new("RolledForgedEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = bevel_segments
    obj["bk_edit_group"] = slot
    obj["bk_visual_pass"] = PASS_ID
    obj["bk_editable"] = True
    return obj


def make_box(slot, part, location, size, material, bone, rotation=(0.0, 0.0, 0.0), bevel=0.002):
    hx, hy, hz = (value * 0.5 for value in size)
    local = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
        (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
    ]
    transform = Matrix.Translation(Vector(location)) @ Euler(rotation).to_matrix().to_4x4()
    vertices = [transform @ Vector(point) for point in local]
    faces = [
        (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
        (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7),
    ]
    return mesh_object(slot, part, vertices, faces, [material], bone, bevel=bevel, bevel_segments=3)


def make_cylinder_x(slot, part, center, radius, depth, material, bone, segments=24):
    vertices = []
    for x in (-depth * 0.5, depth * 0.5):
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((center[0] + x, center[1] + radius * math.cos(angle), center[2] + radius * math.sin(angle)))
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple(segments + index for index in range(segments)))
    return mesh_object(slot, part, vertices, faces, [material], bone, bevel=0.0015, bevel_segments=2, smooth=True)


def build_helmet():
    """Angular close helmet with integrated visor, brow and nasal keel."""
    remove_prefix("RoyalArmor_head_")
    helmet_parts = append_reference_objects(
        lambda name: name.startswith("RoyalArmor_head_Apex") and not any(
            token in name for token in ("Horsehair", "CrestComb", "CrestGiltRail")
        ),
        "head", rigid_bone="head",
    )
    # One connected longitudinal crest replaces both the old disconnected
    # spikes and the rejected transverse slab. Its side profile flows rearward
    # while the thicker root gives it readable volume from the front.
    plume_outline = [
        (-0.105, 1.930), (-0.098, 2.020), (-0.060, 2.103),
        (0.005, 2.148), (0.080, 2.130), (0.154, 2.070),
        (0.204, 1.986), (0.148, 1.940),
    ]
    vertices = []
    half_widths = (0.052, 0.060, 0.050, 0.026, 0.030, 0.024, 0.018, 0.038)
    for side in (-1.0, 1.0):
        vertices.extend((side * width, y, z) for (y, z), width in zip(plume_outline, half_widths))
    count = len(plume_outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    plume = mesh_object(
        "head", "ApexConnectedHorsehairCrest", vertices, faces,
        [CRIMSON, CRIMSON_DARK], "head", bevel=0.010, bevel_segments=4,
    )
    for polygon in plume.data.polygons:
        polygon.material_index = 1 if polygon.index in (2, 5, 6) else 0
    plume["bk_edit_note"] = "Edit side-profile vertices to reshape the plume"
    refine_horsehair_material()
    make_box(
        "head", "ApexEmbeddedCrestComb", (0.0, 0.035, 1.931),
        (0.116, 0.286, 0.030), DARK, "head", bevel=0.007,
    )
    make_box(
        "head", "ApexEmbeddedCrestRail", (0.0, 0.035, 1.941),
        (0.132, 0.274, 0.013), BRASS, "head", bevel=0.004,
    )
    return
    segments = 48
    rings = [
        # z, half width, front depth, rear depth, exponent
        (1.520, 0.166, 0.145, 0.146, 2.45),
        (1.548, 0.160, 0.151, 0.143, 2.50),
        (1.585, 0.145, 0.164, 0.137, 2.55),
        (1.625, 0.144, 0.176, 0.132, 2.62),
        (1.675, 0.150, 0.181, 0.130, 2.66),
        (1.720, 0.156, 0.180, 0.129, 2.62),
        (1.746, 0.160, 0.176, 0.128, 2.58),
        (1.755, 0.161, 0.171, 0.127, 2.54),
        (1.772, 0.161, 0.171, 0.126, 2.48),
        (1.781, 0.161, 0.178, 0.125, 2.42),
        (1.808, 0.160, 0.166, 0.124, 2.34),
        (1.840, 0.156, 0.149, 0.122, 2.22),
        (1.874, 0.145, 0.135, 0.118, 2.10),
        (1.898, 0.128, 0.116, 0.108, 2.02),
        (1.919, 0.096, 0.082, 0.080, 2.00),
        (1.932, 0.052, 0.044, 0.044, 2.00),
        (1.938, 0.010, 0.009, 0.010, 2.00),
    ]
    vertices = []
    for z, half_x, front, rear, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear if sine >= 0 else front
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            vertex_z = z
            if sine < 0:
                frontness = abs(sine) ** 7
                center_keel = max(0.0, 1.0 - abs(x) / 0.026)
                cheek_recess = max(0.0, min(1.0, (abs(x) - 0.055) / 0.070))
                if 1.585 <= z <= 1.815:
                    y -= 0.012 * center_keel * frontness
                    y += 0.006 * cheek_recess * frontness
                if 1.772 <= z <= 1.815:
                    y -= 0.008 * max(0.0, 1.0 - abs(x) / 0.135) * frontness
                if 1.585 <= z <= 1.655:
                    y -= 0.008 * max(0.0, 1.0 - abs(x) / 0.080) * frontness
            vertices.append((x, y, z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            a = row * segments + column
            b = row * segments + nxt
            c = (row + 1) * segments + nxt
            d = (row + 1) * segments + column
            faces.append((a, b, c, d))
    faces.append(tuple((len(rings) - 1) * segments + column for column in range(segments)))
    helmet = mesh_object(
        "head", "ApexUnifiedHelmetShell", vertices, faces,
        [STEEL, COBALT, DARK, BRASS, BLACK, BRIGHT], "head",
        bevel=0.0024, bevel_segments=3, solidify=0.010, smooth=True,
    )
    for polygon in helmet.data.polygons[:-1]:
        row = polygon.index // segments
        column = polygon.index % segments
        z0 = rings[row][0]
        z1 = rings[row + 1][0]
        zmid = (z0 + z1) * 0.5
        angle = math.tau * (column + 0.5) / segments
        front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
        back_delta = abs((angle - 0.5 * math.pi + math.pi) % math.tau - math.pi)
        index = 0
        if front_delta < 0.82 and 1.585 < zmid < 1.840:
            index = 1
        if front_delta < 0.78 and 1.755 < zmid < 1.772:
            index = 4
        elif front_delta < 0.80 and (1.746 < zmid < 1.755 or 1.772 < zmid < 1.781):
            index = 3
        elif 0.78 < front_delta < 1.14 and 1.610 < zmid < 1.825:
            index = 2
        elif back_delta < 0.82 and zmid < 1.850:
            index = 2
        if front_delta < 0.030 and 1.585 < zmid < 1.825:
            index = 3
        if zmid < 1.585:
            index = 3 if row in (0, 2) else (2 if row == 1 else 0)
        polygon.material_index = index
        if front_delta < 0.86 and zmid < 1.840:
            polygon.use_smooth = False

    # A transverse, connected horsehair fan reads clearly from the gameplay
    # camera while retaining the requested Roman/ducal crest character.
    plume_outline = [
        (-0.210, 1.930), (-0.198, 2.012), (-0.160, 2.092),
        (-0.092, 2.151), (0.000, 2.174), (0.092, 2.151),
        (0.160, 2.092), (0.198, 2.012), (0.210, 1.930),
        (0.155, 1.942), (-0.155, 1.942),
    ]
    vertices = []
    half_thickness = 0.026
    for y in (-half_thickness, half_thickness):
        vertices.extend((x, y + 0.020, z) for x, z in plume_outline)
    count = len(plume_outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    plume = mesh_object(
        "head", "ApexUnifiedHorsehair0", vertices, faces,
        [CRIMSON, CRIMSON_DARK], "head", bevel=0.006, bevel_segments=3,
    )
    for polygon in plume.data.polygons:
        polygon.material_index = 1 if polygon.index in (2, 6) else 0

    make_box("head", "ApexUnifiedCrestComb", (0.0, 0.020, 1.931), (0.365, 0.072, 0.030), DARK, "head", bevel=0.007)
    make_box("head", "ApexEmbeddedCrestRail", (0.0, 0.018, 1.941), (0.385, 0.082, 0.014), BRASS, "head", bevel=0.004)

    # Reinforcing brow and lower-bevor edges break up the bucket silhouette.
    brow_vertices = [
        (-0.145, -0.176, 1.792), (0.145, -0.176, 1.792),
        (0.132, -0.181, 1.772), (-0.132, -0.181, 1.772),
        (-0.145, -0.169, 1.792), (0.145, -0.169, 1.792),
        (0.132, -0.174, 1.772), (-0.132, -0.174, 1.772),
    ]
    brow_faces = [
        (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
        (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0),
    ]
    mesh_object(
        "head", "ApexIntegratedBrowReinforce", brow_vertices, brow_faces,
        [BRIGHT], "head", bevel=0.0020, bevel_segments=3,
    )

    # Flush visor ventilation and pivots provide readable function at game scale.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        for index, (x_abs, z) in enumerate(((0.052, 1.666), (0.080, 1.646), (0.106, 1.626)), start=1):
            make_box(
                "head", f"ApexVisorVent{suffix}{index}",
                (side * x_abs, -0.181, z), (0.030, 0.006, 0.008),
                BLACK, "head", rotation=(0.0, 0.0, side * math.radians(8.0)), bevel=0.0015,
            )
        make_cylinder_x(
            "head", f"ApexVisorPivot{suffix}",
            (side * 0.155, -0.004, 1.742), 0.024, 0.009,
            BRASS, "head",
        )


def build_unified_connected_helmet():
    """Build one continuous close-helmet silhouette with no floating face parts."""
    remove_prefix("RoyalArmor_head_")
    segments = 96
    rings = [
        # z, half width, front depth, rear depth, cross-section exponent
        (1.515, 0.126, 0.150, 0.180, 2.70),
        (1.545, 0.139, 0.170, 0.174, 2.76),
        (1.585, 0.150, 0.190, 0.162, 2.72),
        (1.615, 0.154, 0.194, 0.153, 2.69),
        (1.630, 0.156, 0.196, 0.148, 2.67),
        (1.635, 0.157, 0.197, 0.146, 2.66),
        (1.648, 0.159, 0.196, 0.140, 2.65),
        (1.661, 0.160, 0.197, 0.139, 2.63),
        (1.674, 0.162, 0.198, 0.139, 2.62),
        (1.687, 0.163, 0.198, 0.138, 2.61),
        (1.695, 0.164, 0.198, 0.138, 2.60),
        (1.735, 0.165, 0.196, 0.136, 2.56),
        (1.748, 0.165, 0.199, 0.135, 2.54),
        (1.759, 0.165, 0.188, 0.134, 2.52),
        (1.771, 0.164, 0.205, 0.133, 2.50),
        (1.792, 0.160, 0.187, 0.131, 2.44),
        (1.835, 0.153, 0.163, 0.128, 2.34),
        (1.875, 0.144, 0.146, 0.123, 2.22),
        (1.910, 0.121, 0.121, 0.111, 2.10),
        (1.932, 0.083, 0.080, 0.078, 2.02),
        (1.943, 0.035, 0.034, 0.035, 2.00),
        (1.947, 0.006, 0.006, 0.006, 2.00),
    ]
    vertices = []
    for z, half_x, front, rear, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear if sine >= 0 else front
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            vertex_z = z
            if sine < 0:
                frontness = abs(sine) ** 7
                nasal = max(0.0, 1.0 - abs(x) / 0.025)
                cheek = max(0.0, 1.0 - abs(abs(x) - 0.090) / 0.052)
                lower_face = max(0.0, min(1.0, (1.670 - z) / 0.145))
                chin = math.exp(-((x / 0.070) ** 2)) * lower_face
                jaw_recess = math.exp(-(((abs(x) - 0.105) / 0.034) ** 2)) * lower_face
                y -= 0.046 * chin * frontness
                y += 0.010 * jaw_recess * frontness
                if 1.585 <= z <= 1.792:
                    y -= 0.018 * nasal * frontness
                    y += 0.006 * cheek * frontness
                if 1.735 <= z <= 1.792:
                    y -= 0.007 * max(0.0, 1.0 - abs(x) / 0.140) * frontness
                if 1.585 <= z <= 1.650:
                    y -= 0.008 * max(0.0, 1.0 - abs(x) / 0.078) * frontness
                # Lift the lower side edges while leaving the center low. The
                # resulting continuous V-shaped bevor replaces the bucket-like
                # horizontal helmet hem.
                chin_edge = max(0.0, min(1.0, (1.600 - z) / 0.085))
                vertex_z += 0.052 * ((abs(x) / 0.150) ** 1.55) * chin_edge * frontness
            if z > 1.800:
                crown_fade = max(0.0, math.sin(max(0.0, min(1.0, (z - 1.800) / 0.147)) * math.pi))
                crown_flute = 0.0075 * (0.5 + 0.5 * math.cos(angle * 6.0)) * crown_fade
                radial_length = max(1e-6, math.hypot(x, y))
                x += crown_flute * x / radial_length
                y += crown_flute * y / radial_length
            vertices.append((x, y, vertex_z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((
                row * segments + column,
                row * segments + nxt,
                (row + 1) * segments + nxt,
                (row + 1) * segments + column,
            ))
    faces.append(tuple((len(rings) - 1) * segments + column for column in range(segments)))
    helmet = mesh_object(
        "head", "ApexUnifiedConnectedHelmet", vertices, faces,
        [STEEL, COBALT, DARK, BRASS, BLACK, BRIGHT], "head",
        bevel=0.0026, bevel_segments=3, solidify=0.010, smooth=True,
    )
    for polygon in helmet.data.polygons[:-1]:
        row = polygon.index // segments
        column = polygon.index % segments
        zmid = (rings[row][0] + rings[row + 1][0]) * 0.5
        angle = math.tau * (column + 0.5) / segments
        front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
        back_delta = abs((angle - 0.5 * math.pi + math.pi) % math.tau - math.pi)
        center = polygon.center
        material_index = 1 if zmid >= 1.805 else 0
        if front_delta < 0.88 and zmid < 1.835:
            material_index = 1
            polygon.use_smooth = False
        if front_delta < 0.78 and 1.585 < zmid < 1.735:
            cheek_boundary = 0.126 + 0.008 * max(0.0, min(1.0, (zmid - 1.585) / 0.150))
            if abs(center.x) > cheek_boundary:
                material_index = 2
        if 1.748 <= zmid <= 1.765 and front_delta < 0.78:
            material_index = 4
        elif front_delta < 0.045 and 1.585 <= zmid <= 1.792:
            material_index = 5
        elif 0.80 < front_delta < 1.16 and zmid < 1.820:
            material_index = 2
        elif back_delta < 0.90 and zmid < 1.820:
            material_index = 1
        if row == 0:
            material_index = 3
        # Ventilation is part of the visor surface through material zoning;
        # there are no separate boxes hovering in front of the face.
        vent_row = any(abs(zmid - target) < 0.006 for target in (1.642, 1.668))
        if front_delta < 0.62 and vent_row:
            if any(abs(abs(center.x) - target) < 0.010 for target in (0.046, 0.078, 0.110)):
                material_index = 4
        # Narrow gilt brow roll assigned to the unified helmet surface. This
        # provides a readable royal accent without another visor attachment.
        if 1.771 <= zmid <= 1.792 and front_delta < 0.78:
            material_index = 3
        if zmid >= 1.805:
            if front_delta < 0.070 or back_delta < 0.060:
                material_index = 3
            elif 0.48 < front_delta < 0.59 or 0.48 < back_delta < 0.59:
                material_index = 2
        polygon.material_index = material_index

    # The crest is built from overlapping closed feather locks instead of one
    # inflated slab. Every lock begins below the crown surface, so the entire
    # plume has a continuous embedded root while its upper silhouette separates
    # into readable swept horsehair layers.
    plume_vertices = []
    plume_faces = []
    plume_face_materials = []
    # Dense offset locks remove the old comb/cake silhouette.  Each lock is a
    # closed overlapping ribbon with an embedded root; alternating lateral
    # offsets break the repeated vertical-stripe read from front and rear.
    x_centers = (
        -0.038, -0.029, -0.020, -0.011, -0.002, 0.007, 0.016, 0.025, 0.034,
        -0.033, -0.024, -0.015, -0.006, 0.003, 0.012, 0.021, 0.030,
    )
    for blade_index, x_center in enumerate(x_centers):
        layer = blade_index % 9
        root_y = -0.116 + 0.027 * layer + (0.010 if blade_index >= 9 else 0.0)
        height_bias = 0.020 * math.sin(math.pi * blade_index / (len(x_centers) - 1))
        lateral_sweep = 0.008 * math.sin(blade_index * 1.71)
        path = (
            (root_y, 1.902),
            (root_y - 0.004, 1.968),
            (root_y + 0.004, 2.035 + height_bias * 0.35),
            (root_y + 0.026, 2.112 + height_bias),
            (root_y + 0.074, 2.150 + height_bias * 0.55),
            (root_y + 0.130, 2.112 + height_bias * 0.20),
            (root_y + 0.181, 2.025 - 0.0025 * layer),
        )
        widths = (0.016, 0.019, 0.020, 0.018, 0.014, 0.008, 0.0028)
        thicknesses = (0.015, 0.017, 0.018, 0.016, 0.012, 0.007, 0.0028)
        blade_start = len(plume_vertices)
        for point_index, ((y, z), width, thickness) in enumerate(zip(path, widths, thicknesses)):
            previous = path[max(0, point_index - 1)]
            following = path[min(len(path) - 1, point_index + 1)]
            tangent_y = following[0] - previous[0]
            tangent_z = following[1] - previous[1]
            tangent_length = max(1e-6, math.hypot(tangent_y, tangent_z))
            normal_y = -tangent_z / tangent_length
            normal_z = tangent_y / tangent_length
            plume_vertices.extend((
                (x_center + lateral_sweep * point_index / (len(path) - 1) - width, y + normal_y * thickness, z + normal_z * thickness),
                (x_center + lateral_sweep * point_index / (len(path) - 1) + width, y + normal_y * thickness, z + normal_z * thickness),
                (x_center + lateral_sweep * point_index / (len(path) - 1) + width, y - normal_y * thickness, z - normal_z * thickness),
                (x_center + lateral_sweep * point_index / (len(path) - 1) - width, y - normal_y * thickness, z - normal_z * thickness),
            ))
        for point_index in range(len(path) - 1):
            a = blade_start + point_index * 4
            b = a + 4
            plume_faces.extend((
                (a, a + 1, b + 1, b),
                (a + 1, a + 2, b + 2, b + 1),
                (a + 2, a + 3, b + 3, b + 2),
                (a + 3, a, b, b + 3),
            ))
            plume_face_materials.extend((blade_index % 2, blade_index % 2, 1, blade_index % 2))
        plume_faces.append(tuple(blade_start + offset for offset in (3, 2, 1, 0)))
        plume_face_materials.append(2)
        tip = blade_start + (len(path) - 1) * 4
        plume_faces.append(tuple(tip + offset for offset in (0, 1, 2, 3)))
        plume_face_materials.append(blade_index % 2)
    plume = mesh_object(
        "head", "ApexUnifiedConnectedPlume", plume_vertices, plume_faces,
        [CRIMSON, CRIMSON_DARK, BRASS], "head", bevel=0.0035, bevel_segments=3,
        smooth=True,
    )
    for polygon, material_index in zip(plume.data.polygons, plume_face_materials):
        polygon.material_index = material_index
    refine_horsehair_material()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in (helmet, plume):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = helmet
    bpy.ops.object.join()
    helmet.name = "RoyalArmor_head_ApexUnifiedConnectedHelmet"
    helmet.data.name = helmet.name + "_Mesh"
    helmet["bk_edit_note"] = "Single joined helmet and embedded closed crest; no floating face pieces"


def build_unified_gorget_mantle():
    """Cover the complete neck/shoulder junction with one interlocked gorget."""
    remove_object("RoyalArmor_chest_ApexClosedGorget")
    remove_object("RoyalArmor_chest_ApexUnifiedGorgetMantle")
    remove_prefix("RoyalArmor_shoulders_ApexLateralShoulderBridge")

    segments = 64
    vertices = []
    faces = []
    material_indices = []

    def add_face(indices, material_index=0):
        faces.append(tuple(indices))
        material_indices.append(material_index)

    # High closed collar. Its lower half penetrates the breast/back plates and
    # its inner wall overlaps the helmet skirt, removing the exposed neck seam.
    collar_start = len(vertices)
    for index in range(segments):
        angle = math.tau * index / segments
        cosine = math.cos(angle)
        sine = math.sin(angle)
        outer_depth = 0.154 if sine >= 0.0 else 0.180
        inner_depth = 0.128 if sine >= 0.0 else 0.150
        vertices.extend((
            (0.156 * cosine, outer_depth * sine, 1.488),
            (0.156 * cosine, outer_depth * sine, 1.606),
            (0.126 * cosine, inner_depth * sine, 1.488),
            (0.126 * cosine, inner_depth * sine, 1.606),
        ))
    for index in range(segments):
        nxt = (index + 1) % segments
        a = collar_start + index * 4
        b = collar_start + nxt * 4
        add_face((a, b, b + 1, a + 1), 0)
        add_face((a + 2, a + 3, b + 3, b + 2), 0)
        # The collar crown is the same forged plate as its wall. A separate
        # gilt cap read as two loose crescents behind the helmet in motion.
        add_face((a + 1, b + 1, b + 3, a + 3), 0)
        add_face((a, a + 2, b + 2, b), 2)

    mantle = mesh_object(
        "chest", "ApexUnifiedGorgetMantle", vertices, faces,
        [COBALT, BRASS, DARK], "chest",
        bevel=0.0032, bevel_segments=3, smooth=True,
    )
    for polygon, material_index in zip(mantle.data.polygons, material_indices):
        polygon.material_index = material_index
    mantle["bk_edit_note"] = "Compact closed gorget embedded into the raised cuirass and helmet skirt"


def remove_unseated_ornaments():
    """Delete decorative objects that do not form structural overlapping plate."""
    prefixes = (
        "RoyalArmor_chest_ApexBackRivet",
        "RoyalArmor_chest_ApexBackSpine",
        "RoyalArmor_chest_ApexBreastFlute",
        "RoyalArmor_chest_ApexCrownEmblem",
        "RoyalArmor_chest_ApexCrownRuby",
        "RoyalArmor_chest_ApexTapulKeel",
        "RoyalArmor_chest_ApexTassetRivet",
        "RoyalArmor_shoulders_ApexPauldronEdgeTrim",
        "RoyalArmor_hands_ApexElbowBoss",
        "RoyalArmor_feet_ApexGreaveRivet",
        "RoyalArmor_feet_ApexPoleynBoss",
        "RoyalArmor_feet_ApexSabatonGilt",
        "RoyalArmor_chest_ApexClavicleFoundation",
        "RoyalArmor_chest_ApexArmingFoundation",
        "RoyalArmor_pants_ApexCuisseTopRoll",
    )
    for prefix in prefixes:
        remove_prefix(prefix)


def build_ring_shell(slot, part, rings, segments, materials, weights, material_picker, smooth=True, solidify=0.008, bevel=0.0025):
    vertices = []
    for z, half_x, front, rear, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear if sine >= 0 else front
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            if sine < 0 and part == "ApexWaistedCuirass":
                y -= cuirass_front_forging_relief(rings, x, z)
            elif sine > 0 and part == "ApexWaistedCuirass":
                backness = sine ** 8
                center_ridge = math.exp(-((x / 0.038) ** 2))
                ridge_height = math.exp(-(((z - 1.285) / 0.240) ** 2))
                side_flute = math.exp(-(((abs(x) - 0.145) / 0.030) ** 2))
                y += (0.017 * center_ridge * ridge_height + 0.010 * side_flute * ridge_height) * backness
            vertices.append((x, y, z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((
                row * segments + column,
                row * segments + nxt,
                (row + 1) * segments + nxt,
                (row + 1) * segments + column,
            ))
    obj = mesh_object(
        slot, part, vertices, faces, materials, weights,
        bevel=bevel, bevel_segments=3, solidify=solidify, smooth=smooth,
    )
    for polygon in obj.data.polygons:
        row = polygon.index // segments
        column = polygon.index % segments
        angle = math.tau * (column + 0.5) / segments
        zmid = (rings[row][0] + rings[row + 1][0]) * 0.5
        polygon.material_index = material_picker(row, column, angle, zmid)
    return obj


def ring_profile_at_z(rings, z):
    """Interpolate the cuirass cross-section at a requested height."""
    lower = rings[0]
    upper = rings[-1]
    for index in range(len(rings) - 1):
        if rings[index][0] <= z <= rings[index + 1][0]:
            lower, upper = rings[index], rings[index + 1]
            break
    span = max(1e-6, upper[0] - lower[0])
    t = max(0.0, min(1.0, (z - lower[0]) / span))
    return tuple(lower[i] + (upper[i] - lower[i]) * t for i in range(1, 5))


def cuirass_surface_y(rings, x, z):
    half_x, front, _rear, exponent = ring_profile_at_z(rings, z)
    ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
    cosine = ratio ** (exponent * 0.5)
    sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
    return -front * (sine ** (2.0 / exponent))


def cuirass_back_surface_y(rings, x, z):
    half_x, _front, rear, exponent = ring_profile_at_z(rings, z)
    ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
    cosine = ratio ** (exponent * 0.5)
    sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
    return rear * (sine ** (2.0 / exponent))


def cuirass_front_forging_relief(rings, x, z):
    """Depth of the integral tapul, ribs and flutes on the breastplate."""
    half_x, _front, _rear, exponent = ring_profile_at_z(rings, z)
    ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
    cosine = ratio ** (exponent * 0.5)
    sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
    frontness = sine ** 7
    torso_t = max(0.0, min(1.0, (z - 0.985) / 0.575))
    vertical = max(0.0, math.sin(torso_t * math.pi))

    # A pronounced single tapul creates a strong convex knightly chest without
    # returning to the paired breast forms rejected in earlier passes.
    relief = (
        0.032
        * math.exp(-((x / 0.034) ** 2))
        * math.exp(-(((z - 1.290) / 0.225) ** 2))
        * vertical
        * frontness
    )

    # Paired diagonal forging ribs frame an escutcheon-shaped central field.
    panel_fade = max(0.0, min(1.0, (z - 1.105) / 0.070))
    panel_fade *= max(0.0, min(1.0, (1.535 - z) / 0.065))
    panel_target = 0.055 + max(0.0, 1.505 - z) * 0.48
    relief += (
        0.0155
        * math.exp(-(((abs(x) - panel_target) / 0.015) ** 2))
        * panel_fade
        * frontness
    )

    # A continuous swept pectoral brow catches light across the torso as one
    # structural arch rather than two anatomical bulges.
    brow_target_z = 1.425 - 0.115 * ((abs(x) / max(half_x, 1e-6)) ** 1.35)
    brow_fade = max(0.0, 1.0 - (abs(x) / max(half_x * 0.92, 1e-6)) ** 8)
    relief += (
        0.0125
        * math.exp(-(((z - brow_target_z) / 0.017) ** 2))
        * brow_fade
        * frontness
    )

    # Outer flutes and lower abdominal channels break up the remaining broad
    # plate while preserving a single continuous, defensible shell.
    outer_target = 0.224 + 0.018 * math.cos((z - 1.10) * 8.0)
    outer_fade = max(
        0.0,
        math.sin(max(0.0, min(1.0, (z - 1.09) / 0.42)) * math.pi),
    )
    relief += (
        0.0140
        * math.exp(-(((abs(x) - outer_target) / 0.017) ** 2))
        * outer_fade
        * frontness
    )
    abdomen_fade = max(0.0, min(1.0, (1.225 - z) / 0.095))
    abdomen_fade *= max(0.0, min(1.0, (z - 1.005) / 0.065))
    for channel in (0.075, 0.150):
        relief += (
            0.0065
            * math.exp(-(((abs(x) - channel) / 0.014) ** 2))
            * abdomen_fade
            * frontness
        )
    relief += (
        0.0070
        * math.exp(-(((z - 1.075) / 0.013) ** 2))
        * max(0.0, 1.0 - (abs(x) / 0.260) ** 6)
        * frontness
    )
    return relief


def cuirass_front_surface_with_relief(rings, x, z):
    """Return the finished forged front surface, including integral flutes."""
    return cuirass_surface_y(rings, x, z) - cuirass_front_forging_relief(rings, x, z)


def cuirass_back_surface_with_relief(rings, x, z):
    half_x, _front, rear, exponent = ring_profile_at_z(rings, z)
    ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
    cosine = ratio ** (exponent * 0.5)
    sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
    backness = sine ** 8
    base_y = rear * (sine ** (2.0 / exponent))
    ridge_height = math.exp(-(((z - 1.285) / 0.240) ** 2))
    relief = (
        0.017 * math.exp(-((x / 0.038) ** 2)) * ridge_height
        + 0.010 * math.exp(-(((abs(x) - 0.145) / 0.030) ** 2)) * ridge_height
    ) * backness
    return base_y + relief


def build_integral_cuirass_crest(cuirass, rings):
    """Join a connected low-relief royal crest into the breastplate object."""
    remove_prefix("RoyalArmor_chest_ApexIntegralRoyalRelief")
    relief_parts = []

    # A shallow convex escutcheon gives the broad torso a second forged depth
    # tier. Its rear half is buried in the breastplate, and it is joined into the
    # cuirass below, so it reads as a reinforced field rather than a loose badge.
    shield_outline = (
        (-0.108, 1.430), (-0.066, 1.490), (0.0, 1.520),
        (0.066, 1.490), (0.108, 1.430), (0.104, 1.300),
        (0.064, 1.205), (0.0, 1.145), (-0.064, 1.205), (-0.104, 1.300),
    )
    shield_center = (0.0, 1.340)
    shield_vertices = [(
        shield_center[0],
        cuirass_front_surface_with_relief(rings, shield_center[0], shield_center[1]) - 0.012,
        shield_center[1],
    )]
    for x, z in shield_outline:
        inner_x = shield_center[0] + (x - shield_center[0]) * 0.56
        inner_z = shield_center[1] + (z - shield_center[1]) * 0.56
        shield_vertices.append((
            inner_x,
            cuirass_front_surface_with_relief(rings, inner_x, inner_z) - 0.010,
            inner_z,
        ))
    for x, z in shield_outline:
        shield_vertices.append((
            x,
            cuirass_front_surface_with_relief(rings, x, z) - 0.0045,
            z,
        ))
    shield_faces = []
    outline_count = len(shield_outline)
    for index in range(len(shield_outline)):
        current = index + 1
        following = (index + 1) % len(shield_outline) + 1
        shield_faces.append((0, current, following))
        outer_current = current + outline_count
        outer_following = following + outline_count
        shield_faces.append((current, outer_current, outer_following, following))
    shield = mesh_object(
        "chest", "ApexIntegralRoyalReliefEscutcheon",
        shield_vertices, shield_faces, [COBALT, DARK], "chest",
        bevel=0.0026, bevel_segments=3, solidify=0.008, smooth=True,
    )
    shield_solidify = shield.modifiers.get("ForgedThickness")
    if shield_solidify:
        shield_solidify.material_offset_rim = 1
    relief_parts.append(shield)

    paths = (
        ("ShieldBorder", shield_outline + (shield_outline[0],), 0.016),
        ("Sword", ((0.0, 1.174), (0.0, 1.468)), 0.015),
        ("Crossguard", ((-0.065, 1.336), (0.0, 1.362), (0.065, 1.336)), 0.011),
        (
            "Crown",
            (
                (-0.078, 1.420), (-0.052, 1.449), (-0.029, 1.484),
                (0.0, 1.458),
                (0.029, 1.484), (0.052, 1.449), (0.078, 1.420),
            ),
            0.015,
        ),
        ("WingL", ((0.0, 1.278), (-0.043, 1.298), (-0.074, 1.333), (-0.101, 1.354)), 0.009),
        ("WingR", ((0.0, 1.278), (0.043, 1.298), (0.074, 1.333), (0.101, 1.354)), 0.009),
        ("LowerChevron", ((-0.062, 1.205), (0.0, 1.166), (0.062, 1.205)), 0.009),
        ("ClavicleArcL", ((-0.096, 1.465), (-0.195, 1.455), (-0.285, 1.398)), 0.010),
        ("ClavicleArcR", ((0.096, 1.465), (0.195, 1.455), (0.285, 1.398)), 0.010),
        ("MidRibL", ((-0.100, 1.335), (-0.190, 1.312), (-0.270, 1.285)), 0.009),
        ("MidRibR", ((0.100, 1.335), (0.190, 1.312), (0.270, 1.285)), 0.009),
        ("LowerRibL", ((-0.066, 1.205), (-0.175, 1.170), (-0.265, 1.128)), 0.009),
        ("LowerRibR", ((0.066, 1.205), (0.175, 1.170), (0.265, 1.128)), 0.009),
    )
    for name, path, width in paths:
        shield_relief = name not in {
            "ClavicleArcL", "ClavicleArcR", "MidRibL", "MidRibR", "LowerRibL", "LowerRibR",
        }
        projection = 0.014 if shield_relief else 0.006
        thickness = 0.016 if shield_relief else 0.008
        vertices = []
        for index, (x, z) in enumerate(path):
            previous = path[max(0, index - 1)]
            following = path[min(len(path) - 1, index + 1)]
            tangent_x = following[0] - previous[0]
            tangent_z = following[1] - previous[1]
            length = max(1e-6, math.hypot(tangent_x, tangent_z))
            perpendicular_x = -tangent_z / length
            perpendicular_z = tangent_x / length
            for edge in (-0.5, 0.5):
                px = x + perpendicular_x * width * edge
                pz = z + perpendicular_z * width * edge
                py = cuirass_front_surface_with_relief(rings, px, pz) - projection
                vertices.append((px, py, pz))
        faces = []
        for index in range(len(path) - 1):
            a = index * 2
            faces.append((a, a + 1, a + 3, a + 2))
        relief = mesh_object(
            "chest", f"ApexIntegralRoyalRelief{name}",
            vertices, faces, [BRASS], "chest",
            bevel=0.0018, bevel_segments=3, solidify=thickness, smooth=True,
        )
        relief_parts.append(relief)

    back_paths = (
        ("BackSpine", ((0.0, 1.170), (0.0, 1.510)), 0.015),
        (
            "BackCrown",
            ((-0.178, 1.425), (-0.090, 1.468), (0.0, 1.510), (0.090, 1.468), (0.178, 1.425)),
            0.013,
        ),
        ("BackGuard", ((-0.188, 1.325), (0.0, 1.265), (0.188, 1.325)), 0.013),
        ("BackLaurelL", ((-0.018, 1.245), (-0.082, 1.292), (-0.135, 1.352), (-0.185, 1.405)), 0.011),
        ("BackLaurelR", ((0.018, 1.245), (0.082, 1.292), (0.135, 1.352), (0.185, 1.405)), 0.011),
        ("BackLowerChevron", ((-0.155, 1.205), (0.0, 1.158), (0.155, 1.205)), 0.011),
    )
    for name, path, width in back_paths:
        vertices = []
        for index, (x, z) in enumerate(path):
            previous = path[max(0, index - 1)]
            following = path[min(len(path) - 1, index + 1)]
            tangent_x = following[0] - previous[0]
            tangent_z = following[1] - previous[1]
            length = max(1e-6, math.hypot(tangent_x, tangent_z))
            perpendicular_x = -tangent_z / length
            perpendicular_z = tangent_x / length
            for edge in (-0.5, 0.5):
                px = x + perpendicular_x * width * edge
                pz = z + perpendicular_z * width * edge
                py = cuirass_back_surface_with_relief(rings, px, pz) + 0.0030
                vertices.append((px, py, pz))
        faces = []
        for index in range(len(path) - 1):
            a = index * 2
            faces.append((a, a + 2, a + 3, a + 1))
        relief = mesh_object(
            "chest", f"ApexIntegralRoyalRelief{name}",
            vertices, faces, [BRASS], "chest",
            bevel=0.0018, bevel_segments=3, solidify=0.006, smooth=True,
        )
        relief_parts.append(relief)

    for relief in relief_parts:
        bpy.ops.object.select_all(action="DESELECT")
        relief.select_set(True)
        bpy.context.view_layer.objects.active = relief
        for modifier in list(relief.modifiers):
            if modifier.type == "ARMATURE":
                relief.modifiers.remove(modifier)
        for modifier in list(relief.modifiers):
            if modifier.type in {"SOLIDIFY", "BEVEL"}:
                bpy.ops.object.modifier_apply(modifier=modifier.name)

    bpy.ops.object.select_all(action="DESELECT")
    cuirass.select_set(True)
    for relief in relief_parts:
        relief.select_set(True)
    bpy.context.view_layer.objects.active = cuirass
    bpy.ops.object.join()
    cuirass.name = "RoyalArmor_chest_ApexWaistedCuirass"
    cuirass.data.name = cuirass.name + "_Mesh"
    cuirass["bk_edit_note"] = "Unified cuirass with intersecting forged royal sword-and-crown relief"


def build_cuirass_ribbon(part, rings, path, width, material):
    """Build a thin relief physically embedded in the breastplate surface."""
    vertices = []
    for x, z in path:
        for edge in (-0.5, 0.5):
            px = x + width * edge
            py = cuirass_surface_y(rings, px, z) - 0.0025
            vertices.append((px, py, z))
    faces = []
    for index in range(len(path) - 1):
        a = index * 2
        faces.append((a, a + 1, a + 3, a + 2))
    return mesh_object(
        "chest", part, vertices, faces, [material], "chest",
        bevel=0.0018, bevel_segments=3, solidify=0.005, smooth=True,
    )


def build_cuirass_and_waist():
    remove_object("RoyalArmor_chest_ApexWaistedCuirass")
    remove_object("RoyalArmor_chest_ApexIntegralPlackartOverlay")
    remove_object("RoyalArmor_chest_ApexIntegralRearPlackartOverlay")
    remove_object("RoyalArmor_chest_ApexArticulatedFauld")
    remove_object("RoyalArmor_chest_ApexUnifiedFrontTassetL")
    remove_object("RoyalArmor_chest_ApexUnifiedFrontTassetR")
    remove_object("RoyalArmor_chest_ApexUnifiedRearCulet")
    remove_prefix("RoyalArmor_chest_ApexWrapHipLame")
    remove_prefix("RoyalArmor_chest_ApexCuirassRelief")
    for prefix in (
        "RoyalArmor_chest_ApexBreastFlute",
        "RoyalArmor_chest_ApexClavicleRoll",
        "RoyalArmor_chest_ApexCrownEmblem",
        "RoyalArmor_chest_ApexCrownRuby",
        "RoyalArmor_chest_ApexTapulKeel",
        "RoyalArmor_chest_ApexBackFlute",
        "RoyalArmor_chest_ApexBackSpine",
        "RoyalArmor_chest_ApexBackRivet",
    ):
        remove_prefix(prefix)

    cuirass_rings = [
        (0.970, 0.238, 0.154, 0.150, 2.34),
        (0.980, 0.242, 0.157, 0.153, 2.34),
        (1.035, 0.256, 0.166, 0.154, 2.35),
        (1.110, 0.278, 0.190, 0.164, 2.34),
        (1.205, 0.310, 0.216, 0.174, 2.32),
        (1.315, 0.326, 0.226, 0.180, 2.28),
        (1.405, 0.322, 0.220, 0.178, 2.26),
        (1.455, 0.337, 0.212, 0.178, 2.28),
        (1.495, 0.331, 0.201, 0.174, 2.30),
        (1.530, 0.294, 0.187, 0.166, 2.34),
        (1.560, 0.232, 0.171, 0.154, 2.38),
        (1.585, 0.170, 0.158, 0.145, 2.42),
    ]
    # Densify the authored profile before applying forged ridges. The previous
    # sparse rings made the tapul and diagonal flutes read as broad polygons.
    dense_rings = []
    subdivisions = 3
    for ring_index in range(len(cuirass_rings) - 1):
        lower = cuirass_rings[ring_index]
        upper = cuirass_rings[ring_index + 1]
        for step in range(subdivisions):
            t = step / subdivisions
            dense_rings.append(tuple(
                lower[value_index] + (upper[value_index] - lower[value_index]) * t
                for value_index in range(len(lower))
            ))
    dense_rings.append(cuirass_rings[-1])
    cuirass_rings = dense_rings

    def cuirass_material(row, column, angle, zmid):
        front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
        back_delta = abs((angle - 0.5 * math.pi + math.pi) % math.tau - math.pi)
        if row == 0:
            return 2
        # The flutes are forged into the mesh above. Keep them plate-colored so
        # they read as form and highlight, not painted vertical stripes.
        if front_delta < 0.030:
            return 0
        if 0.93 < front_delta < 1.12:
            return 0
        if back_delta < 0.78:
            return 0
        return 0

    cuirass = build_ring_shell(
        "chest", "ApexWaistedCuirass", cuirass_rings, 120,
        [COBALT, DARK, BRASS, STEEL], "chest", cuirass_material,
        smooth=True, solidify=0.010, bevel=0.0032,
    )
    build_integral_cuirass_crest(cuirass, cuirass_rings)

    # A broad fitted plackart reinforces the abdomen and visibly underlaps the
    # upper breastplate. Every point follows the cuirass surface and the shell
    # penetrates it by several millimetres, so this reads as a real overlapping
    # armor section rather than an ornament suspended in front of the body.
    columns = 48
    v_levels = (0.0, 0.25, 0.50, 0.72, 0.86, 0.94, 1.0)
    plackart_vertices = []
    for column in range(columns + 1):
        u = -1.0 + 2.0 * column / columns
        bottom_z = 1.003 + 0.012 * abs(u)
        # The upper edge dips slightly at the sternum and rises toward the
        # flanks. This reads as an abdominal reinforcement, not an under-pec
        # outline or paired breast form.
        top_z = 1.182 + 0.036 * (abs(u) ** 1.45)
        for v in v_levels:
            z = bottom_z + (top_z - bottom_z) * v
            half_x, _front, _rear, _exponent = ring_profile_at_z(cuirass_rings, z)
            x = u * half_x * 0.925
            relief_out = cuirass_front_forging_relief(cuirass_rings, x, z)
            y = cuirass_surface_y(cuirass_rings, x, z) - relief_out - 0.0035
            # One shallow medial ridge stiffens the overlay without turning it
            # into a pointed or breast-shaped plate.
            y -= 0.0025 * math.exp(-((x / 0.055) ** 2)) * math.sin(v * math.pi)
            plackart_vertices.append((x, y, z))
    plackart_faces = []
    stride = len(v_levels)
    for column in range(columns):
        for row in range(stride - 1):
            a = column * stride + row
            plackart_faces.append((a, a + stride, a + stride + 1, a + 1))
    plackart = mesh_object(
        "chest", "ApexIntegralPlackartOverlay",
        plackart_vertices, plackart_faces,
        [COBALT, BRASS], "chest",
        bevel=0.0026, bevel_segments=3, solidify=0.008, smooth=True,
    )
    for polygon in plackart.data.polygons:
        row = polygon.index % (stride - 1)
        polygon.material_index = 1 if row == stride - 2 else 0
    solidify = plackart.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    plackart["bk_edit_note"] = "Fitted lower breastplate reinforcement overlapping the continuous cuirass"

    # Matching fitted rear reinforcement. It follows the forged back ribs and
    # penetrates the backplate, providing a protected layered construction and
    # breaking up the previously uninterrupted rear shell.
    rear_vertices = []
    for column in range(columns + 1):
        u = -1.0 + 2.0 * column / columns
        bottom_z = 1.003 + 0.010 * abs(u)
        top_z = 1.168 + 0.042 * (abs(u) ** 1.45)
        for v in v_levels:
            z = bottom_z + (top_z - bottom_z) * v
            half_x, _front, _rear, exponent = ring_profile_at_z(cuirass_rings, z)
            x = u * half_x * 0.925
            ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
            cosine = ratio ** (exponent * 0.5)
            sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
            backness = sine ** 8
            ridge_height = math.exp(-(((z - 1.285) / 0.240) ** 2))
            relief_out = (
                0.017 * math.exp(-((x / 0.038) ** 2)) * ridge_height
                + 0.010 * math.exp(-(((abs(x) - 0.145) / 0.030) ** 2)) * ridge_height
            ) * backness
            y = cuirass_back_surface_y(cuirass_rings, x, z) + relief_out + 0.0035
            rear_vertices.append((x, y, z))
    rear_faces = []
    for column in range(columns):
        for row in range(stride - 1):
            a = column * stride + row
            rear_faces.append((a, a + 1, a + stride + 1, a + stride))
    rear_plackart = mesh_object(
        "chest", "ApexIntegralRearPlackartOverlay",
        rear_vertices, rear_faces,
        [COBALT, BRASS], "chest",
        bevel=0.0026, bevel_segments=3, solidify=0.008, smooth=True,
    )
    for polygon in rear_plackart.data.polygons:
        row = polygon.index % (stride - 1)
        polygon.material_index = 1 if row == stride - 2 else 0
    solidify = rear_plackart.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    rear_plackart["bk_edit_note"] = "Fitted rear reinforcement overlapping the backplate and fauld"

    relief_prefixes = (
        "RoyalArmor_chest_ApexBreastFlute",
        "RoyalArmor_chest_ApexCrownEmblem",
        "RoyalArmor_chest_ApexCrownRuby",
        "RoyalArmor_chest_ApexTapulKeel",
    )
    relief_parts = append_reference_objects(
        lambda name: name.startswith(relief_prefixes),
        "chest", rigid_bone="chest",
    )
    for obj in relief_parts:
        # The current cuirass is slightly deeper than the source breastplate.
        # This small embedded offset seats the relief into the metal surface.
        for vertex in obj.data.vertices:
            vertex.co.y -= 0.018

    back_prefixes = (
        "RoyalArmor_chest_ApexBackSpine",
        "RoyalArmor_chest_ApexBackRivet",
    )
    back_parts = append_reference_objects(
        lambda name: name.startswith(back_prefixes),
        "chest", rigid_bone="chest",
    )
    for obj in back_parts:
        for vertex in obj.data.vertices:
            vertex.co.y -= 0.022

    fauld_rings = [
        (0.852, 0.246, 0.184, 0.193, 2.48),
        (0.873, 0.250, 0.187, 0.197, 2.48),
        (0.894, 0.254, 0.190, 0.201, 2.48),
        (0.915, 0.257, 0.192, 0.203, 2.48),
        (0.936, 0.257, 0.191, 0.203, 2.48),
        (0.957, 0.253, 0.186, 0.198, 2.48),
        (0.978, 0.246, 0.178, 0.189, 2.48),
        (0.998, 0.239, 0.170, 0.181, 2.48),
    ]

    def fauld_material(row, column, angle, zmid):
        if row in (1, 4, 6):
            return 2
        if row == 3:
            return 1
        return 0

    build_ring_shell(
        "chest", "ApexArticulatedFauld", fauld_rings, 40,
        [COBALT, DARK, BRASS], "pelvis", fauld_material,
        smooth=True, solidify=0.007, bevel=0.0022,
    )

    remove_prefix("RoyalArmor_chest_ApexUnifiedFrontTasset")
    remove_prefix("RoyalArmor_chest_ApexTasset")
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        center = 0.143 * side
        # Three pointed, overlapping tasset lames move with each thigh. They are
        # convex, ridged and edged rather than reading as flat cloth flaps.
        plates = [
            # top, bottom, top half-width, bottom half-width, top y, bottom y
            (0.968, 0.852, 0.105, 0.116, -0.186, -0.203),
            (0.887, 0.748, 0.116, 0.111, -0.198, -0.207),
            (0.782, 0.635, 0.108, 0.075, -0.201, -0.184),
        ]
        columns = 14
        v_levels = (0.0, 0.70, 0.88, 1.0)
        for plate_index, (top, bottom, top_width, bottom_width, top_y, bottom_y) in enumerate(plates):
            vertices = []
            for v in v_levels:
                for column in range(columns + 1):
                    u = -1.0 + 2.0 * column / columns
                    half_width = top_width + (bottom_width - top_width) * v
                    x = center + half_width * u
                    point_drop = 0.030 * (v ** 2.8) * max(0.0, 1.0 - abs(u) ** 1.7)
                    z = top + (bottom - top) * v - point_drop
                    base_y = top_y + (bottom_y - top_y) * v
                    convex = 0.021 * (1.0 - u * u)
                    ridge = 0.008 * max(0.0, 1.0 - abs(u) / 0.18)
                    vertices.append((x, base_y - convex - ridge, z))
            faces = []
            for row in range(len(v_levels) - 1):
                for column in range(columns):
                    a = row * (columns + 1) + column
                    faces.append((a, a + 1, a + columns + 2, a + columns + 1))
            plate = mesh_object(
                "chest", f"ApexTasset{suffix}{plate_index}", vertices, faces,
                [COBALT, BRASS, DARK], {}, bevel=0.003, bevel_segments=3,
                solidify=0.009, smooth=True,
                custom_skin=lambda obj, bone=f"thigh.{suffix}": skin_tasset(obj, bone),
            )
            for polygon in plate.data.polygons:
                row = polygon.index // columns
                column = polygon.index % columns
                u_mid = -1.0 + 2.0 * (column + 0.5) / columns
                if row == len(v_levels) - 2:
                    polygon.material_index = 1
                elif abs(u_mid) < 0.13:
                    polygon.material_index = 2
                else:
                    polygon.material_index = 0
            solidify = plate.modifiers.get("ForgedThickness")
            if solidify:
                solidify.material_offset_rim = 1

    # Connected rear culet extends around both hips so the frontal tassets are
    # part of a complete armored skirt instead of two isolated hanging flaps.
    rear_levels = [
        (0.700, 0.196, 0.160),
        (0.735, 0.212, 0.173),
        (0.746, 0.218, 0.178),
        (0.810, 0.238, 0.189),
        (0.821, 0.243, 0.193),
        (0.884, 0.252, 0.198),
        (0.895, 0.254, 0.199),
        (0.960, 0.240, 0.184),
        (1.000, 0.226, 0.171),
    ]
    columns = 40
    vertices = []
    for z, half_width, depth in rear_levels:
        for column in range(columns + 1):
            angle = -0.30 * math.pi + 1.60 * math.pi * column / columns
            backness = max(0.0, math.sin(angle))
            lower_scallop = 0.018 * (backness ** 2.0) * max(0.0, 1.0 - (z - 0.700) / 0.300)
            vertices.append((half_width * math.cos(angle), depth * math.sin(angle), z - lower_scallop))
    faces = []
    for row in range(len(rear_levels) - 1):
        for column in range(columns):
            a = row * (columns + 1) + column
            faces.append((a, a + 1, a + columns + 2, a + columns + 1))
    culet = mesh_object(
        "chest", "ApexUnifiedRearCulet", vertices, faces,
        [COBALT, DARK, STEEL, BRASS], "pelvis",
        bevel=0.0025, bevel_segments=3, solidify=0.008, smooth=True,
    )
    for polygon in culet.data.polygons:
        row = polygon.index // columns
        polygon.material_index = 3 if row in (1, 3, 5) else 0

    # Three overlapping side lames on each hip bridge the front tassets and the
    # wraparound culet. Their pointed lower edges echo the shoulder silhouette.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        center_angle = math.pi if side < 0 else 0.0
        side_plates = (
            (0.974, 0.858, 0.255, 0.197),
            (0.898, 0.780, 0.260, 0.202),
            (0.818, 0.680, 0.252, 0.196),
        )
        phi_steps = 18
        v_levels = (0.0, 0.70, 0.88, 1.0)
        for plate_index, (top, bottom, radius_x, radius_y) in enumerate(side_plates):
            side_vertices = []
            for v in v_levels:
                for phi_index in range(phi_steps + 1):
                    phi = -1.08 + 2.16 * phi_index / phi_steps
                    angle = center_angle + phi
                    center_point = max(0.0, math.cos(phi))
                    point_drop = 0.032 * (v ** 2.8) * (center_point ** 2.0)
                    z = top + (bottom - top) * v - point_drop
                    flare = 0.005 + 0.009 * v
                    side_vertices.append((
                        (radius_x + flare) * math.cos(angle),
                        (radius_y + flare) * math.sin(angle),
                        z,
                    ))
            side_faces = []
            stride = phi_steps + 1
            for row in range(len(v_levels) - 1):
                for phi_index in range(phi_steps):
                    a = row * stride + phi_index
                    side_faces.append((a, a + 1, a + stride + 1, a + stride))
            side_lame = mesh_object(
                "chest", f"ApexWrapHipLame{suffix}{plate_index}",
                side_vertices, side_faces, [COBALT, BRASS, DARK], "pelvis",
                bevel=0.0028, bevel_segments=3, solidify=0.008, smooth=True,
            )
            for polygon in side_lame.data.polygons:
                row = polygon.index // phi_steps
                column = polygon.index % phi_steps
                phi_mid = -1.08 + 2.16 * (column + 0.5) / phi_steps
                if row == len(v_levels) - 2:
                    polygon.material_index = 1
                elif abs(phi_mid) < 0.11:
                    polygon.material_index = 2
                else:
                    polygon.material_index = 0
            solidify = side_lame.modifiers.get("ForgedThickness")
            if solidify:
                solidify.material_offset_rim = 1


def prism_xz(slot, part, side, outline, y_front, y_back, materials, weights, bevel=0.008):
    points = [(side * x, y_front, z) for x, z in outline]
    points += [(side * x, y_back, z) for x, z in outline]
    count = len(outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    obj = mesh_object(slot, part, points, faces, materials, weights, bevel=bevel, bevel_segments=3)
    for polygon in obj.data.polygons:
        polygon.material_index = 0 if polygon.index < 2 else min(1, len(materials) - 1)
    return obj


def build_connected_codpiece():
    """Close the exposed loincloth gap beneath the fauld with a fitted plate."""
    levels = (
        (0.946, 0.076, -0.192),
        (0.902, 0.079, -0.201),
        (0.852, 0.073, -0.206),
        (0.802, 0.061, -0.204),
        (0.756, 0.043, -0.197),
        (0.716, 0.018, -0.184),
    )
    columns = 10
    vertices = []
    for z, half_width, base_y in levels:
        for column in range(columns + 1):
            u = -1.0 + 2.0 * column / columns
            convex = 0.012 * (1.0 - u * u)
            vertices.append((half_width * u, base_y - convex, z))
    faces = []
    for row in range(len(levels) - 1):
        for column in range(columns):
            a = row * (columns + 1) + column
            faces.append((a, a + 1, a + columns + 2, a + columns + 1))
    codpiece = mesh_object(
        "chest", "ApexUnifiedFrontCodpiece", vertices, faces,
        [COBALT, DARK], "pelvis", bevel=0.0035, bevel_segments=3,
        solidify=0.012, smooth=True,
    )
    solidify = codpiece.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    codpiece["bk_edit_note"] = "Closed groin plate overlapping fauld and both tassets"


def curved_shoulder_bridge(part, side, weights):
    across_steps = 7
    depth_steps = 6
    vertices = []
    for across in range(across_steps + 1):
        t = across / across_steps
        x_abs = 0.178 + 0.150 * t
        for depth_index in range(depth_steps + 1):
            v = -1.0 + 2.0 * depth_index / depth_steps
            x = side * x_abs
            y = 0.090 * v
            z = 1.480 + 0.054 * math.sin(math.pi * t) - 0.008 * v * v
            vertices.append((x, y, z))
    faces = []
    stride = depth_steps + 1
    for across in range(across_steps):
        for depth_index in range(depth_steps):
            a = across * stride + depth_index
            faces.append((a, a + stride, a + stride + 1, a + 1))
    obj = mesh_object(
        "shoulders", part, vertices, faces, [DARK, BRASS], weights,
        bevel=0.0025, bevel_segments=3, solidify=0.007, smooth=True,
    )
    solidify = obj.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    return obj


def curved_pauldron_cap(part, side, weights):
    theta_steps = 16
    phi_steps = 36
    vertices = []
    for theta_index in range(theta_steps + 1):
        t = theta_index / theta_steps
        theta = 0.045 + 1.405 * t
        for phi_index in range(phi_steps + 1):
            # Wrap beyond the shoulder center so the cap visibly underlaps the
            # raised cuirass instead of ending beside it with a black channel.
            phi = -2.12 + 4.24 * phi_index / phi_steps
            crown = 0.116 * math.exp(-((phi / 0.235) ** 2)) * (math.sin(theta) ** 1.04)
            crown += (
                0.046
                * math.exp(-(((abs(phi) - 0.70) / 0.16) ** 2))
                * (math.sin(theta) ** 1.25)
            )
            crown += (
                0.022
                * math.exp(-(((abs(phi) - 1.34) / 0.18) ** 2))
                * (math.sin(theta) ** 1.45)
            )
            edge_fade = math.sin(math.pi * theta_index / theta_steps) ** 1.35
            flute = 0.0155 * (0.5 + 0.5 * math.cos(phi * 7.0)) * edge_fade
            flare = 0.054 * (t ** 2.35) * (
                0.65 + 0.35 * math.exp(-((phi / 0.92) ** 4))
            )
            radius = 0.195 + flute + flare
            skirt_drop = (
                0.076
                * math.exp(-((phi / 0.34) ** 2))
                * (t ** 4)
            )
            skirt_drop += (
                0.026
                * math.exp(-(((abs(phi) - 1.15) / 0.24) ** 2))
                * (t ** 3)
            )
            # Three heraldic points break the formerly round lower silhouette.
            skirt_drop += (
                0.031
                * math.exp(-(((abs(phi) - 0.72) / 0.16) ** 2))
                * (t ** 4.2)
            )
            x_abs = 0.280 + (radius + crown * 0.35) * math.sin(theta) * math.cos(phi)
            y = (0.158 + flute * 0.70 + flare * 0.78) * math.sin(theta) * math.sin(phi)
            z = 1.360 + radius * math.cos(theta) + crown - skirt_drop
            vertices.append((side * x_abs, y, z))
    faces = []
    stride = phi_steps + 1
    for theta_index in range(theta_steps):
        for phi_index in range(phi_steps):
            a = theta_index * stride + phi_index
            faces.append((a, a + stride, a + stride + 1, a + 1))

    obj = mesh_object(
        "shoulders", part, vertices, faces, [COBALT, BRASS, BRIGHT, DARK], weights,
        bevel=0.0028, bevel_segments=3, solidify=0.009, smooth=True,
    )
    solidify = obj.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    for polygon in obj.data.polygons:
        row = polygon.index // phi_steps
        column = polygon.index % phi_steps
        phi_mid = -2.12 + 4.24 * (column + 0.5) / phi_steps
        if row == theta_steps - 1:
            polygon.material_index = 1
        elif abs(phi_mid) < 0.095 and row >= 2:
            polygon.material_index = 1
        elif abs(abs(phi_mid) - 0.70) < 0.075 and row >= 4:
            polygon.material_index = 1
        elif abs(abs(phi_mid) - 1.04) < 0.070 and 5 <= row <= theta_steps - 3:
            polygon.material_index = 3
        else:
            polygon.material_index = 0
    return obj


def curved_pauldron_trim(part, side, weights):
    """A fitted lower-edge band sharing the pauldron curvature."""
    theta_steps = 2
    phi_steps = 14
    vertices = []
    for theta_index in range(theta_steps + 1):
        theta = 1.225 + 0.155 * theta_index / theta_steps
        for phi_index in range(phi_steps + 1):
            phi = -1.31 + 2.62 * phi_index / phi_steps
            radius = 0.188
            x_abs = 0.292 + radius * math.sin(theta) * math.cos(phi)
            y = 0.162 * math.sin(theta) * math.sin(phi)
            z = 1.370 + radius * math.cos(theta)
            vertices.append((side * x_abs, y, z))
    faces = []
    stride = phi_steps + 1
    for theta_index in range(theta_steps):
        for phi_index in range(phi_steps):
            a = theta_index * stride + phi_index
            faces.append((a, a + stride, a + stride + 1, a + 1))
    return mesh_object(
        "shoulders", part, vertices, faces, [BRASS], weights,
        bevel=0.0018, bevel_segments=3, solidify=0.004, smooth=True,
    )


def curved_arm_lame(part, side, z_top, z_bottom, radius, depth, material, bone):
    phi_steps = 14
    rows = 4
    vertices = []
    for row in range(rows + 1):
        t = row / rows
        z_base = z_top + (z_bottom - z_top) * t
        radius_eff = radius * (1.0 - 0.065 * t)
        for phi_index in range(phi_steps + 1):
            phi = -1.32 + 2.64 * phi_index / phi_steps
            x_abs = 0.338 + radius_eff * math.cos(phi)
            y = depth * math.sin(phi)
            lateral = max(0.0, math.cos(phi)) ** 2
            z = z_base + 0.008 * math.cos(phi) - 0.013 * t * lateral
            vertices.append((side * x_abs, y, z))
    faces = []
    stride = phi_steps + 1
    for row in range(rows):
        for phi_index in range(phi_steps):
            a = row * stride + phi_index
            faces.append((a, a + stride, a + stride + 1, a + 1))
    obj = mesh_object(
        "shoulders", part, vertices, faces, [material, BRASS, DARK], bone,
        bevel=0.0022, bevel_segments=3, solidify=0.007, smooth=True,
    )
    solidify = obj.modifiers.get("ForgedThickness")
    if solidify:
        solidify.material_offset_rim = 1
    for polygon in obj.data.polygons:
        row = polygon.index // phi_steps
        column = polygon.index % phi_steps
        phi_mid = -1.32 + 2.64 * (column + 0.5) / phi_steps
        if row == rows - 1:
            polygon.material_index = 1
        elif abs(phi_mid) < 0.11:
            polygon.material_index = 1
        elif abs(abs(phi_mid) - 0.78) < 0.10:
            polygon.material_index = 2
        else:
            polygon.material_index = 0
    return obj


def build_shoulders():
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        for part in (
            f"ApexLateralShoulderBridge{suffix}",
            f"ApexGrandPauldron{suffix}",
            f"ApexImprovedPauldron{suffix}1",
            f"ApexImprovedPauldron{suffix}2",
            f"ApexUnifiedShoulderSkirt{suffix}",
            f"ApexPauldronEdgeTrim{suffix}",
        ):
            remove_object(f"RoyalArmor_shoulders_{part}")

        clavicle = f"clavicle.{suffix}"
        upper = f"upper_arm.{suffix}"
        curved_pauldron_cap(
            f"ApexGrandPauldron{suffix}", side,
            {clavicle: 0.62, upper: 0.38},
        )
        curved_arm_lame(
            f"ApexImprovedPauldron{suffix}1", side,
            1.388, 1.305, 0.142, 0.148, COBALT, upper,
        )
        curved_arm_lame(
            f"ApexImprovedPauldron{suffix}2", side,
            1.326, 1.245, 0.135, 0.142, COBALT, upper,
        )
        curved_arm_lame(
            f"ApexUnifiedShoulderSkirt{suffix}", side,
            1.264, 1.180, 0.126, 0.134, COBALT, upper,
        )


def build_fitted_rerebraces():
    """Replace oversized inherited shells that cut through the breastplate."""
    segments = 28
    rings = (
        (1.075, 0.072, 0.086),
        (1.145, 0.078, 0.094),
        (1.245, 0.083, 0.101),
        (1.335, 0.087, 0.108),
        (1.390, 0.082, 0.104),
    )
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        remove_object(f"RoyalArmor_shoulders_ApexRerebrace{suffix}")
        center_x = 0.375 * side
        vertices = []
        for z, radius_x, radius_y in rings:
            for index in range(segments):
                angle = math.tau * index / segments
                vertices.append((
                    center_x + radius_x * math.cos(angle),
                    radius_y * math.sin(angle),
                    z,
                ))
        faces = []
        for row in range(len(rings) - 1):
            for index in range(segments):
                nxt = (index + 1) % segments
                faces.append((
                    row * segments + index,
                    row * segments + nxt,
                    (row + 1) * segments + nxt,
                    (row + 1) * segments + index,
                ))
        rerebrace = mesh_object(
            "shoulders", f"ApexRerebrace{suffix}", vertices, faces,
            [COBALT, DARK, BRASS, BRIGHT], f"upper_arm.{suffix}",
            bevel=0.0025, bevel_segments=3, solidify=0.007, smooth=True,
        )
        for polygon in rerebrace.data.polygons:
            row = polygon.index // segments
            column = polygon.index % segments
            angle = math.tau * (column + 0.5) / segments
            front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
            if row in (0, len(rings) - 2):
                polygon.material_index = 2
            elif front_delta < 0.12:
                polygon.material_index = 3
            elif 0.72 < front_delta < 0.88:
                polygon.material_index = 1
            else:
                polygon.material_index = 0


def build_fitted_cuisses():
    """Create continuous thigh shells that overlap the culet and poleyns."""
    segments = 32
    rings = (
        (0.480, 0.077, 0.086),
        (0.545, 0.085, 0.095),
        (0.650, 0.096, 0.108),
        (0.760, 0.104, 0.119),
        (0.855, 0.108, 0.126),
        (0.888, 0.106, 0.124),
        (0.910, 0.104, 0.122),
    )
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        remove_object(f"RoyalArmor_pants_ApexCuisse{suffix}")
        center_x = 0.132 * side
        vertices = []
        for z, radius_x, radius_y in rings:
            for index in range(segments):
                angle = math.tau * index / segments
                local_x = radius_x * math.cos(angle)
                y = radius_y * math.sin(angle)
                if math.sin(angle) < 0.0:
                    frontness = abs(math.sin(angle)) ** 8
                    center_ridge = math.exp(-((local_x / 0.024) ** 2))
                    height_fade = max(0.0, math.sin(max(0.0, min(1.0, (z - 0.48) / 0.43)) * math.pi))
                    y -= 0.0110 * center_ridge * height_fade * frontness
                vertices.append((
                    center_x + local_x,
                    y,
                    z,
                ))
        faces = []
        for row in range(len(rings) - 1):
            for index in range(segments):
                nxt = (index + 1) % segments
                faces.append((
                    row * segments + index,
                    row * segments + nxt,
                    (row + 1) * segments + nxt,
                    (row + 1) * segments + index,
                ))
        cuisse = mesh_object(
            "pants", f"ApexCuisse{suffix}", vertices, faces,
            [COBALT, BRASS], f"thigh.{suffix}",
            bevel=0.0025, bevel_segments=3, solidify=0.008, smooth=True,
        )
        for polygon in cuisse.data.polygons:
            row = polygon.index // segments
            polygon.material_index = 1 if row == len(rings) - 2 else 0
        solidify = cuisse.modifiers.get("ForgedThickness")
        if solidify:
            solidify.material_offset_rim = 1
        cuisse["bk_edit_note"] = "Continuous ridged cuisse overlapping tasset and poleyn"


def build_elbows():
    """Replace boxy diamond couters with compact rounded elbow cups."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        part = f"ApexCouter{suffix}"
        remove_object(f"RoyalArmor_hands_{part}")
        phi_steps = 14
        theta_steps = 7
        vertices = []
        center_x = 0.355 * side
        for theta_index in range(theta_steps + 1):
            theta = math.pi * theta_index / theta_steps
            for phi_index in range(phi_steps + 1):
                phi = -1.34 + 2.68 * phi_index / phi_steps
                boss = (
                    0.009
                    * math.exp(-((phi / 0.28) ** 2))
                    * math.exp(-(((theta - math.pi * 0.5) / 0.38) ** 2))
                )
                x = center_x + side * (0.082 * math.cos(phi) * math.sin(theta) + boss)
                y = -0.028 - 0.092 * math.cos(theta)
                z = 1.142 + 0.082 * math.sin(phi) * math.sin(theta)
                vertices.append((x, y, z))
        faces = []
        stride = phi_steps + 1
        for theta_index in range(theta_steps):
            for phi_index in range(phi_steps):
                a = theta_index * stride + phi_index
                faces.append((a, a + stride, a + stride + 1, a + 1))
        couter = mesh_object(
            "hands", part, vertices, faces, [COBALT, DARK], f"forearm.{suffix}",
            bevel=0.0025, bevel_segments=3, solidify=0.007, smooth=True,
        )
        for polygon in couter.data.polygons:
            polygon.material_index = 0
        couter["bk_edit_note"] = "Rounded couter with integral forged pivot boss"


def refine_lower_leg_finish():
    """Carry the cobalt harness continuously through knees and greaves."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        greave = bpy.data.objects.get(f"RoyalArmor_feet_ApexGreave{suffix}")
        if greave is not None and greave.type == "MESH":
            ridge_pass = "RoyalGreaveTripleFlute20260801"
            if greave.get("bk_geometry_pass") != ridge_pass:
                minimum_y = min(vertex.co.y for vertex in greave.data.vertices)
                maximum_y = max(vertex.co.y for vertex in greave.data.vertices)
                center_x = sum(vertex.co.x for vertex in greave.data.vertices) / len(greave.data.vertices)
                depth_span = max(0.001, maximum_y - minimum_y)
                for vertex in greave.data.vertices:
                    frontness = max(0.0, min(1.0, (maximum_y - vertex.co.y) / depth_span)) ** 5
                    center_ridge = max(0.0, 1.0 - abs(vertex.co.x - center_x) / 0.030)
                    side_flute = math.exp(-(((abs(vertex.co.x - center_x) - 0.050) / 0.014) ** 2))
                    height_fade = max(0.0, math.sin(max(0.0, min(1.0, (vertex.co.z - 0.145) / 0.390)) * math.pi))
                    vertex.co.y -= (
                        0.006 * center_ridge + 0.004 * side_flute
                    ) * frontness * height_fade
                greave["bk_geometry_pass"] = ridge_pass
            for material in (COBALT, BRASS, DARK):
                if greave.data.materials.get(material.name) is None:
                    greave.data.materials.append(material)
            indices = {material.name: index for index, material in enumerate(greave.data.materials)}
            maximum_z = max(vertex.co.z for vertex in greave.data.vertices)
            for polygon in greave.data.polygons:
                polygon.material_index = indices[COBALT.name]
                if polygon.center.z > maximum_z - 0.022:
                    polygon.material_index = indices[BRASS.name]
            greave["bk_edit_note"] = "Continuous cobalt greave with integral upper roll"

        poleyn = bpy.data.objects.get(f"RoyalArmor_feet_ApexPoleyn{suffix}")
        if poleyn is not None and poleyn.type == "MESH":
            for material in (COBALT, BRASS):
                if poleyn.data.materials.get(material.name) is None:
                    poleyn.data.materials.append(material)
            material_indices = {
                material.name: index
                for index, material in enumerate(poleyn.data.materials)
                if material is not None
            }
            minimum_y = min(vertex.co.y for vertex in poleyn.data.vertices)
            maximum_y = max(vertex.co.y for vertex in poleyn.data.vertices)
            center_x = sum(vertex.co.x for vertex in poleyn.data.vertices) / len(poleyn.data.vertices)
            center_z = sum(vertex.co.z for vertex in poleyn.data.vertices) / len(poleyn.data.vertices)
            depth = max(0.001, maximum_y - minimum_y)
            boss_pass = "RoyalPoleynIntegralBoss20260801"
            if poleyn.get("bk_geometry_pass") != boss_pass:
                for vertex in poleyn.data.vertices:
                    frontness = max(0.0, min(1.0, (maximum_y - vertex.co.y) / depth)) ** 7
                    radial = math.exp(-(((vertex.co.x - center_x) / 0.032) ** 2))
                    radial *= math.exp(-(((vertex.co.z - center_z) / 0.038) ** 2))
                    vertex.co.y -= 0.007 * frontness * radial
                poleyn["bk_geometry_pass"] = boss_pass
            for polygon in poleyn.data.polygons:
                polygon.material_index = material_indices[COBALT.name]
            poleyn["bk_edit_note"] = "Cobalt poleyn with integral pivot boss overlapping cuisse and greave"


def refine_gauntlet_finish():
    """Separate engraved backhand plates from dark articulated fingers."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        gauntlet = bpy.data.objects.get(f"RoyalArmor_hands_ApexGauntlet{suffix}")
        if gauntlet is None or gauntlet.type != "MESH":
            continue
        for material in (COBALT, DARK):
            if gauntlet.data.materials.get(material.name) is None:
                gauntlet.data.materials.append(material)
        indices = {material.name: index for index, material in enumerate(gauntlet.data.materials)}
        minimum_z = min(vertex.co.z for vertex in gauntlet.data.vertices)
        maximum_z = max(vertex.co.z for vertex in gauntlet.data.vertices)
        plate_cut = minimum_z + (maximum_z - minimum_z) * 0.48
        for polygon in gauntlet.data.polygons:
            polygon.material_index = (
                indices[COBALT.name] if polygon.center.z >= plate_cut
                else indices[DARK.name]
            )
        gauntlet["bk_edit_note"] = "Engraved backhand shell over blackened articulated fingers"


def refine_vambrace_finish():
    """Add forged rolled edges directly to both continuous forearm shells."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        vambrace = bpy.data.objects.get(f"RoyalArmor_hands_ApexVambrace{suffix}")
        if vambrace is None or vambrace.type != "MESH":
            continue
        for material in (COBALT, BRASS):
            if vambrace.data.materials.get(material.name) is None:
                vambrace.data.materials.append(material)
        indices = {
            material.name: index
            for index, material in enumerate(vambrace.data.materials)
            if material is not None
        }
        minimum_z = min(vertex.co.z for vertex in vambrace.data.vertices)
        maximum_z = max(vertex.co.z for vertex in vambrace.data.vertices)
        height = maximum_z - minimum_z
        for polygon in vambrace.data.polygons:
            edge = (
                polygon.center.z < minimum_z + height * 0.060
                or polygon.center.z > maximum_z - height * 0.055
            )
            polygon.material_index = indices[BRASS.name] if edge else indices[COBALT.name]
        vambrace["bk_edit_note"] = "Continuous cobalt vambrace with integral gilt wrist and elbow rolls"


def refine_leg_surfaces():
    """Taper balloon-like cuisses and add integrated forged center ridges."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        obj = bpy.data.objects.get(f"RoyalArmor_pants_ApexCuisse{suffix}")
        if obj is None or obj.type != "MESH":
            continue
        center_x = 0.131 * side
        for vertex in obj.data.vertices:
            if 0.60 <= vertex.co.z <= 0.93:
                height = max(0.0, min(1.0, (vertex.co.z - 0.60) / 0.33))
                taper = 0.82 + 0.18 * height
                vertex.co.x = center_x + (vertex.co.x - center_x) * taper
                if vertex.co.y < 0:
                    vertex.co.y *= 0.94
        for material in (BRIGHT, BRASS):
            if obj.data.materials.get(material.name) is None:
                obj.data.materials.append(material)
        material_indices = {material.name: index for index, material in enumerate(obj.data.materials)}
        for polygon in obj.data.polygons:
            center = polygon.center
            if center.y < -0.055 and abs(center.x - center_x) < 0.024:
                polygon.material_index = material_indices[BRIGHT.name]
            elif center.z > 0.885:
                polygon.material_index = material_indices[BRASS.name]
        obj["bk_visual_pass"] = PASS_ID


def clean_cuisse_exposure():
    """Remove disconnected bright scraps exposed behind the fitted rear culet."""
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        obj = bpy.data.objects.get(f"RoyalArmor_pants_ApexCuisse{suffix}")
        if obj is None or obj.type != "MESH":
            continue
        if obj.data.materials.get(COBALT.name) is None:
            obj.data.materials.append(COBALT)
        cobalt_index = next(
            index for index, material in enumerate(obj.data.materials)
            if material and material.name == COBALT.name
        )
        for polygon in obj.data.polygons:
            if polygon.center.z > 0.850:
                polygon.material_index = cobalt_index
        if not obj.get("bk_rear_cuisse_seated", False):
            for vertex in obj.data.vertices:
                if vertex.co.z > 0.780 and vertex.co.y > 0.0:
                    vertex.co.y *= 0.72
            obj["bk_rear_cuisse_seated"] = True
        obj["bk_visual_pass"] = PASS_ID


def clean_foundation_exposure():
    """Blend deformation-safe shoulder filler into the plate shell."""
    obj = bpy.data.objects.get("RoyalArmor_chest_ApexClavicleFoundation")
    if obj is None or obj.type != "MESH":
        return
    if obj.data.materials.get(COBALT.name) is None:
        obj.data.materials.append(COBALT)
    cobalt_index = next(
        index for index, material in enumerate(obj.data.materials)
        if material and material.name == COBALT.name
    )
    for polygon in obj.data.polygons:
        polygon.material_index = cobalt_index
    for vertex in obj.data.vertices:
        # Keep the flexible filler under the outer shells instead of letting it
        # clip through the narrower breastplate as triangular surface scraps.
        vertex.co.y *= 0.72
    obj["bk_visual_pass"] = PASS_ID
    obj["bk_edit_note"] = "Deformation-safe shoulder gap filler; keep under outer plate"


def write_editing_guide():
    text = bpy.data.texts.get("ARMOR_EDITING_GUIDE") or bpy.data.texts.new("ARMOR_EDITING_GUIDE")
    text.clear()
    text.write(
        """BROKEN KNIGHT - ROYAL ARMOR EDITING

Canonical file: BrokenKnight_Hero_Master.blend
Repeatable visual pass: scripts/refine_royal_armor_visual_pass.py

OUTLINER
10A_ARMOR_HEAD       unified helmet/visor, crown ribs and layered embedded plume
10B_ARMOR_CHEST      convex cuirass, integral plastron, wrap fauld, tassets and culet
10C_ARMOR_SHOULDERS  crowned/fluted pauldrons, articulated lames and rerebraces
10D_ARMOR_HANDS      couters, vambraces and gauntlets
10E_ARMOR_PANTS      arming hose, cuisses, belt and knee voids
10F_ARMOR_FEET       poleyns, greaves and sabatons

The new outer pieces have custom properties:
  bk_edit_group   matching equipment slot
  bk_visual_pass  pass identifier
  bk_editable     true

Safe changes: Edit Mode vertex shaping, material assignment, and Bevel width.
Keep every RoyalArmor_<slot>_ prefix unchanged so Godot can equip the slot.
Do not apply or remove the RoyalArmorRig modifier unless reweighting the piece.
Never add freestanding armor decoration. Detail must be integral to a shell or
visibly overlap a structural neighboring plate; no floating trim or visor parts.
Preserve the generated UV maps; they carry the cobalt filigree into Godot.
Use export-hero-blender.bat after saving, then project.bat check.
"""
    )
    text.use_fake_user = True


def ensure_armor_uvs():
    """Smart-project structural armor so the authored filigree maps can render."""
    previous_active = bpy.context.view_layer.objects.active
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.name.startswith("RoyalArmor_"):
            continue
        if obj.data.materials.get(COBALT.name) is None:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(
            angle_limit=math.radians(66.0),
            island_margin=0.018,
            area_weight=0.35,
            correct_aspect=True,
            scale_to_bounds=True,
        )
        bpy.ops.object.mode_set(mode="OBJECT")
        obj["bk_uv_pass"] = "RoyalFiligreeSmartProjection20260801"
    bpy.ops.object.select_all(action="DESELECT")
    if previous_active is not None and previous_active.name in bpy.context.view_layer.objects:
        bpy.context.view_layer.objects.active = previous_active


def purge_reference_orphans():
    """Remove source-library datablocks that were not attached to the master."""
    for obj in list(bpy.data.objects):
        if obj.type == "ARMATURE" and obj != ARM:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        suffix = action.name.rsplit(".", 1)[-1]
        if len(suffix) == 3 and suffix.isdigit():
            bpy.data.actions.remove(action, do_unlink=True)
    for armature in list(bpy.data.armatures):
        if armature != ARM.data:
            bpy.data.armatures.remove(armature, do_unlink=True)
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def main():
    for reference_path in (REFERENCE_FULL_BODY, REFERENCE_FACE):
        if not os.path.exists(reference_path):
            raise RuntimeError(f"Approved armor reference is missing: {reference_path}")
    bootstrap_reference_harness()
    refine_mail_material()
    build_unified_connected_helmet()
    build_cuirass_and_waist()
    build_connected_codpiece()
    build_unified_gorget_mantle()
    build_shoulders()
    build_fitted_rerebraces()
    build_fitted_cuisses()
    build_elbows()
    refine_lower_leg_finish()
    refine_gauntlet_finish()
    refine_vambrace_finish()
    clean_cuisse_exposure()
    clean_foundation_exposure()
    remove_unseated_ornaments()
    ensure_armor_uvs()
    # The accepted master already contains the one-time cuisse taper. Avoid
    # repeatedly scaling those vertices when this editable pass is rerun.
    write_editing_guide()
    purge_reference_orphans()
    bpy.context.scene["bk_armor_visual_pass"] = PASS_ID
    bpy.context.scene["bk_armor_reference_full_body"] = REFERENCE_FULL_BODY
    bpy.context.scene["bk_armor_reference_face"] = REFERENCE_FACE
    bpy.context.scene.frame_set(1)
    ARM.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.ops.wm.save_as_mainfile(filepath=MASTER, check_existing=False)
    armor_count = len([obj for obj in bpy.data.objects if obj.name.startswith("RoyalArmor_")])
    print(f"ROYAL_ARMOR_VISUAL_PASS_SAVED|file={MASTER}|armor_objects={armor_count}|pass={PASS_ID}")


if __name__ == "__main__":
    main()
