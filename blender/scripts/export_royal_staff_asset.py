"""Extract a static, centered Royal Vanguard staff asset for standalone inspection."""
import os
import bpy
from mathutils import Vector

ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),"..",".."))
BLEND=os.path.join(ROOT,"blender","royal_vanguard_staff.blend")
GLB=os.path.join(ROOT,"godot","assets","equipment","royal_vanguard_staff.glb")
PREFIX="RoyalStaff_"

arm=bpy.data.objects.get("HeroRig")
if arm and arm.animation_data:arm.animation_data.action=None
if arm:
    for bone in arm.pose.bones:
        bone.rotation_mode="XYZ";bone.rotation_euler=(0,0,0);bone.location=(0,0,0);bone.scale=(1,1,1)
bpy.context.scene.frame_set(1)

staff=[obj for obj in bpy.context.scene.objects if obj.type=="MESH" and obj.name.startswith(PREFIX)]
for obj in staff:
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    for modifier in list(obj.modifiers):
        if modifier.type=="ARMATURE":bpy.ops.object.modifier_apply(modifier=modifier.name)
    world=obj.matrix_world.copy();obj.parent=None;obj.matrix_world=world
    obj.location+=Vector((-.345,.020,-.835));obj.select_set(False)

for obj in list(bpy.context.scene.objects):
    if obj not in staff:bpy.data.objects.remove(obj,do_unlink=True)

bpy.ops.wm.save_as_mainfile(filepath=BLEND)
os.makedirs(os.path.dirname(GLB),exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=GLB,export_format="GLB",use_selection=True,export_yup=True,export_animations=False,export_lights=False,export_cameras=False,export_apply=True)
print("ROYAL_STAFF_EXPORTED|blend=%s|glb=%s|parts=%d|bytes=%d"%(BLEND,GLB,len(staff),os.path.getsize(GLB)))
