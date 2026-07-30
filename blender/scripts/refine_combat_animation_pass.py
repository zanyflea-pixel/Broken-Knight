"""Author a weighty diagonal sword cut and a dedicated fishing cast.

The right arm is solved to explicit wrist targets with a two-bone IK chain,
then baked into ordinary armature keyframes.  The exported GLB therefore has
no runtime constraints and remains deterministic in Godot.
"""

import bpy
import importlib.util
import math
import os
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(__file__)
spec = importlib.util.spec_from_file_location(
    "hero_rig_builder",
    os.path.join(SCRIPT_DIR, "rig_hero_for_godot.py"),
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

arm = bpy.data.objects["HeroRig"]
arm.animation_data_create()

# IK baking only needs the armature.  Hiding the 205 skinned render objects
# keeps each dependency-graph update from evaluating every armor/body mesh.
viewport_state = {}
for obj in bpy.context.scene.objects:
    if obj != arm and obj.type in {"MESH", "CURVE"}:
        viewport_state[obj.name] = obj.hide_viewport
        obj.hide_viewport = True


def merged(base, updates):
    result = dict(base)
    result.update(updates)
    return result


guard = {
    "root": {"loc": (0, -.010, 0)},
    "pelvis": {"rot": (2.5, -4.0, -.5)},
    "spine": {"rot": (2.2, 2.5, .4)},
    "chest": {"rot": (-1.0, 3.0, -.4)},
    "neck": {"rot": (-2.0, -1.0, .2)},
    "head": {"rot": (-3.0, 1.2, -.2)},
    "thigh.L": {"rot": (-4.0, 0, -2.0)},
    "thigh.R": {"rot": (-3.0, 0, 2.0)},
    "shin.L": {"rot": (9.0, 0, 0)},
    "shin.R": {"rot": (7.0, 0, 0)},
    "clavicle.L": {"rot": (-3.0, -2.0, -6.0)},
    "upper_arm.L": {"rot": (-31.0, 34.0, -18.0)},
    "forearm.L": {"rot": (-80.0, -18.0, 12.0)},
    "hand.L": {"rot": (-2.0, -7.0, 8.0)},
    "clavicle.R": {"rot": (-2.0, 2.0, 6.0)},
    "upper_arm.R": {"rot": (-16.0, -34.0, 6.0)},
    "forearm.R": {"rot": (-88.0, 18.0, -9.0)},
    "hand.R": {"rot": (4.0, -7.0, -13.0)},
}


def create_ik_helpers(label):
    target = bpy.data.objects.new(f"{label}_WristTarget", None)
    pole = bpy.data.objects.new(f"{label}_ElbowPole", None)
    bpy.context.scene.collection.objects.link(target)
    bpy.context.scene.collection.objects.link(pole)
    constraint = arm.pose.bones["forearm.R"].constraints.new("IK")
    constraint.name = f"{label}_BakeIK"
    constraint.target = target
    constraint.pole_target = pole
    constraint.chain_count = 2
    constraint.use_tail = True
    constraint.pole_angle = math.radians(-90.0)
    return target, pole, constraint


def bake_ik_action(name, keys, end_frame):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    arm.animation_data.action = action
    helpers = create_ik_helpers(name)
    target, pole, constraint = helpers
    for frame, transforms, wrist, elbow_pole, hand_rotation in keys:
        bpy.context.scene.frame_set(frame)
        target.location = wrist
        pole.location = elbow_pole
        target.keyframe_insert("location", frame=frame)
        pole.keyframe_insert("location", frame=frame)
        builder.key_pose(arm, frame, transforms)
        hand = arm.pose.bones["hand.R"]
        hand.rotation_mode = "XYZ"
        hand.rotation_euler = tuple(math.radians(value) for value in hand_rotation)
        hand.keyframe_insert("rotation_euler", frame=frame, group=hand.name)
        bpy.context.view_layer.update()
        solved_hand = arm.matrix_world @ hand.head
        print(
            f"IK_SOLVE|{name}|frame={frame}|"
            f"target={wrist[0]:.3f},{wrist[1]:.3f},{wrist[2]:.3f}|"
            f"hand={solved_hand.x:.3f},{solved_hand.y:.3f},{solved_hand.z:.3f}"
        )

    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.nla.bake(
        frame_start=1,
        frame_end=end_frame,
        step=1,
        only_selected=False,
        visual_keying=True,
        clear_constraints=False,
        clear_parents=False,
        use_current_action=True,
        clean_curves=False,
        bake_types={"POSE"},
    )
    if arm.pose.bones["forearm.R"].constraints.get(constraint.name) is not None:
        arm.pose.bones["forearm.R"].constraints.remove(constraint)
    bpy.data.objects.remove(target, do_unlink=True)
    bpy.data.objects.remove(pole, do_unlink=True)
    action.frame_start = 1
    action.frame_end = end_frame
    return action


sword_keys = (
    # Reference-driven single forehand cut based on an arming-sword/heater-
    # shield drill: shield forward, compact high guard beside the head, hips
    # initiate, hand crosses toward the opposite hip, then a clean recovery.
    # frame, body pose, wrist target, elbow guide, hand rotation
    (1, guard, (.375, -.257, 1.175), (.63, -.02, 1.29), (4, -7, -13)),
    (4, merged(guard, {
        "root": {"loc": (-.006, -.014, -.008)},
        "pelvis": {"rot": (5, -8, -2)}, "spine": {"rot": (5, -11, 2)},
        "chest": {"rot": (2, -14, 3)}, "neck": {"rot": (-3, 4, -1)},
        "head": {"rot": (-4, 5, -1)}, "shin.L": {"rot": (14, 0, 0)},
        "upper_arm.L": {"rot": (-30, 40, -17)}, "forearm.L": {"rot": (-82, -20, 13)},
    }), (.430, -.115, 1.350), (.69, .035, 1.34), (11, -10, -20)),
    (7, merged(guard, {
        "root": {"loc": (-.012, -.014, -.018)},
        "pelvis": {"rot": (7, -13, -3)}, "spine": {"rot": (7, -18, 3)},
        "chest": {"rot": (3, -22, 5)}, "neck": {"rot": (-4, 7, -1)},
        "head": {"rot": (-5, 8, -2)},
        "thigh.L": {"rot": (-8, 0, -2)}, "shin.L": {"rot": (17, 0, 0)},
        "upper_arm.L": {"rot": (-30, 41, -17)}, "forearm.L": {"rot": (-83, -20, 13)},
    }), (.475, .055, 1.515), (.73, .095, 1.39), (18, -15, -28)),
    (10, merged(guard, {
        "root": {"loc": (-.003, -.030, -.004)},
        "pelvis": {"rot": (3, -3, -1)}, "spine": {"rot": (1, -5, 1)},
        "chest": {"rot": (-2, -7, 2)}, "head": {"rot": (-2, 2, -1)},
        "thigh.R": {"rot": (-6, 0, 2)}, "shin.R": {"rot": (13, 0, 0)},
        "upper_arm.L": {"rot": (-30, 42, -18)}, "forearm.L": {"rot": (-84, -21, 14)},
    }), (.420, -.225, 1.455), (.70, -.025, 1.35), (8, -11, -12)),
    (13, merged(guard, {
        "root": {"loc": (.010, -.048, .015)},
        "pelvis": {"rot": (0, 7, 1)}, "spine": {"rot": (-5, 11, -2)},
        "chest": {"rot": (-8, 15, -3)}, "neck": {"rot": (2, -4, 1)},
        "head": {"rot": (1, -6, 1)},
        "thigh.L": {"rot": (-2, 0, -2)}, "thigh.R": {"rot": (-9, 0, 2)},
        "shin.L": {"rot": (8, 0, 0)}, "shin.R": {"rot": (18, 0, 0)},
        "upper_arm.L": {"rot": (-30, 43, -18)}, "forearm.L": {"rot": (-84, -21, 14)},
    }), (.205, -.445, 1.285), (.65, -.185, 1.27), (-8, -4, 13)),
    (16, merged(guard, {
        "root": {"loc": (.016, -.052, .018)},
        "pelvis": {"rot": (0, 11, 2)}, "spine": {"rot": (-7, 17, -3)},
        "chest": {"rot": (-10, 21, -4)}, "neck": {"rot": (3, -6, 1)},
        "head": {"rot": (2, -8, 1)}, "shin.R": {"rot": (20, 0, 0)},
        "upper_arm.L": {"rot": (-30, 43, -18)}, "forearm.L": {"rot": (-84, -21, 14)},
    }), (-.025, -.425, 1.050), (.60, -.145, 1.17), (-18, 3, 28)),
    (19, merged(guard, {
        "root": {"loc": (.010, -.035, .008)},
        "pelvis": {"rot": (2, 8, 1)}, "spine": {"rot": (-3, 12, -2)},
        "chest": {"rot": (-5, 15, -3)}, "head": {"rot": (-1, -5, 1)},
        "upper_arm.L": {"rot": (-30, 42, -18)}, "forearm.L": {"rot": (-83, -20, 13)},
    }), (.090, -.300, 1.055), (.61, -.075, 1.19), (-12, 1, 20)),
    (23, merged(guard, {
        "root": {"loc": (.002, -.020, .002)},
        "pelvis": {"rot": (3, 3, 0)}, "spine": {"rot": (1, 5, 0)},
        "chest": {"rot": (-2, 6, -1)}, "head": {"rot": (-3, -1, 0)},
    }), (.315, -.260, 1.140), (.63, -.035, 1.26), (5, -6, -10)),
    (27, guard, (.375, -.257, 1.175), (.63, -.02, 1.29), (4, -7, -13)),
)
# SwordSlash is authored by build_connected_sword_recovery.py. Preserve it here
# so fishing refinement cannot silently replace the accepted connected cut.
sword = bpy.data.actions.get("SwordSlash")
if sword is None:
    raise RuntimeError("The preserved simple SwordSlash action is missing")


fish_base = {
    "root": {"loc": (0, -.008, 0)},
    "pelvis": {"rot": (3, -3, -.5)}, "spine": {"rot": (3, 2, .5)},
    "chest": {"rot": (-1, 3, -.5)}, "neck": {"rot": (-2, -1, 0)},
    "head": {"rot": (-3, 1, 0)},
    "thigh.L": {"rot": (-5, 0, -2)}, "thigh.R": {"rot": (-3, 0, 2)},
    "shin.L": {"rot": (11, 0, 0)}, "shin.R": {"rot": (7, 0, 0)},
    "clavicle.L": {"rot": (-2, -1, -4)},
    "upper_arm.L": {"rot": (-24, 24, -12)}, "forearm.L": {"rot": (-66, -12, 9)},
    "hand.L": {"rot": (-3, -4, 6)},
    "clavicle.R": {"rot": (-2, 2, 5)},
}
fish_keys = (
    # Controlled overhead load, forward release and damped settle.  The rod now
    # receives exactly this wrist motion once; Godot no longer adds a second
    # sine-wave rotation on top.
    (1, fish_base, (.340, -.240, 1.180), (.61, -.01, 1.26), (4, -6, -10)),
    (4, merged(fish_base, {
        "root": {"loc": (-.006, -.008, -.010)}, "pelvis": {"rot": (5, -6, -1)},
        "spine": {"rot": (5, -8, 1)}, "chest": {"rot": (2, -10, 2)},
        "head": {"rot": (-3, 4, -1)}, "shin.L": {"rot": (14, 0, 0)},
    }), (.385, -.130, 1.355), (.67, .035, 1.32), (9, -9, -17)),
    (8, merged(fish_base, {
        "root": {"loc": (-.014, -.004, -.025)}, "pelvis": {"rot": (8, -13, -3)},
        "spine": {"rot": (8, -18, 3)}, "chest": {"rot": (4, -23, 5)},
        "neck": {"rot": (-4, 8, -1)}, "head": {"rot": (-5, 10, -2)},
        "thigh.L": {"rot": (-8, 0, -2)}, "shin.L": {"rot": (18, 0, 0)},
        "upper_arm.L": {"rot": (-30, 35, -16)}, "forearm.L": {"rot": (-78, -18, 12)},
    }), (.425, .075, 1.525), (.72, .110, 1.39), (17, -14, -27)),
    (11, merged(fish_base, {
        "root": {"loc": (-.002, -.030, -.004)}, "pelvis": {"rot": (3, -2, -1)},
        "spine": {"rot": (1, -3, 1)}, "chest": {"rot": (-2, -5, 1)},
        "head": {"rot": (-1, 2, 0)},
    }), (.355, -.315, 1.555), (.69, -.095, 1.36), (5, -10, -8)),
    (15, merged(fish_base, {
        "root": {"loc": (.012, -.050, .018)}, "pelvis": {"rot": (0, 7, 1)},
        "spine": {"rot": (-5, 11, -2)}, "chest": {"rot": (-9, 15, -3)},
        "neck": {"rot": (2, -4, 1)}, "head": {"rot": (1, -6, 1)},
        "thigh.R": {"rot": (-8, 0, 2)}, "shin.R": {"rot": (16, 0, 0)},
        "upper_arm.L": {"rot": (-31, 38, -17)}, "forearm.L": {"rot": (-80, -19, 13)},
    }), (.245, -.500, 1.315), (.62, -.235, 1.25), (-9, -4, 14)),
    (20, merged(fish_base, {
        "root": {"loc": (.004, -.025, .005)}, "pelvis": {"rot": (2, 2, 0)},
        "spine": {"rot": (0, 4, 0)}, "chest": {"rot": (-4, 6, -1)},
        "head": {"rot": (-2, -2, 0)},
    }), (.295, -.365, 1.235), (.61, -.120, 1.23), (-2, -5, 4)),
    (27, fish_base, (.340, -.240, 1.180), (.61, -.01, 1.26), (4, -6, -10)),
)
fish = bake_ik_action("FishCast", fish_keys, 27)

for action, frames in ((sword, (1, 4, 8)), (fish, (1, 4, 8, 11, 15, 20, 27))):
    arm.animation_data.action = action
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        hand = arm.matrix_world @ arm.pose.bones["hand.R"].head
        print(f"BAKED_HAND|{action.name}|frame={frame}|{hand.x:.3f},{hand.y:.3f},{hand.z:.3f}")

all_actions = [
    action for action in bpy.data.actions
    if action.name in {
        "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
        "Jump", "Land", "Roll", "Death", "Spark", "Nova", "Blink", "Orb",
        "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb", "WarriorIdle",
        "WarriorWalk", "SwordSlash", "ShieldBash", "FishCast",
    }
]
builder.stash_actions(arm, *sorted(all_actions, key=lambda action: action.name))
arm.animation_data.action = None
bpy.context.scene.frame_set(1)
for name, was_hidden in viewport_state.items():
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_viewport = was_hidden
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print(
    "COMBAT_ANIMATION_REFINED|SwordSlash=%d-%d-preserved|FishCast=1-27"
    % (sword.frame_start, sword.frame_end)
)
