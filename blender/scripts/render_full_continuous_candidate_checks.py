"""Render full-body and close connection checks for the rebuild candidate."""

import os

import bpy
from mathutils import Vector


BLEND_DIR = os.path.dirname(os.path.abspath(bpy.data.filepath))
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", os.environ.get("BK_HERO_CANDIDATE_PREVIEW_DIR", "hero_full_continuous_candidate"))


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_visibility():
    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        obj.hide_render = not (
            obj.name == "ConnectedBody"
            or obj.name.startswith((
                "ProfessionalEyes", "ProfessionalIris", "ProfessionalPupil", "ProfessionalBrows",
                "HeroHair", "Loincloth.", "ClothWaistCord",
            ))
        )


def configure_stage():
    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        if obj.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    camera_data = bpy.data.cameras.new("FullContinuousCandidateCamera")
    camera = bpy.data.objects.new("FullContinuousCandidateCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name, location, energy, size, color in (
        ("CandidateKey", (-2.1, -3.4, 3.4), 650.0, 2.7, (1.0, 0.82, 0.72)),
        ("CandidateFill", (2.7, -1.6, 2.5), 360.0, 3.0, (0.72, 0.84, 1.0)),
        ("CandidateRim", (0.7, 3.0, 3.2), 520.0, 2.4, (0.86, 0.93, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        light.location = location
        aim(light, (0.0, 0.0, 1.05))
        scene.collection.objects.link(light)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 600
    scene.render.resolution_y = 780
    scene.render.resolution_percentage = 100
    scene.world.color = (0.018, 0.024, 0.033)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.20
    # Review-only ground reference. It makes false floating/contact poses
    # immediately visible and is never included in the game export.
    ground_mesh = bpy.data.meshes.new("ReviewGround.Mesh")
    ground_mesh.from_pydata(((-3.0, -3.0, 0.0), (3.0, -3.0, 0.0), (3.0, 3.0, 0.0), (-3.0, 3.0, 0.0)), (), ((0, 1, 2, 3),))
    ground_mesh.materials.append(bpy.data.materials.new("ReviewGround.Material"))
    ground_mesh.materials[0].diffuse_color = (0.025, 0.032, 0.042, 1.0)
    ground = bpy.data.objects.new("ReviewGround", ground_mesh)
    scene.collection.objects.link(ground)
    return camera


def render(camera, name, location, target, lens):
    camera.location = location
    camera.data.lens = lens
    aim(camera, target)
    bpy.context.scene.render.filepath = os.path.join(OUTPUT_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print(f"FULL_CONTINUOUS_RENDER|{name}|{bpy.context.scene.render.filepath}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    configure_visibility()
    camera = configure_stage()
    rig = bpy.data.objects["HeroRig"]
    if rig.animation_data is None:
        rig.animation_data_create()
    checks = (
        ("Idle", 31, "idle_front", (0.0, -5.3, 1.05), (0.0, 0.0, 1.00), 76),
        ("Idle", 31, "idle_threequarter", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Idle", 31, "idle_side", (5.3, 0.0, 1.05), (0.0, 0.0, 1.00), 78),
        ("Idle", 31, "idle_back", (0.0, 5.3, 1.05), (0.0, 0.0, 1.00), 76),
        ("Idle", 31, "idle_back_threequarter", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Idle", 31, "idle_face", (0.66, -0.82, 1.74), (0.0, -0.01, 1.70), 92),
        ("Walk", 1, "walk_001_contact", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 7, "walk_007_passing", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 13, "walk_013_contact", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 19, "walk_019_passing", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 1, "walk_rear_001_contact", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 7, "walk_rear_007_passing", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 13, "walk_rear_013_contact", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Walk", 19, "walk_rear_019_passing", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Jump", 8, "jump_008", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Jump", 8, "jump_rear_008", (-3.55, 4.15, 1.10), (0.0, 0.0, 1.00), 78),
        ("Roll", 10, "roll_010", (5.3, 0.0, 1.05), (0.0, 0.0, 0.95), 78),
        ("SwordSlash", 9, "sword_009", (3.55, -4.15, 1.10), (0.0, 0.0, 1.00), 78),
    )
    requested = {
        name.strip() for name in os.environ.get("BK_HERO_CHECKS", "").split(",")
        if name.strip()
    }
    if requested:
        checks = tuple(check for check in checks if check[2] in requested)
        missing = requested - {check[2] for check in checks}
        if missing:
            raise RuntimeError(f"Unknown requested hero checks: {sorted(missing)}")
    for action_name, frame, output, location, target, lens in checks:
        action = bpy.data.actions.get(action_name)
        if action is None:
            raise RuntimeError(f"Required action missing: {action_name}")
        rig.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        render(camera, output, location, target, lens)


if __name__ == "__main__":
    main()
