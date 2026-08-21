"""Build a reference-led professional-topology head WIP for the Broke Knight.

The mesh is generated locally from the pinned open-source MPFB human topology,
then custom-shaped with bundled target data. This avoids every rejected method:
the eyelids, lips, nostrils, ears, jaw, and neck are continuous authored human
topology rather than separate primitive strips. The canonical hero is untouched.
"""

from math import cos, pi, sin
import os
import random

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
ROOT = os.path.abspath(os.path.join(BLEND_DIR, ".."))
OUTPUT_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Head_Professional_WIP.blend")
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "hero_head_professional_wip")
REFERENCE_PATH = os.path.join(BLEND_DIR, "references", "hero_head_reference_v1.png")
SKIN_TEXTURE_PATH = os.path.join(BLEND_DIR, "textures", "hero_skin_micro_albedo_v1.png")
MALE_LANDMARK_Z_SHIFT = 0.13045
SOURCE_LIP_Z = 1.6671
SOURCE_BROW_Z = 1.7678


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def socket(bsdf, *names):
    for name in names:
        result = bsdf.inputs.get(name)
        if result is not None:
            return result
    return None


def make_simple_material(name, color, roughness, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    socket(bsdf, "Base Color").default_value = color
    socket(bsdf, "Roughness").default_value = roughness
    socket(bsdf, "Metallic").default_value = metallic
    return material


def make_skin_material():
    material = bpy.data.materials.new("HeroSkin.ProfessionalWIP")
    material.diffuse_color = (0.39, 0.15, 0.075, 1.0)
    material.roughness = 0.70
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    geometry = nodes.new("ShaderNodeNewGeometry")

    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 38.0
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.66
    links.new(geometry.outputs["Position"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.20
    ramp.color_ramp.elements[0].color = (0.205, 0.052, 0.022, 1.0)
    ramp.color_ramp.elements[1].position = 0.80
    ramp.color_ramp.elements[1].color = (0.355, 0.138, 0.066, 1.0)

    # Project-owned generated micro-albedo supplies non-repeating pore, freckle,
    # and tone variation. Box projection avoids face seams and does not depend
    # on a fragile hand-painted UV layout.
    if not os.path.isfile(SKIN_TEXTURE_PATH):
        raise RuntimeError(f"Skin micro-albedo is missing: {SKIN_TEXTURE_PATH}")
    skin_image = bpy.data.images.load(SKIN_TEXTURE_PATH, check_existing=True)
    skin_image.pack()
    scale_vector = nodes.new("ShaderNodeVectorMath")
    scale_vector.name = "SkinTextureObjectScale"
    scale_vector.operation = "SCALE"
    scale_vector.inputs["Scale"].default_value = 4.0
    links.new(geometry.outputs["Position"], scale_vector.inputs["Vector"])
    skin_texture = nodes.new("ShaderNodeTexImage")
    skin_texture.image = skin_image
    skin_texture.extension = "REPEAT"
    skin_texture.projection = "BOX"
    skin_texture.projection_blend = 0.28
    skin_texture.interpolation = "Linear"
    links.new(scale_vector.outputs["Vector"], skin_texture.inputs["Vector"])
    skin_grade = nodes.new("ShaderNodeHueSaturation")
    skin_grade.inputs["Saturation"].default_value = 1.12
    skin_grade.inputs["Value"].default_value = 0.62
    links.new(skin_texture.outputs["Color"], skin_grade.inputs["Color"])

    # Smooth object-space elliptical lip tint. Unlike polygon masks, this has
    # no pixelated boundary and colors the lips while retaining their topology.
    separate = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], separate.inputs["Vector"])
    x_abs = nodes.new("ShaderNodeMath")
    x_abs.operation = "ABSOLUTE"
    links.new(separate.outputs["X"], x_abs.inputs[0])
    x_scale = nodes.new("ShaderNodeMath")
    x_scale.name = "LipXScale"
    x_scale.operation = "DIVIDE"
    x_scale.inputs[1].default_value = 0.033
    links.new(x_abs.outputs[0], x_scale.inputs[0])
    x_sq = nodes.new("ShaderNodeMath")
    x_sq.operation = "MULTIPLY"
    links.new(x_scale.outputs[0], x_sq.inputs[0])
    links.new(x_scale.outputs[0], x_sq.inputs[1])
    z_center = nodes.new("ShaderNodeMath")
    z_center.name = "LipZCenter"
    z_center.operation = "SUBTRACT"
    z_center.inputs[1].default_value = SOURCE_LIP_Z
    links.new(separate.outputs["Z"], z_center.inputs[0])
    z_scale = nodes.new("ShaderNodeMath")
    z_scale.name = "LipZScale"
    z_scale.operation = "DIVIDE"
    z_scale.inputs[1].default_value = 0.0120
    links.new(z_center.outputs[0], z_scale.inputs[0])
    z_sq = nodes.new("ShaderNodeMath")
    z_sq.operation = "MULTIPLY"
    links.new(z_scale.outputs[0], z_sq.inputs[0])
    links.new(z_scale.outputs[0], z_sq.inputs[1])
    ellipse = nodes.new("ShaderNodeMath")
    ellipse.operation = "ADD"
    links.new(x_sq.outputs[0], ellipse.inputs[0])
    links.new(z_sq.outputs[0], ellipse.inputs[1])
    lip_falloff = nodes.new("ShaderNodeMapRange")
    lip_falloff.clamp = True
    lip_falloff.inputs["From Min"].default_value = 0.58
    lip_falloff.inputs["From Max"].default_value = 1.0
    lip_falloff.inputs["To Min"].default_value = 1.0
    lip_falloff.inputs["To Max"].default_value = 0.0
    links.new(ellipse.outputs[0], lip_falloff.inputs["Value"])
    front_test = nodes.new("ShaderNodeMath")
    front_test.name = "LipFrontLimit"
    front_test.operation = "LESS_THAN"
    front_test.inputs[1].default_value = -0.140
    links.new(separate.outputs["Y"], front_test.inputs[0])
    lip_mask = nodes.new("ShaderNodeMath")
    lip_mask.operation = "MULTIPLY"
    links.new(lip_falloff.outputs[0], lip_mask.inputs[0])
    links.new(front_test.outputs[0], lip_mask.inputs[1])
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MIX"
    mix.inputs[2].default_value = (0.125, 0.034, 0.026, 1.0)
    links.new(lip_mask.outputs[0], mix.inputs[0])
    links.new(skin_grade.outputs["Color"], mix.inputs[1])
    # Fine beard shadow breaks the fully shaved mannequin read without adding a
    # heavy beard. It is restricted to the lower forward face and interrupted
    # by the lip mask.
    stubble_noise = nodes.new("ShaderNodeTexNoise")
    stubble_noise.inputs["Scale"].default_value = 210.0
    stubble_noise.inputs["Detail"].default_value = 2.0
    links.new(geometry.outputs["Position"], stubble_noise.inputs["Vector"])
    x_limit = nodes.new("ShaderNodeMapRange")
    x_limit.name = "StubbleXFalloff"
    x_limit.clamp = True
    x_limit.inputs["From Min"].default_value = 0.056
    x_limit.inputs["From Max"].default_value = 0.086
    x_limit.inputs["To Min"].default_value = 1.0
    x_limit.inputs["To Max"].default_value = 0.0
    links.new(x_abs.outputs[0], x_limit.inputs["Value"])
    y_limit = nodes.new("ShaderNodeMapRange")
    y_limit.name = "StubbleYFalloff"
    y_limit.clamp = True
    y_limit.inputs["From Min"].default_value = -0.020
    y_limit.inputs["From Max"].default_value = 0.055
    y_limit.inputs["To Min"].default_value = 1.0
    y_limit.inputs["To Max"].default_value = 0.0
    links.new(separate.outputs["Y"], y_limit.inputs["Value"])
    z_upper = nodes.new("ShaderNodeMapRange")
    z_upper.name = "StubbleUpperFalloff"
    z_upper.clamp = True
    z_upper.inputs["From Min"].default_value = 1.690
    z_upper.inputs["From Max"].default_value = 1.725
    z_upper.inputs["To Min"].default_value = 1.0
    z_upper.inputs["To Max"].default_value = 0.0
    links.new(separate.outputs["Z"], z_upper.inputs["Value"])
    z_lower = nodes.new("ShaderNodeMapRange")
    z_lower.name = "StubbleLowerFalloff"
    z_lower.clamp = True
    z_lower.inputs["From Min"].default_value = 1.565
    z_lower.inputs["From Max"].default_value = 1.610
    z_lower.inputs["To Min"].default_value = 0.0
    z_lower.inputs["To Max"].default_value = 1.0
    links.new(separate.outputs["Z"], z_lower.inputs["Value"])
    stubble_mask_a = nodes.new("ShaderNodeMath")
    stubble_mask_a.operation = "MULTIPLY"
    links.new(x_limit.outputs["Result"], stubble_mask_a.inputs[0])
    links.new(y_limit.outputs["Result"], stubble_mask_a.inputs[1])
    stubble_mask_b = nodes.new("ShaderNodeMath")
    stubble_mask_b.operation = "MULTIPLY"
    links.new(z_upper.outputs["Result"], stubble_mask_b.inputs[0])
    links.new(z_lower.outputs["Result"], stubble_mask_b.inputs[1])
    stubble_region = nodes.new("ShaderNodeMath")
    stubble_region.operation = "MULTIPLY"
    links.new(stubble_mask_a.outputs[0], stubble_region.inputs[0])
    links.new(stubble_mask_b.outputs[0], stubble_region.inputs[1])
    no_lips = nodes.new("ShaderNodeMath")
    no_lips.operation = "SUBTRACT"
    no_lips.inputs[0].default_value = 1.0
    links.new(lip_mask.outputs[0], no_lips.inputs[1])
    stubble_region_2 = nodes.new("ShaderNodeMath")
    stubble_region_2.operation = "MULTIPLY"
    links.new(stubble_region.outputs[0], stubble_region_2.inputs[0])
    links.new(no_lips.outputs[0], stubble_region_2.inputs[1])
    stubble_strength = nodes.new("ShaderNodeMath")
    stubble_strength.operation = "MULTIPLY"
    stubble_strength.inputs[1].default_value = 0.34
    links.new(stubble_noise.outputs["Fac"], stubble_strength.inputs[0])
    stubble_final = nodes.new("ShaderNodeMath")
    stubble_final.operation = "MULTIPLY"
    links.new(stubble_region_2.outputs[0], stubble_final.inputs[0])
    links.new(stubble_strength.outputs[0], stubble_final.inputs[1])
    stubble_mix = nodes.new("ShaderNodeMixRGB")
    stubble_mix.inputs[2].default_value = (0.055, 0.018, 0.010, 1.0)
    links.new(stubble_final.outputs[0], stubble_mix.inputs[0])
    links.new(mix.outputs["Color"], stubble_mix.inputs[1])
    # Eyebrows are shaded directly onto the continuous facial surface. This is
    # deliberately not separate geometry: it cannot float, intersect, or read
    # as a strip glued onto the forehead.
    brow_center_x = nodes.new("ShaderNodeMath")
    brow_center_x.name = "BrowCenterX"
    brow_center_x.operation = "SUBTRACT"
    brow_center_x.inputs[1].default_value = 0.032
    links.new(x_abs.outputs[0], brow_center_x.inputs[0])
    brow_x = nodes.new("ShaderNodeMath")
    brow_x.name = "BrowXScale"
    brow_x.operation = "DIVIDE"
    brow_x.inputs[1].default_value = 0.021
    links.new(brow_center_x.outputs[0], brow_x.inputs[0])
    brow_x_sq = nodes.new("ShaderNodeMath")
    brow_x_sq.operation = "MULTIPLY"
    links.new(brow_x.outputs[0], brow_x_sq.inputs[0])
    links.new(brow_x.outputs[0], brow_x_sq.inputs[1])
    brow_arch = nodes.new("ShaderNodeMath")
    brow_arch.name = "BrowArch"
    brow_arch.operation = "MULTIPLY_ADD"
    brow_arch.inputs[1].default_value = -0.0060
    brow_arch.inputs[2].default_value = SOURCE_BROW_Z
    links.new(brow_x_sq.outputs[0], brow_arch.inputs[0])
    brow_z_delta = nodes.new("ShaderNodeMath")
    brow_z_delta.operation = "SUBTRACT"
    links.new(separate.outputs["Z"], brow_z_delta.inputs[0])
    links.new(brow_arch.outputs[0], brow_z_delta.inputs[1])
    brow_z_norm = nodes.new("ShaderNodeMath")
    brow_z_norm.name = "BrowZScale"
    brow_z_norm.operation = "DIVIDE"
    brow_z_norm.inputs[1].default_value = 0.00235
    links.new(brow_z_delta.outputs[0], brow_z_norm.inputs[0])
    brow_z_sq = nodes.new("ShaderNodeMath")
    brow_z_sq.operation = "MULTIPLY"
    links.new(brow_z_norm.outputs[0], brow_z_sq.inputs[0])
    links.new(brow_z_norm.outputs[0], brow_z_sq.inputs[1])
    brow_ellipse = nodes.new("ShaderNodeMath")
    brow_ellipse.operation = "ADD"
    links.new(brow_x_sq.outputs[0], brow_ellipse.inputs[0])
    links.new(brow_z_sq.outputs[0], brow_ellipse.inputs[1])
    brow_falloff = nodes.new("ShaderNodeMapRange")
    brow_falloff.clamp = True
    brow_falloff.inputs["From Min"].default_value = 0.55
    brow_falloff.inputs["From Max"].default_value = 1.0
    brow_falloff.inputs["To Min"].default_value = 0.78
    brow_falloff.inputs["To Max"].default_value = 0.0
    links.new(brow_ellipse.outputs[0], brow_falloff.inputs["Value"])
    brow_front = nodes.new("ShaderNodeMath")
    brow_front.name = "BrowFrontLimit"
    brow_front.operation = "LESS_THAN"
    brow_front.inputs[1].default_value = -0.075
    links.new(separate.outputs["Y"], brow_front.inputs[0])
    brow_mask = nodes.new("ShaderNodeMath")
    brow_mask.operation = "MULTIPLY"
    links.new(brow_falloff.outputs[0], brow_mask.inputs[0])
    links.new(brow_front.outputs[0], brow_mask.inputs[1])
    brow_mix = nodes.new("ShaderNodeMixRGB")
    brow_mix.inputs[2].default_value = (0.006, 0.0009, 0.00028, 1.0)
    links.new(brow_mask.outputs[0], brow_mix.inputs[0])
    links.new(stubble_mix.outputs["Color"], brow_mix.inputs[1])
    # Soft scalp pigment beneath the explicit rooted groom. This avoids a
    # separate cap shell while giving short hair realistic optical density.
    scalp_y = nodes.new("ShaderNodeMapRange")
    scalp_y.name = "ScalpYGradient"
    scalp_y.clamp = True
    scalp_y.interpolation_type = "SMOOTHERSTEP"
    scalp_y.inputs["From Min"].default_value = -0.060
    scalp_y.inputs["From Max"].default_value = 0.100
    scalp_y.inputs["To Min"].default_value = 0.0
    scalp_y.inputs["To Max"].default_value = 1.0
    links.new(separate.outputs["Y"], scalp_y.inputs["Value"])
    scalp_drop = nodes.new("ShaderNodeMath")
    scalp_drop.name = "ScalpBackDrop"
    scalp_drop.operation = "MULTIPLY"
    scalp_drop.inputs[1].default_value = 0.070
    links.new(scalp_y.outputs["Result"], scalp_drop.inputs[0])
    scalp_threshold_node = nodes.new("ShaderNodeMath")
    scalp_threshold_node.name = "ScalpFrontZ"
    scalp_threshold_node.operation = "SUBTRACT"
    scalp_threshold_node.inputs[0].default_value = 1.795
    links.new(scalp_drop.outputs[0], scalp_threshold_node.inputs[1])
    scalp_delta = nodes.new("ShaderNodeMath")
    scalp_delta.operation = "SUBTRACT"
    links.new(separate.outputs["Z"], scalp_delta.inputs[0])
    links.new(scalp_threshold_node.outputs[0], scalp_delta.inputs[1])
    scalp_mask = nodes.new("ShaderNodeMapRange")
    scalp_mask.name = "ScalpSoftMask"
    scalp_mask.clamp = True
    scalp_mask.interpolation_type = "SMOOTHERSTEP"
    scalp_mask.inputs["From Min"].default_value = -0.016
    scalp_mask.inputs["From Max"].default_value = 0.018
    scalp_mask.inputs["To Min"].default_value = 0.0
    scalp_mask.inputs["To Max"].default_value = 0.56
    links.new(scalp_delta.outputs[0], scalp_mask.inputs["Value"])
    scalp_mix = nodes.new("ShaderNodeMixRGB")
    scalp_mix.name = "ScalpPigmentMix"
    scalp_mix.inputs[2].default_value = (0.020, 0.0060, 0.0025, 1.0)
    links.new(scalp_mask.outputs["Result"], scalp_mix.inputs[0])
    links.new(brow_mix.outputs["Color"], scalp_mix.inputs[1])
    links.new(scalp_mix.outputs["Color"], socket(bsdf, "Base Color"))

    pore_noise = nodes.new("ShaderNodeTexNoise")
    pore_noise.inputs["Scale"].default_value = 185.0
    pore_noise.inputs["Detail"].default_value = 3.5
    pore_noise.inputs["Roughness"].default_value = 0.72
    links.new(geometry.outputs["Position"], pore_noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.16
    bump.inputs["Distance"].default_value = 0.00055
    links.new(pore_noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    socket(bsdf, "Roughness").default_value = 0.70
    subsurface = socket(bsdf, "Subsurface Weight", "Subsurface")
    if subsurface:
        subsurface.default_value = 0.035
    return material


def make_hair_material():
    material = make_simple_material("HeroHair.ProfessionalWIP", (0.018, 0.0055, 0.0025, 1.0), 0.72)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 285.0
    noise.inputs["Detail"].default_value = 2.5
    noise.inputs["Roughness"].default_value = 0.70
    geometry = nodes.new("ShaderNodeNewGeometry")
    links.new(geometry.outputs["Position"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.0012, 0.00022, 0.00008, 1.0)
    ramp.color_ramp.elements[1].color = (0.012, 0.0026, 0.0010, 1.0)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], socket(bsdf, "Base Color"))
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.38
    bump.inputs["Distance"].default_value = 0.0007
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    anisotropic = socket(bsdf, "Anisotropic IOR Level", "Anisotropic")
    if anisotropic:
        anisotropic.default_value = 0.42
    specular = socket(bsdf, "Specular IOR Level", "Specular")
    if specular:
        specular.default_value = 0.16
    return material


def make_brow_material():
    material = make_simple_material(
        "HeroBrows.ProfessionalWIP", (0.003, 0.00042, 0.00012, 1.0), 0.82,
    )
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    specular = socket(bsdf, "Specular IOR Level", "Specular")
    if specular:
        specular.default_value = 0.18
    return material


def apply_target(human, target_root, relative_path, weight):
    path = os.path.join(target_root, relative_path)
    if not os.path.isfile(path):
        raise RuntimeError(f"Required MPFB target is missing: {path}")
    TargetService.load_target(human, path, weight=weight)


def create_professional_human():
    macro = TargetService.get_default_macro_info_dict()
    macro.update({
        # MPFB's gender macro is 0=female, 1=male.  The original professional
        # WIP accidentally used 0.0 and then tried to recover masculinity with
        # local jaw targets.  Start from an adult male phenotype so the brow,
        # midface, jaw and cranium all agree anatomically.
        "gender": 1.0,
        "age": 0.57,
        "muscle": 0.82,
        "weight": 0.51,
        "height": 0.60,
        "proportions": 0.61,
        "race": {"caucasian": 0.82, "african": 0.08, "asian": 0.10},
    })
    human = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro,
    )
    human.name = "HeroProfessionalTopology"
    targets = LocationService.get_mpfb_data("targets")
    for relative_path, weight in (
        ("head/head-square.target.gz", 0.58),
        ("head/head-rectangular.target.gz", 0.23),
        ("head/head-oval.target.gz", 0.03),
        ("head/head-fat-decr.target.gz", 0.18),
        ("head/head-age-incr.target.gz", 0.30),
        ("head/head-scale-vert-decr.target.gz", 0.07),
        ("head/head-scale-horiz-incr.target.gz", 0.085),
        ("chin/chin-width-incr.target.gz", 0.68),
        ("chin/chin-prominent-incr.target.gz", 0.54),
        ("chin/chin-bones-incr.target.gz", 0.50),
        ("chin/chin-height-incr.target.gz", 0.13),
        ("chin/chin-cleft-incr.target.gz", 0.12),
        ("forehead/forehead-temple-incr.target.gz", 0.26),
        ("forehead/forehead-trans-backward.target.gz", 0.075),
        ("cheek/l-cheek-bones-incr.target.gz", 0.44),
        ("cheek/r-cheek-bones-incr.target.gz", 0.44),
        ("cheek/l-cheek-volume-decr.target.gz", 0.21),
        ("cheek/r-cheek-volume-decr.target.gz", 0.21),
        ("cheek/l-cheek-inner-incr.target.gz", 0.055),
        ("cheek/r-cheek-inner-incr.target.gz", 0.055),
        ("eyes/l-eye-scale-decr.target.gz", 0.34),
        ("eyes/r-eye-scale-decr.target.gz", 0.34),
        ("eyes/l-eye-height1-decr.target.gz", 0.10),
        ("eyes/r-eye-height1-decr.target.gz", 0.10),
        ("eyes/l-eye-height2-decr.target.gz", 0.20),
        ("eyes/r-eye-height2-decr.target.gz", 0.20),
        ("eyes/l-eye-height3-decr.target.gz", 0.10),
        ("eyes/r-eye-height3-decr.target.gz", 0.10),
        ("eyes/l-eye-push1-in.target.gz", 0.085),
        ("eyes/r-eye-push1-in.target.gz", 0.085),
        ("eyes/l-eye-push2-in.target.gz", 0.060),
        ("eyes/r-eye-push2-in.target.gz", 0.060),
        ("eyes/l-eye-eyefold-convex.target.gz", 0.11),
        ("eyes/r-eye-eyefold-convex.target.gz", 0.11),
        ("eyes/l-eye-bag-incr.target.gz", 0.065),
        ("eyes/r-eye-bag-incr.target.gz", 0.065),
        ("eyes/l-eye-bag-in.target.gz", 0.025),
        ("eyes/r-eye-bag-in.target.gz", 0.025),
        ("eyebrows/eyebrows-angle-down.target.gz", 0.13),
        ("eyebrows/eyebrows-trans-down.target.gz", 0.070),
        ("nose/nose-scale-horiz-incr.target.gz", 0.12),
        ("nose/nose-width1-incr.target.gz", 0.10),
        ("nose/nose-width2-incr.target.gz", 0.08),
        ("nose/nose-width3-incr.target.gz", 0.15),
        ("nose/nose-flaring-incr.target.gz", 0.075),
        ("nose/nose-scale-vert-decr.target.gz", 0.025),
        ("nose/nose-scale-depth-incr.target.gz", 0.15),
        ("nose/nose-point-width-incr.target.gz", 0.11),
        ("nose/nose-hump-incr.target.gz", 0.055),
        ("nose/nose-volume-incr.target.gz", 0.045),
        ("mouth/mouth-scale-horiz-incr.target.gz", 0.16),
        ("mouth/mouth-scale-vert-decr.target.gz", 0.025),
        ("mouth/mouth-upperlip-volume-decr.target.gz", 0.055),
        ("mouth/mouth-lowerlip-volume-decr.target.gz", 0.040),
        ("mouth/mouth-upperlip-height-decr.target.gz", 0.035),
        ("mouth/mouth-lowerlip-height-decr.target.gz", 0.025),
        ("mouth/mouth-philtrum-volume-incr.target.gz", 0.08),
        ("mouth/mouth-laugh-lines-out.target.gz", 0.11),
        ("mouth/mouth-dimples-out.target.gz", 0.025),
        ("ears/l-ear-scale-decr.target.gz", 0.060),
        ("ears/r-ear-scale-decr.target.gz", 0.060),
        ("ears/l-ear-wing-decr.target.gz", 0.10),
        ("ears/r-ear-wing-decr.target.gz", 0.10),
        ("asym/asym-jaw-1-r.target.gz", 0.035),
        ("asym/asym-nose-2-l.target.gz", 0.025),
        ("asym/asym-mouth-1-r.target.gz", 0.018),
    ):
        apply_target(human, targets, relative_path, weight)
    human.data.materials.clear()
    human.data.materials.append(make_skin_material())
    for polygon in human.data.polygons:
        polygon.use_smooth = True
    subdivision = human.modifiers.new("ProfessionalTopologySubdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1
    human["replacement_role"] = "professional_reference_led_human_topology"
    human["reference_image"] = REFERENCE_PATH
    human["approval_state"] = "wip_not_integrated"
    return human


def group_indices(obj, names):
    group_ids = {obj.vertex_groups[name].index for name in names if obj.vertex_groups.get(name)}
    selected = set()
    for vertex in obj.data.vertices:
        if any(member.group in group_ids and member.weight > 0.01 for member in vertex.groups):
            selected.add(vertex.index)
    return selected


def extract_groups_evaluated(source, names, object_name, material):
    selected = group_indices(source, names)
    if not selected:
        raise RuntimeError(f"No vertices found for {names}")
    # Preserve original vertex indexing while extracting helper groups. A
    # subdivision modifier changes indices and can accidentally pull unrelated
    # face/ear polygons into the extracted object.
    masks = [
        (modifier, modifier.show_viewport, modifier.show_render)
        for modifier in source.modifiers if modifier.type in {"MASK", "SUBSURF"}
    ]
    for modifier, _view, _render in masks:
        modifier.show_viewport = False
        modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source.evaluated_get(depsgraph)
    evaluated_mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    polygons = [polygon for polygon in evaluated_mesh.polygons if all(index in selected for index in polygon.vertices)]
    used = sorted({index for polygon in polygons for index in polygon.vertices})
    mapping = {old: new for new, old in enumerate(used)}
    vertices = [tuple(evaluated_mesh.vertices[index].co) for index in used]
    faces = [tuple(mapping[index] for index in polygon.vertices) for polygon in polygons]
    evaluated.to_mesh_clear()
    for modifier, view, render in masks:
        modifier.show_viewport = view
        modifier.show_render = render
    mesh = bpy.data.meshes.new(object_name + ".Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(object_name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def group_bounds(obj, name):
    indices = group_indices(obj, (name,))
    points = [obj.data.vertices[index].co for index in indices]
    return (
        Vector(tuple(min(point[axis] for point in points) for axis in range(3))),
        Vector(tuple(max(point[axis] for point in points) for axis in range(3))),
    )


def add_ellipsoid(name, location, scale, material, segments=40, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=1.0, location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def build_eyes_and_lashes(human):
    sclera = make_simple_material("EyeSclera.ProfessionalWIP", (0.57, 0.51, 0.43, 1.0), 0.42)
    iris = make_simple_material("Iris.ProfessionalWIP", (0.030, 0.011, 0.0035, 1.0), 0.38)
    pupil = make_simple_material("Pupil.ProfessionalWIP", (0.004, 0.002, 0.001, 1.0), 0.30)
    eye_mesh = extract_groups_evaluated(
        human, ("helper-l-eye", "helper-r-eye"), "Eyes.ProfessionalWIP", sclera,
    )
    eye_mesh["facial_feature"] = "seated_helper_eyeballs"
    subdivision = eye_mesh.modifiers.new("EyeSurfaceSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    centers = {}
    for label, sign in (("l", 1.0), ("r", -1.0)):
        points = [vertex.co for vertex in eye_mesh.data.vertices if vertex.co.x * sign > 0.0]
        minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
        maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
        center = (minimum + maximum) * 0.5
        centers[sign] = center.copy()
        front_y = minimum.y - 0.00035
        iris_obj = add_ellipsoid(
            f"Iris.{label.upper()}",
            (center.x, front_y, center.z),
            (0.0050, 0.00078, 0.0050),
            iris,
        )
        pupil_obj = add_ellipsoid(
            f"Pupil.{label.upper()}",
            (center.x, front_y - 0.00075, center.z),
            (0.00225, 0.00048, 0.00225),
            pupil,
            segments=32,
            rings=20,
        )
        iris_obj["facial_feature"] = "recessed_iris"
        pupil_obj["facial_feature"] = "recessed_pupil"
    return centers


def current_body_tree(human):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return BVHTree.FromObject(human, depsgraph)


def face_surface_y(tree, x, z):
    hit, _normal, _index, _distance = tree.ray_cast(Vector((x, -0.30, z)), Vector((0.0, 1.0, 0.0)), 0.50)
    if hit is None:
        raise RuntimeError(f"Could not find face surface at x={x}, z={z}")
    return hit.y


def add_curve(name, points, bevel_depth, material, radii=None, resolution=2):
    curve = bpy.data.curves.new(name + ".Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = resolution
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for index, control in enumerate(spline.bezier_points):
        control.co = points[index]
        control.handle_left_type = "AUTO"
        control.handle_right_type = "AUTO"
        if radii:
            control.radius = radii[index]
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def build_eyebrows(human, hair_material, eye_centers):
    tree = current_body_tree(human)
    strands = []
    for side in (-1.0, 1.0):
        eye_center = eye_centers[side]
        strip_vertices = []
        strip_faces = []
        for index in range(11):
            u = index / 10.0
            x_abs = abs(eye_center.x) - 0.014 + 0.035 * u
            x = side * x_abs
            arch = 0.0065 * sin(pi * u)
            center_z = eye_center.z + 0.0215 + arch - 0.0020 * u
            thickness = 0.00055 + 0.0040 * (sin(pi * u) ** 0.55)
            for z in (center_z - thickness * 0.5, center_z + thickness * 0.5):
                y = face_surface_y(tree, x, z) - 0.00080
                strip_vertices.append((x, y, z))
        for index in range(10):
            strip_faces.append((2 * index, 2 * index + 2, 2 * index + 3, 2 * index + 1))
        mesh = bpy.data.meshes.new(f"BrowSurface.{side:+.0f}.Mesh")
        mesh.from_pydata(strip_vertices, [], strip_faces)
        mesh.update()
        brow = bpy.data.objects.new(f"BrowSurface.{side:+.0f}", mesh)
        bpy.context.collection.objects.link(brow)
        brow.data.materials.append(hair_material)
        bevel = brow.modifiers.new("BrowEdgeSoftness", "BEVEL")
        bevel.width = 0.00016
        bevel.segments = 2
        brow["facial_feature"] = "face_conforming_brow_surface"
        strands.append(brow)

        for row in range(3):
            points = []
            for index in range(9):
                u = index / 8.0
                x_abs = abs(eye_center.x) - 0.014 + 0.035 * u
                x = side * x_abs
                arch = 0.0065 * sin(pi * u)
                z = eye_center.z + 0.0215 + arch - 0.0020 * u + row * 0.00070
                y = face_surface_y(tree, x, z) - (0.00090 + row * 0.00008)
                points.append((x, y, z))
            strand = add_curve(
                f"BrowHair.{side:+.0f}.{row}", points, 0.00048, hair_material,
                radii=(0.45, 0.70, 0.90, 1.0, 1.0, 0.90, 0.75, 0.55, 0.30),
                resolution=2,
            )
            strand["facial_feature"] = "surface_following_brow_hair"
            strands.append(strand)
    return strands


def build_eyebrow_groom(human, hair_material, eye_centers):
    """Root fine eyebrow hairs directly on the evaluated facial surface."""
    random.seed(7719)
    tree = current_body_tree(human)
    curve = bpy.data.curves.new("Brows.RootedGroom.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00028
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    for side in (-1.0, 1.0):
        eye_z = eye_centers[side].z
        for _index in range(380):
            u = random.random()
            x_abs = 0.012 + 0.041 * u
            x = side * x_abs
            center_z = eye_z + 0.0225 + 0.0062 * sin(pi * u) - 0.0015 * u
            half_height = 0.0006 + 0.0027 * (sin(pi * u) ** 0.62)
            z = center_z + random.uniform(-half_height, half_height)
            direction_x = side * (0.0020 + 0.0012 * u)
            direction_z = 0.0017 * (1.0 - u) - 0.0007 * u
            end_x = x + direction_x
            end_z = z + direction_z
            try:
                y0 = face_surface_y(tree, x, z) - 0.00034
                y1 = face_surface_y(tree, end_x, end_z) - 0.00036
            except RuntimeError:
                continue
            spline = curve.splines.new("POLY")
            spline.points.add(1)
            spline.points[0].co = (x, y0, z, 1.0)
            spline.points[0].radius = 0.78
            spline.points[1].co = (end_x, y1, end_z, 1.0)
            spline.points[1].radius = 0.12
    brows = bpy.data.objects.new("Brows.RootedGroom", curve)
    bpy.context.collection.objects.link(brows)
    brows.data.materials.append(hair_material)
    brows["facial_feature"] = "surface_rooted_individual_brow_hairs"
    return brows


def build_facial_stubble(human, hair_material):
    """Root short irregular beard hairs directly into the evaluated face."""
    random.seed(41831)
    tree = current_body_tree(human)
    curve = bpy.data.curves.new("Face.RootedStubble.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.000105
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    added = 0
    for _attempt in range(4200):
        x = random.uniform(-0.078, 0.078)
        ax = abs(x)
        z = random.uniform(1.565, 1.716)
        lower_beard = z < 1.648
        cheek_beard = z < 1.695 and ax > 0.040
        moustache = (
            1.680 < z < 1.704
            and 0.014 < ax < 0.055
        )
        if not (lower_beard or cheek_beard or moustache):
            continue
        # Keep the actual lip surfaces clean and avoid a solid beard boundary.
        if abs(z - SOURCE_LIP_Z) < 0.015 and ax < 0.043:
            continue
        if random.random() > (0.52 if cheek_beard else 0.70):
            continue
        hit, normal, _index, _distance = tree.ray_cast(
            Vector((x, -0.30, z)), Vector((0.0, 1.0, 0.0)), 0.50,
        )
        if hit is None or hit.y > -0.035:
            continue
        normal.normalize()
        length = random.uniform(0.0011, 0.0024)
        drift = Vector((random.uniform(-0.00045, 0.00045), 0.0, -random.uniform(0.00015, 0.00070)))
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        root = hit + normal * 0.00020
        tip = root + normal * length + drift
        spline.points[0].co = (*root, 1.0)
        spline.points[0].radius = 0.72
        spline.points[1].co = (*tip, 1.0)
        spline.points[1].radius = 0.08
        added += 1
        if added >= 1350:
            break
    stubble = bpy.data.objects.new("Face.RootedStubble", curve)
    bpy.context.collection.objects.link(stubble)
    stubble.data.materials.append(hair_material)
    stubble["facial_feature"] = "surface_rooted_short_stubble"
    stubble["hair_count"] = added
    return stubble


def evaluated_mesh_snapshot(source):
    # Keep subdivision here: evaluated vertex weights are interpolated, giving
    # the scalp a dense, smooth hairline instead of a coarse polygon staircase.
    masks = [
        (modifier, modifier.show_viewport, modifier.show_render)
        for modifier in source.modifiers if modifier.type == "MASK"
    ]
    for modifier, _view, _render in masks:
        modifier.show_viewport = False
        modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    for modifier, view, render in masks:
        modifier.show_viewport = view
        modifier.show_render = render
    return mesh


def scalp_threshold(x, y):
    """Continuous adult crop boundary in source-head coordinates."""
    ax = abs(x)
    # Compensate for the coarse central forehead quad layout. Without this
    # smooth center lift, one entire low polygon row becomes a square forelock.
    center_lift = 0.006 * max(0.0, 1.0 - ax / 0.040) ** 2
    frontal = (
        1.663 + MALE_LANDMARK_Z_SHIFT + center_lift
        + 0.0045 * min(1.0, ax / 0.082) ** 1.7
    )
    if y < -0.055:
        return frontal
    if y < 0.030:
        transition = (y + 0.055) / 0.085
        side = (
            1.600 + MALE_LANDMARK_Z_SHIFT
            + 0.008 * max(0.0, min(1.0, (ax - 0.045) / 0.045))
        )
        return frontal * (1.0 - transition) + side * transition
    backness = max(0.0, min(1.0, (y - 0.030) / 0.120))
    return 1.600 + MALE_LANDMARK_Z_SHIFT - 0.052 * backness


def build_scalp_cap(human, hair_material):
    source = evaluated_mesh_snapshot(human)
    body_group = human.vertex_groups.get("body")
    if body_group is None:
        raise RuntimeError("MPFB body group required for clean scalp extraction")

    def group_weight(vertex, group_index):
        return max((member.weight for member in vertex.groups if member.group == group_index), default=0.0)

    selected_faces = []
    for polygon in source.polygons:
        if not all(group_weight(source.vertices[index], body_group.index) > 0.50 for index in polygon.vertices):
            continue
        points = [source.vertices[index].co for index in polygon.vertices]
        center = sum(points, Vector()) / len(points)
        x, y, z = center
        ax = abs(x)
        if (
            ax > 0.074 and -0.062 < y < 0.048
            and z < 1.665 + MALE_LANDMARK_Z_SHIFT
        ):
            # Geometric backup exclusion around the ear opening.
            continue
        # Adult crop: a clean, slightly receded front hairline, close sides,
        # and a tapered nape. The continuous threshold avoids a bowl fringe.
        threshold = scalp_threshold(x, y)
        # Select by polygon center instead of requiring every corner above the
        # threshold.  The old all-corners rule turned the boundary into a row
        # of triangular teeth after subdivision.
        irregularity = 0.00025 * sin(61.0 * x + 17.0 * y)
        if center.z <= threshold + irregularity:
            continue
        # Helper-mask topology can contain long triangles whose center lies in
        # the scalp while one corner reaches the ear or neck. Those produced
        # the isolated black spikes seen in review renders.
        if any(
            point.z < scalp_threshold(point.x, point.y) - 0.022
            for point in points
        ):
            continue
        longest_edge = max(
            (points[(index + 1) % len(points)] - points[index]).length
            for index in range(len(points))
        )
        if longest_edge > 0.030:
            continue
        selected_faces.append(polygon)
    edge_counts = {}
    for polygon in selected_faces:
        indices = list(polygon.vertices)
        for corner, index in enumerate(indices):
            edge = tuple(sorted((index, indices[(corner + 1) % len(indices)])))
            edge_counts[edge] = edge_counts.get(edge, 0) + 1
    boundary_edges = []
    boundary_indices = set()
    for (first, second), count in edge_counts.items():
        if count != 1:
            continue
        midpoint = (source.vertices[first].co + source.vertices[second].co) * 0.5
        if abs(midpoint.z - scalp_threshold(midpoint.x, midpoint.y)) > 0.030:
            # Ear-helper and lower body-mask boundaries are not hairlines.
            continue
        boundary_indices.update((first, second))
        boundary_edges.append((
            source.vertices[first].co.copy(),
            source.vertices[second].co.copy(),
            source.vertices[first].normal.copy(),
            source.vertices[second].normal.copy(),
        ))

    used = sorted({index for polygon in selected_faces for index in polygon.vertices})
    mapping = {old: new for new, old in enumerate(used)}
    vertices = []
    for index in used:
        vertex = source.vertices[index]
        point = vertex.co + vertex.normal * 0.0018
        desired = scalp_threshold(point.x, point.y)
        if (
            index in boundary_indices and point.y < 0.025
            and abs(point.z - desired) < 0.030
        ):
            # Snap only the extracted boundary to the analytic curve. This
            # removes topology-dependent center blocks and triangular steps.
            point.z = desired + 0.00035 * sin(43.0 * point.x)
        vertices.append(tuple(point))
    faces = [tuple(mapping[index] for index in polygon.vertices) for polygon in selected_faces]
    # Keep a weighted triangle surface for the actual groom before freeing the
    # temporary snapshot. Each tuple stores points, normals, and area.
    groom_surface = []
    for polygon in selected_faces:
        indices = list(polygon.vertices)
        for corner in range(1, len(indices) - 1):
            tri_indices = (indices[0], indices[corner], indices[corner + 1])
            tri_points = tuple(source.vertices[index].co.copy() for index in tri_indices)
            tri_normals = tuple(source.vertices[index].normal.copy() for index in tri_indices)
            area = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0]).length * 0.5
            if area > 1e-10:
                groom_surface.append((tri_points, tri_normals, area))
    bpy.data.meshes.remove(source)
    # Build a smooth skull-conforming underlayer independently of the helper
    # topology. The extracted mesh is excellent for rooting the groom, but its
    # forehead face layout generated a central block when used as a visible cap.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=64)
    scalp = bpy.context.object
    scalp.name = "HairScalp.ProfessionalWIP"
    scalp.data.name = "HairScalp.ProfessionalWIP.Mesh"
    center = Vector((0.0, -0.001, 1.742))
    radii = Vector((0.0795, 0.1105, 0.1305))
    for vertex in scalp.data.vertices:
        direction = vertex.co.normalized()
        point = center + Vector((
            direction.x * radii.x,
            direction.y * radii.y,
            direction.z * radii.z,
        ))
        vertex.co = point
    scalp.data.update()
    # Keep only the skull shell above the analytic crop boundary. Clamping the
    # lower hemisphere produced a visible rear helmet shell; a true cut leaves
    # a thin surface that follows the head.
    bm = bmesh.new()
    bm.from_mesh(scalp.data)
    remove = [
        vertex for vertex in bm.verts
        if vertex.co.z < scalp_threshold(vertex.co.x, vertex.co.y) + 0.0012
    ]
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(scalp.data)
    bm.free()
    scalp.data.update()
    # primitive_uv_sphere_add already links the object to the active collection.
    scalp.data.materials.append(hair_material)
    for polygon in scalp.data.polygons:
        polygon.use_smooth = True
    texture = bpy.data.textures.new("HairScalpBreakup", type="CLOUDS")
    texture.noise_scale = 0.006
    texture.noise_depth = 2
    displace = scalp.modifiers.new("HairScalpBreakup", "DISPLACE")
    displace.texture = texture
    displace.strength = 0.00038
    displace.mid_level = 0.52
    scalp["hair_style"] = "smooth_parametric_skull_underlayer"
    return scalp, groom_surface, boundary_edges


def build_hairline_edge_groom(boundary_edges, hair_material):
    """Break the scalp boundary with rooted micro-locks instead of a hard cap."""
    random.seed(93019)
    curve = bpy.data.curves.new("Hair.EdgeGroom.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00022
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    count = 0
    for point_a, point_b, normal_a, normal_b in boundary_edges:
        edge_length = (point_b - point_a).length
        samples = max(2, int(edge_length / 0.0016))
        for sample in range(samples):
            t = (sample + random.uniform(0.15, 0.85)) / samples
            root = point_a.lerp(point_b, t)
            normal = normal_a.lerp(normal_b, t).normalized()
            up = Vector((0.0, 0.0, 1.0))
            up -= normal * up.dot(normal)
            if up.length_squared < 1e-8:
                continue
            up.normalize()
            side = Vector((random.uniform(-0.28, 0.28), 0.0, 0.0))
            side -= normal * side.dot(normal)
            flow = up + side
            flow.normalize()
            length = random.uniform(0.0045, 0.0085)
            spline = curve.splines.new("POLY")
            spline.points.add(2)
            points = (
                root + normal * 0.00065,
                root + normal * 0.0012 + flow * (length * 0.45),
                root + normal * 0.0010 + flow * length,
            )
            for index, point in enumerate(points):
                spline.points[index].co = (*point, 1.0)
                spline.points[index].radius = (0.78, 0.66, 0.08)[index]
            count += 1
    groom = bpy.data.objects.new("Hair.EdgeGroom", curve)
    bpy.context.collection.objects.link(groom)
    groom.data.materials.append(hair_material)
    groom["hair_style"] = "surface_rooted_hairline_transition"
    groom["strand_count"] = count
    return groom


def scalp_point(tree, theta, phi, lift=0.0):
    center = Vector((0.0, -0.004, 1.594 + MALE_LANDMARK_Z_SHIFT))
    c = cos(phi)
    direction = Vector((sin(theta) * c, cos(theta) * c, sin(phi))).normalized()
    hit, normal, _index, _distance = tree.ray_cast(center, direction, 0.25)
    if hit is None:
        return None
    if (
        abs(hit.x) > 0.070 and -0.055 < hit.y < 0.040
        and 1.49 + MALE_LANDMARK_Z_SHIFT < hit.z < 1.65 + MALE_LANDMARK_Z_SHIFT
    ):
        return None
    normal = normal.normalized()
    return hit + normal * lift, normal


def build_short_hair_groom(groom_surface, hair_material):
    """Create individually tapered, swept strands from the real scalp surface."""
    random.seed(93017)
    cumulative = []
    total_area = 0.0
    for triangle in groom_surface:
        total_area += triangle[2]
        cumulative.append(total_area)
    if total_area <= 0.0:
        raise RuntimeError("Hair groom has no usable scalp surface")

    curve = bpy.data.curves.new("Hair.ShortGroom.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00024
    curve.bevel_resolution = 1
    curve.resolution_u = 1
    curve.use_fill_caps = True

    import bisect
    for strand_index in range(9000):
        pick = random.random() * total_area
        tri = groom_surface[min(bisect.bisect_left(cumulative, pick), len(groom_surface) - 1)]
        points, normals, _area = tri
        r1 = random.random() ** 0.5
        r2 = random.random()
        weights = (1.0 - r1, r1 * (1.0 - r2), r1 * r2)
        root = sum((points[i] * weights[i] for i in range(3)), Vector())
        normal = sum((normals[i] * weights[i] for i in range(3)), Vector()).normalized()
        if root.z < scalp_threshold(root.x, root.y) - 0.004:
            continue

        topness = max(0.0, normal.z)
        frontness = max(0.0, min(1.0, (-root.y - 0.005) / 0.105))
        sideness = max(0.0, min(1.0, abs(root.x) / 0.090))
        length = (0.0060 + 0.0220 * topness ** 1.8) * random.uniform(0.76, 1.20)
        if frontness > 0.72 and root.z < 1.655:
            length *= 0.84
        boundary_distance = root.z - scalp_threshold(root.x, root.y)
        if boundary_distance < 0.020:
            length *= 0.24 + 0.76 * max(0.0, boundary_distance / 0.020)

        back = Vector((0.0, 1.0, 0.0))
        back -= normal * back.dot(normal)
        if back.length_squared < 1e-8:
            back = Vector((0.0, 1.0, 0.0))
        back.normalize()
        down = Vector((0.0, 0.0, -1.0))
        down -= normal * down.dot(normal)
        if down.length_squared > 1e-8:
            down.normalize()
        outward = Vector((1.0 if root.x >= 0.0 else -1.0, 0.0, 0.0))
        outward -= normal * outward.dot(normal)
        if outward.length_squared > 1e-8:
            outward.normalize()
        jitter = Vector((random.uniform(-1.0, 1.0), random.uniform(-0.5, 0.8), random.uniform(-0.25, 0.25)))
        jitter -= normal * jitter.dot(normal)
        if jitter.length_squared > 1e-8:
            jitter.normalize()
        flow = back * (0.78 + 0.22 * frontness) + down * (0.38 * sideness) + outward * (0.10 * sideness) + jitter * 0.12
        if flow.length_squared > 1e-8:
            flow.normalize()

        spline = curve.splines.new("POLY")
        spline.points.add(2)
        strand_points = (
            root + normal * 0.0010,
            root + normal * (length * 0.34) + flow * (length * 0.26),
            root + normal * (length * 0.40) + flow * (length * 0.88),
        )
        for index, point in enumerate(strand_points):
            spline.points[index].co = (*point, 1.0)
            spline.points[index].radius = (0.78, 1.0, 0.10)[index]

    groom = bpy.data.objects.new("Hair.ShortGroom", curve)
    bpy.context.collection.objects.link(groom)
    groom.data.materials.append(hair_material)
    groom["hair_style"] = "individual_surface_rooted_short_crop"
    groom["strand_count"] = 9000
    return groom


def build_hair_clumps(groom_surface, hair_material):
    """Add thicker directional locks so the crop has designed volume."""
    import bisect
    random.seed(93018)
    cumulative = []
    total_area = 0.0
    for triangle in groom_surface:
        total_area += triangle[2]
        cumulative.append(total_area)
    curve = bpy.data.curves.new("Hair.DirectionalClumps.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00056
    curve.bevel_resolution = 2
    curve.use_fill_caps = True

    for _strand_index in range(1200):
        pick = random.random() * total_area
        points, normals, _area = groom_surface[min(bisect.bisect_left(cumulative, pick), len(groom_surface) - 1)]
        r1 = random.random() ** 0.5
        r2 = random.random()
        weights = (1.0 - r1, r1 * (1.0 - r2), r1 * r2)
        root = sum((points[i] * weights[i] for i in range(3)), Vector())
        normal = sum((normals[i] * weights[i] for i in range(3)), Vector()).normalized()
        if root.z < scalp_threshold(root.x, root.y) - 0.004:
            continue
        topness = max(0.0, normal.z)
        sideness = max(0.0, min(1.0, abs(root.x) / 0.090))
        length = (0.009 + 0.030 * topness ** 1.75) * random.uniform(0.72, 1.18)
        boundary_distance = root.z - scalp_threshold(root.x, root.y)
        if boundary_distance < 0.024:
            length *= 0.18 + 0.82 * max(0.0, boundary_distance / 0.024)

        back = Vector((0.0, 1.0, 0.0))
        back -= normal * back.dot(normal)
        if back.length_squared > 1e-8:
            back.normalize()
        down = Vector((0.0, 0.0, -1.0))
        down -= normal * down.dot(normal)
        if down.length_squared > 1e-8:
            down.normalize()
        side = Vector((random.uniform(-0.38, 0.38), 0.0, 0.0))
        side -= normal * side.dot(normal)
        flow = back * (0.82 + 0.20 * topness) + down * (0.34 * sideness) + side
        if flow.length_squared > 1e-8:
            flow.normalize()

        strand = curve.splines.new("POLY")
        strand.points.add(3)
        strand_points = (
            root + normal * 0.0011,
            root + normal * (length * 0.22) + flow * (length * 0.12),
            root + normal * (length * 0.34) + flow * (length * 0.50),
            root + normal * (length * 0.24) + flow * (length * 0.94),
        )
        for index, point in enumerate(strand_points):
            strand.points[index].co = (*point, 1.0)
            strand.points[index].radius = (0.55, 1.0, 0.72, 0.06)[index]

    clumps = bpy.data.objects.new("Hair.DirectionalClumps", curve)
    bpy.context.collection.objects.link(clumps)
    clumps.data.materials.append(hair_material)
    clumps["hair_style"] = "rooted_directional_short_locks"
    clumps["clump_count"] = 1200
    return clumps


def add_reference_empty():
    if not os.path.isfile(REFERENCE_PATH):
        return
    image = bpy.data.images.load(REFERENCE_PATH, check_existing=True)
    image.pack()
    empty = bpy.data.objects.new("REFERENCE_HeroHead_v1", None)
    empty.empty_display_type = "IMAGE"
    empty.data = image
    empty.empty_display_size = 0.75
    empty.location = (-0.65, 0.30, 1.52 + MALE_LANDMARK_Z_SHIFT)
    empty.rotation_euler = (pi / 2.0, 0.0, 0.0)
    empty.color[3] = 0.70
    empty.hide_render = True
    bpy.context.collection.objects.link(empty)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_stage():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.world.color = (0.023, 0.028, 0.038)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.35
    bpy.ops.object.camera_add(location=(0.0, -1.12, 1.545 + MALE_LANDMARK_Z_SHIFT))
    camera = bpy.context.active_object
    camera.name = "ProfessionalHeadReviewCamera"
    camera.data.lens = 92
    scene.camera = camera
    target = (0.0, -0.020, 1.535 + MALE_LANDMARK_Z_SHIFT)
    for name, location, energy, size, color in (
        ("ReviewKey", (-0.55, -0.62, 2.08 + MALE_LANDMARK_Z_SHIFT), 46.0, 0.55, (1.0, 0.82, 0.72)),
        ("ReviewFill", (0.63, -0.38, 1.90 + MALE_LANDMARK_Z_SHIFT), 23.0, 0.70, (0.72, 0.83, 1.0)),
        ("ReviewRim", (0.25, 0.44, 2.02 + MALE_LANDMARK_Z_SHIFT), 36.0, 0.50, (0.82, 0.90, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        aim(obj, target)
        scene.collection.objects.link(obj)
    return camera


def render_reviews(camera):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    views = (
        ("front", (0.0, -1.15, 1.545 + MALE_LANDMARK_Z_SHIFT), (0.0, -0.018, 1.535 + MALE_LANDMARK_Z_SHIFT), 92),
        ("threequarter", (0.73, -0.91, 1.555 + MALE_LANDMARK_Z_SHIFT), (0.0, -0.010, 1.535 + MALE_LANDMARK_Z_SHIFT), 94),
        ("profile", (1.18, -0.005, 1.545 + MALE_LANDMARK_Z_SHIFT), (0.0, 0.000, 1.530 + MALE_LANDMARK_Z_SHIFT), 96),
    )
    for name, location, target, lens in views:
        camera.location = location
        camera.data.lens = lens
        aim(camera, target)
        scene.render.filepath = os.path.join(OUTPUT_DIR, f"head_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"PROFESSIONAL_HEAD_RENDER|{name}|{scene.render.filepath}")


def main():
    clear_scene()
    human = create_professional_human()
    hair_material = make_hair_material()
    brow_material = make_brow_material()
    eye_centers = build_eyes_and_lashes(human)
    build_eyebrow_groom(human, brow_material, eye_centers)
    build_facial_stubble(human, brow_material)
    scalp, groom_surface, _boundary_edges = build_scalp_cap(human, hair_material)
    scalp.hide_render = True
    build_short_hair_groom(groom_surface, hair_material)
    build_hair_clumps(groom_surface, hair_material)
    add_reference_empty()
    camera = configure_stage()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    render_reviews(camera)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"PROFESSIONAL_HEAD_WIP_DONE|{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
