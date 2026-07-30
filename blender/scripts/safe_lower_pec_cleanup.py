"""Conservative lower-pectoral cleanup that preserves original chest volume."""

import bpy
from math import exp


MARKER = "safe_lower_pec_cleanup_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        # Touch only the lower chest.  Upper pectoral volume, sternum, nipples,
        # and the shoulder/chest junction remain exactly as authored.
        if y < -0.035 and ax < 0.235 and 1.275 < z < 1.405:
            surface = min(1.0, max(0.0, (-y - 0.035) / 0.095))
            lower_roundness = gaussian(z, 1.345, 0.052)
            width = 0.65 + 0.35 * gaussian(ax, 0.105, 0.120)
            vertex.co.y += 0.010 * surface * lower_roundness * width

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("SAFE_PEC_CLEANUP|original_upper_chest_preserved")
else:
    print("SAFE_PEC_CLEANUP|already_applied")
