"""Fit the royal harness to the locked hero with body-derived weighted shells.

The accepted body is immutable.  The older armor's rigid limb parts were built
around a different rest pose and left exposed skin, ring cuffs and separated
plates.  This pass replaces them with overlapping shells copied from the
accepted body's own surface and weights.  The shells therefore fit the current
anatomy and follow every revised animation without independent drift.
"""

from hashlib import sha256
from math import exp
import struct

import bpy


rig = bpy.data.objects["HeroRig"]
body = bpy.data.objects["ConnectedBody"]


def geometry_digest(mesh):
    digest = sha256()
    digest.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for vertex in mesh.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


BODY_BEFORE = geometry_digest(body.data)


def material(name):
    result = bpy.data.materials.get(name)
    if result is None:
        raise RuntimeError("Missing armor material: " + name)
    return result


COBALT = material("Royal Cobalt Filigree Plate")
BRASS = material("Royal Gilt Brass")
DARK = material("Royal Blackened Steel")
MAIL = material("Riveted Mail")
MATERIALS = (COBALT, BRASS, DARK, MAIL)


def collection_for(slot):
    return bpy.data.collections[{
        "shoulders": "10C_ARMOR_SHOULDERS",
        "hands": "10D_ARMOR_HANDS",
        "pants": "10E_ARMOR_PANTS",
        "feet": "10F_ARMOR_FEET",
    }[slot]]


def remove_old_extremities():
    keep_shoulder = (
        "ApexGrandPauldron", "ApexImprovedPauldron",
        "ApexUnifiedShoulderSkirt", "ApexSpaulderLame",
    )
    keep_pants = ("ApexHarnessBelt", "ApexRoyalBuckle")
    for obj in list(bpy.data.objects):
        if not obj.name.startswith("RoyalArmor_"):
            continue
        if obj.name.startswith("RoyalArmor_shoulders_"):
            if not any(token in obj.name for token in keep_shoulder):
                bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.name.startswith("RoyalArmor_hands_"):
            bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.name.startswith("RoyalArmor_pants_"):
            if not any(token in obj.name for token in keep_pants):
                bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.name.startswith("RoyalArmor_feet_"):
            bpy.data.objects.remove(obj, do_unlink=True)


def group_indices(names):
    return {
        body.vertex_groups[name].index for name in names
        if body.vertex_groups.get(name) is not None
    }


def vertex_weight(vertex, indices):
    return sum(assignment.weight for assignment in vertex.groups if assignment.group in indices)


def source_assignment_map(vertex):
    return {
        body.vertex_groups[assignment.group].name: assignment.weight
        for assignment in vertex.groups
        if assignment.weight > 0.0001
        and assignment.group < len(body.vertex_groups)
        and body.vertex_groups[assignment.group].name in rig.data.bones
    }


def create_fitted_shell(slot, part, influence_names, threshold, offset, zone):
    """Copy influenced body faces, offset them, and preserve all source weights."""
    name = "RoyalArmor_%s_%s" % (slot, part)
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)

    influence = group_indices(influence_names)
    selected = []
    for polygon in body.data.polygons:
        average = sum(vertex_weight(body.data.vertices[index], influence) for index in polygon.vertices) / len(polygon.vertices)
        if average >= threshold:
            selected.append(polygon)
    if not selected:
        raise RuntimeError("No body faces selected for " + name)

    used = sorted({index for polygon in selected for index in polygon.vertices})
    remap = {source: target for target, source in enumerate(used)}
    vertices = []
    for source_index in used:
        source = body.data.vertices[source_index]
        vertices.append(tuple(source.co + source.normal.normalized() * offset))
    faces = [tuple(remap[index] for index in polygon.vertices) for polygon in selected]

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    for mat in MATERIALS:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection_for(slot).objects.link(obj)
    obj.parent = rig
    obj["bk_editable"] = True
    obj["bk_edit_group"] = slot
    obj["bk_visual_pass"] = "LockedBodySovereignWeightedShell20260813"
    obj["bk_edit_note"] = "Body-derived overlapping shell; retains accepted hero weights"

    groups = {}
    for target_index, source_index in enumerate(used):
        for group_name, weight in source_assignment_map(body.data.vertices[source_index]).items():
            group = groups.get(group_name)
            if group is None:
                group = obj.vertex_groups.new(name=group_name)
                groups[group_name] = group
            group.add((target_index,), weight, "REPLACE")

    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = rig
    solidify = obj.modifiers.new("ForgedThickness", "SOLIDIFY")
    solidify.thickness = 0.0045
    solidify.offset = -1.0
    solidify.material_offset_rim = 2
    bevel = obj.modifiers.new("RolledEdges", "BEVEL")
    bevel.width = 0.0017
    bevel.segments = 2

    # Detail is integrated into the same shell by material zoning.  There are
    # no freestanding rings, stripes, bosses or trim pieces.
    for target_polygon, source_polygon in zip(mesh.polygons, selected):
        target_polygon.use_smooth = True
        center = source_polygon.center
        weights = {
            key: sum(vertex_weight(body.data.vertices[index], group_indices(names)) for index in source_polygon.vertices) / len(source_polygon.vertices)
            for key, names in zone["parts"].items()
        }
        dominant = max(weights, key=weights.get)
        transition = sorted(weights.values(), reverse=True)
        material_index = 0
        if len(transition) > 1 and transition[1] > 0.16:
            material_index = 2
        if dominant in zone.get("dark_parts", ()):
            material_index = 2
        # Narrow integral gilt rolls follow the anatomy and remain on-shell.
        if any(abs(center.z - height) < width for height, width in zone.get("gilt_z", ())):
            material_index = 1
        target_polygon.material_index = material_index

    # The copied UV topology remains editable; generate a clean armor map.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.1519, island_margin=0.014, correct_aspect=True, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    return obj


def fingers_for(side):
    # MakeHuman's source-side finger suffixes are opposite the professional
    # rig's .L/.R arm names in this accepted mesh.
    suffix = "r" if side == "L" else "l"
    return tuple(
        "%s_%02d_%s" % (finger, segment, suffix)
        for finger in ("thumb", "index", "middle", "ring", "pinky")
        for segment in range(1, 4)
        if body.vertex_groups.get("%s_%02d_%s" % (finger, segment, suffix)) is not None
    )


def build_weighted_extremities():
    for side in ("L", "R"):
        create_fitted_shell(
            "shoulders", "SovereignUpperArm" + side,
            ("clavicle." + side, "upper_arm." + side), 0.075, 0.010,
            {"parts": {"upper": ("upper_arm." + side,), "clavicle": ("clavicle." + side,)},
             "dark_parts": ("clavicle",), "gilt_z": ((1.245, 0.010), (1.375, 0.009))},
        )
        hand_groups = ("forearm." + side, "hand." + side) + fingers_for(side)
        create_fitted_shell(
            "hands", "SovereignVambraceGauntlet" + side,
            hand_groups, 0.070, 0.009,
            {"parts": {"forearm": ("forearm." + side,), "hand": ("hand." + side,) + fingers_for(side)},
             "dark_parts": ("hand",), "gilt_z": ((1.105, 0.009), (1.225, 0.010))},
        )
        create_fitted_shell(
            "pants", "SovereignCuisse" + side,
            ("thigh." + side,), 0.070, 0.010,
            {"parts": {"thigh": ("thigh." + side,)}, "gilt_z": ((0.525, 0.010), (0.890, 0.010))},
        )
        create_fitted_shell(
            "feet", "SovereignGreaveSabaton" + side,
            ("shin." + side, "foot." + side, "toe." + side), 0.065, 0.009,
            {"parts": {"shin": ("shin." + side,), "foot": ("foot." + side, "toe." + side)},
             "dark_parts": ("foot",), "gilt_z": ((0.145, 0.009), (0.495, 0.010))},
        )


def tighten_cuirass():
    for name in (
        "RoyalArmor_chest_ApexWaistedCuirass",
        "RoyalArmor_chest_ApexIntegralPlackartOverlay",
        "RoyalArmor_chest_ApexIntegralRearPlackartOverlay",
        "RoyalArmor_chest_ApexUnifiedGorgetMantle",
    ):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            continue
        for vertex in obj.data.vertices:
            waist = exp(-((vertex.co.z - 1.075) / 0.155) ** 2)
            chest = exp(-((vertex.co.z - 1.330) / 0.270) ** 2)
            vertex.co.x *= 1.0 - 0.095 * waist - 0.040 * chest
            vertex.co.y *= 1.0 - 0.060 * waist - 0.025 * chest
        obj.data.update()


def tune_materials():
    values = {
        "Royal Cobalt Filigree Plate": (0.80, 0.38),
        "Royal Blued Steel": (0.82, 0.42),
        "Royal Planished Edge Steel": (0.88, 0.36),
        "Royal Blackened Steel": (0.72, 0.54),
        "Royal Gilt Brass": (0.76, 0.45),
        "Riveted Mail": (0.66, 0.56),
    }
    for name, (metallic, roughness) in values.items():
        mat = bpy.data.materials.get(name)
        if mat is None:
            continue
        mat["export_metallic"] = metallic
        mat["export_roughness"] = roughness
        if mat.use_nodes:
            bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
            if bsdf is not None:
                bsdf.inputs["Metallic"].default_value = metallic
                if not bsdf.inputs["Roughness"].is_linked:
                    bsdf.inputs["Roughness"].default_value = roughness


def main():
    remove_old_extremities()
    tighten_cuirass()
    build_weighted_extremities()
    tune_materials()
    if geometry_digest(body.data) != BODY_BEFORE:
        raise RuntimeError("Armor fit pass changed locked hero geometry")
    for obj in bpy.data.objects:
        if obj.name.startswith("RoyalArmor_"):
            obj.hide_viewport = False
            obj.hide_render = False
            obj.hide_set(False)
    bpy.context.scene["bk_armor_fit_pass"] = "LockedBodySovereignWeightedShell20260813"
    bpy.context.scene.frame_set(1)
    rig.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("LOCKED_BODY_ARMOR_FIT|objects=%d|body_unchanged=true|file=%s" % (
        len([obj for obj in bpy.data.objects if obj.name.startswith("RoyalArmor_")]), bpy.data.filepath,
    ))


if __name__ == "__main__":
    main()
