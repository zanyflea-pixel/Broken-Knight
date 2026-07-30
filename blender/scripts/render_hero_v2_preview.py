import bpy
import json
import os
from mathutils import Vector


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def main():
    blend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    output_dir = os.path.join(blend_dir, "preview", "hero_v2")
    os.makedirs(output_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.4
    camera = scene.camera
    views = [
        ("front", (0.0, -5.2, 1.05), (0.0, 0.0, 1.04), 72),
        ("side", (4.6, -0.05, 1.08), (0.0, 0.0, 1.04), 72),
        ("threequarter", (3.4, -3.8, 1.16), (0.0, 0.0, 1.06), 76),
        ("back", (0.0, 5.2, 1.05), (0.0, 0.0, 1.04), 72),
        ("face", (0.0, -2.05, 1.88), (0.0, -0.02, 1.88), 105),
    ]
    manifest = {}
    for name, location, target, lens in views:
        camera.location = Vector(location)
        camera.data.lens = lens
        point_camera(camera, target)
        path = os.path.join(output_dir, f"hero_v2_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        manifest[name] = path
    with open(os.path.join(output_dir, "manifest.json"), "w", encoding="utf-8") as file:
        json.dump(manifest, file, indent=2)
    print(f"Rendered hero v2 previews to: {output_dir}")


if __name__ == "__main__":
    main()
