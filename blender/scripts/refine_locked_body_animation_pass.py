"""Refine the complete hero animation set for the locked continuous body.

This pass preserves meshes, weights and proportions.  It rebuilds the four
locomotion sets with clearer contact/down/passing/up mechanics, distinct carry
poses, a lower combat guard, and stronger anticipation/recovery for traversal.
Existing spell/combat clips are retained, but their interpolation and loop
metadata are normalized for predictable Godot playback.
"""

import importlib.util
import os

import bpy

print("LOCKED_BODY_ANIMATION_SCRIPT_LOADED", flush=True)


# Blender can execute this through both ``--python`` and an internal text
# runner.  Resolve against the open project file so neither mode inherits a
# stale ``__file__`` from another script.
SCRIPT_DIR = os.path.join(os.path.dirname(os.path.abspath(bpy.data.filepath)), "scripts")
BUILDER_PATH = os.path.join(SCRIPT_DIR, "build_full_continuous_runtime_candidate.py")
spec = importlib.util.spec_from_file_location("locked_runtime_builder", BUILDER_PATH)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
rig.animation_data_create()

RUNTIME_NAMES = {
    "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
    "WarriorIdle", "WarriorWalk", "Jump", "Land", "Roll", "Death",
    "Spark", "Nova", "Blink", "Orb", "StaffSpark", "StaffNova",
    "StaffBlink", "StaffOrb", "SwordSlash", "ShieldBash", "FishCast",
}
LOOPS = {
    "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
    "WarriorIdle", "WarriorWalk",
}


def copy_pose(pose):
    return {name: dict(values) for name, values in pose.items()}


def set_linear_root(action):
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    if bag.slot_handle != slot.handle:
                        continue
                    for curve in bag.fcurves:
                        if curve.data_path.endswith('pose.bones["root"].location'):
                            for point in curve.keyframe_points:
                                point.interpolation = "LINEAR"


def remove_actions(names):
    rig.animation_data.action = None
    for name in names:
        action = bpy.data.actions.get(name)
        if action is not None:
            bpy.data.actions.remove(action, do_unlink=True)


def base_idle_frames():
    base = {
        "root": {"loc": (0.0, 0.0, 0.0)},
        "pelvis": {"loc": (-0.003, 0.0, 0.0), "rot": (0.8, -1.4, -0.5)},
        "spine": {"rot": (0.8, 0.8, 0.25)},
        "chest": {"rot": (-0.5, 1.0, -0.30)},
        "neck": {"rot": (-0.35, -0.4, 0.12)},
        "head": {"rot": (-0.65, -0.6, -0.08)},
        "thigh.L": {"rot": (-2.8, 0.0, -1.4)},
        "thigh.R": {"rot": (-1.0, 0.0, 1.4)},
        "shin.L": {"rot": (6.0, 0.0, 0.0)},
        "shin.R": {"rot": (3.0, 0.0, 0.0)},
        "upper_arm.L": {"rot": (-7.0, 0.0, 18.0)},
        "upper_arm.R": {"rot": (-5.0, 0.0, -18.0)},
        "forearm.L": {"rot": (-22.0, 0.0, 4.0)},
        "forearm.R": {"rot": (-25.0, 0.0, -4.0)},
        "hand.L": {"rot": (-3.0, -1.0, 2.0)},
        "hand.R": {"rot": (3.0, 1.0, -2.0)},
    }
    inhale = copy_pose(base)
    inhale.update({
        "root": {"loc": (0.0, 0.003, 0.0)},
        "pelvis": {"loc": (-0.006, 0.0, 0.0), "rot": (0.4, -0.7, -0.2)},
        "spine": {"rot": (1.2, 0.4, 0.25)},
        "chest": {"rot": (-0.9, 0.5, -0.20), "scale": (1.007, 1.003, 1.008)},
        "head": {"rot": (-0.45, -0.3, -0.05)},
    })
    watch = copy_pose(base)
    watch.update({
        "root": {"loc": (0.0, -0.002, 0.0)},
        "pelvis": {"loc": (0.004, 0.0, 0.0), "rot": (1.2, 1.2, 0.35)},
        "spine": {"rot": (0.6, -0.8, -0.2)},
        "chest": {"rot": (-0.3, -1.4, 0.30)},
        "neck": {"rot": (-0.25, 1.1, -0.1)},
        "head": {"rot": (-0.55, 2.0, 0.1)},
        "thigh.L": {"rot": (-1.1, 0.0, -1.4)},
        "thigh.R": {"rot": (-2.8, 0.0, 1.4)},
        "shin.L": {"rot": (3.0, 0.0, 0.0)},
        "shin.R": {"rot": (6.0, 0.0, 0.0)},
    })
    return ((1, base), (21, inhale), (41, watch), (61, base))


def gait_phase(
    left_thigh, right_thigh, left_knee, right_knee,
    left_foot, right_foot, left_toe, right_toe,
    left_arm, right_arm, left_elbow, right_elbow,
    height, twist, side_shift,
):
    return {
        "root": {"loc": (0.0, 0.0, height)},
        "pelvis": {"loc": (side_shift, 0.0, 0.0), "rot": (0.8, 3.3 * twist, 2.0 * twist)},
        "spine": {"rot": (0.8, -1.0 * twist, -0.75 * twist)},
        "chest": {"rot": (0.25, -2.35 * twist, -0.82 * twist)},
        "neck": {"rot": (-0.45, 0.45 * twist, 0.18 * twist)},
        "head": {"rot": (-0.65, 0.28 * twist, -0.13 * twist)},
        "thigh.L": {"rot": (left_thigh, 0.0, 0.48 * left_thigh)},
        "thigh.R": {"rot": (right_thigh, 0.0, -0.48 * right_thigh)},
        "shin.L": {"rot": (left_knee, 0.0, 0.0)},
        "shin.R": {"rot": (right_knee, 0.0, 0.0)},
        "foot.L": {"rot": (left_foot, 0.0, -0.4)},
        "foot.R": {"rot": (right_foot, 0.0, 0.4)},
        "toe.L": {"rot": (left_toe, 0.0, 0.0)},
        "toe.R": {"rot": (right_toe, 0.0, 0.0)},
        # Back-swinging arms with naturally flexed elbows replace the former
        # straight, forward-held mannequin hands.
        "clavicle.L": {"rot": (0.05 * left_arm, 0.0, -0.6)},
        "clavicle.R": {"rot": (0.05 * right_arm, 0.0, 0.6)},
        "upper_arm.L": {"rot": (left_arm, 0.0, 18.0)},
        "upper_arm.R": {"rot": (right_arm, 0.0, -18.0)},
        "forearm.L": {"rot": (left_elbow, 0.0, 4.0)},
        "forearm.R": {"rot": (right_elbow, 0.0, -4.0)},
        "hand.L": {"rot": (-3.0 + 0.07 * left_arm, -1.0, 2.0)},
        "hand.R": {"rot": (3.0 + 0.07 * right_arm, 1.0, -2.0)},
        "loin_front": {"rot": (-0.10 * (left_thigh - right_thigh), 0.0, 0.0)},
        "loin_back": {"rot": (-0.07 * (left_thigh - right_thigh), 0.0, 0.0)},
    }


def walk_frames():
    phases = (
        # Restrained human walk: a shorter stride and longer grounded phase
        # replaces the floaty near-run silhouette of the first candidate.
        gait_phase(-17, 19, 7, 15, -11, 10, 0, 12, -13, 15, -22, -25, 0.004, 1.0, -0.005),
        gait_phase(-14, 13, 15, 18, -5, 13, 4, 16, -10, 12, -24, -27, -0.007, 0.68, -0.008),
        gait_phase(1, -4, 9, 36, 4, -6, 8, 3, 1, -2, -27, -23, 0.005, 0.05, -0.002),
        gait_phase(13, -15, 8, 33, 13, -10, 16, 0, 13, -15, -24, -22, 0.010, -0.72, 0.005),
        gait_phase(19, -17, 15, 7, 10, -11, 12, 0, 15, -13, -25, -22, 0.004, -1.0, 0.005),
        gait_phase(13, -14, 18, 15, 13, -5, 16, 4, 12, -10, -27, -24, -0.007, -0.68, 0.008),
        gait_phase(-4, 1, 36, 9, -6, 4, 3, 8, -2, 1, -23, -27, 0.005, -0.05, 0.002),
        gait_phase(-15, 13, 33, 8, -10, 13, 0, 16, -15, 13, -22, -24, 0.010, 0.72, -0.005),
    )
    frames = (1, 4, 7, 10, 13, 16, 19, 22)
    return tuple(zip(frames, phases)) + ((25, copy_pose(phases[0])),)


def torch_pose(base, phase):
    pose = copy_pose(base)
    sway = (-0.8, -0.3, 0.4, 0.8, 0.6, 0.1, -0.4, -0.7)[phase % 8]
    pose.update({
        "clavicle.L": {"rot": (-2.0, 0.0, 15.0)},
        "upper_arm.L": {"rot": (-42.0 + sway, 0.0, 33.0)},
        "forearm.L": {"rot": (-58.0 + 0.8 * sway, -8.0, 6.0)},
        "hand.L": {"rot": (-8.0, -5.0, 7.0)},
    })
    return pose


def staff_pose(base, phase):
    pose = copy_pose(base)
    sway = (-0.8, -0.3, 0.4, 0.8, 0.7, 0.2, -0.4, -0.7)[phase % 8]
    pose.update({
        "clavicle.R": {"rot": (-1.0, 0.0, -11.0)},
        "upper_arm.R": {"rot": (-28.0 + 0.5 * sway, 0.0, -31.0)},
        "forearm.R": {"rot": (-46.0 + 0.6 * sway, 7.0, -5.0)},
        "hand.R": {"rot": (6.0, 4.0, -7.0)},
    })
    return pose


def warrior_pose(base, phase):
    pose = copy_pose(base)
    weight = (0.6, 0.2, -0.3, -0.6, -0.5, -0.1, 0.3, 0.6)[phase % 8]
    pose.update({
        "spine": {"rot": (1.8, -0.8 * weight, -0.4 * weight)},
        "chest": {"rot": (2.8, -1.4 * weight, -0.5 * weight)},
        "neck": {"rot": (-1.6, 0.3 * weight, 0.0)},
        "head": {"rot": (-2.0, 0.4 * weight, 0.0)},
        # Anatomical right/sword arm (.L): elbow held away from ribs and the
        # sword carried beside the shoulder. Anatomical left/shield arm (.R):
        # forearm forward with the shield upright in front of the torso.
        # Positive local-X brings both forearms in front of the body. The prior
        # negative values placed both hands behind the spine and consequently
        # carried the sword and shield on the hero's back.
        "clavicle.L": {"rot": (-1.0, 0.0, 7.0)},
        "upper_arm.L": {"rot": (13.0 + weight, 3.0, 24.0)},
        "forearm.L": {"rot": (-42.0 + 0.5 * weight, -3.0, 5.0)},
        "hand.L": {"rot": (-3.0, -2.0, 4.0)},
        "clavicle.R": {"rot": (-1.0, 0.0, -7.0)},
        "upper_arm.R": {"rot": (11.0 - 0.5 * weight, -3.0, -24.0)},
        "forearm.R": {"rot": (-48.0 - 0.5 * weight, 3.0, -5.0)},
        "hand.R": {"rot": (3.0, 2.0, -4.0)},
    })
    return pose


def derived_frames(transformer):
    result = []
    source = walk_frames()
    for phase, (frame, pose) in enumerate(source[:-1]):
        result.append((frame, transformer(pose, phase)))
    result.append((25, transformer(source[0][1], 0)))
    return tuple(result)


def idle_from_pose(name, transformer):
    source = base_idle_frames()
    frames = []
    for phase, (frame, pose) in enumerate(source):
        # The final idle key must exactly repeat phase zero for a seamless
        # cyclic interpolation at the loop boundary.
        frames.append((frame, transformer(pose, 0 if phase == len(source) - 1 else phase * 2)))
    return builder.make_action(rig, name, frames, 61, True)


def ground_roll_action(action):
    """Keep the rolling body close to the floor without changing its path."""
    rig.animation_data.action = action
    for frame in (1, 5, 10, 15, 19, 22):
        bpy.context.scene.frame_set(frame)
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        world = evaluated.matrix_world
        minimum = min((world @ vertex.co).z for vertex in evaluated.data.vertices)
        root = rig.pose.bones["root"]
        root.location.z += 0.006 - minimum
        root.keyframe_insert(data_path="location", frame=frame, group="root")
    rig.animation_data.action = None


def rebuild_actions():
    replace = {
        "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
        "WarriorIdle", "WarriorWalk", "Jump", "Land", "Roll",
    }
    remove_actions(replace)
    print("ANIM_STAGE|old_actions_removed", flush=True)

    idle = builder.make_action(rig, "Idle", base_idle_frames(), 61, True)
    print("ANIM_STAGE|idle", flush=True)
    walk = builder.make_action(rig, "Walk", walk_frames(), 25, True)
    print("ANIM_STAGE|walk_authored", flush=True)
    builder.ground_walk_action(rig, body, walk)
    print("ANIM_STAGE|walk_grounded", flush=True)

    torch_idle = idle_from_pose("TorchIdle", torch_pose)
    print("ANIM_STAGE|torch_idle", flush=True)
    torch_walk = builder.make_action(rig, "TorchWalk", derived_frames(torch_pose), 25, True)
    builder.ground_walk_action(rig, body, torch_walk)
    print("ANIM_STAGE|torch_walk", flush=True)
    staff_idle = idle_from_pose("StaffIdle", staff_pose)
    staff_walk = builder.make_action(rig, "StaffWalk", derived_frames(staff_pose), 25, True)
    builder.ground_walk_action(rig, body, staff_walk)
    print("ANIM_STAGE|staff", flush=True)
    warrior_idle = idle_from_pose("WarriorIdle", warrior_pose)
    warrior_walk = builder.make_action(rig, "WarriorWalk", derived_frames(warrior_pose), 25, True)
    builder.ground_walk_action(rig, body, warrior_walk)
    print("ANIM_STAGE|warrior", flush=True)

    # Traversal gets explicit anticipation, airborne compression, impact and
    # recovery on the professional skeleton. The body has no obsolete cloth
    # bones, so these poses remain purely skeletal and topology-safe.
    jump_frames = (
        (1, {
            "root": {"loc": (0.0, 0.0, -0.075)}, "pelvis": {"rot": (8.0, 0.0, 0.0)},
            "spine": {"rot": (5.0, 0.0, 0.0)}, "chest": {"rot": (2.5, 0.0, 0.0)},
            "thigh.L": {"rot": (-28.0, 0.0, -13.0)}, "thigh.R": {"rot": (-28.0, 0.0, 13.0)},
            "shin.L": {"rot": (55.0, 0.0, 0.0)}, "shin.R": {"rot": (55.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (20.0, 0.0, 17.0)}, "upper_arm.R": {"rot": (20.0, 0.0, -17.0)},
            "forearm.L": {"rot": (-38.0, 0.0, 4.0)}, "forearm.R": {"rot": (-38.0, 0.0, -4.0)},
        }),
        (4, {
            "root": {"loc": (0.0, 0.0, 0.018)}, "pelvis": {"rot": (-4.0, 0.0, 0.0)},
            "spine": {"rot": (-4.0, 0.0, 0.0)}, "chest": {"rot": (-5.0, 0.0, 0.0)},
            "thigh.L": {"rot": (-3.0, 0.0, -1.0)}, "thigh.R": {"rot": (-5.0, 0.0, 1.0)},
            "shin.L": {"rot": (7.0, 0.0, 0.0)}, "shin.R": {"rot": (10.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (-45.0, 0.0, 17.0)}, "upper_arm.R": {"rot": (-42.0, 0.0, -17.0)},
            "forearm.L": {"rot": (-24.0, 0.0, 4.0)}, "forearm.R": {"rot": (-22.0, 0.0, -4.0)},
        }),
        (9, {
            "root": {"loc": (0.0, 0.0, 0.075)}, "pelvis": {"rot": (2.0, -1.0, -0.3)},
            "spine": {"rot": (0.5, 1.0, 0.2)}, "chest": {"rot": (-2.0, 1.0, -0.2)},
            "thigh.L": {"rot": (-18.0, 0.0, -8.5)}, "thigh.R": {"rot": (-10.0, 0.0, 4.8)},
            "shin.L": {"rot": (45.0, 0.0, 0.0)}, "shin.R": {"rot": (31.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (-16.0, 7.0, 18.0)}, "upper_arm.R": {"rot": (-12.0, -7.0, -18.0)},
            "forearm.L": {"rot": (-54.0, 0.0, 4.0)}, "forearm.R": {"rot": (-49.0, 0.0, -4.0)},
        }),
        (15, {
            "root": {"loc": (0.0, 0.0, 0.035)}, "pelvis": {"rot": (3.0, 1.0, 0.3)},
            "thigh.L": {"rot": (-11.0, 0.0, -5.2)}, "thigh.R": {"rot": (-14.0, 0.0, 6.7)},
            "shin.L": {"rot": (26.0, 0.0, 0.0)}, "shin.R": {"rot": (32.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (-8.0, 4.0, 18.0)}, "upper_arm.R": {"rot": (-11.0, -4.0, -18.0)},
            "forearm.L": {"rot": (-34.0, 0.0, 4.0)}, "forearm.R": {"rot": (-39.0, 0.0, -4.0)},
        }),
        (19, copy_pose(base_idle_frames()[0][1])),
    )
    land_frames = (
        (1, jump_frames[3][1]),
        (3, {
            "root": {"loc": (0.0, 0.0, -0.115)}, "pelvis": {"rot": (11.0, 0.0, 0.0)},
            "spine": {"rot": (7.0, 0.0, 0.0)}, "chest": {"rot": (4.0, 0.0, 0.0)},
            "thigh.L": {"rot": (-32.0, 0.0, -15.4)}, "thigh.R": {"rot": (-29.0, 0.0, 13.9)},
            "shin.L": {"rot": (63.0, 0.0, 0.0)}, "shin.R": {"rot": (58.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (-12.0, 4.0, 17.0)}, "upper_arm.R": {"rot": (-18.0, -4.0, -17.0)},
            "forearm.L": {"rot": (-45.0, 0.0, 4.0)}, "forearm.R": {"rot": (-49.0, 0.0, -4.0)},
        }),
        (8, {
            "root": {"loc": (0.0, 0.0, -0.032)}, "pelvis": {"rot": (5.0, 0.0, 0.0)},
            "thigh.L": {"rot": (-12.0, 0.0, -5.8)}, "thigh.R": {"rot": (-14.0, 0.0, 6.7)},
            "shin.L": {"rot": (28.0, 0.0, 0.0)}, "shin.R": {"rot": (31.0, 0.0, 0.0)},
            "upper_arm.L": {"rot": (-16.0, 0.0, 18.0)}, "upper_arm.R": {"rot": (-20.0, 0.0, -18.0)},
            "forearm.L": {"rot": (-29.0, 0.0, 4.0)}, "forearm.R": {"rot": (-32.0, 0.0, -4.0)},
        }),
        (14, copy_pose(base_idle_frames()[0][1])),
        (18, copy_pose(base_idle_frames()[0][1])),
    )
    roll_frames = (
        (1, {"root": {"loc": (0.0, 0.0, -0.035)}, "pelvis": {"rot": (12.0, 0.0, 0.0)},
             "thigh.L": {"rot": (-20.0, 0.0, -9.6)}, "thigh.R": {"rot": (-20.0, 0.0, 9.6)},
             "shin.L": {"rot": (45.0, 0.0, 0.0)}, "shin.R": {"rot": (45.0, 0.0, 0.0)}}),
        # Root compensation rotates around the tucked body's center instead
        # of around the feet. Runtime movement supplies forward travel.
        (5, {"root": {"loc": (0.0, 0.875, 0.635), "rot": (72.0, 0.0, 0.0)}, "pelvis": {"rot": (34.0, 0.0, 0.0)},
             "spine": {"rot": (43.0, 0.0, 0.0)}, "chest": {"rot": (30.0, 0.0, 0.0)},
             "thigh.L": {"rot": (-70.0, 0.0, -12.0)}, "thigh.R": {"rot": (-65.0, 0.0, 12.0)},
             "shin.L": {"rot": (112.0, 0.0, 0.0)}, "shin.R": {"rot": (106.0, 0.0, 0.0)},
             "upper_arm.L": {"rot": (-66.0, -8.0, 14.0)}, "upper_arm.R": {"rot": (-58.0, 8.0, -14.0)},
             "forearm.L": {"rot": (-104.0, 0.0, 5.0)}, "forearm.R": {"rot": (-98.0, 0.0, -5.0)}}),
        (10, {"root": {"loc": (0.0, 0.0, 1.840), "rot": (180.0, 0.0, 0.0)}, "pelvis": {"rot": (38.0, 0.0, 0.0)},
              "spine": {"rot": (46.0, 0.0, 0.0)}, "chest": {"rot": (32.0, 0.0, 0.0)},
              "thigh.L": {"rot": (-82.0, 0.0, -12.0)}, "thigh.R": {"rot": (-78.0, 0.0, 12.0)},
              "shin.L": {"rot": (124.0, 0.0, 0.0)}, "shin.R": {"rot": (120.0, 0.0, 0.0)},
              "upper_arm.L": {"rot": (-78.0, -8.0, 14.0)}, "upper_arm.R": {"rot": (-72.0, 8.0, -14.0)},
              "forearm.L": {"rot": (-118.0, 0.0, 5.0)}, "forearm.R": {"rot": (-112.0, 0.0, -5.0)}}),
        (15, {"root": {"loc": (0.0, -0.853, 0.575), "rot": (292.0, 0.0, 0.0)}, "pelvis": {"rot": (25.0, 0.0, 0.0)},
              "thigh.L": {"rot": (-48.0, 0.0, -10.0)}, "thigh.R": {"rot": (-44.0, 0.0, 10.0)},
              "shin.L": {"rot": (85.0, 0.0, 0.0)}, "shin.R": {"rot": (80.0, 0.0, 0.0)}}),
        (19, {"root": {"loc": (0.0, 0.0, -0.020), "rot": (360.0, 0.0, 0.0)},
              "pelvis": {"rot": (10.0, 0.0, 0.0)}, "spine": {"rot": (7.0, 0.0, 0.0)},
              "chest": {"rot": (5.0, 0.0, 0.0)}, "thigh.L": {"rot": (-18.0, 0.0, -7.0)},
              "thigh.R": {"rot": (-17.0, 0.0, 7.0)}, "shin.L": {"rot": (38.0, 0.0, 0.0)},
              "shin.R": {"rot": (36.0, 0.0, 0.0)}}),
        (22, {"root": {"loc": (0.0, 0.0, -0.015), "rot": (360.0, 0.0, 0.0)},
              "pelvis": {"rot": (4.0, 0.0, 0.0)}, "thigh.L": {"rot": (-7.0, 0.0, -2.0)},
              "thigh.R": {"rot": (-6.0, 0.0, 2.0)}, "shin.L": {"rot": (15.0, 0.0, 0.0)},
              "shin.R": {"rot": (13.0, 0.0, 0.0)}}),
    )
    for name, frames, end in (("Jump", jump_frames, 19), ("Land", land_frames, 18), ("Roll", roll_frames, 22)):
        action = builder.make_action(rig, name, frames, end, False)
        action.use_frame_range = True
        action.use_cyclic = False
        if name == "Roll":
            ground_roll_action(action)
        print(f"ANIM_STAGE|{name.lower()}", flush=True)


def normalize_and_stash():
    print("ANIM_STAGE|normalize_begin", flush=True)
    rig.animation_data.action = None
    while rig.animation_data.nla_tracks:
        rig.animation_data.nla_tracks.remove(rig.animation_data.nla_tracks[0])
    missing = sorted(RUNTIME_NAMES - set(bpy.data.actions.keys()))
    if missing:
        raise RuntimeError(f"Runtime actions missing: {missing}")
    for name in sorted(RUNTIME_NAMES):
        action = bpy.data.actions[name]
        action.use_frame_range = True
        action.use_cyclic = name in LOOPS
        if name in LOOPS:
            set_linear_root(action)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(action.frame_start), action)
        strip.action_frame_start = action.frame_start
        strip.action_frame_end = action.frame_end
        strip.mute = True
    print("ANIM_STAGE|normalize_done", flush=True)


def main():
    print("LOCKED_BODY_ANIMATION_MAIN_BEGIN", flush=True)
    before_vertices = len(body.data.vertices)
    before_polygons = len(body.data.polygons)
    rebuild_actions()
    normalize_and_stash()
    if len(body.data.vertices) != before_vertices or len(body.data.polygons) != before_polygons:
        raise RuntimeError("Animation pass changed body topology")
    rig.animation_data.action = bpy.data.actions["Idle"]
    bpy.context.scene.frame_set(1)
    bpy.context.scene.render.fps = 24
    bpy.context.scene["bk_animation_pass"] = "LockedBodyNaturalMotion_2026_08_13"
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print(
        "LOCKED_BODY_ANIMATION_PASS|actions=%d|loops=%d|body_verts=%d|file=%s"
        % (len(RUNTIME_NAMES), len(LOOPS), before_vertices, bpy.data.filepath)
    )


if __name__ == "__main__":
    main()
