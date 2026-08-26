import os

import bpy


ROOT = r"C:\Users\Jimmy\Desktop\Broken Knight"
BLEND = os.path.join(ROOT, "blender", "world", "animals", "riverwatch_horse.blend")
GLB = os.path.join(ROOT, "godot", "assets", "animals", "riverwatch_horse.glb")


def evaluated_positions(obj, frame):
    bpy.context.scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        return [vertex.co.copy() for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


bpy.ops.wm.open_mainfile(filepath=BLEND)
rig = bpy.data.objects.get("RiverwatchHorseRig")
body = bpy.data.objects.get("RiverwatchHorseProductionBody")
assert rig is not None and rig.type == "ARMATURE", "Production armature missing"
assert body is not None and body.type == "MESH", "Production mesh missing"
assert os.path.exists(GLB) and os.path.getsize(GLB) > 100_000, "Runtime GLB missing"
required_actions = {"Idle", "Walk", "Trot", "Jump"}
assert required_actions.issubset(set(bpy.data.actions.keys())), "Required horse animations missing"
assert len(body.vertex_groups) >= 16, "Horse is not fully grouped"
assert any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in body.modifiers), "Armature modifier missing"
unweighted = [vertex.index for vertex in body.data.vertices if not vertex.groups]
assert not unweighted, "Unweighted production vertices: %d" % len(unweighted)

rig.animation_data.action = bpy.data.actions["Trot"]
start = evaluated_positions(body, 1)
stride = evaluated_positions(body, 9)
assert len(start) == len(stride)
max_deformation = max((a - b).length for a, b in zip(start, stride))
assert max_deformation > 0.08, "Trot does not visibly deform the mesh"

rig.animation_data.action = bpy.data.actions["Walk"]
walk_start = evaluated_positions(body, 1)
walk_stride = evaluated_positions(body, 13)
max_walk_deformation = max((a - b).length for a, b in zip(walk_start, walk_stride))
assert max_walk_deformation > 0.04, "Walk does not visibly deform the mesh"

rig.animation_data.action = bpy.data.actions["Jump"]
jump_start = evaluated_positions(body, 1)
jump_air = evaluated_positions(body, 20)
max_jump_deformation = max((a - b).length for a, b in zip(jump_start, jump_air))
assert max_jump_deformation > 0.08, "Jump does not visibly deform the mesh"

print(
    "HORSE_PRODUCTION_VALID|vertices=%d|groups=%d|max_walk_deformation=%.3f|max_trot_deformation=%.3f|max_jump_deformation=%.3f|animations=Idle,Walk,Trot,Jump|glb_bytes=%d"
    % (
        len(body.data.vertices), len(body.vertex_groups), max_walk_deformation,
        max_deformation, max_jump_deformation, os.path.getsize(GLB),
    )
)
