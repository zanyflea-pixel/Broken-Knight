"""Print a compact, deterministic inventory of a Blender source file."""

import bpy


print(f"BLEND_AUDIT|file={bpy.data.filepath}")
print(
    "BLEND_COUNTS|objects=%d|meshes=%d|armatures=%d|collections=%d|actions=%d|materials=%d"
    % (
        len(bpy.data.objects),
        len(bpy.data.meshes),
        len(bpy.data.armatures),
        len(bpy.data.collections),
        len(bpy.data.actions),
        len(bpy.data.materials),
    )
)
for collection in sorted(bpy.data.collections, key=lambda item: item.name.lower()):
    print(f"COLLECTION|{collection.name}|objects={len(collection.objects)}|children={len(collection.children)}")
for armature in sorted(
    (obj for obj in bpy.data.objects if obj.type == "ARMATURE"),
    key=lambda item: item.name.lower(),
):
    print(f"ARMATURE|{armature.name}|bones={len(armature.data.bones)}")
for action in sorted(bpy.data.actions, key=lambda item: item.name.lower()):
    start, end = action.frame_range
    print(f"ACTION|{action.name}|frames={start:.1f}-{end:.1f}|users={action.users}")
if __import__("os").environ.get("BK_AUDIT_OBJECTS") == "1":
    for obj in sorted(bpy.data.objects, key=lambda item: item.name.lower()):
        collections = ",".join(sorted(item.name for item in obj.users_collection))
        materials = ",".join(
            sorted(slot.material.name for slot in obj.material_slots if slot.material)
        )
        print(
            f"OBJECT|{obj.name}|type={obj.type}|parent={obj.parent.name if obj.parent else '-'}"
            f"|collections={collections}|materials={materials}"
        )
if __import__("os").environ.get("BK_AUDIT_BOUNDS") == "1":
    for obj in sorted(bpy.data.objects, key=lambda item: item.name.lower()):
        if not obj.name.startswith("RoyalArmor_"):
            continue
        dimensions = obj.dimensions
        location = obj.location
        vertices = len(obj.data.vertices) if obj.type == "MESH" else 0
        groups = ",".join(sorted(group.name for group in obj.vertex_groups))
        print(
            f"ARMOR_BOUNDS|{obj.name}|loc={location.x:.4f},{location.y:.4f},{location.z:.4f}"
            f"|dim={dimensions.x:.4f},{dimensions.y:.4f},{dimensions.z:.4f}"
            f"|vertices={vertices}|groups={groups}"
        )
