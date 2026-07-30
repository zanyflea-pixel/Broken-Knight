"""One-time proportion correction for slimmer arms and a male pectoral plane."""

import bpy
from math import exp


MARKER = "arms_pecs_refine_v1"
body = bpy.data.objects["ConnectedBody"]
if body.get(MARKER):
    print("SHAPE_REFINE|already_applied")
else:
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)

        # Slim the arm cylinders around their bone axes. Fade at the shoulder
        # and wrist so the repaired attachments and hands remain unchanged.
        if 0.90 < z < 1.45 and ax > 0.215:
            if z >= 1.145:
                t = min(1.0, max(0.0, (z - 1.145) / 0.31))
                center = 0.334 + (0.215 - 0.334) * t
            else:
                t = min(1.0, max(0.0, (z - 0.90) / 0.245))
                center = 0.345 + (0.334 - 0.345) * t
            shoulder_fade = min(1.0, max(0.0, (1.45 - z) / 0.13))
            wrist_fade = min(1.0, max(0.0, (z - 0.90) / 0.10))
            influence = shoulder_fade * wrist_fade
            radial_scale = 1.0 - 0.17 * influence
            local_x = ax - center
            vertex.co.x = (1.0 if x >= 0 else -1.0) * (center + local_x * radial_scale)
            vertex.co.y = 0.006 + (y - 0.006) * radial_scale

        # Replace the low round breast-like bulge with a broader upper shelf
        # and flatter lower border characteristic of a male pectoral mass.
        if 1.285 < z < 1.555 and ax < 0.235 and y < -0.035:
            center_mask = exp(-((ax - 0.105) / 0.125) ** 2)
            lower_roundness = exp(-((z - 1.345) / 0.075) ** 2) * center_mask
            upper_shelf = exp(-((z - 1.465) / 0.060) ** 2) * center_mask
            lower_edge = exp(-((z - 1.305) / 0.035) ** 2) * center_mask
            vertex.co.y += 0.017 * lower_roundness + 0.008 * lower_edge
            vertex.co.y -= 0.007 * upper_shelf

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("SHAPE_REFINE|arms_slimmed|pecs_reshaped")
