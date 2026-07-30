"""Build, rig, animate, preview, and export the Ashfang Hound enemy.

One authored asset serves both adult pack leaders and smaller runts in Godot.
The model is a lean quadruped with charred hide, ember fissures, plated mane,
readable paws, jaws, teeth, and a complete five-action animation set.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "blender", "ashfang_hound.blend")
GLB_OUT = os.path.join(ROOT, "godot", "assets", "enemies", "ashfang_hound.glb")
PREVIEW_OUT = os.path.join(ROOT, "blender", "previews", "ashfang_hound_preview.png")


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=.82, metallic=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    mat["export_roughness"] = roughness
    mat["export_metallic"] = metallic
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = .24
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def skin(obj, arm, bone, mat, smooth=True):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("AshfangRig", "ARMATURE")
    modifier.object = arm
    obj.parent = arm
    obj.select_set(False)
    return obj


def ellipsoid(name, location, scale, mat, arm, bone, segments=28, rings=18):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return skin(obj, arm, bone, mat)


def cone_between(name, start, end, radius1, radius2, mat, arm, bone, vertices=18):
    start = Vector(start)
    end = Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=delta.length,
        location=(start + end) * .5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return skin(obj, arm, bone, mat)


def torus(name, location, major, minor, mat, arm, bone, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=30,
        minor_segments=10,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    return skin(obj, arm, bone, mat)


def build_armature():
    data = bpy.data.armatures.new("AshfangRig")
    arm = bpy.data.objects.new("AshfangRig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    specs = {
        "root": ((0, 0, .04), (0, 0, .54), None),
        "pelvis": ((0, .30, .54), (0, .18, .70), "root"),
        "spine": ((0, .22, .67), (0, -.15, .74), "pelvis"),
        "chest": ((0, -.12, .72), (0, -.44, .78), "spine"),
        "neck": ((0, -.42, .77), (0, -.65, .88), "chest"),
        "head": ((0, -.62, .87), (0, -.91, .91), "neck"),
        "jaw": ((0, -.76, .80), (0, -1.04, .78), "head"),
        "tail.1": ((0, .48, .63), (0, .78, .72), "pelvis"),
        "tail.2": ((0, .77, .72), (.08, 1.03, .80), "tail.1"),
        "tail.3": ((.08, 1.03, .80), (0, 1.26, .73), "tail.2"),
    }
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        specs.update({
            f"front_upper.{suffix}": ((side * .25, -.34, .70), (side * .28, -.40, .38), "chest"),
            f"front_lower.{suffix}": ((side * .28, -.40, .38), (side * .25, -.46, .14), f"front_upper.{suffix}"),
            f"front_paw.{suffix}": ((side * .25, -.46, .14), (side * .25, -.70, .09), f"front_lower.{suffix}"),
            f"hind_upper.{suffix}": ((side * .25, .34, .62), (side * .31, .47, .39), "pelvis"),
            f"hind_lower.{suffix}": ((side * .31, .47, .39), (side * .28, .25, .16), f"hind_upper.{suffix}"),
            f"hind_paw.{suffix}": ((side * .28, .25, .16), (side * .27, -.03, .09), f"hind_lower.{suffix}"),
        })
    for name, (head, tail, parent_name) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent_name:
            bone.parent = data.edit_bones[parent_name]
    bpy.ops.object.mode_set(mode="POSE")
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.select_set(False)
    return arm


def build_hound(arm):
    hide = material("Ashfang Charred Hide", (.048, .036, .032, 1), .94)
    hide_mid = material("Ashfang Hide Planes", (.105, .074, .057, 1), .90)
    hide_light = material("Ashfang Scarred Hide", (.19, .115, .075, 1), .86)
    mane = material("Ashfang Obsidian Mane", (.020, .025, .031, 1), .78, .16)
    ember = material("Ashfang Ember Fissures", (.42, .028, .004, 1), .48, .08, (1.0, .055, .004, 1), 3.2)
    eye = material("Ashfang Eyes", (.80, .13, .008, 1), .34, 0, (1.0, .07, .002, 1), 5.0)
    pupil = material("Ashfang Pupils", (.006, .002, .001, 1), .45)
    mouth = material("Ashfang Mouth", (.055, .003, .004, 1), .96)
    tooth = material("Ashfang Teeth", (.70, .58, .38, 1), .72)
    claw = material("Ashfang Claws", (.055, .045, .036, 1), .64)
    iron = material("Ashfang Collar Iron", (.075, .082, .090, 1), .48, .72)

    # Connected-looking lean torso masses with a deep chest and tucked waist.
    ellipsoid("AshfangPelvis", (0, .32, .62), (.30, .35, .27), hide, arm, "pelvis")
    ellipsoid("AshfangWaist", (0, .10, .65), (.255, .33, .24), hide_mid, arm, "spine")
    ellipsoid("AshfangRibcage", (0, -.22, .72), (.34, .42, .34), hide, arm, "chest")
    ellipsoid("AshfangBreast", (0, -.48, .68), (.31, .27, .37), hide_mid, arm, "chest")
    ellipsoid("AshfangNeck", (0, -.57, .80), (.235, .29, .265), hide, arm, "neck")

    # Predatory head, working jaw, nostrils, brow planes, ears, and teeth.
    ellipsoid("AshfangSkull", (0, -.78, .90), (.255, .29, .25), hide, arm, "head")
    ellipsoid("AshfangMuzzle", (0, -1.015, .84), (.205, .19, .145), hide_mid, arm, "head")
    ellipsoid("AshfangJaw", (0, -.985, .765), (.188, .175, .090), hide_light, arm, "jaw")
    ellipsoid("AshfangMouthGap", (0, -1.115, .795), (.145, .025, .040), mouth, arm, "jaw", 24, 12)
    ellipsoid("AshfangNose", (0, -1.185, .865), (.115, .075, .068), mane, arm, "head", 24, 14)
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        ellipsoid(f"AshfangCheek{suffix}", (side * .155, -.925, .83), (.105, .105, .13), hide_mid, arm, "head")
        ellipsoid(f"AshfangBrow{suffix}", (side * .105, -.990, .975), (.125, .055, .052), mane, arm, "head", 22, 12)
        ellipsoid(f"AshfangEye{suffix}", (side * .105, -1.025, .945), (.052, .027, .042), eye, arm, "head", 20, 12)
        ellipsoid(f"AshfangPupil{suffix}", (side * .105, -1.051, .945), (.009, .006, .027), pupil, arm, "head", 14, 8)
        ellipsoid(f"AshfangNostril{suffix}", (side * .040, -1.253, .872), (.018, .010, .013), mouth, arm, "head", 12, 8)
        cone_between(
            f"AshfangEar{suffix}",
            (side * .16, -.70, 1.04),
            (side * .25, -.58, 1.34),
            .105,
            .012,
            hide_mid,
            arm,
            "head",
            18,
        )
        cone_between(
            f"AshfangEarCore{suffix}",
            (side * .17, -.71, 1.05),
            (side * .235, -.60, 1.285),
            .060,
            .006,
            ember,
            arm,
            "head",
            14,
        )
        for fang_index, x_offset in enumerate((.070, .125)):
            cone_between(
                f"AshfangFang{suffix}{fang_index}",
                (side * x_offset, -1.125, .820),
                (side * x_offset, -1.140, .745),
                .018,
                .003,
                tooth,
                arm,
                "jaw",
                12,
            )

    # Layered obsidian mane plates grow from the shoulders into the skull.
    for index, (y, z, height) in enumerate((
        (.22, .88, .22), (.06, .96, .27), (-.10, 1.03, .29),
        (-.27, 1.08, .27), (-.43, 1.10, .23), (-.59, 1.11, .18),
    )):
        cone_between(
            f"AshfangManePlate{index}",
            (0, y, z),
            (0, y + .025, z + height),
            .095 - index * .006,
            .008,
            mane,
            arm,
            "chest" if index < 4 else "neck",
            16,
        )

    # Four articulated legs with visible joint masses, broad pads, and claws.
    leg_data = {
        "front": {
            "L": ((-.25, -.34, .70), (-.28, -.40, .38), (-.25, -.46, .14), (-.25, -.60, .09)),
            "R": ((.25, -.34, .70), (.28, -.40, .38), (.25, -.46, .14), (.25, -.60, .09)),
        },
        "hind": {
            "L": ((-.25, .34, .62), (-.31, .47, .39), (-.28, .25, .16), (-.27, .04, .09)),
            "R": ((.25, .34, .62), (.31, .47, .39), (.28, .25, .16), (.27, .04, .09)),
        },
    }
    for pair, sides in leg_data.items():
        for suffix, (hip, knee, ankle, paw) in sides.items():
            upper = f"{pair}_upper.{suffix}"
            lower = f"{pair}_lower.{suffix}"
            paw_bone = f"{pair}_paw.{suffix}"
            ellipsoid(f"Ashfang{pair.title()}Shoulder{suffix}", hip, (.145, .155, .17), hide_mid, arm, upper)
            cone_between(f"Ashfang{pair.title()}Upper{suffix}", hip, knee, .115, .080, hide, arm, upper)
            ellipsoid(f"Ashfang{pair.title()}Joint{suffix}", knee, (.090, .092, .092), hide_light, arm, lower)
            cone_between(f"Ashfang{pair.title()}Lower{suffix}", knee, ankle, .082, .050, hide, arm, lower)
            ellipsoid(f"Ashfang{pair.title()}Paw{suffix}", paw, (.125, .20, .070), hide_mid, arm, paw_bone, 24, 14)
            for claw_index in range(3):
                dx = (claw_index - 1) * .055
                cone_between(
                    f"Ashfang{pair.title()}Claw{suffix}{claw_index}",
                    (paw[0] + dx, paw[1] - .12, paw[2] + .005),
                    (paw[0] + dx * 1.12, paw[1] - .25, paw[2] - .015),
                    .020,
                    .0025,
                    claw,
                    arm,
                    paw_bone,
                    12,
                )

    # Flexible tail with an ember-lit spear of fur at the tip.
    cone_between("AshfangTailBase", (0, .47, .63), (0, .78, .72), .115, .085, hide, arm, "tail.1")
    cone_between("AshfangTailMid", (0, .78, .72), (.08, 1.03, .80), .086, .052, hide_mid, arm, "tail.2")
    cone_between("AshfangTailTip", (.08, 1.03, .80), (0, 1.27, .73), .055, .010, mane, arm, "tail.3")
    ellipsoid("AshfangTailEmber", (0, 1.25, .735), (.045, .075, .045), ember, arm, "tail.3", 18, 10)

    # Surface-seated ember fissures and a scavenged iron collar.
    for side in (-1, 1):
        for index, (y, z) in enumerate(((-.38, .82), (-.17, .87), (.05, .80))):
            cone_between(
                f"AshfangFissure{side}_{index}",
                (side * .295, y - .07, z + .05),
                (side * .315, y + .07, z - .05),
                .012,
                .007,
                ember,
                arm,
                "chest" if y < 0 else "spine",
                10,
            )
    torus("AshfangCollar", (0, -.59, .82), .245, .025, iron, arm, "neck", rotation=(math.pi / 2, 0, 0))
    for side in (-1, 1):
        cone_between(
            f"AshfangCollarSpike{side}",
            (side * .17, -.61, .92),
            (side * .27, -.63, 1.00),
            .030,
            .002,
            iron,
            arm,
            "neck",
            12,
        )


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def key_pose(arm, frame, transforms):
    reset_pose(arm)
    for name, values in transforms.items():
        bone = arm.pose.bones[name]
        if "rot" in values:
            bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
        if "scale" in values:
            bone.scale = values["scale"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def make_action(arm, name, keys, end_frame):
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    action.frame_start = 1
    action.frame_end = end_frame
    return action


def make_animations(arm):
    alert = {
        "pelvis": {"rot": (2, 0, 0)},
        "spine": {"rot": (-2, 0, 0)},
        "chest": {"rot": (3, 0, 0)},
        "neck": {"rot": (-4, 0, 0)},
        "head": {"rot": (3, 0, 0)},
        "jaw": {"rot": (4, 0, 0)},
        "tail.1": {"rot": (0, -5, 0)},
        "tail.2": {"rot": (0, 10, 0)},
        "tail.3": {"rot": (0, -12, 0)},
    }
    breathe = {
        **alert,
        "chest": {"rot": (1, 1, 0), "scale": (1.015, 1.018, 1.02)},
        "head": {"rot": (1, -4, 2)},
        "jaw": {"rot": (7, 0, 0)},
        "tail.1": {"rot": (0, 7, 0)},
        "tail.2": {"rot": (0, -13, 0)},
        "tail.3": {"rot": (0, 18, 0)},
    }
    idle = make_action(arm, "Idle", [(1, alert), (20, breathe), (38, {**alert, "head": {"rot": (2, 5, -2)}}), (49, alert)], 49)

    run_keys = []
    frames = (1, 4, 7, 10, 13, 16, 19, 22, 25)
    for phase, frame in enumerate(frames):
        cycle = phase % 8
        lead = 1 if cycle < 4 else -1
        down = cycle in (1, 5)
        pose = {
            "root": {"loc": (0, .018 if down else -.012, 0)},
            "pelvis": {"rot": (4, lead * 2, lead * 2)},
            "spine": {"rot": (-5, -lead * 2, -lead * 2)},
            "chest": {"rot": (6, lead * 2, lead * 3)},
            "neck": {"rot": (-8, -lead * 2, -lead * 2)},
            "head": {"rot": (5, lead * 2, 0)},
            "jaw": {"rot": (6, 0, 0)},
            "front_upper.L": {"rot": (lead * 30, 0, 0)},
            "front_upper.R": {"rot": (-lead * 30, 0, 0)},
            "front_lower.L": {"rot": (28 if lead < 0 else 7, 0, 0)},
            "front_lower.R": {"rot": (28 if lead > 0 else 7, 0, 0)},
            "hind_upper.L": {"rot": (-lead * 28, 0, 0)},
            "hind_upper.R": {"rot": (lead * 28, 0, 0)},
            "hind_lower.L": {"rot": (34 if lead > 0 else 8, 0, 0)},
            "hind_lower.R": {"rot": (34 if lead < 0 else 8, 0, 0)},
            "tail.1": {"rot": (0, -lead * 8, 0)},
            "tail.2": {"rot": (0, lead * 16, 0)},
            "tail.3": {"rot": (0, -lead * 22, 0)},
        }
        run_keys.append((frame, pose))
    run = make_action(arm, "Run", run_keys, 25)

    attack = make_action(arm, "Attack", [
        (1, alert),
        (4, {
            "root": {"loc": (0, -.035, .025)},
            "pelvis": {"rot": (9, 0, 0)}, "spine": {"rot": (7, 0, 0)},
            "chest": {"rot": (10, 0, 0)}, "neck": {"rot": (-18, 0, 0)},
            "head": {"rot": (-12, 0, 0)}, "jaw": {"rot": (24, 0, 0)},
            "front_upper.L": {"rot": (-18, 0, -3)}, "front_upper.R": {"rot": (-18, 0, 3)},
            "hind_upper.L": {"rot": (14, 0, 0)}, "hind_upper.R": {"rot": (14, 0, 0)},
        }),
        (8, {
            "root": {"loc": (0, .020, -.12)},
            "pelvis": {"rot": (-7, 0, 0)}, "spine": {"rot": (-11, 0, 0)},
            "chest": {"rot": (-16, 0, 0)}, "neck": {"rot": (20, 0, 0)},
            "head": {"rot": (17, 0, 0)}, "jaw": {"rot": (38, 0, 0)},
            "front_upper.L": {"rot": (24, 0, -3)}, "front_upper.R": {"rot": (24, 0, 3)},
            "hind_upper.L": {"rot": (-12, 0, 0)}, "hind_upper.R": {"rot": (-12, 0, 0)},
        }),
        (12, {**alert, "jaw": {"rot": (14, 0, 0)}}),
        (18, alert),
    ], 18)
    hit = make_action(arm, "Hit", [
        (1, alert),
        (3, {
            "root": {"loc": (0, .025, .04)}, "pelvis": {"rot": (-10, 0, 8)},
            "spine": {"rot": (-13, 0, -9)}, "chest": {"rot": (-16, 0, -12)},
            "neck": {"rot": (14, 0, 8)}, "head": {"rot": (20, -7, 8)},
            "jaw": {"rot": (18, 0, 0)}, "tail.1": {"rot": (0, 18, 0)},
        }),
        (9, alert),
    ], 9)
    death = make_action(arm, "Death", [
        (1, alert),
        (7, {
            "root": {"loc": (0, .05, .02)}, "pelvis": {"rot": (-12, 0, 16)},
            "spine": {"rot": (-20, 0, -14)}, "chest": {"rot": (-28, 0, -18)},
            "neck": {"rot": (20, 0, 10)}, "head": {"rot": (25, 0, 12)},
            "front_upper.L": {"rot": (30, 0, -12)}, "front_upper.R": {"rot": (-20, 0, 14)},
        }),
        (16, {
            "root": {"loc": (0, .18, -.25), "rot": (-44, 0, -28)},
            "pelvis": {"rot": (-18, 0, -14)}, "spine": {"rot": (-22, 0, -12)},
            "chest": {"rot": (-30, 0, -10)}, "neck": {"rot": (18, 0, 8)},
            "head": {"rot": (22, 0, 12)}, "jaw": {"rot": (16, 0, 0)},
            "front_upper.L": {"rot": (45, 0, -18)}, "front_upper.R": {"rot": (-35, 0, 20)},
            "hind_upper.L": {"rot": (32, 0, -10)}, "hind_upper.R": {"rot": (-28, 0, 12)},
        }),
        (27, {
            "root": {"loc": (0, .28, -.52), "rot": (-78, 0, -34)},
            "head": {"rot": (15, 0, 8)}, "jaw": {"rot": (10, 0, 0)},
            "tail.1": {"rot": (0, 20, 0)}, "tail.2": {"rot": (0, -30, 0)},
        }),
        (35, {
            "root": {"loc": (0, .30, -.55), "rot": (-80, 0, -34)},
            "head": {"rot": (12, 0, 6)}, "tail.2": {"rot": (0, -32, 0)},
        }),
    ], 35)

    arm.animation_data.action = None
    for action in (idle, run, attack, hit, death):
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_start), action)
        strip.mute = True
    return [idle, run, attack, hit, death]


def setup_preview(arm):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 760
    scene.render.resolution_y = 620
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = PREVIEW_OUT
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.world.color = (.006, .008, .012)
    bpy.ops.mesh.primitive_plane_add(size=7, location=(0, 0, -.005))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(material("Ashfang Preview Floor", (.025, .028, .034, 1), .94))
    bpy.ops.object.camera_add(location=(2.65, -4.3, 1.68))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 60
    camera.rotation_euler = (Vector((0, -.15, .66)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    for name, location, energy, color, size in (
        ("PreviewKey", (-2.2, -2.5, 3.0), 850, (1.0, .28, .10), 3.0),
        ("PreviewFill", (2.5, -1.0, 2.1), 620, (.16, .28, 1.0), 2.6),
        ("PreviewRim", (0, 2.5, 2.6), 900, (1.0, .06, .01), 2.4),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.size = size
        light.rotation_euler = (Vector((0, -.05, .72)) - light.location).to_track_quat("-Z", "Y").to_euler()
    arm.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(20)
    os.makedirs(os.path.dirname(PREVIEW_OUT), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for obj in scene.objects:
        if obj.name.startswith("Preview"):
            obj.hide_render = True


def consolidate(arm):
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.parent == arm]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "AshfangBody"
    body.parent = arm
    return body


def export_asset(arm):
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "ARMATURE"} and not obj.name.startswith("Preview"):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_lights=False,
        export_cameras=False,
        export_apply=False,
    )


clear_scene()
armature = build_armature()
build_hound(armature)
actions = make_animations(armature)
setup_preview(armature)
consolidate(armature)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
export_asset(armature)
print(
    "ASHFANG_COMPLETE|blend=%s|glb=%s|preview=%s|animations=%s"
    % (BLEND_OUT, GLB_OUT, PREVIEW_OUT, ",".join(action.name for action in actions))
)
