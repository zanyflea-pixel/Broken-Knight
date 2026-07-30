import os
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PATH = os.path.join(ROOT, "godot", "assets", "hero", "hero_base_body.glb")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=PATH)

armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
# The glTF importer creates an internal Icosphere helper for armature display;
# it is not present in the GLB mesh table and must not affect asset bounds.
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "Icosphere"]
cameras = [obj for obj in bpy.context.scene.objects if obj.type == "CAMERA"]
lights = [obj for obj in bpy.context.scene.objects if obj.type == "LIGHT"]
actions = sorted(action.name for action in bpy.data.actions)
height = 0.0
if meshes:
    minimum = min((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
    maximum = max((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
    height = maximum - minimum
print(f"GLB_VERIFY|armatures={len(armatures)}|meshes={len(meshes)}|cameras={len(cameras)}|lights={len(lights)}|actions={actions}|height={height:.4f}")
for armature in armatures:
    print(f"GLB_ARMATURE|{armature.name}|bones={len(armature.data.bones)}")
for obj in meshes:
    low = min((obj.matrix_world @ Vector(co)).z for co in obj.bound_box)
    high = max((obj.matrix_world @ Vector(co)).z for co in obj.bound_box)
    if low < -0.05 or high > 2.0:
        print(f"GLB_BAD_BOUND|{obj.name}|z=({low:.4f},{high:.4f})|parent={obj.parent.name if obj.parent else None}")
for action in bpy.data.actions:
    print(f"GLB_ACTION|{action.name}|range=({action.frame_range[0]:.1f},{action.frame_range[1]:.1f})")
