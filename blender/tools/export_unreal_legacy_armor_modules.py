"""Export modular royal-armor source geometry for later MetaHuman fitting.

The original Blender file is only read. Exported FBX modules are explicitly
marked as legacy fit sources, not final Unreal skeletal meshes.
"""

from collections import defaultdict
from pathlib import Path
import json

import bpy


SOURCE = Path(r"C:\Users\Jimmy\Desktop\Broken Knight\blender\royal_armor_articulated_editable.blend")
OUTPUT_DIR = Path(r"C:\Users\Jimmy\Desktop\Broken Knight Unreal\SourceData\Hero\ArmorLegacyModules")
SLOT_ALIASES = {
    "head": "helmet",
    "chest": "torso",
    "shoulders": "shoulders",
    "hands": "arms_hands",
    "pants": "hips_legs",
    "feet": "boots",
}


def armor_slot(object_name: str) -> str | None:
    if not object_name.startswith("RoyalArmor_"):
        return None
    parts = object_name.split("_", 2)
    if len(parts) < 3:
        return "misc"
    return SLOT_ALIASES.get(parts[1].lower(), parts[1].lower())


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    modules = defaultdict(list)
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        slot = armor_slot(obj.name)
        if slot:
            modules[slot].append(obj)

    report_modules = {}
    for slot, objects in sorted(modules.items()):
        bpy.ops.object.select_all(action="DESELECT")
        triangle_count = 0
        material_names = set()
        for obj in objects:
            obj.select_set(True)
            triangle_count += sum(max(len(poly.vertices) - 2, 1) for poly in obj.data.polygons)
            for material_slot in obj.material_slots:
                if material_slot.material:
                    material_names.add(material_slot.material.name)
        bpy.context.view_layer.objects.active = objects[0]
        output_path = OUTPUT_DIR / f"SK_LegacyRoyalArmor_{slot}_Source.fbx"
        bpy.ops.export_scene.fbx(
            filepath=str(output_path),
            use_selection=True,
            object_types={"MESH"},
            use_mesh_modifiers=True,
            mesh_smooth_type="FACE",
            use_triangles=True,
            use_tspace=True,
            add_leaf_bones=False,
            bake_anim=False,
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_UNITS",
            axis_forward="-Y",
            axis_up="Z",
            path_mode="COPY",
            embed_textures=True,
        )
        report_modules[slot] = {
            "file": output_path.name,
            "objects": len(objects),
            "triangles": triangle_count,
            "materials": sorted(material_names),
        }
        print(
            f"ARMOR_MODULE|slot={slot}|objects={len(objects)}|triangles={triangle_count}|file={output_path.name}"
        )

    report = {
        "schema": "broken_knight_legacy_armor_modules_v1",
        "source": str(SOURCE),
        "status": "refit_source_only",
        "acceptance_note": (
            "These modules preserve authored shapes for review. They must be conformed, "
            "reweighted, material-reviewed, collision-tested, and LOD-tested against the "
            "final MetaHuman before any module is accepted for runtime use."
        ),
        "modules": report_modules,
    }
    (OUTPUT_DIR / "legacy_armor_modules_manifest.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(f"ARMOR_MODULE_EXPORT_COMPLETE|modules={len(report_modules)}|output={OUTPUT_DIR}")


if __name__ == "__main__":
    main()
