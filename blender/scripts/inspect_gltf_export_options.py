import bpy
props = bpy.ops.export_scene.gltf.get_rna_type().properties
for prop in props:
    if "anim" in prop.identifier or "nla" in prop.identifier or "action" in prop.identifier or "skin" in prop.identifier:
        print(f"GLTF_PROP|{prop.identifier}|default={getattr(prop, 'default', None)}")
