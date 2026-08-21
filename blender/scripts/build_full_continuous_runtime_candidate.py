"""Build a game-compatible candidate on the professional deformation rig.

This keeps the authored full-body rest pose/weights exactly intact, renames the
gameplay joints Godot uses, and creates clean in-place animations directly on
that skeleton. It intentionally omits armor from this candidate until the hero
body and head have passed visual inspection.
"""

from math import cos, pi, radians, sin
import os

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
ROOT = os.path.abspath(os.path.join(BLEND_DIR, ".."))
SOURCE = os.path.join(BLEND_DIR, "BrokenKnight_Hero_FullContinuous_Prototype.blend")
EQUIPMENT_SOURCE = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master.blend")
OUTPUT_BLEND = os.environ.get(
    "BK_FULL_HERO_OUTPUT_BLEND",
    os.path.join(BLEND_DIR, "BrokenKnight_Hero_FullContinuous_RuntimeCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_FULL_HERO_OUTPUT_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_body.glb"),
)


RENAME = {
    "Root": "root", "spine_01": "spine", "spine_03": "chest", "neck_01": "neck",
    "clavicle_l": "clavicle.R", "upperarm_l": "upper_arm.R", "lowerarm_l": "forearm.R", "hand_l": "hand.R",
    "clavicle_r": "clavicle.L", "upperarm_r": "upper_arm.L", "lowerarm_r": "forearm.L", "hand_r": "hand.L",
    "thigh_l": "thigh.R", "calf_l": "shin.R", "foot_l": "foot.R", "ball_l": "toe.R",
    "thigh_r": "thigh.L", "calf_r": "shin.L", "foot_r": "foot.L", "ball_r": "toe.L",
}


def rename_rig(rig):
    body = bpy.data.objects["ConnectedBody"]
    for old_name, new_name in RENAME.items():
        bone = rig.data.bones.get(old_name)
        if bone is None:
            raise RuntimeError(f"Professional rig missing {old_name}")
        bone.name = new_name
        group = body.vertex_groups.get(old_name)
        if group is not None:
            group.name = new_name
    rig.name = "HeroRig"
    rig.data.name = "HeroRig"
    rig["runtime_rig"] = "professional_game_engine_full_body"
    return body


def clean_body(body, rig):
    # Freeze the authored MPFB morph mix into the mesh.  `shape_key_clear()`
    # used here previously discarded the hero targets and silently restored
    # the generic base (the reason the first runtime review became smaller and
    # feminine).  Apply the visible mix instead.
    rig.data.pose_position = "REST"
    if rig.animation_data is not None:
        rig.animation_data.action = None
    bpy.context.scene.frame_set(0)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    if body.data.shape_keys is not None:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    # Apply surface-only modifiers ahead of deformation.  Applying MASK/SUBSURF
    # below an active Armature baked the pose and reduced the measured height.
    armatures = [modifier for modifier in body.modifiers if modifier.type == "ARMATURE"]
    for modifier in armatures:
        body.modifiers.remove(modifier)
    for modifier in list(body.modifiers):
        if modifier.type in {"MASK", "SUBSURF"}:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    armature = body.modifiers.new("HeroArmature", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    body.select_set(False)
    body.parent = rig
    body.matrix_parent_inverse = rig.matrix_world.inverted()
    body["topology"] = "single_continuous_professional_human_clean_export"


def bind_head_accessories(rig):
    for obj in bpy.context.scene.objects:
        if not (
            obj.name in {
                "ProfessionalEyes", "ProfessionalIris.L", "ProfessionalIris.R", "ProfessionalPupil.L", "ProfessionalPupil.R",
                "ProfessionalBrows",
            }
            or obj.name.startswith("HeroHair")
        ):
            continue
        if obj.type == "CURVE":
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target="MESH")
        # Accessories are authored in final world/rest coordinates.  Bone
        # parenting with an unchanged world matrix is the correct rigid bind;
        # a head-weight Armature modifier on those world coordinates applies
        # the head rest transform a second time and launches them above the
        # skull.
        for modifier in list(obj.modifiers):
            if modifier.type == "ARMATURE":
                obj.modifiers.remove(modifier)
        # Preserve non-deformation attributes such as the foundation's smooth
        # hairline mask; rigid bone parenting does not evaluate them as weights.
        world = obj.matrix_world.copy()
        obj.parent = rig
        obj.parent_type = "BONE"
        obj.parent_bone = "head"
        obj.matrix_world = world


def simple_material(name, color, roughness):
    result = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    result.diffuse_color = color
    result.roughness = roughness
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return result


def rigid_bone_parent(obj, rig, bone_name):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


def transfer_body_weights(obj, body, rig):
    """Copy the body's interpolated deformation weights onto fitted clothing."""
    for group in body.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    transfer = obj.modifiers.new("CopyContinuousBodyWeights", "DATA_TRANSFER")
    transfer.object = body
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.modifier_apply(modifier=transfer.name)
    armature = obj.modifiers.new("HeroArmature", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def create_loincloth(body, rig):
    """Create a close-fitting front/back cloth on the rebuilt body's surface."""
    cloth = simple_material("PlainLoincloth.Continuous", (0.115, 0.030, 0.010, 1.0), 0.94)
    cord = simple_material("LoinCord.Continuous", (0.035, 0.008, 0.003, 1.0), 0.91)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    columns = (-1.0, -0.84, -0.66, -0.48, -0.30, -0.12, 0.12, 0.30, 0.48, 0.66, 0.84, 1.0)
    for name, front in (("Loincloth.Front", True), ("Loincloth.Back", False)):
        rows = (
            ((0.982, 0.148), (0.940, 0.150), (0.895, 0.146), (0.850, 0.137),
             (0.805, 0.125), (0.762, 0.111), (0.724, 0.094), (0.690, 0.077))
            if front else
            ((0.982, 0.152), (0.948, 0.158), (0.912, 0.161), (0.875, 0.158),
             (0.838, 0.151), (0.803, 0.141))
        )
        vertices = []
        blends = []
        for row_index, (z, half_width) in enumerate(rows):
            t = row_index / (len(rows) - 1)
            for column in columns:
                x = half_width * column
                origin = Vector((x, -0.50 if front else 0.50, z))
                direction = Vector((0.0, 1.0 if front else -1.0, 0.0))
                hit = tree.ray_cast(origin, direction, 1.0)
                surface = hit[0].y if hit[0] is not None else (-0.13 if front else 0.13)
                # The back panel is intentionally almost skin-tight. Its old
                # six-millimetre stand-off visibly floated behind the glutes.
                offset = (0.0040 + 0.0009 * t) if front else (0.0060 + 0.0008 * t)
                y = surface - offset if front else surface + offset
                y += (-1.0 if front else 1.0) * (0.0014 if front else 0.00045) * sin((column + 1.0) * pi * 2.0) * t
                hem = 0.004 * sin((column + 1.0) * pi * 2.2) if row_index == len(rows) - 1 else 0.0
                vertices.append((x, y, z + hem))
                blends.append((t, column))
        width = len(columns)
        faces = []
        for row in range(len(rows) - 1):
            for column in range(width - 1):
                index = row * width + column
                faces.append((index, index + 1, index + width + 1, index + width))
        mesh = bpy.data.meshes.new(name + ".Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(cloth)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        if front:
            transfer_body_weights(obj, body, rig)
        else:
            # The rear cloth is a single close panel over a region governed
            # almost entirely by the pelvis. Interpolated surface weights tore
            # its two halves apart; rigid pelvis binding keeps the fitted
            # silhouette coherent through Idle and Walk.
            rigid_bone_parent(obj, rig, "pelvis")
        solidify = obj.modifiers.new("ClothThickness", "SOLIDIFY")
        solidify.thickness = 0.0016
        # Preserve the sampled glute contour on the rear panel. Subdivision
        # averaged those fitted rows away from the body and recreated the old
        # floating butt flap. The front may keep one draping subdivision pass.
        if front:
            subdivision = obj.modifiers.new("ClothDrape", "SUBSURF")
            subdivision.levels = 1
            subdivision.render_levels = 1

    # Body-fitted waistband. A scaled torus intersected the hips and appeared
    # as floating horizontal spikes from the side; this band follows the real
    # waist surface all the way around.
    segments = 72
    band_vertices = []
    for z in (0.972, 0.989):
        for index in range(segments):
            angle = 2.0 * pi * index / segments
            radial = Vector((cos(angle), sin(angle), 0.0))
            origin = Vector((radial.x * 0.55, radial.y * 0.55, z))
            hit = tree.ray_cast(origin, -radial, 1.0)
            surface = hit[0] if hit[0] is not None else Vector((radial.x * 0.155, radial.y * 0.125, z))
            point = surface + radial * 0.0024
            point.z = z
            band_vertices.append(tuple(point))
    band_faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        band_faces.append((index, nxt, segments + nxt, segments + index))
    band_mesh = bpy.data.meshes.new("Loincloth.Waistband.Mesh")
    band_mesh.from_pydata(band_vertices, [], band_faces)
    band_mesh.materials.append(cord)
    band_mesh.update()
    belt = bpy.data.objects.new("Loincloth.Waistband", band_mesh)
    bpy.context.collection.objects.link(belt)
    for polygon in band_mesh.polygons:
        polygon.use_smooth = True
    band_solid = belt.modifiers.new("WaistbandThickness", "SOLIDIFY")
    band_solid.thickness = 0.0022
    band_bevel = belt.modifiers.new("WaistbandEdge", "BEVEL")
    band_bevel.width = 0.0012
    band_bevel.segments = 2
    rigid_bone_parent(belt, rig, "pelvis")


def append_existing_equipment(rig):
    """Preserve the authored royal equipment while replacing only its rig."""
    with bpy.data.libraries.load(EQUIPMENT_SOURCE, link=False) as (source, target):
        target.objects = [name for name in source.objects if name.startswith(("RoyalArmor_", "RoyalStaff_"))]
    for obj in target.objects:
        if obj is None:
            continue
        if obj.name not in bpy.context.scene.objects:
            bpy.context.collection.objects.link(obj)
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE":
                modifier.object = rig
        obj.parent = rig
        obj.parent_type = "OBJECT"
        obj.matrix_parent_inverse = rig.matrix_world.inverted()
        obj["equipment_transfer"] = "preserved_authored_mesh_rebound_to_continuous_rig"


def clear_actions(rig):
    rig.animation_data_create()
    rig.animation_data.action = None
    while rig.animation_data.nla_tracks:
        rig.animation_data.nla_tracks.remove(rig.animation_data.nla_tracks[0])
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def key_pose(rig, frame, transforms):
    reset_pose(rig)
    for name, values in transforms.items():
        bone = rig.pose.bones.get(name)
        if bone is None:
            continue
        if "rot" in values:
            bone.rotation_euler = tuple(radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
    for bone in rig.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def make_action(rig, name, frames, length, loop):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame, transforms in frames:
        key_pose(rig, frame, transforms)
    action.frame_start = 1
    action.frame_end = length
    action.use_frame_range = True
    action.use_cyclic = loop
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    if bag.slot_handle == slot.handle:
                        for curve in bag.fcurves:
                            for point in curve.keyframe_points:
                                point.interpolation = "BEZIER"
    return action


def idle_frames():
    base = {
        "pelvis": {"rot": (0.4, -0.5, -0.2)}, "spine": {"rot": (0.4, 0.3, 0.15)},
        "chest": {"rot": (-0.3, 0.35, -0.15)}, "neck": {"rot": (-0.1, -0.2, 0.08)}, "head": {"rot": (-0.35, -0.25, 0.0)},
        # This skeleton's local Z axis controls arm adduction. Twenty degrees
        # produces a relaxed human hang; the former 2.5 degrees left an A-pose.
        "upper_arm.L": {"rot": (4.0, 0.0, 21.0)}, "upper_arm.R": {"rot": (4.0, 0.0, -21.0)},
        "forearm.L": {"rot": (8.0, 0.0, 5.0)}, "forearm.R": {"rot": (8.0, 0.0, -5.0)},
    }
    inhale = {name: dict(value) for name, value in base.items()}
    inhale["pelvis"] = {"rot": (0.8, 0.8, 0.2), "loc": (0.0, 0.0, 0.003)}
    inhale["chest"] = {"rot": (-0.65, -0.35, 0.20)}
    inhale["head"] = {"rot": (-0.3, 0.35, 0.1)}
    return ((1, base), (31, inhale), (61, base))


def walk_frames():
    def phase(left_thigh, right_thigh, left_knee, right_knee, left_foot, right_foot,
              left_toe, right_toe, left_arm, right_arm, left_elbow, right_elbow,
              height, twist, side_shift):
        return {
            "root": {"loc": (0.0, 0.0, height)},
            "pelvis": {"loc": (side_shift, 0.0, 0.0), "rot": (1.2, 3.0 * twist, 1.8 * twist)},
            "spine": {"rot": (0.4, -0.9 * twist, -0.65 * twist)},
            "chest": {"rot": (0.2, -2.1 * twist, -0.75 * twist)},
            "neck": {"rot": (-0.5, 0.35 * twist, 0.16 * twist)},
            "head": {"rot": (-0.7, 0.25 * twist, -0.12 * twist)},
            # These professional bones are oblique in local space. Pair the
            # forward X rotation with Z compensation so knees track forward
            # instead of sweeping across or away from the body's centre line.
            "thigh.L": {"rot": (left_thigh, 0.0, 0.48 * left_thigh)},
            "thigh.R": {"rot": (right_thigh, 0.0, -0.48 * right_thigh)},
            "shin.L": {"rot": (left_knee, 0.0, 0.0)},
            "shin.R": {"rot": (right_knee, 0.0, 0.0)},
            "foot.L": {"rot": (left_foot, 0.0, 0.0)},
            "foot.R": {"rot": (right_foot, 0.0, 0.0)},
            "toe.L": {"rot": (left_toe, 0.0, 0.0)},
            "toe.R": {"rot": (right_toe, 0.0, 0.0)},
            # Contralateral arm swing layered over the relaxed inward stance.
            "upper_arm.L": {"rot": (left_arm, 0.0, 21.0)},
            "upper_arm.R": {"rot": (right_arm, 0.0, -21.0)},
            "forearm.L": {"rot": (left_elbow, 0.0, 5.0)},
            "forearm.R": {"rot": (right_elbow, 0.0, -5.0)},
            "hand.L": {"rot": (-2.0 + 0.10 * left_arm, -1.0, 2.0)},
            "hand.R": {"rot": (2.0 + 0.10 * right_arm, 1.0, -2.0)},
        }

    # Contact / down / passing / up for each side.  The stance leg remains
    # long at contact, absorbs weight at down, then drives through toe-off;
    # the swing knee peaks in passing and opens before heel strike.
    left_contact = phase(-21, 24, 6, 20, -16, 15, 0, 17, -18, 21, 14, 18, 0.008, 1.0, -0.006)
    left_down = phase(-16, 14, 15, 19, -7, 18, 4, 22, -13, 17, 16, 19, -0.006, 0.68, -0.009)
    left_pass = phase(1, -4, 10, 43, 5, -8, 10, 4, 1, -2, 18, 15, 0.010, 0.05, -0.003)
    left_up = phase(15, -17, 8, 48, 17, -12, 20, 0, 16, -19, 20, 14, 0.018, -0.72, 0.006)
    right_contact = phase(24, -21, 20, 6, 15, -16, 17, 0, 21, -18, 18, 14, 0.008, -1.0, 0.006)
    right_down = phase(14, -16, 19, 15, 18, -7, 22, 4, 17, -13, 19, 16, -0.006, -0.68, 0.009)
    right_pass = phase(-4, 1, 43, 10, -8, 5, 4, 10, -2, 1, 15, 18, 0.010, -0.05, 0.003)
    right_up = phase(-17, 15, 48, 8, -12, 17, 0, 20, -19, 16, 14, 20, 0.018, 0.72, -0.006)
    return (
        (1, left_contact), (4, left_down), (7, left_pass), (10, left_up),
        (13, right_contact), (16, right_down), (19, right_pass), (22, right_up),
        (25, left_contact),
    )


def ground_walk_action(rig, body, action):
    """Bake per-frame root height so the stance sole remains on the floor."""
    rig.animation_data.action = action
    root = rig.pose.bones["root"]
    scene = bpy.context.scene
    for frame in range(1, 26):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = body.evaluated_get(depsgraph)
        minimum = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)
        root.location.z -= minimum
        root.keyframe_insert("location", frame=frame, group=root.name)
    # Dense root keys prevent Bezier overshoot between the eight authored poses.
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    if bag.slot_handle == slot.handle:
                        for curve in bag.fcurves:
                            if curve.data_path.endswith('pose.bones["root"].location'):
                                for point in curve.keyframe_points:
                                    point.interpolation = "LINEAR"


def build_walk_action_ik(rig):
    """Author the gait from planted ankle paths, then bake to portable bones."""
    source_action = bpy.data.actions.new("WalkIKSource")
    rig.animation_data.action = source_action
    targets = {}
    for side in ("L", "R"):
        target = bpy.data.objects.new(f"WalkFootTarget.{side}", None)
        target.empty_display_type = "PLAIN_AXES"
        target.empty_display_size = 0.035
        bpy.context.collection.objects.link(target)
        targets[side] = target
        ik = rig.pose.bones[f"shin.{side}"].constraints.new("IK")
        ik.name = f"WalkPlantedFootIK.{side}"
        ik.target = target
        ik.chain_count = 2
        ik.use_tail = True
        ik.influence = 1.0

    # frame, left ankle xyz, right ankle xyz, body phase, left/right foot pitch
    path = (
        (1,  (-0.145, -0.205, 0.079), (0.145, 0.145, 0.108), 0, -9.0, 21.0),
        (4,  (-0.145, -0.155, 0.076), (0.145, 0.175, 0.105), 1, -2.0, 24.0),
        (7,  (-0.145, -0.055, 0.076), (0.145, 0.025, 0.150), 2, 5.0, -4.0),
        (10, (-0.145, 0.125, 0.100), (0.145, -0.130, 0.132), 3, 22.0, -8.0),
        (13, (-0.145, 0.145, 0.108), (0.145, -0.205, 0.079), 4, 21.0, -9.0),
        (16, (-0.145, 0.175, 0.105), (0.145, -0.155, 0.076), 5, 24.0, -2.0),
        (19, (-0.145, 0.025, 0.150), (0.145, -0.055, 0.076), 6, -4.0, 5.0),
        (22, (-0.145, -0.130, 0.132), (0.145, 0.125, 0.100), 7, -8.0, 22.0),
        (25, (-0.145, -0.205, 0.079), (0.145, 0.145, 0.108), 0, -9.0, 21.0),
    )
    body_phases = [transforms for _frame, transforms in walk_frames()]
    for frame, left, right, phase_index, left_pitch, right_pitch in path:
        transforms = {
            name: dict(values)
            for name, values in body_phases[phase_index].items()
            if not name.startswith(("thigh.", "shin.", "foot."))
        }
        transforms["foot.L"] = {"rot": (left_pitch, 0.0, 0.0)}
        transforms["foot.R"] = {"rot": (right_pitch, 0.0, 0.0)}
        key_pose(rig, frame, transforms)
        targets["L"].location = left
        targets["R"].location = right
        targets["L"].keyframe_insert("location", frame=frame)
        targets["R"].keyframe_insert("location", frame=frame)

    for target in targets.values():
        if target.animation_data and target.animation_data.action:
            for slot in target.animation_data.action.slots:
                for layer in target.animation_data.action.layers:
                    for strip in layer.strips:
                        for bag in strip.channelbags:
                            if bag.slot_handle == slot.handle:
                                for curve in bag.fcurves:
                                    for point in curve.keyframe_points:
                                        point.interpolation = "BEZIER"

    # Blender 5.1's operator bake silently returned a static layered action in
    # headless mode. Sample each evaluated constrained pose explicitly, remove
    # IK, then key those final armature-space matrices into a portable action.
    sampled = {}
    for frame in range(1, 26):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        sampled[frame] = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    for side in ("L", "R"):
        shin = rig.pose.bones[f"shin.{side}"]
        for constraint in list(shin.constraints):
            if constraint.name.startswith("WalkPlantedFootIK"):
                shin.constraints.remove(constraint)
    target_actions = [
        target.animation_data.action
        for target in targets.values()
        if target.animation_data is not None and target.animation_data.action is not None
    ]
    for target in targets.values():
        bpy.data.objects.remove(target, do_unlink=True)
    for target_action in target_actions:
        if target_action.users == 0:
            bpy.data.actions.remove(target_action)
    rig.animation_data.action = None
    if source_action.users == 0:
        bpy.data.actions.remove(source_action)
    action = bpy.data.actions.new("Walk")
    rig.animation_data.action = action
    for frame in range(1, 26):
        bpy.context.scene.frame_set(frame)
        reset_pose(rig)
        for bone in rig.pose.bones:
            bone.matrix = sampled[frame][bone.name]
        bpy.context.view_layer.update()
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("scale", frame=frame, group=bone.name)
    action.name = "Walk"
    action.frame_start = 1
    action.frame_end = 25
    action.use_frame_range = True
    action.use_cyclic = True
    return action


def static_skill_pose(root_rot=(0.0, 0.0, 0.0), arms=True):
    result = {"pelvis": {"rot": root_rot}, "spine": {"rot": (-2.0, 0.0, 0.0)}, "chest": {"rot": (-3.0, 0.0, 0.0)}}
    if arms:
        result.update({
            "upper_arm.L": {"rot": (-22.0, -10.0, 18.0)}, "forearm.L": {"rot": (28.0, 0.0, 4.0)},
            "upper_arm.R": {"rot": (-22.0, 10.0, -18.0)}, "forearm.R": {"rot": (28.0, 0.0, -4.0)},
        })
    return result


def build_actions(rig, body):
    idle = make_action(rig, "Idle", idle_frames(), 61, True)
    walk = make_action(rig, "Walk", walk_frames(), 25, True)
    ground_walk_action(rig, body, walk)
    # Equipment loop aliases intentionally begin with the same stable base.
    for name in ("TorchIdle", "StaffIdle", "WarriorIdle"):
        make_action(rig, name, idle_frames(), 61, True)
    for name in ("TorchWalk", "StaffWalk", "WarriorWalk"):
        alias = walk.copy()
        alias.name = name
    jump = ((1, static_skill_pose()), (7, {"pelvis": {"loc": (0, 0, -0.035)}, "thigh.L": {"rot": (-18,0,0)}, "thigh.R": {"rot": (-18,0,0)}, "shin.L": {"rot": (42,0,0)}, "shin.R": {"rot": (42,0,0)}}), (13, {"pelvis": {"loc": (0,0,0.035)}, "thigh.L": {"rot": (12,0,0)}, "thigh.R": {"rot": (12,0,0)}, "shin.L": {"rot": (18,0,0)}, "shin.R": {"rot": (18,0,0)}}))
    make_action(rig, "Jump", jump, 13, False)
    make_action(rig, "Land", ((1, jump[-1][1]), (6, jump[1][1]), (12, static_skill_pose())), 12, False)
    make_action(rig, "Roll", ((1, static_skill_pose()), (8, {"root": {"rot": (-75,0,0)}, "pelvis": {"rot": (-35,0,0)}, "thigh.L": {"rot": (-55,0,0)}, "thigh.R": {"rot": (-55,0,0)}, "shin.L": {"rot": (80,0,0)}, "shin.R": {"rot": (80,0,0)}}), (16, {"root": {"rot": (-180,0,0)}, "pelvis": {"rot": (-20,0,0)}}), (25, static_skill_pose())), 25, False)
    for name in ("Spark", "Nova", "Blink", "Orb", "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb", "ShieldBash", "FishCast"):
        make_action(rig, name, ((1, static_skill_pose()), (8, static_skill_pose((-2, 2, 0))), (16, static_skill_pose())), 16, False)
    make_action(rig, "SwordSlash", ((1, static_skill_pose()), (7, {"chest": {"rot": (-4,-10,-8)}, "upper_arm.L": {"rot": (-42,-12,20)}, "forearm.L": {"rot": (62,0,10)}}), (13, {"chest": {"rot": (4,12,9)}, "upper_arm.L": {"rot": (24,8,-16)}, "forearm.L": {"rot": (18,0,-8)}}), (21, static_skill_pose())), 21, False)
    make_action(rig, "Death", ((1, static_skill_pose()), (15, {"root": {"rot": (-35,0,12)}, "pelvis": {"rot": (-18,0,8)}, "thigh.L": {"rot": (-15,0,0)}, "thigh.R": {"rot": (-15,0,0)}}), (31, {"root": {"rot": (-86,0,12)}, "pelvis": {"rot": (-8,0,0)}})), 31, False)
    rig.animation_data.action = None
    for action in bpy.data.actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_start), action)
        track.mute = True


def export(rig):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and (obj.name == "ConnectedBody" or obj.name.startswith(("Professional", "HeroHair", "Loincloth.", "ClothWaistCord", "RoyalArmor_", "RoyalStaff_"))):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    # Repeated review renders can leave a pose as the currently displayed
    # action.  Export all NLA actions from a deterministic clean rest state.
    rig.data.pose_position = "POSE"
    rig.animation_data.action = None
    reset_pose(rig)
    bpy.context.scene.frame_set(0)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB, export_format="GLB", use_selection=True, export_apply=False,
        export_animations=True, export_nla_strips=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=True,
        export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_yup=True,
    )


def validate(body, rig):
    required_bones = {"root", "pelvis", "spine", "chest", "neck", "head", "hand.L", "hand.R", "foot.L", "foot.R"}
    missing = required_bones - {bone.name for bone in rig.data.bones}
    if missing:
        raise RuntimeError(f"Missing runtime bones: {sorted(missing)}")
    required_actions = {"Idle", "Walk", "Jump", "Land", "Roll", "SwordSlash", "Death"}
    if not required_actions <= set(bpy.data.actions.keys()):
        raise RuntimeError("Required runtime actions missing")
    if len(body.data.vertices) < 50000:
        raise RuntimeError("Clean professional body was unexpectedly reduced")
    print(f"FULL_RUNTIME_CANDIDATE|verts={len(body.data.vertices)}|bones={len(rig.data.bones)}|actions={len(bpy.data.actions)}|height={body.dimensions.z:.5f}")


def main():
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    rig = bpy.data.objects["FullHeroPrototypeRig"]
    body = rename_rig(rig)
    clean_body(body, rig)
    bind_head_accessories(rig)
    create_loincloth(body, rig)
    clear_actions(rig)
    # clean_body temporarily enters REST so morphs/modifiers can be applied
    # safely. Grounding must evaluate the actual posed/deformed walk mesh.
    rig.data.pose_position = "POSE"
    build_actions(rig, body)
    validate(body, rig)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"FULL_RUNTIME_CANDIDATE_DONE|blend={OUTPUT_BLEND}|glb={OUTPUT_GLB}")


if __name__ == "__main__":
    main()
