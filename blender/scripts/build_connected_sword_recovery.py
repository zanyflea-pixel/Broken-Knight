"""Build the minimal sword action: extend the right elbow, then retract it."""

import importlib.util
import os

import bpy


SCRIPT_DIR = os.path.dirname(__file__)
spec = importlib.util.spec_from_file_location(
    "hero_rig_builder", os.path.join(SCRIPT_DIR, "rig_hero_for_godot.py")
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

arm = bpy.data.objects["HeroRig"]
arm.animation_data_create()
scene = bpy.context.scene

# The pose bake only needs the armature. Avoid reevaluating every skinned body
# and armor mesh on each dependency-graph update.
viewport_state = {}
for obj in scene.objects:
    if obj != arm and obj.type in {"MESH", "CURVE"}:
        viewport_state[obj.name] = obj.hide_viewport
        obj.hide_viewport = True


idle = bpy.data.actions["WarriorIdle"]
arm.animation_data.action = idle
scene.frame_set(int(idle.frame_range[0]))
bpy.context.view_layer.update()
idle_basis = {bone.name: bone.matrix_basis.copy() for bone in arm.pose.bones}


def key_idle_with_elbow(frame, elbow_extension_degrees=0.0):
    """Key the exact current idle pose, changing only the right elbow bend."""
    scene.frame_set(frame)
    for bone in arm.pose.bones:
        bone.matrix_basis = idle_basis[bone.name].copy()
        bone.rotation_mode = "XYZ"
        if bone.name == "forearm.R":
            rotation = bone.rotation_euler.copy()
            rotation.x += __import__("math").radians(elbow_extension_degrees)
            bone.rotation_euler = rotation
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)

old = bpy.data.actions.get("SwordSlash")
if old is not None:
    bpy.data.actions.remove(old)
action = bpy.data.actions.new("SwordSlash")
arm.animation_data.action = action
key_idle_with_elbow(1)
key_idle_with_elbow(9, 52.0)
key_idle_with_elbow(17)
action.frame_start = 1
action.frame_end = 17
action.use_fake_user = True

all_actions = [
    stored
    for stored in bpy.data.actions
    if stored.name
    in {
        "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
        "Jump", "Land", "Roll", "Death", "Spark", "Nova", "Blink", "Orb",
        "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb", "WarriorIdle",
        "WarriorWalk", "SwordSlash", "ShieldBash", "FishCast",
    }
]
builder.stash_actions(arm, *sorted(all_actions, key=lambda stored: stored.name))
arm.animation_data.action = None
scene.frame_set(1)
for name, was_hidden in viewport_state.items():
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_viewport = was_hidden
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("ELBOW_ONLY_SWORD_ACTION|SwordSlash=1-17|idle,+52deg,idle")
