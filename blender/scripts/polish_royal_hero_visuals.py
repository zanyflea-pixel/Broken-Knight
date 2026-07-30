"""Final cohesive visual polish for the accepted Royal Vanguard hero.

This pass deliberately preserves armor fit, weights, and every animation.  It
replaces the sparse rod-like helmet crest with a continuous horsehair fan,
adds flush functional visor ventilation, and seats a shallow heraldic relief
into the otherwise empty breastplate.
"""

import bpy
import math


ARM = bpy.data.objects["HeroRig"]
PREFIX = "RoyalArmor_"


def mat(name):
    material = bpy.data.materials.get(name)
    if material is None:
        raise RuntimeError(f"Missing material: {name}")
    return material


COBALT = mat("Royal Cobalt Filigree Plate")
STEEL = mat("Royal Blued Steel")
BRIGHT = mat("Royal Planished Edge Steel")
DARK = mat("Royal Blackened Steel")
BRASS = mat("Royal Gilt Brass")
BLACK = mat("Helmet Interior")
CRIMSON = mat("Ducal Crimson Horsehair")
CRIMSON_DARK = mat("Ducal Horsehair Shadow")


def tune_material(material, metallic, roughness):
    material["export_metallic"] = metallic
    material["export_roughness"] = roughness
    if not material.use_nodes:
        return
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Metallic"].default_value = metallic
        if not bsdf.inputs["Roughness"].is_linked:
            bsdf.inputs["Roughness"].default_value = roughness


# Slightly broader highlights and less mirror-like brass make the harness read
# as used forged armor instead of glossy molded plastic.
tune_material(STEEL, .86, .40)
tune_material(BRIGHT, .90, .35)
tune_material(DARK, .80, .48)
tune_material(BRASS, .78, .43)
tune_material(CRIMSON, .02, .76)
tune_material(CRIMSON_DARK, .01, .86)


def remove_named(fragment):
    for obj in list(bpy.data.objects):
        if fragment in obj.name:
            bpy.data.objects.remove(obj, do_unlink=True)


remove_named("FinalPolish")
# The previous crest consisted of separated cones and read as spikes.  Keep its
# mechanically seated comb/rail but replace only the horsehair.
for obj in list(bpy.data.objects):
    if obj.name.startswith(PREFIX + "head_ApexUnifiedHorsehair"):
        bpy.data.objects.remove(obj, do_unlink=True)


def bind(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("HeroRigDeform", "ARMATURE")
    modifier.object = ARM
    obj.parent = ARM
    obj["royal_final_polish"] = True
    obj["armor_slot"] = obj.name[len(PREFIX):].split("_", 1)[0]
    obj.select_set(False)
    return obj


def front_prism(slot, name, outline, back_y, front_y, material, bone, bevel=.0018):
    vertices = [(x, front_y, z) for x, z in outline] + [(x, back_y, z) for x, z in outline]
    count = len(outline)
    faces = [tuple(range(count)), tuple(range(2 * count - 1, count - 1, -1))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    obj = bpy.data.objects.new(f"{PREFIX}{slot}_{name}", mesh)
    bpy.context.scene.collection.objects.link(obj)
    if bevel:
        edge = obj.modifiers.new("SeatedReliefEdge", "BEVEL")
        edge.width = bevel
        edge.segments = 3
    return bind(obj, bone)


def lofted_plume():
    # A thin fore-to-aft horsehair fan replaces the old rounded football-like
    # mass.  It remains one closed piece seated in the crest rail, but reads as
    # a Roman/ducal plume from both the front and side.
    sections = [
        # y, bottom z, top z, half width
        (-.145, 1.936, 2.010, .013),
        (-.105, 1.938, 2.105, .025),
        (-.040, 1.940, 2.175, .035),
        (.045, 1.940, 2.198, .040),
        (.125, 1.936, 2.165, .036),
        (.205, 1.928, 2.090, .027),
        (.270, 1.916, 2.010, .014),
    ]
    vertices = []
    for y, bottom_z, top_z, half_x in sections:
        vertices.extend((
            (-half_x, y, bottom_z),
            ( half_x, y, bottom_z),
            (-half_x, y, top_z),
            ( half_x, y, top_z),
        ))
    faces = []
    for index in range(len(sections) - 1):
        a = index * 4
        b = (index + 1) * 4
        faces.extend((
            (a, b, b + 2, a + 2),
            (a + 1, a + 3, b + 3, b + 1),
            (a + 2, b + 2, b + 3, a + 3),
            (a, a + 1, b + 1, b),
        ))
    faces.append((0, 2, 3, 1))
    last = (len(sections) - 1) * 4
    faces.append((last, last + 1, last + 3, last + 2))
    mesh = bpy.data.meshes.new("FinalPolishSweptHorsehairMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(CRIMSON)
    mesh.materials.append(CRIMSON_DARK)
    for polygon in mesh.polygons:
        polygon.material_index = 1 if polygon.index % 4 in (0, 3) else 0
    obj = bpy.data.objects.new(f"{PREFIX}head_FinalPolishSweptHorsehair", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bevel = obj.modifiers.new("BoundHorsehairSoftness", "BEVEL")
    bevel.width = .0025
    bevel.segments = 3
    return bind(obj, "head")


def curve_relief(slot, name, points, radius, material, bone):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(f"{PREFIX}{slot}_{name}", curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    return bind(obj, bone)


def helmet_front_y(x, z):
    rings = [
        (1.628, .126, .192, 2.48),
        (1.658, .132, .194, 2.50),
        (1.688, .138, .191, 2.50),
        (1.718, .144, .186, 2.46),
    ]
    lower = rings[0]
    upper = rings[-1]
    for a, b in zip(rings, rings[1:]):
        if a[0] <= z <= b[0]:
            lower, upper = a, b
            break
    t = max(0.0, min(1.0, (z - lower[0]) / max(.0001, upper[0] - lower[0])))
    half_x = lower[1] * (1 - t) + upper[1] * t
    depth = lower[2] * (1 - t) + upper[2] * t
    exponent = lower[3] * (1 - t) + upper[3] * t
    cosine = min(.999, abs(x) / half_x) ** (exponent / 2.0)
    sine = math.sqrt(max(.001, 1.0 - cosine * cosine))
    return -depth * sine ** (2.0 / exponent)


def inset_vent(name, x, z):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16,
        ring_count=8,
        location=(x, helmet_front_y(x, z) - .0008, z),
    )
    obj = bpy.context.object
    obj.name = f"{PREFIX}head_{name}"
    obj.scale = (.0060, .0035, .0140)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(BLACK)
    return bind(obj, "head")


lofted_plume()

# Shallow locks sit on both broad faces of the fan.  Their sub-millimetre
# relief breaks up the solid red fin without returning to detached hair spikes.
for side in (-1, 1):
    suffix = "L" if side < 0 else "R"
    for index in range(4):
        drift = (index - 1.5) * .0045
        curve_relief(
            "head",
            f"FinalPolishHorsehairLayer{suffix}{index:02d}",
            [
                (side * .015, -.130 + drift, 1.956),
                (side * .027, -.090 + drift, 2.080),
                (side * .037, -.022 + drift, 2.158),
                (side * .041, .052 + drift, 2.181),
                (side * .036, .132 + drift, 2.140),
                (side * .025, .218 + drift, 2.052),
            ],
            .0009,
            CRIMSON_DARK,
            "head",
        )

# Flush dark ventilation apertures integrated into the bevor.  They protrude
# less than a millimetre beyond the helmet surface and read as recesses.
for side in (-1, 1):
    suffix = "L" if side < 0 else "R"
    for column, x in enumerate((.050, .080, .108)):
        inset_vent(f"FinalPolishBevorVent{suffix}{column}", side * x, 1.672 + column * .014)

def cuirass_point(x, z, outward=.0025):
    rings = [
        (.970, .242, .155), (1.055, .262, .170), (1.165, .300, .190),
        (1.300, .330, .205), (1.420, .334, .202), (1.485, .318, .190),
    ]
    lower = rings[0]
    upper = rings[-1]
    for a, b in zip(rings, rings[1:]):
        if a[0] <= z <= b[0]:
            lower, upper = a, b
            break
    t = max(0.0, min(1.0, (z - lower[0]) / max(.0001, upper[0] - lower[0])))
    half_x = lower[1] * (1 - t) + upper[1] * t
    depth = lower[2] * (1 - t) + upper[2] * t
    # The accepted cuirass includes a 13 mm planished outer relief beyond its
    # construction profile.  Account for that layer so the ornament remains
    # half-seated in the metal instead of being hidden behind it.
    y = -(depth + .013) * math.sqrt(max(.01, 1.0 - (x / half_x) ** 2)) - outward
    return (x, y, z)


# Surface-conforming line relief stays embedded along the convex breastplate
# instead of behaving like a flat badge hovering over it.
shield_outline = [
    (-.105, 1.385), (.105, 1.385), (.092, 1.268),
    (0, 1.198), (-.092, 1.268), (-.105, 1.385),
]
curve_relief(
    "chest",
    "FinalPolishHeraldicShield",
    [cuirass_point(x, z) for x, z in shield_outline],
    .0048,
    BRASS,
    "chest",
)
crown_line = [
    (-.105, 1.405), (-.082, 1.452), (-.041, 1.423),
    (0, 1.472), (.041, 1.423), (.082, 1.452), (.105, 1.405),
]
curve_relief(
    "chest",
    "FinalPolishCrown",
    [cuirass_point(x, z) for x, z in crown_line],
    .0045,
    BRASS,
    "chest",
)
curve_relief(
    "chest",
    "FinalPolishCrownBase",
    [cuirass_point(-.105, 1.405), cuirass_point(.105, 1.405)],
    .0042,
    BRASS,
    "chest",
)
for obj in bpy.data.objects:
    if obj.name.startswith(PREFIX):
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False

bpy.context.scene["royal_final_visual_polish"] = "bound plume, visor ventilation, seated breastplate heraldry, forged roughness"
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)

polish_objects = [obj for obj in bpy.data.objects if obj.get("royal_final_polish")]
print(f"ROYAL_FINAL_VISUAL_POLISH|objects={len(polish_objects)}|file={bpy.data.filepath}")
