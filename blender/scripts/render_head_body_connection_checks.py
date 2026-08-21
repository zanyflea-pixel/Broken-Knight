"""Focused neutral and animated checks for the unified neck/collar surface."""

import bpy
from mathutils import Vector
import os


BLEND_DIR = os.path.dirname(os.path.abspath(bpy.data.filepath))
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "hero_head_body_connection")


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


os.makedirs(OUTPUT_DIR, exist_ok=True)
scene = bpy.context.scene
rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
for modifier in body.modifiers:
    if modifier.type == "SUBSURF":
        modifier.show_render = False

allowed = {
    "ConnectedBody", "BodyHair", "ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R",
    "ProfessionalPupil.L", "ProfessionalPupil.R", "ProfessionalBrows", "ProfessionalFaceStubble",
    "ProfessionalHairStrands", "ProfessionalHairClumps",
}
for obj in scene.objects:
    if obj.type in {"MESH", "CURVE"}:
        obj.hide_render = obj.name not in allowed

camera_data = bpy.data.cameras.new("HeadBodyConnectionCamera")
camera = bpy.data.objects.new("HeadBodyConnectionCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 84

for name, location, energy, size, color in (
    ("ConnectionKey", (-0.75, -1.05, 2.25), 520.0, 1.0, (1.0, 0.83, 0.74)),
    ("ConnectionFill", (0.80, -0.50, 1.88), 250.0, 1.2, (0.73, 0.84, 1.0)),
    ("ConnectionRim", (0.30, 0.85, 2.15), 390.0, 0.9, (0.86, 0.93, 1.0)),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    light.location = location
    aim(light, (0.0, 0.0, 1.62))
    scene.collection.objects.link(light)

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 620
scene.render.resolution_y = 680
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.world.color = (0.018, 0.023, 0.031)
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.15

checks = (
    ("Idle", 25, "front", (0.0, -1.34, 1.66), (0.0, 0.0, 1.64)),
    ("Idle", 25, "threequarter", (0.86, -1.05, 1.67), (0.0, 0.0, 1.64)),
    ("Idle", 25, "back", (0.0, 1.34, 1.66), (0.0, 0.0, 1.64)),
    ("Walk", 9, "threequarter", (0.86, -1.05, 1.67), (0.0, 0.0, 1.64)),
    ("Jump", 8, "threequarter", (0.86, -1.05, 1.67), (0.0, 0.0, 1.64)),
    ("Roll", 10, "side", (1.25, -0.14, 1.56), (0.0, 0.0, 1.56)),
    ("SwordSlash", 9, "threequarter", (0.86, -1.05, 1.67), (0.0, 0.0, 1.64)),
)
for action_name, frame, view, location, target in checks:
    rig.animation_data.action = bpy.data.actions[action_name]
    scene.frame_set(frame)
    camera.location = location
    aim(camera, target)
    path = os.path.join(OUTPUT_DIR, f"{action_name}_{frame:03d}_{view}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"HEAD_BODY_CONNECTION_RENDER|{action_name}|{frame}|{view}|{path}")

