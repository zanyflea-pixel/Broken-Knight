"""Report whether the source rig contains usable Warrior animation actions."""
import bpy

arm = bpy.data.objects.get("HeroRig")
names = sorted(action.name for action in bpy.data.actions)
tracks = []
if arm and arm.animation_data:
    tracks = sorted(track.name for track in arm.animation_data.nla_tracks)
for name in ("WarriorIdle", "WarriorWalk", "SwordSlash", "ShieldBash"):
    action = bpy.data.actions.get(name)
    slot_info = [(slot.identifier, slot.target_id_type) for slot in action.slots] if action else []
    print(f"WARRIOR_ACTION|{name}|exists={action is not None}|range={tuple(action.frame_range) if action else ()}|slots={slot_info}|users={action.users if action else 0}")
for name in ("Walk", "Roll"):
    action = bpy.data.actions.get(name)
    slot_info = [(slot.identifier, slot.target_id_type) for slot in action.slots] if action else []
    print(f"REFERENCE_ACTION|{name}|slots={slot_info}|users={action.users if action else 0}")
print("SOURCE_ACTIONS|" + ",".join(names))
print("SOURCE_NLA|" + ",".join(tracks))
