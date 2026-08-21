"""Build a fitted royal arming sword and heater shield as real Blender assets.

The game previously assembled both weapons from Godot boxes and spheres.  These
assets use continuous forged surfaces, integrated borders, seated relief, and
real back-side hardware.  Their origins are placed at the hand grips.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "blender", "royal_vanguard_weapons.blend")
SWORD_OUT = os.path.join(ROOT, "godot", "assets", "equipment", "royal_vanguard_sword.glb")
SHIELD_OUT = os.path.join(ROOT, "godot", "assets", "equipment", "royal_vanguard_shield.glb")
PREVIEW_OUT = os.path.join(ROOT, "blender", "previews", "royal_weapons", "royal_vanguard_weapons.png")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def finish_mesh(obj, materials, bevel=0.004, smooth=False):
    for mat in materials:
        obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("HandForgedRolledEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def mesh_object(name, vertices, faces, materials, material_indices=None, bevel=0.004, parent=None):
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    finish_mesh(obj, materials, bevel)
    if material_indices:
        for polygon, index in zip(obj.data.polygons, material_indices):
            polygon.material_index = index
    obj.parent = parent
    return obj


def cylinder(name, location, radius, depth, mat, parent, rotation=(0, 0, 0), vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    return finish_mesh(obj, (mat,), 0.002, True)


def sphere(name, location, scale, mat, parent, segments=32, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.parent = parent
    return finish_mesh(obj, (mat,), 0, True)


def tube(name, points, radius, mat, parent, resolution=3):
    curve = bpy.data.curves.new(f"{name}Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = parent
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    return obj


def prism(name, outline, front_y, back_y, mat, parent, bevel=0.003):
    count = len(outline)
    vertices = [(x, front_y, z) for x, z in outline] + [(x, back_y, z) for x, z in outline]
    faces = [tuple(range(count)), tuple(range(count * 2 - 1, count - 1, -1))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))
    return mesh_object(name, vertices, faces, (mat,), bevel=bevel, parent=parent)


def shield_surface_y(x, z):
    """Approximate the authored heater crown at a point on its front field."""
    radial = min(1.0, ((x / .33) ** 2 + ((z - .075) / .45) ** 2) ** .5)
    return -.094 + .028 * radial


def conforming_shield_relief(name, outline, mat, parent):
    """Build a shallow crest that follows and intersects the shield field."""
    count = len(outline)
    front = [(x, shield_surface_y(x, z) - .0025, z) for x, z in outline]
    # The rear face sits 0.8 mm inside the steel field.  That intentional
    # overlap makes the repoussé read as one piece of armor and removes the
    # coplanar faces that shimmered in Godot.
    back = [(x, shield_surface_y(x, z) + .0008, z) for x, z in outline]
    vertices = front + back
    faces = [tuple(range(count)), tuple(range(count * 2 - 1, count - 1, -1))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))
    return mesh_object(name, vertices, faces, (mat,), bevel=.0012, parent=parent)


def build_blade(parent, steel, edge, cobalt):
    # Four-sided diamond sections create a continuous rigid blade with a real
    # medial ridge.  The blue fuller is assigned to faces of this same mesh.
    stations = (
        (0.115, 0.060, 0.010),
        (0.250, 0.058, 0.010),
        (0.700, 0.049, 0.009),
        (0.985, 0.030, 0.007),
        (1.075, 0.002, 0.002),
    )
    vertices = []
    for z, width, thickness in stations:
        vertices.extend(
            (
                (-width, 0, z),
                (0, -thickness, z),
                (width, 0, z),
                (0, thickness, z),
            )
        )
    faces = []
    indices = []
    for row in range(len(stations) - 1):
        base = row * 4
        next_base = (row + 1) * 4
        for side in range(4):
            nxt = (side + 1) % 4
            faces.append((base + side, base + nxt, next_base + nxt, next_base + side))
            indices.append(2 if side in (0, 1) and row in (1, 2) else (1 if side in (2, 3) else 0))
    faces.extend(((0, 3, 2, 1), (16, 17, 18, 19)))
    indices.extend((0, 1))
    blade = mesh_object(
        "RoyalSword_ForgedBlade", vertices, faces, (steel, edge, cobalt),
        indices, bevel=0.0015, parent=parent,
    )
    blade["continuous_forged_blade"] = True
    return blade


def build_sword(materials):
    steel, edge, cobalt, brass, leather, dark = materials
    root = bpy.data.objects.new("RoyalVanguardSwordAsset", None)
    bpy.context.collection.objects.link(root)
    root["asset_type"] = "royal_vanguard_sword"
    root["grip_origin"] = "hand.R"

    build_blade(root, steel, edge, cobalt)
    # Seated blue fuller terminates before the point and is less than 2 mm proud.
    prism(
        "RoyalSword_SeatedFuller",
        [(-.010, .205), (.010, .205), (.008, .850), (0, .930), (-.008, .850)],
        -.0108, -.0092, cobalt, root, .001,
    )
    prism(
        "RoyalSword_RainGuard",
        [(-.050, .115), (.050, .115), (.040, .155), (-.040, .155)],
        -.020, .020, brass, root, .003,
    )

    # A compact, thick crossguard is one continuous forged member passing
    # through a broad center block.  The previous thin 57 cm tube read as an
    # unexplained line coming out of the hand.
    guard_points = (
        (-.225, 0, .096), (-.185, 0, .112), (-.095, 0, .130),
        (0, 0, .136), (.095, 0, .130), (.185, 0, .112), (.225, 0, .096),
    )
    tube("RoyalSword_ContinuousCrossguard", guard_points, .023, edge, root, 5)
    prism(
        "RoyalSword_IntegratedGuardBlock",
        [(-.072,.112),(.072,.112),(.060,.162),(-.060,.162)],
        -.028,.028,brass,root,.004,
    )
    sphere("RoyalSword_QuillonL", (-.227, 0, .094), (.030, .026, .030), brass, root, 24, 14)
    sphere("RoyalSword_QuillonR", (.227, 0, .094), (.030, .026, .030), brass, root, 24, 14)
    cylinder("RoyalSword_GripCore", (0, 0, -.025), .026, .255, leather, root, vertices=36)

    helix = []
    for index in range(65):
        t = index / 64.0
        angle = t * math.tau * 6.0
        helix.append((math.cos(angle) * .0285, math.sin(angle) * .0285, -.145 + t * .240))
    tube("RoyalSword_LeatherSpiralWrap", helix, .0035, brass, root, 2)
    cylinder("RoyalSword_UpperGripCollar", (0, 0, .103), .034, .020, brass, root, vertices=32)
    cylinder("RoyalSword_LowerGripCollar", (0, 0, -.155), .034, .020, brass, root, vertices=32)
    sphere("RoyalSword_WheelPommel", (0, 0, -.205), (.070, .034, .066), steel, root, 40, 24)
    sphere("RoyalSword_PommelCabochonFront", (0, -.035, -.205), (.025, .007, .025), cobalt, root, 24, 14)
    sphere("RoyalSword_PommelCabochonBack", (0, .035, -.205), (.025, .007, .025), cobalt, root, 24, 14)
    return root


def build_shield(materials):
    steel, edge, cobalt, brass, leather, dark = materials
    root = bpy.data.objects.new("RoyalVanguardShieldAsset", None)
    bpy.context.collection.objects.link(root)
    root["asset_type"] = "royal_vanguard_heater_shield"
    root["grip_origin"] = "hand.L"

    outer = (
        (-.335, .500), (.335, .500), (.365, .360), (.350, .105),
        (.282, -.205), (0, -.515), (-.282, -.205), (-.350, .105), (-.365, .360),
    )
    center = Vector((0, .075))
    inner = []
    for x, z in outer:
        point = Vector((x, z)).lerp(center, .095)
        inner.append((point.x, point.y))
    vertices = []
    # Rolled outer rim, crowned inner field, one back plate.
    vertices.extend((x, -.042, z) for x, z in outer)
    vertices.extend((x, -.066, z) for x, z in inner)
    vertices.append((0, -.094, .075))
    vertices.extend((x, .030, z) for x, z in outer)
    count = len(outer)
    hub = count * 2
    back = hub + 1
    faces = []
    indices = []
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
        indices.append(3)
        faces.append((count + index, count + nxt, hub))
        indices.append(2)
        faces.append((index, back + index, back + nxt, nxt))
        indices.append(1)
    faces.append(tuple(back + index for index in range(count - 1, -1, -1)))
    indices.append(5)
    shield = mesh_object(
        "RoyalShield_ContinuousHeaterShell", vertices, faces,
        (steel, edge, cobalt, brass, leather, dark), indices, .006, root,
    )
    shield["integrated_rolled_rim"] = True

    # The crest is a single shallow repoussé plate intersecting the shield face.
    crest_outline = [
        (-.145, .235), (-.145, .125), (-.105, .125), (-.120, .205),
        (-.060, .160), (0, .270), (.060, .160), (.120, .205),
        (.105, .125), (.145, .125), (.145, .235),
    ]
    crest = conforming_shield_relief("FlushRealmCrest", crest_outline, brass, root)
    crest["relief_depth_m"] = .0033
    sphere("RoyalShield_SeatedBoss", (0, -.103, .040), (.074, .025, .074), edge, root, 36, 20)
    sphere("RoyalShield_BossCabochon", (0, -.130, .040), (.026, .008, .026), cobalt, root, 24, 14)
    for side in (-1, 1):
        for z in (.390, -.105):
            sphere(
                f"RoyalShield_SeatedRivet_{side}_{z}", (side * .285, -.060, z),
                (.011, .006, .011), brass, root, 20, 12,
            )

    # Back hardware is modeled where it can actually be held.
    tube(
        "RoyalShield_ForearmStrap",
        ((-.190, .048, .220), (-.105, .105, .245), (.105, .105, .245), (.190, .048, .220)),
        .020, leather, root, 3,
    )
    tube(
        "RoyalShield_HandGrip",
        ((-.115, .060, -.030), (-.065, .120, -.020), (.065, .120, -.020), (.115, .060, -.030)),
        .018, leather, root, 3,
    )
    for x in (-.190, .190, -.115, .115):
        z = .220 if abs(x) > .15 else -.030
        sphere(f"RoyalShield_BackRivet_{x}", (x, .044, z), (.015, .008, .015), brass, root, 20, 12)
    return root


def descendants(root):
    output = [root]
    for child in root.children:
        output.extend(descendants(child))
    return output


def export_asset(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in descendants(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_lights=False,
        export_cameras=False,
        export_apply=True,
    )
    print(f"ROYAL_WEAPON_EXPORTED|{root.name}|{filepath}")


def render_preview(sword, shield, dark):
    os.makedirs(os.path.dirname(PREVIEW_OUT), exist_ok=True)
    sword.location.x = -.55
    sword.location.z = .25
    shield.location.x = .55
    shield.location.z = .20
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (.008, .010, .018)
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.006, .009, .018, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .18
    for name, location, energy, color, size in (
        ("WeaponKey", (3.2, -4.2, 3.6), 700, (1.0, .78, .55), 3.0),
        ("WeaponFill", (-3.0, -2.8, 2.7), 450, (.35, .52, 1.0), 3.0),
        ("WeaponRim", (0, 3.0, 3.2), 650, (.55, .72, 1.0), 2.2),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (Vector((0, 0, .42)) - light.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=5, location=(0, .10, -.42))
    floor = bpy.context.object
    floor.data.materials.append(dark)
    bpy.ops.object.camera_add(location=(2.75, -4.8, 1.90))
    camera = bpy.context.object
    camera.data.lens = 62
    camera.rotation_euler = (Vector((0, 0, .42)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = PREVIEW_OUT
    bpy.ops.render.render(write_still=True)
    print(f"ROYAL_WEAPON_PREVIEW|{PREVIEW_OUT}")


clear_scene()
steel = material("Vanguard Forged Steel", (.105, .135, .175, 1), .94, .38)
edge = material("Vanguard Planished Edge", (.340, .390, .465, 1), .96, .36)
cobalt = material("Vanguard Cobalt Enamel", (.018, .070, .210, 1), .72, .46)
brass = material("Vanguard Gilt Brass", (.530, .270, .045, 1), .90, .48)
leather = material("Vanguard Oxblood Leather", (.105, .025, .018, 1), .04, .76)
dark = material("Vanguard Blackened Backing", (.010, .015, .024, 1), .82, .46)
materials = (steel, edge, cobalt, brass, leather, dark)

sword_root = build_sword(materials)
shield_root = build_shield(materials)
bpy.context.scene["royal_weapon_revision"] = "Closed Harness Weapon Pass"
bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
export_asset(sword_root, SWORD_OUT)
export_asset(shield_root, SHIELD_OUT)
render_preview(sword_root, shield_root, dark)
print(f"ROYAL_WEAPONS_BUILT|{BLEND_OUT}|{SWORD_OUT}|{SHIELD_OUT}")
