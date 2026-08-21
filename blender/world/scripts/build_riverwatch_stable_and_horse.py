"""Build the custom Riverwatch starter stable and a rigged riding horse."""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
STABLE_BLEND = os.path.join(ROOT, "blender", "world", "architecture", "riverwatch_stable.blend")
HORSE_BLEND = os.path.join(ROOT, "blender", "world", "animals", "riverwatch_horse.blend")
STABLE_GLB = os.path.join(ROOT, "godot", "assets", "architecture", "riverwatch_stable.glb")
HORSE_GLB = os.path.join(ROOT, "godot", "assets", "animals", "riverwatch_horse.glb")


def clear_scene():
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name, color, roughness=0.7, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def bevel(obj, width=0.035, segments=3):
    modifier = obj.modifiers.new("CraftedEdge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def cube(name, location, size, mat, rotation=(0.0, 0.0, 0.0), edge=0.035):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if edge > 0.0:
        bevel(obj, edge, 3)
    return obj


def sphere(name, location, scale, mat, segments=28, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def cylinder_between(name, start, end, radius, mat, vertices=20, radius2=None):
    start_v, end_v = Vector(start), Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    if radius2 is None or abs(radius2 - radius) < 0.0001:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=direction.length, location=midpoint)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius2, depth=direction.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bevel(obj, min(0.018, radius * 0.14), 2)
    return obj


def torus(name, location, major_radius, minor_radius, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=32,
        minor_segments=8,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def export_static(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_lights=False,
        export_cameras=False,
        export_apply=True,
    )


def build_stable():
    clear_scene()
    timber = material("Riverwatch Dark Oak", (0.16, 0.070, 0.025, 1), 0.78)
    timber_light = material("Riverwatch Hewn Oak", (0.29, 0.135, 0.045, 1), 0.76)
    plaster = material("Riverwatch Limewash", (0.46, 0.39, 0.29, 1), 0.92)
    roof = material("Riverwatch Clay Shingle", (0.22, 0.055, 0.025, 1), 0.86)
    stone = material("Riverwatch Stable Stone", (0.27, 0.27, 0.25, 1), 0.96)
    iron = material("Riverwatch Wrought Iron", (0.035, 0.042, 0.050, 1), 0.42, 0.72)
    hay = material("Riverwatch Hay", (0.52, 0.34, 0.075, 1), 0.96)
    leather = material("Riverwatch Tack Leather", (0.11, 0.030, 0.012, 1), 0.82)

    # Stone sill and packed aisle.
    cube("StableStoneSill", (0, 0.25, 0.18), (18.8, 9.6, 0.36), stone, edge=0.055)
    cube("StablePackedAisle", (0, -2.75, 0.40), (17.6, 3.0, 0.16), plaster, edge=0.025)

    # Heavy post-and-beam frame with three genuine stalls.
    for x in (-8.7, -2.9, 2.9, 8.7):
        for y in (-4.1, 4.1):
            cube("StablePost", (x, y, 2.65), (0.48, 0.48, 5.3), timber, edge=0.045)
    for y in (-4.1, 4.1):
        cube("StableLongWallPlate", (0, y, 5.0), (18.2, 0.48, 0.52), timber, edge=0.045)
        cube("StableLowerWallRail", (0, y, 1.25), (18.2, 0.28, 0.34), timber_light, edge=0.035)
    for x in (-8.7, 8.7):
        cube("StableEndTie", (x, 0, 4.8), (0.48, 8.5, 0.48), timber, edge=0.045)
    cube("StableRidgeBeam", (0, 0, 6.35), (18.8, 0.42, 0.48), timber, edge=0.04)

    # Back infill boards and end-wall limewash panels.
    for x in (-7.25, -4.35, -1.45, 1.45, 4.35, 7.25):
        cube("StableBackBoard", (x, 4.24, 2.78), (2.62, 0.18, 3.0), plaster, edge=0.025)
        cube("StableBackStud", (x + 1.36, 4.05, 2.9), (0.20, 0.26, 3.7), timber_light, edge=0.025)
    for x in (-8.82, 8.82):
        cube("StableSideWall", (x, 1.2, 2.7), (0.22, 5.5, 3.2), plaster, edge=0.025)
        for y in (-1.0, 1.4, 3.5):
            cube("StableSideBrace", (x + (-0.02 if x < 0 else 0.02), y, 2.9), (0.30, 0.24, 3.7), timber_light, rotation=(0.35 if x < 0 else -0.35, 0, 0), edge=0.025)

    # Pitched shingle roof with broad eaves and visible fascia.
    roof_angle = math.radians(27.0)
    cube("StableRoofFront", (0, -2.55, 5.70), (19.6, 6.25, 0.30), roof, rotation=(roof_angle, 0, 0), edge=0.055)
    cube("StableRoofRear", (0, 2.55, 5.70), (19.6, 6.25, 0.30), roof, rotation=(-roof_angle, 0, 0), edge=0.055)
    for y in (-5.25, 5.25):
        cube("StableRoofFascia", (0, y, 4.45), (19.8, 0.22, 0.52), timber_light, edge=0.035)

    # Stall partitions, half-height gates, feed troughs and straw bedding.
    for divider_x in (-2.9, 2.9):
        for y in (-1.5, 0.1, 1.7, 3.3):
            cube("StablePartitionRail", (divider_x, y, 1.45), (0.26, 1.72, 0.24), timber_light, edge=0.025)
        for y in (-2.35, 0.8, 3.75):
            cube("StablePartitionPost", (divider_x, y, 1.55), (0.34, 0.34, 3.1), timber, edge=0.035)
    for stall_x in (-5.8, 0.0, 5.8):
        for z in (0.82, 1.52):
            cube("StableGateRail", (stall_x, -2.25, z), (4.9, 0.22, 0.24), timber_light, edge=0.025)
        for x_offset in (-2.35, 2.35):
            cube("StableGatePost", (stall_x + x_offset, -2.25, 1.25), (0.30, 0.30, 2.5), timber, edge=0.03)
        cube("StableFeedTrough", (stall_x, 3.55, 0.82), (3.4, 0.90, 0.72), timber, edge=0.06)
        cube("StableHayBed", (stall_x, 1.25, 0.50), (4.6, 3.2, 0.22), hay, edge=0.05)
        for bale_index, y in enumerate((2.15, 2.95)):
            cube("StableHayBale", (stall_x + (-1.05 if bale_index == 0 else 1.05), y, 0.86), (1.65, 0.86, 0.78), hay, rotation=(0, 0, 0.08 * (-1 if bale_index == 0 else 1)), edge=0.08)

    # Hitching rail and tack display make the stable readable from the road.
    for x in (-6.5, 0.0, 6.5):
        cube("StableHitchPost", (x, -6.15, 1.15), (0.34, 0.34, 2.3), timber, edge=0.035)
    cube("StableHitchRail", (0, -6.15, 1.55), (13.4, 0.30, 0.32), timber_light, edge=0.035)
    cube("StableSignBoard", (0, -4.46, 4.0), (5.2, 0.24, 1.25), timber_light, edge=0.10)
    torus("StableHorseshoeSign", (0, -4.61, 4.0), 0.37, 0.055, iron, rotation=(math.pi / 2, 0, 0))
    for side in (-1, 1):
        torus("StableHangingBridle", (side * 6.8, -4.55, 2.55), 0.46, 0.035, leather, rotation=(math.pi / 2, 0, 0))

    os.makedirs(os.path.dirname(STABLE_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=STABLE_BLEND)
    export_static(STABLE_GLB)
    print("RIVERWATCH_STABLE_BUILT|blend=%s|glb=%s" % (STABLE_BLEND, STABLE_GLB))


def build_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "RiverwatchHorseRig"
    arm.data.name = "RiverwatchHorseRigData"
    default = arm.data.edit_bones.get("Bone")
    arm.data.edit_bones.remove(default)
    definitions = {
        "root": ((0, 0, 0), (0, 0, 0.42), None),
        "body": ((0, 0, 0.42), (0, 0, 1.28), "root"),
        "neck": ((0, -0.48, 1.34), (0, -0.96, 1.72), "body"),
        "head": ((0, -0.96, 1.72), (0, -1.46, 1.68), "neck"),
        "tail.1": ((0, 0.68, 1.28), (0, 1.05, 1.02), "body"),
        "tail.2": ((0, 1.05, 1.02), (0, 1.34, 0.70), "tail.1"),
    }
    for prefix, x, y in (
        ("front.L", -0.25, -0.43), ("front.R", 0.25, -0.43),
        ("hind.L", -0.27, 0.43), ("hind.R", 0.27, 0.43),
    ):
        definitions[prefix + ".upper"] = ((x, y, 1.02), (x, y, 0.58), "body")
        definitions[prefix + ".lower"] = ((x, y, 0.58), (x, y, 0.18), prefix + ".upper")
        definitions[prefix + ".hoof"] = ((x, y, 0.18), (x, y - 0.12, 0.08), prefix + ".lower")
    for name, (head, tail, parent) in definitions.items():
        bone = arm.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    return arm


def rigid_skin(obj, arm, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    obj.parent = arm
    modifier = obj.modifiers.new("HorseRig", "ARMATURE")
    modifier.object = arm
    return obj


def horse_sphere(name, location, scale, mat, arm, bone, segments=28, rings=16):
    return rigid_skin(sphere(name, location, scale, mat, segments, rings), arm, bone)


def horse_cube(name, location, size, mat, arm, bone, rotation=(0, 0, 0), edge=0.025):
    return rigid_skin(cube(name, location, size, mat, rotation, edge), arm, bone)


def horse_cylinder(name, start, end, radius, mat, arm, bone, radius2=None):
    return rigid_skin(cylinder_between(name, start, end, radius, mat, 20, radius2), arm, bone)


def build_horse_model(arm):
    coat = material("Riverwatch Bay Coat", (0.24, 0.070, 0.022, 1), 0.72)
    coat_light = material("Riverwatch Bay Highlight", (0.39, 0.135, 0.045, 1), 0.70)
    dark = material("Riverwatch Mane and Hoof", (0.018, 0.012, 0.010, 1), 0.76)
    leather = material("Riverwatch Saddle Leather", (0.095, 0.025, 0.010, 1), 0.72)
    blanket = material("Riverwatch Saddle Blanket", (0.035, 0.105, 0.18, 1), 0.82)
    brass = material("Riverwatch Tack Brass", (0.36, 0.18, 0.045, 1), 0.42, 0.68)
    eye = material("Riverwatch Horse Eye", (0.004, 0.003, 0.002, 1), 0.22)

    horse_sphere("HorseBarrel", (0, 0.02, 1.12), (0.38, 0.72, 0.46), coat, arm, "body")
    horse_sphere("HorseChest", (0, -0.42, 1.20), (0.42, 0.38, 0.48), coat_light, arm, "body")
    horse_sphere("HorseHindquarter", (0, 0.48, 1.19), (0.43, 0.42, 0.47), coat, arm, "body")
    horse_cylinder("HorseNeckCore", (0, -0.40, 1.38), (0, -0.94, 1.73), 0.25, coat_light, arm, "neck", 0.18)
    horse_sphere("HorseHead", (0, -1.14, 1.75), (0.235, 0.37, 0.265), coat, arm, "head")
    horse_sphere("HorseMuzzle", (0, -1.46, 1.66), (0.215, 0.255, 0.17), coat_light, arm, "head")
    for side in (-1, 1):
        horse_cylinder("HorseEar", (side * 0.105, -1.12, 1.93), (side * 0.125, -1.09, 2.13), 0.064, coat, arm, "head", 0.018)
        horse_sphere("HorseEye", (side * 0.208, -1.26, 1.81), (0.030, 0.021, 0.030), eye, arm, "head", 18, 10)
        horse_sphere("HorseNostril", (side * 0.105, -1.665, 1.69), (0.029, 0.018, 0.022), eye, arm, "head", 16, 8)

    # Mane is a layered ridge, not a single helmet-like slab.
    for index in range(9):
        t = index / 8.0
        y = -1.03 + t * 0.62
        z = 1.93 - t * 0.46
        horse_cube("HorseManeLock", (0, y, z), (0.075, 0.16, 0.24), dark, arm, "head" if index < 3 else "neck", rotation=(0.10 + t * 0.22, 0, 0.06 * math.sin(index)), edge=0.045)

    horse_cylinder("HorseTailUpper", (0, 0.67, 1.30), (0, 1.07, 1.02), 0.105, dark, arm, "tail.1", 0.075)
    horse_cylinder("HorseTailLower", (0, 1.03, 1.04), (0, 1.37, 0.57), 0.095, dark, arm, "tail.2", 0.040)

    # Four articulated legs with distinct joints, fetlocks and broad hooves.
    for prefix, x, y in (
        ("front.L", -0.25, -0.43), ("front.R", 0.25, -0.43),
        ("hind.L", -0.27, 0.43), ("hind.R", 0.27, 0.43),
    ):
        horse_sphere("HorseShoulderJoint", (x, y, 1.02), (0.17, 0.18, 0.20), coat, arm, prefix + ".upper")
        horse_cylinder("HorseUpperLeg", (x, y, 0.99), (x, y, 0.59), 0.105, coat, arm, prefix + ".upper", 0.082)
        horse_sphere("HorseKnee", (x, y, 0.57), (0.105, 0.11, 0.12), coat_light, arm, prefix + ".lower")
        horse_cylinder("HorseCannon", (x, y, 0.55), (x, y, 0.18), 0.074, coat, arm, prefix + ".lower", 0.060)
        horse_sphere("HorseFetlock", (x, y, 0.17), (0.082, 0.09, 0.085), dark, arm, prefix + ".hoof")
        horse_cube("HorseHoof", (x, y - 0.055, 0.075), (0.19, 0.30, 0.15), dark, arm, prefix + ".hoof", rotation=(0.04, 0, 0), edge=0.045)

    # Proper riding tack: blanket, shaped saddle, girth, bridle and stirrups.
    horse_cube("HorseSaddleBlanket", (0, 0.03, 1.49), (0.82, 0.92, 0.075), blanket, arm, "body", rotation=(0.03, 0, 0), edge=0.06)
    horse_sphere("HorseSaddleSeat", (0, 0.02, 1.56), (0.34, 0.40, 0.105), leather, arm, "body")
    horse_cube("HorseSaddlePommel", (0, -0.30, 1.64), (0.48, 0.13, 0.25), leather, arm, "body", edge=0.055)
    horse_cube("HorseSaddleCantle", (0, 0.31, 1.64), (0.50, 0.14, 0.28), leather, arm, "body", edge=0.055)
    torus_obj = torus("HorseGirth", (0, 0.03, 1.22), 0.47, 0.035, leather, rotation=(math.pi / 2, 0, 0))
    rigid_skin(torus_obj, arm, "body")
    for side in (-1, 1):
        horse_cylinder("HorseStirrupLeather", (side * 0.28, 0.02, 1.51), (side * 0.48, 0.02, 0.94), 0.018, leather, arm, "body")
        stirrup = torus("HorseStirrup", (side * 0.50, 0.02, 0.89), 0.12, 0.018, brass, rotation=(math.pi / 2, 0, 0))
        rigid_skin(stirrup, arm, "body")
        horse_cylinder("HorseBridleCheek", (side * 0.19, -1.16, 1.87), (side * 0.19, -1.48, 1.66), 0.017, leather, arm, "head")
    bridle = torus("HorseBridleNoseband", (0, -1.49, 1.68), 0.22, 0.018, leather, rotation=(math.pi / 2, 0, 0))
    rigid_skin(bridle, arm, "head")


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def key_pose(arm, frame, transforms):
    reset_pose(arm)
    for name, values in transforms.items():
        bone = arm.pose.bones[name]
        if "rot" in values:
            bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def make_action(arm, name, keys, end_frame):
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    action.frame_start = 1
    action.frame_end = end_frame
    return action


def make_horse_animations(arm):
    idle = make_action(arm, "Idle", [
        (1, {"body": {"loc": (0, 0, 0.0)}, "neck": {"rot": (-1, 0, 0)}, "head": {"rot": (1, 0, -1)}, "tail.1": {"rot": (0, -5, 0)}, "tail.2": {"rot": (0, 8, 0)}}),
        (24, {"body": {"loc": (0, 0, 0.018)}, "neck": {"rot": (2, 0, 0)}, "head": {"rot": (-3, 0, 2)}, "tail.1": {"rot": (0, 7, 0)}, "tail.2": {"rot": (0, -12, 0)}}),
        (48, {"body": {"loc": (0, 0, 0.0)}, "neck": {"rot": (-1, 0, 0)}, "head": {"rot": (1, 0, -1)}, "tail.1": {"rot": (0, -5, 0)}, "tail.2": {"rot": (0, 8, 0)}}),
    ], 48)

    trot_keys = []
    for frame, phase in ((1, 0), (7, 1), (13, 2), (19, 3), (25, 4)):
        diagonal = 1.0 if phase in (0, 4) else (-1.0 if phase == 2 else 0.0)
        if phase == 1:
            diagonal = 0.45
        elif phase == 3:
            diagonal = -0.45
        rise = 0.045 if phase in (1, 3) else 0.0
        pose = {
            "body": {"loc": (0, 0, rise), "rot": (1.8 * diagonal, 0, 0)},
            "neck": {"rot": (-4.0 * diagonal, 0, 0)},
            "head": {"rot": (5.0 * diagonal, 0, 0)},
            "tail.1": {"rot": (0, 12.0 * diagonal, 0)},
            "tail.2": {"rot": (0, -18.0 * diagonal, 0)},
            "front.L.upper": {"rot": (30.0 * diagonal, 0, 0)},
            "front.R.upper": {"rot": (-30.0 * diagonal, 0, 0)},
            "hind.L.upper": {"rot": (-27.0 * diagonal, 0, 0)},
            "hind.R.upper": {"rot": (27.0 * diagonal, 0, 0)},
            "front.L.lower": {"rot": (-18.0 if diagonal > 0 else 7.0, 0, 0)},
            "front.R.lower": {"rot": (-18.0 if diagonal < 0 else 7.0, 0, 0)},
            "hind.L.lower": {"rot": (-22.0 if diagonal < 0 else 8.0, 0, 0)},
            "hind.R.lower": {"rot": (-22.0 if diagonal > 0 else 8.0, 0, 0)},
        }
        trot_keys.append((frame, pose))
    trot = make_action(arm, "Trot", trot_keys, 25)
    arm.animation_data.action = None
    for action in (idle, trot):
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_start), action)
        strip.mute = True
    return idle, trot


def consolidate_horse(arm):
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.parent == arm]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = max(parts, key=lambda obj: len(obj.data.vertices))
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "RiverwatchHorseBody"
    body.data.name = "RiverwatchHorseBodyMesh"
    body.parent = arm
    for modifier in body.modifiers:
        if modifier.type == "ARMATURE":
            modifier.object = arm
    return body


def export_horse(arm):
    os.makedirs(os.path.dirname(HORSE_GLB), exist_ok=True)
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=HORSE_GLB,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_lights=False,
        export_cameras=False,
        export_apply=False,
    )


def build_horse():
    clear_scene()
    bpy.context.scene.render.fps = 30
    arm = build_armature()
    build_horse_model(arm)
    actions = make_horse_animations(arm)
    consolidate_horse(arm)
    os.makedirs(os.path.dirname(HORSE_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=HORSE_BLEND)
    export_horse(arm)
    print("RIVERWATCH_HORSE_BUILT|blend=%s|glb=%s|animations=%s" % (
        HORSE_BLEND, HORSE_GLB, ",".join(action.name for action in actions)))


build_stable()
build_horse()
