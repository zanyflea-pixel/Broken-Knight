"""Refresh Idle/Walk on the existing weighted rig without rebuilding weights."""

import importlib.util
import os
import bpy


SCRIPT_DIR = os.path.dirname(__file__)
RIG_SCRIPT = os.path.join(SCRIPT_DIR, "rig_hero_for_godot.py")
spec = importlib.util.spec_from_file_location("hero_rig_builder", RIG_SCRIPT)
rig_builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rig_builder)

arm = bpy.data.objects["HeroRig"]
# Solving an upright staff only needs the armature matrices. Hiding the dense
# skinned meshes during key generation prevents every staff key from
# needlessly reevaluating the full hero and armor, then restores the exact
# viewport visibility before saving.
mesh_visibility = {
    obj.name: (obj.hide_get(), obj.hide_viewport)
    for obj in bpy.context.scene.objects
    if obj.type == "MESH"
}
for obj_name in mesh_visibility:
    obj = bpy.data.objects[obj_name]
    obj.hide_set(True)
    obj.hide_viewport = True
arm.animation_data.action = None
while arm.animation_data.nla_tracks:
    arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
for name in ("Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk", "Jump", "Land", "Roll", "Spark", "Nova", "Blink", "Orb", "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb"):
    action = bpy.data.actions.get(name)
    if action is not None:
        bpy.data.actions.remove(action)

idle = rig_builder.make_idle(arm)
walk = rig_builder.make_walk(arm)
torch_idle = rig_builder.make_torch_idle(arm)
torch_walk = rig_builder.make_torch_walk(arm)
staff_idle = rig_builder.make_staff_idle(arm)
staff_walk = rig_builder.make_staff_walk(arm)
jump = rig_builder.make_jump(arm)
land = rig_builder.make_land(arm)
roll = rig_builder.make_roll(arm)
spark = rig_builder.make_spark(arm)
nova = rig_builder.make_nova(arm)
blink = rig_builder.make_blink(arm)
orb = rig_builder.make_orb(arm)
staff_spark = rig_builder.clone_staff_cast(arm, spark, "StaffSpark")
staff_nova = rig_builder.clone_staff_cast(arm, nova, "StaffNova")
staff_blink = rig_builder.clone_staff_cast(arm, blink, "StaffBlink")
staff_orb = rig_builder.clone_staff_cast(arm, orb, "StaffOrb")
rig_builder.stash_actions(arm, idle, walk, torch_idle, torch_walk, staff_idle, staff_walk, jump, land, roll, spark, nova, blink, orb, staff_spark, staff_nova, staff_blink, staff_orb)
for obj_name, visibility in mesh_visibility.items():
    obj = bpy.data.objects.get(obj_name)
    if obj is not None:
        was_hidden, was_viewport_hidden = visibility
        obj.hide_viewport = was_viewport_hidden
        obj.hide_set(was_hidden)
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("ANIMATIONS_REFRESHED|Idle,Walk,TorchIdle,TorchWalk,StaffIdle,StaffWalk,Jump,Land,Roll,Spark,Nova,Blink,Orb,StaffSpark,StaffNova,StaffBlink,StaffOrb")
