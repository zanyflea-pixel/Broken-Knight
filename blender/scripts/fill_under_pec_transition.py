"""Fill the hollow beneath the pecs without restoring a pointed chest apex."""

import bpy
from math import exp


MARKER = "fill_under_pec_transition_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    moved = 0
    maximum = 0.0
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        # This band ends below the previously flattened apex.  It restores the
        # missing rib-cage/pec tie-in instead of advancing the chest tip.
        if y < -0.025 and ax < 0.240 and 1.285 < z < 1.425:
            surface = min(1.0, max(0.0, (-y - 0.025) / 0.090))
            height = gaussian(z, 1.365, 0.060)
            width = 0.82 + 0.18 * gaussian(ax, 0.105, 0.125)
            displacement = 0.0125 * surface * height * width
            if displacement > 0.0001:
                vertex.co.y -= displacement
                moved += 1
                maximum = max(maximum, displacement)

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("UNDER_PEC_FILL|vertices=%d|max_move=%.5f" % (moved, maximum))
else:
    print("UNDER_PEC_FILL|already_applied")
