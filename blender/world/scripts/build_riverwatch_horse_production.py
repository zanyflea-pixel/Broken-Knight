"""Build the single production Riverwatch horse from the best previous silhouette.

The V73 model had the strongest overall horse proportions, but its joined mesh
was never actually skinned: the armature animated invisibly while the horse
remained static. This pass keeps that silhouette, cleans the materials, and
adds deterministic vertex groups for a genuinely deforming quadruped rig.
"""

import math
import os

import bpy


ROOT = r"C:\Users\Jimmy\Desktop\Broken Knight"
SOURCE = os.path.join(
    ROOT,
    "blender",
    "world",
    "animals",
    "archive",
    "best_previous_v73",
    "riverwatch_horse_best_previous_v73.blend",
)
OUTPUT_BLEND = os.path.join(ROOT, "blender", "world", "animals", "riverwatch_horse.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "animals", "riverwatch_horse.glb")


def set_principled(material, color, roughness, metallic=0.0):
    if material is None:
        return
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node is None:
        return
    node.inputs["Base Color"].default_value = color
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in node.inputs:
        node.inputs["Coat Weight"].default_value = 0.06 if metallic <= 0.05 else 0.0


def tune_materials():
    palette = {
        "Riverwatch V67 Warm Bay": ((0.245, 0.073, 0.028, 1.0), 0.78, 0.0),
        "Riverwatch V67 Dark Points": ((0.025, 0.014, 0.010, 1.0), 0.88, 0.0),
        "Riverwatch V67 Hoof": ((0.055, 0.050, 0.046, 1.0), 0.91, 0.0),
        "Riverwatch V67 Muzzle": ((0.20, 0.16, 0.14, 1.0), 0.94, 0.0),
        "Riverwatch V67 Eyes": ((0.006, 0.004, 0.003, 1.0), 0.28, 0.0),
        "Riverwatch V67 Royal Blue": ((0.025, 0.105, 0.30, 1.0), 0.76, 0.05),
        "Riverwatch V67 Saddle Leather": ((0.095, 0.030, 0.014, 1.0), 0.84, 0.0),
        "Riverwatch V67 Saddle Highlight": ((0.27, 0.105, 0.040, 1.0), 0.79, 0.0),
        "Riverwatch V67 Brass": ((0.48, 0.245, 0.045, 1.0), 0.46, 0.72),
        "Riverwatch V67 Steel": ((0.25, 0.28, 0.30, 1.0), 0.52, 0.70),
    }
    for name, values in palette.items():
        set_principled(bpy.data.materials.get(name), *values)


def clear_active_pose(rig):
    if rig.animation_data:
        rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.location = (0.0, 0.0, 0.0)
        # The retained Idle/Trot actions key Euler channels. Changing these
        # bones to quaternion mode makes Blender preserve the clips by name
        # while silently ignoring their visible rotations.
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def consolidate_visual_meshes(rig):
    mesh_objects = []
    for obj in list(bpy.context.scene.objects):
        if obj.type not in {"MESH", "CURVE"}:
            continue
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        if obj.type == "CURVE":
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.convert(target="MESH")
            obj.select_set(False)
        mesh_objects.append(obj)

    body = bpy.data.objects.get("RiverwatchHorseBody")
    if body is None or body not in mesh_objects:
        raise RuntimeError("Best previous horse body was not found")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "RiverwatchHorseProductionBody"
    body.data.name = "RiverwatchHorseProductionMesh"
    for group in list(body.vertex_groups):
        body.vertex_groups.remove(group)
    for modifier in list(body.modifiers):
        body.modifiers.remove(modifier)
    return body


def vertex_material_names(mesh):
    result = [set() for _ in mesh.vertices]
    slot_names = [material.name if material else "" for material in mesh.materials]
    for polygon in mesh.polygons:
        material_name = slot_names[polygon.material_index] if polygon.material_index < len(slot_names) else ""
        for index in polygon.vertices:
            result[index].add(material_name)
    return result


def choose_bone(co, material_names):
    names = " ".join(material_names).lower()
    anatomy = any(token in names for token in ("warm bay", "dark points", "hoof", "muzzle", "eyes"))
    tack = any(token in names for token in ("royal blue", "saddle", "brass", "steel"))

    # Tack below the barrel is a stirrup, not a leg. Anatomy-only gating keeps
    # the saddle and bags attached to the torso while the true limbs articulate.
    if anatomy and co.z < 1.16 and not tack:
        front = co.y < 0.05
        side = "L" if co.x < 0.0 else "R"
        prefix = ("front" if front else "hind") + "." + side
        if "hoof" in names or co.z < 0.205:
            return prefix + ".hoof"
        if co.z < 0.625:
            return prefix + ".lower"
        return prefix + ".upper"

    if "dark points" in names and co.y > 0.82:
        return "tail.2" if co.y > 1.20 or co.z < 0.92 else "tail.1"
    if co.y < -0.88 and co.z > 1.34:
        return "head"
    if co.y < -0.34 and co.z > 1.13:
        return "neck"
    return "body"


def improve_silhouette(body, vertex_materials):
    # Keep the approved V73 proportions while taking the hardest polygonal
    # edges off its anatomical masses. Tack and hardware are never reshaped.
    for vertex in body.data.vertices:
        co = vertex.co
        names = " ".join(vertex_materials[vertex.index]).lower()
        anatomical_surface = any(token in names for token in ("warm bay", "dark points", "muzzle"))
        if not anatomical_surface:
            continue
        if 0.18 < co.y < 0.94 and 0.82 < co.z < 1.66:
            # Fuller, rounder hindquarter without the ballooned anatomy-v2 rump.
            co.x *= 1.045
            co.z += 0.018 * max(0.0, 1.0 - abs(co.y - 0.56) / 0.42)
        elif -0.34 < co.y <= 0.18 and 0.90 < co.z < 1.62:
            # A modest ribcage taper gives the shoulder and barrel a readable flow.
            co.x *= 1.018
        if co.y < -1.12 and co.z > 1.55:
            # Refine the broad shield-like muzzle into a narrower horse profile.
            co.x *= 0.92
            co.z = 1.86 + (co.z - 1.86) * 0.96


def skin_to_rig(body, rig):
    vertex_materials = vertex_material_names(body.data)
    improve_silhouette(body, vertex_materials)
    assignments = {bone.name: [] for bone in rig.data.bones}
    for vertex in body.data.vertices:
        bone_name = choose_bone(vertex.co, vertex_materials[vertex.index])
        if bone_name not in assignments:
            bone_name = "body"
        assignments[bone_name].append(vertex.index)
    for bone_name, indices in assignments.items():
        if not indices:
            continue
        group = body.vertex_groups.new(name=bone_name)
        group.add(indices, 1.0, "REPLACE")
    body.parent = rig
    modifier = body.modifiers.new("RiverwatchHorseSkin", "ARMATURE")
    modifier.object = rig
    for polygon in body.data.polygons:
        material = body.data.materials[polygon.material_index] if polygon.material_index < len(body.data.materials) else None
        material_name = material.name.lower() if material else ""
        polygon.use_smooth = any(token in material_name for token in ("warm bay", "dark points", "muzzle", "eyes"))
    body["production_asset"] = True
    body["source_revision"] = "best_previous_v73"
    rig["production_asset"] = True


def key_full_pose(rig, frame, pose):
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)
        values = pose.get(bone.name, {})
        if "loc" in values:
            bone.location = values["loc"]
        if "rot" in values:
            bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="scale", frame=frame, group=bone.name)


def make_production_actions(rig):
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for action_name in ("Idle", "Walk", "Trot", "Jump"):
        old = bpy.data.actions.get(action_name)
        if old is not None:
            bpy.data.actions.remove(old)

    idle = bpy.data.actions.new("Idle")
    rig.animation_data.action = idle
    idle_poses = {
        1: {"body": {"loc": (0.0, 0.0, 0.0)}, "neck": {"rot": (-1.0, 0.0, 0.0)}, "head": {"rot": (1.0, 0.0, 0.0)}, "tail.1": {"rot": (0.0, 0.0, -3.0)}},
        19: {"body": {"loc": (0.0, 0.0, 0.012)}, "neck": {"rot": (0.5, 0.0, 0.0)}, "head": {"rot": (-1.2, 0.0, 0.0)}, "tail.1": {"rot": (0.0, 0.0, 3.5)}},
        37: {"body": {"loc": (0.0, 0.0, 0.0)}, "neck": {"rot": (1.2, 0.0, 0.0)}, "head": {"rot": (-1.8, 0.0, 0.0)}, "tail.1": {"rot": (0.0, 0.0, -2.0)}},
        55: {"body": {"loc": (0.0, 0.0, -0.008)}, "neck": {"rot": (-0.4, 0.0, 0.0)}, "head": {"rot": (1.0, 0.0, 0.0)}, "tail.1": {"rot": (0.0, 0.0, 2.5)}},
        73: {"body": {"loc": (0.0, 0.0, 0.0)}, "neck": {"rot": (-1.0, 0.0, 0.0)}, "head": {"rot": (1.0, 0.0, 0.0)}, "tail.1": {"rot": (0.0, 0.0, -3.0)}},
    }
    for frame, pose in idle_poses.items():
        key_full_pose(rig, frame, pose)
    idle.use_frame_range = True
    idle.frame_start = 1
    idle.frame_end = 73

    # A restrained four-beat walk for ordinary mounted travel. Each leg is
    # phase-offset so the horse does not read as a two-legged mechanical pace.
    walk = bpy.data.actions.new("Walk")
    rig.animation_data.action = walk
    for frame in (1, 7, 13, 19, 25, 31, 37, 43, 49):
        phase = math.tau * float(frame - 1) / 48.0
        leg_phases = {
            "front.L": phase,
            "hind.R": phase + math.pi * 0.5,
            "front.R": phase + math.pi,
            "hind.L": phase + math.pi * 1.5,
        }
        pose = {
            "root": {"loc": (0.0, 0.0, 0.004 * math.sin(phase * 2.0))},
            "body": {"loc": (0.0, 0.0, 0.008 + 0.012 * (1.0 - abs(math.cos(phase * 2.0)))), "rot": (0.8 * math.sin(phase), 0.0, 0.6 * math.sin(phase * 2.0))},
            "neck": {"rot": (-1.4 - 1.0 * math.sin(phase), 0.0, 0.0)},
            "head": {"rot": (0.8 + 0.7 * math.sin(phase), 0.0, 0.0)},
            "tail.1": {"rot": (0.0, 0.0, 4.0 * math.sin(phase))},
            "tail.2": {"rot": (0.0, 0.0, 5.5 * math.sin(phase))},
        }
        for prefix, leg_phase in leg_phases.items():
            swing = math.sin(leg_phase)
            amplitude = 10.0 if prefix.startswith("front") else 9.0
            upper = amplitude * swing
            lower = 5.0 + max(0.0, -swing) * 11.0
            pose[prefix + ".upper"] = {"rot": (upper, 0.0, 0.0)}
            pose[prefix + ".lower"] = {"rot": (lower, 0.0, 0.0)}
            pose[prefix + ".hoof"] = {"rot": (-upper * 0.22, 0.0, 0.0)}
        key_full_pose(rig, frame, pose)
    walk.use_frame_range = True
    walk.frame_start = 1
    walk.frame_end = 49

    trot = bpy.data.actions.new("Trot")
    rig.animation_data.action = trot
    for frame in (1, 5, 9, 13, 17, 21, 25, 29, 33):
        phase = math.tau * float(frame - 1) / 32.0
        diagonal = math.sin(phase)
        lift = 1.0 - abs(math.cos(phase * 2.0))
        left_front = -17.0 * diagonal
        right_front = 17.0 * diagonal
        left_hind = 15.0 * diagonal
        right_hind = -15.0 * diagonal
        pose = {
            "root": {"loc": (0.0, 0.0, 0.012 * lift)},
            "body": {"loc": (0.0, 0.0, 0.018 + 0.025 * lift), "rot": (1.5 * diagonal, 0.0, 0.0)},
            "neck": {"rot": (-2.2 - 1.4 * diagonal, 0.0, 0.0)},
            "head": {"rot": (1.4 + 0.8 * diagonal, 0.0, 0.0)},
            "tail.1": {"rot": (0.0, 0.0, 6.0 * diagonal)},
            "tail.2": {"rot": (0.0, 0.0, 8.0 * diagonal)},
            "front.L.upper": {"rot": (left_front, 0.0, 0.0)},
            "front.R.upper": {"rot": (right_front, 0.0, 0.0)},
            "hind.L.upper": {"rot": (left_hind, 0.0, 0.0)},
            "hind.R.upper": {"rot": (right_hind, 0.0, 0.0)},
            "front.L.lower": {"rot": (7.0 + max(0.0, -diagonal) * 15.0, 0.0, 0.0)},
            "front.R.lower": {"rot": (7.0 + max(0.0, diagonal) * 15.0, 0.0, 0.0)},
            "hind.L.lower": {"rot": (9.0 + max(0.0, diagonal) * 13.0, 0.0, 0.0)},
            "hind.R.lower": {"rot": (9.0 + max(0.0, -diagonal) * 13.0, 0.0, 0.0)},
            "front.L.hoof": {"rot": (-left_front * 0.28, 0.0, 0.0)},
            "front.R.hoof": {"rot": (-right_front * 0.28, 0.0, 0.0)},
            "hind.L.hoof": {"rot": (-left_hind * 0.24, 0.0, 0.0)},
            "hind.R.hoof": {"rot": (-right_hind * 0.24, 0.0, 0.0)},
        }
        key_full_pose(rig, frame, pose)
    trot.use_frame_range = True
    trot.frame_start = 1
    trot.frame_end = 33

    # The controller supplies the actual ballistic movement. This clip keeps
    # the horse compact during takeoff, tucks its legs in flight, then extends
    # them for contact without adding root travel that would fight Godot.
    jump = bpy.data.actions.new("Jump")
    rig.animation_data.action = jump
    jump_poses = {
        1: {},
        6: {
            "body": {"loc": (0.0, 0.0, -0.045), "rot": (-2.0, 0.0, 0.0)},
            "neck": {"rot": (3.0, 0.0, 0.0)},
            "front.L.upper": {"rot": (-7.0, 0.0, 0.0)}, "front.R.upper": {"rot": (-7.0, 0.0, 0.0)},
            "front.L.lower": {"rot": (18.0, 0.0, 0.0)}, "front.R.lower": {"rot": (18.0, 0.0, 0.0)},
            "hind.L.upper": {"rot": (7.0, 0.0, 0.0)}, "hind.R.upper": {"rot": (7.0, 0.0, 0.0)},
            "hind.L.lower": {"rot": (20.0, 0.0, 0.0)}, "hind.R.lower": {"rot": (20.0, 0.0, 0.0)},
        },
        12: {
            "body": {"loc": (0.0, 0.0, 0.035), "rot": (4.0, 0.0, 0.0)},
            "neck": {"rot": (-5.0, 0.0, 0.0)}, "head": {"rot": (3.0, 0.0, 0.0)},
            "front.L.upper": {"rot": (-12.0, 0.0, 0.0)}, "front.R.upper": {"rot": (-12.0, 0.0, 0.0)},
            "front.L.lower": {"rot": (28.0, 0.0, 0.0)}, "front.R.lower": {"rot": (28.0, 0.0, 0.0)},
            "hind.L.upper": {"rot": (-8.0, 0.0, 0.0)}, "hind.R.upper": {"rot": (-8.0, 0.0, 0.0)},
            "hind.L.lower": {"rot": (26.0, 0.0, 0.0)}, "hind.R.lower": {"rot": (26.0, 0.0, 0.0)},
        },
        20: {
            "body": {"loc": (0.0, 0.0, 0.055), "rot": (1.0, 0.0, 0.0)},
            "neck": {"rot": (-2.0, 0.0, 0.0)}, "head": {"rot": (1.0, 0.0, 0.0)},
            "front.L.upper": {"rot": (-9.0, 0.0, 0.0)}, "front.R.upper": {"rot": (-9.0, 0.0, 0.0)},
            "front.L.lower": {"rot": (34.0, 0.0, 0.0)}, "front.R.lower": {"rot": (34.0, 0.0, 0.0)},
            "hind.L.upper": {"rot": (-10.0, 0.0, 0.0)}, "hind.R.upper": {"rot": (-10.0, 0.0, 0.0)},
            "hind.L.lower": {"rot": (32.0, 0.0, 0.0)}, "hind.R.lower": {"rot": (32.0, 0.0, 0.0)},
        },
        28: {
            "body": {"loc": (0.0, 0.0, -0.015), "rot": (-2.0, 0.0, 0.0)},
            "neck": {"rot": (4.0, 0.0, 0.0)},
            "front.L.upper": {"rot": (5.0, 0.0, 0.0)}, "front.R.upper": {"rot": (5.0, 0.0, 0.0)},
            "front.L.lower": {"rot": (7.0, 0.0, 0.0)}, "front.R.lower": {"rot": (7.0, 0.0, 0.0)},
            "hind.L.upper": {"rot": (4.0, 0.0, 0.0)}, "hind.R.upper": {"rot": (4.0, 0.0, 0.0)},
            "hind.L.lower": {"rot": (8.0, 0.0, 0.0)}, "hind.R.lower": {"rot": (8.0, 0.0, 0.0)},
        },
        35: {},
    }
    for frame, pose in jump_poses.items():
        key_full_pose(rig, frame, pose)
    jump.use_frame_range = True
    jump.frame_start = 1
    jump.frame_end = 35
    return [idle, walk, trot, jump]


def configure_actions(rig):
    required = make_production_actions(rig)
    for action in required:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_range[0]), action)
        strip.name = action.name
        strip.action_frame_start = action.frame_range[0]
        strip.action_frame_end = action.frame_range[1]
        track.mute = True
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 73


def export(rig, body):
    os.makedirs(os.path.dirname(OUTPUT_BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(OUTPUT_GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_force_sampling=True,
        export_skins=True,
        export_all_influences=False,
        export_lights=False,
        export_cameras=False,
    )


if not os.path.exists(SOURCE):
    raise FileNotFoundError(SOURCE)
bpy.ops.wm.open_mainfile(filepath=SOURCE)
rig = bpy.data.objects.get("RiverwatchHorseRig")
if rig is None or rig.type != "ARMATURE":
    raise RuntimeError("Best previous horse armature is missing")
clear_active_pose(rig)
tune_materials()
body = consolidate_visual_meshes(rig)
skin_to_rig(body, rig)
configure_actions(rig)
export(rig, body)
print(
    "RIVERWATCH_HORSE_PRODUCTION|blend=%s|glb=%s|vertices=%d|groups=%d|animations=Idle,Walk,Trot,Jump"
    % (OUTPUT_BLEND, OUTPUT_GLB, len(body.data.vertices), len(body.vertex_groups))
)
