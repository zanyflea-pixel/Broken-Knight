import bpy
import math
import os
from mathutils import Vector

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "items"))
os.makedirs(OUT, exist_ok=True)


def mat(name, color, metallic=0.0, roughness=0.7):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


WOOD = mat("Ash Wood", (0.22, 0.085, 0.025), 0.0, 0.84)
WOOD_LIGHT = mat("Fresh Cut", (0.55, 0.30, 0.10), 0.0, 0.78)
STEEL = mat("Forged Steel", (0.31, 0.38, 0.43), 0.82, 0.24)
IRON = mat("Dark Iron", (0.07, 0.085, 0.09), 0.75, 0.32)
CORD = mat("Cord", (0.035, 0.027, 0.018), 0.0, 0.92)
RED = mat("Berry", (0.48, 0.012, 0.018), 0.0, 0.38)
LEAF = mat("Leaf", (0.055, 0.24, 0.045), 0.0, 0.74)
FISH = mat("Fish Scales", (0.22, 0.42, 0.48), 0.22, 0.30)
FISH_BELLY = mat("Fish Belly", (0.64, 0.69, 0.62), 0.0, 0.42)
COOKED = mat("Cooked Fish", (0.48, 0.19, 0.055), 0.0, 0.62)
BLACK = mat("Black", (0.008, 0.01, 0.012), 0.0, 0.42)
GOLD = mat("Coin Gold", (0.72, 0.40, 0.045), 0.82, 0.22)
LEATHER = mat("Leather", (0.18, 0.055, 0.018), 0.0, 0.82)
CRYSTAL = mat("Crystal", (0.06, 0.48, 0.72), 0.18, 0.16)
BARK = mat("Bark", (0.16, 0.065, 0.018), 0.0, 0.96)
FOLIAGE = mat("Foliage", (0.045, 0.20, 0.035), 0.0, 0.88)


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def bevel(obj, amount=0.035, segments=2):
    mod = obj.modifiers.new("Edge Softening", 'BEVEL')
    mod.width = amount
    mod.segments = segments


def cube(name, loc, scale, material, rotation=(0, 0, 0), bevel_amount=0.025):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rotation)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    if bevel_amount:
        bevel(o, bevel_amount)
    return o


def cylinder(name, loc, radius, depth, material, rotation=(0, 0, 0), vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    bevel(o, min(radius * .18, .035), 2)
    return o


def sphere(name, loc, scale, material, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    return o


def beam(name, a, b, radius, material):
    a, b = Vector(a), Vector(b)
    direction = b - a
    o = cylinder(name, (a + b) * .5, radius, direction.length, material)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = direction.to_track_quat('Z', 'Y')
    # Bake the branch orientation before GLTF converts Blender's Z-up axes to
    # Godot's Y-up axes.  Leaving this as an object rotation made the canopy
    # arrive detached from the standing trunk in Godot.
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.select_set(False)
    return o


def curve_tube(name, points, radius, material):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 3
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for bp, point in zip(spline.bezier_points, points):
        bp.co = point
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    o = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o


def export(name):
    bpy.ops.object.select_all(action='SELECT')
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_materials='EXPORT', export_cameras=False,
                              export_lights=False)
    print("EXPORTED", path)


def axe():
    clear()
    cylinder("Axe_Handle", (0, .68, 0), .045, 1.36, WOOD, vertices=18)
    cylinder("Axe_Grip", (0, .22, 0), .053, .42, LEATHER, vertices=18)
    cube("Axe_Eye", (0, 1.26, 0), (.14, .105, .105), IRON, bevel_amount=.03)
    blade = cube("Axe_Blade", (-.20, 1.27, 0), (.24, .23, .052), STEEL, rotation=(0, 0, -.16), bevel_amount=.045)
    blade.scale.x = 1.12
    cube("Axe_Poll", (.17, 1.27, 0), (.11, .12, .075), IRON, bevel_amount=.025)
    export("axe")


def fishing_pole():
    clear()
    curve_tube("Fishing_Rod", [(0, 0, 0), (0, .65, 0), (.02, 1.45, -.04), (.08, 2.1, -.18)], .025, WOOD)
    cylinder("Grip", (0, .20, 0), .042, .38, LEATHER, vertices=16)
    bpy.ops.mesh.primitive_torus_add(major_radius=.105, minor_radius=.025, major_segments=20, minor_segments=8, location=(.10, .53, 0), rotation=(math.pi/2, 0, 0))
    bpy.context.object.name = "Reel"; bpy.context.object.data.materials.append(IRON)
    cylinder("Reel_Handle", (.18, .53, 0), .018, .17, STEEL, rotation=(0, math.pi/2, 0), vertices=12)
    curve_tube("Fishing_Line", [(.08, 2.1, -.18), (.18, 1.35, -.65), (.26, .38, -.88)], .006, CORD)
    curve_tube("Hook", [(.26, .38, -.88), (.28, .29, -.88), (.24, .25, -.86)], .012, STEEL)
    export("fishing_pole")


def fish(name="fish", cooked=False):
    clear()
    body_mat = COOKED if cooked else FISH
    sphere("Fish_Body", (0, .18, 0), (.62, .25, .20), body_mat, 24, 14)
    sphere("Fish_Belly", (0, .12, -.10), (.48, .13, .08), COOKED if cooked else FISH_BELLY, 20, 10)
    tail = cube("Fish_Tail", (-.67, .18, 0), (.26, .28, .045), body_mat, rotation=(0, 0, math.pi/4), bevel_amount=.04)
    cube("Dorsal_Fin", (-.02, .39, 0), (.17, .20, .025), body_mat, rotation=(0, 0, -.18), bevel_amount=.025)
    if not cooked:
        for side in (-1, 1):
            sphere("Eye", (.43, .26, side*.17), (.045, .045, .025), BLACK, 12, 8)
    export(name)


def berries():
    clear()
    for i, p in enumerate([(-.12,.12,0),(.05,.10,.07),(.15,.17,-.03),(-.03,.23,-.06),(.08,.29,.04)]):
        sphere("Berry_%02d"%i, p, (.105,.105,.105), RED, 16, 10)
    beam("Stem", (0,.26,0),(0,.58,0), .018, WOOD)
    for side in (-1,1):
        leaf=sphere("Leaf", (side*.15,.46,0), (.20,.055,.11), LEAF, 16, 8)
        leaf.rotation_euler.z=side*.38
    export("berries")


def log_asset():
    clear()
    cylinder("Log", (0,.20,0), .22, 1.45, BARK, rotation=(0,math.pi/2,0), vertices=18)
    cylinder("Cut_End_L", (-.735,.20,0), .205, .018, WOOD_LIGHT, rotation=(0,math.pi/2,0), vertices=18)
    cylinder("Cut_End_R", (.735,.20,0), .205, .018, WOOD_LIGHT, rotation=(0,math.pi/2,0), vertices=18)
    for x in (-.28,.31):
        cylinder("Broken_Branch", (x,.39,.02), .045, .28, BARK, rotation=(0.25,0,.65), vertices=12)
    export("log")


def coin_pouch():
    clear()
    sphere("Pouch", (0,.22,0), (.30,.31,.23), LEATHER, 20, 12)
    cylinder("Tie", (0,.48,0), .19, .055, CORD, vertices=18)
    for i in range(3):
        cylinder("Coin", (-.20+i*.18,.07,-.18-i*.02), .10, .035, GOLD, rotation=(math.pi/2,0,0), vertices=20)
    export("coin_pouch")


def armor_bundle():
    clear()
    sphere("Breastplate", (0,.28,0), (.40,.38,.18), STEEL, 20, 12)
    cube("Chest_Ridge", (0,.31,-.18), (.28,.055,.025), GOLD, bevel_amount=.018)
    for side in (-1,1):
        sphere("Pauldron", (side*.38,.39,0), (.22,.17,.20), STEEL, 16, 10)
    cylinder("Leather_Strap", (0,.16,.18), .12, .55, LEATHER, rotation=(0,0,math.pi/2), vertices=14)
    export("armor_bundle")


def crystal():
    clear()
    for i,(x,z,s) in enumerate([(-.12,0,.85),(.13,.05,.65),(0,-.10,1.0)]):
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=.13*s, radius2=.08*s, depth=.62*s, location=(x,.31*s,z))
        o=bpy.context.object;o.name="Crystal_%d"%i;o.data.materials.append(CRYSTAL)
    export("crystal")


def sword():
    clear()
    cylinder("Grip", (0,.22,0), .045, .40, LEATHER, vertices=18)
    cube("Crossguard", (0,.45,0), (.32,.045,.065), GOLD, bevel_amount=.025)
    blade=cube("Blade", (0,1.15,0), (.085,.69,.025), STEEL, bevel_amount=.018)
    cube("Blade_Ridge", (0,1.15,-.027), (.018,.62,.012), IRON, bevel_amount=.006)
    sphere("Pommel", (0,-.02,0), (.09,.09,.09), GOLD, 16, 10)
    export("sword")


def shield():
    clear()
    sphere("Shield_Body", (0,.43,0), (.47,.58,.09), STEEL, 20, 12)
    cube("Shield_Rim_H", (0,.43,-.09), (.36,.045,.025), GOLD, bevel_amount=.015)
    cube("Shield_Rim_V", (0,.43,-.09), (.045,.46,.025), GOLD, bevel_amount=.015)
    sphere("Shield_Boss", (0,.43,-.14), (.12,.12,.07), IRON, 16, 10)
    export("shield")


def ore():
    clear()
    ore_mat=mat("Iron Ore",(.22,.25,.27),.48,.64)
    for i,(p,s) in enumerate([((0,.16,0),(.32,.22,.26)),((.26,.13,.06),(.22,.18,.20)),((-.23,.12,-.04),(.24,.16,.18))]):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=p)
        o=bpy.context.object;o.name="Ore_%d"%i;o.scale=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(ore_mat)
    export("ore")


def tree():
    clear()
    # Blender is Z-up.  The GLTF exporter converts this to Godot's Y-up.
    # Keep the complete standing tree authored upright here so it cannot read
    # as a pre-chopped stump/log pile before the player touches it.
    cylinder("Trunk", (0,0,2.75), .38, 5.5, BARK, vertices=16)
    # A tapered butt replaces the old short cylinder, which looked like the
    # tree was mounted on a cut stump or round pedestal.
    bpy.ops.mesh.primitive_cone_add(
        vertices=16,
        radius1=.60,
        radius2=.38,
        depth=.90,
        location=(0,0,.45),
    )
    root_flare=bpy.context.object
    root_flare.name="Natural_Root_Flare"
    root_flare.data.materials.append(BARK)
    branches=[
        ((0,0,3.15),(1.45,.25,4.80)),
        ((0,0,3.65),(-1.35,-.20,5.15)),
        ((0,0,4.10),(.55,-1.15,5.75)),
        ((0,0,4.35),(-.55,1.0,6.05)),
        ((0,0,4.65),(.30,.35,6.35)),
    ]
    for i,(a,b) in enumerate(branches):beam("Branch_%d"%i,a,b,.11,BARK)
    crowns=[
        ((0,0,6.05),(1.75,1.55,1.25)),
        ((1.35,.25,5.15),(1.15,1.0,.90)),
        ((-1.25,-.2,5.35),(1.10,.96,.86)),
        ((.5,-1.0,5.95),(.92,.86,.74)),
        ((-.5,.9,6.15),(.9,.82,.7)),
        ((.25,.15,6.75),(1.05,.95,.72)),
    ]
    for i,(p,s) in enumerate(crowns):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=p)
        o=bpy.context.object;o.name="Leaf_Cluster_%d"%i;o.scale=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(FOLIAGE)
    export("choppable_tree")


axe(); fishing_pole(); fish(); fish("cooked_fish", True); berries(); log_asset(); coin_pouch(); armor_bundle(); crystal(); sword(); shield(); ore(); tree()
