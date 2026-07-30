import importlib.util
import os
import bpy

script_dir=os.path.dirname(__file__)
path=os.path.join(script_dir,"rig_hero_for_godot.py")
spec=importlib.util.spec_from_file_location("hero_rig_builder",path)
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
arm=bpy.data.objects["HeroRig"]
arm.animation_data.action=None
for track in list(arm.animation_data.nla_tracks):
    if track.name=="RollTrack":arm.animation_data.nla_tracks.remove(track)
old=bpy.data.actions.get("Roll")
if old is not None:bpy.data.actions.remove(old)
roll=builder.make_roll(arm)
arm.animation_data.action=None
track=arm.animation_data.nla_tracks.new();track.name="RollTrack"
strip=track.strips.new("Roll",int(roll.frame_range[0]),roll)
strip.action_frame_start=roll.frame_range[0];strip.action_frame_end=roll.frame_range[1];strip.mute=True
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("ROLL_REFRESHED|frames=1-19")
