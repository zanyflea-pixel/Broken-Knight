import os
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "preview", "rig_checks")
os.makedirs(OUT, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = (
    "OBJECT" if os.environ.get("RIG_CHECK_OBJECT_COLORS") == "1"
    else os.environ.get("RIG_CHECK_COLOR", "MATERIAL")
)
scene.display.shading.show_shadows = True
scene.render.resolution_x = 240
scene.render.resolution_y = 340
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.45
scene.world.color = (0.025, 0.025, 0.03)

bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
floor = bpy.context.object
floor.name = "RigCheckFloor"
mat = bpy.data.materials.new("RigCheckFloorMat")
mat.diffuse_color = (0.13, 0.14, 0.15, 1)
floor.data.materials.append(mat)

for location, energy, size in [((-3, -4, 4.5), 650, 4.0), ((3, -2, 3), 320, 3.0), ((0, 3, 4), 420, 3.0)]:
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size

bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.lens = 68
scene.camera = camera


def aim(location, target=(0, 0, 0.95)):
    camera.location = Vector(location)
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


arm = bpy.data.objects["HeroRig"]
for obj in bpy.context.scene.objects:
    for modifier in getattr(obj, "modifiers", []):
        if modifier.type == "SUBSURF":
            modifier.levels = 0
            modifier.render_levels = 0
requested_action = os.environ.get("RIG_CHECK_ACTION", "").strip()
if requested_action:
    requested_frames = tuple(
        int(value.strip())
        for value in os.environ.get("RIG_CHECK_FRAMES", "1,4,7,10,13,16,19,22").split(",")
        if value.strip()
    )
    checks = [(requested_action, requested_frames)]
else:
    checks = [
        ("TorchIdle", (1, 25)),
        ("TorchWalk", (4, 10)),
    ]
for action_name, frames in checks:
    arm.animation_data.action = bpy.data.actions[action_name]
    for frame in frames:
        scene.frame_set(frame)
        for view, location in [
            ("side", (-3.4, 0, 1.0)),
            ("threequarter", (-2.6, -2.6, 1.1)),
        ]:
            aim(location)
            scene.render.filepath = os.path.join(OUT, f"{action_name}_{frame:02d}_{view}.png")
            bpy.ops.render.render(write_still=True)
print(OUT)
