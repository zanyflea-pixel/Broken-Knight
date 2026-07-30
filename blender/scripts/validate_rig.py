import bpy

arm = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]
print("RIG_VALIDATION_BEGIN")
print(f"HEIGHT|{body.dimensions.z:.4f}")
print(f"BONES|{len(arm.data.bones)}|" + ",".join(bone.name for bone in arm.data.bones))
print("ACTIONS|" + ",".join(sorted(action.name for action in bpy.data.actions)))
print("EXCLUDED_TYPES|" + ",".join(sorted({obj.type for obj in bpy.context.scene.objects if obj.type in {'CAMERA','LIGHT'}})))
print(f"HAS_FLOOR|{int('Plane' in bpy.data.objects)}")

for obj_name in ("ConnectedBody", "Loincloth.Front", "Loincloth.Back", "BodyHair"):
    obj = bpy.data.objects[obj_name]
    group_names = {group.index: group.name for group in obj.vertex_groups}
    min_sum = 99.0
    max_sum = 0.0
    max_influences = 0
    unweighted = 0
    for vertex in obj.data.vertices:
        weights = [element.weight for element in vertex.groups
                   if group_names.get(element.group) in arm.data.bones]
        total = sum(weights)
        if not weights:
            unweighted += 1
        min_sum = min(min_sum, total)
        max_sum = max(max_sum, total)
        max_influences = max(max_influences, len(weights))
    print(f"WEIGHTS|{obj_name}|unweighted={unweighted}|min={min_sum:.5f}|max={max_sum:.5f}|influences={max_influences}")

# Bone trajectory checks do not need to re-evaluate the dense skinned meshes.
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.hide_viewport = True

for action_name, frames in (("Idle", (1, 25, 49)),
                            ("Walk", (1, 5, 9, 13, 17, 21, 25, 29, 33))):
    arm.animation_data.action = bpy.data.actions[action_name]
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        left = arm.matrix_world @ arm.pose.bones["foot.L"].head
        right = arm.matrix_world @ arm.pose.bones["foot.R"].head
        toe_left = arm.matrix_world @ arm.pose.bones["toe.L"].head
        toe_right = arm.matrix_world @ arm.pose.bones["toe.R"].head
        print(f"POSE|{action_name}|{frame}|ankleL=({left.y:.3f},{left.z:.3f})|ankleR=({right.y:.3f},{right.z:.3f})|toeL=({toe_left.y:.3f},{toe_left.z:.3f})|toeR=({toe_right.y:.3f},{toe_right.z:.3f})")
print("RIG_VALIDATION_END")
