"""Render close head/neck checks in important existing animation actions."""

import bpy
from mathutils import Vector
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.dirname(os.path.abspath(bpy.data.filepath))
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "hero_head_deformation_checks")


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    rig = bpy.data.objects["HeroRig"]
    has_separate_head = bpy.data.objects.get("ProfessionalHead") is not None
    for obj in scene.objects:
        if obj.type in {"MESH", "CURVE"}:
            keep = obj.name in {
                "ConnectedBody", "BodyHair", "ProfessionalHead",
                "ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R",
                "ProfessionalPupil.L", "ProfessionalPupil.R", "ProfessionalBrows",
                "ProfessionalFaceStubble",
                "ProfessionalHairStrands", "ProfessionalHairClumps",
            }
            obj.hide_render = not keep
    body = bpy.data.objects.get("ConnectedBody")
    if body is not None and not has_separate_head:
        for modifier in body.modifiers:
            if modifier.type == "SUBSURF":
                modifier.show_render = False

    camera_data = bpy.data.cameras.new("DeformationReviewCamera")
    camera = bpy.data.objects.new("DeformationReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.lens = 92
    camera.location = (0.68, -0.96, 1.79)

    for name, location, energy, size, color in (
        ("DeformKey", (-0.56, -0.66, 2.18), 58.0, 0.58, (1.0, 0.82, 0.72)),
        ("DeformFill", (0.62, -0.40, 1.98), 26.0, 0.70, (0.72, 0.84, 1.0)),
        ("DeformRim", (0.25, 0.50, 2.10), 40.0, 0.52, (0.84, 0.92, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        light.location = location
        aim(light, (0.0, 0.01, 1.76))
        scene.collection.objects.link(light)

    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.world.color = (0.020, 0.025, 0.034)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.35

    checks = (
        ("Idle", 25),
        ("Walk", 9),
        ("Jump", 8),
        ("Roll", 10),
        ("SwordSlash", 9),
    )
    for action_name, frame in checks:
        action = bpy.data.actions.get(action_name)
        if action is None:
            raise RuntimeError(f"Required action missing: {action_name}")
        rig.animation_data.action = action
        scene.frame_set(frame)
        head = rig.pose.bones["head"]
        center = rig.matrix_world @ head.head
        aim(camera, center + Vector((0.0, -0.015, 0.075)))
        scene.render.filepath = os.path.join(OUTPUT_DIR, f"{action_name}_{frame:03d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"HEAD_DEFORM_RENDER|{action_name}|{frame}|{scene.render.filepath}")


if __name__ == "__main__":
    main()
