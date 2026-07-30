"""Create an organized, user-editable Blender file for the closed royal harness."""

import os
import bpy


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.join(ROOT, "blender", "royal_armor_closed_harness_editable.blend")
PREFIX = "RoyalArmor_"


def clean_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is not None:
        for child in list(collection.children):
            collection.children.unlink(child)
        for parent in bpy.data.collections:
            if collection.name in parent.children:
                parent.children.unlink(collection)
        if collection.name in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.unlink(collection)
        bpy.data.collections.remove(collection)


clean_collection("ROYAL ARMOR - EDITABLE")
root = bpy.data.collections.new("ROYAL ARMOR - EDITABLE")
bpy.context.scene.collection.children.link(root)

slot_collections = {}
for slot, label in (
    ("head", "01 CLOSED ARMET + CREST"),
    ("chest", "02 CUIRASS + Tassets"),
    ("shoulders", "03 PAULDRONS + UPPER ARMS"),
    ("hands", "04 COUTERS + VAMBRACES + GAUNTLETS"),
    ("pants", "05 CUISSES + ARMING LAYERS"),
    ("feet", "06 POLEYNS + GREAVES + SABATONS"),
):
    collection = bpy.data.collections.new(label)
    root.children.link(collection)
    slot_collections[slot] = collection

armor_objects = [obj for obj in bpy.data.objects if obj.name.startswith(PREFIX)]
for obj in armor_objects:
    remainder = obj.name[len(PREFIX):]
    slot = remainder.split("_", 1)[0]
    target = slot_collections.get(slot)
    if target is None:
        continue
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    target.objects.link(obj)
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    obj.color = (0.12, 0.22, 0.55, 1.0)

for obj in bpy.data.objects:
    if obj.name.startswith("RoyalStaff_"):
        obj.hide_set(True)
        obj.hide_viewport = True
        obj.hide_render = True

armature = bpy.data.objects.get("HeroRig")
if armature is not None:
    armature.show_in_front = True
    armature.display_type = "WIRE"

readme = bpy.data.texts.get("ROYAL_ARMOR_README") or bpy.data.texts.new("ROYAL_ARMOR_README")
readme.clear()
readme.write(
    "ROYAL APEX PLATE - EDITABLE FILE\n"
    "\n"
    "Armor objects are grouped into six collections under ROYAL ARMOR - EDITABLE.\n"
    "The hero and HeroRig remain in this file as a live fitting/deformation reference.\n"
    "Every armor object is separately editable and remains bound to HeroRig.\n"
    "The dome, visor, bevor, chin, and upper gorget are one continuous forged helmet mesh.\n"
    "The eye slit, nasal keel, cheek ribs, perimeter, and filigree are surface insets/relief.\n"
    "One curved shoulder mantle and two overlapping shoulder skirts close the gaps beneath both pauldrons.\n"
    "Large fitted front tassets and one continuous wraparound rear culet connect the fauld to the leg armor.\n"
    "The obsolete floating face plates, bridges, hip panels, hand badges, knee wings, accent rods, and neck rings are absent.\n"
    "\n"
    "IMPORTANT:\n"
    "- Keep the RoyalArmor_<slot>_ prefix if the piece must remain equipable in Godot.\n"
    "- Apply major shape edits in Rest Position, then test the Walk and Jump actions.\n"
    "- The crimson fore-aft horsehair crest is grouped with the helmet collection.\n"
    "- The staff is hidden in this editing file so it does not obstruct armor work.\n"
    "- Re-export with blender/scripts/export_rigged_hero.py after accepted edits.\n"
)

bpy.context.scene["royal_armor_file"] = "Royal Apex Plate - Editable"
bpy.context.scene["royal_armor_object_count"] = len(armor_objects)
bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)
print(f"ROYAL_ARMOR_EDITABLE|{OUTPUT}|objects={len(armor_objects)}")
