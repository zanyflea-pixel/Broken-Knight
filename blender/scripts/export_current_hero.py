"""Export the open accepted hero master with rig, equipment and all NLA clips."""

import os
import bpy

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
output = os.path.abspath(os.environ.get(
    "BK_HERO_OUTPUT_GLB",
    os.path.join(root, "godot", "assets", "hero", "hero_full_continuous_body.glb"),
))
rig = bpy.data.objects["HeroRig"]
bpy.ops.object.select_all(action="DESELECT")
rig.hide_set(False)
rig.select_set(True)
selected_meshes = []
prefixes = (
    "Professional", "HeroHair", "Loincloth.", "LoinTie.", "LoinKnot.",
    "LoinTail.", "ClothWaistCord", "RoyalArmor_", "RoyalStaff_",
)
for obj in bpy.context.scene.objects:
    if obj.type in {"MESH", "CURVE"} and (obj.name == "ConnectedBody" or obj.name.startswith(prefixes)):
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
        selected_meshes.append(obj)
bpy.context.view_layer.objects.active = rig
os.makedirs(os.path.dirname(output), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=output,
    export_format="GLB",
    use_selection=True,
    export_apply=False,
    export_animations=True,
    export_nla_strips=True,
    export_optimize_animation_size=False,
    export_optimize_animation_keep_anim_armature=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_yup=True,
)
print("HERO_EXPORT|file=%s|meshes=%d|actions=%d" % (output, len(selected_meshes), len(bpy.data.actions)))
