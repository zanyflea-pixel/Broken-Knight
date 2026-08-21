"""Final facial cleanup: smooth mouth masks, natural brow arcs, balanced profile."""

from math import exp

import bpy
from mathutils import Vector


MARKER = "hero_head_finish_v3"


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def clamp01(value):
    return max(0.0, min(1.0, value))


def balance_profile(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        if not (1.608 < z < 1.775 and ax < .080):
            continue
        front = clamp01((-y - .040) / .090)
        if front <= 0.0:
            continue
        nose = bell(ax, 0.0, .019) * bell(z, 1.709, .043)
        chin = bell(ax, 0.0, .042) * bell(z, 1.634, .021)
        point.y += front * .0055 * nose
        point.y -= front * .0090 * chin
        vertex.co = inverse @ point
    body.data.update()


def smooth_mouth_mask(body):
    slots = {material.name: index for index, material in enumerate(body.data.materials) if material}
    skin_index = slots["Skin"]
    lip_index = slots["LipTone"]
    mouth_index = slots["MouthCrease"]
    world = body.matrix_world
    for polygon in body.data.polygons:
        center = sum((world @ body.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if polygon.material_index == lip_index:
            lip_ellipse = (center.x / .0240) ** 2 + ((center.z - 1.6772) / .0062) ** 2
            if lip_ellipse > 1.0:
                polygon.material_index = skin_index
        elif polygon.material_index == mouth_index:
            crease_ellipse = (center.x / .0215) ** 2 + ((center.z - 1.6775) / .00165) ** 2
            if crease_ellipse > 1.0:
                polygon.material_index = skin_index
    body.data.update()


def arc_brow(obj):
    if obj is None or obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    points = [world @ vertex.co for vertex in obj.data.vertices]
    center = sum(points, Vector()) / len(points)
    half_span = max(abs(point.x - center.x) for point in points)
    side = 1.0 if center.x > 0.0 else -1.0
    for vertex, point in zip(obj.data.vertices, points):
        # u=-1 at the inner end and +1 at the outer end on both brows.
        u = (abs(point.x) - abs(center.x)) / max(.001, half_span)
        cross = (point.z - center.z) * .34
        arch = .0022 * (1.0 - u * u) + .00045 * u
        point.z = center.z + arch + cross
        # The center remains embedded by roughly a millimeter; only the soft
        # upper surface is visible, so this reads as hair on skin, not a bar.
        point.y -= .0008
        vertex.co = inverse @ point
    obj.data.update()


def move_nostril(obj):
    if obj is None or obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    for vertex in obj.data.vertices:
        point = world @ vertex.co
        point.y += .0050
        vertex.co = inverse @ point
    obj.data.update()


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_HEAD_FINISH_V3|already_applied")
        return
    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    balance_profile(body)
    smooth_mouth_mask(body)
    for side in ("-1", "1"):
        arc_brow(bpy.data.objects.get(f"Brow.{side}"))
        move_nostril(bpy.data.objects.get(f"Nostril.{side}"))
    body[MARKER] = True
    body["hero_head_finish_v3_notes"] = (
        "Elliptical lip and mouth-crease masks, shallow seated brow arches, shorter nose, stronger chin"
    )
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_HEAD_FINISH_V3|mouth_brows_profile|applied")


main()
