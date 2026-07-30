"""Deterministic structural audit for every exported hero action."""

import math

import bpy


REQUIRED = (
    "Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk",
    "Jump", "Land", "Roll", "Death",
    "Spark", "Nova", "Blink", "Orb",
    "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb",
    "WarriorIdle", "WarriorWalk", "SwordSlash", "ShieldBash",
    "FishCast",
)
LOOPS = (
    "Idle", "Walk", "TorchIdle", "TorchWalk",
    "StaffIdle", "StaffWalk", "WarriorIdle", "WarriorWalk",
)

scene = bpy.context.scene
arm = bpy.data.objects["HeroRig"]
# This audit reads armature transforms only. Exclude dense skinned geometry
# from dependency-graph evaluation so every sampled frame remains inexpensive.
for obj in scene.objects:
    if obj.type == "MESH":
        obj.hide_viewport = True
missing = [name for name in REQUIRED if bpy.data.actions.get(name) is None]
if missing:
    raise RuntimeError("Missing actions: " + ",".join(missing))

print("HERO_ANIMATION_AUDIT_BEGIN")
for name in REQUIRED:
    action = bpy.data.actions[name]
    start, end = int(action.frame_range[0]), int(action.frame_range[1])
    arm.animation_data.action = action
    finite = True
    for frame in sorted({start, (start + end) // 2, end}):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        for bone in arm.pose.bones:
            finite = finite and all(math.isfinite(value) for row in bone.matrix for value in row)
    print(f"ACTION|{name}|frames={start}-{end}|duration={(end-start)/24.0:.3f}|finite={finite}")

for name in LOOPS:
    action = bpy.data.actions[name]
    start, end = int(action.frame_range[0]), int(action.frame_range[1])
    arm.animation_data.action = action
    scene.frame_set(start)
    bpy.context.view_layer.update()
    first = {bone.name: bone.matrix.copy() for bone in arm.pose.bones}
    scene.frame_set(end)
    bpy.context.view_layer.update()
    delta = max(
        max(abs(first[bone.name][row][col] - bone.matrix[row][col])
            for row in range(4) for col in range(4))
        for bone in arm.pose.bones
    )
    print(f"LOOP|{name}|endpoint_delta={delta:.7f}")

for name, frames in (
    ("Walk", (1, 4, 7, 10, 13, 16, 19, 22, 25)),
    ("WarriorWalk", (1, 4, 7, 10, 13, 16, 19, 22, 25)),
):
    arm.animation_data.action = bpy.data.actions[name]
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        left = arm.matrix_world @ arm.pose.bones["foot.L"].head
        right = arm.matrix_world @ arm.pose.bones["foot.R"].head
        root = arm.pose.bones["root"]
        print(
            f"GAIT|{name}|frame={frame}|"
            f"ankle_z={left.z:.4f},{right.z:.4f}|"
            f"ankle_forward={left.y:.4f},{right.y:.4f}|"
            f"root_forward={root.location.z:.6f}"
        )

for name, frames in (
    ("WarriorIdle", (1, 25, 49, 73)),
    ("SwordSlash", (1, 4, 8)),
    ("ShieldBash", (1, 4, 6, 8, 11, 16, 19)),
    ("FishCast", (1, 4, 7, 10, 14, 20)),
):
    arm.animation_data.action = bpy.data.actions[name]
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        values = {}
        for side in ("L", "R"):
            shoulder = arm.matrix_world @ arm.pose.bones[f"upper_arm.{side}"].head
            elbow = arm.matrix_world @ arm.pose.bones[f"forearm.{side}"].head
            hand = arm.matrix_world @ arm.pose.bones[f"hand.{side}"].head
            values[side] = (shoulder.x, elbow.x, hand.x)
        print(
            f"GUARD|{name}|frame={frame}|"
            f"L={values['L'][0]:.4f},{values['L'][1]:.4f},{values['L'][2]:.4f}|"
            f"R={values['R'][0]:.4f},{values['R'][1]:.4f},{values['R'][2]:.4f}"
        )

print("HERO_ANIMATION_AUDIT_END")
