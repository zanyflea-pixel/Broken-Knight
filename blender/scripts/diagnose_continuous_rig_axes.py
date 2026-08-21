"""Print how the continuous hero's main limb bones respond to local rotations."""

from math import radians
import os

import bpy


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
SOURCE = os.environ.get(
    "BK_RIG_DIAGNOSTIC_BLEND",
    os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master.blend"),
)


def reset(rig):
    rig.animation_data_create()
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def coords(bone):
    return tuple(round(value, 4) for value in (*bone.head, *bone.tail))


def main():
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    rig = bpy.data.objects["HeroRig"]
    for bone_name in ("upper_arm.L", "upper_arm.R", "forearm.L", "thigh.L", "thigh.R", "shin.L", "foot.L"):
        reset(rig)
        bone = rig.pose.bones[bone_name]
        print(f"RIG_AXIS|{bone_name}|rest|{coords(bone)}")
        for axis in range(3):
            for angle in (-25.0, 25.0):
                reset(rig)
                bone = rig.pose.bones[bone_name]
                bone.rotation_euler[axis] = radians(angle)
                bpy.context.view_layer.update()
                print(f"RIG_AXIS|{bone_name}|axis={axis}|angle={angle:+.0f}|{coords(bone)}")


if __name__ == "__main__":
    main()
