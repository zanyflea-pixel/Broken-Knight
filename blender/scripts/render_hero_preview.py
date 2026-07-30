import bpy
import json
import os
from mathutils import Vector

FAST_LOOP = os.environ.get("BK_HERO_FAST_LOOP", "1") == "1"


def point_camera(cam, target):
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_view(scene, cam, output_path, location, target, lens):
    cam.location = Vector(location)
    cam.data.lens = lens
    point_camera(cam, Vector(target))
    scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    print(f"Rendered view to: {output_path}")


def main():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    output_dir = os.path.join(project_root, "blender", "preview")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "hero_preview.png")
    output_side_path = os.path.join(output_dir, "hero_preview_side.png")
    output_three_path = os.path.join(output_dir, "hero_preview_threequarter.png")
    output_face_path = os.path.join(output_dir, "hero_preview_face.png")
    output_torso_path = os.path.join(output_dir, "hero_preview_torso.png")
    manifest_path = os.path.join(output_dir, "hero_preview_manifest.json")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = output_path
    scene.render.resolution_x = 900 if FAST_LOOP else 1400
    scene.render.resolution_y = 900 if FAST_LOOP else 1400
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    if hasattr(scene, "view_settings"):
        scene.view_settings.view_transform = "Standard"
        if hasattr(scene.view_settings, "look"):
            scene.view_settings.look = "None"
        scene.view_settings.exposure = -1.2
        scene.view_settings.gamma = 1.0
    if hasattr(scene.eevee, "use_gtao"):
        scene.eevee.use_gtao = True
    if hasattr(scene.eevee, "gtao_factor"):
        scene.eevee.gtao_factor = 1.5
    if hasattr(scene.eevee, "use_bloom"):
        scene.eevee.use_bloom = False

    cam = scene.camera

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.78, 0.82, 0.88, 1.0)
        bg.inputs[1].default_value = 0.06

    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.data.type == "SUN":
            obj.data.energy = 0.22

    if "PreviewKey" not in bpy.data.objects:
        bpy.ops.object.light_add(type="AREA", location=(1.6, -2.2, 2.5))
        key = bpy.context.active_object
        key.name = "PreviewKey"
        key.data.energy = 160
        key.data.shape = "RECTANGLE"
        key.data.size = 3.0
        key.data.size_y = 3.0

    if "PreviewFill" not in bpy.data.objects:
        bpy.ops.object.light_add(type="AREA", location=(-2.2, -1.4, 1.8))
        fill = bpy.context.active_object
        fill.name = "PreviewFill"
        fill.data.energy = 65
        fill.data.shape = "RECTANGLE"
        fill.data.size = 2.8
        fill.data.size_y = 2.8

    if cam:
        if FAST_LOOP:
            views = [
                ("face", output_face_path, (0.0, -1.65, 1.20), (0.0, -0.06, 1.10), 105),
                ("side", output_side_path, (3.25, -0.35, 1.02), (0.0, -0.02, 1.08), 88),
            ]
        else:
            views = [
                ("front", output_path, (-1.75, -3.55, 0.55), (0.0, 0.03, 0.46), 65),
                ("side", output_side_path, (3.25, -0.35, 0.72), (0.0, 0.03, 0.50), 65),
                ("threequarter", output_three_path, (2.25, -2.55, 0.78), (0.0, 0.02, 0.54), 70),
                ("face", output_face_path, (0.0, -1.65, 1.20), (0.0, -0.06, 1.10), 105),
                ("torso", output_torso_path, (-0.95, -2.10, 0.62), (0.0, 0.02, 0.55), 95),
            ]
        manifest = {"blend_file": bpy.data.filepath, "views": []}
        for label, path, location, target, lens in views:
            render_view(scene, cam, path, location, target, lens)
            manifest["views"].append(
                {
                    "label": label,
                    "path": path,
                    "location": [round(float(v), 4) for v in location],
                    "target": [round(float(v), 4) for v in target],
                    "lens": lens,
                }
            )
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
        print(f"Wrote preview manifest to: {manifest_path}")


if __name__ == "__main__":
    main()
