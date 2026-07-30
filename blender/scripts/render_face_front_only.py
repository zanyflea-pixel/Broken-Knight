import os
import bpy
from mathutils import Vector


def aim(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
view = os.environ.get("BK_FACE_VIEW", "front").lower()
views = {
    "front": ("face_front.png", (0.0, -1.35, 1.80)),
    "threequarter": ("face_threequarter.png", (0.78, -1.05, 1.82)),
    "side": ("face_side.png", (1.25, -0.01, 1.80)),
    "rear": ("face_rear.png", (0.0, 1.30, 1.80)),
}
filename, location = views.get(view, views["front"])
out = os.path.join(root, "preview", "face_check", filename)
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
camera.location = Vector(location)
camera.data.lens = 105
aim(camera, (0.0, -0.015, 1.79))
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print(out)
