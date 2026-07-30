"""Reduce synthetic gloss while preserving necessary eye response."""

import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "hero_restart.blend")
BACKUP = os.path.join(ROOT, "hero_restart_pre_matte_materials.blend")


SETTINGS = {
    "Skin": (0.82, 0.32),
    "Dark": (0.82, 0.30),
    "Eyes": (0.76, 0.34),
    "IrisBrown": (0.68, 0.34),
    "LipTone": (0.88, 0.30),
    "Nails": (0.82, 0.30),
    "AreolaTone": (0.84, 0.30),
    "NippleTone": (0.83, 0.30),
    "PlainLoincloth": (0.97, 0.20),
    "LoinCord": (0.94, 0.22),
}


if __name__ == "__main__":
    bpy.ops.wm.save_as_mainfile(filepath=BACKUP)
    for name, (roughness, specular) in SETTINGS.items():
        mat = bpy.data.materials.get(name)
        if not mat or not mat.use_nodes:
            continue
        bsdf = next((node for node in mat.node_tree.nodes
                     if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Specular IOR Level"].default_value = specular
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("Saved matte material pass", OUT)
