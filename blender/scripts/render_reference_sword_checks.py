"""Render the restored simple sword-and-shield swing."""

import math
import os

import bpy
from mathutils import Euler, Matrix, Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODE = os.environ.get("SWORD_RENDER_MODE", "simple_arc")
LABEL = os.environ.get("SWORD_RENDER_LABEL", "sword_simple_rollback")
GRIP_ALONG_HAND = float(os.environ.get("SWORD_GRIP_ALONG_HAND", "0.62"))
ACTION_SOURCE = os.environ.get("SWORD_ACTION_SOURCE", "")
OUT = os.path.join(ROOT, "blender", "previews", LABEL)
SWORD = os.path.join(ROOT, "godot", "assets", "equipment", "royal_vanguard_sword.glb")
SHIELD = os.path.join(ROOT, "godot", "assets", "equipment", "royal_vanguard_shield.glb")
os.makedirs(OUT, exist_ok=True)


def import_root(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    imported = [obj for obj in bpy.data.objects if obj not in before]
    roots = [obj for obj in imported if obj.parent is None or obj.parent not in imported]
    if not roots:
        raise RuntimeError("No imported root for " + path)
    return roots[0]


def set_sword_pose(root, hand, hand_bone, phase):
    hand_world = arm.matrix_world @ hand_bone.matrix
    grip_point = hand_world @ Vector((0.0, hand_bone.length * GRIP_ALONG_HAND, 0.0))
    if MODE == "bone_follow":
        root.matrix_world = (
            Matrix.Translation(grip_point)
            @ hand_world.to_3x3().normalized().to_4x4()
        )
        return
    if MODE == "bone_follow_calibrated":
        hand_basis = hand_world.to_3x3().normalized()
        root.matrix_world = (
            Matrix.Translation(grip_point)
            @ (hand_basis @ grip_correction).to_4x4()
        )
        return
    arc = math.sin(phase * math.pi)
    basis = Euler(
        (-.12 - arc * 1.18, .05 + arc * .48, -.12 - arc * .32),
        "XYZ",
    ).to_matrix().to_4x4()
    root.matrix_world = Matrix.Translation(hand) @ basis


scene = bpy.context.scene
arm = bpy.data.objects["HeroRig"]
if ACTION_SOURCE:
    with bpy.data.libraries.load(ACTION_SOURCE, link=False) as (available, requested):
        if "SwordSlash" not in available.actions:
            raise RuntimeError("SwordSlash missing from " + ACTION_SOURCE)
        requested.actions = ["SwordSlash"]
    reference_action = requested.actions[0]
    reference_action.name = "SwordSlash_RenderReference"
else:
    reference_action = bpy.data.actions["SwordSlash"]
arm.animation_data.action = reference_action
sword = import_root(SWORD)
shield = import_root(SHIELD)
scene.frame_set(1)
bpy.context.view_layer.update()
guard_hand_basis = (arm.matrix_world @ arm.pose.bones["hand.R"].matrix).to_3x3().normalized()
guard_sword_basis = Euler((-.12, .05, -.12), "XYZ").to_matrix()
grip_correction = guard_hand_basis.inverted() @ guard_sword_basis

for obj in scene.objects:
    if obj.name.startswith("RoyalStaff_"):
        obj.hide_render = True
    if obj.name.startswith(("Loincloth.", "LoinTie.", "LoinKnot.", "LoinTail.")):
        obj.hide_render = True
    for modifier in getattr(obj, "modifiers", []):
        if modifier.type == "SUBSURF":
            modifier.levels = 0
            modifier.render_levels = 0

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.studio_light = "paint.sl"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.display.shading.curvature_ridge_factor = 1.4
scene.display.shading.curvature_valley_factor = 1.1
scene.render.resolution_x = 620
scene.render.resolution_y = 760
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -.35
scene.world.color = (.012, .016, .025)

bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, -.006))
floor = bpy.context.object
floor.name = "SwordReferenceFloor"
floor_material = bpy.data.materials.new("SwordReferenceFloorMaterial")
floor_material.diffuse_color = (.045, .052, .068, 1.0)
floor.data.materials.append(floor_material)

bpy.ops.object.camera_add(location=(2.70, -4.30, 2.02))
camera = bpy.context.object
camera.data.lens = 64
camera.rotation_euler = (
    Vector((0.0, 0.0, 1.08)) - camera.location
).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera

action_end = int(round(arm.animation_data.action.frame_range[1]))
if action_end == 8:
    samples = (
        ("ready", 1, 0.0),
        ("swipe", 4, 3.0 / 24.0),
        ("reset", 8, 7.0 / 24.0),
    )
elif action_end == 19:
    samples = (
        ("guard", 1, 0.0),
        ("load", 4, 3.0 / 24.0),
        ("launch", 6, 5.0 / 24.0),
        ("impact", 8, 7.0 / 24.0),
        ("follow", 11, 10.0 / 24.0),
        ("recover", 16, 15.0 / 24.0),
        ("guard_return", 19, 18.0 / 24.0),
    )
elif action_end == 13:
    samples = (
        ("guard", 1, 0.0),
        ("load", 3, 2.0 / 24.0),
        ("launch", 5, 4.0 / 24.0),
        ("impact", 7, 6.0 / 24.0),
        ("follow", 9, 8.0 / 24.0),
        ("recover", 11, 10.0 / 24.0),
        ("guard_return", 13, 12.0 / 24.0),
    )
else:
    samples = (
        ("start", 2, .083),
        ("rise", 6, .250),
        ("cut", 12, .500),
        ("follow", 18, .750),
        ("recover", 24, 1.000),
    )
render_only = os.environ.get("SWORD_RENDER_ONLY", "")
if render_only:
    samples = tuple(sample for sample in samples if sample[0] == render_only)
action_duration = float(action_end) / 24.0
for name, frame, sample_time in samples:
    phase = sample_time / action_duration
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    right_hand_bone = arm.pose.bones["hand.R"]
    right_hand = arm.matrix_world @ right_hand_bone.head
    left_hand = arm.matrix_world @ arm.pose.bones["hand.L"].head
    set_sword_pose(sword, right_hand, right_hand_bone, phase)
    shield_clear = __import__("math").sin(phase * __import__("math").pi) * .035
    shield.location = left_hand + Vector((-.090 - shield_clear, -.145, -.025 - shield_clear * .22))
    shield.rotation_euler = (-.08, -.14, .10)
    scene.render.filepath = os.path.join(OUT, f"{LABEL}_{name}.png")
    bpy.ops.render.render(write_still=True)
    print(
        "SWORD_RENDER|mode=%s|%s|frame=%d|hand=%.3f,%.3f,%.3f"
        % (MODE, name, frame, right_hand.x, right_hand.y, right_hand.z)
    )

print("SWORD_RENDER_COMPLETE|mode=%s|%s" % (MODE, OUT))
