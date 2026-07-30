"""Replace only the hero hair cap and material with broad scalp-following clumps."""

import os
import sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from build_hero_restart import hair


ROOT = os.path.abspath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "hero_restart.blend")
BACKUP = os.path.join(ROOT, "hero_restart_pre_hairline_edge_smooth.blend")


def configure_material(mat):
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.82
    bsdf.inputs["Base Color"].default_value = (0.055, 0.020, 0.009, 1)
    bsdf.inputs["Roughness"].default_value = 0.84
    bsdf.inputs["Specular IOR Level"].default_value = 0.28
    bsdf.inputs["Anisotropic"].default_value = 0.10
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (7.5, 7.5, 1.35)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4.8
    noise.inputs["Detail"].default_value = 2.4
    noise.inputs["Roughness"].default_value = 0.56
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.48
    bump.inputs["Distance"].default_value = 0.0038
    roughness = nodes.new("ShaderNodeValToRGB")
    roughness.color_ramp.elements[0].color = (0.76, 0.76, 0.76, 1)
    roughness.color_ramp.elements[1].color = (0.92, 0.92, 0.92, 1)
    links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(noise.outputs["Fac"], roughness.inputs["Fac"])
    links.new(roughness.outputs["Color"], bsdf.inputs["Roughness"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])


if __name__ == "__main__":
    bpy.ops.wm.save_as_mainfile(filepath=BACKUP)
    old = bpy.data.objects.get("Hair")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    old_clumps = bpy.data.objects.get("HairSculptedClumps")
    if old_clumps:
        bpy.data.objects.remove(old_clumps, do_unlink=True)
    mat = bpy.data.materials.get("HairBrown")
    configure_material(mat)
    hair(mat)
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("Saved hair texture pass", OUT)
