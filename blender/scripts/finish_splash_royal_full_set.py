"""Finish the splash-reference armor around the accepted forged cuirass.

The pass replaces the closed bucket helmet and shorts-like lower armor with an
open ducal armet, overlapping fauld/tassets, articulated cuisses and poleyns,
fitted greaves, and closed sabatons.  Every decorative element intersects its
supporting plate before the six runtime slots are consolidated.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_SPLASH_FULL_SET_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_SplashRoyalFullSetCandidate.blend"),
))
PASS_ID = "RoyalArmorSplashFullSet20260813V1"
PREFIX = "RoyalArmor_"
BODY = bpy.data.objects["ConnectedBody"]
RIG = bpy.data.objects["HeroRig"]


def material(name):
    result = bpy.data.materials.get(name)
    if result is None:
        raise RuntimeError("Missing armor material: " + name)
    return result


COBALT = material("Royal Cobalt Filigree Plate")
STEEL = material("Royal Blued Steel")
DARK = material("Royal Blackened Steel")
BRASS = material("Royal Gilt Brass")
BRIGHT = material("Royal Planished Edge Steel")
MAIL = material("Riveted Mail")
CRIMSON = material("Ducal Crimson Horsehair")
CRIMSON_DARK = material("Ducal Horsehair Shadow")


def collection(slot):
    root = bpy.data.collections.get("10_ROYAL_ARMOR")
    if root is None:
        root = bpy.data.collections.new("10_ROYAL_ARMOR")
        bpy.context.scene.collection.children.link(root)
    child_name = {
        "head": "10A_ARMOR_HEAD", "chest": "10B_ARMOR_CHEST",
        "shoulders": "10C_ARMOR_SHOULDERS", "hands": "10D_ARMOR_HANDS",
        "pants": "10E_ARMOR_PANTS", "feet": "10F_ARMOR_FEET",
    }[slot]
    child = bpy.data.collections.get(child_name)
    if child is None:
        child = bpy.data.collections.new(child_name)
        root.children.link(child)
    return child


def remove_slot(slot):
    prefix = f"{PREFIX}{slot}_"
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefix):
            bpy.data.objects.remove(obj, do_unlink=True)


def source_group_indices(names):
    result = set()
    for name in names:
        group = BODY.vertex_groups.get(name)
        if group is not None:
            result.add(group.index)
    if not result:
        raise RuntimeError("No body groups found for " + ", ".join(names))
    return result


def weighted(vertex, indices, minimum):
    return any(item.group in indices and item.weight >= minimum for item in vertex.groups)


def copy_weights(obj, remap):
    for source_group in BODY.vertex_groups:
        obj.vertex_groups.new(name=source_group.name)
    for source_index, target_index in remap.items():
        for item in BODY.data.vertices[source_index].groups:
            obj.vertex_groups[item.group].add([target_index], item.weight, "REPLACE")


def armature(obj):
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG


def rigid_skin(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    armature(obj)


def mesh_object(slot, part, vertices, faces, materials, bone=None, smooth=False):
    name = f"{PREFIX}{slot}_{part}"
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection(slot).objects.link(obj)
    for item in materials:
        mesh.materials.append(item)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    if bone:
        rigid_skin(obj, bone)
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_no_floating_parts"] = True
    return obj


def fitted_piece(slot, part, groups, keep, plate_material, outward, thickness=0.007, minimum=0.004):
    indices = source_group_indices(groups)
    flags = [keep(vertex.co) and weighted(vertex, indices, minimum) for vertex in BODY.data.vertices]
    source_faces = [tuple(poly.vertices) for poly in BODY.data.polygons if all(flags[index] for index in poly.vertices)]
    used = sorted({index for face in source_faces for index in face})
    if not used:
        raise RuntimeError(f"No fitted surface selected for {slot}/{part}")
    remap = {source: target for target, source in enumerate(used)}
    vertices = [tuple(BODY.data.vertices[index].co + BODY.data.vertices[index].normal * outward) for index in used]
    faces = [tuple(remap[index] for index in face) for face in source_faces]
    obj = mesh_object(slot, part, vertices, faces, [plate_material, BRASS, DARK], smooth=True)
    copy_weights(obj, remap)
    armature(obj)
    solidify = obj.modifiers.new("OverlappedForgedThickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = -0.45
    solidify.material_offset_rim = 1
    bevel = obj.modifiers.new("RolledConnectedEdge", "BEVEL")
    bevel.width = 0.0024
    bevel.segments = 3
    obj["bk_overlap_fitted"] = True
    return obj


def add_ridge(obj, x_center, z_min, z_max, amount=0.005, width=0.024):
    for vertex in obj.data.vertices:
        if z_min <= vertex.co.z <= z_max:
            fade = math.sin(math.pi * (vertex.co.z - z_min) / max(0.0001, z_max - z_min))
            influence = math.exp(-(((vertex.co.x - x_center) / width) ** 2))
            vertex.co += vertex.normal * amount * influence * fade


def tube(slot, part, points, radii, tube_material, bone, sides=8):
    vertices = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
        if normal.length < 0.00001:
            normal = tangent.cross(Vector((0.0, 1.0, 0.0)))
        normal.normalize()
        binormal = tangent.cross(normal).normalized()
        for side in range(sides):
            angle = math.tau * side / sides
            offset = normal * math.cos(angle) * radii[index] + binormal * math.sin(angle) * radii[index]
            vertices.append(tuple(Vector(point) + offset))
    faces = []
    for ring in range(len(points) - 1):
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((ring * sides + side, ring * sides + nxt, (ring + 1) * sides + nxt, (ring + 1) * sides + side))
    return mesh_object(slot, part, vertices, faces, [tube_material], bone, True)


def closed_prism(slot, part, outline, front_y, rear_y, plate_material, bone):
    front = [(x, front_y, z) for x, z in outline]
    rear = [(x, rear_y, z) for x, z in outline]
    count = len(outline)
    vertices = front + rear
    faces = [tuple(range(count)), tuple(range(count, count * 2))[::-1]]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    obj = mesh_object(slot, part, vertices, faces, [plate_material, BRASS, DARK], bone)
    obj.data.polygons[0].material_index = 0
    obj.data.polygons[1].material_index = 2
    for polygon in obj.data.polygons[2:]:
        polygon.material_index = 1
    bevel = obj.modifiers.new("SeatedPlateEdge", "BEVEL")
    bevel.width = 0.003
    bevel.segments = 3
    return obj


def build_open_ducal_helmet():
    remove_slot("head")
    rings = [
        (1.575, .145, .176, .157, 2.55),
        (1.625, .154, .192, .151, 2.58),
        (1.690, .162, .202, .144, 2.56),
        (1.755, .165, .196, .138, 2.48),
        (1.805, .161, .172, .134, 2.34),
        (1.850, .150, .147, .126, 2.22),
        (1.895, .127, .119, .108, 2.08),
        (1.925, .085, .078, .073, 2.0),
        (1.940, .020, .020, .020, 2.0),
    ]
    segments = 72
    vertices = []
    for z, half_x, front, rear, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear if sine >= 0.0 else front
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            vertices.append((x, y, z))
    faces = []
    face_material = []
    for row in range(len(rings) - 1):
        z_mid = (rings[row][0] + rings[row + 1][0]) * 0.5
        for column in range(segments):
            nxt = (column + 1) % segments
            angle = math.tau * (column + 0.5) / segments
            front_delta = abs((angle - math.pi * 1.5 + math.pi) % math.tau - math.pi)
            # A true face aperture: lower front polygons do not exist.
            if z_mid < 1.805 and front_delta < 0.69:
                continue
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
            face_material.append(1 if front_delta < 1.20 else (2 if z_mid < 1.66 else 0))
    faces.append(tuple((len(rings) - 1) * segments + column for column in range(segments)))
    face_material.append(0)
    helmet = mesh_object("head", "SplashOpenDucalArmet", vertices, faces, [STEEL, COBALT, DARK, BRASS, BRIGHT], "head", True)
    for polygon, index in zip(helmet.data.polygons, face_material):
        polygon.material_index = index
    solidify = helmet.modifiers.new("ForgedHelmetThickness", "SOLIDIFY")
    solidify.thickness = .010
    solidify.offset = -1.0
    bevel = helmet.modifiers.new("RolledFaceAperture", "BEVEL")
    bevel.width = .0028
    bevel.segments = 3

    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        # Narrow swept cheek plates leave the eyes, nose and mouth readable.
        # Their outer edge is buried into the helmet shell, while the pointed
        # lower edge overlaps the gorget instead of ending as a loose square.
        outline = [
            (side * .158, 1.785), (side * .112, 1.790),
            (side * .087, 1.712), (side * .096, 1.625),
            (side * .124, 1.575), (side * .154, 1.615),
        ]
        closed_prism("head", f"SplashIntegratedCheekGuard{suffix}", outline, -.190, -.172, COBALT, "head")
        tube("head", f"SplashCheekGuardRim{suffix}",
             [(side * .124, -.200, 1.578), (side * .096, -.200, 1.625), (side * .087, -.200, 1.712), (side * .112, -.200, 1.788)],
             (.005, .005, .005, .005), BRASS, "head")

    tube("head", "SplashIntegratedBrowCrownRail",
         [(-.148, -.184, 1.790), (-.080, -.205, 1.802), (0, -.214, 1.808), (.080, -.205, 1.802), (.148, -.184, 1.790)],
         (.007, .008, .008, .008, .007), BRASS, "head")
    for index, x in enumerate((-.105, -.052, 0.0, .052, .105)):
        height = 1.875 if index == 2 else (1.854 if index in (1, 3) else 1.835)
        outline = [(x - .024, 1.795), (x + .024, 1.795), (x + .012, 1.825), (x, height), (x - .012, 1.825)]
        closed_prism("head", f"SplashSeatedCrownPoint{index}", outline, -.204, -.145, BRASS, "head")

    # The crest rail intersects the dome; every swept plume ribbon begins
    # inside that rail so no strand is a detached plug.
    closed_prism("head", "SplashPlumeCrestRail", [(-.025, 1.910), (.025, 1.910), (.025, 1.965), (-.025, 1.965)], -.030, .105, BRASS, "head")
    for index in range(34):
        row = index % 9
        layer = index // 9
        x = -.045 + row * .011 + .004 * math.sin(index * 1.37)
        root_y = -.015 + layer * .023
        fan = (row - 4) * .006
        drop = .015 * math.sin(index * 1.11)
        points = (
            (x, root_y, 1.935),
            (x + fan * .08, root_y + .045, 2.015),
            (x + fan * .25, root_y + .120, 2.085 + drop),
            (x + fan * .55, root_y + .225, 2.070 + drop),
            (x + fan * .85, root_y + .345, 1.965 + drop),
            (x + fan * 1.15, root_y + .455, 1.810 - .010 * layer + drop),
        )
        tube("head", f"SplashSweptPlumeRibbon{index:02d}", points,
             (.0065, .0075, .0070, .0058, .0038, .0012),
             CRIMSON if index % 4 else CRIMSON_DARK, "head", 7)


def build_waist_and_tassets():
    # These overlap the lower 20 mm of the accepted cuirass and each other.
    for index, (bottom, top, outward) in enumerate(((.905, 1.015, .030), (.845, .935, .033), (.790, .870, .036))):
        fitted_piece("chest", f"SplashRoyalFauld{index}", ("pelvis", "chest"),
                     lambda co, b=bottom, t=top: b < co.z < t and abs(co.x) < .34,
                     STEEL if index != 1 else COBALT, outward, .008, .003)
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        groups = ("pelvis", f"thigh.{suffix}")
        for row, (bottom, top, outward) in enumerate(((.685, .885, .041), (.555, .735, .044))):
            plate = fitted_piece("chest", f"SplashRoyalTasset{suffix}{row}", groups,
                                 lambda co, s=side, b=bottom, t=top: b < co.z < t and co.x * s > .020 and co.y < .035,
                                 COBALT if row == 0 else STEEL, outward, .008, .003)
            add_ridge(plate, side * .145, bottom + .02, top - .02, .0045, .030)
        for row, (bottom, top, outward) in enumerate(((.700, .885, .038), (.585, .735, .041))):
            fitted_piece("chest", f"SplashRoyalCulet{suffix}{row}", groups,
                         lambda co, s=side, b=bottom, t=top: b < co.z < t and co.x * s > .018 and co.y > -.020,
                         DARK if row == 0 else STEEL, outward, .008, .003)
        # A shaped front tasset overlaps both the fauld and the fitted lower
        # tasset foundation.  It is rigid to the pelvis, as real suspended
        # armor is, so the thigh can pass underneath during walking.
        if side < 0:
            outline = [(-.035, .875), (-.215, .845), (-.220, .715), (-.175, .575), (-.070, .600)]
        else:
            outline = [( .035, .875), ( .215, .845), ( .220, .715), ( .175, .575), ( .070, .600)]
        panel = closed_prism("chest", f"SplashRoyalFrontTassetShield{suffix}", outline, -.153, -.134, COBALT, "pelvis")
        panel["bk_suspended_over_thigh"] = True
        # One seated diagonal flute gives each plate a heraldic direction
        # without gluing a badge onto its face.
        start = (side * .070, -.157, .855)
        middle = (side * .125, -.159, .730)
        end = (side * .165, -.157, .600)
        tube("chest", f"SplashRoyalTassetFlute{suffix}", (start, middle, end), (.004, .005, .004), BRASS, "pelvis")


def build_articulated_legs():
    remove_slot("pants")
    remove_slot("feet")
    fitted_piece("pants", "SplashMailChausses", ("pelvis", "thigh.L", "thigh.R"),
                 lambda co: .405 < co.z < 1.010 and abs(co.x) < .33,
                 MAIL, .010, .003, .003)
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        center_x = -.145 if side < 0 else .145
        thigh = (f"thigh.{suffix}",)
        shin = (f"shin.{suffix}",)
        upper = fitted_piece("pants", f"SplashRoyalCuisse{suffix}Upper", thigh,
                             lambda co: .625 < co.z < .930 and co.y < .035, COBALT, .031, .008, .004)
        lower = fitted_piece("pants", f"SplashRoyalCuisse{suffix}Lower", thigh,
                             lambda co: .475 < co.z < .675 and co.y < .040, STEEL, .035, .008, .004)
        add_ridge(upper, center_x, .65, .91, .006, .026)
        add_ridge(lower, center_x, .50, .66, .005, .024)
        # The central rigid plate is half buried into the fitted cuisse. It
        # turns the front silhouette into a forged thigh defense rather than
        # a metallic pair of shorts.
        outline = [
            (center_x - .070, .885), (center_x + .070, .885),
            (center_x + .076, .735), (center_x + .052, .535),
            (center_x, .485), (center_x - .052, .535),
            (center_x - .076, .735),
        ]
        cuisse_shield = closed_prism("pants", f"SplashRoyalCuisseShield{suffix}", outline, -.150, -.131, COBALT, f"thigh.{suffix}")
        cuisse_shield["bk_embedded_in_cuisse"] = True
        tube("pants", f"SplashCuisseShieldKeel{suffix}",
             [(center_x, -.155, .505), (center_x, -.160, .700), (center_x, -.155, .885)],
             (.004, .0055, .004), BRASS, f"thigh.{suffix}")

        fitted_piece("feet", f"SplashRoyalKneeCup{suffix}", (f"thigh.{suffix}", f"shin.{suffix}"),
                     lambda co: .420 < co.z < .625, DARK, .030, .008, .003)
        outline = [
            (center_x - .090, .555), (center_x, .635), (center_x + .090, .555),
            (center_x + .072, .455), (center_x, .405), (center_x - .072, .455),
        ]
        closed_prism("feet", f"SplashRoyalPoleynShield{suffix}", outline, -.145, -.058, COBALT, f"shin.{suffix}")
        tube("feet", f"SplashPoleynKeel{suffix}",
             [(center_x, -.151, .425), (center_x, -.158, .520), (center_x, -.151, .615)],
             (.0045, .0060, .0045), BRASS, f"shin.{suffix}")

        greave = fitted_piece("feet", f"SplashRoyalGreave{suffix}", shin,
                              lambda co: .080 < co.z < .505, STEEL, .031, .009, .004)
        add_ridge(greave, center_x, .105, .485, .0065, .022)
        # Two buried gilt flutes strengthen the readable front silhouette.
        for offset in (-.046, .046):
            tube("feet", f"SplashGreaveFlute{suffix}{'L' if offset < 0 else 'R'}",
                 [(center_x + offset * .72, -.105, .110), (center_x + offset, -.126, .300), (center_x + offset * .80, -.118, .475)],
                 (.0035, .0040, .0035), BRASS, f"shin.{suffix}")
        build_sabaton(side, suffix)


def build_sabaton(side, suffix):
    center_x = -.205 if side < 0 else .205
    sections = [
        (.055, .073, .105, .087),
        (-.015, .088, .082, .064),
        (-.105, .102, .062, .050),
        (-.205, .108, .047, .038),
        (-.292, .082, .034, .026),
    ]
    ring_segments = 16
    vertices = []
    for y, half_x, center_z, half_z in sections:
        for segment in range(ring_segments):
            angle = math.tau * segment / ring_segments
            vertices.append((center_x + half_x * math.cos(angle), y, center_z + half_z * math.sin(angle)))
    faces = []
    for row in range(len(sections) - 1):
        for segment in range(ring_segments):
            nxt = (segment + 1) % ring_segments
            faces.append((row * ring_segments + segment, row * ring_segments + nxt, (row + 1) * ring_segments + nxt, (row + 1) * ring_segments + segment))
    faces.append(tuple(range(ring_segments))[::-1])
    faces.append(tuple((len(sections) - 1) * ring_segments + index for index in range(ring_segments)))
    sabaton = mesh_object("feet", f"SplashClosedSabaton{suffix}", vertices, faces, [DARK, STEEL, COBALT, BRASS], f"foot.{suffix}", True)
    for polygon in sabaton.data.polygons:
        if polygon.index < (len(sections) - 1) * ring_segments:
            polygon.material_index = 1 if (polygon.index // ring_segments) % 2 == 0 else 2
    bevel = sabaton.modifiers.new("SabatonPlanishedEdges", "BEVEL")
    bevel.width = .0026
    bevel.segments = 3
    top_points = [(center_x, y, center_z + half_z - .002) for y, half_x, center_z, half_z in sections]
    tube("feet", f"SplashSabatonKeel{suffix}", top_points, (.0035,) * len(top_points), BRASS, f"foot.{suffix}")


def main():
    RIG.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    build_open_ducal_helmet()
    build_waist_and_tassets()
    build_articulated_legs()
    RIG.data.pose_position = "POSE"
    RIG.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.scene["bk_armor_visual_pass"] = PASS_ID
    bpy.context.scene["bk_armor_reference_match"] = "open_ducal_helmet_articulated_lower_harness"
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print("SPLASH_ROYAL_FULL_SET|file=%s|pass=%s" % (OUTPUT, PASS_ID))


if __name__ == "__main__":
    main()
