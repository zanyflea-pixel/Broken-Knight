"""Topology-preserving anatomical detail and skin-response pass."""

import bpy
from math import exp


MARKER = "lifelike_anatomy_v1"
body = bpy.data.objects["ConnectedBody"]


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


if not body.get(MARKER):
    for vertex in body.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        side = 1.0 if x >= 0.0 else -1.0

        # Collarbone and shoulder-girdle landmarks.
        if y < -0.020 and 1.455 < z < 1.570 and ax < 0.245:
            clavicle = gaussian(z, 1.515, 0.020) * gaussian(ax, 0.120, 0.085)
            sternum_notch = gaussian(z, 1.535, 0.018) * gaussian(ax, 0.0, 0.022)
            vertex.co.y += 0.0028 * clavicle + 0.0020 * sternum_notch

        if 0.205 < ax < 0.345 and 1.345 < z < 1.525:
            deltoid = gaussian(ax, 0.265, 0.060) * gaussian(z, 1.430, 0.080)
            vertex.co.x += side * 0.0035 * deltoid
            vertex.co.y += (-0.0022 if y < 0.0 else 0.0022) * deltoid

        # Rib, serratus, oblique, navel, and linea-alba transitions.
        if y < -0.018 and ax < 0.190 and 0.975 < z < 1.335:
            serratus = gaussian(ax, 0.145, 0.032) * (
                gaussian(z, 1.295, 0.018)
                + 0.85 * gaussian(z, 1.250, 0.018)
                + 0.65 * gaussian(z, 1.205, 0.019)
            )
            oblique_line_z = 1.205 - 0.55 * max(0.0, ax - 0.085)
            oblique = gaussian(ax, 0.125, 0.045) * gaussian(z, oblique_line_z, 0.020)
            linea = gaussian(ax, 0.0, 0.012) * gaussian(z, 1.150, 0.145)
            navel = gaussian(ax, 0.0, 0.010) * gaussian(z, 1.035, 0.014)
            vertex.co.y -= 0.0018 * serratus
            vertex.co.y += 0.0022 * oblique + 0.0015 * linea + 0.0035 * navel

        # Biceps, triceps, elbow break, and forearm flexor plane.
        if 0.235 < ax < 0.385 and 0.890 < z < 1.405:
            arm_center = 0.330 + 0.020 * gaussian(z, 1.030, 0.140)
            radial = gaussian(ax, arm_center, 0.060)
            biceps = radial * gaussian(z, 1.245, 0.085)
            triceps = radial * gaussian(z, 1.285, 0.100)
            elbow = radial * gaussian(z, 1.105, 0.025)
            forearm = radial * gaussian(z, 0.995, 0.075)
            if y < 0.0:
                vertex.co.y -= 0.0040 * biceps + 0.0025 * forearm
                vertex.co.y += 0.0018 * elbow
            else:
                vertex.co.y += 0.0035 * triceps + 0.0015 * forearm

        # Gluteal shelf and athletic leg landmarks, fading before joints.
        if y > 0.015 and ax < 0.260 and 0.790 < z < 1.010:
            glute = gaussian(ax, 0.120, 0.105) * gaussian(z, 0.900, 0.080)
            glute_fold = gaussian(ax, 0.120, 0.100) * gaussian(z, 0.815, 0.020)
            vertex.co.y += 0.0045 * glute
            vertex.co.y -= 0.0018 * glute_fold

        if 0.040 < ax < 0.270 and 0.500 < z < 0.980:
            quad = gaussian(ax, 0.125, 0.085) * gaussian(z, 0.760, 0.125)
            outer_quad = gaussian(ax, 0.205, 0.055) * gaussian(z, 0.765, 0.115)
            knee = gaussian(ax, 0.120, 0.065) * gaussian(z, 0.565, 0.032)
            upper_knee_break = gaussian(ax, 0.120, 0.075) * gaussian(z, 0.615, 0.020)
            if y < 0.0:
                vertex.co.y -= 0.0042 * quad + 0.0022 * knee
                vertex.co.y += 0.0016 * upper_knee_break
            vertex.co.x += side * 0.0028 * outer_quad

        if 0.045 < ax < 0.205 and 0.230 < z < 0.600:
            calf = gaussian(ax, 0.115, 0.060) * gaussian(z, 0.415, 0.095)
            tibia = gaussian(ax, 0.110, 0.045) * gaussian(z, 0.390, 0.120)
            if y > 0.0:
                vertex.co.y += 0.0045 * calf
            elif y < -0.010:
                vertex.co.y -= 0.0012 * tibia
            vertex.co.x += side * 0.0022 * calf

        # Very restrained facial bone structure: jaw angle and cheek plane.
        if 1.655 < z < 1.825 and ax < 0.145:
            jaw = gaussian(ax, 0.080, 0.040) * gaussian(z, 1.700, 0.045)
            cheek = gaussian(ax, 0.072, 0.035) * gaussian(z, 1.765, 0.040)
            vertex.co.x += side * 0.0018 * jaw
            if y < -0.015:
                vertex.co.y -= 0.0014 * cheek

    skin = bpy.data.materials.get("Skin")
    if skin is not None:
        skin.diffuse_color = (0.64, 0.42, 0.31, 1.0)
        skin.roughness = 0.72
        if skin.use_nodes:
            bsdf = skin.node_tree.nodes.get("Principled BSDF")
            if bsdf is not None:
                bsdf.inputs["Base Color"].default_value = skin.diffuse_color
                bsdf.inputs["Roughness"].default_value = 0.72

    body[MARKER] = True
    body.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("LIFELIKE_PASS|clavicle_shoulders_core_arms_legs_face_skin")
else:
    print("LIFELIKE_PASS|already_applied")
