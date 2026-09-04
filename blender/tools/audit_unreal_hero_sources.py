"""Audit legacy Broken Knight hero sources before Unreal migration.

This is intentionally read-only with respect to the Blender sources. It writes
one JSON report into the separate Unreal project's SourceData/Hero directory.
"""

from pathlib import Path
import json
import math

import bpy


SOURCE_ROOT = Path(r"C:\Users\Jimmy\Desktop\Broken Knight\blender")
OUTPUT_PATH = Path(r"C:\Users\Jimmy\Desktop\Broken Knight Unreal\SourceData\Hero\legacy_hero_source_audit.json")
SOURCES = (
    SOURCE_ROOT / "BrokenKnight_Hero_Master.blend",
    SOURCE_ROOT / "BrokenKnight_Hero_RomanAnatomicalV16_RuntimeCandidate.blend",
    SOURCE_ROOT / "hero_restart_rigged_shoulders_improved.blend",
    SOURCE_ROOT / "royal_armor_articulated_editable.blend",
)


def rounded_vector(value):
    return [round(float(component), 5) for component in value]


def inspect_source(path: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    mesh_entries = []
    total_triangles = 0
    unapplied_transforms = []
    for obj in sorted(meshes, key=lambda item: item.name.lower()):
        triangle_count = sum(max(len(poly.vertices) - 2, 1) for poly in obj.data.polygons)
        total_triangles += triangle_count
        if any(abs(component - 1.0) > 0.0001 for component in obj.scale) or any(
            abs(component) > 0.0001 for component in obj.rotation_euler
        ):
            unapplied_transforms.append(obj.name)
        mesh_entries.append(
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "triangles": triangle_count,
                "materials": [slot.material.name if slot.material else "" for slot in obj.material_slots],
                "dimensions_m": rounded_vector(obj.dimensions),
                "parent": obj.parent.name if obj.parent else "",
                "armature_modifiers": [
                    modifier.object.name if modifier.object else ""
                    for modifier in obj.modifiers
                    if modifier.type == "ARMATURE"
                ],
                "shape_keys": len(obj.data.shape_keys.key_blocks) if obj.data.shape_keys else 0,
            }
        )
    armature_entries = []
    for armature in armatures:
        armature_entries.append(
            {
                "name": armature.name,
                "bones": len(armature.data.bones),
                "root_bones": [bone.name for bone in armature.data.bones if bone.parent is None],
                "dimensions_m": rounded_vector(armature.dimensions),
            }
        )
    images = []
    for image in bpy.data.images:
        if image.source == "VIEWER":
            continue
        images.append(
            {
                "name": image.name,
                "size": [int(image.size[0]), int(image.size[1])],
                "filepath": bpy.path.abspath(image.filepath) if image.filepath else "",
                "packed": image.packed_file is not None,
            }
        )
    return {
        "path": str(path),
        "file_size_mb": round(path.stat().st_size / (1024.0 * 1024.0), 3),
        "scene_units": {
            "system": bpy.context.scene.unit_settings.system,
            "scale_length": bpy.context.scene.unit_settings.scale_length,
        },
        "object_count": len(bpy.data.objects),
        "mesh_count": len(meshes),
        "total_triangles": total_triangles,
        "armatures": armature_entries,
        "actions": [action.name for action in bpy.data.actions],
        "materials": [material.name for material in bpy.data.materials],
        "images": images,
        "unapplied_transform_meshes": unapplied_transforms,
        "meshes": mesh_entries,
    }


def main():
    reports = []
    for source in SOURCES:
        if not source.exists():
            reports.append({"path": str(source), "missing": True})
            continue
        report = inspect_source(source)
        reports.append(report)
        print(
            "HERO_SOURCE|file=%s|meshes=%d|tris=%d|armatures=%d|actions=%d|materials=%d"
            % (
                source.name,
                report["mesh_count"],
                report["total_triangles"],
                len(report["armatures"]),
                len(report["actions"]),
                len(report["materials"]),
            )
        )
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(
            {
                "schema": "broken_knight_legacy_hero_audit_v1",
                "purpose": "Reuse assessment only; no source is automatically accepted as the final Unreal hero.",
                "sources": reports,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"HERO_SOURCE_AUDIT_COMPLETE|output={OUTPUT_PATH}|sources={len(reports)}")


if __name__ == "__main__":
    main()
