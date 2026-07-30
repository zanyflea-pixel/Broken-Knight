import os
import bpy
from mathutils import Vector


def aim(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
out = os.path.join(root, "preview", "general_accept")
os.makedirs(out, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 620
scene.render.resolution_y = 780
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.55
camera = scene.camera

all_views = {
    "front": ("front", (0.0, -3.25, 1.00), (0.0, 0.0, 0.95), 72),
    "back": ("back", (0.0, 3.25, 1.00), (0.0, 0.0, 0.95), 72),
    "side": ("side", (3.25, 0.0, 1.00), (0.0, 0.0, 0.95), 72),
    "torso": ("torso", (0.0, -2.00, 1.30), (0.0, -0.02, 1.30), 110),
}
selected = os.environ.get("BK_ACCEPT_VIEW", "front")
views = [all_views[selected]]
for name, location, target, lens in views:
    camera.location = Vector(location)
    camera.data.lens = lens
    aim(camera, target)
    scene.render.filepath = os.path.join(out, f"{name}.png")
    bpy.ops.render.render(write_still=True)

print(out)
