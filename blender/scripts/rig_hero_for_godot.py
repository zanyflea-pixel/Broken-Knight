"""Rig the accepted Broken Knight hero without remodeling it."""

import os
import bpy
from math import radians
from mathutils import Matrix


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "hero_restart_rigged.blend")


def smoothstep(value, start, end):
    if end <= start:
        return float(value >= end)
    t = max(0.0, min(1.0, (value - start) / (end - start)))
    return t * t * (3.0 - 2.0 * t)


def normalize(weights):
    weights = {name: max(0.0, value) for name, value in weights.items() if value > 1e-6}
    total = sum(weights.values())
    if total <= 1e-8:
        return {"pelvis": 1.0}
    return {name: value / total for name, value in weights.items()}


def create_armature():
    data = bpy.data.armatures.new("HeroRig")
    arm = bpy.data.objects.new("HeroRig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    arm.data.display_type = "OCTAHEDRAL"
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name, head, tail, parent=None, connected=False, deform=True):
        edit = data.edit_bones.new(name)
        edit.head = head
        edit.tail = tail
        edit.use_deform = deform
        if parent:
            edit.parent = data.edit_bones[parent]
            edit.use_connect = connected
        return edit

    bone("root", (0, 0, 0.03), (0, 0, 0.15), deform=False)
    bone("pelvis", (0, 0, 0.88), (0, 0, 1.06), "root")
    bone("spine", (0, 0, 1.06), (0, 0, 1.27), "pelvis", True)
    bone("chest", (0, 0, 1.27), (0, 0, 1.50), "spine", True)
    bone("neck", (0, 0, 1.50), (0, 0, 1.65), "chest", True)
    bone("head", (0, 0, 1.65), (0, 0, 1.86), "neck", True)
    bone("jaw", (0, -0.012, 1.725), (0, -0.075, 1.675), "head", deform=True)

    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        bone(f"clavicle.{suffix}", (0.018 * side, 0, 1.485),
             (0.215 * side, 0, 1.455), "chest")
        bone(f"upper_arm.{suffix}", (0.215 * side, 0, 1.455),
             (0.334 * side, 0.012, 1.145), f"clavicle.{suffix}")
        bone(f"forearm.{suffix}", (0.334 * side, 0.012, 1.145),
             (0.345 * side, 0, 0.900), f"upper_arm.{suffix}", True)
        bone(f"hand.{suffix}", (0.345 * side, 0, 0.900),
             (0.345 * side, -0.012, 0.785), f"forearm.{suffix}", True)

        bone(f"thigh.{suffix}", (0.112 * side, 0, 0.965),
             (0.130 * side, 0.008, 0.555), "pelvis")
        bone(f"shin.{suffix}", (0.130 * side, 0.008, 0.555),
             (0.132 * side, 0.018, 0.135), f"thigh.{suffix}", True)
        bone(f"foot.{suffix}", (0.132 * side, 0.018, 0.135),
             (0.132 * side, -0.155, 0.070), f"shin.{suffix}", True)
        bone(f"toe.{suffix}", (0.132 * side, -0.155, 0.070),
             (0.132 * side, -0.245, 0.060), f"foot.{suffix}", True)

    bone("loin_front", (0, -0.125, 0.985), (0, -0.145, 0.770), "pelvis", deform=True)
    bone("loin_back", (0, 0.125, 0.985), (0, 0.145, 0.770), "pelvis", deform=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.select_set(False)
    return arm


def main_body_weights(co):
    x, y, z = co
    ax = abs(x)
    side = "L" if x < 0 else "R"

    # Arms branch laterally from the ribcage.  Classify the complete hand
    # before the legs: fingertips sit below z=.82 and the old vertical gate
    # accidentally assigned them to thigh/pelvis bones.
    if ax > 0.205 and z > 0.735:
        if z <= 0.86:
            return {f"hand.{side}": 1.0}
        if z <= 0.99:
            wrist = smoothstep(z, 0.86, 0.99)
            return normalize({f"hand.{side}": 1.0 - wrist,
                              f"forearm.{side}": wrist})
        if z <= 1.20:
            elbow = smoothstep(z, 1.06, 1.20)
            return normalize({f"forearm.{side}": 1.0 - elbow,
                              f"upper_arm.{side}": elbow})
        if z <= 1.42:
            shoulder = smoothstep(z, 1.34, 1.44)
            return normalize({f"upper_arm.{side}": 1.0 - 0.35 * shoulder,
                              f"clavicle.{side}": 0.35 * shoulder})
        chest_mix = smoothstep(z, 1.42, 1.52)
        return normalize({f"upper_arm.{side}": 0.55 * (1.0 - chest_mix),
                          f"clavicle.{side}": 0.65,
                          "chest": 0.35 * chest_mix})

    # Legs and feet.
    if z < 1.02 and ax > 0.045:
        if z < 0.105:
            toe = smoothstep(-y, 0.13, 0.22)
            return normalize({f"foot.{side}": 1.0 - toe, f"toe.{side}": toe})
        if z < 0.22:
            # Use a broad ankle blend so the skin does not form a visible
            # horizontal weight boundary while the planted foot rolls.
            ankle = smoothstep(z, 0.085, 0.22)
            return normalize({f"foot.{side}": 1.0 - ankle,
                              f"shin.{side}": ankle})
        if z < 0.70:
            # The old narrow blend read as a line around the knee in motion.
            # Spread deformation across the full joint volume instead.
            knee = smoothstep(z, 0.43, 0.69)
            return normalize({f"shin.{side}": 1.0 - knee,
                              f"thigh.{side}": knee})
        if z < 0.93:
            return {f"thigh.{side}": 1.0}
        hip = smoothstep(z, 0.93, 1.04)
        return normalize({f"thigh.{side}": 1.0 - hip, "pelvis": hip})

    # Head, jaw, and neck are kept conservative to protect facial details.
    if z > 1.69:
        jaw_mask = smoothstep(1.735 - z, 0.0, 0.075) * smoothstep(-y, 0.025, 0.09)
        return normalize({"head": 1.0 - 0.75 * jaw_mask, "jaw": 0.75 * jaw_mask})
    if z > 1.58:
        head_mix = smoothstep(z, 1.61, 1.70)
        return normalize({"neck": 1.0 - head_mix, "head": head_mix})
    if z > 1.46:
        neck_mix = smoothstep(z, 1.48, 1.60)
        return normalize({"chest": 1.0 - neck_mix, "neck": neck_mix})

    # Pelvis/spine/chest core.
    if z < 1.05:
        return {"pelvis": 1.0}
    if z < 1.28:
        t = smoothstep(z, 1.05, 1.28)
        return normalize({"pelvis": 1.0 - t, "spine": t})
    if z < 1.48:
        t = smoothstep(z, 1.25, 1.48)
        return normalize({"spine": 1.0 - t, "chest": t})
    return {"chest": 1.0}


def cloth_weights(co, front=True):
    x, y, z = co
    lower = 1.0 - smoothstep(z, 0.76, 0.99)
    side = smoothstep(abs(x), 0.025, 0.105)
    weights = {"pelvis": 1.0 - 0.55 * lower}
    if lower > 0:
        if x < 0:
            weights["thigh.L"] = 0.38 * lower * side
        else:
            weights["thigh.R"] = 0.38 * lower * side
        weights["loin_front" if front else "loin_back"] = 0.25 * lower * (1.0 - 0.5 * side)
    return normalize(weights)


def apply_weights(obj, arm, weight_function):
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    groups = {bone.name: obj.vertex_groups.new(name=bone.name)
              for bone in arm.data.bones if bone.use_deform}
    for vertex in obj.data.vertices:
        for name, weight in weight_function(vertex.co).items():
            if name in groups:
                groups[name].add([vertex.index], weight, "REPLACE")
    modifier = next((mod for mod in obj.modifiers if mod.type == "ARMATURE"), None)
    if modifier is None:
        modifier = obj.modifiers.new("HeroArmature", "ARMATURE")
    modifier.object = arm
    modifier.use_deform_preserve_volume = True
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()


def apply_automatic_weights(obj, arm):
    """Generate connected-surface weights with Blender's bone heat solver."""
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO", keep_transform=True)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Four normalized influences are a safe Godot/glTF skinning limit and
    # avoid weak distant bones creating ribbons during large gait poses.
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    # Bone heat can decline a small facial/detail region on a remeshed body.
    # Fill only vertices for which it produced no influence at all.
    groups = {group.name: group for group in obj.vertex_groups}
    for vertex in obj.data.vertices:
        if vertex.groups:
            continue
        for name, weight in main_body_weights(vertex.co).items():
            group = groups.get(name)
            if group is not None:
                group.add([vertex.index], weight, "REPLACE")
    obj.select_set(False)
    modifier = next((mod for mod in obj.modifiers if mod.type == "ARMATURE"), None)
    if modifier is None:
        modifier = obj.modifiers.new("HeroArmature", "ARMATURE")
        modifier.object = arm
    modifier.use_deform_preserve_volume = True


def bone_parent(obj, arm, bone_name):
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


def convert_curves():
    for obj in list(bpy.context.scene.objects):
        if obj.type != "CURVE":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")


def cut_deformation_bridges(body):
    """Remove hidden remesh bridges between touching limbs in the bind mesh."""
    cutters = [
        # Arms/hands remain connected through the shoulders above this cut,
        # but must not also be welded to ribs, hips, or upper thighs.
        ("ArmGap.L", (-0.252, 0.0, 1.01), (0.032, 0.62, 0.58)),
        ("ArmGap.R", (0.252, 0.0, 1.01), (0.032, 0.62, 0.58)),
        # Keep the pelvis/crotch intact while separating the two legs below it.
        ("LegGap", (0.0, 0.0, 0.49), (0.030, 0.62, 0.74)),
    ]
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    for name, location, scale in cutters:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
        cutter = bpy.context.object
        cutter.name = name
        cutter.dimensions = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

        bpy.context.view_layer.objects.active = body
        modifier = body.modifiers.new(name, "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.solver = "EXACT"
        modifier.object = cutter
        # Cut the original cage before its smoothing modifier.
        while list(body.modifiers).index(modifier) > 0:
            bpy.ops.object.modifier_move_up(modifier=modifier.name)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
    # Boolean-created cap faces default to flat shading and otherwise show as
    # circular patches under game lighting.
    for polygon in body.data.polygons:
        polygon.use_smooth = True


def rig_objects(arm):
    convert_curves()
    body = bpy.data.objects["ConnectedBody"]
    cut_deformation_bridges(body)
    apply_automatic_weights(body, arm)

    for obj in list(bpy.context.scene.objects):
        if obj in {arm, body} or obj.type != "MESH" or obj.name == "Plane":
            continue
        name = obj.name
        if name == "BodyHair":
            apply_weights(obj, arm, main_body_weights)
        elif name.startswith("Loincloth.Front"):
            apply_weights(obj, arm, lambda co: cloth_weights(co, True))
        elif name.startswith("Loincloth.Back"):
            apply_weights(obj, arm, lambda co: cloth_weights(co, False))
        elif name.startswith(("ClothWaistCord", "LoinKnot", "LoinTie", "LoinTail")):
            bone_parent(obj, arm, "pelvis")
        elif name.startswith(("Hair", "Eye", "Iris", "Pupil", "Brow", "UpperLid", "Nostril")):
            bone_parent(obj, arm, "head")
        elif name.startswith(("Areola", "Nipple")):
            bone_parent(obj, arm, "chest")
        elif name.startswith(("Fingernail", "Thumbnail")):
            bone_parent(obj, arm, "hand.L" if name.endswith(".L") else "hand.R")
        elif name.startswith("Toenail"):
            bone_parent(obj, arm, "foot.L" if name.endswith(".L") else "foot.R")
        else:
            apply_weights(obj, arm, main_body_weights)


def set_pose(arm, transforms):
    for pose_bone in arm.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0, 0, 0)
        pose_bone.location = (0, 0, 0)
        pose_bone.scale = (1, 1, 1)
    for name, values in transforms.items():
        bone = arm.pose.bones[name]
        if "rot" in values:
            bone.rotation_euler = tuple(radians(v) for v in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
        if "scale" in values:
            bone.scale = values["scale"]


def key_pose(arm, frame, transforms):
    set_pose(arm, transforms)
    for pose_bone in arm.pose.bones:
        pose_bone.keyframe_insert("rotation_euler", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert("location", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert("scale", frame=frame, group=pose_bone.name)


def key_upright_staff_pose(arm, frame, transforms):
    """Key a pose, then counter-rotate the grip so the rigid staff stays upright."""
    key_pose(arm, frame, transforms)
    bpy.context.view_layer.update()
    hand = arm.pose.bones["hand.R"]
    translation = hand.matrix.translation.copy()
    rest_rotation = arm.data.bones["hand.R"].matrix_local.to_quaternion()
    desired = Matrix.Translation(translation) @ rest_rotation.to_matrix().to_4x4()
    hand.matrix = desired
    hand.keyframe_insert("rotation_euler", frame=frame, group=hand.name)


def make_idle(arm):
    action = bpy.data.actions.new("Idle")
    arm.animation_data_create()
    arm.animation_data.action = action
    base = {
        "root": {"loc": (0.0, -0.006, 0.0)},
        "pelvis": {"loc": (-0.004, 0.0, 0.0), "rot": (1.4, -1.2, -0.4)},
        "spine": {"rot": (1.1, 0.6, 0.25)},
        "chest": {"rot": (-0.65, 0.9, -0.30)},
        "neck": {"rot": (-0.35, -0.35, 0.10)},
        "head": {"rot": (-0.75, -0.55, -0.08)},
        "thigh.L": {"rot": (-2.8, 0.0, -1.2)},
        "thigh.R": {"rot": (-1.2, 0.0, 1.2)},
        "shin.L": {"rot": (6.0, 0.0, 0.0)},
        "shin.R": {"rot": (3.5, 0.0, 0.0)},
        "foot.L": {"rot": (-0.4, 0.0, -0.5)},
        "foot.R": {"rot": (-0.2, 0.0, 0.5)},
        "clavicle.L": {"rot": (0.2, 0.0, -0.5)},
        "clavicle.R": {"rot": (-0.2, 0.0, 0.5)},
        "upper_arm.L": {"rot": (2.0, 1.5, -2.2)},
        "upper_arm.R": {"rot": (-1.0, -1.5, 2.2)},
        "forearm.L": {"rot": (-10.0, 0.0, 1.0)},
        "forearm.R": {"rot": (-13.0, 0.0, -1.0)},
        "hand.L": {"rot": (-2.5, 0.0, 1.8)},
        "hand.R": {"rot": (1.5, 0.0, -1.8)},
    }
    key_pose(arm, 1, base)
    inhale = dict(base)
    inhale.update({
        "root": {"loc": (-0.003, -0.003, 0.0)},
        "pelvis": {"loc": (-0.007, 0.0, 0.0), "rot": (0.8, -0.8, -0.2)},
        "spine": {"rot": (1.4, 0.35, 0.30)},
        "chest": {"rot": (-1.0, 0.45, -0.25), "scale": (1.009, 1.004, 1.010)},
        "clavicle.L": {"rot": (0.65, 0.0, -0.65)},
        "clavicle.R": {"rot": (-0.55, 0.0, 0.65)},
        "neck": {"rot": (-0.15, -0.15, 0.10)},
        "head": {"rot": (-0.55, -0.35, -0.08)},
        "thigh.L": {"rot": (-2.2, 0.0, -1.2)},
        "shin.L": {"rot": (5.0, 0.0, 0.0)},
    })
    key_pose(arm, 19, inhale)
    glance = dict(base)
    glance.update({
        "root": {"loc": (0.004, -0.007, 0.0)},
        "pelvis": {"loc": (0.005, 0.0, 0.0), "rot": (1.8, 1.4, 0.45)},
        "spine": {"rot": (1.0, -1.0, -0.25)},
        "chest": {"rot": (-0.35, -1.6, 0.35)},
        "neck": {"rot": (-0.25, 1.2, -0.10)},
        "head": {"rot": (-0.65, 2.2, 0.12)},
        "thigh.L": {"rot": (-1.0, 0.0, -1.2)},
        "thigh.R": {"rot": (-3.0, 0.0, 1.2)},
        "shin.L": {"rot": (3.0, 0.0, 0.0)},
        "shin.R": {"rot": (6.5, 0.0, 0.0)},
        "upper_arm.L": {"rot": (1.2, 1.5, -1.8)},
        "upper_arm.R": {"rot": (-1.8, -1.5, 2.0)},
        "loin_front": {"rot": (0.4, 0.0, -0.3)},
        "loin_back": {"rot": (-0.25, 0.0, 0.2)},
    })
    key_pose(arm, 37, glance)
    exhale = dict(base)
    exhale.update({
        "root": {"loc": (0.001, -0.010, 0.0)},
        "pelvis": {"loc": (0.001, 0.0, 0.0), "rot": (1.9, 0.2, 0.1)},
        "spine": {"rot": (0.55, 0.1, 0.10)},
        "chest": {"rot": (0.15, 0.0, -0.10), "scale": (0.997, 0.999, 0.998)},
        "neck": {"rot": (-0.45, 0.05, 0.06)},
        "head": {"rot": (-0.35, 0.1, -0.05)},
        "thigh.R": {"rot": (-2.0, 0.0, 1.2)},
        "shin.R": {"rot": (4.8, 0.0, 0.0)},
    })
    key_pose(arm, 55, exhale)
    key_pose(arm, 73, base)
    action.frame_start = 1
    action.frame_end = 73
    return action


def walk_pose(phase):
    # phase 0/4: contacts, 1/5: down, 2/6: passing, 3/7: up.
    table = [
        (+25, -25, +7, +8, +18, -22, -28, -34, -0.004),
        (+18, -17, +16, +22, +13, -17, -31, -32, -0.014),
        (+2, +3, +44, +10, -4, +4, -36, -28, -0.006),
        (-20, +20, +30, +8, -20, +18, -31, -35, +0.005),
        (-25, +25, +8, +7, -22, +18, -34, -28, -0.004),
        (-17, +18, +22, +16, -17, +13, -32, -31, -0.014),
        (+3, +2, +10, +44, +4, -4, -28, -36, -0.006),
        (+20, -20, +8, +30, +18, -20, -35, -31, +0.005),
    ][phase]
    lt, rt, ls, rs, la, ra, lfa, rfa, bob = table
    shift = (-0.010, -0.016, -0.008, 0.008, 0.010, 0.016, 0.008, -0.008)[phase]
    pelvis_yaw = (-4.0, -2.7, -0.4, 2.5, 4.0, 2.7, 0.4, -2.5)[phase]
    pelvis_side = (1.5, 2.4, 0.9, -1.0, -1.5, -2.4, -0.9, 1.0)[phase]
    chest_yaw = -0.72 * pelvis_yaw
    foot_left = (-45.0, -35.0, -12.0, 8.0, 12.0, 5.0, -2.0, -18.0)[phase]
    foot_right = (12.0, 5.0, -2.0, -18.0, -45.0, -35.0, -12.0, 8.0)[phase]
    toe_left = (18.0, 24.0, 8.0, 0.0, 0.0, 0.0, 0.0, 8.0)[phase]
    toe_right = (0.0, 0.0, 0.0, 8.0, 18.0, 24.0, 8.0, 0.0)[phase]
    return {
        # Root bone local Y follows the character's world-up axis.
        "root": {"loc": (0, bob, 0)},
        # A normal walk is almost upright.  The old accumulated pelvis/spine/
        # chest pitch made the hero look as though he was constantly falling
        # forward, while the head counter-rotation exaggerated the effect.
        "pelvis": {"loc": (shift, 0.0, 0.0), "rot": (1.4, pelvis_yaw, pelvis_side)},
        "spine": {"rot": (1.1, -0.30 * pelvis_yaw, -0.34 * pelvis_side)},
        "chest": {"rot": (0.6, chest_yaw, -0.34 * pelvis_side)},
        "neck": {"rot": (-0.7, -0.16 * chest_yaw, 0.16 * pelvis_side)},
        "head": {"rot": (-0.9, 0.10 * chest_yaw, -0.12 * pelvis_side)},
        "thigh.L": {"rot": (lt, 0.0, 0.0)},
        "thigh.R": {"rot": (rt, 0.0, 0.0)},
        "shin.L": {"rot": (ls, 0.0, 0.0)},
        "shin.R": {"rot": (rs, 0.0, 0.0)},
        "foot.L": {"rot": (foot_left, 0.0, -0.6 + 0.10 * pelvis_side)},
        "foot.R": {"rot": (foot_right, 0.0, 0.6 + 0.10 * pelvis_side)},
        "toe.L": {"rot": (toe_left, 0.0, 0.0)},
        "toe.R": {"rot": (toe_right, 0.0, 0.0)},
        "clavicle.L": {"rot": (0.11 * la, -0.08 * chest_yaw, -0.8)},
        "clavicle.R": {"rot": (0.11 * ra, -0.08 * chest_yaw, 0.8)},
        "upper_arm.L": {"rot": (la, 1.5, -3.0)},
        "upper_arm.R": {"rot": (ra, -1.5, 3.0)},
        "forearm.L": {"rot": (lfa, 0.0, 0.0)},
        "forearm.R": {"rot": (rfa, 0.0, 0.0)},
        "hand.L": {"rot": (-3.0 + 0.10 * la, -1.0, 2.0)},
        "hand.R": {"rot": (3.0 + 0.10 * ra, 1.0, -2.0)},
        "loin_front": {"rot": (-0.12 * (lt - rt), 0.0, 0.0)},
        "loin_back": {"rot": (-0.09 * (lt - rt), 0.0, 0.0)},
    }


def make_walk(arm):
    action = bpy.data.actions.new("Walk")
    arm.animation_data.action = action
    # Eight gait phases over one second at 24 fps.  The former 1.375-second
    # cycle was too slow for even a human-scale controller speed and made the
    # planted feet appear to slide backward.
    frames = [1, 4, 7, 10, 13, 16, 19, 22]
    for phase, frame in enumerate(frames):
        key_pose(arm, frame, walk_pose(phase))
    key_pose(arm, 25, walk_pose(0))
    return action


def torch_hold_pose(base_pose, phase=0):
    pose = dict(base_pose)
    carry_sway = (-1.2, -0.4, 0.6, 1.1, 0.7, -0.3, -0.9, -1.4)[phase % 8]
    pose.update({
        # The torch is carried just outside the left shoulder with the elbow
        # supporting its weight, rather than pinched against the breastplate.
        "clavicle.L": {"rot": (-1.0, 2.5, -3.0)},
        "upper_arm.L": {"rot": (-24.0 + 0.20 * carry_sway, 25.0, -9.0)},
        "forearm.L": {"rot": (-76.0 + carry_sway, -10.0, 8.0)},
        "hand.L": {"rot": (-8.0, -5.0, 8.0)},
    })
    return pose


def make_torch_idle(arm):
    action = bpy.data.actions.new("TorchIdle")
    arm.animation_data.action = action
    base = torch_hold_pose({
        "root": {"loc": (0.0, -0.006, 0.0)},
        "pelvis": {"loc": (0.004, 0.0, 0.0), "rot": (1.4, 1.0, 0.35)},
        "spine": {"rot": (1.0, -0.6, -0.2)},
        "chest": {"rot": (-0.6, -1.0, 0.25)},
        "neck": {"rot": (-0.4, 0.5, -0.1)},
        "head": {"rot": (-0.8, 0.8, 0.1)},
        "thigh.L": {"rot": (-1.5, 0.0, -1.0)},
        "thigh.R": {"rot": (-2.7, 0.0, 1.0)},
        "shin.L": {"rot": (3.5, 0.0, 0.0)},
        "shin.R": {"rot": (6.0, 0.0, 0.0)},
        "upper_arm.R": {"rot": (-2.0, -1.5, 2.0)},
        "forearm.R": {"rot": (-13.0, 0.0, -1.0)},
    })
    key_pose(arm, 1, base)
    breathe = torch_hold_pose(dict(base), 2)
    breathe.update({
        "root": {"loc": (-0.003, -0.003, 0.0)},
        "spine": {"rot": (1.5, -0.3, 0.1)},
        "chest": {"rot": (-1.1, -0.7, -0.15), "scale": (1.008, 1.003, 1.008)},
        "neck": {"rot": (-0.2, 0.4, 0.08)},
        "head": {"rot": (-0.6, 0.6, -0.08)},
    })
    key_pose(arm, 25, breathe)
    glance = torch_hold_pose(dict(base), 5)
    glance.update({
        "pelvis": {"loc": (-0.003, 0.0, 0.0), "rot": (1.7, -1.0, -0.2)},
        "chest": {"rot": (-0.4, 1.2, 0.3)},
        "neck": {"rot": (-0.3, -1.3, -0.1)},
        "head": {"rot": (-0.7, 2.1, 0.1)},
    })
    key_pose(arm, 49, glance)
    key_pose(arm, 73, base)
    return action


def make_torch_walk(arm):
    action = bpy.data.actions.new("TorchWalk")
    arm.animation_data.action = action
    frames = [1, 4, 7, 10, 13, 16, 19, 22]
    for phase, frame in enumerate(frames):
        key_pose(arm, frame, torch_hold_pose(walk_pose(phase), phase))
    key_pose(arm, 25, torch_hold_pose(walk_pose(0), 0))
    return action


def staff_hold_pose(base_pose, phase=0):
    """Hold the staff forward/outboard so no part passes through the torso."""
    pose = dict(base_pose)
    carry_sway = (-1.3, -0.5, 0.5, 1.1, 1.3, 0.5, -0.5, -1.1)[phase % 8]
    pose.update({
        # Move the complete arm diagonally forward/outboard, then counter that
        # rotation at the wrist.  This keeps the stave upright beside the hero
        # instead of laying it diagonally across the breastplate.
        "clavicle.R": {"rot": (-1.0, -2.0, 3.5)},
        "upper_arm.R": {"rot": (-23.0 + 0.08 * carry_sway, -38.0, 4.0)},
        "forearm.R": {"rot": (-14.0 + 0.10 * carry_sway, 3.0, -3.0)},
    })
    return pose


def make_staff_idle(arm):
    action = bpy.data.actions.new("StaffIdle")
    arm.animation_data.action = action
    base = staff_hold_pose({
        "root": {"loc": (0.0, -0.006, 0.0)},
        "pelvis": {"loc": (-0.003, 0.0, 0.0), "rot": (1.6, -1.0, -0.3)},
        "spine": {"rot": (1.2, 0.8, 0.2)},
        "chest": {"rot": (-0.8, 1.1, -0.3)},
        "neck": {"rot": (-0.4, -0.5, 0.1)},
        "head": {"rot": (-0.8, -0.7, -0.1)},
        "thigh.L": {"rot": (-2.8, 0.0, -1.0)},
        "thigh.R": {"rot": (-1.4, 0.0, 1.0)},
        "shin.L": {"rot": (6.0, 0.0, 0.0)},
        "shin.R": {"rot": (3.8, 0.0, 0.0)},
        "upper_arm.L": {"rot": (1.0, 1.5, -2.0)},
        "forearm.L": {"rot": (-12.0, 0.0, 1.0)},
    })
    key_upright_staff_pose(arm, 1, base)
    breathe = staff_hold_pose(dict(base), 2)
    breathe.update({
        "root":{"loc":(-.003,-.003,0.0)},
        "spine":{"rot":(1.6,.5,.25)},
        "chest":{"rot":(-1.3,.7,-.25),"scale":(1.008,1.003,1.009)},
        "neck":{"rot":(-.2,-.3,.08)},
        "head":{"rot":(-.6,-.5,-.08)},
    })
    key_upright_staff_pose(arm, 25, breathe)
    watch = staff_hold_pose(dict(base), 5)
    watch.update({
        "pelvis":{"loc":(.003,0.0,0.0),"rot":(1.8,1.2,.25)},
        "chest":{"rot":(-.5,-1.0,.3)},
        "neck":{"rot":(-.3,1.3,-.1)},
        "head":{"rot":(-.7,2.1,.1)},
    })
    key_upright_staff_pose(arm, 49, watch)
    key_upright_staff_pose(arm, 73, base)
    return action


def make_staff_walk(arm):
    action = bpy.data.actions.new("StaffWalk")
    arm.animation_data.action = action
    frames = [1, 4, 7, 10, 13, 16, 19, 22]
    for phase, frame in enumerate(frames):
        key_upright_staff_pose(arm, frame, staff_hold_pose(walk_pose(phase), phase))
    key_upright_staff_pose(arm, 25, staff_hold_pose(walk_pose(0), 0))
    return action


def clone_staff_cast(arm, source_action, name):
    """Author a one-handed spell while the other hand keeps the staff planted."""
    action = bpy.data.actions.new(name)
    arm.animation_data.action = action
    end = max(14, int(source_action.frame_end))
    charge_frame = max(4, int(round(end * 0.28)))
    release_frame = max(charge_frame + 3, int(round(end * 0.55)))
    follow_frame = min(end - 3, release_frame + 3)
    base = staff_hold_pose({
        "root": {"loc": (0.0, -0.008, 0.0)},
        "pelvis": {"rot": (1.5, -2.0, -0.3)},
        "spine": {"rot": (1.2, 1.5, 0.25)},
        "chest": {"rot": (-1.0, 2.0, -0.4)},
        "neck": {"rot": (-0.5, -0.7, 0.1)},
        "head": {"rot": (-1.0, -1.0, -0.1)},
        "thigh.L": {"rot": (-3.0, 0.0, -1.2)},
        "thigh.R": {"rot": (-1.0, 0.0, 1.2)},
        "shin.L": {"rot": (6.0, 0.0, 0.0)},
        "shin.R": {"rot": (3.0, 0.0, 0.0)},
        "upper_arm.L": {"rot": (-10.0, 8.0, -8.0)},
        "forearm.L": {"rot": (-36.0, -4.0, 5.0)},
        "hand.L": {"rot": (-5.0, -3.0, 6.0)},
    }, 0)
    charge = staff_hold_pose({
        "root": {"loc": (-.006, -.028, -.010)},
        "pelvis": {"rot": (5.0, -7.0, .8)},
        "spine": {"rot": (5.5, 7.0, -.7)},
        "chest": {"rot": (3.5, 11.0, -1.4)},
        "neck": {"rot": (-2.5, -4.0, .6)},
        "head": {"rot": (-3.5, -5.0, .6)},
        "thigh.L": {"rot": (-9.0, 0.0, -1.5)},
        "thigh.R": {"rot": (-6.0, 0.0, 1.5)},
        "shin.L": {"rot": (18.0, 0.0, 0.0)},
        "shin.R": {"rot": (13.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-3.0, 3.0, -5.0)},
        "upper_arm.L": {"rot": (-28.0, 15.0, -14.0)},
        "forearm.L": {"rot": (-76.0, -8.0, 9.0)},
        "hand.L": {"rot": (-13.0, -7.0, 12.0)},
        "loin_front": {"rot": (4.0, 0.0, -1.0)},
        "loin_back": {"rot": (-2.5, 0.0, .7)},
    }, 2)
    release = staff_hold_pose({
        "root": {"loc": (.008, -.004, .025)},
        "pelvis": {"rot": (-2.0, 6.0, -1.2)},
        "spine": {"rot": (-5.0, -7.0, 1.2)},
        "chest": {"rot": (-8.0, -12.0, 2.0)},
        "neck": {"rot": (4.0, 5.0, -.7)},
        "head": {"rot": (2.0, 6.0, -.6)},
        "thigh.L": {"rot": (-1.0, 0.0, -1.2)},
        "thigh.R": {"rot": (-5.0, 0.0, 1.2)},
        "shin.L": {"rot": (4.0, 0.0, 0.0)},
        "shin.R": {"rot": (10.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-4.0, 3.0, -5.0)},
        "upper_arm.L": {"rot": (-78.0, 16.0, -11.0)},
        "forearm.L": {"rot": (-24.0, -4.0, 7.0)},
        "hand.L": {"rot": (-16.0, -6.0, 12.0)},
        "loin_front": {"rot": (-5.0, 0.0, 1.2)},
        "loin_back": {"rot": (3.0, 0.0, -.8)},
    }, 4)
    follow = staff_hold_pose({
        "root": {"loc": (.003, -.010, .012)},
        "pelvis": {"rot": (1.0, 2.0, -.5)},
        "spine": {"rot": (-1.8, -2.5, .5)},
        "chest": {"rot": (-3.0, -4.0, .8)},
        "neck": {"rot": (1.0, 1.5, -.2)},
        "head": {"rot": (.3, 2.0, -.2)},
        "clavicle.L": {"rot": (-2.0, 2.0, -4.0)},
        "upper_arm.L": {"rot": (-58.0, 14.0, -10.0)},
        "forearm.L": {"rot": (-38.0, -3.0, 7.0)},
        "hand.L": {"rot": (-10.0, -4.0, 9.0)},
    }, 5)
    # Each spell keeps the same safe staff grip but gets a distinct readable
    # free-hand silhouette.
    if source_action.name == "Nova":
        charge.update({"root":{"loc":(-.004,-.050,0.0)},"chest":{"rot":(5.0,14.0,-2.2)},"upper_arm.L":{"rot":(-48.0,18.0,-20.0)},"forearm.L":{"rot":(-92.0,-8.0,12.0)}})
        release.update({"root":{"loc":(.006,.012,.012)},"chest":{"rot":(-9.0,-15.0,2.4)},"upper_arm.L":{"rot":(-88.0,20.0,-16.0)},"forearm.L":{"rot":(-34.0,-4.0,9.0)}})
    elif source_action.name == "Blink":
        charge.update({"root":{"loc":(0.0,-.060,-.035)},"pelvis":{"rot":(10.0,-2.0,0.0)},"spine":{"rot":(12.0,2.0,0.0)},"head":{"rot":(-8.0,-1.0,0.0)}})
        release.update({"root":{"loc":(0.0,.025,.050)},"pelvis":{"rot":(-6.0,2.0,0.0)},"spine":{"rot":(-9.0,-2.0,0.0)},"upper_arm.L":{"rot":(-58.0,16.0,-10.0)}})
    elif source_action.name == "Orb":
        charge.update({"upper_arm.L":{"rot":(-62.0,17.0,-14.0)},"forearm.L":{"rot":(-82.0,-6.0,10.0)},"hand.L":{"rot":(-18.0,-8.0,13.0)}})
        release.update({"upper_arm.L":{"rot":(-96.0,16.0,-9.0)},"forearm.L":{"rot":(-40.0,-4.0,8.0)},"hand.L":{"rot":(-20.0,-6.0,10.0)}})
    for frame, pose in (
        (1, base),
        (charge_frame, charge),
        (release_frame, release),
        (follow_frame, follow),
        (end, base),
    ):
        key_upright_staff_pose(arm, frame, pose)
    action.frame_start = 1
    action.frame_end = end
    return action


def make_jump(arm):
    action = bpy.data.actions.new("Jump")
    arm.animation_data.action = action
    anticipation = {
        "root": {"loc": (0.0, -0.092, -0.018)},
        "pelvis": {"rot": (8.0, -1.5, -0.5)},
        "spine": {"rot": (5.5, 1.0, 0.4)},
        "chest": {"rot": (2.5, 1.0, -0.4)},
        "neck": {"rot": (-2.0, -0.5, 0.2)},
        "head": {"rot": (-2.5, -0.8, -0.2)},
        "thigh.L": {"rot": (-27.0, 0.0, -2.5)},
        "thigh.R": {"rot": (-25.0, 0.0, 2.5)},
        "shin.L": {"rot": (54.0, 0.0, 0.0)},
        "shin.R": {"rot": (51.0, 0.0, 0.0)},
        "foot.L": {"rot": (4.0, 0.0, -0.5)},
        "foot.R": {"rot": (4.0, 0.0, 0.5)},
        "upper_arm.L": {"rot": (22.0, 4.0, -7.0)},
        "upper_arm.R": {"rot": (18.0, -4.0, 7.0)},
        "forearm.L": {"rot": (-38.0, 0.0, 3.0)},
        "forearm.R": {"rot": (-34.0, 0.0, -3.0)},
        "hand.L": {"rot": (-5.0, -4.0, 3.0)},
        "hand.R": {"rot": (5.0, 4.0, -3.0)},
        "loin_front": {"rot": (7.0, 0.0, 0.0)},
        "loin_back": {"rot": (-5.0, 0.0, 0.0)},
    }
    key_pose(arm, 1, anticipation)
    takeoff = dict(anticipation)
    takeoff.update({
        "root": {"loc": (0.0, 0.018, 0.026)},
        "pelvis": {"rot": (-3.5, 0.5, 0.0)},
        "spine": {"rot": (-4.0, -0.5, 0.0)},
        "chest": {"rot": (-5.5, -0.5, 0.0)},
        "neck": {"rot": (1.5, 0.2, 0.0)},
        "head": {"rot": (0.5, 0.3, 0.0)},
        "thigh.L": {"rot": (-1.0, 0.0, -1.5)},
        "thigh.R": {"rot": (-3.0, 0.0, 1.5)},
        "shin.L": {"rot": (4.0, 0.0, 0.0)},
        "shin.R": {"rot": (7.0, 0.0, 0.0)},
        "foot.L": {"rot": (-8.0, 0.0, -0.5)},
        "foot.R": {"rot": (-7.0, 0.0, 0.5)},
        "upper_arm.L": {"rot": (-48.0, 4.0, -7.0)},
        "upper_arm.R": {"rot": (-43.0, -4.0, 7.0)},
        "forearm.L": {"rot": (-21.0, 0.0, 3.0)},
        "forearm.R": {"rot": (-19.0, 0.0, -3.0)},
        "hand.L": {"rot": (-9.0, -7.0, 4.0)},
        "hand.R": {"rot": (9.0, 7.0, -4.0)},
        "loin_front": {"rot": (-8.0, 0.0, 0.0)},
        "loin_back": {"rot": (6.0, 0.0, 0.0)},
    })
    key_pose(arm, 4, takeoff)
    rise = dict(takeoff)
    rise.update({
        "root": {"loc": (0.0, 0.046, 0.038)},
        "pelvis": {"rot": (1.0, -1.0, -0.3)},
        "spine": {"rot": (-1.0, 1.0, 0.2)},
        "chest": {"rot": (-3.0, 1.0, -0.2)},
        "thigh.L": {"rot": (-12.0, 0.0, -3.0)},
        "thigh.R": {"rot": (-7.0, 0.0, 3.0)},
        "shin.L": {"rot": (34.0, 0.0, 0.0)},
        "shin.R": {"rot": (24.0, 0.0, 0.0)},
        "foot.L": {"rot": (-10.0, 0.0, -0.5)},
        "foot.R": {"rot": (-8.0, 0.0, 0.5)},
        "upper_arm.L": {"rot": (-22.0, 8.0, -10.0)},
        "upper_arm.R": {"rot": (-16.0, -8.0, 10.0)},
        "forearm.L": {"rot": (-52.0, -4.0, 5.0)},
        "forearm.R": {"rot": (-46.0, 4.0, -5.0)},
        "hand.L": {"rot": (-9.0, -7.0, 5.0)},
        "hand.R": {"rot": (9.0, 7.0, -5.0)},
    })
    key_pose(arm, 8, rise)
    apex = dict(rise)
    apex.update({
        "root": {"loc": (0.0, 0.064, 0.050)},
        "pelvis": {"rot": (4.0, -2.0, -0.6)},
        "spine": {"rot": (2.0, 2.0, 0.4)},
        "chest": {"rot": (-1.0, 2.0, -0.4)},
        "neck": {"rot": (-1.5, -1.0, 0.15)},
        "head": {"rot": (-2.5, -1.5, -0.15)},
        "thigh.L": {"rot": (-19.0, 0.0, -3.5)},
        "thigh.R": {"rot": (-10.0, 0.0, 3.5)},
        "shin.L": {"rot": (48.0, 0.0, 0.0)},
        "shin.R": {"rot": (33.0, 0.0, 0.0)},
        "foot.L": {"rot": (-7.0, 0.0, -0.5)},
        "foot.R": {"rot": (-5.0, 0.0, 0.5)},
        "upper_arm.L": {"rot": (-14.0, 9.0, -11.0)},
        "upper_arm.R": {"rot": (-10.0, -9.0, 11.0)},
        "forearm.L": {"rot": (-58.0, -4.0, 6.0)},
        "forearm.R": {"rot": (-52.0, 4.0, -6.0)},
        "hand.L": {"rot": (-10.0, -8.0, 5.0)},
        "hand.R": {"rot": (10.0, 8.0, -5.0)},
        "loin_front": {"rot": (-12.0, 0.0, 0.0)},
        "loin_back": {"rot": (9.0, 0.0, 0.0)},
    })
    key_pose(arm, 13, apex)
    descend = dict(apex)
    descend.update({
        "root": {"loc": (0.0, 0.028, 0.064)},
        "pelvis": {"rot": (3.5, 1.0, 0.3)},
        "spine": {"rot": (2.5, -1.0, -0.2)},
        "chest": {"rot": (1.0, -1.0, 0.2)},
        "neck": {"rot": (-1.5, 0.5, -0.1)},
        "head": {"rot": (-2.0, 0.8, 0.1)},
        "thigh.L": {"rot": (-12.0, 0.0, -2.0)},
        "thigh.R": {"rot": (-15.0, 0.0, 2.0)},
        "shin.L": {"rot": (27.0, 0.0, 0.0)},
        "shin.R": {"rot": (32.0, 0.0, 0.0)},
        "foot.L": {"rot": (1.0, 0.0, -0.3)},
        "foot.R": {"rot": (2.0, 0.0, 0.3)},
        "upper_arm.L": {"rot": (-6.0, 6.0, -8.0)},
        "upper_arm.R": {"rot": (-10.0, -6.0, 8.0)},
        "forearm.L": {"rot": (-38.0, 0.0, 3.0)},
        "forearm.R": {"rot": (-42.0, 0.0, -3.0)},
        "hand.L": {"rot": (-6.0, -5.0, 4.0)},
        "hand.R": {"rot": (6.0, 5.0, -4.0)},
        "loin_front": {"rot": (-5.0, 0.0, 0.0)},
        "loin_back": {"rot": (4.0, 0.0, 0.0)},
    })
    key_pose(arm, 19, descend)
    action.frame_start = 1
    action.frame_end = 19
    return action


def make_land(arm):
    action = bpy.data.actions.new("Land")
    arm.animation_data.action = action
    impact = {
        "root": {"loc": (0.0, -0.052, 0.022)},
        "pelvis": {"rot": (5.0, 1.0, 0.3)},
        "spine": {"rot": (3.0, -1.0, -0.2)},
        "chest": {"rot": (1.5, -1.0, 0.2)},
        "neck": {"rot": (-2.0, 0.5, -0.1)},
        "head": {"rot": (-2.5, 0.8, 0.1)},
        "thigh.L": {"rot": (-15.0, 0.0, -2.2)},
        "thigh.R": {"rot": (-18.0, 0.0, 2.2)},
        "shin.L": {"rot": (32.0, 0.0, 0.0)},
        "shin.R": {"rot": (38.0, 0.0, 0.0)},
        "foot.L": {"rot": (1.0, 0.0, -0.3)},
        "foot.R": {"rot": (1.5, 0.0, 0.3)},
        "upper_arm.L": {"rot": (-25.0, 4.0, -6.0)},
        "upper_arm.R": {"rot": (-31.0, -4.0, 6.0)},
        "forearm.L": {"rot": (-33.0, 0.0, 3.0)},
        "forearm.R": {"rot": (-39.0, 0.0, -3.0)},
    }
    key_pose(arm, 1, impact)
    compression = dict(impact)
    compression.update({
        "root": {"loc": (0.0, -0.122, 0.0)},
        "pelvis": {"rot": (10.0, -1.0, -0.4)},
        "spine": {"rot": (7.0, 1.0, 0.3)},
        "chest": {"rot": (4.0, 1.0, -0.3)},
        "neck": {"rot": (-3.0, -0.5, 0.1)},
        "head": {"rot": (-3.5, -0.8, -0.1)},
        "thigh.L": {"rot": (-30.0, 0.0, -2.5)},
        "thigh.R": {"rot": (-27.0, 0.0, 2.5)},
        "shin.L": {"rot": (61.0, 0.0, 0.0)},
        "shin.R": {"rot": (56.0, 0.0, 0.0)},
        "foot.L": {"rot": (2.5, 0.0, -0.4)},
        "foot.R": {"rot": (2.0, 0.0, 0.4)},
        "upper_arm.L": {"rot": (-10.0, 5.0, -7.0)},
        "upper_arm.R": {"rot": (-17.0, -5.0, 7.0)},
        "forearm.L": {"rot": (-46.0, 0.0, 4.0)},
        "forearm.R": {"rot": (-50.0, 0.0, -4.0)},
        "loin_front": {"rot": (8.0, 0.0, 0.0)},
        "loin_back": {"rot": (-6.0, 0.0, 0.0)},
    })
    key_pose(arm, 3, compression)
    recoil = dict(impact)
    recoil.update({
        "root": {"loc": (0.0, -0.048, 0.006)},
        "pelvis": {"rot": (6.0, 0.6, 0.2)},
        "spine": {"rot": (3.5, -0.6, -0.15)},
        "chest": {"rot": (1.0, -0.5, 0.15)},
        "thigh.L": {"rot": (-13.0, 0.0, -1.7)},
        "thigh.R": {"rot": (-15.0, 0.0, 1.7)},
        "shin.L": {"rot": (29.0, 0.0, 0.0)},
        "shin.R": {"rot": (32.0, 0.0, 0.0)},
        "upper_arm.L": {"rot": (-18.0, 3.0, -5.0)},
        "upper_arm.R": {"rot": (-22.0, -3.0, 5.0)},
        "forearm.L": {"rot": (-30.0, 0.0, 2.0)},
        "forearm.R": {"rot": (-34.0, 0.0, -2.0)},
    })
    key_pose(arm, 7, recoil)
    settle = {
        "root": {"loc": (0.0, -0.010, 0.0)},
        "pelvis": {"rot": (1.5, 0.0, 0.0)},
        "spine": {"rot": (0.8, 0.0, 0.0)},
        "chest": {"rot": (-0.3, 0.0, 0.0)},
        "neck": {"rot": (-0.2, 0.0, 0.0)},
        "head": {"rot": (-0.5, 0.0, 0.0)},
        "thigh.L": {"rot": (-3.0, 0.0, -1.0)},
        "thigh.R": {"rot": (-3.0, 0.0, 1.0)},
        "shin.L": {"rot": (7.0, 0.0, 0.0)},
        "shin.R": {"rot": (7.0, 0.0, 0.0)},
        "forearm.L": {"rot": (-12.0, 0.0, 1.0)},
        "forearm.R": {"rot": (-12.0, 0.0, -1.0)},
    }
    key_pose(arm, 13, settle)
    key_pose(arm, 18, {})
    action.frame_start = 1
    action.frame_end = 18
    return action


def make_roll(arm):
    """Grounded forward shoulder roll with a compact, protected tuck."""
    action = bpy.data.actions.new("Roll")
    arm.animation_data.action = action
    # Root lift values compensate for rotation around the rig origin so the
    # lowest body point remains approximately 1-2 cm above the floor.  The
    # horizontal offsets keep the authored clip in-place; gameplay supplies
    # the actual forward travel and therefore cannot double-slide the feet.
    poses = [
        # frame, spin, lift, horizontal compensation, thigh, shin, arm, elbow
        (1,   0, -.024, -.124, -20,  44, -24,  58),
        (4,  55, -.007, -.827, -54,  92, -52,  96),
        (7, 135, 1.474, -.477, -78, 122, -76, 118),
        (10,215,  .927,  .809, -84, 126, -82, 124),
        (13,295, -.003,  .609, -66, 104, -60, 106),
        (16,345, -.031,  .075, -30,  58, -30,  70),
        (19,360, -.028, -.011,  -6,  14,  -8,  20),
    ]
    for frame,spin,lift,forward,thigh,shin,arm_swing,elbow in poses:
        tucked=4<=frame<=13
        lead = 1.0 if frame <= 10 else -1.0
        key_pose(arm, frame, {
            "root":{"loc":(-.010*lead,lift,forward),"rot":(spin,-2.5*lead,-5.0*lead)},
            "pelvis":{"rot":(24.0 if tucked else (10.0 if frame<19 else 2.0),3.0*lead,-2.0*lead)},
            "spine":{"rot":(42.0 if tucked else (16.0 if frame<19 else 3.0),-4.0*lead,3.0*lead)},
            "chest":{"rot":(30.0 if tucked else (10.0 if frame<19 else 2.0),-5.0*lead,4.0*lead)},
            "neck":{"rot":(-32.0 if tucked else -6.0,3.0*lead,-2.0*lead)},
            "head":{"rot":(-40.0 if tucked else -8.0,4.0*lead,-3.0*lead)},
            "thigh.L":{"rot":(thigh-5.0*lead,0.0,-8.0)},
            "thigh.R":{"rot":(thigh+5.0*lead,0.0,8.0)},
            "shin.L":{"rot":(shin+6.0*lead,0.0,0.0)},
            "shin.R":{"rot":(shin-6.0*lead,0.0,0.0)},
            "foot.L":{"rot":((-24.0 if tucked else -10.0)-2.0*lead,0.0,-4.0)},
            "foot.R":{"rot":((-20.0 if tucked else -10.0)+2.0*lead,0.0,4.0)},
            "clavicle.L":{"rot":(-5.0,5.0,-8.0)},
            "clavicle.R":{"rot":(-2.0,-5.0,8.0)},
            "upper_arm.L":{"rot":(arm_swing-8.0,-8.0,-16.0)},
            "upper_arm.R":{"rot":(arm_swing+10.0,8.0,16.0)},
            "forearm.L":{"rot":(-elbow-8.0,-4.0,5.0)},
            "forearm.R":{"rot":(-elbow+6.0,4.0,-5.0)},
            "hand.L":{"rot":(-20.0,-3.0,12.0)},
            "hand.R":{"rot":(-16.0,3.0,-12.0)},
            "loin_front":{"rot":(-24.0 if tucked else 0.0,0.0,0.0)},
            "loin_back":{"rot":(20.0 if tucked else 0.0,0.0,0.0)},
        })
    action.frame_start = 1
    action.frame_end = 19
    return action


def make_spark(arm):
    action = bpy.data.actions.new("Spark")
    arm.animation_data.action = action
    key_pose(arm, 1, {})
    key_pose(arm, 3, {
        "root": {"loc": (-.006, -.018, -.008)},
        "pelvis": {"rot": (4.0, -7.0, .8)},
        "spine": {"rot": (4.0, 7.0, -.7)},
        "chest": {"rot": (2.0, 11.0, -1.2)},
        "neck": {"rot": (-2.0, -4.0, .5)},
        "head": {"rot": (-3.0, -5.0, .5)},
        "thigh.L": {"rot": (-7.0, 0.0, -1.0)},
        "thigh.R": {"rot": (-4.0, 0.0, 1.0)},
        "shin.L": {"rot": (15.0, 0.0, 0.0)},
        "shin.R": {"rot": (10.0, 0.0, 0.0)},
        "upper_arm.R": {"rot": (14.0, -22.0, 9.0)},
        "forearm.R": {"rot": (-58.0, 9.0, -7.0)},
        "hand.R": {"rot": (8.0, 6.0, -10.0)},
        "upper_arm.L": {"rot": (-20.0, 14.0, -9.0)},
        "forearm.L": {"rot": (-66.0, -7.0, 7.0)},
        "hand.L": {"rot": (-8.0, -5.0, 9.0)},
    })
    key_pose(arm, 6, {
        "root": {"loc": (.008, -.002, .022)},
        "pelvis": {"rot": (-2.0, 6.0, -1.0)},
        "spine": {"rot": (-5.0, -7.0, 1.0)},
        "chest": {"rot": (-8.0, -12.0, 1.8)},
        "neck": {"rot": (4.0, 5.0, -.6)},
        "head": {"rot": (2.0, 6.0, -.5)},
        "thigh.L": {"rot": (-1.0, 0.0, -1.0)},
        "thigh.R": {"rot": (-5.0, 0.0, 1.0)},
        "shin.L": {"rot": (4.0, 0.0, 0.0)},
        "shin.R": {"rot": (11.0, 0.0, 0.0)},
        "upper_arm.R": {"rot": (-76.0, -24.0, 3.0)},
        "forearm.R": {"rot": (-14.0, 5.0, -3.0)},
        "hand.R": {"rot": (-16.0, 4.0, -5.0)},
        "upper_arm.L": {"rot": (-28.0, 17.0, -11.0)},
        "forearm.L": {"rot": (-72.0, -6.0, 8.0)},
        "loin_front": {"rot": (-4.0, 0.0, 1.0)},
        "loin_back": {"rot": (3.0, 0.0, -.7)},
    })
    key_pose(arm, 9, {
        "root": {"loc": (.003, -.008, .010)},
        "pelvis": {"rot": (1.0, 2.0, -.4)},
        "spine": {"rot": (-2.0, -3.0, .5)},
        "chest": {"rot": (-3.0, -5.0, .8)},
        "upper_arm.R": {"rot": (-58.0, -20.0, 3.0)},
        "forearm.R": {"rot": (-29.0, 5.0, -4.0)},
        "hand.R": {"rot": (-10.0, 3.0, -4.0)},
        "upper_arm.L": {"rot": (-18.0, 12.0, -8.0)},
        "forearm.L": {"rot": (-48.0, -4.0, 6.0)},
    })
    key_pose(arm, 14, {})
    action.frame_start = 1
    action.frame_end = 14
    return action


def make_nova(arm):
    action = bpy.data.actions.new("Nova")
    arm.animation_data.action = action
    key_pose(arm, 1, {})
    key_pose(arm, 4, {
        "root": {"loc": (0.0, -0.060, -0.010)},
        "pelvis": {"rot": (10.0, -2.0, -.4)},
        "spine": {"rot": (8.0, 2.0, .3)},
        "chest": {"rot": (5.0, 3.0, -.4)},
        "neck": {"rot": (-3.0, -1.0, .1)},
        "head": {"rot": (-4.0, -1.5, -.1)},
        "thigh.L": {"rot": (-15.0, 0.0, -1.8)},
        "thigh.R": {"rot": (-13.0, 0.0, 1.8)},
        "shin.L": {"rot": (32.0, 0.0, 0.0)},
        "shin.R": {"rot": (28.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-3.0, 3.0, -5.0)},
        "clavicle.R": {"rot": (-3.0, -3.0, 5.0)},
        "upper_arm.L": {"rot": (-34.0, 18.0, -18.0)},
        "upper_arm.R": {"rot": (-31.0, -18.0, 18.0)},
        "forearm.L": {"rot": (-84.0, -8.0, 10.0)},
        "forearm.R": {"rot": (-80.0, 8.0, -10.0)},
        "hand.L": {"rot": (-12.0, -7.0, 12.0)},
        "hand.R": {"rot": (12.0, 7.0, -12.0)},
    })
    key_pose(arm, 8, {
        "root": {"loc": (0.0, -0.072, 0.0)},
        "pelvis": {"rot": (12.0, 0.0, 0.0)},
        "spine": {"rot": (10.0, 0.0, 0.0)},
        "chest": {"rot": (8.0, 0.0, 0.0)},
        "neck": {"rot": (-5.0, 0.0, 0.0)},
        "head": {"rot": (-6.0, 0.0, 0.0)},
        "thigh.L": {"rot": (-18.0, 0.0, -2.0)},
        "thigh.R": {"rot": (-18.0, 0.0, 2.0)},
        "shin.L": {"rot": (38.0, 0.0, 0.0)},
        "shin.R": {"rot": (38.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-4.0, 4.0, -6.0)},
        "clavicle.R": {"rot": (-4.0, -4.0, 6.0)},
        "upper_arm.L": {"rot": (-50.0, 20.0, -24.0)},
        "upper_arm.R": {"rot": (-50.0, -20.0, 24.0)},
        "forearm.L": {"rot": (-96.0, -10.0, 14.0)},
        "forearm.R": {"rot": (-96.0, 10.0, -14.0)},
        "hand.L": {"rot": (-17.0, -9.0, 16.0)},
        "hand.R": {"rot": (17.0, 9.0, -16.0)},
        "loin_front": {"rot": (6.0, 0.0, 0.0)},
        "loin_back": {"rot": (-4.0, 0.0, 0.0)},
    })
    key_pose(arm, 11, {
        "root": {"loc": (0.0, 0.018, 0.012)},
        "pelvis": {"rot": (-3.0, 0.0, 0.0)},
        "spine": {"rot": (-6.0, 0.0, 0.0)},
        "chest": {"rot": (-10.0, 0.0, 0.0)},
        "neck": {"rot": (5.0, 0.0, 0.0)},
        "head": {"rot": (3.0, 0.0, 0.0)},
        "thigh.L": {"rot": (-4.0, 0.0, -1.5)},
        "thigh.R": {"rot": (-4.0, 0.0, 1.5)},
        "shin.L": {"rot": (10.0, 0.0, 0.0)},
        "shin.R": {"rot": (10.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-4.0, 4.0, -6.0)},
        "clavicle.R": {"rot": (-4.0, -4.0, 6.0)},
        "upper_arm.L": {"rot": (-68.0, 20.0, -24.0)},
        "upper_arm.R": {"rot": (-68.0, -20.0, 24.0)},
        "forearm.L": {"rot": (-25.0, -5.0, 8.0)},
        "forearm.R": {"rot": (-25.0, 5.0, -8.0)},
        "hand.L": {"rot": (-10.0, -4.0, 10.0)},
        "hand.R": {"rot": (10.0, 4.0, -10.0)},
        "loin_front": {"rot": (-7.0, 0.0, 0.0)},
        "loin_back": {"rot": (5.0, 0.0, 0.0)},
    })
    key_pose(arm, 15, {
        "root": {"loc": (0.0, -0.008, 0.004)},
        "pelvis": {"rot": (1.0, 0.0, 0.0)},
        "spine": {"rot": (-1.5, 0.0, 0.0)},
        "chest": {"rot": (-3.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-2.0, 2.0, -4.0)},
        "clavicle.R": {"rot": (-2.0, -2.0, 4.0)},
        "upper_arm.L": {"rot": (-45.0, 17.0, -17.0)},
        "upper_arm.R": {"rot": (-45.0, -17.0, 17.0)},
        "forearm.L": {"rot": (-42.0, -4.0, 7.0)},
        "forearm.R": {"rot": (-42.0, 4.0, -7.0)},
    })
    key_pose(arm, 20, {})
    action.frame_start = 1
    action.frame_end = 20
    return action


def make_blink(arm):
    action = bpy.data.actions.new("Blink")
    arm.animation_data.action = action
    key_pose(arm, 1, {})
    key_pose(arm, 3, {
        "root": {"loc": (-.008, -0.052, -0.018)},
        "pelvis": {"rot": (12.0, -4.0, -.8)},
        "spine": {"rot": (11.0, 3.0, .5)},
        "chest": {"rot": (8.0, 4.0, -.6)},
        "neck": {"rot": (-5.0, -2.0, .2)},
        "head": {"rot": (-8.0, -2.5, -.2)},
        "thigh.L": {"rot": (-27.0, 0.0, -2.5)},
        "thigh.R": {"rot": (12.0, 0.0, 2.5)},
        "shin.L": {"rot": (31.0, 0.0, 0.0)},
        "shin.R": {"rot": (42.0, 0.0, 0.0)},
        "foot.L": {"rot": (3.0, 0.0, -.4)},
        "foot.R": {"rot": (-9.0, 0.0, .4)},
        "upper_arm.L": {"rot": (-48.0, 10.0, -7.0)},
        "upper_arm.R": {"rot": (27.0, -10.0, 7.0)},
        "forearm.L": {"rot": (-48.0, -4.0, 4.0)},
        "forearm.R": {"rot": (-39.0, 4.0, -4.0)},
        "loin_front": {"rot": (8.0, 0.0, -1.0)},
        "loin_back": {"rot": (-6.0, 0.0, .7)},
    })
    key_pose(arm, 6, {
        "root": {"loc": (.006, 0.012, 0.040)},
        "pelvis": {"rot": (-5.0, 3.0, .6)},
        "spine": {"rot": (-8.0, -2.0, -.4)},
        "chest": {"rot": (-10.0, -3.0, .5)},
        "neck": {"rot": (5.0, 1.5, -.2)},
        "head": {"rot": (3.0, 2.0, .2)},
        "thigh.L": {"rot": (9.0, 0.0, -2.0)},
        "thigh.R": {"rot": (-23.0, 0.0, 2.0)},
        "shin.L": {"rot": (39.0, 0.0, 0.0)},
        "shin.R": {"rot": (27.0, 0.0, 0.0)},
        "foot.L": {"rot": (-8.0, 0.0, -.3)},
        "foot.R": {"rot": (2.0, 0.0, .3)},
        "upper_arm.L": {"rot": (20.0, 9.0, -6.0)},
        "upper_arm.R": {"rot": (-46.0, -9.0, 6.0)},
        "forearm.L": {"rot": (-36.0, -3.0, 3.0)},
        "forearm.R": {"rot": (-45.0, 3.0, -3.0)},
        "loin_front": {"rot": (-10.0, 0.0, 1.0)},
        "loin_back": {"rot": (7.0, 0.0, -.7)},
    })
    key_pose(arm, 9, {
        "root": {"loc": (.002, -0.012, 0.018)},
        "pelvis": {"rot": (4.0, 1.0, .2)},
        "spine": {"rot": (3.0, -1.0, -.2)},
        "chest": {"rot": (1.5, -1.0, .2)},
        "thigh.L": {"rot": (-7.0, 0.0, -1.0)},
        "thigh.R": {"rot": (-3.0, 0.0, 1.0)},
        "shin.L": {"rot": (15.0, 0.0, 0.0)},
        "shin.R": {"rot": (9.0, 0.0, 0.0)},
        "upper_arm.L": {"rot": (-17.0, 6.0, -4.0)},
        "upper_arm.R": {"rot": (6.0, -6.0, 4.0)},
        "forearm.L": {"rot": (-31.0, -2.0, 2.0)},
        "forearm.R": {"rot": (-27.0, 2.0, -2.0)},
    })
    key_pose(arm, 13, {})
    action.frame_start = 1
    action.frame_end = 13
    return action


def make_orb(arm):
    action = bpy.data.actions.new("Orb")
    arm.animation_data.action = action
    key_pose(arm, 1, {})
    key_pose(arm, 5, {
        "root": {"loc": (0.0, -0.028, -0.008)},
        "pelvis": {"rot": (5.0, -2.0, -.4)},
        "spine": {"rot": (4.0, 2.0, .3)},
        "chest": {"rot": (2.0, 3.0, -.4)},
        "neck": {"rot": (-3.0, -1.5, .15)},
        "head": {"rot": (-5.0, -2.0, -.15)},
        "thigh.L": {"rot": (-8.0, 0.0, -1.5)},
        "thigh.R": {"rot": (-6.0, 0.0, 1.5)},
        "shin.L": {"rot": (18.0, 0.0, 0.0)},
        "shin.R": {"rot": (14.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-3.0, 3.0, -5.0)},
        "clavicle.R": {"rot": (-3.0, -3.0, 5.0)},
        "upper_arm.L": {"rot": (-50.0, 18.0, -18.0)},
        "upper_arm.R": {"rot": (-47.0, -18.0, 18.0)},
        "forearm.L": {"rot": (-76.0, -8.0, 10.0)},
        "forearm.R": {"rot": (-72.0, 8.0, -10.0)},
        "hand.L": {"rot": (-12.0, -7.0, 15.0)},
        "hand.R": {"rot": (12.0, 7.0, -15.0)},
    })
    key_pose(arm, 10, {
        "root": {"loc": (0.0, -0.042, 0.0)},
        "pelvis": {"rot": (7.0, 0.0, 0.0)},
        "spine": {"rot": (6.0, 0.0, 0.0)},
        "chest": {"rot": (4.0, 0.0, 0.0)},
        "neck": {"rot": (-4.0, 0.0, 0.0)},
        "head": {"rot": (-6.0, 0.0, 0.0)},
        "thigh.L": {"rot": (-11.0, 0.0, -1.8)},
        "thigh.R": {"rot": (-11.0, 0.0, 1.8)},
        "shin.L": {"rot": (24.0, 0.0, 0.0)},
        "shin.R": {"rot": (24.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-4.0, 4.0, -6.0)},
        "clavicle.R": {"rot": (-4.0, -4.0, 6.0)},
        "upper_arm.L": {"rot": (-62.0, 20.0, -20.0)},
        "upper_arm.R": {"rot": (-62.0, -20.0, 20.0)},
        "forearm.L": {"rot": (-88.0, -10.0, 13.0)},
        "forearm.R": {"rot": (-88.0, 10.0, -13.0)},
        "hand.L": {"rot": (-18.0, -9.0, 18.0)},
        "hand.R": {"rot": (18.0, 9.0, -18.0)},
    })
    key_pose(arm, 14, {
        "root": {"loc": (0.0, 0.010, 0.024)},
        "pelvis": {"rot": (-2.0, 0.0, 0.0)},
        "spine": {"rot": (-5.0, 0.0, 0.0)},
        "chest": {"rot": (-8.0, 0.0, 0.0)},
        "neck": {"rot": (4.0, 0.0, 0.0)},
        "head": {"rot": (2.0, 0.0, 0.0)},
        "thigh.L": {"rot": (-3.0, 0.0, -1.3)},
        "thigh.R": {"rot": (-3.0, 0.0, 1.3)},
        "shin.L": {"rot": (8.0, 0.0, 0.0)},
        "shin.R": {"rot": (8.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-4.0, 3.0, -5.0)},
        "clavicle.R": {"rot": (-4.0, -3.0, 5.0)},
        "upper_arm.L": {"rot": (-88.0, 16.0, -8.0)},
        "upper_arm.R": {"rot": (-88.0, -16.0, 8.0)},
        "forearm.L": {"rot": (-22.0, -4.0, 7.0)},
        "forearm.R": {"rot": (-22.0, 4.0, -7.0)},
        "hand.L": {"rot": (-12.0, -4.0, 10.0)},
        "hand.R": {"rot": (12.0, 4.0, -10.0)},
        "loin_front": {"rot": (-5.0, 0.0, 0.0)},
        "loin_back": {"rot": (4.0, 0.0, 0.0)},
    })
    key_pose(arm, 18, {
        "root": {"loc": (0.0, -0.008, 0.010)},
        "pelvis": {"rot": (1.0, 0.0, 0.0)},
        "spine": {"rot": (-1.5, 0.0, 0.0)},
        "chest": {"rot": (-3.0, 0.0, 0.0)},
        "clavicle.L": {"rot": (-2.0, 2.0, -4.0)},
        "clavicle.R": {"rot": (-2.0, -2.0, 4.0)},
        "upper_arm.L": {"rot": (-58.0, 14.0, -9.0)},
        "upper_arm.R": {"rot": (-58.0, -14.0, 9.0)},
        "forearm.L": {"rot": (-42.0, -3.0, 6.0)},
        "forearm.R": {"rot": (-42.0, 3.0, -6.0)},
    })
    key_pose(arm, 24, {})
    action.frame_start = 1
    action.frame_end = 24
    return action


def stash_actions(arm, *actions):
    arm.animation_data.action = None
    while arm.animation_data.nla_tracks:
        arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
    for action in actions:
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_range[0]), action)
        strip.action_frame_start = action.frame_range[0]
        strip.action_frame_end = action.frame_range[1]
        strip.mute = True


def clean_scene():
    for obj in list(bpy.context.scene.objects):
        if obj.type in {"CAMERA", "LIGHT"} or obj.name == "Plane":
            bpy.data.objects.remove(obj, do_unlink=True)


def main():
    clean_scene()
    arm = create_armature()
    rig_objects(arm)
    idle = make_idle(arm)
    walk = make_walk(arm)
    torch_idle = make_torch_idle(arm)
    torch_walk = make_torch_walk(arm)
    staff_idle = make_staff_idle(arm)
    staff_walk = make_staff_walk(arm)
    jump = make_jump(arm)
    land = make_land(arm)
    roll = make_roll(arm)
    spark = make_spark(arm)
    nova = make_nova(arm)
    blink = make_blink(arm)
    orb = make_orb(arm)
    staff_spark = clone_staff_cast(arm, spark, "StaffSpark")
    staff_nova = clone_staff_cast(arm, nova, "StaffNova")
    staff_blink = clone_staff_cast(arm, blink, "StaffBlink")
    staff_orb = clone_staff_cast(arm, orb, "StaffOrb")
    stash_actions(arm, idle, walk, torch_idle, torch_walk, staff_idle, staff_walk, jump, land, roll, spark, nova, blink, orb, staff_spark, staff_nova, staff_blink, staff_orb)
    bpy.context.scene.render.fps = 24
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 73
    bpy.context.scene.frame_set(1)
    for obj in bpy.context.scene.objects:
        obj.hide_viewport = False
        obj.hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print(f"RIGGED_FILE|{OUT}")
    print(f"ARMATURE|{arm.name}|bones={len(arm.data.bones)}")
    print("ACTIONS|" + ",".join(sorted(action.name for action in bpy.data.actions)))


if __name__ == "__main__":
    main()
