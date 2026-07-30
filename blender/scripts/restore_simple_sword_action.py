"""Restore the compact pre-connection SwordSlash without changing the hero."""

import os

import bpy


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.environ.get(
    "SWORD_RESTORE_SOURCE",
    os.path.join(
        ROOT,
        "blender",
        "hero_restart_rigged_pre_animation_overhaul_20260726.blend",
    ),
)

arm = bpy.data.objects["HeroRig"]
arm.animation_data_create()
old_action = bpy.data.actions.get("SwordSlash")

with bpy.data.libraries.load(SOURCE, link=False) as (available, requested):
    if "SwordSlash" not in available.actions:
        raise RuntimeError("Source checkpoint does not contain SwordSlash")
    requested.actions = ["SwordSlash"]

restored_action = requested.actions[0]
if restored_action is None:
    raise RuntimeError("Failed to append SwordSlash from source checkpoint")

for track in arm.animation_data.nla_tracks:
    for strip in track.strips:
        if strip.action == old_action or strip.name == "SwordSlash":
            strip.action = restored_action
            strip.name = "SwordSlash"
            track.name = "SwordSlash"

if arm.animation_data.action == old_action:
    arm.animation_data.action = restored_action
if old_action is not None and old_action != restored_action:
    bpy.data.actions.remove(old_action)

restored_action.name = "SwordSlash"
restored_action.use_fake_user = True
restored_action.frame_start = int(round(restored_action.frame_range[0]))
restored_action.frame_end = int(round(restored_action.frame_range[1]))

arm.animation_data.action = None
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print(
    "PRE_CONNECTION_SWORD_RESTORED|source=%s|frames=%d-%d"
    % (SOURCE, restored_action.frame_start, restored_action.frame_end)
)
