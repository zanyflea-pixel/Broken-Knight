"""Render the unarmored hero at the eight authored Walk gait phases."""

import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "previews", os.environ.get("BK_WALK_REVIEW_DIR", "walk_cycle_review"))
os.makedirs(OUT, exist_ok=True)
VISIBLE_COLLECTIONS = {
    "00_RIG", "01_HERO_BODY", "02_HERO_FACE", "03_HERO_HAIR", "04_LOINCLOTH",
}


def collection_tree(collection):
    yield collection
    for child in collection.children:
        yield from collection_tree(child)


for obj in bpy.data.objects:
    if obj.type not in {"MESH", "CURVE", "ARMATURE"}:
        continue
    obj.hide_render = not (
        obj.name == "ConnectedBody"
        or obj.name.startswith((
            "ProfessionalEyes", "ProfessionalIris", "ProfessionalPupil", "ProfessionalBrows",
            "HeroHair", "Loincloth.", "ClothWaistCord",
        ))
    )

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.render.resolution_x = 360
scene.render.resolution_y = 500
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.15
scene.world.color = (0.025, 0.025, 0.030)

for obj in bpy.context.scene.objects:
    for modifier in getattr(obj, "modifiers", []):
        if modifier.type == "SUBSURF":
            modifier.levels = 0
            modifier.render_levels = 0

bpy.ops.mesh.primitive_plane_add(size=7.0, location=(0.0, 0.0, 0.0))
floor = bpy.context.object
floor.name = "WalkReviewFloor"
floor.hide_render = False
floor_mat = bpy.data.materials.new("WalkReviewFloorMat")
floor_mat.diffuse_color = (0.12, 0.13, 0.15, 1.0)
floor.data.materials.append(floor_mat)

bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.lens = 58
scene.camera = camera


def aim(location, target=(0.0, 0.0, 0.97)):
    camera.location = Vector(location)
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


rig = bpy.data.objects["HeroRig"]
rig.animation_data.action = bpy.data.actions[os.environ.get("BK_WALK_REVIEW_ACTION", "Walk")]
frames = tuple(
    int(value.strip())
    for value in os.environ.get("BK_WALK_REVIEW_FRAMES", "1,4,7,10,13,16,19,22").split(",")
    if value.strip()
)
for frame in frames:
    scene.frame_set(frame)
    for view, location in (
        ("side", (-4.8, 0.0, 1.10)),
        ("threequarter", (-3.55, -3.55, 1.18)),
    ):
        aim(location)
        scene.render.filepath = os.path.join(OUT, f"Walk_{frame:02d}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"WALK_REVIEW|{frame}|{view}|{scene.render.filepath}")
