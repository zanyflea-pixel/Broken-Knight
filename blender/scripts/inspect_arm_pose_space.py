"""Sample the professional rig arm controls for natural carry poses."""

from math import radians
import bpy


rig = bpy.data.objects["HeroRig"]
rig.animation_data.action = None
for bone in rig.pose.bones:
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = (0.0, 0.0, 0.0)
    bone.location = (0.0, 0.0, 0.0)
    bone.scale = (1.0, 1.0, 1.0)

for side in ("L", "R"):
    print("ARM_SPACE|side=%s" % side)
    for upper_x in (-20, 0, 20):
        for upper_z in (-35, -20, 0, 20, 35):
            for elbow_x in (-55, -30, 0, 30):
                for bone in rig.pose.bones:
                    bone.rotation_euler = (0.0, 0.0, 0.0)
                rig.pose.bones[f"upper_arm.{side}"].rotation_euler = (
                    radians(upper_x), 0.0, radians(upper_z)
                )
                rig.pose.bones[f"forearm.{side}"].rotation_euler = (
                    radians(elbow_x), 0.0, 0.0
                )
                bpy.context.view_layer.update()
                hand = rig.matrix_world @ rig.pose.bones[f"hand.{side}"].head
                if 0.95 <= hand.z <= 1.28 and -0.18 <= hand.y <= 0.06:
                    print(
                        "ARM_OPTION|%d,%d,%d|hand=%.3f,%.3f,%.3f"
                        % (upper_x, upper_z, elbow_x, hand.x, hand.y, hand.z)
                    )
