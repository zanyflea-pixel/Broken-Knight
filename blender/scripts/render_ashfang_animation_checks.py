"""Render compact Ashfang action checks from the accepted Blender source."""

import os

import bpy


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "blender", "previews", "ashfang_checks")

scene = bpy.context.scene
arm = bpy.data.objects.get("AshfangRig")
camera = bpy.data.objects.get("PreviewCamera")
if arm is None or camera is None:
    raise RuntimeError("Ashfang rig or preview camera is missing.")

for obj in scene.objects:
    if obj.name.startswith("Preview"):
        obj.hide_render = False

scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
scene.render.resolution_y = 520
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
os.makedirs(OUT_DIR, exist_ok=True)

checks = (
    ("run_stride", "Run", 7),
    ("attack_bite", "Attack", 8),
    ("death_fall", "Death", 27),
)
for label, action_name, frame in checks:
    arm.animation_data.action = bpy.data.actions[action_name]
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(OUT_DIR, f"ashfang_{label}.png")
    bpy.ops.render.render(write_still=True)
    print(f"ASHFANG_RENDER|{action_name}|frame={frame}|{scene.render.filepath}")
