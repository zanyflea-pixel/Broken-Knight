"""Print compact SwordSlash metadata for historical checkpoint comparison."""

import bpy


action = bpy.data.actions.get("SwordSlash")
if action is None:
    raise RuntimeError("SwordSlash is missing")

keyed_frames = sorted(
    {
        round(point.co.x, 4)
        for curve in action.fcurves
        for point in curve.keyframe_points
    }
)
print(
    "SWORD_CHECKPOINT|file=%s|frames=%d-%d|curves=%d|keys=%s"
    % (
        bpy.data.filepath,
        action.frame_start,
        action.frame_end,
        len(action.fcurves),
        ",".join(str(value) for value in keyed_frames),
    )
)
