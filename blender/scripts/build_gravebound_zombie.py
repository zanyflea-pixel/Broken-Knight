"""Author, rig, animate and export the original Gravebound zombie family base.

The asset is deliberately independent of the hero.  Overlapping anatomical
forms are consolidated to one skinned mesh at export; there are no loose body
parts or floating damage decals.  Godot adds variant equipment (runner,
graveguard, carrier and champion) to this common animated base.
"""

import math
import os
import random
import struct
import wave

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "blender", "gravebound_zombie.blend")
GLB_OUT = os.path.join(ROOT, "godot", "assets", "enemies", "gravebound_zombie.glb")
PREVIEW_OUT = os.path.join(ROOT, "blender", "previews", "gravebound_zombie_preview.png")
AUDIO_OUT = os.path.join(ROOT, "godot", "assets", "audio", "gravebound")


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=.84, metallic=0.0, emission=None, strength=0.0):
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Specular IOR Level"].default_value = .22
    if emission is not None:
        shader.inputs["Emission Color"].default_value = emission
        shader.inputs["Emission Strength"].default_value = strength
    return result


def skin(obj, armature, bone_name, mat, smooth=True):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if smooth and obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("GraveboundRig", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.select_set(False)
    return obj


def ellipsoid(name, location, scale, mat, armature, bone, segments=28, rings=18):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return skin(obj, armature, bone, mat)


def cone_between(name, start, end, r1, r2, mat, armature, bone, vertices=18):
    start, end = Vector(start), Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2,
                                   depth=delta.length, location=(start + end) * .5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return skin(obj, armature, bone, mat)


def mesh_piece(name, vertices, faces, mat, armature, bone):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return skin(obj, armature, bone, mat, False)


def build_armature():
    data = bpy.data.armatures.new("GraveboundRig")
    arm = bpy.data.objects.new("GraveboundRig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    specs = {
        "root": ((0, 0, .03), (0, 0, .88), None),
        "pelvis": ((0, 0, .87), (0, 0, 1.09), "root"),
        "spine": ((0, 0, 1.04), (0, -.015, 1.43), "pelvis"),
        "chest": ((0, -.015, 1.39), (0, -.04, 1.71), "spine"),
        "neck": ((0, -.04, 1.67), (0, -.07, 1.82), "chest"),
        "head": ((0, -.07, 1.79), (0, -.10, 2.11), "neck"),
        "thigh.L": ((-.20, 0, .94), (-.24, -.06, .55), "pelvis"),
        "shin.L": ((-.24, -.06, .55), (-.21, .01, .16), "thigh.L"),
        "foot.L": ((-.21, .01, .16), (-.22, -.28, .08), "shin.L"),
        "thigh.R": ((.20, 0, .94), (.24, -.06, .55), "pelvis"),
        "shin.R": ((.24, -.06, .55), (.21, .01, .16), "thigh.R"),
        "foot.R": ((.21, .01, .16), (.22, -.28, .08), "shin.R"),
        "upper_arm.L": ((-.28, -.02, 1.59), (-.54, -.06, 1.29), "chest"),
        "forearm.L": ((-.54, -.06, 1.29), (-.58, -.16, .96), "upper_arm.L"),
        "hand.L": ((-.58, -.16, .96), (-.60, -.25, .78), "forearm.L"),
        "upper_arm.R": ((.28, -.02, 1.59), (.54, -.06, 1.29), "chest"),
        "forearm.R": ((.54, -.06, 1.29), (.58, -.16, .96), "upper_arm.R"),
        "hand.R": ((.58, -.16, .96), (.60, -.25, .78), "forearm.R"),
        "jaw": ((0, -.13, 1.91), (0, -.24, 1.82), "head"),
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


def build_zombie(arm):
    skin_base = material("Gravebound Mottled Skin", (.205, .255, .155, 1), .96)
    skin_pale = material("Gravebound Pallor", (.315, .35, .225, 1), .94)
    skin_dark = material("Gravebound Rot", (.105, .135, .072, 1), .98)
    wound = material("Dried Wounds", (.245, .035, .026, 1), .92)
    bone = material("Exposed Bone", (.63, .57, .40, 1), .82)
    eye = material("Dead Eye", (.58, .70, .29, 1), .38, emission=(.30, .52, .08, 1), strength=1.2)
    pupil = material("Sunken Socket", (.012, .015, .009, 1), .99)
    mouth = material("Dead Mouth", (.055, .012, .012, 1), .99)
    cloth = material("Mildewed Linen", (.20, .18, .115, 1), 1.0)
    cloth_dark = material("Torn Grave Cloth", (.105, .095, .063, 1), 1.0)
    leather = material("Rotten Belt", (.105, .052, .020, 1), .96)
    iron = material("Burial Iron", (.11, .13, .125, 1), .58, .52)

    # Every anatomical mass overlaps its neighbour.  After consolidation this
    # reads as one complete corpse rather than a kit of floating primitives.
    ellipsoid("Pelvis", (0, .01, .98), (.245, .185, .245), skin_dark, arm, "pelvis")
    ellipsoid("Abdomen", (0, -.015, 1.22), (.235, .17, .31), skin_base, arm, "spine")
    ellipsoid("Ribcage", (0, -.02, 1.49), (.315, .205, .32), skin_pale, arm, "chest")
    ellipsoid("Sternum", (0, -.202, 1.48), (.185, .035, .22), skin_base, arm, "chest", 24, 14)
    ellipsoid("Neck", (0, -.04, 1.73), (.125, .115, .18), skin_dark, arm, "neck")
    ellipsoid("Skull", (0, -.07, 1.96), (.225, .19, .27), skin_pale, arm, "head")
    ellipsoid("Brow", (0, -.235, 2.045), (.175, .045, .070), skin_dark, arm, "head")
    ellipsoid("Muzzle", (0, -.235, 1.925), (.155, .075, .115), skin_base, arm, "head")
    ellipsoid("Jaw", (0, -.205, 1.825), (.145, .075, .095), skin_dark, arm, "jaw")
    ellipsoid("MouthGap", (0, -.285, 1.845), (.11, .018, .034), mouth, arm, "jaw", 22, 10)
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        ellipsoid("Socket." + suffix, (side*.090, -.243, 2.015), (.070, .025, .052), pupil, arm, "head", 20, 12)
        ellipsoid("Eye." + suffix, (side*.090, -.266, 2.008), (.036, .014, .028), eye, arm, "head", 16, 10)
        ellipsoid("Cheek." + suffix, (side*.125, -.19, 1.91), (.085, .050, .105), skin_base, arm, "head", 20, 12)
        # Torn ears remain physically seated in the skull.
        sx = side
        mesh_piece("TornEar." + suffix,
                   [(sx*.16,-.05,2.02),(sx*.34,-.02,2.01),(sx*.24,-.10,1.88)],
                   [(0,1,2)], skin_dark, arm, "head")
        cone_between("Tooth." + suffix, (side*.055,-.301,1.86), (side*.055,-.303,1.815), .015, .004, bone, arm, "jaw", 12)

    limb_specs = {
        "L": ((-.27,-.02,1.58),(-.54,-.06,1.29),(-.58,-.16,.96),(-.60,-.25,.80),
              (-.20,0,.96),(-.24,-.06,.55),(-.21,.01,.16),(-.22,-.26,.08)),
        "R": ((.27,-.02,1.58),(.54,-.06,1.29),(.58,-.16,.96),(.60,-.25,.80),
              (.20,0,.96),(.24,-.06,.55),(.21,.01,.16),(.22,-.26,.08)),
    }
    for suffix, points in limb_specs.items():
        shoulder, elbow, wrist, palm, hip, knee, ankle, toe = points
        ellipsoid("Shoulder."+suffix, shoulder, (.13,.12,.15), skin_base, arm, "upper_arm."+suffix, 22, 14)
        cone_between("UpperArm."+suffix, shoulder, elbow, .115, .085, skin_base, arm, "upper_arm."+suffix)
        ellipsoid("Elbow."+suffix, elbow, (.095,.085,.095), skin_dark, arm, "forearm."+suffix, 20, 12)
        cone_between("Forearm."+suffix, elbow, wrist, .09, .065, skin_pale, arm, "forearm."+suffix)
        cone_between("WristBridge."+suffix, wrist, palm, .067, .073, skin_dark, arm, "hand."+suffix, 16)
        ellipsoid("Hand."+suffix, palm, (.095,.085,.13), skin_dark, arm, "hand."+suffix, 20, 12)
        side = -1 if suffix == "L" else 1
        for finger in range(3):
            fx = palm[0] + (finger-1)*.045
            cone_between("Finger.%s.%d"%(suffix,finger), (fx,palm[1]-.02,palm[2]),
                         (fx+side*(finger-1)*.012,palm[1]-.115,palm[2]-.10), .021, .008,
                         bone if finger == 2 else skin_dark, arm, "hand."+suffix, 12)
        ellipsoid("Hip."+suffix, hip, (.145,.13,.18), skin_dark, arm, "thigh."+suffix, 22, 14)
        cone_between("Thigh."+suffix, hip, knee, .135, .105, skin_base, arm, "thigh."+suffix)
        ellipsoid("Knee."+suffix, knee, (.115,.105,.11), skin_dark, arm, "shin."+suffix, 20, 12)
        cone_between("Shin."+suffix, knee, ankle, .105, .070, skin_pale, arm, "shin."+suffix)
        ellipsoid("Foot."+suffix, (toe[0],-.15,.09), (.14,.22,.085), skin_dark, arm, "foot."+suffix, 22, 12)
        for digit in range(3):
            dx=(digit-1)*.060
            cone_between("Toe.%s.%d"%(suffix,digit),(toe[0]+dx,-.28,.09),(toe[0]+dx,-.38,.055),.024,.004,bone,arm,"foot."+suffix,12)

    # Wounds are embedded in the surface rather than hovering decals.
    ellipsoid("SunkenChestWound", (-.12,-.225,1.51), (.09,.016,.14), wound, arm, "chest", 18, 10)
    ellipsoid("ExposedRib", (-.14,-.242,1.52), (.022,.012,.15), bone, arm, "chest", 14, 8)
    ellipsoid("TempleRot", (.15,-.19,2.03), (.075,.025,.085), wound, arm, "head", 18, 10)
    ellipsoid("ForearmBone", (-.59,-.18,1.05), (.030,.024,.115), bone, arm, "forearm.L", 14, 8)

    # A complete but damaged burial tunic: front, back, shoulders and side
    # panels overlap the torso, with an uneven torn hem and bound belt.
    mesh_piece("TunicFront",
               [(-.30,-.222,1.64),(.30,-.222,1.64),(.265,-.214,1.09),(.09,-.225,1.02),(-.02,-.222,1.09),(-.15,-.225,1.01),(-.28,-.214,1.11)],
               [(0,1,2),(0,2,3),(0,3,4),(0,4,5),(0,5,6)], cloth, arm, "chest")
    mesh_piece("TunicBack",
               [(-.30,.19,1.64),(.30,.19,1.64),(.27,.17,1.10),(.08,.18,1.02),(-.09,.18,1.10),(-.26,.17,1.04)],
               [(0,2,1),(0,3,2),(0,4,3),(0,5,4)], cloth_dark, arm, "chest")
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        mesh_piece("TunicSide."+suffix,
                   [(side*.30,-.21,1.62),(side*.30,.18,1.62),(side*.26,.16,1.10),(side*.27,-.20,1.09)],
                   [(0,1,2),(0,2,3)], cloth_dark, arm, "chest")
        ellipsoid("Sleeve."+suffix,(side*.34,-.025,1.53),(.16,.14,.17),cloth,arm,"upper_arm."+suffix,20,12)
    bpy.ops.mesh.primitive_torus_add(major_radius=.275, minor_radius=.030, major_segments=28, minor_segments=9, location=(0,0,1.08))
    belt=bpy.context.object;belt.name="RottenBelt";skin(belt,arm,"pelvis",leather)
    ellipsoid("BeltClasp", (0,-.276,1.08), (.06,.026,.055), iron, arm, "pelvis", 18, 10)


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def key_pose(arm, frame, transforms):
    reset_pose(arm)
    for name, values in transforms.items():
        pose_bone = arm.pose.bones[name]
        if "rot" in values:
            pose_bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        if "loc" in values:
            pose_bone.location = values["loc"]
        if "scale" in values:
            pose_bone.scale = values["scale"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def action(arm, name, keys, end_frame):
    result = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = result
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    result.frame_start, result.frame_end = 1, end_frame
    return result


def make_animations(arm):
    idle_pose={"pelvis":{"loc":(0,0,-.03),"rot":(5,0,3)},"spine":{"rot":(10,0,-4)},"chest":{"rot":(-8,0,5)},"neck":{"rot":(13,0,-4)},"head":{"rot":(-8,0,7)},"jaw":{"rot":(9,0,0)},"upper_arm.L":{"rot":(8,0,-14)},"forearm.L":{"rot":(-22,0,0)},"upper_arm.R":{"rot":(-5,0,17)},"forearm.R":{"rot":(-30,0,0)}}
    breath={**idle_pose,"chest":{"rot":(-11,2,4),"scale":(1.01,1.01,1.025)},"head":{"rot":(-3,-7,8)},"jaw":{"rot":(17,0,0)},"upper_arm.R":{"rot":(-11,0,20)}}
    idle=action(arm,"Idle",[(1,idle_pose),(27,breath),(54,{**idle_pose,"head":{"rot":(-13,9,4)}}),(73,idle_pose)],73)

    walk_keys=[]
    for index, frame in enumerate([1,8,15,22,29,36,43]):
        side=1 if index%2==0 else -1
        walk_keys.append((frame,{"root":{"loc":(0,0,.015 if index%2 else -.012)},"pelvis":{"rot":(6,0,side*4)},"spine":{"rot":(11,0,-side*4)},"head":{"rot":(-9,0,side*3)},"thigh.L":{"rot":(side*22,0,0)},"thigh.R":{"rot":(-side*22,0,0)},"shin.L":{"rot":(18 if side<0 else 3,0,0)},"shin.R":{"rot":(18 if side>0 else 3,0,0)},"upper_arm.L":{"rot":(-side*14,0,-12)},"upper_arm.R":{"rot":(side*14,0,15)},"forearm.L":{"rot":(-20,0,0)},"forearm.R":{"rot":(-28,0,0)}}))
    walk=action(arm,"Walk",walk_keys,43)

    run_keys=[]
    for index, frame in enumerate([1,5,9,13,17,21,25]):
        side=1 if index%2==0 else -1
        run_keys.append((frame,{"root":{"loc":(0,0,.025 if index%2 else -.025)},"pelvis":{"rot":(14,0,side*6)},"spine":{"rot":(18,0,-side*7)},"chest":{"rot":(-7,0,-side*6)},"head":{"rot":(-16,0,side*4)},"thigh.L":{"rot":(side*34,0,0)},"thigh.R":{"rot":(-side*34,0,0)},"shin.L":{"rot":(38 if side<0 else 4,0,0)},"shin.R":{"rot":(38 if side>0 else 4,0,0)},"upper_arm.L":{"rot":(-side*28,0,-15)},"upper_arm.R":{"rot":(side*28,0,18)},"forearm.L":{"rot":(-36,0,0)},"forearm.R":{"rot":(-38,0,0)}}))
    run=action(arm,"Run",run_keys,25)
    attack=action(arm,"Attack",[(1,idle_pose),(7,{"pelvis":{"rot":(4,0,-14)},"spine":{"rot":(8,0,-20)},"chest":{"rot":(-12,0,-24)},"upper_arm.R":{"rot":(-48,8,32)},"forearm.R":{"rot":(-65,0,0)},"head":{"rot":(-2,12,4)},"jaw":{"rot":(24,0,0)}}),(12,{"root":{"loc":(0,-.09,.02)},"pelvis":{"rot":(-6,0,13)},"spine":{"rot":(-8,0,18)},"chest":{"rot":(10,0,28)},"upper_arm.R":{"rot":(78,-8,-32)},"forearm.R":{"rot":(-4,0,0)},"upper_arm.L":{"rot":(36,0,-18)},"jaw":{"rot":(34,0,0)},"head":{"rot":(-15,-9,0)}}),(22,idle_pose)],22)
    hit=action(arm,"Hit",[(1,idle_pose),(4,{"root":{"loc":(0,.05,0)},"pelvis":{"rot":(-12,0,11)},"spine":{"rot":(-18,0,-8)},"chest":{"rot":(-22,0,-13)},"head":{"rot":(24,9,8)},"upper_arm.L":{"rot":(30,0,-25)},"upper_arm.R":{"rot":(-30,0,25)}}),(12,idle_pose)],12)
    stagger=action(arm,"Stagger",[(1,idle_pose),(7,{"root":{"loc":(0,.10,-.02)},"pelvis":{"rot":(-18,0,-16)},"spine":{"rot":(-20,0,17)},"head":{"rot":(31,-12,8)},"thigh.L":{"rot":(-28,0,0)},"shin.L":{"rot":(32,0,0)},"upper_arm.L":{"rot":(44,0,-26)},"upper_arm.R":{"rot":(-38,0,31)}}),(18,{"root":{"loc":(0,.03,-.04)},"pelvis":{"rot":(-5,0,8)},"head":{"rot":(12,7,2)}}),(27,idle_pose)],27)
    knockdown=action(arm,"Knockdown",[(1,idle_pose),(10,{"root":{"loc":(0,.15,-.22),"rot":(-42,0,10)},"pelvis":{"rot":(-20,0,12)},"spine":{"rot":(-25,0,7)},"head":{"rot":(30,0,0)},"thigh.L":{"rot":(40,0,0)},"thigh.R":{"rot":(56,0,0)}}),(22,{"root":{"loc":(0,.30,-.52),"rot":(-76,0,8)},"head":{"rot":(12,0,0)},"upper_arm.L":{"rot":(52,0,-25)},"upper_arm.R":{"rot":(-45,0,20)}}),(34,idle_pose)],34)
    death=action(arm,"Death",[(1,idle_pose),(9,{"root":{"loc":(0,.12,-.18),"rot":(-32,0,-12)},"pelvis":{"rot":(-18,0,-15)},"spine":{"rot":(-28,0,12)},"head":{"rot":(32,-10,0)},"upper_arm.L":{"rot":(40,0,-24)},"upper_arm.R":{"rot":(-42,0,26)}}),(20,{"root":{"loc":(0,.28,-.50),"rot":(-78,0,-10)},"head":{"rot":(18,0,0)},"thigh.L":{"rot":(48,0,0)},"thigh.R":{"rot":(60,0,0)}}),(38,{"root":{"loc":(0,.30,-.54),"rot":(-82,0,-9)},"jaw":{"rot":(24,0,0)}})],38)
    actions=[idle,walk,run,attack,hit,stagger,knockdown,death]
    arm.animation_data.action=None
    for clip in actions:
        track=arm.animation_data.nla_tracks.new();track.name=clip.name
        track.strips.new(clip.name,int(clip.frame_start),clip)
    return actions


def consolidate(arm):
    parts=[obj for obj in bpy.context.scene.objects if obj.type=="MESH" and obj.parent==arm]
    if not parts:
        raise RuntimeError("No Gravebound meshes were created")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    body=bpy.context.object
    body.name="GraveboundBody"
    body.parent=arm
    return body


def make_audio():
    os.makedirs(AUDIO_OUT, exist_ok=True)
    rate=22050
    for name,duration,base,noise,falloff in [
        ("groan",.85,76,.24,1.3),("attack",.42,112,.36,2.2),
        ("hit",.25,156,.48,4.0),("death",1.25,58,.31,1.0),
    ]:
        random.seed(8400+len(name))
        frames=[]
        count=int(rate*duration)
        for i in range(count):
            t=i/rate
            envelope=(1.0-math.pow(t/duration,falloff))*(min(1.0,t/.025))
            wobble=base*(1.0+.08*math.sin(t*17.0)+.04*math.sin(t*31.0))
            tone=math.sin(2*math.pi*wobble*t)+.34*math.sin(2*math.pi*wobble*.51*t)
            rasp=(random.random()*2-1)*noise*(.55+.45*math.sin(t*base*.7)**2)
            value=max(-1.0,min(1.0,(tone*.48+rasp)*envelope))
            frames.append(struct.pack('<h',int(value*32767)))
        with wave.open(os.path.join(AUDIO_OUT,name+".wav"),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate);wav.writeframes(b''.join(frames))


def setup_preview(arm):
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x=720;scene.render.resolution_y=820;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG";scene.render.filepath=PREVIEW_OUT
    scene.world.color=(.012,.016,.010)
    bpy.ops.mesh.primitive_plane_add(size=8,location=(0,0,0))
    floor=bpy.context.object;floor.name="PreviewFloor";floor.data.materials.append(material("PreviewFloor",(.025,.030,.020,1),.98))
    bpy.ops.object.camera_add(location=(2.7,-5.4,2.35));camera=bpy.context.object;scene.camera=camera
    camera.rotation_euler=(Vector((0,-.04,1.12))-camera.location).to_track_quat("-Z","Y").to_euler();camera.data.lens=62
    bpy.ops.object.light_add(type="AREA",location=(-2.5,-3.2,4.0));key=bpy.context.object;key.data.energy=1050;key.data.color=(.72,1.0,.48);key.data.size=3.0
    bpy.ops.object.light_add(type="AREA",location=(2.4,-1.0,2.6));fill=bpy.context.object;fill.data.energy=680;fill.data.color=(.32,.50,1.0);fill.data.size=2.4
    bpy.ops.object.light_add(type="AREA",location=(0,2.2,3.1));rim=bpy.context.object;rim.data.energy=900;rim.data.color=(1.0,.30,.12);rim.data.size=2.0
    arm.animation_data.action=bpy.data.actions["Idle"];scene.frame_set(27)
    os.makedirs(os.path.dirname(PREVIEW_OUT),exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for obj in (floor,camera,key,fill,rim):obj.hide_render=True


def export(arm):
    os.makedirs(os.path.dirname(GLB_OUT),exist_ok=True)
    arm.animation_data.action=None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH","ARMATURE"} and not obj.name.startswith("Preview"):
            obj.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.export_scene.gltf(filepath=GLB_OUT,export_format="GLB",use_selection=True,export_yup=True,
                              export_animations=True,export_animation_mode="ACTIONS",export_merge_animation="ACTION",
                              export_anim_single_armature=True,export_force_sampling=True,export_frame_range=False,
                              export_skins=True,export_lights=False,export_cameras=False,export_apply=False)


clear_scene()
armature=build_armature()
build_zombie(armature)
actions=make_animations(armature)
setup_preview(armature)
consolidate(armature)
make_audio()
bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
export(armature)
print("GRAVEBOUND_COMPLETE|blend=%s|glb=%s|preview=%s|animations=%s"%(BLEND_OUT,GLB_OUT,PREVIEW_OUT,",".join(a.name for a in actions)))
