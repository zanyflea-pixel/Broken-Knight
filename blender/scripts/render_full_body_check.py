import os
import bpy
from mathutils import Vector


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
out = os.path.join(root, "preview", "full_body_check")
os.makedirs(out, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 650
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.55
camera = scene.camera

for name, location in [
    ("front", (0.0, -3.25, 1.00)),
    ("back", (0.0, 3.25, 1.00)),
    ("side", (3.25, 0.0, 1.00)),
    ("threequarter", (2.25, -2.25, 1.05)),
]:
    camera.location = Vector(location)
    camera.data.lens = 72
    point_camera(camera, (0.0, 0.0, 0.95))
    scene.render.filepath = os.path.join(out, f"hero_{name}.png")
    bpy.ops.render.render(write_still=True)

print(out)
