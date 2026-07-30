"""Render deformation checks from the authored cave dragon actions."""

import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT_DIR = os.path.join(ROOT, "blender", "previews", "dragon_animation_checks")

scene = bpy.context.scene
armature = bpy.data.objects["DragonRig"]
camera = bpy.data.objects["PreviewCamera"]
floor = bpy.data.objects["PreviewFloor"]

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 820
scene.render.resolution_y = 620
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.camera = camera
floor.hide_render = False
camera.hide_render = False

for obj in scene.objects:
    if obj.type == "LIGHT":
        obj.hide_render = False

for track in armature.animation_data.nla_tracks:
    track.mute = True

os.makedirs(OUTPUT_DIR, exist_ok=True)
checks = (
    ("Idle", 25, (12.5, 15.5, 8.8), (0, -.35, 3.45)),
    ("Walk", 13, (12.5, 15.5, 8.8), (0, -.35, 3.45)),
    ("Attack", 18, (12.5, 15.5, 8.8), (0, .15, 3.55)),
    ("Roar", 42, (10.8, 16.2, 9.6), (0, .45, 3.75)),
    ("Death", 72, (14.8, 12.0, 8.0), (0, -1.0, 2.65)),
)

for action_name, frame, camera_location, target_location in checks:
    armature.animation_data.action = bpy.data.actions[action_name]
    scene.frame_start = 1
    scene.frame_end = int(bpy.data.actions[action_name].frame_end)
    scene.frame_set(frame)
    camera.location = camera_location
    target = Vector(target_location)
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 52
    path = os.path.join(OUTPUT_DIR, f"{action_name.lower()}_{frame:03d}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"DRAGON_CHECK|action={action_name}|frame={frame}|path={path}")

