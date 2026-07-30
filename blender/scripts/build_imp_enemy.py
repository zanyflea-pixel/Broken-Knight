"""Build, rig, animate, and export the Broken Knight imp enemy."""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "blender", "imp_enemy.blend")
GLB_OUT = os.path.join(ROOT, "godot", "assets", "enemies", "imp_enemy.glb")
RENDER_OUT = os.path.join(ROOT, "blender", "previews", "imp_enemy_preview.png")


def clear_scene():
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        pass


def material(name, color, roughness=0.78, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = 0.27
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = 3.5
    return mat


def apply_and_skin(obj, armature, bone_name, mat, smooth=True):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if smooth and obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("ImpRig", "ARMATURE")
    mod.object = armature
    obj.parent = armature
    obj.select_set(False)
    return obj


def ellipsoid(name, location, scale, mat, armature, bone, segments=32, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return apply_and_skin(obj, armature, bone, mat)


def cone_between(name, start, end, r1, r2, mat, armature, bone, vertices=20):
    start, end = Vector(start), Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=delta.length, location=(start + end) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return apply_and_skin(obj, armature, bone, mat)


def triangular_mesh(name, vertices, faces, mat, armature, bone):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return apply_and_skin(obj, armature, bone, mat, smooth=False)


def build_armature():
    data = bpy.data.armatures.new("ImpRig")
    arm = bpy.data.objects.new("ImpRig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specs = {
        "root": ((0, 0, 0.04), (0, 0, 0.70), None),
        "pelvis": ((0, 0, 0.66), (0, 0, 0.82), "root"),
        "spine": ((0, 0, 0.78), (0, 0, 1.02), "pelvis"),
        "chest": ((0, 0, 0.98), (0, -0.02, 1.18), "spine"),
        "neck": ((0, -0.01, 1.13), (0, -0.035, 1.23), "chest"),
        "head": ((0, -0.035, 1.20), (0, -0.06, 1.43), "neck"),
        "thigh.L": ((-0.17, 0, 0.73), (-0.27, -0.04, 0.43), "pelvis"),
        "shin.L": ((-0.27, -0.04, 0.43), (-0.21, -0.02, 0.16), "thigh.L"),
        "foot.L": ((-0.21, -0.02, 0.16), (-0.22, -0.27, 0.08), "shin.L"),
        "thigh.R": ((0.17, 0, 0.73), (0.27, -0.04, 0.43), "pelvis"),
        "shin.R": ((0.27, -0.04, 0.43), (0.21, -0.02, 0.16), "thigh.R"),
        "foot.R": ((0.21, -0.02, 0.16), (0.22, -0.27, 0.08), "shin.R"),
        "upper_arm.L": ((-0.24, -0.01, 1.08), (-0.44, -0.04, 0.80), "chest"),
        "forearm.L": ((-0.44, -0.04, 0.80), (-0.40, -0.16, 0.49), "upper_arm.L"),
        "hand.L": ((-0.40, -0.16, 0.49), (-0.38, -0.24, 0.36), "forearm.L"),
        "upper_arm.R": ((0.24, -0.01, 1.08), (0.44, -0.04, 0.80), "chest"),
        "forearm.R": ((0.44, -0.04, 0.80), (0.40, -0.16, 0.49), "upper_arm.R"),
        "hand.R": ((0.40, -0.16, 0.49), (0.38, -0.24, 0.36), "forearm.R"),
        "tail.1": ((0, 0.09, 0.72), (0, 0.36, 0.60), "pelvis"),
        "tail.2": ((0, 0.36, 0.60), (0.18, 0.56, 0.48), "tail.1"),
        "tail.3": ((0.18, 0.56, 0.48), (0.34, 0.52, 0.69), "tail.2"),
        "wing.L": ((-0.12, 0.08, 1.09), (-0.54, 0.18, 1.23), "chest"),
        "wing.R": ((0.12, 0.08, 1.09), (0.54, 0.18, 1.23), "chest"),
    }
    for name, (head, tail, parent) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="POSE")
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.select_set(False)
    return arm


def build_imp(arm):
    skin = material("Imp Skin", (0.30, 0.032, 0.018, 1), 0.90)
    skin_light = material("Imp Skin Highlights", (0.38, 0.060, 0.027, 1), 0.88)
    skin_dark = material("Imp Skin Shadow", (0.205, 0.014, 0.010, 1), 0.93)
    horn = material("Horn", (0.105, 0.067, 0.037, 1), 0.73)
    horn_tip = material("Horn Tips", (0.025, 0.018, 0.014, 1), 0.66)
    eye = material("Infernal Eyes", (0.62, 0.075, 0.008, 1), 0.48, emission=(0.72, 0.025, 0.002, 1))
    pupil = material("Eye Slits", (0.015, 0.004, 0.002, 1), 0.4)
    tooth = material("Fangs", (0.88, 0.72, 0.42, 1), 0.68)
    mouth = material("Mouth", (0.10, 0.004, 0.006, 1), 0.9)
    leather = material("Leather", (0.12, 0.048, 0.018, 1), 0.9)
    cloth = material("Ash Cloth", (0.11, 0.075, 0.058, 1), 1.0)
    metal = material("Iron", (0.15, 0.13, 0.115, 1), 0.52, 0.58)
    wing = material("Wing Membrane", (0.21, 0.025, 0.022, 1), 0.94)
    scar = material("Scars", (0.58, 0.16, 0.09, 1), 0.95)

    # Lean, hungry silhouette: narrow ribs and waist, long limbs, and visible
    # joints. Imps should read as wiry scavengers rather than miniature ogres.
    ellipsoid("Pelvis", (0, 0.015, 0.73), (0.18, 0.140, 0.20), skin, arm, "pelvis")
    ellipsoid("Belly", (0, -0.040, 0.87), (0.155, 0.125, 0.22), skin, arm, "spine")
    ellipsoid("WaistBridge", (0, -0.012, 0.79), (0.165, 0.132, 0.13), skin, arm, "pelvis")
    ellipsoid("Ribcage", (0, -0.015, 1.03), (0.235, 0.148, 0.24), skin, arm, "chest")
    ellipsoid("ChestPlane", (0, -0.154, 1.06), (0.174, 0.026, 0.125), skin, arm, "chest", 24, 16)
    ellipsoid("Neck", (0, -0.005, 1.17), (0.105, 0.10, 0.15), skin, arm, "neck")

    # Head, muzzle, cheek planes, brow, ears, and a readable snarling mouth.
    ellipsoid("Head", (0, -0.055, 1.34), (0.205, 0.165, 0.238), skin, arm, "head")
    ellipsoid("Muzzle", (0, -0.212, 1.285), (0.148, 0.082, 0.098), skin, arm, "head", 28, 18)
    ellipsoid("Jaw", (0, -0.190, 1.235), (0.130, 0.070, 0.075), skin, arm, "head", 26, 16)
    ellipsoid("Nose", (0, -0.282, 1.325), (0.082, 0.040, 0.052), skin_dark, arm, "head", 24, 14)
    for side in (-1, 1):
        ellipsoid(f"Cheek.{side}", (side * 0.122, -0.175, 1.28), (0.088, 0.054, 0.105), skin, arm, "head", 24, 14)
        ellipsoid(f"Brow.{side}", (side * 0.090, -0.210, 1.42), (0.105, 0.044, 0.041), skin_dark, arm, "head", 24, 12)
        ellipsoid(f"Eye.{side}", (side * 0.088, -0.224, 1.385), (0.055, 0.026, 0.037), eye, arm, "head", 24, 14)
        ellipsoid(f"Pupil.{side}", (side * 0.088, -0.248, 1.385), (0.009, 0.007, 0.027), pupil, arm, "head", 16, 10)
        ellipsoid(f"Nostril.{side}", (side * 0.030, -0.316, 1.326), (0.012, 0.009, 0.011), mouth, arm, "head", 16, 10)
        # Pointed swept ears.
        sx = side
        triangular_mesh(f"Ear.{side}", [(sx*.18,-.06,1.40),(sx*.48,-.02,1.43),(sx*.21,-.15,1.30),(sx*.18,-.06,1.40)], [(0,1,2)], skin_light, arm, "head")
        triangular_mesh(f"EarInner.{side}", [(sx*.205,-.07,1.385),(sx*.425,-.035,1.418),(sx*.225,-.13,1.325)], [(0,1,2)], skin_dark, arm, "head")
    ellipsoid("MouthGap", (0, -0.286, 1.245), (0.105, 0.015, 0.026), mouth, arm, "head", 28, 12)
    for side in (-1, 1):
        cone_between(f"Fang.{side}", (side*.064,-.306,1.265), (side*.064,-.310,1.208), .018, .004, tooth, arm, "head", 14)

    # Back-swept segmented horns with dark tips.
    for side in (-1, 1):
        cone_between(f"HornBase.{side}", (side*.13,.005,1.50), (side*.20,.07,1.65), .070, .050, horn, arm, "head")
        cone_between(f"HornMid.{side}", (side*.20,.07,1.65), (side*.26,.17,1.69), .050, .026, horn, arm, "head")
        cone_between(f"HornTip.{side}", (side*.26,.17,1.69), (side*.29,.27,1.64), .027, .003, horn_tip, arm, "head", 16)

    # Long sinewy arms, joined with oversized deltoids and clawed hands.
    arm_specs = {
        -1: ((-.24,-.01,1.08),(-.44,-.04,.80),(-.40,-.16,.49),(-.38,-.24,.37)),
         1: (( .24,-.01,1.08),( .44,-.04,.80),( .40,-.16,.49),( .38,-.24,.37)),
    }
    for side, (shoulder, elbow, wrist, palm) in arm_specs.items():
        suffix = "L" if side < 0 else "R"
        ellipsoid(f"Deltoid.{suffix}", shoulder, (.092,.090,.122), skin, arm, f"upper_arm.{suffix}", 24, 16)
        cone_between(f"UpperArm.{suffix}", shoulder, elbow, .088, .064, skin, arm, f"upper_arm.{suffix}")
        ellipsoid(f"Elbow.{suffix}", elbow, (.073,.070,.083), skin, arm, f"forearm.{suffix}", 22, 14)
        cone_between(f"Forearm.{suffix}", elbow, wrist, .075, .050, skin, arm, f"forearm.{suffix}")
        cone_between(f"WristBridge.{suffix}", wrist, palm, .052, .058, skin, arm, f"hand.{suffix}", 18)
        ellipsoid(f"Hand.{suffix}", palm, (.070,.066,.098), skin, arm, f"hand.{suffix}", 24, 16)
        for finger in range(3):
            x = palm[0] + side * (finger-1) * .027
            start=(x,palm[1]-.045,palm[2]-.035)
            end=(x+side*(finger-1)*.01,palm[1]-.115,palm[2]-.105-finger*.006)
            cone_between(f"Claw.{suffix}.{finger}", start, end, .018, .004, horn_tip, arm, f"hand.{suffix}", 12)

    # Crouched digitigrade legs, broad feet, and separate hooked claws.
    leg_specs = {
        -1: ((-.17,0,.73),(-.27,-.04,.43),(-.21,-.02,.16),(-.22,-.27,.08)),
         1: (( .17,0,.73),( .27,-.04,.43),( .21,-.02,.16),( .22,-.27,.08)),
    }
    for side, (hip, knee, ankle, toe) in leg_specs.items():
        suffix = "L" if side < 0 else "R"
        ellipsoid(f"Haunch.{suffix}", hip, (.115,.112,.158), skin, arm, f"thigh.{suffix}", 24, 16)
        cone_between(f"Thigh.{suffix}", hip, knee, .108, .078, skin, arm, f"thigh.{suffix}")
        ellipsoid(f"Knee.{suffix}", knee, (.083,.078,.088), skin, arm, f"shin.{suffix}", 22, 14)
        cone_between(f"Shin.{suffix}", knee, ankle, .078, .050, skin, arm, f"shin.{suffix}")
        cone_between(f"AnkleBridge.{suffix}", ankle, (toe[0],-.16,.10), .052, .062, skin_dark, arm, f"foot.{suffix}", 18)
        ellipsoid(f"Foot.{suffix}", (toe[0],-.18,.09), (.115,.18,.072), skin_dark, arm, f"foot.{suffix}", 26, 16)
        for digit in range(3):
            dx=(digit-1)*.055
            cone_between(f"ToeClaw.{suffix}.{digit}", (toe[0]+dx,-.30,.09), (toe[0]+dx*1.2,-.40,.06), .026, .004, horn_tip, arm, f"foot.{suffix}", 14)

    # Tail follows a readable S curve and ends in a classic spear point.
    cone_between("TailBase", (0,.08,.73), (0,.36,.60), .10, .075, skin_dark, arm, "tail.1")
    cone_between("TailMid", (0,.36,.60), (.18,.56,.48), .075, .050, skin, arm, "tail.2")
    cone_between("TailTip", (.18,.56,.48), (.34,.52,.69), .052, .023, skin_light, arm, "tail.3")
    triangular_mesh("TailSpear", [(.34,.52,.69),(.26,.51,.79),(.43,.51,.76),(.34,.52,.69),(.34,.63,.75)], [(0,1,2),(0,2,4),(0,4,1)], skin_dark, arm, "tail.3")

    # Small leathery wings: bony leading edges plus double-sided membranes.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        bone = f"wing.{suffix}"
        sx = side
        cone_between(f"WingBone.{suffix}", (sx*.11,.08,1.10), (sx*.55,.19,1.26), .035, .018, horn, arm, bone, 14)
        verts=[(sx*.12,.10,1.09),(sx*.55,.20,1.26),(sx*.46,.22,.92),(sx*.28,.18,.99)]
        # Materials export double-sided; reversed duplicate faces made the
        # consolidated mesh non-manifold and triggered a glTF validity warning.
        triangular_mesh(f"WingMembrane.{suffix}", verts, [(0,1,2),(0,2,3)], wing, arm, bone)
        cone_between(f"WingFinger.{suffix}", (sx*.55,.19,1.26), (sx*.46,.21,.92), .018, .008, horn, arm, bone, 12)

    # Belt, front/back ragged loincloth, iron buckle, scars and spine bumps.
    bpy.ops.mesh.primitive_torus_add(major_radius=.245, minor_radius=.026, major_segments=32, minor_segments=10, location=(0,0,.72))
    belt=bpy.context.object; belt.name="Belt"; apply_and_skin(belt,arm,"pelvis",leather)
    ellipsoid("Buckle", (0,-.242,.72), (.06,.025,.052), metal, arm, "pelvis", 20, 12)
    triangular_mesh("LoinFront", [(-.18,-.23,.70),(.18,-.23,.70),(.13,-.25,.42),(0,-.25,.34),(-.13,-.25,.42)], [(0,1,2),(0,2,3),(0,3,4)], cloth, arm, "pelvis")
    triangular_mesh("LoinBack", [(-.17,.20,.70),(.17,.20,.70),(.12,.22,.47),(0,.23,.40),(-.12,.22,.47)], [(0,2,1),(0,3,2),(0,4,3)], cloth, arm, "pelvis")
    for i in range(3):
        ellipsoid(f"SpineBump.{i}", (0,.185,1.02+i*.085), (.045,.038,.055), horn, arm, "chest", 18, 10)
    cone_between("ChestScar", (-.12,-.216,1.13), (.10,-.222,.96), .010, .007, scar, arm, "chest", 10)


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
            bone.rotation_euler = tuple(math.radians(v) for v in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
        if "scale" in values:
            bone.scale = values["scale"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def action(arm, name, keys, end_frame, cyclic=False):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    act.frame_start, act.frame_end = 1, end_frame
    # Blender 5 stores new actions in layered channel bags rather than exposing
    # the legacy Action.fcurves collection. Matching first/last poses provide
    # seamless loops in Godot; the import script controls playback looping.
    return act


def make_animations(arm):
    crouch={"pelvis":{"loc":(0,0,-.025)},"spine":{"rot":(7,0,0)},"chest":{"rot":(-5,0,0)},"head":{"rot":(6,0,0)},"upper_arm.L":{"rot":(0,0,-5)},"upper_arm.R":{"rot":(0,0,5)},"tail.2":{"rot":(0,5,0)},"tail.3":{"rot":(0,-8,0)}}
    breathe={**crouch,"chest":{"rot":(-7,1,0),"scale":(1.02,1.02,1.025)},"head":{"rot":(4,-3,1)},"wing.L":{"rot":(0,-3,-2)},"wing.R":{"rot":(0,3,2)},"tail.2":{"rot":(0,-8,4)},"tail.3":{"rot":(0,14,-5)}}
    idle=action(arm,"Idle",[(1,crouch),(18,breathe),(36,{**crouch,"head":{"rot":(7,5,-2)},"tail.2":{"rot":(0,10,-3)},"tail.3":{"rot":(0,-15,5)}}),(49,crouch)],49,True)

    run_keys=[]
    frames=[1,4,7,10,13,16,19]
    for i,frame in enumerate(frames):
        phase=i%6; left=1 if phase<3 else -1
        pose={"root":{"loc":(0,0,.015 if phase in (1,4) else -.02)},"pelvis":{"rot":(8,0,left*4)},"spine":{"rot":(12,0,-left*3)},"chest":{"rot":(-5,0,-left*5)},"head":{"rot":(-5,0,left*2)},
              "thigh.L":{"rot":(left*25,0,0)},"thigh.R":{"rot":(-left*25,0,0)},"shin.L":{"rot":(30 if left<0 else 5,0,0)},"shin.R":{"rot":(30 if left>0 else 5,0,0)},
              "upper_arm.L":{"rot":(-left*28,0,-4)},"upper_arm.R":{"rot":(left*28,0,4)},"forearm.L":{"rot":(-18,0,0)},"forearm.R":{"rot":(-18,0,0)},
              "tail.1":{"rot":(0,-left*6,0)},"tail.2":{"rot":(0,left*13,0)},"tail.3":{"rot":(0,-left*18,0)},"wing.L":{"rot":(0,0,-5)},"wing.R":{"rot":(0,0,5)}}
        run_keys.append((frame,pose))
    run=action(arm,"Run",run_keys,19,True)

    attack=action(arm,"Attack",[(1,crouch),(5,{"pelvis":{"rot":(8,0,-8)},"spine":{"rot":(10,0,-12)},"chest":{"rot":(-8,0,-18)},"upper_arm.R":{"rot":(-35,5,25)},"forearm.R":{"rot":(-55,0,0)},"head":{"rot":(3,8,0)},"tail.2":{"rot":(0,18,0)}}),(9,{"root":{"loc":(0,-.055,.025)},"pelvis":{"rot":(-5,0,12)},"spine":{"rot":(-6,0,15)},"chest":{"rot":(7,0,25)},"upper_arm.R":{"rot":(74,-5,-28)},"forearm.R":{"rot":(-6,0,0)},"hand.R":{"rot":(14,0,0)},"upper_arm.L":{"rot":(-30,0,-18)},"head":{"rot":(-7,-11,0)},"wing.L":{"rot":(0,0,-9)},"wing.R":{"rot":(0,0,9)}}),(12,{"root":{"loc":(0,-.025,.012)},"chest":{"rot":(2,0,-12)},"upper_arm.L":{"rot":(42,0,-20)},"forearm.L":{"rot":(-15,0,0)},"upper_arm.R":{"rot":(20,0,12)},"tail.2":{"rot":(0,-16,0)}}),(18,crouch)],18)
    hit=action(arm,"Hit",[(1,crouch),(3,{"root":{"loc":(0,.035,0)},"pelvis":{"rot":(-10,0,9)},"spine":{"rot":(-12,0,-7)},"chest":{"rot":(-16,0,-10)},"head":{"rot":(18,8,5)},"upper_arm.L":{"rot":(18,0,-15)},"upper_arm.R":{"rot":(-18,0,15)},"wing.L":{"rot":(0,0,-15)},"wing.R":{"rot":(0,0,15)}}),(9,crouch)],9)
    death=action(arm,"Death",[(1,crouch),(6,{"pelvis":{"rot":(-8,0,18)},"spine":{"rot":(-22,0,15)},"head":{"rot":(25,-15,8)},"upper_arm.L":{"rot":(35,0,-25)},"upper_arm.R":{"rot":(-25,0,20)}}),(13,{"root":{"loc":(0,.08,-.16),"rot":(-30,0,10)},"pelvis":{"rot":(-20,0,12)},"spine":{"rot":(-24,0,8)},"head":{"rot":(22,0,0)},"shin.L":{"rot":(48,0,0)},"shin.R":{"rot":(62,0,0)},"upper_arm.L":{"rot":(45,0,-20)},"upper_arm.R":{"rot":(-40,0,18)},"tail.2":{"rot":(0,22,0)}}),(22,{"root":{"loc":(0,.22,-.40),"rot":(-68,0,12)},"pelvis":{"rot":(-20,0,12)},"spine":{"rot":(-18,0,8)},"head":{"rot":(20,0,0)},"upper_arm.L":{"rot":(45,0,-20)},"upper_arm.R":{"rot":(-40,0,18)},"tail.2":{"rot":(0,22,0)},"wing.L":{"rot":(0,0,-20)},"wing.R":{"rot":(0,0,20)}}),(34,{"root":{"loc":(0,.25,-.47),"rot":(-76,0,10)},"head":{"rot":(12,0,0)},"tail.2":{"rot":(0,25,0)}})],34)

    arm.animation_data.action=None
    for act in (idle,run,attack,hit,death):
        track=arm.animation_data.nla_tracks.new();track.name=act.name;track.strips.new(act.name,int(act.frame_start),act)
    return [idle,run,attack,hit,death]


def setup_preview(arm):
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x=620;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG";scene.render.filepath=RENDER_OUT
    scene.world.color=(.012,.008,.009)
    bpy.ops.mesh.primitive_plane_add(size=8,location=(0,0,0))
    floor=bpy.context.object;floor.name="PreviewFloor"
    floor.data.materials.append(material("PreviewFloor",(.025,.018,.016,1),.95))
    bpy.ops.object.camera_add(location=(2.35,-4.8,2.15))
    camera=bpy.context.object;camera.name="PreviewCamera";scene.camera=camera
    direction=Vector((0,-.05,1.00))-camera.location
    camera.rotation_euler=direction.to_track_quat("-Z","Y").to_euler();camera.data.lens=58
    bpy.ops.object.light_add(type="AREA",location=(-2.1,-2.4,3.2));key=bpy.context.object;key.data.energy=950;key.data.color=(1.0,.34,.18);key.data.shape="DISK";key.data.size=3.0
    bpy.ops.object.light_add(type="AREA",location=(2.3,-.4,2.6));fill=bpy.context.object;fill.data.energy=700;fill.data.color=(.18,.30,1.0);fill.data.size=2.4
    bpy.ops.object.light_add(type="AREA",location=(0,2.0,2.7));rim=bpy.context.object;rim.data.energy=1000;rim.data.color=(1.0,.12,.04);rim.data.size=2.0
    arm.animation_data.action=bpy.data.actions["Idle"]
    scene.frame_set(18)
    os.makedirs(os.path.dirname(RENDER_OUT),exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for obj in (floor,camera,key,fill,rim): obj.hide_render=True


def consolidate_skinned_mesh(arm):
    """Merge rigid authored pieces into one skinned object for Godot.

    Vertex groups retain their bone names during Blender's join operation, so
    the silhouette and animation are unchanged while scene-node and draw-call
    overhead drops from roughly eighty mesh nodes to one skinned mesh.
    """
    parts=[obj for obj in bpy.context.scene.objects if obj.type=="MESH" and obj.parent==arm]
    if not parts:raise RuntimeError("No skinned imp meshes to consolidate")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    body=bpy.context.object;body.name="ImpBody"
    # Joining keeps the active object's armature modifier and merges all named
    # vertex groups from the other pieces.
    body.parent=arm
    return body


def export(arm):
    os.makedirs(os.path.dirname(GLB_OUT),exist_ok=True)
    arm.animation_data.action=None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH","ARMATURE"} and not obj.name.startswith("Preview"):
            obj.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.export_scene.gltf(filepath=GLB_OUT,export_format="GLB",use_selection=True,export_yup=True,export_animations=True,export_animation_mode="ACTIONS",export_merge_animation="ACTION",export_anim_single_armature=True,export_force_sampling=True,export_frame_range=False,export_skins=True,export_lights=False,export_cameras=False,export_apply=False)


clear_scene()
armature=build_armature()
build_imp(armature)
actions=make_animations(armature)
setup_preview(armature)
consolidate_skinned_mesh(armature)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
export(armature)
print("IMP_COMPLETE|blend=%s|glb=%s|preview=%s|animations=%s"%(BLEND_OUT,GLB_OUT,RENDER_OUT,",".join(a.name for a in actions)))
