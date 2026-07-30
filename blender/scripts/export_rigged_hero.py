"""Export only the rigged hero, materials, skeleton, and named actions."""

import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "godot", "assets", "hero", "hero_base_body.glb")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

flat_colors = {
    "Skin": (0.48, 0.29, 0.20, 1),
    "HairBrown": (0.055, 0.020, 0.009, 1),
    "PlainLoincloth": (0.22, 0.105, 0.050, 1),
    "LoinCord": (0.105, 0.040, 0.014, 1),
    "BodyHairBrown": (0.032, 0.012, 0.006, 1),
}

for material in bpy.data.materials:
    if not material.use_nodes:
        continue
    # Preserve the authored cobalt engraving maps; flattening this material
    # erased the filigree, normal relief, and roughness variation in Godot.
    if material.name == "Royal Cobalt Filigree Plate":
        continue
    base = flat_colors.get(material.name, tuple(material.diffuse_color))
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        nodes.remove(node)
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = float(material.get("export_roughness", 0.82 if material.name == "Skin" else 0.78))
    bsdf.inputs["Metallic"].default_value = float(material.get("export_metallic", 0.0))
    bsdf.inputs["Specular IOR Level"].default_value = 0.28
    if "export_emission" in material:
        bsdf.inputs["Emission Color"].default_value = tuple(material["export_emission"])
        bsdf.inputs["Emission Strength"].default_value = float(material.get("export_emission_strength", 1.0))
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = base

arm = bpy.data.objects["HeroRig"]
arm.animation_data.action = None
# The authored body already contains 132k vertices. The source rig keeps its
# level-2 viewport smoothing, but exporting that modifier would expand the GLB
# beyond two million skinned vertices. One export-only level preserves the
# silhouette and facial detail while remaining practical for Godot.
body = bpy.data.objects["ConnectedBody"]
for modifier in body.modifiers:
    if modifier.type == "SUBSURF":
        modifier.levels = 1
        modifier.render_levels = 1
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type in {"MESH", "ARMATURE"}:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
bpy.context.view_layer.objects.active = arm

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_merge_animation="ACTION",
    export_anim_single_armature=True,
    export_force_sampling=False,
    export_frame_range=False,
    export_skins=True,
    export_all_influences=False,
    export_morph=False,
    export_lights=False,
    export_cameras=False,
    export_apply=False,
)
print(f"EXPORTED_GLB|{OUT}|bytes={os.path.getsize(OUT)}")
