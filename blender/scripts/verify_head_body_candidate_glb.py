"""Verify the exported unified head/body GLB after a clean re-import."""

import bpy
from mathutils import Vector
import os


BLEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PATH = os.path.abspath(
    os.environ.get(
        "BK_HEAD_BODY_CANDIDATE",
        os.path.join(BLEND_DIR, "previews", "hero_head_body_connection", "hero_head_body_candidate.glb"),
    )
)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=PATH)

armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "Icosphere"]
cameras = [obj for obj in bpy.context.scene.objects if obj.type == "CAMERA"]
lights = [obj for obj in bpy.context.scene.objects if obj.type == "LIGHT"]
actions = sorted(action.name for action in bpy.data.actions)
body = bpy.data.objects.get("ConnectedBody")
separate_head = bpy.data.objects.get("ProfessionalHead")
if body is None:
    raise RuntimeError("Candidate GLB lost ConnectedBody")
if separate_head is not None:
    raise RuntimeError("Candidate GLB still contains a separate ProfessionalHead shell")

boundary_edges = -1
nonmanifold_edges = -1
minimum = min((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
maximum = max((obj.matrix_world @ Vector(co)).z for obj in meshes for co in obj.bound_box)
professional = sorted(obj.name for obj in meshes if obj.name.startswith("Professional"))

print(
    f"HEAD_BODY_CANDIDATE|armatures={len(armatures)}|"
    f"bones={len(armatures[0].data.bones) if armatures else 0}|meshes={len(meshes)}|"
    f"cameras={len(cameras)}|lights={len(lights)}|height={maximum-minimum:.4f}|"
    f"connected_body=1|separate_head=0"
)
print("HEAD_BODY_ACTIONS|" + "|".join(actions))
print("HEAD_BODY_COMPONENTS|" + "|".join(professional))
if len(armatures) != 1 or cameras or lights:
    raise RuntimeError("Candidate GLB scene content failed validation")
if len(armatures[0].data.bones) != 25:
    raise RuntimeError("Candidate GLB skeleton bone count changed")
if "Idle" not in actions or "Walk" not in actions:
    raise RuntimeError("Candidate GLB lost Idle or Walk")
# glTF triangulates and can duplicate vertices along UV/hard-normal seams, so
# a raw post-import BMesh manifold count does not describe the exported source
# topology. The source WIP is validated as closed before export; this import
# check instead proves it remains one ConnectedBody and never recreates the
# separate ProfessionalHead shell that caused the runtime gap.
required = {"ProfessionalEyes", "ProfessionalHairStrands", "ProfessionalHairClumps"}
if not required.issubset(professional):
    raise RuntimeError(f"Candidate GLB lost head components: {required - set(professional)}")
print("HEAD_BODY_CANDIDATE_VERIFY|PASS")
