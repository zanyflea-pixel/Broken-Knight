"""Restore restrained male pectoral volume after an over-flat chest pass."""

import bpy
from math import exp


MARKER = "repair_caved_chest_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if body.get(MARKER):
    print("CHEST_REPAIR|already_applied")
else:
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        if y >= -0.025 or ax >= 0.245 or not 1.360 < z < 1.545:
            continue
        surface = min(1.0, max(0.0, (-y - 0.025) / 0.095))
        height = gaussian(z, 1.455, 0.075)
        lower_blend = gaussian(z, 1.395, 0.045)
        paired_plane = gaussian(ax, 0.105, 0.115)
        broad_slab = 0.45 + 0.55 * paired_plane
        # Advance the whole upper plane slightly, with restrained paired
        # fullness.  Because the displacement is broad and shallow it restores
        # rib-cage volume without recreating two round breast-like lobes.
        vertex.co.y -= surface * (
            0.0095 * height * broad_slab
            + 0.0045 * lower_blend * paired_plane
        )

    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        detail = bpy.data.objects.get(name)
        if detail is None or detail.type != "MESH":
            continue
        world = detail.matrix_world.copy()
        inverse = world.inverted()
        for vertex in detail.data.vertices:
            point = world @ vertex.co
            point.y -= 0.009
            vertex.co = inverse @ point
        detail.data.update()

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("CHEST_REPAIR|flat_pectoral_volume_restored")
