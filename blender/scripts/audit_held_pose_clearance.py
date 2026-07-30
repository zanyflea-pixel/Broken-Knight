"""Print held-item and arm joint positions for collision-oriented pose tuning."""

import bpy
from mathutils import Vector


arm = bpy.data.objects["HeroRig"]
scene = bpy.context.scene


def world_point(local):
    return arm.matrix_world @ Vector(local)


def bone_points(name):
    bone = arm.pose.bones[name]
    return world_point(bone.head), world_point(bone.tail)


def staff_extremes():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in scene.objects:
        if obj.type != "MESH" or not obj.name.startswith("RoyalStaff_"):
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        points.extend(evaluated.matrix_world @ vertex.co for vertex in mesh.vertices)
        evaluated.to_mesh_clear()
    minimum = min(point.z for point in points)
    maximum = max(point.z for point in points)
    bottom = [point for point in points if point.z <= minimum + .06]
    top = [point for point in points if point.z >= maximum - .06]
    average = lambda values: sum(values, Vector()) / len(values)
    return average(bottom), average(top), minimum, maximum


for action_name, frame in (
    ("WarriorIdle", 1),
    ("StaffIdle", 1),
    ("StaffWalk", 7),
    ("StaffSpark", 7),
):
    arm.animation_data.action = bpy.data.actions[action_name]
    scene.frame_set(frame)
    left_shoulder, left_elbow = bone_points("upper_arm.L")
    _, left_hand = bone_points("forearm.L")
    right_shoulder, right_elbow = bone_points("upper_arm.R")
    _, right_hand = bone_points("forearm.R")
    print(
        "POSE_JOINTS|%s|L_shoulder=%s|L_elbow=%s|L_hand=%s|"
        "R_shoulder=%s|R_elbow=%s|R_hand=%s"
        % (
            action_name,
            tuple(round(value, 4) for value in left_shoulder),
            tuple(round(value, 4) for value in left_elbow),
            tuple(round(value, 4) for value in left_hand),
            tuple(round(value, 4) for value in right_shoulder),
            tuple(round(value, 4) for value in right_elbow),
            tuple(round(value, 4) for value in right_hand),
        )
    )
    if action_name.startswith("Staff"):
        bottom, top, minimum, maximum = staff_extremes()
        print(
            "STAFF_AXIS|%s|bottom=%s|top=%s|min_z=%.4f|max_z=%.4f"
            % (
                action_name,
                tuple(round(value, 4) for value in bottom),
                tuple(round(value, 4) for value in top),
                minimum,
                maximum,
            )
        )
