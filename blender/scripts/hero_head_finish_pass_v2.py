"""Second topology-safe face pass: correct mouth, nose profile, brows, and chin."""

from math import exp

import bpy
from mathutils import Vector


MARKER = "hero_head_finish_v2"


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def clamp01(value):
    return max(0.0, min(1.0, value))


def reshape_profile(body):
    world = body.matrix_world.copy()
    inverse = world.inverted()
    for vertex in body.data.vertices:
        point = world @ vertex.co
        x, y, z = point
        ax = abs(x)
        if not (1.605 < z < 1.810 and ax < .115):
            continue
        front = clamp01((-y - .040) / .090)
        if front <= 0.0:
            continue

        # Pull the beak-like first-pass tip back while keeping a clear bridge,
        # then flatten the old inflated lip shelf and project the chin instead.
        nose = bell(ax, 0.0, .020) * bell(z, 1.710, .047)
        mouth = bell(ax, 0.0, .047) * bell(z, 1.677, .020)
        mouth_corner = bell(ax, .035, .015) * bell(z, 1.677, .015)
        chin = bell(ax, 0.0, .043) * bell(z, 1.635, .022)
        mental_crease = bell(ax, 0.0, .037) * bell(z, 1.650, .006)
        point.y += front * (.0100 * nose + .0090 * mouth + .0030 * mouth_corner + .0020 * mental_crease)
        point.y -= front * .0075 * chin

        # Taper the jaw into the chin instead of ending the face in a square.
        lower_face = bell(z, 1.645, .040) * clamp01((ax - .035) / .070)
        point.x *= 1.0 - .035 * lower_face
        vertex.co = inverse @ point

    body.data.update()


def make_material(name, color, roughness):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = color
    material.roughness = roughness
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
    return material


def refine_mouth_material(body):
    slots = {material.name: index for index, material in enumerate(body.data.materials) if material}
    skin_index = slots["Skin"]
    lip_index = slots["LipTone"]
    old_dark_index = slots["Dark"]
    mouth_material = make_material("MouthCrease", (.050, .010, .007, 1.0), .92)
    if body.data.materials.get("MouthCrease") is None:
        body.data.materials.append(mouth_material)
    mouth_index = next(index for index, material in enumerate(body.data.materials) if material == mouth_material)
    world = body.matrix_world
    for polygon in body.data.polygons:
        center = sum((world @ body.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if polygon.material_index == lip_index:
            if abs(center.x) > .0245 or not (1.6720 < center.z < 1.6825):
                polygon.material_index = skin_index
        elif polygon.material_index == old_dark_index:
            if abs(center.x) <= .0220 and 1.6755 < center.z < 1.6795:
                polygon.material_index = mouth_index
            else:
                polygon.material_index = skin_index
    body.data.update()


def move_mesh_world(obj, scale_x=1.0, scale_z=1.0, offset_y=0.0):
    if obj is None or obj.type != "MESH":
        return
    world = obj.matrix_world.copy()
    inverse = world.inverted()
    points = [world @ vertex.co for vertex in obj.data.vertices]
    center = sum(points, Vector()) / len(points)
    for vertex, point in zip(obj.data.vertices, points):
        point.x = center.x + (point.x - center.x) * scale_x
        point.z = center.z + (point.z - center.z) * scale_z
        point.y += offset_y
        vertex.co = inverse @ point
    obj.data.update()


def restore_brows_and_nose_details():
    for side in ("-1", "1"):
        # Expand the corrected brow just enough to span the orbit and place its
        # center 1-2 mm above the skin, not hidden and not floating.
        move_mesh_world(bpy.data.objects.get(f"Brow.{side}"), 1.14, 1.04, -.0053)
        move_mesh_world(bpy.data.objects.get(f"Nostril.{side}"), 1.0, 1.0, .0075)


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_HEAD_FINISH_V2|already_applied")
        return
    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    reshape_profile(body)
    refine_mouth_material(body)
    restore_brows_and_nose_details()
    body[MARKER] = True
    body["hero_head_finish_v2_notes"] = (
        "Reduced beak-like nose and inflated lips; tapered lower jaw; projected chin; "
        "restored seated full brows; tightened lip color and changed the mouth line to a natural dark red crease"
    )
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_HEAD_FINISH_V2|profile_brows_mouth|applied")


main()
