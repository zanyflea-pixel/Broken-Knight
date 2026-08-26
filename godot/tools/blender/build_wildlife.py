import bpy
import math
import os
from mathutils import Vector


ROOT = r"C:\Users\Jimmy\Desktop\Broken Knight\godot"
OUT = os.path.join(ROOT, "assets", "animals")


def material(name, color, roughness=0.82, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.location = location
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def smooth(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def sphere(name, location, scale, mat, parent=None, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    smooth(obj)
    if parent:
        obj.parent = parent
    return obj


def cone(name, location, radius1, radius2, depth, mat, rotation=(0, 0, 0), parent=None, vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    smooth(obj)
    return obj


def cylinder_between(name, start, end, radius, mat, parent=None, vertices=10):
    a = Vector(start)
    b = Vector(end)
    vector = b - a
    midpoint = (a + b) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=vector.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(vector.normalized())
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    smooth(obj)
    return obj


def leg(root, name, shoulder, knee, hoof, coat, hoof_mat, thickness):
    pivot = empty(name, shoulder, root)
    local_knee = Vector(knee) - Vector(shoulder)
    local_hoof = Vector(hoof) - Vector(shoulder)
    cylinder_between(name + "Upper", (0, 0, 0), local_knee, thickness, coat, pivot, 10)
    cylinder_between(name + "Lower", local_knee, local_hoof, thickness * 0.72, coat, pivot, 10)
    sphere(name + "Hoof", local_hoof + Vector((0, -0.035, -0.015)), (thickness * 1.10, thickness * 1.55, thickness * .62), hoof_mat, pivot, 12, 7)
    return pivot


def export_asset(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print("Exported", path)


def build_deer():
    reset()
    deer_coat = material("Deer warm winter coat", (0.29, 0.135, 0.055), 0.94)
    deer_light = material("Deer throat and belly", (0.60, 0.42, 0.23), 0.96)
    deer_dark = material("Deer dark points", (0.055, 0.036, 0.024), 0.91)
    antler = material("Weathered antler", (0.31, 0.25, 0.17), 0.88)
    eye = material("Animal eyes", (0.006, 0.005, 0.004), 0.28)
    root = empty("WildlifeDeer")
    sphere("Body", (0, 0.08, 1.22), (.48, 1.03, .61), deer_coat, root, 24, 14)
    sphere("Chest", (0, -.63, 1.40), (.50, .55, .68), deer_coat, root, 22, 13)
    sphere("BellyPatch", (0, .02, .91), (.34, .72, .18), deer_light, root, 18, 10)
    cylinder_between("Neck", (0, -.58, 1.52), (0, -.92, 2.08), .31, deer_coat, root, 14)
    sphere("Head", (0, -1.06, 2.25), (.33, .48, .34), deer_coat, root, 20, 12)
    sphere("Muzzle", (0, -1.47, 2.16), (.24, .30, .19), deer_light, root, 18, 10)
    sphere("Nose", (0, -1.70, 2.16), (.18, .12, .13), deer_dark, root, 14, 8)
    sphere("Throat", (0, -.90, 1.83), (.24, .32, .34), deer_light, root, 16, 9)
    for side in (-1, 1):
        sphere("EyeL" if side < 0 else "EyeR", (side * .265, -1.31, 2.34), (.048, .035, .052), eye, root, 12, 7)
        cone("EarL" if side < 0 else "EarR", (side * .30, -1.02, 2.64), .16, .035, .48, deer_coat, (0, side * .22, side * .25), root, 12)
        # Antlers are intentionally asymmetric organic branches, not a crown of cones.
        cylinder_between("AntlerMainL" if side < 0 else "AntlerMainR", (side*.16,-1.00,2.50), (side*.27,-.91,3.04), .045, antler, root, 9)
        cylinder_between("AntlerBackL" if side < 0 else "AntlerBackR", (side*.24,-.94,2.79), (side*.43,-.74,3.12), .033, antler, root, 8)
        cylinder_between("AntlerFrontL" if side < 0 else "AntlerFrontR", (side*.25,-.97,2.90), (side*.37,-1.18,3.14), .028, antler, root, 8)
        cylinder_between("AntlerTipL" if side < 0 else "AntlerTipR", (side*.27,-.91,3.02), (side*.22,-.86,3.27), .024, antler, root, 8)
    leg(root, "FrontLegL", (-.29, -.55, 1.30), (-.30, -.62, .62), (-.31, -.70, .08), deer_coat, deer_dark, .105)
    leg(root, "FrontLegR", (.29, -.55, 1.30), (.30, -.62, .62), (.31, -.70, .08), deer_coat, deer_dark, .105)
    leg(root, "RearLegL", (-.31, .63, 1.27), (-.40, .72, .63), (-.34, .58, .08), deer_coat, deer_dark, .12)
    leg(root, "RearLegR", (.31, .63, 1.27), (.40, .72, .63), (.34, .58, .08), deer_coat, deer_dark, .12)
    tail = empty("TailPivot", (0, .98, 1.50), root)
    cone("Tail", (0, .19, -.05), .16, .04, .48, deer_light, (math.pi * .42, 0, 0), tail, 12)
    export_asset("highland_deer_v1")


def build_hare():
    reset()
    hare_coat = material("Hare mottled coat", (0.30, 0.255, 0.19), 0.98)
    hare_light = material("Hare pale underside", (0.62, 0.57, 0.46), 0.98)
    hare_dark = material("Hare ear markings", (0.115, 0.085, 0.065), 0.97)
    eye = material("Animal eyes", (0.006, 0.005, 0.004), 0.28)
    root = empty("WildlifeHare")
    sphere("Body", (0, .10, .46), (.34, .59, .38), hare_coat, root, 20, 12)
    sphere("Chest", (0, -.34, .54), (.31, .35, .40), hare_light, root, 18, 10)
    sphere("Head", (0, -.58, .83), (.28, .31, .31), hare_coat, root, 20, 12)
    sphere("Muzzle", (0, -.82, .75), (.21, .18, .16), hare_light, root, 16, 9)
    sphere("Tail", (0, .63, .54), (.20, .20, .20), hare_light, root, 14, 8)
    for side in (-1, 1):
        sphere("EyeL" if side < 0 else "EyeR", (side*.225,-.74,.89), (.045,.035,.050), eye, root, 10, 6)
        ear_pivot = empty("EarL" if side < 0 else "EarR", (side*.13,-.50,1.04), root)
        cone("EarBlade", (side*.035,0,.31), .105, .025, .68, hare_coat, (0, side*.10, side*.08), ear_pivot, 12)
        cone("EarInner", (side*.055,-.018,.32), .052, .015, .52, hare_dark, (0, side*.10, side*.08), ear_pivot, 10)
    leg(root, "FrontLegL", (-.19,-.35,.48), (-.19,-.48,.22), (-.18,-.54,.05), hare_light, hare_dark, .052)
    leg(root, "FrontLegR", (.19,-.35,.48), (.19,-.48,.22), (.18,-.54,.05), hare_light, hare_dark, .052)
    leg(root, "RearLegL", (-.24,.34,.43), (-.35,.53,.19), (-.28,.69,.06), hare_coat, hare_dark, .085)
    leg(root, "RearLegR", (.24,.34,.43), (.35,.53,.19), (.28,.69,.06), hare_coat, hare_dark, .085)
    export_asset("highland_hare_v1")


def build_grouse():
    reset()
    grouse_brown = material("Grouse barred brown", (0.22, 0.125, 0.068), 0.98)
    grouse_rust = material("Grouse rust mantle", (0.43, 0.19, 0.075), 0.97)
    grouse_cream = material("Grouse breast", (0.59, 0.48, 0.31), 0.98)
    beak = material("Horn beak", (0.25, 0.22, 0.12), 0.86)
    eye = material("Animal eyes", (0.006, 0.005, 0.004), 0.28)
    root = empty("WildlifeGrouse")
    sphere("Body", (0, .02, .38), (.34, .48, .38), grouse_brown, root, 20, 12)
    sphere("Breast", (0, -.34, .43), (.31, .29, .35), grouse_cream, root, 18, 10)
    sphere("Head", (0, -.50, .73), (.22, .24, .23), grouse_rust, root, 18, 10)
    cone("Beak", (0,-.76,.70), .10, 0, .27, beak, (math.pi*.5,0,0), root, 10)
    for side in (-1, 1):
        sphere("EyeL" if side < 0 else "EyeR", (side*.175,-.66,.77), (.032,.025,.034), eye, root, 10, 6)
        wing = sphere("WingL" if side < 0 else "WingR", (side*.29,.02,.40), (.10,.37,.29), grouse_rust, root, 16, 9)
        wing.rotation_euler.y = side * .12
        leg(root, "LegL" if side < 0 else "LegR", (side*.13,.03,.20), (side*.14,-.01,.10), (side*.15,-.09,.025), grouse_rust, beak, .027)
    tail = empty("TailPivot", (0,.36,.43), root)
    for feather in range(5):
        x=(feather-2)*.075
        cone("TailFeather%02d"%feather, (x,.32,-.02), .085, .025, .60, grouse_brown if feather%2==0 else grouse_rust, (math.pi*.5,0,0), tail, 10)
    export_asset("highland_grouse_v1")


def build_venison():
    reset()
    meat = material("Fresh venison", (0.34, 0.035, 0.025), 0.86)
    fat = material("Venison fat", (0.72, 0.59, 0.43), 0.94)
    bone = material("Cut bone", (0.76, 0.68, 0.52), 0.92)
    root = empty("VenisonPickup")
    steak = sphere("VenisonCut", (0, 0, .17), (.48, .31, .16), meat, root, 20, 10)
    steak.rotation_euler.z = -.14
    cylinder_between("Bone", (-.39, -.02, .22), (.42, .03, .20), .070, bone, root, 12)
    sphere("BoneEndL", (-.43, -.02, .22), (.12, .10, .09), bone, root, 12, 7)
    sphere("BoneEndR", (.45, .03, .20), (.12, .10, .09), bone, root, 12, 7)
    cylinder_between("FatMarblingA", (-.24, -.22, .28), (.18, -.22, .27), .022, fat, root, 8)
    cylinder_between("FatMarblingB", (-.05, .22, .27), (.28, .16, .25), .018, fat, root, 8)
    export_asset("venison_cut_v1")


build_deer()
build_hare()
build_grouse()
build_venison()
