import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_base_body.glb")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=GLB)
if os.environ.get("RIG_CHECK_OBJECT_COLORS") == "1":
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if obj.name.startswith("ConnectedBody"):
            obj.color = (1.0, 0.05, 0.05, 1.0)
        elif obj.name.startswith("BodyHair"):
            obj.color = (0.05, 0.2, 1.0, 1.0)
        elif obj.name.startswith("Loincloth"):
            obj.color = (0.05, 1.0, 0.15, 1.0)
        else:
            obj.color = (1.0, 0.8, 0.05, 1.0)
# The skeleton is useful for rig inspection but must not appear as geometry in
# pose renders; Workbench can otherwise draw the octahedral bones through skin.
for obj in bpy.context.scene.objects:
    if obj.type == "ARMATURE":
        obj.hide_render = True
        obj.hide_viewport = True
        obj.hide_set(True)
check_script = os.path.join(ROOT, "blender", "scripts", "render_rig_animation_checks.py")
with open(check_script, "r", encoding="utf-8") as handle:
    exec(compile(handle.read(), check_script, "exec"))
