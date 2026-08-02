"""Create the canonical, organized Broken Knight hero master without remodeling it."""

import os

import bpy
from mathutils import Quaternion, Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.join(ROOT, "blender", "BrokenKnight_Hero_Master.blend")

COLLECTION_LAYOUT = {
    "00_RIG": None,
    "01_HERO_BODY": None,
    "02_HERO_FACE": None,
    "03_HERO_HAIR": None,
    "04_LOINCLOTH": None,
    "10_ARMOR": None,
    "10A_ARMOR_HEAD": "10_ARMOR",
    "10B_ARMOR_CHEST": "10_ARMOR",
    "10C_ARMOR_SHOULDERS": "10_ARMOR",
    "10D_ARMOR_HANDS": "10_ARMOR",
    "10E_ARMOR_PANTS": "10_ARMOR",
    "10F_ARMOR_FEET": "10_ARMOR",
    "20_STAFF": None,
    "90_PREVIEW": None,
    "99_MISC": None,
}

COLLECTION_COLORS = {
    "00_RIG": "COLOR_01",
    "01_HERO_BODY": "COLOR_03",
    "02_HERO_FACE": "COLOR_04",
    "03_HERO_HAIR": "COLOR_05",
    "04_LOINCLOTH": "COLOR_06",
    "10_ARMOR": "COLOR_02",
    "20_STAFF": "COLOR_07",
    "90_PREVIEW": "COLOR_08",
    "99_MISC": "COLOR_08",
}

ACTION_CATEGORIES = {
    "Idle": ("Locomotion", True),
    "Walk": ("Locomotion", True),
    "WarriorIdle": ("Locomotion", True),
    "WarriorWalk": ("Locomotion", True),
    "TorchIdle": ("Locomotion", True),
    "TorchWalk": ("Locomotion", True),
    "StaffIdle": ("Locomotion", True),
    "StaffWalk": ("Locomotion", True),
    "Jump": ("Traversal", False),
    "Land": ("Traversal", False),
    "Roll": ("Traversal", False),
    "SwordSlash": ("Combat", False),
    "ShieldBash": ("Combat", False),
    "Death": ("Combat", False),
    "Spark": ("Magic", False),
    "Nova": ("Magic", False),
    "Blink": ("Magic", False),
    "Orb": ("Magic", False),
    "StaffSpark": ("Magic", False),
    "StaffNova": ("Magic", False),
    "StaffBlink": ("Magic", False),
    "StaffOrb": ("Magic", False),
    "FishCast": ("Utility", False),
    "SwordSlash_Improved_Test": ("Experimental", False),
}

FACE_PREFIXES = (
    "Brow.",
    "Eye.",
    "EyeHighlight.",
    "Iris.",
    "Nostril.",
    "Pupil.",
    "UpperLid.",
)
BODY_PREFIXES = ("Areola.", "Nipple.", "Fingernail", "Thumbnail.", "Toenail")
LOINCLOTH_PREFIXES = ("Loincloth.", "LoinKnot.", "LoinTail.", "LoinTie.")
ARMOR_COLLECTIONS = {
    "head": "10A_ARMOR_HEAD",
    "chest": "10B_ARMOR_CHEST",
    "shoulders": "10C_ARMOR_SHOULDERS",
    "hands": "10D_ARMOR_HANDS",
    "pants": "10E_ARMOR_PANTS",
    "feet": "10F_ARMOR_FEET",
}


def ensure_collection(name, parent_name=None):
    collection = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = bpy.data.collections.get(parent_name) if parent_name else bpy.context.scene.collection
    if collection.name not in parent.children:
        parent.children.link(collection)
    if parent_name:
        root = bpy.context.scene.collection
        if collection.name in root.children:
            root.children.unlink(collection)
    collection.color_tag = COLLECTION_COLORS.get(name, "COLOR_02")
    return collection


def collection_for_object(obj):
    name = obj.name
    if obj.type == "ARMATURE" or name == "HeroRig":
        return "00_RIG"
    if name.startswith("RoyalArmor_"):
        slot = name[len("RoyalArmor_") :].split("_", 1)[0].lower()
        return ARMOR_COLLECTIONS.get(slot, "10_ARMOR")
    if name.startswith("RoyalStaff_"):
        return "20_STAFF"
    if name == "ClothWaistCord" or name.startswith(LOINCLOTH_PREFIXES):
        return "04_LOINCLOTH"
    if name == "Hair" or name == "BodyHair":
        return "03_HERO_HAIR"
    if name.startswith(FACE_PREFIXES):
        return "02_HERO_FACE"
    if name == "ConnectedBody" or name.startswith(BODY_PREFIXES):
        return "01_HERO_BODY"
    if obj.type in {"CAMERA", "LIGHT"} or "Preview" in name:
        return "90_PREVIEW"
    return "99_MISC"


def write_text(name, body):
    text = bpy.data.texts.get(name) or bpy.data.texts.new(name)
    text.clear()
    text.write(body.rstrip() + "\n")
    text.use_fake_user = True


def organize_collections():
    collections = {
        name: ensure_collection(name, parent)
        for name, parent in COLLECTION_LAYOUT.items()
    }
    for obj in list(bpy.data.objects):
        destination = collections[collection_for_object(obj)]
        if destination.objects.get(obj.name) is None:
            destination.objects.link(obj)
        for existing in list(obj.users_collection):
            if existing != destination:
                existing.objects.unlink(obj)
        root = bpy.context.scene.collection
        if root.objects.get(obj.name) is not None:
            root.objects.unlink(obj)

    keep = set(COLLECTION_LAYOUT)
    for collection in list(bpy.data.collections):
        if collection.name not in keep and not collection.objects and not collection.children:
            bpy.data.collections.remove(collection)


def annotate_actions():
    for action in bpy.data.actions:
        category, loop = ACTION_CATEGORIES.get(action.name, ("Unsorted", False))
        start, end = action.frame_range
        action["bk_category"] = category
        action["bk_loop"] = loop
        action["bk_frame_start"] = int(round(start))
        action["bk_frame_end"] = int(round(end))
        action["bk_status"] = (
            "Reference only; not part of the verified runtime set"
            if category == "Experimental"
            else "Runtime"
        )


def add_guides():
    write_text(
        "00_START_HERE",
        """BROKEN KNIGHT — HERO MASTER

This is the canonical editable hero. It was organized from
hero_restart_rigged_shoulders_improved.blend without changing geometry,
weights, materials, proportions, or animation keyframes.

QUICK START
1. Select HeroRig in 00_RIG.
2. Switch the bottom editor to Dope Sheet > Action Editor.
3. Choose an action by its exact name. See the ANIMATION_INDEX text.
4. Edit the character in the named Outliner collections.
5. Save, then run export-hero-blender.bat from the project root.

IMPORTANT
- Runtime GLB: ../godot/assets/hero/hero_base_body.glb
- Keep runtime animation names unchanged.
- SwordSlash_Improved_Test is retained only as an experiment/reference.
- The current in-game sword attack adds procedural arm motion in HeroVisual.gd.
- 90_PREVIEW is never exported by the hero exporter.
""",
    )

    lines = [
        "BROKEN KNIGHT — ANIMATION INDEX",
        "",
        "Exact names are preserved because Godot depends on them.",
        "Frames are inclusive. Project playback is 24 fps.",
        "",
        "CATEGORY      ACTION                       FRAMES    LOOP   STATUS",
        "------------  ---------------------------  --------  -----  ----------------",
    ]
    for action in sorted(
        bpy.data.actions,
        key=lambda item: (str(item.get("bk_category", "Unsorted")), item.name.lower()),
    ):
        start, end = action.frame_range
        category = str(action.get("bk_category", "Unsorted"))
        loop = "yes" if bool(action.get("bk_loop", False)) else "no"
        status = "reference" if category == "Experimental" else "runtime"
        lines.append(
            f"{category:<12}  {action.name:<27}  {int(start):>3}-{int(end):<3}  {loop:<5}  {status}"
        )
    write_text("ANIMATION_INDEX", "\n".join(lines))


def prepare_scene():
    scene = bpy.context.scene
    scene["bk_canonical_source"] = "blender/BrokenKnight_Hero_Master.blend"
    scene["bk_runtime_export"] = "godot/assets/hero/hero_base_body.glb"
    scene["bk_organized_from"] = os.path.basename(bpy.data.filepath)
    scene.frame_start = 1
    scene.frame_end = 73
    scene.frame_set(1)

    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    rig = bpy.data.objects.get("HeroRig")
    if rig:
        rig.hide_set(False)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        if rig.animation_data is None:
            rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")

    camera = bpy.data.objects.get("SwordPreviewCamera")
    if camera:
        camera.hide_render = True


def configure_viewport(area, front_view=False):
    area.type = "VIEW_3D"
    space = area.spaces.active
    # SOLID is available even in background mode and keeps the master quick to open.
    space.shading.type = "SOLID"
    space.clip_start = 0.01
    space.clip_end = 100.0
    if space.region_3d:
        space.region_3d.view_distance = 3.1
        space.region_3d.view_location = Vector((0.0, 0.0, 1.0))
        if front_view:
            space.region_3d.view_rotation = Quaternion((0.7071068, 0.7071068, 0.0, 0.0))


def prepare_workspaces():
    layout = bpy.data.screens.get("Layout")
    if layout:
        editable = [area for area in layout.areas if area.type not in {"PROPERTIES", "OUTLINER"}]
        if editable:
            main_area = max(editable, key=lambda area: area.width * area.height)
            configure_viewport(main_area, front_view=False)
            for area in editable:
                if area != main_area:
                    area.type = "DOPESHEET_EDITOR"
                    area.spaces.active.mode = "TIMELINE"

    animation = bpy.data.screens.get("Animation")
    if animation:
        viewports = [area for area in animation.areas if area.type == "VIEW_3D"]
        for index, area in enumerate(sorted(viewports, key=lambda item: item.width, reverse=True)):
            configure_viewport(area, front_view=index == 0)
        for area in animation.areas:
            if area.type == "DOPESHEET_EDITOR":
                area.spaces.active.mode = "ACTION"
                area.spaces.active.show_region_ui = True

    scripting = bpy.data.screens.get("Scripting")
    if scripting:
        guide = bpy.data.texts.get("00_START_HERE")
        for area in scripting.areas:
            if area.type == "TEXT_EDITOR" and guide:
                area.spaces.active.text = guide

    if bpy.context.window and bpy.data.workspaces.get("Layout"):
        bpy.context.window.workspace = bpy.data.workspaces["Layout"]


def main():
    if not bpy.data.objects.get("HeroRig"):
        raise RuntimeError("HeroRig was not found; refusing to create a master from the wrong file")
    if not bpy.data.objects.get("RoyalArmor_shoulders_ApexImprovedPauldronL1"):
        raise RuntimeError("The improved shoulder set was not found; refusing to promote an older hero")

    source = bpy.data.filepath
    organize_collections()
    annotate_actions()
    add_guides()
    prepare_scene()
    prepare_workspaces()
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
    print(
        "HERO_MASTER_SAVED|source=%s|output=%s|objects=%d|actions=%d|collections=%d"
        % (source, OUTPUT, len(bpy.data.objects), len(bpy.data.actions), len(bpy.data.collections))
    )


if __name__ == "__main__":
    main()
