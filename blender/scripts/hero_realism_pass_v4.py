"""Topology-safe realism pass for the canonical rigged Broken Knight hero.

The accepted rig, vertex order, weights, scale, and animation set are preserved.
Anatomical edits move existing ConnectedBody vertices; accepted eyes, brows,
nostrils, hair, and cloth are refined without rebuilding or disconnecting them.
"""

from math import exp, sin, pi

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


MARKER = "hero_realism_v4"


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def clamp01(value):
    return max(0.0, min(1.0, value))


def set_rest_pose(rig):
    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def reshape_connected_body(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        side = 1.0 if x >= 0.0 else -1.0

        # Masculine head: a broader jaw and chin, defined cheek plane, modest
        # brow ridge, and a real nose/mouth profile without inflating the head.
        if 1.615 < z < 1.825 and ax < 0.150:
            point.x *= 0.940
            jaw = bell(z, 1.674, 0.047)
            chin_width = bell(z, 1.635, 0.030)
            cheek_taper = bell(z, 1.725, 0.042)
            point.x *= 1.0 + 0.145 * jaw + 0.105 * chin_width - 0.025 * cheek_taper
            x, y, z = point
            ax = abs(x)
            front = clamp01((-y - 0.045) / 0.060)
            cheekbone = bell(ax, 0.061, 0.028) * bell(z, 1.742, 0.028)
            cheek_hollow = bell(ax, 0.060, 0.030) * bell(z, 1.704, 0.025)
            brow_ridge = bell(ax, 0.038, 0.030) * bell(z, 1.782, 0.017)
            nose_bridge = bell(ax, 0.0, 0.013) * bell(z, 1.733, 0.032)
            nose_tip = bell(ax, 0.0, 0.020) * bell(z, 1.704, 0.014)
            nose_wing = bell(ax, 0.014, 0.010) * bell(z, 1.699, 0.011)
            upper_lip = bell(ax, 0.0, 0.040) * bell(z, 1.672, 0.009)
            lower_lip = bell(ax, 0.0, 0.043) * bell(z, 1.657, 0.010)
            mouth_groove = bell(ax, 0.0, 0.044) * bell(z, 1.664, 0.0045)
            chin = bell(ax, 0.0, 0.050) * bell(z, 1.635, 0.022)
            point.y -= front * (
                0.0045 * cheekbone
                + 0.0035 * brow_ridge
                + 0.0080 * nose_bridge
                + 0.0140 * nose_tip
                + 0.0025 * nose_wing
                + 0.0038 * upper_lip
                + 0.0048 * lower_lip
                + 0.0110 * chin
            )
            point.y += front * (0.0040 * cheek_hollow + 0.0028 * mouth_groove)
            if z < 1.650 and ax < 0.060:
                point.z -= 0.0090 * bell(z, 1.632, 0.023)

        # Short, powerful neck and a continuous trapezius ramp into the delts.
        if 1.515 < z < 1.675 and ax < 0.175:
            neck = bell(z, 1.610, 0.075) * bell(ax, 0.065, 0.090)
            point.x *= 1.0 + 0.105 * neck
            point.y *= 1.0 + 0.070 * neck
        shoulder_shelf = bell(z, 1.490, 0.080) * bell(ax, 0.205, 0.105)
        deltoid = bell(z, 1.420, 0.090) * bell(ax, 0.275, 0.070)
        if ax > 0.105:
            point.x += side * (0.0190 * shoulder_shelf + 0.0150 * deltoid)
            point.z += 0.0140 * shoulder_shelf * clamp01((ax - 0.12) / 0.14)
            point.y += (0.0090 if y > 0.0 else -0.0090) * deltoid

        # Athletic V taper with a broad upper rib cage and an actual waist.
        x, y, z = point
        ax = abs(x)
        if 0.075 < ax < 0.285 and 0.960 < z < 1.480:
            lat = bell(z, 1.300, 0.145) * bell(ax, 0.185, 0.095)
            waist = bell(z, 1.095, 0.100) * bell(ax, 0.160, 0.080)
            point.x += side * (0.0200 * lat - 0.0100 * waist)

        # A high, broad male pectoral shelf. Extreme old peaks are pulled back
        # to a plane, then shallow clavicle/sternum/lower-edge breaks are cut in.
        x, y, z = point
        ax = abs(x)
        front = clamp01((-y - 0.045) / 0.085)
        if front > 0.0 and ax < 0.235 and 1.330 < z < 1.535:
            upper_pec = bell(ax, 0.105, 0.110) * bell(z, 1.455, 0.078)
            sternum = bell(ax, 0.0, 0.017) * bell(z, 1.435, 0.115)
            lower_edge = bell(ax, 0.105, 0.110) * bell(z, 1.350, 0.025)
            clavicle = bell(ax, 0.115, 0.100) * bell(z, 1.515, 0.018)
            point.y -= front * 0.0090 * upper_pec
            point.y += front * (0.0048 * sternum + 0.0040 * lower_edge + 0.0030 * clavicle)
            outer = 0.009 * (ax / 0.235) ** 2
            top = 0.010 * bell(z, 1.525, 0.030)
            bottom = 0.012 * bell(z, 1.338, 0.025)
            front_plane = -0.162 + outer + top + bottom
            if point.y < front_plane:
                point.y = front_plane + 0.08 * (point.y - front_plane)

        # Clear six-pack and obliques carried by flesh, with grooves shallower
        # than the muscle bellies and a small navel depression.
        x, y, z = point
        ax = abs(x)
        front = clamp01((-y - 0.035) / 0.090)
        if front > 0.0 and ax < 0.190 and 1.000 < z < 1.335:
            pairs = bell(ax, 0.048, 0.031)
            rows = bell(z, 1.278, 0.030) + 0.92 * bell(z, 1.190, 0.031) + 0.78 * bell(z, 1.105, 0.034)
            linea = bell(ax, 0.0, 0.011) * bell(z, 1.190, 0.180)
            cross = (bell(z, 1.235, 0.010) + bell(z, 1.148, 0.010)) * bell(ax, 0.0, 0.095)
            oblique = bell(ax, 0.128, 0.038) * bell(z, 1.145, 0.110)
            serratus = bell(ax, 0.155, 0.024) * (
                bell(z, 1.300, 0.017) + 0.8 * bell(z, 1.255, 0.018) + 0.6 * bell(z, 1.212, 0.019)
            )
            navel = bell(ax, 0.0, 0.012) * bell(z, 1.035, 0.014)
            point.y -= front * (0.0105 * pairs * rows + 0.0040 * oblique)
            point.y += front * (0.0052 * linea + 0.0038 * cross + 0.0028 * serratus + 0.0040 * navel)

        # Real arm rhythm: caps and bellies, then a pinched elbow and wrist.
        x, y, z = point
        ax = abs(x)
        if ax > 0.235 and 0.885 < z < 1.465:
            center = 0.333 + 0.010 * bell(z, 1.020, 0.150)
            local_x = ax - center
            upper = bell(z, 1.275, 0.115)
            elbow = bell(z, 1.105, 0.040)
            forearm = bell(z, 0.995, 0.085)
            wrist = bell(z, 0.900, 0.035)
            radial_scale = 1.0 + 0.145 * upper - 0.085 * elbow + 0.090 * forearm - 0.050 * wrist
            point.x = side * (center + local_x * radial_scale)
            point.y = 0.006 + (point.y - 0.006) * radial_scale
            if point.y < 0.006:
                point.y -= 0.0100 * upper + 0.0055 * forearm
            else:
                point.y += 0.0090 * bell(z, 1.310, 0.120) + 0.0040 * forearm

        # Back, glutes, and leg muscle groups with actual joint transitions.
        x, y, z = point
        ax = abs(x)
        back = clamp01((y - 0.030) / 0.080)
        if back > 0.0 and ax < 0.270 and 1.130 < z < 1.585:
            traps = bell(ax, 0.090, 0.085) * bell(z, 1.500, 0.085)
            lats = bell(ax, 0.165, 0.085) * bell(z, 1.300, 0.145)
            spine = bell(ax, 0.0, 0.017) * bell(z, 1.330, 0.225)
            point.y += back * (0.0090 * traps + 0.0090 * lats - 0.0045 * spine)
        if back > 0.0 and ax < 0.255 and 0.785 < z < 1.015:
            glute = bell(ax, 0.105, 0.095) * bell(z, 0.900, 0.082)
            cleft = bell(ax, 0.0, 0.017) * bell(z, 0.910, 0.105)
            fold = bell(ax, 0.105, 0.095) * bell(z, 0.810, 0.018)
            point.y += back * (0.0110 * glute - 0.0070 * cleft - 0.0035 * fold)
        if 0.050 < ax < 0.275 and 0.145 < z < 0.985:
            leg_center = 0.130 * side
            local_x = point.x - leg_center
            thigh = bell(z, 0.765, 0.150)
            knee = bell(z, 0.575, 0.050)
            calf = bell(z, 0.405, 0.105)
            ankle = bell(z, 0.165, 0.050)
            leg_scale = 1.0 + 0.035 * thigh - 0.065 * knee + 0.055 * calf - 0.070 * ankle
            point.x = leg_center + local_x * leg_scale
            if point.y < 0.0:
                point.y -= 0.0080 * thigh + 0.0020 * calf
                point.y += 0.0040 * knee
            else:
                point.y += 0.0070 * thigh + 0.0110 * calf
                point.y -= 0.0030 * knee

        # Final silhouette guardrails. The old mesh contains pointed chest and
        # abdominal peaks; these planes keep muscle definition without spikes.
        x, y, z = point
        ax = abs(x)
        if y < -0.115 and ax < 0.235 and 1.330 < z < 1.535:
            chest_target = (
                -0.153
                + 0.018 * (ax / 0.235) ** 2
                + 0.012 * bell(z, 1.525, 0.030)
                + 0.012 * bell(z, 1.338, 0.025)
            )
            if point.y < chest_target:
                point.y = chest_target + 0.06 * (point.y - chest_target)
        if y < -0.105 and ax < 0.175 and 1.000 < z < 1.330:
            pairs = bell(ax, 0.048, 0.032)
            rows = bell(z, 1.278, 0.035) + 0.9 * bell(z, 1.190, 0.036) + 0.75 * bell(z, 1.105, 0.039)
            abdominal_target = -0.124 - 0.0075 * pairs * rows
            if point.y < abdominal_target:
                point.y = abdominal_target + 0.05 * (point.y - abdominal_target)

        vertex.co = inverse @ point

    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body.data.update()


def install_skin_finish():
    skin = bpy.data.materials.get("Skin")
    if skin is None or not skin.use_nodes:
        return
    skin.diffuse_color = (0.43, 0.25, 0.18, 1.0)
    skin.roughness = 0.78
    nodes = skin.node_tree.nodes
    links = skin.node_tree.links
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    for old in list(nodes):
        if old.name == "HeroSkinComplexion":
            nodes.remove(old)
    incoming = next((link for link in links if link.to_node == bsdf and link.to_socket == bsdf.inputs["Base Color"]), None)
    complexion = nodes.new("ShaderNodeHueSaturation")
    complexion.name = "HeroSkinComplexion"
    complexion.label = "Warm heroic complexion"
    complexion.inputs["Hue"].default_value = 0.50
    complexion.inputs["Saturation"].default_value = 1.12
    complexion.inputs["Value"].default_value = 0.76
    complexion.inputs["Fac"].default_value = 1.0
    if incoming:
        source = incoming.from_socket
        links.remove(incoming)
        links.new(source, complexion.inputs["Color"])
    else:
        complexion.inputs["Color"].default_value = skin.diffuse_color
    links.new(complexion.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.78
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.24


def refine_eye_surfaces():
    for suffix in ("-1", "1"):
        for prefix, sx, sz in (
            ("Eye", 0.96, 0.86),
            ("Iris", 1.08, 1.02),
            ("Pupil", 1.06, 1.02),
            ("UpperLid", 0.96, 0.90),
            ("EyeHighlight", 0.90, 0.90),
        ):
            obj = bpy.data.objects.get(f"{prefix}.{suffix}")
            if obj is None or obj.type != "MESH":
                continue
            world = obj.matrix_world.copy()
            inverse = world.inverted()
            points = [world @ vertex.co for vertex in obj.data.vertices]
            center = sum(points, Vector()) / len(points)
            for vertex, point in zip(obj.data.vertices, points):
                point.x *= 0.940
                point.x = center.x + (point.x - center.x) * sx
                point.z = center.z + (point.z - center.z) * sz
                vertex.co = inverse @ point
            obj.data.update()

    # Keep the accepted eyebrow meshes, but make them read as proper brows and
    # sit closer to the forehead instead of looking like thin floating sticks.
    for suffix in ("-1", "1"):
        obj = bpy.data.objects.get(f"Brow.{suffix}")
        if obj is None or obj.type != "MESH":
            continue
        world = obj.matrix_world.copy()
        inverse = world.inverted()
        points = [world @ vertex.co for vertex in obj.data.vertices]
        center = sum(points, Vector()) / len(points)
        for vertex, point in zip(obj.data.vertices, points):
            point.x *= 0.940
            point.x = center.x + (point.x - center.x) * 1.90
            point.y = center.y + (point.y - center.y) * 0.78
            point.z = center.z + (point.z - center.z) * 2.10
            vertex.co = inverse @ point
        obj.data.update()


def body_surface_tree(body):
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return BVHTree.FromObject(body, depsgraph)


def refit_loincloth(body):
    tree = body_surface_tree(body)
    for name in ("Loincloth.Front", "Loincloth.Back"):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            continue
        front = name.endswith("Front")
        world = obj.matrix_world.copy()
        inverse = world.inverted()
        points = [world @ vertex.co for vertex in obj.data.vertices]
        top = max(point.z for point in points)
        bottom = min(point.z for point in points)
        span = max(0.001, top - bottom)
        for vertex, point in zip(obj.data.vertices, points):
            t = clamp01((top - point.z) / span)
            # The front stays modest; the rear must cover the glutes instead of
            # disappearing inside them like the old jockstrap-shaped panel.
            point.x *= (1.17 - 0.02 * t) if front else (1.38 - 0.10 * t)
            if t > 0.72:
                point.z -= 0.014 * clamp01((t - 0.72) / 0.28)
            if not front:
                hit = tree.ray_cast(Vector((point.x, 0.55, point.z)), Vector((0.0, -1.0, 0.0)), 1.1)
                if hit[0] is not None:
                    point.y = max(point.y, hit[0].y + 0.0060)
            vertex.co = inverse @ point
        obj.data.update()
        for polygon in obj.data.polygons:
            polygon.use_smooth = True

    cloth = bpy.data.materials.get("PlainLoincloth")
    if cloth and cloth.use_nodes:
        cloth.diffuse_color = (0.16, 0.045, 0.018, 1.0)
        cloth.roughness = 0.95
        bsdf = next((node for node in cloth.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Roughness"].default_value = 0.95
            if "Specular IOR Level" in bsdf.inputs:
                bsdf.inputs["Specular IOR Level"].default_value = 0.18
            for link in cloth.node_tree.links:
                if link.to_node == bsdf and link.to_socket == bsdf.inputs["Base Color"] and link.from_node.type == "VALTORGB":
                    link.from_node.color_ramp.elements[0].color = (0.050, 0.008, 0.003, 1.0)
                    link.from_node.color_ramp.elements[-1].color = (0.165, 0.035, 0.012, 1.0)


def darken_hair():
    hair = bpy.data.materials.get("HairBrown")
    if hair is None or not hair.use_nodes:
        return
    hair.diffuse_color = (0.032, 0.009, 0.003, 1.0)
    hair.roughness = 0.88
    bsdf = next((node for node in hair.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 0.88
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.20
        for link in hair.node_tree.links:
            if link.to_node == bsdf and link.to_socket == bsdf.inputs["Base Color"] and link.from_node.type == "VALTORGB":
                link.from_node.color_ramp.elements[0].color = (0.008, 0.0015, 0.0005, 1.0)
                link.from_node.color_ramp.elements[-1].color = (0.045, 0.010, 0.003, 1.0)

    # Match the cap to the narrower head while preserving the accepted hairline.
    hair_object = bpy.data.objects.get("Hair")
    if hair_object and hair_object.type == "MESH":
        world = hair_object.matrix_world.copy()
        inverse = world.inverted()
        for vertex in hair_object.data.vertices:
            point = world @ vertex.co
            point.x *= 0.940
            vertex.co = inverse @ point
        hair_object.data.update()


def remove_floating_chest_details():
    # These legacy meshes sit centimeters in front of the torso and create the
    # pointed side silhouette. They are removed; the skin shader already has
    # restrained chest color variation and the body remains one clean surface.
    for name in ("Areola.L", "Areola.R", "Nipple.L", "Nipple.R"):
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_REALISM_PASS|already_applied")
        return

    set_rest_pose(rig)
    reshape_connected_body(body)
    refine_eye_surfaces()
    remove_floating_chest_details()
    install_skin_finish()
    darken_hair()
    refit_loincloth(body)

    body[MARKER] = True
    body["hero_visual_rating_internal"] = 58
    body["hero_visual_pass_notes"] = (
        "Masculine head, integrated facial/chest details, athletic anatomy, "
        "warm matte skin, stronger limbs, and body-fitted loincloth"
    )
    rig.data.pose_position = "POSE"
    if rig.animation_data:
        rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_REALISM_PASS|head_body_surface_details_loincloth|applied")


main()
