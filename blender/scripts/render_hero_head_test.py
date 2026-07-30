"""Render only the views needed to judge an isolated face pass."""

import bpy
import json
import os
from mathutils import Vector


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_view(scene, camera, path, location, target, lens):
    camera.location = Vector(location)
    camera.data.lens = lens
    point_camera(camera, target)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    blend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    output_dir = os.path.join(blend_dir, "preview", "head_test")
    os.makedirs(output_dir, exist_ok=True)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    if hasattr(scene, "view_settings"):
        scene.view_settings.view_transform = "Standard"
        if hasattr(scene.view_settings, "look"):
            scene.view_settings.look = "None"
        scene.view_settings.exposure = -1.0

    world = scene.world or bpy.data.worlds.new("HeadTestWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.78, 0.82, 0.88, 1.0)
        background.inputs[1].default_value = 0.08

    bpy.ops.object.light_add(type="AREA", location=(1.2, -1.6, 1.8))
    key = bpy.context.active_object
    key.data.energy = 115
    key.data.shape = "DISK"
    key.data.size = 2.0
    bpy.ops.object.light_add(type="AREA", location=(-1.4, -0.9, 1.25))
    fill = bpy.context.active_object
    fill.data.energy = 45
    fill.data.size = 1.8

    camera = scene.camera
    views = [
        ("front", (0.0, -1.18, 1.035), (0.0, -0.02, 1.02), 92),
        ("profile", (1.12, -0.05, 1.035), (0.0, -0.02, 1.02), 92),
        ("threequarter", (0.78, -0.82, 1.07), (0.0, -0.02, 1.02), 96),
    ]
    manifest = {}
    for name, location, target, lens in views:
        path = os.path.join(output_dir, f"head_test_{name}.png")
        render_view(scene, camera, path, location, target, lens)
        manifest[name] = path

    manifest_path = os.path.join(output_dir, "head_test_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2)
    print(f"Head test previews written to: {output_dir}")


if __name__ == "__main__":
    main()
