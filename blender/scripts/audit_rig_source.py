import bpy

print("SCENE_AUDIT_BEGIN")
for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
    if obj.type not in {"MESH", "CURVE", "ARMATURE"}:
        continue
    dims = tuple(round(value, 4) for value in obj.dimensions)
    loc = tuple(round(value, 4) for value in obj.location)
    materials = [slot.material.name if slot.material else "None" for slot in obj.material_slots]
    vertices = len(obj.data.vertices) if obj.type == "MESH" else 0
    modifiers = [(modifier.name, modifier.type, getattr(modifier, 'levels', None), getattr(modifier, 'render_levels', None)) for modifier in obj.modifiers]
    print(f"OBJECT|{obj.name}|{obj.type}|loc={loc}|dims={dims}|verts={vertices}|mats={materials}|mods={modifiers}")
print("SCENE_AUDIT_END")
