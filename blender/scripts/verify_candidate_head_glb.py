"""Import and verify the isolated professional-head candidate GLB."""

import bpy
from mathutils import Vector
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PATH = os.path.join(ROOT, "previews", "hero_head_integration_wip", "hero_head_candidate.glb")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=PATH)
armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "Icosphere"]
cameras = [obj for obj in bpy.context.scene.objects if obj.type == "CAMERA"]
lights = [obj for obj in bpy.context.scene.objects if obj.type == "LIGHT"]
actions = sorted(action.name for action in bpy.data.actions)
professional = sorted(obj.name for obj in meshes if obj.name.startswith("Professional"))
minimum = min((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
maximum = max((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
print(f"CANDIDATE_VERIFY|armatures={len(armatures)}|bones={len(armatures[0].data.bones) if armatures else 0}|meshes={len(meshes)}|cameras={len(cameras)}|lights={len(lights)}|height={maximum-minimum:.4f}")
print("CANDIDATE_ACTIONS|" + "|".join(actions))
print("CANDIDATE_PROFESSIONAL|" + "|".join(professional))
if len(armatures) != 1 or cameras or lights:
    raise RuntimeError("Candidate GLB scene content failed validation")
if "Idle" not in actions or "Walk" not in actions:
    raise RuntimeError("Candidate GLB lost Idle or Walk")
required = {"ProfessionalHead", "ProfessionalEyes", "ProfessionalHairStrands"}
if not required.issubset(professional):
    raise RuntimeError(f"Candidate GLB lost professional components: {required-set(professional)}")
print("CANDIDATE_VERIFY_PASS")
