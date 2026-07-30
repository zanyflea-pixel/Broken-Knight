import os
import bpy
from mathutils import Vector


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


blend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
output_dir = os.path.join(blend_dir, "preview", "face_check")
os.makedirs(output_dir, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.35
camera = scene.camera

for name, location in [
    ("front", (0.0, -1.35, 1.80)),
    ("threequarter", (0.78, -1.05, 1.82)),
    ("side", (1.25, -0.01, 1.80)),
]:
    camera.location = Vector(location)
    camera.data.lens = 105
    point_camera(camera, (0.0, -0.015, 1.79))
    scene.render.filepath = os.path.join(output_dir, f"face_{name}.png")
    bpy.ops.render.render(write_still=True)

print(output_dir)
