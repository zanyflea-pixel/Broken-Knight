"""Topology-safe face correction and human movement refresh for the hero master."""

from math import exp
import importlib.util
import os

import bpy
from mathutils import Vector


MARKER = "hero_head_movement_v1"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RIG_SCRIPT = os.path.join(SCRIPT_DIR, "rig_hero_for_godot.py")
spec = importlib.util.spec_from_file_location("hero_rig_builder_head_movement", RIG_SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def clamp01(value):
    return max(0.0, min(1.0, value))


def smoothstep(low, high, value):
    t = clamp01((value - low) / (high - low))
    return t * t * (3.0 - 2.0 * t)


def sculpt_adult_head(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        if not (1.602 < z < 1.905 and ax < .150):
            continue

        # The old head was nearly as wide as it was tall.  Taper it into an
        # adult skull while retaining a broad jaw and blending into the neck.
        head_blend = smoothstep(1.605, 1.646, z)
        jaw = bell(z, 1.650, .036)
        chin_taper = bell(z, 1.615, .024)
        width_scale = 1.0 - head_blend * (.140 - .032 * jaw + .075 * chin_taper)
        point.x *= width_scale

        x, y, z = point
        ax = abs(x)
        front = clamp01((-y - .035) / .090)
        if front <= 0.0:
            vertex.co = inverse @ point
            continue

        # Establish readable adult planes: orbital recess, cheekbone, cheek
        # hollow, brow shelf, nose bridge/tip, modest lips, and a real chin.
        eye_socket = bell(ax, .027, .027) * bell(z, 1.760, .019)
        brow_shelf = bell(ax, .030, .033) * bell(z, 1.786, .016)
        cheekbone = bell(ax, .054, .028) * bell(z, 1.724, .030)
        cheek_hollow = bell(ax, .057, .030) * bell(z, 1.690, .024)
        temple = bell(ax, .077, .024) * bell(z, 1.765, .052)
        nose_bridge = bell(ax, 0.0, .012) * bell(z, 1.742, .041)
        nose_tip = bell(ax, 0.0, .018) * bell(z, 1.704, .014)
        alar_plane = bell(ax, .013, .009) * bell(z, 1.702, .012)
        philtrum = bell(ax, 0.0, .013) * bell(z, 1.691, .013)
        upper_lip = bell(ax, 0.0, .031) * bell(z, 1.680, .0065)
        lower_lip = bell(ax, 0.0, .033) * bell(z, 1.671, .0070)
        mouth_mass = bell(ax, 0.0, .045) * bell(z, 1.677, .018)
        mouth_crease = bell(ax, 0.0, .031) * bell(z, 1.676, .0035)
        chin = bell(ax, 0.0, .042) * bell(z, 1.635, .022)
        mental_crease = bell(ax, 0.0, .038) * bell(z, 1.650, .006)

        point.y += front * (
            .0055 * eye_socket
            + .0040 * cheek_hollow
            + .0025 * temple
            + .0060 * mouth_mass
            + .0028 * mouth_crease
            + .0025 * mental_crease
        )
        point.y -= front * (
            .0035 * brow_shelf
            + .0040 * cheekbone
            + .0100 * nose_bridge
            + .0130 * nose_tip
            + .0030 * alar_plane
            + .0020 * philtrum
            + .0020 * upper_lip
            + .0026 * lower_lip
            + .0090 * chin
        )
        if z < 1.642 and ax < .050:
            point.z -= .0045 * bell(z, 1.623, .020)

        vertex.co = inverse @ point

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body.data.update()


def tighten_mouth_materials(body):
    slots = {material.name: index for index, material in enumerate(body.data.materials) if material}
    skin_index = slots.get("Skin")
    lip_index = slots.get("LipTone")
    dark_index = slots.get("Dark")
    if skin_index is None:
        return
    world = body.matrix_world
    for polygon in body.data.polygons:
        center = sum((world @ body.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if polygon.material_index == lip_index:
            if abs(center.x) > .0290 or not (1.670 < center.z < 1.6845):
                polygon.material_index = skin_index
        elif polygon.material_index == dark_index:
            if abs(center.x) > .0265 or not (1.6745 < center.z < 1.6805):
                polygon.material_index = skin_index
    lip = bpy.data.materials.get("LipTone")
    if lip:
        lip.diffuse_color = (.22, .080, .060, 1.0)
        lip.roughness = .88
        if lip.use_nodes:
            bsdf = lip.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = lip.diffuse_color
                bsdf.inputs["Roughness"].default_value = .88
    body.data.update()


def transform_part(obj, global_x=.86, local_x=1.0, local_z=1.0, inset_y=0.0):
    if obj is None or obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    points = [world @ vertex.co for vertex in obj.data.vertices]
    center = sum(points, Vector()) / len(points)
    new_center_x = center.x * global_x
    for vertex, point in zip(obj.data.vertices, points):
        point.x = new_center_x + (point.x - center.x) * global_x * local_x
        point.z = center.z + (point.z - center.z) * local_z
        point.y += inset_y
        vertex.co = inverse @ point
    obj.data.update()


def refit_face_parts():
    for side in ("-1", "1"):
        for prefix in ("Eye", "Iris", "Pupil", "UpperLid", "EyeHighlight"):
            transform_part(
                bpy.data.objects.get(f"{prefix}.{side}"),
                global_x=.86,
                local_x=.90 if prefix in {"Eye", "UpperLid"} else .92,
                local_z=.72 if prefix in {"Eye", "UpperLid"} else .80,
                inset_y=.0022,
            )
        # Each old brow crossed the facial center line.  Shorten it around its
        # own center, thin its heavy bar profile, and seat it into the brow.
        transform_part(
            bpy.data.objects.get(f"Brow.{side}"),
            global_x=.86,
            local_x=.62,
            local_z=.46,
            inset_y=.0026,
        )
        transform_part(
            bpy.data.objects.get(f"Nostril.{side}"),
            global_x=.86,
            local_x=1.02,
            local_z=.92,
            inset_y=0.0,
        )

    hair = bpy.data.objects.get("Hair")
    transform_part(hair, global_x=.87, local_x=1.0, local_z=1.0, inset_y=0.0)


def warrior_guard_pose(base_pose, phase=0):
    pose = dict(base_pose)
    sway = (-1.5, -.7, .4, 1.0, 1.5, .7, -.4, -1.0)[phase % 8]
    pose.update({
        "clavicle.L": {"rot": (-3.0, -2.0, -6.0)},
        "upper_arm.L": {"rot": (-31.0 + .12 * sway, 34.0, -18.0)},
        "forearm.L": {"rot": (-80.0 + .26 * sway, -18.0, 12.0)},
        "hand.L": {"rot": (-2.0, -7.0, 8.0)},
        "clavicle.R": {"rot": (-2.0, 2.0, 6.0)},
        "upper_arm.R": {"rot": (-16.0 - .10 * sway, -34.0, 6.0)},
        "forearm.R": {"rot": (-88.0 - .22 * sway, 18.0, -9.0)},
        "hand.R": {"rot": (4.0, -7.0, -13.0)},
    })
    pelvis_rot = pose["pelvis"]["rot"]
    pose["spine"] = {"rot": (1.5, -.26 * pelvis_rot[1], -.20 * pelvis_rot[2])}
    pose["chest"] = {"rot": (1.0, -.36 * pelvis_rot[1], -.18 * pelvis_rot[2])}
    pose["neck"] = {"rot": (-.8, 0.0, 0.0)}
    pose["head"] = {"rot": (-1.0, 0.0, 0.0)}
    return pose


def rebuild_movement_actions(rig):
    names = ("Walk", "TorchWalk", "StaffWalk", "WarriorWalk", "Jump", "Land", "Roll")
    for name in names:
        action = bpy.data.actions.get(name)
        if action:
            bpy.data.actions.remove(action, do_unlink=True)

    builder.make_walk(rig)
    builder.make_torch_walk(rig)
    builder.make_staff_walk(rig)
    warrior_walk = bpy.data.actions.new("WarriorWalk")
    rig.animation_data.action = warrior_walk
    for phase, frame in enumerate((1, 4, 7, 10, 13, 16, 19, 22)):
        builder.key_pose(rig, frame, warrior_guard_pose(builder.walk_pose(phase), phase))
    builder.key_pose(rig, 25, warrior_guard_pose(builder.walk_pose(0), 0))
    warrior_walk.frame_start = 1
    warrior_walk.frame_end = 25
    builder.make_jump(rig)
    builder.make_land(rig)
    builder.make_roll(rig)

    runtime_actions = [
        action for action in bpy.data.actions
        if action.get("bk_status") != "Reference only; not part of the verified runtime set"
    ]
    builder.stash_actions(rig, *sorted(runtime_actions, key=lambda action: action.name))


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_HEAD_MOVEMENT_PASS|already_applied")
        return

    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()

    sculpt_adult_head(body)
    tighten_mouth_materials(body)
    refit_face_parts()
    rebuild_movement_actions(rig)

    body[MARKER] = True
    body["hero_head_movement_notes"] = (
        "Narrowed adult skull and jaw silhouette; rebuilt orbital, cheek, nose, mouth, and chin planes; "
        "reduced and seated eyes/brows/lips; rebuilt carried and unarmed walks with subtle bob and upright torso; "
        "refreshed Jump, Land, and Roll from the movement source"
    )
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_HEAD_MOVEMENT_PASS|head_and_seven_movement_actions|applied")


main()
