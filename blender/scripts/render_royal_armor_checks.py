"""Render fitted Royal Vanguard armor from useful inspection angles."""
import os
import bpy
from mathutils import Vector

ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),"..",".."))
OUT=os.path.join(ROOT,"blender","previews","royal_armor")
os.makedirs(OUT,exist_ok=True)
scene=bpy.context.scene
material_check=os.environ.get("BK_ARMOR_MATERIAL_CHECK")=="1"
scene.render.engine="BLENDER_EEVEE" if material_check else "BLENDER_WORKBENCH"
if not material_check:
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
scene.render.resolution_x=500;scene.render.resolution_y=720;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="Standard";scene.view_settings.look="None";scene.view_settings.exposure=-.35
scene.world.color=(.025,.028,.035)
if material_check:
    scene.world.use_nodes=True
    background=scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value=(.010,.014,.024,1)
    background.inputs["Strength"].default_value=.20
    for name,location,energy,color,size in (
        ("ArmorKey",(3.2,-4.0,4.2),300,(1.0,.82,.66),3.0),
        ("ArmorFill",(-3.0,-2.2,2.8),170,(.42,.58,1.0),3.5),
        ("ArmorRim",(0,3.4,3.5),360,(.55,.68,1.0),2.5),
    ):
        bpy.ops.object.light_add(type="AREA",location=location)
        light=bpy.context.object;light.name=name
        light.data.energy=energy;light.data.color=color;light.data.shape="DISK";light.data.size=size
        light.rotation_euler=((Vector((0,0,1.15))-light.location).to_track_quat("-Z","Y").to_euler())
for obj in scene.objects:
    for modifier in getattr(obj,"modifiers",[]):
        if modifier.type=="SUBSURF":modifier.levels=0;modifier.render_levels=0

bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,-.005))
floor=bpy.context.object;floor.name="RoyalArmorCheckFloor"
floor_mat=bpy.data.materials.new("RoyalArmorCheckFloorMat");floor_mat.diffuse_color=(.055,.060,.070,1)
floor_mat.use_nodes=True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(.055,.060,.070,1)
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value=.82
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add();camera=bpy.context.object;camera.data.lens=70;scene.camera=camera
arm=bpy.data.objects["HeroRig"]
staff_check=os.environ.get("BK_STAFF_CHECK")=="1"
if not staff_check:
    for obj in scene.objects:
        if obj.name.startswith("RoyalStaff_"):
            obj.hide_render=True
if os.environ.get("BK_ARMOR_ONLY")=="1":
    for obj in scene.objects:
        if obj.type in {"MESH","CURVE"} and not obj.name.startswith(("RoyalArmor_","RoyalArmorCheckFloor")):
            obj.hide_render=True
hide_armor_fragment=os.environ.get("BK_HIDE_ARMOR_FRAGMENT","").strip()
if hide_armor_fragment:
    for obj in scene.objects:
        if obj.name.startswith("RoyalArmor_") and hide_armor_fragment in obj.name:
            obj.hide_render=True
            print(f"ROYAL_ARMOR_DIAGNOSTIC_HIDE|{obj.name}")
if os.environ.get("BK_HIDE_BASE_LOIN")=="1":
    for obj in scene.objects:
        if obj.name.startswith(("Loincloth.","LoinTie.","LoinKnot.","LoinTail.")):
            obj.hide_render=True

def aim(location,target=(0,0,1.06)):
    camera.location=Vector(location)
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat("-Z","Y").to_euler()

views=(("front",(0,-4.50,1.05)),("threequarter",(3.35,-3.62,1.10)),("side",(4.65,0,1.08)),("back",(0,4.50,1.05)))
if material_check:
    views=(("material_front",(0,-4.50,1.05)),("material_threequarter",(3.35,-3.62,1.10)))
if os.environ.get("BK_ARMOR_CLOSEUP")=="1":
    scene.render.resolution_x=900;scene.render.resolution_y=900
    views=(("material_closeup",(0,-2.45,1.33)),)
if os.environ.get("BK_ARMOR_BACK_ONLY")=="1":views=(("back",(0,3.4,1.0)),)
if os.environ.get("BK_ARMOR_SIDE_ONLY")=="1":views=(("side",(3.4,0,1.0)),)
if os.environ.get("BK_ARMOR_FRONT_ONLY")=="1":views=(("front",(0,-4.2,1.05)),)
poses=(("idle","Idle",1),)
if os.environ.get("BK_ARMOR_DEFORM_ONLY")=="1":
    poses=(("walk","Walk",7),("jump","Jump",8));views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_WARRIOR_DEFORM_ONLY")=="1":
    poses=(("warrior_idle","WarriorIdle",1),("warrior_contact","WarriorWalk",1),("warrior_passing","WarriorWalk",7));views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_WARRIOR_PASSING_ONLY")=="1":
    poses=(("warrior_passing","WarriorWalk",7),);views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_WARRIOR_ACTION_CHECK")=="1":
    poses=(
        ("sword_windup","SwordSlash",6),
        ("sword_entry","SwordSlash",10),
        ("sword_impact","SwordSlash",12),
        ("sword_follow","SwordSlash",14),
        ("sword_recover","SwordSlash",21),
        ("shield_load","ShieldBash",4),
        ("shield_impact","ShieldBash",8),
        ("shield_recover","ShieldBash",11),
    )
    views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_SWORD_ACTION_CHECK")=="1":
    poses=(
        ("sword_windup","SwordSlash",6),
        ("sword_entry","SwordSlash",10),
        ("sword_impact","SwordSlash",12),
        ("sword_follow","SwordSlash",14),
        ("sword_recover","SwordSlash",21),
    )
    views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_SWORD_WINDUP_ONLY")=="1":
    poses=(("sword_windup","SwordSlash",6),)
    views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_FISH_ACTION_CHECK")=="1":
    poses=(
        ("fish_load","FishCast",4),
        ("fish_release","FishCast",10),
        ("fish_settle","FishCast",14),
    )
    views=(("threequarter",(2.55,-2.75,1.05)),)
if staff_check:
    poses=(("staff_idle","StaffIdle",1),("staff_walk","StaffWalk",7),("staff_cast","StaffSpark",7))
    views=(
        ("front",(0,-3.75,1.08)),
        ("threequarter",(2.55,-2.95,1.10)),
        ("side",(3.75,0,1.08)),
    )
if os.environ.get("BK_ROLL_CHECK")=="1":
    poses=(("roll_tuck","Roll",7),("roll_inverted","Roll",10),("roll_recover","Roll",16));views=(("side",(3.55,0,1.0)),)
if os.environ.get("BK_AIR_ACTION_CHECK")=="1":
    poses=(
        ("jump_anticipation","Jump",1),
        ("jump_airborne","Jump",8),
        ("land_contact","Land",1),
        ("land_compression","Land",3),
        ("land_recover","Land",8),
    )
    views=(("threequarter",(2.55,-2.75,1.05)),)
if os.environ.get("BK_MAGIC_ACTION_CHECK")=="1":
    poses=(
        ("spark_release","Spark",6),
        ("nova_gather","Nova",8),
        ("nova_release","Nova",11),
        ("blink_drive","Blink",6),
        ("orb_charge","Orb",10),
        ("orb_release","Orb",14),
    )
    views=(("front",(0,-3.75,1.08)),("threequarter",(2.55,-2.95,1.10)))
if os.environ.get("BK_CARRY_ACTION_CHECK")=="1":
    poses=(
        ("torch_idle","TorchIdle",25),
        ("torch_contact","TorchWalk",1),
        ("torch_passing","TorchWalk",7),
        ("staff_idle","StaffIdle",25),
        ("staff_contact","StaffWalk",1),
        ("staff_passing","StaffWalk",7),
    )
    views=(("threequarter",(2.55,-2.95,1.10)),)
if os.environ.get("BK_SKIN_CHECK")=="1":
    for obj in scene.objects:
        if obj.name.startswith(("RoyalArmor_","RoyalStaff_")):obj.hide_render=True
    poses=(("skin_tone","Idle",1),);views=(("front",(0,-3.4,1.0)),("threequarter",(2.55,-2.75,1.05)))
for pose_name,action_name,frame in poses:
    arm.animation_data.action=bpy.data.actions[action_name];scene.frame_set(frame)
    for label,location in views:
        aim(location,(0,0,1.35) if label=="material_closeup" else (0,0,1.06))
        suffix=label if pose_name=="idle" else f"{pose_name}_{label}"
        scene.render.filepath=os.path.join(OUT,f"royal_armor_{suffix}.png")
        bpy.ops.render.render(write_still=True)
        print(f"ROYAL_ARMOR_RENDER|{suffix}|{scene.render.filepath}")
