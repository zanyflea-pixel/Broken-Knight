import math
import os

import bpy
from mathutils import Vector

ROOT = r"C:\Users\Jimmy\Desktop\Broken Knight"
OUT = os.path.join(ROOT, "blender", "world", "renders")


def look_at(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def material(name, color, roughness=1.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def prepare_scene(camera_location, target, ground_size):
    for obj in list(bpy.context.scene.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.mesh.primitive_plane_add(size=ground_size, location=(0, 0, -0.015))
    bpy.context.object.data.materials.append(material("Preview Ground", (0.12, 0.17, 0.08, 1.0)))
    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.data.lens = 52
    look_at(camera, target)
    bpy.context.scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-4, -8, 12))
    bpy.context.object.data.energy = 1450
    bpy.context.object.data.shape = "DISK"
    bpy.context.object.data.size = 8.0
    look_at(bpy.context.object, target)
    bpy.ops.object.light_add(type="SUN", location=(4, -4, 10))
    bpy.context.object.rotation_euler = (math.radians(28), math.radians(-22), math.radians(28))
    bpy.context.object.data.energy = 2.0
    world = bpy.context.scene.world or bpy.data.worlds.new("Preview World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.045, 0.065, 0.095, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"


def render_stable():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blender", "world", "architecture", "riverwatch_stable.blend"))
    prepare_scene((23.5, -29.0, 16.0), (0, 0, 2.5), 70)
    bpy.context.scene.render.filepath = os.path.join(OUT, "riverwatch_stable_preview.png")
    bpy.ops.render.render(write_still=True)


def render_horse():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blender", "world", "animals", "riverwatch_horse.blend"))
    arm = bpy.data.objects.get("RiverwatchHorseRig")
    trot = bpy.data.actions.get("Trot")
    if arm and trot:
        if not arm.animation_data:
            arm.animation_data_create()
        arm.animation_data.action = trot
        bpy.context.scene.frame_set(8)
    prepare_scene((4.4, -6.8, 3.05), (0, -0.12, 1.02), 20)
    bpy.context.scene.render.filepath = os.path.join(OUT, "riverwatch_horse_preview.png")
    bpy.ops.render.render(write_still=True)


os.makedirs(OUT, exist_ok=True)
render_stable()
render_horse()
print("RIVERWATCH_PREVIEWS|%s" % OUT)
