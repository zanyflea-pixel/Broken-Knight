"""Render isolated integrated-hair layers for visual fault isolation."""

import bpy
from mathutils import Vector
import os


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "previews", "hero_head_component_diagnostics")


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


scene = bpy.context.scene
os.makedirs(OUT, exist_ok=True)
rig = bpy.data.objects["HeroRig"]
rig.data.pose_position = "REST"
base_allowed = {
    "ConnectedBody", "ProfessionalHead", "ProfessionalEyes",
    "ProfessionalIris.L", "ProfessionalIris.R", "ProfessionalPupil.L",
    "ProfessionalPupil.R", "ProfessionalBrows", "ProfessionalFaceStubble",
}
hair_names = {"ProfessionalHairScalp", "ProfessionalHairStrands", "ProfessionalHairClumps"}

camera_data = bpy.data.cameras.new("HairDiagnosticCamera")
camera = bpy.data.objects.new("HairDiagnosticCamera", camera_data)
scene.collection.objects.link(camera)
camera.location = (0.0, -1.22, 1.77)
camera.data.lens = 92
aim(camera, (0.0, 0.010, 1.76))
scene.camera = camera
for name, location, energy, size in (
    ("DiagKey", (-0.58, -0.68, 2.20), 58.0, 0.58),
    ("DiagFill", (0.66, -0.42, 1.98), 28.0, 0.72),
    ("DiagRim", (0.26, 0.52, 2.12), 42.0, 0.52),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    light = bpy.data.objects.new(name, data)
    light.location = location
    aim(light, (0.0, 0.015, 1.76))
    scene.collection.objects.link(light)

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 480
scene.render.resolution_y = 520
scene.render.resolution_percentage = 100
scene.world.color = (0.020, 0.025, 0.034)
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.35

variants = {
    "scalp_only": {"ProfessionalHairScalp"},
    "scalp_strands": {"ProfessionalHairScalp", "ProfessionalHairStrands"},
    "strands_clumps_no_scalp": {"ProfessionalHairStrands", "ProfessionalHairClumps"},
    "all_hair": hair_names,
}
for label, enabled_hair in variants.items():
    allowed = base_allowed | enabled_hair
    for obj in scene.objects:
        if obj.type in {"MESH", "CURVE"}:
            obj.hide_render = obj.name not in allowed
    scene.render.filepath = os.path.join(OUT, label + ".png")
    bpy.ops.render.render(write_still=True)
    print(f"HEAD_COMPONENT_DIAGNOSTIC|{label}|{scene.render.filepath}")
