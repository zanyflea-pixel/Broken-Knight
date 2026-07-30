import bpy
import os
from mathutils import Vector


def point_camera(cam, target):
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    output_dir = os.path.join(project_root, "blender", "preview")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "hero_head_preview.png")
    if os.path.exists(output_path):
        try:
            os.remove(output_path)
        except OSError:
            output_path = os.path.join(output_dir, "hero_head_preview_tmp.png")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = output_path
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100

    cam = scene.camera
    if cam:
        cam.location = (-0.42, -1.76, 1.33)
        point_camera(cam, Vector((0.0, -0.02, 1.29)))
        cam.data.lens = 78

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.75, 0.84, 0.98, 1.0)
        bg.inputs[1].default_value = 0.4

    bpy.ops.render.render(write_still=True)
    print(f"Rendered hero head preview to: {output_path}")


if __name__ == "__main__":
    main()
