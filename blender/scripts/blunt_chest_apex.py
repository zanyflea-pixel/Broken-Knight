"""Blunt only the pointed front apex of the restored pectoral shape."""

import bpy
from math import exp


MARKER = "blunt_chest_apex_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        # Affect only the foremost few millimeters of the upper pec.  Everything
        # behind this soft depth limit remains exactly where it is.
        if ax < 0.225 and 1.405 < z < 1.525 and y < -0.158:
            height = gaussian(z, 1.465, 0.070)
            width = 0.75 + 0.25 * gaussian(ax, 0.105, 0.120)
            excess = -0.158 - y
            vertex.co.y += excess * 0.62 * height * width

    # Seat the small surface details against the blunter plane.
    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        detail = bpy.data.objects.get(name)
        if detail is None or detail.type != "MESH":
            continue
        world = detail.matrix_world.copy()
        inverse = world.inverted()
        for vertex in detail.data.vertices:
            point = world @ vertex.co
            point.y += 0.0045
            vertex.co = inverse @ point
        detail.data.update()

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("CHEST_APEX|softened_without_volume_loss")
else:
    print("CHEST_APEX|already_applied")
