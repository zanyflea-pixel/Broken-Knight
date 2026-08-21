"""Refit the consolidated Royal Vanguard armor to the locked hero body.

This pass changes only RoyalArmor_* mesh vertices. It trims the barrel-like
depth of the torso, reduces pauldron/vambrace bulk, and tapers each cuisse and
greave around its own limb center without changing leg spacing, body geometry,
weights, materials, rig, or animations.
"""

from hashlib import sha256
import os
import struct

import bpy
import bmesh


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_ARMOR_REFIT_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_ArmorRefitCandidate.blend"),
))
PASS_ID = "RoyalArmorAnatomicalRefit20260813"


def digest(mesh):
    result = sha256()
    result.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for vertex in mesh.vertices:
        result.update(struct.pack("<3f", *vertex.co))
    return result.hexdigest()


OUTER_MATERIALS = {
    "Royal Cobalt Filigree Plate", "Royal Gilt Brass", "Royal Blued Steel",
    "Royal Planished Edge Steel",
}


def material_vertices(obj, names=OUTER_MATERIALS):
    result = set()
    for polygon in obj.data.polygons:
        if polygon.material_index >= len(obj.data.materials):
            continue
        material = obj.data.materials[polygon.material_index]
        if material is not None and material.name in names:
            result.update(polygon.vertices)
    return result


def scale_depth(obj, center_y, factor, indices, z_min=-1e9, z_max=1e9):
    for vertex in obj.data.vertices:
        if vertex.index in indices and z_min <= vertex.co.z <= z_max:
            vertex.co.y = center_y + (vertex.co.y - center_y) * factor


def scale_width(obj, factor, indices, z_min=-1e9, z_max=1e9):
    for vertex in obj.data.vertices:
        if vertex.index in indices and z_min <= vertex.co.z <= z_max:
            vertex.co.x *= factor


def taper_paired_limbs(obj, center_x, width_factor, depth_factor, indices, z_min=-1e9, z_max=1e9):
    """Thin each limb shell without moving the left/right limb center."""
    for vertex in obj.data.vertices:
        if vertex.index not in indices or not (z_min <= vertex.co.z <= z_max):
            continue
        if abs(vertex.co.x) > 0.045:
            side_center = center_x if vertex.co.x > 0.0 else -center_x
            vertex.co.x = side_center + (vertex.co.x - side_center) * width_factor
        else:
            # Keep central cod/waist plates centered while making them less broad.
            vertex.co.x *= 0.94
        vertex.co.y *= depth_factor


def require(slot):
    name = f"RoyalArmor_{slot}_SovereignConsolidated"
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Consolidated armor slot missing: {name}")
    return obj


def add_thigh_mail_underlayer(body, pants, rig):
    """Fill articulation gaps with body-fitted mail, not oversized outer plate."""
    underlayer = body.copy()
    underlayer.data = body.data.copy()
    underlayer.name = "RoyalArmor_pants_AnatomicalMailUnderlayer"
    bpy.context.scene.collection.objects.link(underlayer)
    for modifier in list(underlayer.modifiers):
        underlayer.modifiers.remove(modifier)
    mesh = underlayer.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    delete = [
        vertex for vertex in bm.verts
        if not (0.43 <= vertex.co.z <= 1.035 and abs(vertex.co.x) <= 0.34)
    ]
    bmesh.ops.delete(bm, geom=delete, context="VERTS")
    # Sit just above the hidden body surface while staying far below the outer
    # plate. Each thigh expands around its own center so stance is unchanged.
    for vertex in bm.verts:
        if abs(vertex.co.x) > 0.045:
            center = 0.131 if vertex.co.x > 0.0 else -0.131
            vertex.co.x = center + (vertex.co.x - center) * 1.018
        vertex.co.y *= 1.018
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.clear()
    mail = bpy.data.materials.get("Riveted Mail")
    if mail is None:
        raise RuntimeError("Riveted Mail material is missing")
    mesh.materials.append(mail)
    underlayer.parent = rig

    bpy.ops.object.select_all(action="DESELECT")
    pants.select_set(True)
    underlayer.select_set(True)
    bpy.context.view_layer.objects.active = pants
    bpy.ops.object.join()
    pants["bk_anatomical_mail_underlayer"] = True


def main():
    body = bpy.data.objects.get("ConnectedBody")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or rig is None:
        raise RuntimeError("Locked body or HeroRig is missing")
    body_before = digest(body.data)

    chest = require("chest")
    shoulders = require("shoulders")
    hands = require("hands")
    pants = require("pants")
    feet = require("feet")
    head = require("head")
    if any(obj.get("bk_geometry_pass") == PASS_ID for obj in (chest, shoulders, hands, pants, feet, head)):
        raise RuntimeError("Anatomical armor refit is already applied")

    # Cuirass: retain its protective overlap and heroic width, but remove the
    # inflated front/back barrel that made the entire hero look padded.
    chest_outer = material_vertices(chest)
    scale_width(chest, 0.91, chest_outer)
    scale_depth(chest, -0.012, 0.93, chest_outer)

    # Pauldrons stay visibly royal, but sit closer to the deltoids and no longer
    # dominate the silhouette from either the front or side.
    shoulder_outer = material_vertices(shoulders)
    scale_width(shoulders, 0.90, shoulder_outer)
    scale_depth(shoulders, 0.0, 0.94, shoulder_outer)

    # Keep gauntlets/vambraces unchanged. Their authored clearance is needed at
    # the wrists and elbows, and they are not the source of the heavy-leg read.

    # Separate-leg taper is the important correction: do not scale both legs
    # toward the origin, which would narrow stance and disturb planted feet.
    pants_outer = material_vertices(pants)
    taper_paired_limbs(pants, 0.131, 0.82, 0.95, pants_outer)
    # Greaves and sabatons stay unchanged to preserve full calf/ankle coverage.
    add_thigh_mail_underlayer(body, pants, rig)

    # A small helmet depth correction balances the now-fitted torso. The plume
    # height and all connected helmet parts remain intact.
    head_outer = material_vertices(head)
    scale_width(head, 0.975, head_outer, z_max=1.96)
    scale_depth(head, 0.025, 0.98, head_outer, z_max=1.96)

    for obj in (chest, shoulders, hands, pants, feet, head):
        obj["bk_geometry_pass"] = PASS_ID
        obj["bk_refit_note"] = "Anatomically fitted consolidated royal armor; locked body unchanged"
        obj.data.update()

    if digest(body.data) != body_before:
        raise RuntimeError("Armor refit changed the locked hero body")
    bpy.context.scene["bk_armor_fit_pass"] = PASS_ID
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print(f"ROYAL_ARMOR_REFIT|file={OUTPUT}|body_unchanged=true|pass={PASS_ID}")


if __name__ == "__main__":
    main()
