"""Final broad-volume correction for the strongman pectoral plane."""

import bpy
from math import exp


MARKER = "restore_chest_volume_v2"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        if y < -0.025 and ax < 0.245 and 1.355 < z < 1.550:
            surface = min(1.0, max(0.0, (-y - 0.025) / 0.095))
            upper_plane = gaussian(z, 1.455, 0.085)
            lower_tie = gaussian(z, 1.395, 0.050)
            width = 0.82 + 0.18 * gaussian(ax, 0.105, 0.125)
            vertex.co.y -= surface * width * (0.0075 * upper_plane + 0.0035 * lower_tie)

    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        detail = bpy.data.objects.get(name)
        if detail is None or detail.type != "MESH":
            continue
        world = detail.matrix_world.copy()
        inverse = world.inverted()
        for vertex in detail.data.vertices:
            point = world @ vertex.co
            point.y -= 0.007
            vertex.co = inverse @ point
        detail.data.update()

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("CHEST_VOLUME_V2|broad_upper_ribcage_depth_added")
else:
    print("CHEST_VOLUME_V2|already_applied")
