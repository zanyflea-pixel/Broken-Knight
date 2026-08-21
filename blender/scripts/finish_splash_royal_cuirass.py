"""Finish the splash hybrid with one closed forged royal cuirass.

The body-fitted mail and waist articulation remain underneath.  The visible
torso becomes a rigid tapered shell with integral pectoral planes, plackart,
rolled overlap bands and a seated Broken Crown relief.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_SPLASH_CUIRASS_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_SplashRoyalCandidate.blend"),
))
PASS_ID = "RoyalArmorSplashForgedCuirass20260813V1"
RIG = bpy.data.objects["HeroRig"]


def material(name):
    result = bpy.data.materials.get(name)
    if result is None:
        raise RuntimeError(f"Missing material: {name}")
    return result


STEEL = material("Royal Blued Steel")
COBALT = material("Royal Cobalt Filigree Plate")
DARK = material("Royal Blackened Steel")
BRASS = material("Royal Gilt Brass")
BRIGHT = material("Royal Planished Edge Steel")


def remove_prefix(prefix):
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefix):
            bpy.data.objects.remove(obj, do_unlink=True)


def chest_collection():
    result = bpy.data.collections.get("10B_ARMOR_CHEST")
    if result is None:
        raise RuntimeError("10B_ARMOR_CHEST collection is missing")
    return result


def skin_rigid(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_connected_construction"] = True


def profile_at(rings, z):
    lower, upper = rings[0], rings[-1]
    for index in range(len(rings) - 1):
        if rings[index][0] <= z <= rings[index + 1][0]:
            lower, upper = rings[index], rings[index + 1]
            break
    t = (z - lower[0]) / max(1e-6, upper[0] - lower[0])
    return tuple(lower[value] + (upper[value] - lower[value]) * t for value in range(1, 5))


def shell_y(rings, x, z, front=True):
    half_x, front_depth, rear_depth, exponent = profile_at(rings, z)
    ratio = max(0.0, min(0.999, abs(x) / max(half_x, 1e-6)))
    cosine = ratio ** (exponent * 0.5)
    sine = math.sqrt(max(0.0, 1.0 - cosine * cosine))
    return (-front_depth if front else rear_depth) * (sine ** (2.0 / exponent))


def make_shell(name, rings, materials, bone, segments=96, thickness=0.010, bevel=0.003):
    dense = []
    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        for step in range(3):
            t = step / 3.0
            dense.append(tuple(lower[i] + (upper[i] - lower[i]) * t for i in range(len(lower))))
    dense.append(rings[-1])
    rings = dense
    vertices = []
    for z, half_x, front_depth, rear_depth, exponent in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            cosine, sine = math.cos(angle), math.sin(angle)
            x = half_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            depth = rear_depth if sine >= 0.0 else front_depth
            y = depth * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            if sine < 0.0:
                frontness = abs(sine) ** 8
                vertical = max(0.0, math.sin(max(0.0, min(1.0, (z - 1.005) / 0.555)) * math.pi))
                # Single tapul keel and two restrained pectoral planes.  The
                # planes are forged into one shell, never anatomical domes.
                keel = 0.015 * math.exp(-((x / 0.040) ** 2)) * vertical
                pec = 0.007 * math.exp(-(((abs(x) - 0.105) / 0.115) ** 4)) * math.exp(-(((z - 1.405) / 0.105) ** 2))
                lower_flute = 0.004 * math.exp(-(((abs(x) - 0.135) / 0.022) ** 2)) * math.exp(-(((z - 1.150) / 0.135) ** 2))
                y -= (keel + pec + lower_flute) * frontness
            vertices.append((x, y, z))
    faces = []
    for row in range(len(rings) - 1):
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    chest_collection().objects.link(obj)
    for value in materials:
        mesh.materials.append(value)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        row = polygon.index // segments
        column = polygon.index % segments
        z = (rings[row][0] + rings[row + 1][0]) * 0.5
        angle = math.tau * (column + 0.5) / segments
        front_delta = abs((angle - 1.5 * math.pi + math.pi) % math.tau - math.pi)
        back_delta = abs((angle - 0.5 * math.pi + math.pi) % math.tau - math.pi)
        if any(abs(z - band) < 0.010 for band in (rings[0][0] + 0.010, rings[-1][0] - 0.010)):
            polygon.material_index = 2
        elif 0.70 < front_delta < 1.18:
            polygon.material_index = 1
        elif back_delta < 0.62:
            polygon.material_index = 0
        else:
            polygon.material_index = 0
    skin_rigid(obj, bone)
    solid = obj.modifiers.new("ForgedPlateThickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = -0.65
    solid.material_offset_rim = 2
    edge = obj.modifiers.new("RolledForgedEdges", "BEVEL")
    edge.width = bevel
    edge.segments = 3
    obj["bk_profile_rings"] = str(rings)
    return obj, rings


def make_tube(name, points, radii, material, bone="chest", sides=8):
    vertices = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
        if normal.length < 1e-5:
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
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    chest_collection().objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    skin_rigid(obj, bone)
    return obj


def add_relief(cuirass, rings):
    paths = (
        ("Keel", ((0.0, 1.090), (0.0, 1.515)), 0.0050),
        ("Shield", ((-0.090, 1.445), (-0.050, 1.505), (0.0, 1.525), (0.050, 1.505), (0.090, 1.445), (0.082, 1.300), (0.0, 1.195), (-0.082, 1.300), (-0.090, 1.445)), 0.0045),
        ("CrownL", ((0.0, 1.430), (-0.038, 1.466), (-0.070, 1.500), (-0.104, 1.452)), 0.0040),
        ("CrownR", ((0.0, 1.430), (0.038, 1.466), (0.070, 1.500), (0.104, 1.452)), 0.0040),
        ("BreastArcL", ((-0.095, 1.465), (-0.180, 1.440), (-0.255, 1.380)), 0.0036),
        ("BreastArcR", ((0.095, 1.465), (0.180, 1.440), (0.255, 1.380)), 0.0036),
        ("LowerL", ((0.0, 1.175), (-0.110, 1.205), (-0.230, 1.145)), 0.0034),
        ("LowerR", ((0.0, 1.175), (0.110, 1.205), (0.230, 1.145)), 0.0034),
    )
    relief = []
    for label, path, radius in paths:
        points = []
        for x, z in path:
            # Half the tube is buried in the finished shell.
            points.append((x, shell_y(rings, x, z, True) - 0.012, z))
        relief.append(make_tube(f"RoyalArmor_chest_SplashIntegralRelief{label}", points, tuple(radius for _ in points), BRASS))

    # The rear heraldry uses the same half-buried construction as the front.
    # It breaks up the broad backplate without adding any disconnected badges.
    back_paths = (
        ("BackSpine", ((0.0, 1.080), (0.0, 1.515)), 0.0042),
        ("BackCrownL", ((0.0, 1.420), (-0.045, 1.470), (-0.095, 1.505), (-0.135, 1.450)), 0.0037),
        ("BackCrownR", ((0.0, 1.420), (0.045, 1.470), (0.095, 1.505), (0.135, 1.450)), 0.0037),
        ("BackChevronL", ((0.0, 1.210), (-0.120, 1.250), (-0.245, 1.205)), 0.0035),
        ("BackChevronR", ((0.0, 1.210), (0.120, 1.250), (0.245, 1.205)), 0.0035),
    )
    for label, path, radius in back_paths:
        points = []
        for x, z in path:
            # Positive Y is the rear surface.  Keeping the tube centre only
            # 2 mm proud leaves more than half of the trim embedded in plate.
            points.append((x, shell_y(rings, x, z, False) + 0.002, z))
        relief.append(make_tube(f"RoyalArmor_chest_SplashIntegralRelief{label}", points, tuple(radius for _ in points), BRASS))
    bpy.ops.object.select_all(action="DESELECT")
    cuirass.select_set(True)
    for obj in relief:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = cuirass
    bpy.ops.object.join()
    cuirass.name = "RoyalArmor_chest_SplashForgedRoyalCuirass"
    cuirass.data.name = cuirass.name + "_Mesh"


def main():
    for prefix in (
        "RoyalArmor_chest_SplashAnatomicalBreastplate",
        "RoyalArmor_chest_SplashPectoralPlate",
        "RoyalArmor_chest_SplashOverlappingPlackart",
        "RoyalArmor_chest_SplashRelief",
        "RoyalArmor_chest_SplashIntegralRelief",
        "RoyalArmor_chest_SplashForgedRoyalCuirass",
    ):
        remove_prefix(prefix)

    cuirass, rings = make_shell(
        "RoyalArmor_chest_SplashForgedRoyalCuirass",
        [
            (1.000, 0.242, 0.164, 0.154, 2.45),
            (1.075, 0.260, 0.178, 0.162, 2.46),
            (1.165, 0.286, 0.194, 0.171, 2.44),
            (1.275, 0.312, 0.207, 0.179, 2.40),
            (1.385, 0.324, 0.212, 0.182, 2.36),
            (1.465, 0.315, 0.205, 0.178, 2.36),
            (1.525, 0.288, 0.190, 0.168, 2.40),
            (1.565, 0.228, 0.172, 0.154, 2.48),
        ],
        [COBALT, DARK, BRASS, BRIGHT], "chest",
    )
    add_relief(cuirass, rings)
    bpy.context.scene["bk_armor_visual_pass"] = PASS_ID
    RIG.data.pose_position = "POSE"
    RIG.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print(f"SPLASH_ROYAL_CUIRASS|file={OUTPUT}|pass={PASS_ID}")


if __name__ == "__main__":
    main()
