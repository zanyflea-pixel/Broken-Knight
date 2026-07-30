"""Create a visibly flatter pec front without collapsing chest volume."""

import bpy
from math import exp


MARKER = "flatten_pec_apex_visible_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    moved = 0
    maximum = 0.0
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        if ax < 0.235 and 1.405 < z < 1.525 and y < -0.150:
            height = gaussian(z, 1.465, 0.080)
            edge_fade = min(1.0, max(0.0, (0.235 - ax) / 0.035))
            strength = 0.90 * height * edge_fade
            target = -0.150 - 0.002 * gaussian(ax, 0.105, 0.100)
            displacement = (target - y) * strength
            if displacement > 0.0001:
                vertex.co.y += displacement
                moved += 1
                maximum = max(maximum, displacement)

    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        detail = bpy.data.objects.get(name)
        if detail is None or detail.type != "MESH":
            continue
        world = detail.matrix_world.copy()
        inverse = world.inverted()
        for vertex in detail.data.vertices:
            point = world @ vertex.co
            point.y += 0.007
            vertex.co = inverse @ point
        detail.data.update()

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("VISIBLE_PEC_FLATTEN|vertices=%d|max_move=%.5f" % (moved, maximum))
else:
    print("VISIBLE_PEC_FLATTEN|already_applied")
