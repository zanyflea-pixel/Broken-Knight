"""Integrate the approved single-topology hero into a safe game candidate.

The canonical Blender file and runtime GLB remain untouched. This script uses
the professional full-body topology and weights, keeps the current compatible
HeroRig/actions/equipment, and writes a separate candidate for deformation and
Godot validation.
"""

from math import pi, sin
import os

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
ROOT = os.path.abspath(os.path.join(BLEND_DIR, ".."))
MASTER = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master.blend")
PROTOTYPE = os.path.join(BLEND_DIR, "BrokenKnight_Hero_FullContinuous_Prototype.blend")
OUTPUT_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_FullContinuous_Candidate.blend")
OUTPUT_GLB = os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_candidate.glb")

REPLACED_PREFIXES = (
    "ConnectedBody", "ProfessionalHead", "BodyHair", "Hair", "HeroHair",
    "ProfessionalEye", "ProfessionalIris", "ProfessionalPupil", "ProfessionalBrow",
    "ProfessionalFaceStubble", "Nostril", "UpperLid", "Areola", "Nipple",
    "Loincloth.", "LoinTie.", "LoinKnot.", "LoinTail.", "ClothWaistCord",
)


def append_prototype_objects():
    names = {
        "ConnectedBody", "ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R",
        "ProfessionalPupil.L", "ProfessionalPupil.R", "ProfessionalBrows",
        "HeroHairFoundation", "HeroHairDirectionalTexture", "FullHeroPrototypeRig",
    }
    directory = os.path.join(PROTOTYPE, "Object") + os.sep
    bpy.ops.wm.append(directory=directory, files=[{"name": name} for name in sorted(names)])
    result = {}
    for name in names:
        matches = [obj for obj in bpy.context.selected_objects if obj.name == name or obj.name.startswith(name + ".")]
        if not matches:
            raise RuntimeError(f"Prototype object did not append: {name}")
        obj = max(matches, key=lambda candidate: len(candidate.data.vertices) if candidate.type == "MESH" else 0)
        result[name] = obj
    return result


def move_to_collection(obj, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def delete_old_anatomy():
    for obj in list(bpy.data.objects):
        if obj.name == "HeroRig":
            continue
        if obj.type not in {"MESH", "CURVE"}:
            continue
        if obj.name.startswith("RoyalArmor_") or obj.name.startswith("RoyalStaff_"):
            continue
        if obj.name.startswith(REPLACED_PREFIXES) or obj.name.startswith("ProfessionalHair"):
            bpy.data.objects.remove(obj, do_unlink=True)


def source_to_target_mapping():
    mapping = {
        "pelvis": "pelvis",
        "spine_01": "spine", "spine_02": "spine", "spine_03": "chest",
        "neck_01": "neck", "head": "head",
        "thigh_l": "thigh.R", "calf_l": "shin.R", "foot_l": "foot.R", "ball_l": "toe.R",
        "thigh_r": "thigh.L", "calf_r": "shin.L", "foot_r": "foot.L", "ball_r": "toe.L",
        "clavicle_l": "clavicle.R", "upperarm_l": "upper_arm.R", "lowerarm_l": "forearm.R", "hand_l": "hand.R",
        "clavicle_r": "clavicle.L", "upperarm_r": "upper_arm.L", "lowerarm_r": "forearm.L", "hand_r": "hand.L",
    }
    # Finger weights follow their hand as a rigid cluster in the simplified
    # gameplay skeleton; this preserves authored hands without collapsing them.
    for side, suffix in (("l", "R"), ("r", "L")):
        for finger in ("index", "middle", "pinky", "ring", "thumb"):
            for segment in ("01", "02", "03"):
                mapping[f"{finger}_{segment}_{side}"] = f"hand.{suffix}"
    return mapping


def source_reference_bone(group_name):
    # Finger vertices keep their relative hand layout; mapping every phalanx to
    # the target hand matrix independently would stack all fingers together.
    if group_name.endswith("_l") and group_name.startswith(("index_", "middle_", "pinky_", "ring_", "thumb_")):
        return "hand_l"
    if group_name.endswith("_r") and group_name.startswith(("index_", "middle_", "pinky_", "ring_", "thumb_")):
        return "hand_r"
    return group_name


def warp_body_to_game_rest(body, source_rig, target_rig):
    """No destructive rest warp: professional anatomy stays in authored rest.

    The compatible HeroRig is adjusted to this body below. Matrix-blending two
    unlike skeleton rest orientations twisted shoulders and neck beyond repair.
    """
    body["rest_pose_conversion"] = "preserved_professional_rest_pose"


def fit_game_rig_to_professional(source_rig, target_rig):
    """Move the existing named game bones onto professional anatomical joints."""
    specs = {
        "pelvis": ("pelvis", "spine_01"),
        "spine": ("spine_01", "spine_03"),
        "chest": ("spine_03", None),
        "neck": ("neck_01", "head"),
        "head": ("head", None),
        "clavicle.R": ("clavicle_l", "upperarm_l"),
        "upper_arm.R": ("upperarm_l", "lowerarm_l"),
        "forearm.R": ("lowerarm_l", "hand_l"),
        "hand.R": ("hand_l", None),
        "clavicle.L": ("clavicle_r", "upperarm_r"),
        "upper_arm.L": ("upperarm_r", "lowerarm_r"),
        "forearm.L": ("lowerarm_r", "hand_r"),
        "hand.L": ("hand_r", None),
        "thigh.R": ("thigh_l", "calf_l"),
        "shin.R": ("calf_l", "foot_l"),
        "foot.R": ("foot_l", "ball_l"),
        "toe.R": ("ball_l", None),
        "thigh.L": ("thigh_r", "calf_r"),
        "shin.L": ("calf_r", "foot_r"),
        "foot.L": ("foot_r", "ball_r"),
        "toe.L": ("ball_r", None),
    }
    bpy.context.view_layer.objects.active = target_rig
    target_rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edits = target_rig.data.edit_bones
    for target_name, (source_name, source_tail_name) in specs.items():
        target = edits.get(target_name)
        source = source_rig.data.bones.get(source_name)
        if target is None or source is None:
            continue
        target.head = source.head_local
        if source_tail_name:
            source_tail = source_rig.data.bones.get(source_tail_name)
            target.tail = source_tail.head_local if source_tail else source.tail_local
        else:
            target.tail = source.tail_local
    # Chest must reach the clavicle/neck junction; jaw and cloth bones follow
    # the professionally fitted core without changing their public names.
    edits["chest"].tail = Vector((0.0, -0.010, 1.585))
    edits["jaw"].head = Vector((0.0, -0.055, 1.710))
    edits["jaw"].tail = Vector((0.0, -0.105, 1.660))
    edits["loin_front"].head = Vector((0.0, -0.125, 0.995))
    edits["loin_front"].tail = Vector((0.0, -0.145, 0.760))
    edits["loin_back"].head = Vector((0.0, 0.125, 0.995))
    edits["loin_back"].tail = Vector((0.0, 0.145, 0.760))
    bpy.ops.object.mode_set(mode="OBJECT")
    target_rig.select_set(False)
    target_rig["rest_pose_fit"] = "professional_full_body_anatomical_joints_v1"


def retarget_actions_rest_change(target_rig, old_rest_matrices):
    """Preserve animation world motion after changing the named bone rests."""
    new_rest = {bone.name: bone.matrix_local.copy() for bone in target_rig.data.bones}
    for action in bpy.data.actions:
        if not action.slots:
            continue
        bags = action.layers[0].strips[0].channelbags if action.layers and action.layers[0].strips else []
        fcurves = [curve for bag in bags for curve in bag.fcurves]
        frame_numbers = sorted({int(round(point.co.x)) for curve in fcurves for point in curve.keyframe_points})
        if not frame_numbers:
            continue
        target_rig.animation_data.action = action
        for frame in frame_numbers:
            bpy.context.scene.frame_set(frame)
            old_basis = {bone.name: bone.matrix_basis.copy() for bone in target_rig.pose.bones}
            for pose_bone in target_rig.pose.bones:
                name = pose_bone.name
                old_rest = old_rest_matrices.get(name)
                if old_rest is None:
                    continue
                pose_bone.matrix_basis = new_rest[name].inverted() @ old_rest @ old_basis[name]
                pose_bone.keyframe_insert("rotation_euler", frame=frame, group=name)
                pose_bone.keyframe_insert("location", frame=frame, group=name)
                pose_bone.keyframe_insert("scale", frame=frame, group=name)
        action["rest_pose_retarget"] = "old_hero_rig_to_professional_fit_v1"


def head_rest_transform(source_rig, target_rig):
    return Matrix.Identity(4)


def warp_object(obj, transform):
    if obj.type == "CURVE":
        for spline in obj.data.splines:
            for point in spline.points:
                world = obj.matrix_world @ Vector(point.co[:3])
                point.co = (*((obj.matrix_world.inverted() @ (transform @ world))), point.co.w)
            for point in spline.bezier_points:
                world = obj.matrix_world @ point.co
                point.co = obj.matrix_world.inverted() @ (transform @ world)
                point.handle_left = obj.matrix_world.inverted() @ (transform @ (obj.matrix_world @ point.handle_left))
                point.handle_right = obj.matrix_world.inverted() @ (transform @ (obj.matrix_world @ point.handle_right))
    elif obj.type == "MESH":
        inverse = obj.matrix_world.inverted()
        for vertex in obj.data.vertices:
            vertex.co = inverse @ (transform @ (obj.matrix_world @ vertex.co))
        obj.data.update()


def fallback_bone_for_point(point):
    x, y, z = point
    side = "L" if x < 0.0 else "R"
    ax = abs(x)
    if ax > 0.30 and z > 1.0:
        return f"hand.{side}" if ax > 0.47 else (f"forearm.{side}" if ax > 0.38 else f"upper_arm.{side}")
    if z < 0.13:
        return f"toe.{side}" if y < -0.10 else f"foot.{side}"
    if z < 0.55 and ax > 0.06:
        return f"shin.{side}"
    if z < 1.0 and ax > 0.06:
        return f"thigh.{side}"
    if z > 1.64:
        return "head"
    if z > 1.49:
        return "neck"
    if z > 1.25:
        return "chest"
    if z > 1.04:
        return "spine"
    return "pelvis"


def remap_body_to_game_rig(body, rig):
    mapping = source_to_target_mapping()
    source_groups = list(body.vertex_groups)
    source_names = {group.index: group.name for group in source_groups}
    preserved_groups = {
        group.name: [(vertex.index, next((member.weight for member in vertex.groups if member.group == group.index), 0.0)) for vertex in body.data.vertices]
        for group in source_groups if group.name in {"body"}
    }
    assignments = []
    for vertex in body.data.vertices:
        weights = {}
        for member in vertex.groups:
            target = mapping.get(source_names.get(member.group, ""))
            if target is not None and member.weight > 1e-6:
                weights[target] = weights.get(target, 0.0) + member.weight
        if not weights:
            weights = {fallback_bone_for_point(vertex.co): 1.0}
        total = sum(weights.values())
        assignments.append({name: weight / total for name, weight in weights.items()})
    for group in list(body.vertex_groups):
        body.vertex_groups.remove(group)
    for name, values in preserved_groups.items():
        group = body.vertex_groups.new(name=name)
        for index, weight in values:
            if weight > 1e-6:
                group.add([index], weight, "REPLACE")
    target_groups = {
        bone.name: body.vertex_groups.new(name=bone.name)
        for bone in rig.data.bones if bone.use_deform
    }
    for index, weights in enumerate(assignments):
        for name, weight in sorted(weights.items(), key=lambda item: item[1], reverse=True)[:4]:
            target_groups[name].add([index], weight, "REPLACE")
    for modifier in list(body.modifiers):
        if modifier.type == "ARMATURE":
            body.modifiers.remove(modifier)
    armature = body.modifiers.new("HeroArmature", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    body.parent = rig
    body.matrix_parent_inverse = rig.matrix_world.inverted()
    body.name = "ConnectedBody"
    body["hero_rebuild"] = "single_continuous_professional_full_body"
    body["game_rig_weight_mapping"] = "mpfb_professional_to_hero_rig_v1"
    move_to_collection(body, "01_HERO_BODY")


def clean_body_only(body):
    """Apply the helper mask and subdivision while preserving skin weights."""
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    if body.data.shape_keys is not None:
        body.shape_key_clear()
    for modifier in list(body.modifiers):
        if modifier.type in {"MASK", "SUBSURF"}:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    body.select_set(False)
    # The evaluated body no longer needs MPFB helper/joint metadata groups.
    deform_names = {bone.name for bone in bpy.data.objects["HeroRig"].data.bones if bone.use_deform}
    for group in list(body.vertex_groups):
        if group.name not in deform_names:
            body.vertex_groups.remove(group)
    groups = {group.name: group for group in body.vertex_groups}
    group_names = {group.index: group.name for group in body.vertex_groups}
    # Subdivision interpolates skin groups, but seam-adjacent evaluated points
    # can land a hair below normalized total. Fill/renormalize explicitly.
    for vertex in body.data.vertices:
        memberships = [member for member in vertex.groups if group_names.get(member.group) in deform_names and member.weight > 1e-8]
        total = sum(member.weight for member in memberships)
        if total < 1e-8:
            groups[fallback_bone_for_point(vertex.co)].add([vertex.index], 1.0, "REPLACE")
            continue
        if abs(total - 1.0) > 1e-5:
            for member in memberships:
                groups[group_names[member.group]].add([vertex.index], member.weight / total, "REPLACE")


def bone_parent(obj, rig, bone_name="head"):
    if obj.type == "CURVE":
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        obj.select_set(False)
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("HeroArmature", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def create_material(name, color, roughness):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = color
    material.roughness = roughness
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def create_loincloth(body, rig):
    cloth = create_material("PlainLoincloth.Continuous", (0.16, 0.042, 0.015, 1.0), 0.92)
    cord = create_material("LoinCord.Continuous", (0.055, 0.012, 0.004, 1.0), 0.88)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    columns = (-1.0, -0.82, -0.64, -0.46, -0.28, -0.10, 0.10, 0.28, 0.46, 0.64, 0.82, 1.0)
    for name, front in (("Loincloth.Front", True), ("Loincloth.Back", False)):
        rows = (
            (0.995, 0.137), (0.955, 0.140), (0.910, 0.143), (0.865, 0.141),
            (0.820, 0.134), (0.775, 0.123), (0.735, 0.108), (0.700, 0.092),
        )
        vertices = []
        vertex_blends = []
        for row_index, (z, half_width) in enumerate(rows):
            t = row_index / (len(rows) - 1)
            for column in columns:
                x = half_width * column
                if front:
                    hit = tree.ray_cast(Vector((x, -0.50, z)), Vector((0.0, 1.0, 0.0)), 1.0)
                    surface = hit[0].y if hit[0] is not None else -0.14
                    y = surface - (0.0065 + 0.002 * t)
                    y -= 0.0030 * sin((column + 1.0) * pi * 2.5) * t
                else:
                    hit = tree.ray_cast(Vector((x, 0.50, z)), Vector((0.0, -1.0, 0.0)), 1.0)
                    surface = hit[0].y if hit[0] is not None else 0.13
                    y = surface + (0.0065 + 0.002 * t)
                    y += 0.0030 * sin((column + 1.0) * pi * 2.5) * t
                hem = 0.005 * sin((column + 1.0) * pi * 2.3) if row_index == len(rows) - 1 else 0.0
                vertices.append((x, y, z + hem))
                vertex_blends.append((t, column))
        faces = []
        width = len(columns)
        for row in range(len(rows) - 1):
            for column in range(width - 1):
                index = row * width + column
                faces.append((index, index + 1, index + width + 1, index + width))
        mesh = bpy.data.meshes.new(name + ".Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(cloth)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.data.collections["04_LOINCLOTH"].objects.link(obj)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        pelvis = obj.vertex_groups.new(name="pelvis")
        left = obj.vertex_groups.new(name="thigh.L")
        right = obj.vertex_groups.new(name="thigh.R")
        loin = obj.vertex_groups.new(name="loin_front" if front else "loin_back")
        for index, (t, column) in enumerate(vertex_blends):
            lower = max(0.0, (t - 0.22) / 0.78)
            leg_weight = 0.16 * lower * min(1.0, abs(column) * 1.5)
            loin_weight = 0.15 * lower * (1.0 - min(1.0, abs(column)))
            pelvis.add([index], 1.0 - leg_weight - loin_weight, "REPLACE")
            if column < 0.0:
                left.add([index], leg_weight, "REPLACE")
            else:
                right.add([index], leg_weight, "REPLACE")
            loin.add([index], loin_weight, "REPLACE")
        modifier = obj.modifiers.new("HeroArmature", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = True
        solidify = obj.modifiers.new("ClothThickness", "SOLIDIFY")
        solidify.thickness = 0.0014
        subdivision = obj.modifiers.new("ClothDrape", "SUBSURF")
        subdivision.levels = 1
        subdivision.render_levels = 1
        obj.parent = rig
        obj.matrix_parent_inverse = rig.matrix_world.inverted()

    # Close-fitting rope belt with no floating bow in back.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.156, minor_radius=0.0052, major_segments=64, minor_segments=10, location=(0.0, 0.0, 0.997))
    belt = bpy.context.object
    belt.name = "ClothWaistCord"
    belt.scale.y = 0.82
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    belt.data.materials.append(cord)
    move_to_collection(belt, "04_LOINCLOTH")
    bone_parent(belt, rig, "pelvis")


def export_candidate(rig):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if obj.name == "ConnectedBody" or obj.name.startswith((
            "Professional", "HeroHair", "Loincloth.", "ClothWaistCord",
            "RoyalArmor_", "RoyalStaff_",
        )):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=True,
        export_nla_strips=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )


def validate(body, rig):
    if len(body.data.vertices) < 18000:
        raise RuntimeError("Professional body topology was unexpectedly reduced")
    names = {bone.name for bone in rig.data.bones}
    required = {"root", "pelvis", "spine", "chest", "neck", "head", "hand.L", "hand.R", "foot.L", "foot.R"}
    if not required <= names:
        raise RuntimeError(f"Game rig is missing required bones: {sorted(required - names)}")
    missing = [name for name in ("Idle", "Walk", "Jump", "Land", "Roll", "SwordSlash", "Death") if bpy.data.actions.get(name) is None]
    if missing:
        raise RuntimeError(f"Required actions missing: {missing}")
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    group_names = {group.index: group.name for group in body.vertex_groups}
    minimum = 10.0
    maximum = 0.0
    underweighted = 0
    for vertex in body.data.vertices:
        total = sum(member.weight for member in vertex.groups if group_names.get(member.group) in deform_names)
        minimum = min(minimum, total)
        maximum = max(maximum, total)
        if total < 0.999:
            underweighted += 1
    if underweighted:
        raise RuntimeError(f"Continuous body has {underweighted} underweighted vertices")
    print(
        f"FULL_CONTINUOUS_CANDIDATE|verts={len(body.data.vertices)}|faces={len(body.data.polygons)}|"
        f"weights={minimum:.6f}:{maximum:.6f}|actions={len(bpy.data.actions)}|height={body.dimensions.z:.5f}"
    )


def main():
    if not os.path.isfile(MASTER) or not os.path.isfile(PROTOTYPE):
        raise RuntimeError("Required master/prototype blend is missing")
    bpy.ops.wm.open_mainfile(filepath=MASTER)
    rig = bpy.data.objects.get("HeroRig")
    if rig is None:
        raise RuntimeError("HeroRig missing from canonical master")
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    old_rest_matrices = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
    delete_old_anatomy()
    objects = append_prototype_objects()
    body = objects["ConnectedBody"]
    source_rig = objects["FullHeroPrototypeRig"]
    if source_rig is None or source_rig.type != "ARMATURE":
        raise RuntimeError("Professional source rig was not appended with the body")
    fit_game_rig_to_professional(source_rig, rig)
    rig.data.pose_position = "POSE"
    retarget_actions_rest_change(rig, old_rest_matrices)
    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    warp_body_to_game_rest(body, source_rig, rig)
    remap_body_to_game_rig(body, rig)
    clean_body_only(body)
    accessory_transform = head_rest_transform(source_rig, rig)
    for name in ("ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R", "ProfessionalPupil.L", "ProfessionalPupil.R", "ProfessionalBrows"):
        obj = objects[name]
        warp_object(obj, accessory_transform)
        move_to_collection(obj, "02_HERO_FACE")
        bone_parent(obj, rig, "head")
    for name in ("HeroHairFoundation", "HeroHairDirectionalTexture"):
        obj = objects[name]
        warp_object(obj, accessory_transform)
        move_to_collection(obj, "03_HERO_HAIR")
        bone_parent(obj, rig, "head")
    if source_rig != rig:
        bpy.data.objects.remove(source_rig, do_unlink=True)
    create_loincloth(body, rig)
    rig.data.pose_position = "POSE"
    rig.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    validate(body, rig)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    export_candidate(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"FULL_CONTINUOUS_CANDIDATE_DONE|blend={OUTPUT_BLEND}|glb={OUTPUT_GLB}")


if __name__ == "__main__":
    main()
