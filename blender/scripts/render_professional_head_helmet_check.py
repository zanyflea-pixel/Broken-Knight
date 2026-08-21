"""Render a close royal-helmet clearance check for the replacement head."""

import bpy
from mathutils import Vector
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
OUTPUT = os.path.join(BLEND_DIR, "previews", "hero_head_deformation_checks", "Helmet_Clearance.png")


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for obj in bpy.context.scene.objects:
    if obj.type not in {"MESH", "CURVE"}:
        continue
    keep = obj.name in {
        "ConnectedBody", "ProfessionalHead",
        "ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R",
        "ProfessionalPupil.L", "ProfessionalPupil.R", "ProfessionalBrows",
        "ProfessionalFaceStubble",
        "ProfessionalHairStrands", "ProfessionalHairClumps",
        "RoyalArmor_head_ApexUnifiedConnectedHelmet",
    }
    obj.hide_render = not keep

scene = bpy.context.scene
rig = bpy.data.objects["HeroRig"]
rig.animation_data.action = bpy.data.actions.get("Idle")
scene.frame_set(25)
camera_data = bpy.data.cameras.new("HelmetCheckCamera")
camera = bpy.data.objects.new("HelmetCheckCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera.location = (0.74, -1.02, 1.79)
camera.data.lens = 92
aim(camera, (0.0, 0.005, 1.76))
for name, location, energy, size in (
    ("HelmetKey", (-0.56, -0.66, 2.18), 60.0, 0.58),
    ("HelmetFill", (0.64, -0.40, 1.98), 30.0, 0.70),
    ("HelmetRim", (0.25, 0.50, 2.10), 44.0, 0.52),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    light = bpy.data.objects.new(name, data)
    light.location = location
    aim(light, (0.0, 0.01, 1.76))
    scene.collection.objects.link(light)
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 680
scene.render.resolution_y = 740
scene.render.resolution_percentage = 100
scene.world.color = (0.020, 0.025, 0.034)
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.35
scene.render.filepath = OUTPUT
bpy.ops.render.render(write_still=True)
print(f"HEAD_HELMET_RENDER|{OUTPUT}")
