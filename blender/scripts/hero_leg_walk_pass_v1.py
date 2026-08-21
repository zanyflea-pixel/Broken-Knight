"""Athletic leg sculpt and grounded eight-pose walk refresh for the hero master."""

from math import exp
import importlib.util
import os

import bpy


MARKER = "hero_leg_walk_v1"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RIG_SCRIPT = os.path.join(SCRIPT_DIR, "rig_hero_for_godot.py")
spec = importlib.util.spec_from_file_location("hero_rig_builder_leg_walk", RIG_SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def reshape_legs(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        if not (0.045 < ax < 0.285 and 0.140 < z < 0.990):
            continue

        side = 1.0 if x >= 0.0 else -1.0
        center_x = 0.130 * side
        local_x = point.x - center_x
        thigh = bell(z, 0.765, 0.175)
        upper_thigh = bell(z, 0.895, 0.085)
        knee = bell(z, 0.575, 0.052)
        calf = bell(z, 0.405, 0.110)
        ankle = bell(z, 0.175, 0.055)

        # Remove the balloon silhouette first. Muscle forms are added back in
        # specific directions below instead of uniformly inflating each limb.
        width_scale = 1.0 - 0.078 * thigh - 0.105 * knee - 0.035 * calf - 0.060 * ankle
        depth_scale = 1.0 - 0.060 * thigh - 0.095 * knee - 0.030 * calf - 0.055 * ankle
        point.x = center_x + local_x * width_scale
        point.y = 0.004 + (point.y - 0.004) * depth_scale

        # Quadriceps, patella, hamstrings, and calf belly create readable front,
        # side, and rear planes while retaining a narrow knee and ankle.
        local_abs = abs(point.x - center_x)
        outer_quad = bell(local_abs, 0.070, 0.035) * bell(z, 0.775, 0.135)
        inner_quad = bell(local_abs, 0.035, 0.026) * bell(z, 0.690, 0.110)
        patella = bell(local_abs, 0.025, 0.035) * bell(z, 0.575, 0.032)
        hamstring = bell(z, 0.735, 0.145)
        calf_belly = bell(z, 0.410, 0.095)
        shin_ridge = bell(local_abs, 0.020, 0.028) * bell(z, 0.360, 0.125)
        if point.y < 0.004:
            point.y -= 0.0065 * (0.65 * outer_quad + 0.55 * inner_quad)
            point.y -= 0.0035 * patella + 0.0018 * shin_ridge
        else:
            point.y += 0.0055 * hamstring + 0.0075 * calf_belly
        point.x += side * (0.0035 * outer_quad - 0.0015 * knee)

        vertex.co = inverse @ point

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body.data.update()


def warrior_guard_pose(base_pose, phase=0):
    pose = dict(base_pose)
    sway = (-1.5, -0.7, 0.4, 1.0, 1.5, 0.7, -0.4, -1.0)[phase % 8]
    pose.update({
        "clavicle.L": {"rot": (-3.0, -2.0, -6.0)},
        "upper_arm.L": {"rot": (-31.0 + 0.12 * sway, 34.0, -18.0)},
        "forearm.L": {"rot": (-80.0 + 0.26 * sway, -18.0, 12.0)},
        "hand.L": {"rot": (-2.0, -7.0, 8.0)},
        "clavicle.R": {"rot": (-2.0, 2.0, 6.0)},
        "upper_arm.R": {"rot": (-16.0 - 0.10 * sway, -34.0, 6.0)},
        "forearm.R": {"rot": (-88.0 - 0.22 * sway, 18.0, -9.0)},
        "hand.R": {"rot": (4.0, -7.0, -13.0)},
    })
    return pose


def warrior_walk_pose(phase):
    pose = warrior_guard_pose(builder.walk_pose(phase), phase)
    pelvis_rot = pose["pelvis"]["rot"]
    pose["spine"] = {"rot": (1.5, -0.26 * pelvis_rot[1], -0.20 * pelvis_rot[2])}
    pose["chest"] = {"rot": (1.0, -0.36 * pelvis_rot[1], -0.18 * pelvis_rot[2])}
    pose["neck"] = {"rot": (-0.8, 0.0, 0.0)}
    pose["head"] = {"rot": (-1.0, 0.0, 0.0)}
    return pose


def rebuild_walk_actions(rig):
    for name in ("Walk", "TorchWalk", "StaffWalk", "WarriorWalk"):
        action = bpy.data.actions.get(name)
        if action:
            bpy.data.actions.remove(action, do_unlink=True)

    walk = builder.make_walk(rig)
    torch_walk = builder.make_torch_walk(rig)
    staff_walk = builder.make_staff_walk(rig)
    warrior_walk = bpy.data.actions.new("WarriorWalk")
    rig.animation_data.action = warrior_walk
    for phase, frame in enumerate((1, 4, 7, 10, 13, 16, 19, 22)):
        builder.key_pose(rig, frame, warrior_walk_pose(phase))
    builder.key_pose(rig, 25, warrior_walk_pose(0))
    warrior_walk.frame_start = 1
    warrior_walk.frame_end = 25

    runtime_actions = [
        action for action in bpy.data.actions
        if action.get("bk_status") != "Reference only; not part of the verified runtime set"
    ]
    builder.stash_actions(rig, *sorted(runtime_actions, key=lambda action: action.name))
    return walk, torch_walk, staff_walk, warrior_walk


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_LEG_WALK_PASS|already_applied")
        return

    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    reshape_legs(body)

    mesh_visibility = {
        obj.name: (obj.hide_get(), obj.hide_viewport)
        for obj in bpy.context.scene.objects if obj.type == "MESH"
    }
    for name in mesh_visibility:
        obj = bpy.data.objects[name]
        obj.hide_set(True)
        obj.hide_viewport = True
    rebuild_walk_actions(rig)
    for name, (hidden, viewport_hidden) in mesh_visibility.items():
        obj = bpy.data.objects.get(name)
        if obj:
            obj.hide_viewport = viewport_hidden
            obj.hide_set(hidden)

    body[MARKER] = True
    body["hero_leg_walk_notes"] = (
        "Slimmed ballooned thigh/calf volumes; added quad, knee, hamstring and calf planes; "
        "rebuilt Walk, TorchWalk, StaffWalk and WarriorWalk with grounded contact/down/passing/up poses"
    )
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_LEG_WALK_PASS|legs_and_four_walk_actions|applied")


main()
