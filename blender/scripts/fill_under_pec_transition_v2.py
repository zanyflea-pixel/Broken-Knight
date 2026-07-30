"""Second stronger fill for the hollow beneath the pectoral shelf."""

import bpy
from math import exp


MARKER = "fill_under_pec_transition_v2"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    moved = 0
    maximum = 0.0
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        if y < -0.020 and ax < 0.250 and 1.265 < z < 1.430:
            surface = min(1.0, max(0.0, (-y - 0.020) / 0.095))
            height = gaussian(z, 1.355, 0.072)
            broad_width = 0.88 + 0.12 * gaussian(ax, 0.105, 0.140)
            displacement = 0.0105 * surface * height * broad_width
            if displacement > 0.0001:
                vertex.co.y -= displacement
                moved += 1
                maximum = max(maximum, displacement)

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("UNDER_PEC_FILL_V2|vertices=%d|max_move=%.5f" % (moved, maximum))
else:
    print("UNDER_PEC_FILL_V2|already_applied")
