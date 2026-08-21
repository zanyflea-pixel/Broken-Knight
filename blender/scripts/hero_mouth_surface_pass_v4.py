"""Replace pixelated face-material lips with shallow, weighted facial surfaces."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


MARKER = "hero_mouth_surface_v4"


def remove_old(name):
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)


def skin_only_mouth_region(body):
    slots = {material.name: index for index, material in enumerate(body.data.materials) if material}
    skin_index = slots["Skin"]
    colored = {slots.get("LipTone"), slots.get("Dark"), slots.get("MouthCrease")}
    colored.discard(None)
    for polygon in body.data.polygons:
        if polygon.material_index in colored:
            polygon.material_index = skin_index
    body.data.update()


def body_surface_tree(body):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return BVHTree.FromObject(body, depsgraph)


def surface_y(tree, x, z):
    hit, _normal, _index, _distance = tree.ray_cast(Vector((x, -.260, z)), Vector((0.0, 1.0, 0.0)), .50)
    if hit is None:
        raise RuntimeError(f"Could not locate face surface at x={x:.4f}, z={z:.4f}")
    return hit.y


def weighted_mesh(name, vertices, faces, material, rig):
    mesh = bpy.data.meshes.new(f"{name}.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj.parent = rig
    group = obj.vertex_groups.new(name="head")
    group.add(list(range(len(vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("HeroRig", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    bevel = obj.modifiers.new("IntegratedLipEdge", "BEVEL")
    bevel.width = .00035
    bevel.segments = 2
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def build_mouth_surfaces(body, rig):
    for name in ("MouthUpperSurface", "MouthLowerSurface", "MouthCreaseSurface"):
        remove_old(name)
    tree = body_surface_tree(body)
    xs = (-.0240, -.0180, -.0100, 0.0, .0100, .0180, .0240)

    seam_z = []
    upper_z = []
    lower_z = []
    for x in xs:
        u = abs(x) / .0240
        seam = 1.6772 - .00055 * (u ** 1.4)
        fullness = max(0.0, 1.0 - u ** 1.55)
        seam_z.append(seam)
        upper_z.append(seam + .00035 + .0038 * fullness)
        lower_z.append(seam - .00035 - .0037 * fullness)

    def lip_vertices(other_z):
        vertices = []
        for x, seam, outside in zip(xs, seam_z, other_z):
            u = abs(x) / .0240
            offset = .00015 + .00070 * max(0.0, 1.0 - u)
            vertices.append((x, surface_y(tree, x, seam) - offset, seam))
            vertices.append((x, surface_y(tree, x, outside) - offset, outside))
        return vertices

    upper_vertices = lip_vertices(upper_z)
    lower_vertices = lip_vertices(lower_z)
    upper_faces = [(2 * index, 2 * index + 2, 2 * index + 3, 2 * index + 1) for index in range(len(xs) - 1)]
    # Reverse the lower strip winding so its visible face also points forward.
    lower_faces = [(2 * index + 1, 2 * index + 3, 2 * index + 2, 2 * index) for index in range(len(xs) - 1)]

    lip_material = bpy.data.materials.get("LipTone")
    mouth_material = bpy.data.materials.get("MouthCrease")
    weighted_mesh("MouthUpperSurface", upper_vertices, upper_faces, lip_material, rig)
    weighted_mesh("MouthLowerSurface", lower_vertices, lower_faces, lip_material, rig)

    crease_vertices = []
    for x, seam in zip(xs, seam_z):
        u = abs(x) / .0240
        half_height = .00018 + .00040 * max(0.0, 1.0 - u ** 1.5)
        offset = .00085
        crease_vertices.append((x, surface_y(tree, x, seam - half_height) - offset, seam - half_height))
        crease_vertices.append((x, surface_y(tree, x, seam + half_height) - offset, seam + half_height))
    crease_faces = [(2 * index, 2 * index + 2, 2 * index + 3, 2 * index + 1) for index in range(len(xs) - 1)]
    weighted_mesh("MouthCreaseSurface", crease_vertices, crease_faces, mouth_material, rig)


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("ConnectedBody or HeroRig is missing")
    if body.get(MARKER):
        print("HERO_MOUTH_SURFACE_V4|already_applied")
        return
    if rig.animation_data:
        rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    skin_only_mouth_region(body)
    build_mouth_surfaces(body, rig)
    body[MARKER] = True
    body["hero_mouth_surface_v4_notes"] = (
        "Removed pixelated polygon lip masks; added shallow face-conforming upper lip, lower lip, and mouth crease; "
        "all three surfaces intersect the face and carry full head-bone weights"
    )
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("HERO_MOUTH_SURFACE_V4|weighted_conforming_lips|applied")


main()
