"""Consolidate the visually accepted armor to one skinned mesh per slot.

This is a runtime-only structural optimization. It applies each armor piece's
non-deforming forge modifiers and joins the pieces by equipment slot while
preserving materials, UVs, vertex groups, the accepted body, and the armature.
"""

from hashlib import sha256
import struct
import bpy

rig=bpy.data.objects["HeroRig"]
body=bpy.data.objects["ConnectedBody"]


def digest(mesh):
    result=sha256()
    result.update(struct.pack("<II",len(mesh.vertices),len(mesh.polygons)))
    for vertex in mesh.vertices:result.update(struct.pack("<3f",*vertex.co))
    return result.hexdigest()


def clamp_deform_weights(obj):
    """Remove tiny invalid weights introduced by modifier interpolation.

    Bevel/solidify can numerically overshoot rigid 0..1 deform weights by a
    few millionths. Blender displays correctly but glTF flags the mesh as
    invalid, so clamp only those out-of-range samples after consolidation.
    """
    updates=[]
    for vertex in obj.data.vertices:
        for assignment in vertex.groups:
            if assignment.weight < 0.0 or assignment.weight > 1.0:
                updates.append((vertex.index,assignment.group,max(0.0,min(1.0,assignment.weight))))
    for vertex_index,group_index,weight in updates:
        obj.vertex_groups[group_index].add([vertex_index],weight,"REPLACE")
    return len(updates)


before=digest(body.data)
rig.data.pose_position="REST"
bpy.context.scene.frame_set(1)
bpy.context.view_layer.update()

for slot in ("head","chest","shoulders","hands","pants","feet"):
    prefix=f"RoyalArmor_{slot}_"
    parts=[obj for obj in bpy.data.objects if obj.type=="MESH" and obj.name.startswith(prefix)]
    if not parts:raise RuntimeError("Armor slot has no mesh parts: "+slot)
    for obj in parts:
        obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True);bpy.context.view_layer.objects.active=obj
        armatures=[modifier for modifier in obj.modifiers if modifier.type=="ARMATURE"]
        for armature in armatures:
            bpy.ops.object.modifier_move_to_index(modifier=armature.name,index=len(obj.modifiers)-1)
        for modifier in list(obj.modifiers):
            if modifier.type!="ARMATURE":bpy.ops.object.modifier_apply(modifier=modifier.name)

    # The largest piece provides the single retained armature modifier.
    active=max(parts,key=lambda obj:len(obj.data.vertices))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=active
    bpy.ops.object.join()
    active.name=f"RoyalArmor_{slot}_SovereignConsolidated"
    active.data.name=active.name+"_Mesh"
    active["bk_runtime_consolidated"]=True
    active["bk_source_piece_count"]=len(parts)
    active["bk_edit_note"]="Runtime consolidated slot; edit source pass and rebuild for structural changes"
    for modifier in list(active.modifiers):
        if modifier.type=="ARMATURE":modifier.object=rig
    if not any(modifier.type=="ARMATURE" for modifier in active.modifiers):
        modifier=active.modifiers.new("RoyalArmorRig","ARMATURE");modifier.object=rig
    active.parent=rig
    active["bk_clamped_deform_weights"]=clamp_deform_weights(active)

rig.data.pose_position="POSE"
if digest(body.data)!=before:raise RuntimeError("Armor optimization changed the locked body")
bpy.context.scene["bk_armor_runtime_meshes"]=6
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("ARMOR_RUNTIME_CONSOLIDATED|meshes=6|body_unchanged=true|file="+bpy.data.filepath)
