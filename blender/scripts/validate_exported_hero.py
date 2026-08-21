"""Validate a hero GLB through a clean Blender import.

This intentionally runs from an empty file so the result cannot borrow the
source scene's rig, materials, meshes, or actions.
"""

import os

import bpy


path = os.path.abspath(os.environ["BK_VALIDATE_HERO_GLB"])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
armor = [obj for obj in meshes if obj.name.startswith("RoyalArmor_")]
actions = sorted(action.name for action in bpy.data.actions)

required_actions = {"Idle", "Walk"}
missing = sorted(required_actions.difference(actions))
if len(armatures) != 1:
    raise RuntimeError(f"Expected one armature, found {len(armatures)}")
if not any(obj.name.startswith("ConnectedBody") for obj in meshes):
    raise RuntimeError("ConnectedBody missing from imported GLB")
if len(armor) != 6:
    raise RuntimeError(f"Expected six consolidated armor meshes, found {len(armor)}")
if missing:
    raise RuntimeError("Missing required actions: " + ", ".join(missing))

print(
    "HERO_GLB_VALID|"
    f"file={path}|armatures={len(armatures)}|meshes={len(meshes)}|"
    f"armor_meshes={len(armor)}|actions={len(actions)}|"
    f"required={','.join(sorted(required_actions))}"
)
