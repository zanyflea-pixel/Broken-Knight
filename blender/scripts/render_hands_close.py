import os
import bpy
from mathutils import Vector


def aim(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
out = os.path.join(root, "preview", "hands_close")
os.makedirs(out, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 700
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.45
camera = scene.camera

for name, location, target in [
    ("front", (-0.345, -0.78, 0.900), (-0.345, -0.005, 0.895)),
]:
    camera.location = Vector(location)
    camera.data.lens = 105
    aim(camera, target)
    scene.render.filepath = os.path.join(out, f"hand_{name}.png")
    bpy.ops.render.render(write_still=True)

print(out)
