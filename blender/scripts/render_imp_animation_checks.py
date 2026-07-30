"""Render focused imp animation poses from the authored Blender file."""
import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "previews", "imp_checks")
os.makedirs(OUT, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 360
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"

for name in ("PreviewFloor", "PreviewCamera", "Area", "Area.001", "Area.002"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = False
scene.camera = bpy.data.objects.get("PreviewCamera")
arm = bpy.data.objects["ImpRig"]

for clip, frame in (("Idle",18),("Run",4),("Run",10),("Attack",9),("Hit",3),("Death",17)):
    arm.animation_data.action = bpy.data.actions[clip]
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(OUT, "%s_%02d.png" % (clip, frame))
    bpy.ops.render.render(write_still=True)
    print("IMP_RENDER|%s|%d|%s" % (clip, frame, scene.render.filepath))
