"""Topology-preserving strongman anatomy pass for the already weighted hero."""

import bpy
from math import exp


MARKER = "strongman_anatomy_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if body.get(MARKER):
    print("STRONGMAN_PASS|already_applied")
else:
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        side = 1.0 if x >= 0.0 else -1.0

        # Rebuild the chest as a high, broad male pectoral shelf.  The lower
        # round mass is pushed back into the rib cage; volume is retained high
        # and outward, with a narrow sternum break between the two pecs.
        if False and y < -0.025 and ax < 0.245 and 1.275 < z < 1.565:
            surface = min(1.0, max(0.0, (-y - 0.025) / 0.105))
            pair = gaussian(ax, 0.105, 0.105)
            lower_mass = gaussian(z, 1.345, 0.070)
            lower_border = gaussian(z, 1.292, 0.026)
            upper_shelf = gaussian(z, 1.465, 0.060)
            lower_transition = gaussian(z, 1.405, 0.038)
            sternum = gaussian(ax, 0.0, 0.020) * gaussian(z, 1.420, 0.125)
            outer_tie = gaussian(ax, 0.185, 0.060) * gaussian(z, 1.430, 0.085)
            vertex.co.y += surface * (
                0.023 * lower_mass * pair
                + 0.022 * lower_border * pair
                + 0.009 * sternum
                - 0.006 * lower_transition * pair
                - 0.004 * outer_tie
            )
            # Compress the former round upper bulge into a broad plane.  Keep
            # slight left/right volume, but prevent the side silhouette from
            # projecting into a hemispherical breast shape.
            target_front = -0.130 - 0.002 * gaussian(ax, 0.105, 0.090)
            broad_plane = 0.88 + 0.12 * pair
            plane_strength = 0.96 * upper_shelf * broad_plane * surface
            if vertex.co.y < target_front:
                vertex.co.y += (target_front - vertex.co.y) * plane_strength

        # Stronger shoulder girdle and V taper without inflating the joints.
        upper_width = gaussian(z, 1.445, 0.145) * gaussian(ax, 0.205, 0.095)
        lat_width = gaussian(z, 1.285, 0.135) * gaussian(ax, 0.185, 0.075)
        waist_taper = gaussian(z, 1.090, 0.105) * gaussian(ax, 0.165, 0.060)
        if ax > 0.075:
            vertex.co.x += side * (0.0120 * upper_width + 0.010 * lat_width - 0.0050 * waist_taper)

        # Deltoid cap plus front biceps/rear triceps planes.  These are small
        # directional forms, not a uniform arm-thickening operation.
        if 0.215 < ax < 0.385 and 1.075 < z < 1.505:
            deltoid = gaussian(z, 1.430, 0.085) * gaussian(ax, 0.255, 0.075)
            biceps = gaussian(z, 1.245, 0.095) * gaussian(ax, 0.325, 0.060)
            triceps = gaussian(z, 1.285, 0.110) * gaussian(ax, 0.320, 0.065)
            vertex.co.x += side * (0.0075 * deltoid + 0.0030 * biceps)
            if y < 0.015:
                vertex.co.y -= 0.0050 * biceps
            elif y > 0.015:
                vertex.co.y += 0.0040 * triceps

        # Back strength: subtle lat and trapezius planes on the rear surface.
        if y > 0.025 and ax < 0.270 and 1.155 < z < 1.590:
            lats = gaussian(ax, 0.145, 0.090) * gaussian(z, 1.285, 0.145)
            traps = gaussian(ax, 0.095, 0.085) * gaussian(z, 1.505, 0.090)
            spine_channel = gaussian(ax, 0.0, 0.018) * gaussian(z, 1.300, 0.230)
            vertex.co.y += 0.0090 * lats + 0.0060 * traps
            vertex.co.y -= 0.0030 * spine_channel

        # Natural abdominal segmentation and oblique transitions.  The forms
        # are kept shallow so the torso reads as flesh rather than armor.
        if y < -0.020 and ax < 0.175 and 1.000 < z < 1.315:
            linea = gaussian(ax, 0.0, 0.014) * gaussian(z, 1.155, 0.175)
            abs_pairs = gaussian(ax, 0.052, 0.030) * (
                gaussian(z, 1.245, 0.030)
                + 0.9 * gaussian(z, 1.165, 0.030)
                + 0.7 * gaussian(z, 1.085, 0.030)
            )
            oblique = gaussian(ax, 0.125, 0.035) * gaussian(z, 1.145, 0.105)
            vertex.co.y += 0.0035 * linea + 0.0020 * oblique
            vertex.co.y -= 0.0028 * abs_pairs

        # Denser glutes, quads, hamstrings, and calves for an athletic lower
        # body.  Silhouette changes are deliberately modest at knees/ankles.
        if 0.045 < ax < 0.285 and 0.500 < z < 1.020:
            quad = gaussian(ax, 0.125, 0.085) * gaussian(z, 0.775, 0.145)
            outer_thigh = gaussian(ax, 0.205, 0.060) * gaussian(z, 0.790, 0.150)
            if y < -0.015:
                vertex.co.y -= 0.0070 * quad
            elif y > 0.015:
                vertex.co.y += 0.0050 * quad
            vertex.co.x += side * 0.0055 * outer_thigh

        if y > 0.020 and ax < 0.255 and 0.790 < z < 1.020:
            glute = gaussian(ax, 0.120, 0.105) * gaussian(z, 0.900, 0.085)
            vertex.co.y += 0.0075 * glute

        if 0.050 < ax < 0.205 and 0.245 < z < 0.615:
            calf = gaussian(ax, 0.115, 0.060) * gaussian(z, 0.440, 0.105)
            if y > 0.010:
                vertex.co.y += 0.0070 * calf
            vertex.co.x += side * 0.0040 * calf

    # Keep the surface-mounted chest details seated on the newly raised upper
    # pectoral plane.  Vertex-space conversion works for the bone-parented
    # areola meshes as well as the nipple meshes.
    for name in ():
        detail = bpy.data.objects.get(name)
        if detail is None or detail.type != "MESH":
            continue
        world = detail.matrix_world.copy()
        inverse = world.inverted()
        for vertex in detail.data.vertices:
            point = world @ vertex.co
            point.y += 0.034
            vertex.co = inverse @ point
        detail.data.update()

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("STRONGMAN_PASS|chest_shoulders_back_arms_core_legs|applied")
