"""Render the accepted closed harness with the Blender weapons in high guard."""

import os

import bpy
from mathutils import Vector


ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),"..",".."))
OUT=os.path.join(ROOT,"blender","previews","royal_armor","royal_harness_armed_guard.png")
SWORD=os.path.join(ROOT,"godot","assets","equipment","royal_vanguard_sword.glb")
SHIELD=os.path.join(ROOT,"godot","assets","equipment","royal_vanguard_shield.glb")
os.makedirs(os.path.dirname(OUT),exist_ok=True)


def import_root(path):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    imported=[obj for obj in bpy.data.objects if obj not in before]
    roots=[obj for obj in imported if obj.parent is None or obj.parent not in imported]
    if not roots:
        raise RuntimeError("No imported root for "+path)
    return roots[0]


scene=bpy.context.scene
arm=bpy.data.objects["HeroRig"]
arm.animation_data.action=bpy.data.actions["WarriorIdle"]
scene.frame_set(1)
bpy.context.view_layer.update()
sword=import_root(SWORD)
shield=import_root(SHIELD)
right=arm.matrix_world@arm.pose.bones["hand.R"].head
left=arm.matrix_world@arm.pose.bones["hand.L"].head
sword.location=right
sword.rotation_euler=(-.12,.05,-.12)
shield.location=left+Vector((-.090,-.145,-.025))
shield.rotation_euler=(-.08,-.14,.10)

for obj in scene.objects:
    if obj.name.startswith("RoyalStaff_"):
        obj.hide_render=True
    if obj.name.startswith(("Loincloth.","LoinTie.","LoinKnot.","LoinTail.")):
        obj.hide_render=True
    for modifier in getattr(obj,"modifiers",[]):
        if modifier.type=="SUBSURF":
            modifier.levels=0
            modifier.render_levels=0

scene.render.engine="BLENDER_EEVEE"
scene.render.resolution_x=820
scene.render.resolution_y=820
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="Standard"
scene.view_settings.look="None"
scene.view_settings.exposure=-.25
scene.world.use_nodes=True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.008,.012,.022,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=.18

for name,location,energy,color,size in (
    ("HarnessKey",(3.4,-4.5,4.1),450,(1.0,.80,.60),3.2),
    ("HarnessFill",(-3.0,-2.5,2.8),260,(.38,.55,1.0),3.5),
    ("HarnessRim",(0,3.4,3.4),500,(.48,.66,1.0),2.5),
):
    bpy.ops.object.light_add(type="AREA",location=location)
    light=bpy.context.object
    light.name=name
    light.data.energy=energy
    light.data.color=color
    light.data.shape="DISK"
    light.data.size=size
    light.rotation_euler=(Vector((0,0,1.10))-light.location).to_track_quat("-Z","Y").to_euler()

bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,-.006))
floor=bpy.context.object
floor_mat=bpy.data.materials.new("ArmedGuardFloor")
floor_mat.use_nodes=True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(.025,.032,.045,1)
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value=.84
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(2.50,-4.05,2.05))
camera=bpy.context.object
camera.data.lens=63
camera.rotation_euler=(Vector((0,0,1.10))-camera.location).to_track_quat("-Z","Y").to_euler()
scene.camera=camera
scene.render.filepath=OUT
bpy.ops.render.render(write_still=True)
print(f"ROYAL_HARNESS_ARMED_GUARD_RENDER|{OUT}")
