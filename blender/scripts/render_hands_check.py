import os
import bpy
from mathutils import Vector


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


blend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
output_dir = os.path.join(blend_dir, "preview", "hands_check")
os.makedirs(output_dir, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.25
camera = scene.camera

for name, location in [
    ("front", (-0.345, -0.70, 0.82)),
    ("threequarter", (-0.82, -0.52, 0.84)),
    ("back", (-0.345, 0.70, 0.82)),
]:
    camera.location = Vector(location)
    camera.data.lens = 85
    point_camera(camera, (-0.345, -0.010, 0.82))
    scene.render.filepath = os.path.join(output_dir, f"hands_{name}.png")
    bpy.ops.render.render(write_still=True)

print(output_dir)
