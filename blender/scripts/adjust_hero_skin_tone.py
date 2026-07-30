import bpy

skin=bpy.data.materials.get("Skin")
if skin is None:raise RuntimeError("Skin material not found")
color=(.48,.29,.20,1.0)
skin.diffuse_color=color
skin.use_nodes=True
bsdf=skin.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value=color
    bsdf.inputs["Roughness"].default_value=.88
skin["export_roughness"]=.88
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("SKIN_TONE_UPDATED|warm_tan|%.2f,%.2f,%.2f"%color[:3])
