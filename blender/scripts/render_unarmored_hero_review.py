"""Render fast neutral-pose reviews of the canonical unarmored hero."""

import os

import bpy
from mathutils import Vector


BLEND_DIR = os.path.dirname(os.path.abspath(bpy.data.filepath))
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "unarmored_hero_review")
VISIBLE_COLLECTIONS = {
    "00_RIG",
    "01_HERO_BODY",
    "02_HERO_FACE",
    "03_HERO_HAIR",
    "04_LOINCLOTH",
    "90_PREVIEW",
}


def collection_tree(collection):
    yield collection
    for child in collection.children:
        yield from collection_tree(child)


def aim(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def configure_visibility():
    for collection in collection_tree(bpy.context.scene.collection):
        if collection == bpy.context.scene.collection:
            continue
        collection.hide_render = collection.name not in VISIBLE_COLLECTIONS
    for obj in bpy.data.objects:
        owned = {collection.name for collection in obj.users_collection}
        visible = bool(owned & VISIBLE_COLLECTIONS)
        if obj.type in {"LIGHT", "CAMERA"}:
            visible = True
        obj.hide_render = not visible


def configure_neutral_pose():
    rig = bpy.data.objects.get("HeroRig")
    if rig is None:
        return
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)


def configure_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 520
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.35
    scene.world.color = (0.035, 0.045, 0.060)

    body = bpy.data.objects.get("ConnectedBody")
    if body and os.environ.get("BK_HERO_REVIEW_SUBSURF", "0") != "1":
        # The authored body already has 132k vertices. Disabling its preview
        # subdivision makes review iterations much faster without changing the
        # saved source or hiding the sculpted landmarks under a coarse cage.
        for modifier in body.modifiers:
            if modifier.type == "SUBSURF":
                modifier.show_render = False

    for light in [obj for obj in bpy.data.objects if obj.type == "LIGHT"]:
        bpy.data.objects.remove(light, do_unlink=True)
    lights = [
        ("ReviewKey", (-2.2, -3.3, 3.6), 780.0, 3.0),
        ("ReviewFill", (2.8, -1.6, 2.5), 520.0, 3.0),
        ("ReviewRim", (0.8, 3.0, 3.1), 620.0, 2.4),
    ]
    for name, location, energy, size in lights:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        aim(obj, (0.0, 0.0, 1.05))
        scene.collection.objects.link(obj)


def render_views():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    camera = scene.camera
    if camera is None:
        data = bpy.data.cameras.new("UnarmoredReviewCamera")
        camera = bpy.data.objects.new("UnarmoredReviewCamera", data)
        scene.collection.objects.link(camera)
        scene.camera = camera
    camera.constraints.clear()
    camera.data.type = "PERSP"
    camera.data.sensor_width = 36.0
    camera.data.shift_x = 0.0
    camera.data.shift_y = 0.0
    views = [
        ("front", (0.0, -6.3, 1.05), (0.0, 0.0, 1.02), 78),
        ("threequarter", (4.35, -4.55, 1.18), (0.0, 0.0, 1.03), 80),
        ("side", (6.35, 0.0, 1.10), (0.0, 0.0, 1.03), 82),
        ("back", (0.0, 6.3, 1.05), (0.0, 0.0, 1.02), 78),
        ("face", (0.0, -0.96, 1.755), (0.0, -0.005, 1.745), 88),
        ("face_threequarter", (0.62, -0.72, 1.755), (0.0, -0.005, 1.745), 88),
        ("face_side", (0.92, 0.0, 1.755), (0.0, -0.005, 1.745), 88),
    ]
    requested = {name.strip() for name in os.environ.get("BK_HERO_REVIEW_VIEWS", "").split(",") if name.strip()}
    if requested:
        views = [view for view in views if view[0] in requested]
    for name, location, target, lens in views:
        camera.location = location
        camera.data.lens = lens
        aim(camera, target)
        scene.render.filepath = os.path.join(OUTPUT_DIR, f"hero_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"UNARMORED_REVIEW|{name}|{scene.render.filepath}")


configure_visibility()
configure_neutral_pose()
configure_render()
render_views()
