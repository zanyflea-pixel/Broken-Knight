"""Render close, diagnostic views for the current hero hair, brows, and glute/cloth fit."""

import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT = os.path.join(ROOT, "previews", os.environ.get("BK_DETAIL_REVIEW_DIR", "hero_detail_review"))
HIDE_LOINCLOTH = os.environ.get("BK_HIDE_LOINCLOTH", "0") == "1"


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def main():
    os.makedirs(OUTPUT, exist_ok=True)
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        obj.hide_render = not (
            obj.name == "ConnectedBody"
            or obj.name.startswith((
                "ProfessionalEyes", "ProfessionalIris", "ProfessionalPupil", "ProfessionalBrows",
                "HeroHair", *(() if HIDE_LOINCLOTH else ("Loincloth.", "ClothWaistCord")),
            ))
        )
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.world.color = (0.012, 0.015, 0.022)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.18
    camera_data = bpy.data.cameras.new("HeroDetailReview.Camera")
    camera = bpy.data.objects.new("HeroDetailReview.Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name, location, energy, size, color in (
        ("DetailKey", (-2.0, -2.5, 3.1), 620.0, 2.0, (1.0, .82, .70)),
        ("DetailFill", (2.4, -1.3, 2.4), 300.0, 2.3, (.68, .82, 1.0)),
        ("DetailRim", (0.2, 2.4, 2.8), 500.0, 1.8, (.86, .92, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        light.location = location
        aim(light, (0.0, 0.0, 1.25))
        scene.collection.objects.link(light)
    rig = bpy.data.objects["HeroRig"]
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(31)
    checks = (
        ("face_front", (0.0, -1.20, 1.73), (0.0, -0.015, 1.72), 72),
        ("hair_threequarter", (0.72, -0.98, 1.82), (0.0, -0.015, 1.77), 78),
        ("hair_side", (1.10, 0.0, 1.76), (0.0, 0.0, 1.75), 82),
        ("hair_back", (0.0, 1.12, 1.75), (0.0, 0.01, 1.75), 82),
        ("butt_back", (0.0, 1.58, 0.91), (0.0, 0.01, 0.83), 74),
        ("butt_threequarter", (-1.18, 1.18, 0.91), (0.0, 0.01, 0.83), 74),
        ("butt_side", (-1.52, 0.0, 0.91), (0.0, 0.01, 0.83), 74),
    )
    requested = {
        name.strip() for name in os.environ.get("BK_DETAIL_CHECKS", "").split(",")
        if name.strip()
    }
    if requested:
        checks = tuple(check for check in checks if check[0] in requested)
        missing = requested - {check[0] for check in checks}
        if missing:
            raise RuntimeError(f"Unknown requested detail checks: {sorted(missing)}")
    for name, location, target, lens in checks:
        camera.location = location
        camera.data.lens = lens
        aim(camera, target)
        scene.render.filepath = os.path.join(OUTPUT, f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"HERO_DETAIL_REVIEW|{name}|{scene.render.filepath}")


if __name__ == "__main__":
    main()
