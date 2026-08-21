"""Prototype a single-topology professional full hero before game integration."""

from math import cos, pi, sin
import os
import random

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService


BLEND_DIR = os.path.abspath(
    os.environ.get(
        "BK_BLEND_DIR",
        os.path.join(os.path.expanduser("~"), "Desktop", "Broken Knight", "blender"),
    )
)
OUTPUT_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_FullContinuous_Prototype.blend")
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "hero_full_continuous_prototype")
SKIN_TEXTURE_PATH = os.path.join(BLEND_DIR, "textures", "hero_skin_micro_albedo_v1.png")
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


def material(name, color, roughness=0.72):
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    socket(bsdf, "Base Color").default_value = color
    socket(bsdf, "Roughness").default_value = roughness
    specular = socket(bsdf, "Specular IOR Level", "Specular")
    if specular is not None:
        specular.default_value = 0.26
    return result


def make_hair_material():
    result = material("HeroHair.FullContinuous", (0.020, 0.0065, 0.0028, 1.0), 0.79)
    # Direction is carried by the actual 11k strand curves and scalp geometry.
    # Keep the shader glTF-portable; Blender procedural Wave/Noise links are not
    # serialized by the exporter and arrived in Godot as a white material.
    return result
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    geometry = nodes.new("ShaderNodeNewGeometry")
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 150.0
    wave.inputs["Distortion"].default_value = 7.5
    wave.inputs["Detail"].default_value = 4.0
    wave.inputs["Detail Scale"].default_value = 2.5
    links.new(geometry.outputs["Position"], wave.inputs["Vector"])
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 72.0
    noise.inputs["Detail"].default_value = 5.0
    noise.inputs["Roughness"].default_value = 0.78
    links.new(geometry.outputs["Position"], noise.inputs["Vector"])
    multiply = nodes.new("ShaderNodeMath")
    multiply.operation = "MULTIPLY"
    links.new(wave.outputs["Color"], multiply.inputs[0])
    links.new(noise.outputs["Fac"], multiply.inputs[1])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.24
    ramp.color_ramp.elements[0].color = (0.006, 0.0012, 0.0005, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (0.040, 0.013, 0.006, 1.0)
    links.new(multiply.outputs[0], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], socket(bsdf, "Base Color"))
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.16
    bump.inputs["Distance"].default_value = 0.00065
    links.new(multiply.outputs[0], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    socket(bsdf, "Roughness").default_value = 0.79
    return result


def make_skin_material_procedural_legacy():
    """Neutral, matte skin without the former freckle-heavy packed albedo."""
    result = bpy.data.materials.new("HeroSkin.FullContinuous")
    result.diffuse_color = (0.36, 0.145, 0.115, 1.0)
    result.roughness = 0.78
    result.use_nodes = True
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    geometry = nodes.new("ShaderNodeNewGeometry")

    # The old box-projected micro-albedo read as dense freckles in Godot and
    # shifted the skin yellow under the warm world light. Keep the export base
    # deliberately clean; form now comes from geometry and lighting.
    base = nodes.new("ShaderNodeRGB")
    base.outputs[0].default_value = (0.36, 0.145, 0.115, 1.0)
    base_color = base.outputs[0]

    separate = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], separate.inputs["Vector"])

    # Smooth lip tint on the continuous topology: colored anatomy, never a
    # floating lip object or a polygonal decal.
    x_abs = nodes.new("ShaderNodeMath")
    x_abs.operation = "ABSOLUTE"
    links.new(separate.outputs["X"], x_abs.inputs[0])
    x_norm = nodes.new("ShaderNodeMath")
    x_norm.operation = "DIVIDE"
    x_norm.inputs[1].default_value = 0.036
    links.new(x_abs.outputs[0], x_norm.inputs[0])
    x_sq = nodes.new("ShaderNodeMath")
    x_sq.operation = "MULTIPLY"
    links.new(x_norm.outputs[0], x_sq.inputs[0])
    links.new(x_norm.outputs[0], x_sq.inputs[1])
    z_delta = nodes.new("ShaderNodeMath")
    z_delta.operation = "SUBTRACT"
    z_delta.inputs[1].default_value = SOURCE_LIP_Z
    links.new(separate.outputs["Z"], z_delta.inputs[0])
    z_norm = nodes.new("ShaderNodeMath")
    z_norm.operation = "DIVIDE"
    z_norm.inputs[1].default_value = 0.0132
    links.new(z_delta.outputs[0], z_norm.inputs[0])
    z_sq = nodes.new("ShaderNodeMath")
    z_sq.operation = "MULTIPLY"
    links.new(z_norm.outputs[0], z_sq.inputs[0])
    links.new(z_norm.outputs[0], z_sq.inputs[1])
    ellipse = nodes.new("ShaderNodeMath")
    ellipse.operation = "ADD"
    links.new(x_sq.outputs[0], ellipse.inputs[0])
    links.new(z_sq.outputs[0], ellipse.inputs[1])
    lip_falloff = nodes.new("ShaderNodeMapRange")
    lip_falloff.clamp = True
    lip_falloff.interpolation_type = "SMOOTHERSTEP"
    lip_falloff.inputs["From Min"].default_value = 0.50
    lip_falloff.inputs["From Max"].default_value = 1.0
    lip_falloff.inputs["To Min"].default_value = 0.72
    lip_falloff.inputs["To Max"].default_value = 0.0
    links.new(ellipse.outputs[0], lip_falloff.inputs["Value"])
    lip_front = nodes.new("ShaderNodeMath")
    lip_front.operation = "LESS_THAN"
    lip_front.inputs[1].default_value = -0.137
    links.new(separate.outputs["Y"], lip_front.inputs[0])
    lip_mask = nodes.new("ShaderNodeMath")
    lip_mask.operation = "MULTIPLY"
    links.new(lip_falloff.outputs["Result"], lip_mask.inputs[0])
    links.new(lip_front.outputs[0], lip_mask.inputs[1])
    lip_mix = nodes.new("ShaderNodeMixRGB")
    lip_mix.inputs[2].default_value = (0.24, 0.055, 0.038, 1.0)
    links.new(lip_mask.outputs[0], lip_mix.inputs[0])
    links.new(base_color, lip_mix.inputs[1])

    # Beard shadow breaks the blow-up-doll read while remaining subtle.
    beard_noise = nodes.new("ShaderNodeTexNoise")
    beard_noise.inputs["Scale"].default_value = 210.0
    beard_noise.inputs["Detail"].default_value = 2.2
    links.new(geometry.outputs["Position"], beard_noise.inputs["Vector"])
    x_limit = nodes.new("ShaderNodeMapRange")
    x_limit.clamp = True
    x_limit.inputs["From Min"].default_value = 0.055
    x_limit.inputs["From Max"].default_value = 0.090
    x_limit.inputs["To Min"].default_value = 1.0
    x_limit.inputs["To Max"].default_value = 0.0
    links.new(x_abs.outputs[0], x_limit.inputs["Value"])
    z_low = nodes.new("ShaderNodeMapRange")
    z_low.clamp = True
    z_low.inputs["From Min"].default_value = 1.565
    z_low.inputs["From Max"].default_value = 1.610
    z_low.inputs["To Min"].default_value = 0.0
    z_low.inputs["To Max"].default_value = 1.0
    links.new(separate.outputs["Z"], z_low.inputs["Value"])
    z_high = nodes.new("ShaderNodeMapRange")
    z_high.clamp = True
    z_high.inputs["From Min"].default_value = 1.690
    z_high.inputs["From Max"].default_value = 1.725
    z_high.inputs["To Min"].default_value = 1.0
    z_high.inputs["To Max"].default_value = 0.0
    links.new(separate.outputs["Z"], z_high.inputs["Value"])
    y_limit = nodes.new("ShaderNodeMath")
    y_limit.operation = "LESS_THAN"
    y_limit.inputs[1].default_value = 0.040
    links.new(separate.outputs["Y"], y_limit.inputs[0])
    beard_a = nodes.new("ShaderNodeMath")
    beard_a.operation = "MULTIPLY"
    links.new(x_limit.outputs["Result"], beard_a.inputs[0])
    links.new(z_low.outputs["Result"], beard_a.inputs[1])
    beard_b = nodes.new("ShaderNodeMath")
    beard_b.operation = "MULTIPLY"
    links.new(z_high.outputs["Result"], beard_b.inputs[0])
    links.new(y_limit.outputs[0], beard_b.inputs[1])
    beard_region = nodes.new("ShaderNodeMath")
    beard_region.operation = "MULTIPLY"
    links.new(beard_a.outputs[0], beard_region.inputs[0])
    links.new(beard_b.outputs[0], beard_region.inputs[1])
    beard_strength = nodes.new("ShaderNodeMath")
    beard_strength.operation = "MULTIPLY"
    beard_strength.inputs[1].default_value = 0.12
    links.new(beard_noise.outputs["Fac"], beard_strength.inputs[0])
    beard_final = nodes.new("ShaderNodeMath")
    beard_final.operation = "MULTIPLY"
    links.new(beard_region.outputs[0], beard_final.inputs[0])
    links.new(beard_strength.outputs[0], beard_final.inputs[1])
    beard_mix = nodes.new("ShaderNodeMixRGB")
    beard_mix.inputs[2].default_value = (0.045, 0.012, 0.006, 1.0)
    links.new(beard_final.outputs[0], beard_mix.inputs[0])
    links.new(lip_mix.outputs["Color"], beard_mix.inputs[1])
    links.new(beard_mix.outputs["Color"], socket(bsdf, "Base Color"))

    pore_noise = nodes.new("ShaderNodeTexNoise")
    pore_noise.inputs["Scale"].default_value = 235.0
    pore_noise.inputs["Detail"].default_value = 2.2
    pore_noise.inputs["Roughness"].default_value = 0.72
    links.new(geometry.outputs["Position"], pore_noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.035
    bump.inputs["Distance"].default_value = 0.00016
    links.new(pore_noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    socket(bsdf, "Roughness").default_value = 0.78
    specular = socket(bsdf, "Specular IOR Level", "Specular")
    if specular is not None:
        specular.default_value = 0.22
    subsurface = socket(bsdf, "Subsurface Weight", "Subsurface")
    if subsurface is not None:
        subsurface.default_value = 0.025
    return result


def make_skin_material():
    """Plain glTF material that arrives in Godot with the authored skin tone."""
    result = material("HeroSkin.FullContinuous", (0.36, 0.145, 0.105, 1.0), 0.78)
    result.diffuse_color = (0.36, 0.145, 0.105, 1.0)
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    socket(bsdf, "Base Color").default_value = result.diffuse_color
    socket(bsdf, "Roughness").default_value = 0.78
    specular = socket(bsdf, "Specular IOR Level", "Specular")
    if specular is not None:
        specular.default_value = 0.18
    return result


def assign_anatomical_materials(human):
    """Add portable lip colour without a floating lip mesh."""
    lip = material("HeroLips.FullContinuous", (0.24, 0.055, 0.042, 1.0), 0.72)
    human.data.materials.append(lip)
    assigned = 0
    for polygon in human.data.polygons:
        center = polygon.center
        if abs(center.x) < 0.042 and -0.170 < center.y < -0.132 and 1.650 < center.z < 1.683:
            polygon.material_index = 1
            assigned += 1
    human["portable_lip_faces"] = assigned


def apply_target(human, relative_path, weight):
    target_root = LocationService.get_mpfb_data("targets")
    path = os.path.join(target_root, relative_path)
    if not os.path.isfile(path):
        raise RuntimeError(f"Required target missing: {path}")
    TargetService.load_target(human, path, weight=weight)


def create_human():
    macro = TargetService.get_default_macro_info_dict()
    macro.update({
        "gender": 1.0,
        "age": 0.57,
        "muscle": 1.0,
        "weight": 0.40,
        "height": 0.60,
        "proportions": 0.63,
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
    human.name = "ConnectedBody"
    targets = (
        # Coherent adult hero head; reused from the accepted professional face.
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
        ("eyebrows/eyebrows-angle-down.target.gz", 0.13),
        ("eyebrows/eyebrows-trans-down.target.gz", 0.070),
        ("nose/nose-scale-horiz-incr.target.gz", 0.12),
        ("nose/nose-width1-incr.target.gz", 0.10),
        ("nose/nose-width2-incr.target.gz", 0.08),
        ("nose/nose-width3-incr.target.gz", 0.15),
        ("nose/nose-flaring-incr.target.gz", 0.075),
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
        ("ears/l-ear-scale-decr.target.gz", 0.060),
        ("ears/r-ear-scale-decr.target.gz", 0.060),
        ("ears/l-ear-wing-decr.target.gz", 0.10),
        ("ears/r-ear-wing-decr.target.gz", 0.10),
        # One anatomical head/neck/torso surface; no graft or overlap.
        ("neck/neck-scale-horiz-incr.target.gz", 0.31),
        ("neck/neck-scale-depth-incr.target.gz", 0.23),
        ("neck/neck-scale-vert-decr.target.gz", 0.17),
        ("neck/neck-back-scale-depth-incr.target.gz", 0.26),
        ("neck/neck-trans-backward.target.gz", 0.10),
        ("neck/measure-neck-circ-incr.target.gz", 0.18),
        ("torso/torso-vshape-incr.target.gz", 1.0),
        ("torso/measure-shoulder-dist-incr.target.gz", 0.84),
        ("torso/torso-muscle-pectoral-incr.target.gz", 0.86),
        ("torso/torso-muscle-dorsi-incr.target.gz", 1.0),
        ("torso/torso-scale-horiz-incr.target.gz", 0.24),
        ("torso/torso-scale-depth-incr.target.gz", 0.27),
        ("torso/measure-bust-circ-decr.target.gz", 0.10),
        ("torso/measure-underbust-circ-incr.target.gz", 0.18),
        ("torso/measure-waist-circ-decr.target.gz", 0.08),
        ("stomach/stomach-tone-incr.target.gz", 0.94),
        ("stomach/stomach-navel-in.target.gz", 0.12),
        ("breast/breast-point-decr.target.gz", 1.0),
        ("breast/breast-trans-up.target.gz", 0.24),
        ("breast/nipple-point-decr.target.gz", 0.46),
        ("breast/nipple-size-decr.target.gz", 0.20),
        ("buttocks/buttocks-volume-incr.target.gz", 0.30),
        ("pelvis/pelvis-tone-incr.target.gz", 0.54),
        # Strong natural limbs; the target forms remain continuous at joints.
        ("arms/l-upperarm-muscle-incr.target.gz", 0.90),
        ("arms/r-upperarm-muscle-incr.target.gz", 0.90),
        ("arms/l-upperarm-shoulder-muscle-incr.target.gz", 0.94),
        ("arms/r-upperarm-shoulder-muscle-incr.target.gz", 0.94),
        ("arms/l-lowerarm-muscle-incr.target.gz", 0.78),
        ("arms/r-lowerarm-muscle-incr.target.gz", 0.78),
        ("arms/measure-upperarm-circ-incr.target.gz", 0.17),
        ("arms/measure-upperarm-length-decr.target.gz", 0.16),
        ("arms/measure-lowerarm-length-decr.target.gz", 0.14),
        ("legs/l-upperleg-muscle-incr.target.gz", 0.80),
        ("legs/r-upperleg-muscle-incr.target.gz", 0.80),
        ("legs/l-lowerleg-muscle-incr.target.gz", 0.72),
        ("legs/r-lowerleg-muscle-incr.target.gz", 0.72),
        ("legs/measure-thigh-circ-incr.target.gz", 0.14),
        ("legs/measure-calf-circ-incr.target.gz", 0.11),
        ("hands/l-hand-scale-incr.target.gz", 0.08),
        ("hands/r-hand-scale-incr.target.gz", 0.08),
        ("feet/l-foot-scale-incr.target.gz", 0.06),
        ("feet/r-foot-scale-incr.target.gz", 0.06),
    )
    for path, weight in targets:
        apply_target(human, path, weight)

    human.data.materials.clear()
    human.data.materials.append(make_skin_material())
    assign_anatomical_materials(human)
    for polygon in human.data.polygons:
        polygon.use_smooth = True
    for modifier in human.modifiers:
        if modifier.type == "SUBSURF":
            modifier.levels = 1
            modifier.render_levels = 1
    if not any(modifier.type == "SUBSURF" for modifier in human.modifiers):
        subdivision = human.modifiers.new("FullHeroSurfaceSmoothing", "SUBSURF")
        subdivision.levels = 1
        subdivision.render_levels = 1
    human["topology"] = "single_continuous_professional_human"
    return human


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def anatomical_sculpt(human):
    """Large-form anatomical pass on the one continuous rest mesh.

    This deliberately modifies the body surface itself. It does not add muscle
    plates or seam-hiding geometry, so the head, neck, shoulders and torso stay
    one watertight deforming topology.
    """
    # MPFB uses negative Y as the visible front. Keep all offsets gradual at
    # joint zones to preserve the professional skinning weights.
    for vertex in human.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        original_x = x

        # Stronger clavicle/deltoid line and upper-lat taper.
        shoulder_z = smoothstep(1.29, 1.40, z) * (1.0 - smoothstep(1.49, 1.55, z))
        shoulder_x = smoothstep(0.145, 0.225, ax) * (1.0 - smoothstep(0.285, 0.37, ax))
        if shoulder_z > 0.0 and shoulder_x > 0.0:
            vertex.co.x += (1.0 if x >= 0.0 else -1.0) * 0.021 * shoulder_z * shoulder_x

        # Broad male pectoral plane. Flatten the low/central mound first, then
        # build a restrained upper shelf so the side view reads as rib cage
        # and pectoral mass rather than hanging breasts.
        pec_flat_z = smoothstep(1.205, 1.245, z) * (1.0 - smoothstep(1.330, 1.385, z))
        pec_flat_x = 1.0 - smoothstep(0.145, 0.220, ax)
        front_flat = smoothstep(-0.050, -0.095, y)
        if pec_flat_z > 0.0 and pec_flat_x > 0.0 and front_flat > 0.0:
            vertex.co.y += 0.0105 * pec_flat_z * pec_flat_x * front_flat

        # Upper pectoral shelf with a shallow central sternum valley.
        pec_z = smoothstep(1.245, 1.305, z) * (1.0 - smoothstep(1.385, 1.445, z))
        pec_x = smoothstep(0.018, 0.055, ax) * (1.0 - smoothstep(0.165, 0.225, ax))
        front = smoothstep(-0.055, -0.105, y)
        if pec_z > 0.0 and pec_x > 0.0 and front > 0.0:
            upper_bias = smoothstep(1.25, 1.34, z) * (1.0 - smoothstep(1.365, 1.43, z))
            vertex.co.y -= (0.0080 + 0.0075 * upper_bias) * pec_z * pec_x * front

        # Serratus/lat breadth beneath the armpit, blended back into the waist.
        lat_z = smoothstep(1.10, 1.22, z) * (1.0 - smoothstep(1.35, 1.44, z))
        lat_x = smoothstep(0.12, 0.18, ax) * (1.0 - smoothstep(0.225, 0.285, ax))
        if lat_z > 0.0 and lat_x > 0.0:
            vertex.co.x += (1.0 if x >= 0.0 else -1.0) * 0.016 * lat_z * lat_x

        # Rectus abdominis: three paired broad pads, a subtle linea alba and
        # oblique flank plane. The small offsets survive subdivision without
        # looking like separate chunks glued to the belly.
        front_ab = smoothstep(-0.035, -0.105, y)
        ab_x = smoothstep(0.004, 0.020, ax) * (1.0 - smoothstep(0.060, 0.095, ax))
        ab = 0.0
        for center, height, strength in ((1.205, 0.056, 0.0155), (1.125, 0.052, 0.0170), (1.047, 0.050, 0.0130)):
            dz = abs(z - center) / height
            ab += max(0.0, 1.0 - dz * dz) * strength
        if front_ab > 0.0 and ab_x > 0.0:
            vertex.co.y -= ab * ab_x * front_ab
        center_line = (1.0 - smoothstep(0.0, 0.012, ax)) * smoothstep(0.99, 1.04, z) * (1.0 - smoothstep(1.27, 1.31, z))
        if front_ab > 0.0 and center_line > 0.0:
            vertex.co.y += 0.0060 * center_line * front_ab
        oblique_z = smoothstep(0.96, 1.04, z) * (1.0 - smoothstep(1.22, 1.30, z))
        oblique_x = smoothstep(0.07, 0.11, ax) * (1.0 - smoothstep(0.14, 0.19, ax))
        if oblique_z > 0.0 and oblique_x > 0.0 and front_ab > 0.0:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.0075 * oblique_z * oblique_x

        # Male flank/waist plane.  The source target combination otherwise
        # pinches too abruptly beneath the lats and produces an hourglass
        # silhouette.  This broadens the obliques and quadratus region without
        # inflating the hips.
        waist_z = smoothstep(0.91, 0.99, z) * (1.0 - smoothstep(1.17, 1.26, z))
        waist_side = smoothstep(0.095, 0.125, ax) * (1.0 - smoothstep(0.175, 0.225, ax))
        if waist_z > 0.0 and waist_side > 0.0:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.016 * waist_z * waist_side

        # Arm form remains one skinned surface. Add restrained biceps/triceps
        # depth and forearm taper instead of disconnected muscle pieces.
        upper_arm = smoothstep(0.245, 0.285, ax) * (1.0 - smoothstep(0.425, 0.470, ax))
        upper_arm *= smoothstep(1.205, 1.255, z) * (1.0 - smoothstep(1.405, 1.475, z))
        if upper_arm > 0.0:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.0055 * upper_arm
            if y < -0.012:
                vertex.co.y -= 0.0060 * upper_arm * smoothstep(-0.012, -0.070, y)
            elif y > 0.005:
                vertex.co.y += 0.0042 * upper_arm * smoothstep(0.005, 0.060, y)
        forearm = smoothstep(0.405, 0.455, ax) * (1.0 - smoothstep(0.555, 0.600, ax))
        forearm *= smoothstep(1.105, 1.155, z) * (1.0 - smoothstep(1.285, 1.340, z))
        if forearm > 0.0:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.0032 * forearm

        # Neck base/trapezius blend. This is the critical anti-Frankenstein
        # transition: broaden only the lower neck and flow it into the clavicle.
        lower_neck = smoothstep(1.405, 1.455, z) * (1.0 - smoothstep(1.515, 1.565, z))
        neck_side = smoothstep(0.050, 0.072, ax) * (1.0 - smoothstep(0.105, 0.145, ax))
        if lower_neck > 0.0 and neck_side > 0.0:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.010 * lower_neck * neck_side
        nape = smoothstep(1.405, 1.47, z) * (1.0 - smoothstep(1.54, 1.59, z)) * smoothstep(0.005, 0.035, y)
        if nape > 0.0:
            vertex.co.y += 0.007 * nape

        # Thigh/calf silhouette definition without the old balloon-leg look.
        thigh_z = smoothstep(0.45, 0.58, z) * (1.0 - smoothstep(0.81, 0.90, z))
        if thigh_z > 0.0 and 0.10 < ax < 0.25:
            outer = smoothstep(0.10, 0.15, ax) * (1.0 - smoothstep(0.20, 0.25, ax))
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.0085 * thigh_z * outer
            if y < -0.015:
                vertex.co.y -= 0.0045 * thigh_z * outer
        calf_z = smoothstep(0.17, 0.28, z) * (1.0 - smoothstep(0.48, 0.60, z))
        if calf_z > 0.0 and 0.10 < ax < 0.23:
            vertex.co.x += (1.0 if original_x >= 0.0 else -1.0) * 0.0065 * calf_z

    human.data.update()
    human["anatomical_sculpt"] = "continuous_hero_large_forms_v2"


def evaluated_body_mesh(human):
    masks = [(modifier, modifier.show_viewport, modifier.show_render) for modifier in human.modifiers if modifier.type == "MASK"]
    for modifier, _viewport, _render in masks:
        modifier.show_viewport = False
        modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = human.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph, preserve_all_data_layers=True)
    for modifier, viewport, render in masks:
        modifier.show_viewport = viewport
        modifier.show_render = render
    return mesh


def group_weight(vertex, group_index):
    return max((member.weight for member in vertex.groups if member.group == group_index), default=0.0)


def extract_groups_evaluated(source, names, object_name, assigned_material):
    group_ids = {source.vertex_groups[name].index for name in names if source.vertex_groups.get(name)}
    selected = {
        vertex.index for vertex in source.data.vertices
        if any(member.group in group_ids and member.weight > 0.01 for member in vertex.groups)
    }
    if not selected:
        raise RuntimeError(f"No vertices found for groups {names}")
    disabled = [
        (modifier, modifier.show_viewport, modifier.show_render)
        for modifier in source.modifiers if modifier.type in {"MASK", "SUBSURF"}
    ]
    for modifier, _viewport, _render in disabled:
        modifier.show_viewport = False
        modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source.evaluated_get(depsgraph)
    evaluated_mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    polygons = [polygon for polygon in evaluated_mesh.polygons if all(index in selected for index in polygon.vertices)]
    used = sorted({index for polygon in polygons for index in polygon.vertices})
    mapping = {old: new for new, old in enumerate(used)}
    mesh = bpy.data.meshes.new(object_name + ".Mesh")
    mesh.from_pydata(
        [tuple(evaluated_mesh.vertices[index].co) for index in used], [],
        [tuple(mapping[index] for index in polygon.vertices) for polygon in polygons],
    )
    mesh.update()
    evaluated.to_mesh_clear()
    for modifier, viewport, render in disabled:
        modifier.show_viewport = viewport
        modifier.show_render = render
    obj = bpy.data.objects.new(object_name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(assigned_material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def add_ellipsoid(name, location, scale, assigned_material, segments=40, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=1.0, location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(assigned_material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def build_eyes(human):
    sclera = material("EyeSclera.FullContinuous", (0.52, 0.46, 0.38, 1.0), 0.48)
    iris_material = material("Iris.FullContinuous", (0.055, 0.025, 0.007, 1.0), 0.40)
    pupil_material = material("Pupil.FullContinuous", (0.002, 0.001, 0.0005, 1.0), 0.36)
    eye_mesh = extract_groups_evaluated(
        human, ("helper-l-eye", "helper-r-eye"), "ProfessionalEyes", sclera,
    )
    subdivision = eye_mesh.modifiers.new("EyeSurfaceSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    eyes = [eye_mesh]
    centers = {}
    for label, sign in (("L", 1.0), ("R", -1.0)):
        points = [vertex.co for vertex in eye_mesh.data.vertices if vertex.co.x * sign > 0.0]
        minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
        maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
        center = (minimum + maximum) * 0.5
        centers[sign] = center
        front_y = minimum.y - 0.00035
        eyes.append(add_ellipsoid(f"ProfessionalIris.{label}", (center.x, front_y, center.z), (0.0052, 0.00075, 0.0052), iris_material))
        eyes.append(add_ellipsoid(f"ProfessionalPupil.{label}", (center.x, front_y - 0.00072, center.z), (0.0023, 0.00045, 0.0023), pupil_material, 32, 20))
    return eyes, centers


def face_tree(human):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return BVHTree.FromObject(human, depsgraph)


def face_surface_y(tree, x, z):
    hit, _normal, _index, _distance = tree.ray_cast(Vector((x, -0.30, z)), Vector((0.0, 1.0, 0.0)), 0.50)
    if hit is None:
        raise RuntimeError("Could not locate face surface for brow")
    return hit.y


def build_brows(human, centers, hair_material):
    random.seed(94111)
    tree = face_tree(human)
    curve = bpy.data.curves.new("ProfessionalBrows.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00023
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    for side in (-1.0, 1.0):
        eye_z = centers[side].z
        for _index in range(300):
            u = random.random()
            x_abs = 0.012 + 0.041 * u
            x = side * x_abs
            z = eye_z + 0.022 + 0.006 * sin(pi * u) - 0.0015 * u
            z += random.uniform(-0.0006, 0.0006) + random.uniform(-0.0024, 0.0024) * sin(pi * u)
            end_x = x + side * (0.0017 + 0.0011 * u)
            end_z = z + 0.0015 * (1.0 - u) - 0.0006 * u
            try:
                y0 = face_surface_y(tree, x, z) - 0.00028
                y1 = face_surface_y(tree, end_x, end_z) - 0.00031
            except RuntimeError:
                continue
            strand = curve.splines.new("POLY")
            strand.points.add(1)
            strand.points[0].co = (x, y0, z, 1.0)
            strand.points[0].radius = 0.72
            strand.points[1].co = (end_x, y1, end_z, 1.0)
            strand.points[1].radius = 0.08
    brows = bpy.data.objects.new("ProfessionalBrows", curve)
    bpy.context.collection.objects.link(brows)
    brows.data.materials.append(hair_material)
    return brows


def scalp_threshold(x, y):
    ax = abs(x)
    center_peak = 0.0060 * max(0.0, 1.0 - ax / 0.040) ** 2
    temple_recession = 0.0065 * smoothstep(0.050, 0.092, ax)
    natural_breakup = 0.0010 * sin(x * 210.0 + 0.45)
    frontal = 1.791 - center_peak + temple_recession + natural_breakup
    if y < -0.055:
        return frontal
    if y < 0.035:
        transition = (y + 0.055) / 0.090
        side = 1.729 + 0.006 * max(0.0, min(1.0, (ax - 0.045) / 0.045))
        return frontal * (1.0 - transition) + side * transition
    backness = max(0.0, min(1.0, (y - 0.035) / 0.120))
    return 1.729 - 0.042 * backness


def scalp_surface(human):
    source = evaluated_body_mesh(human)
    body_group = human.vertex_groups["body"]
    triangles = []
    selected_faces = []
    for polygon in source.polygons:
        if not all(group_weight(source.vertices[index], body_group.index) > 0.50 for index in polygon.vertices):
            continue
        points = [source.vertices[index].co for index in polygon.vertices]
        center = sum(points, Vector()) / len(points)
        if center.z <= scalp_threshold(center.x, center.y):
            continue
        if abs(center.x) > 0.100 or center.y < -0.180 or center.y > 0.100:
            continue
        selected_faces.append(polygon)
        indices = list(polygon.vertices)
        for corner in range(1, len(indices) - 1):
            ids = (indices[0], indices[corner], indices[corner + 1])
            tri_points = tuple(source.vertices[index].co.copy() for index in ids)
            tri_normals = tuple(source.vertices[index].normal.copy() for index in ids)
            area = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0]).length * 0.5
            if area > 1e-10:
                triangles.append((tri_points, tri_normals, area))
    if not triangles:
        bpy.data.meshes.remove(source)
        raise RuntimeError("No scalp triangles found")

    # Build a dense scalp-conforming foundation and let a smooth vertex-group
    # opacity mask define the hairline in the material.  Geometry deletion at
    # the coarse body edge caused the rejected stair-step fringe.
    dense_faces = []
    for polygon in source.polygons:
        if not all(group_weight(source.vertices[index], body_group.index) > 0.50 for index in polygon.vertices):
            continue
        center = sum((source.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if center.z < 1.665 or abs(center.x) > 0.106 or center.y < -0.185 or center.y > 0.115:
            continue
        dense_faces.append(polygon)
    used = sorted({index for polygon in dense_faces for index in polygon.vertices})
    mapping = {old: new for new, old in enumerate(used)}
    foundation_mesh = bpy.data.meshes.new("HeroHairFoundation.Mesh")
    foundation_mesh.from_pydata(
        [tuple(source.vertices[index].co + source.vertices[index].normal * 0.0050) for index in used],
        [],
        [tuple(mapping[index] for index in polygon.vertices) for polygon in dense_faces],
    )
    foundation_mesh.update()
    foundation = bpy.data.objects.new("HeroHairFoundation", foundation_mesh)
    bpy.context.collection.objects.link(foundation)
    fiber_material = make_hair_material()
    fiber_material.name = "HeroHair.Fibers"
    foundation_material = fiber_material.copy()
    foundation_material.name = "HeroHair.Foundation"
    foundation_material.diffuse_color = (0.008, 0.0022, 0.0012, 1.0)
    foundation_bsdf = foundation_material.node_tree.nodes.get("Principled BSDF")
    socket(foundation_bsdf, "Base Color").default_value = foundation_material.diffuse_color
    fiber_material.diffuse_color = (0.030, 0.009, 0.0035, 1.0)
    fiber_bsdf = fiber_material.node_tree.nodes.get("Principled BSDF")
    socket(fiber_bsdf, "Base Color").default_value = fiber_material.diffuse_color
    foundation.data.materials.append(foundation_material)
    # Physically cut the hairline after three topology subdivisions.  This is
    # dense enough to look smooth but remains plain portable geometry in glTF;
    # Godot does not preserve Blender's vertex-attribute opacity masks.
    bm = bmesh.new()
    bm.from_mesh(foundation.data)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=3, use_grid_fill=True)
    remove = [
        vertex for vertex in bm.verts
        if vertex.co.z < scalp_threshold(vertex.co.x, vertex.co.y) + 0.0007
    ]
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(foundation.data)
    bm.free()
    foundation.data.update()
    for polygon in foundation.data.polygons:
        polygon.use_smooth = True
    texture = bpy.data.textures.new("HeroHairFoundationBreakup", type="CLOUDS")
    texture.noise_scale = 0.0036
    texture.noise_depth = 2
    subdivision = foundation.modifiers.new("HairFoundationSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    displace = foundation.modifiers.new("HairFoundationMicroBreakup", "DISPLACE")
    displace.texture = texture
    displace.strength = 0.00028
    displace.mid_level = 0.51
    thickness = foundation.modifiers.new("HairFoundationThickness", "SOLIDIFY")
    thickness.thickness = 0.0012
    thickness.offset = 0.0
    bpy.data.meshes.remove(source)
    return foundation, triangles, fiber_material


def random_surface_sample(triangles, cumulative, total):
    import bisect
    points, normals, _area = triangles[min(bisect.bisect_left(cumulative, random.random() * total), len(triangles) - 1)]
    r1 = random.random() ** 0.5
    r2 = random.random()
    weights = (1.0 - r1, r1 * (1.0 - r2), r1 * r2)
    root = sum((points[index] * weights[index] for index in range(3)), Vector())
    normal = sum((normals[index] * weights[index] for index in range(3)), Vector()).normalized()
    return root, normal


def build_hair_cards(triangles, hair_material):
    random.seed(94031)
    cumulative = []
    total = 0.0
    for triangle in triangles:
        total += triangle[2]
        cumulative.append(total)
    vertices = []
    faces = []
    # Fine overlapping tapered ribbons form coherent directional bundles,
    # avoiding both hair plugs and blocky roof-shingle locks.
    for _index in range(1450):
        root, normal = random_surface_sample(triangles, cumulative, total)
        boundary = root.z - scalp_threshold(root.x, root.y)
        if boundary < -0.002:
            continue
        topness = max(0.0, normal.z)
        sideness = max(0.0, min(1.0, abs(root.x) / 0.095))
        back = Vector((0.0, 1.0, 0.0))
        back -= normal * back.dot(normal)
        if back.length_squared < 1e-8:
            continue
        back.normalize()
        downward = Vector((0.0, 0.0, -1.0))
        downward -= normal * downward.dot(normal)
        if downward.length_squared > 1e-8:
            downward.normalize()
        outward = Vector((1.0 if root.x >= 0.0 else -1.0, 0.0, 0.0))
        outward -= normal * outward.dot(normal)
        if outward.length_squared > 1e-8:
            outward.normalize()
        flow = back * (0.92 + 0.15 * topness) + downward * (0.36 * sideness) + outward * (0.10 * sideness)
        flow += Vector((random.uniform(-0.08, 0.08), random.uniform(-0.04, 0.07), random.uniform(-0.025, 0.025)))
        flow -= normal * flow.dot(normal)
        if flow.length_squared < 1e-8:
            continue
        flow.normalize()
        side = normal.cross(flow).normalized()
        length = (0.012 + 0.021 * topness) * random.uniform(0.78, 1.20)
        if boundary < 0.020:
            length *= 0.45 + 0.55 * max(0.0, boundary / 0.020)
        width = (0.00042 + 0.00036 * topness) * random.uniform(0.72, 1.18)
        base = len(vertices)
        centers = (
            root + normal * 0.0019,
            root + flow * (length * 0.48) + normal * (0.0030 + length * 0.065),
            root + flow * length + normal * (0.0022 + length * 0.035),
        )
        widths = (width * 0.42, width, width * 0.025)
        for center, half_width in zip(centers, widths):
            vertices.extend((tuple(center - side * half_width), tuple(center + side * half_width)))
        faces.extend(((base, base + 1, base + 3, base + 2), (base + 2, base + 3, base + 5, base + 4)))
    mesh = bpy.data.meshes.new("HeroHairDirectionalLocks.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    cards = bpy.data.objects.new("HeroHairDirectionalLocks", mesh)
    bpy.context.collection.objects.link(cards)
    cards.data.materials.append(hair_material)
    solidify = cards.modifiers.new("HairLockThickness", "SOLIDIFY")
    solidify.thickness = 0.00022
    solidify.offset = 0.0
    bevel = cards.modifiers.new("HairLockEdgeSoftness", "BEVEL")
    bevel.width = 0.00011
    bevel.segments = 2
    cards["hair_style"] = "overlapping_directional_lock_groom"
    cards["lock_count"] = len(faces) // 2
    return cards


def build_layered_hair_shells(triangles, hair_material):
    """Build a connected, scalp-conforming crop from overlapping shell layers.

    The old groom exposed thousands of identical vertical roots. These shells
    read as one designed haircut at game distance; restrained swept ridges in
    the shell geometry provide direction without plugs, dots, or roof tiles.
    """
    vertices = []
    faces = []
    random.seed(94137)
    curve = bpy.data.curves.new("HeroHairDirectionalTexture.Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00019
    curve.bevel_resolution = 1
    curve.use_fill_caps = True

    import bisect
    cumulative = []
    total = 0.0
    for triangle in triangles:
        total += triangle[2]
        cumulative.append(total)
    added = 0
    # Thin, surface-hugging directional texture—not upright plugs. At normal
    # gameplay distance these merge into coherent fiber flow over the cap.
    for _index in range(9000):
        root, normal = random_surface_sample(triangles, cumulative, total)
        boundary = root.z - scalp_threshold(root.x, root.y)
        if boundary < 0.0015:
            continue
        topness = max(0.0, normal.z)
        sideness = max(0.0, min(1.0, abs(root.x) / 0.095))
        back = Vector((0.0, 1.0, 0.0))
        back -= normal * back.dot(normal)
        if back.length_squared < 1e-8:
            continue
        back.normalize()
        down = Vector((0.0, 0.0, -1.0))
        down -= normal * down.dot(normal)
        if down.length_squared > 1e-8:
            down.normalize()
        outward = Vector((1.0 if root.x >= 0.0 else -1.0, 0.0, 0.0))
        outward -= normal * outward.dot(normal)
        if outward.length_squared > 1e-8:
            outward.normalize()
        flow = back * (0.95 + 0.12 * topness) + down * (0.32 * sideness) + outward * (0.06 * sideness)
        flow += Vector((random.uniform(-0.10, 0.10), random.uniform(-0.03, 0.05), random.uniform(-0.02, 0.02)))
        flow -= normal * flow.dot(normal)
        if flow.length_squared < 1e-8:
            continue
        flow.normalize()
        length = (0.009 + 0.019 * topness) * random.uniform(0.72, 1.18)
        if boundary < 0.020:
            length *= 0.45 + 0.55 * boundary / 0.020
        strand = curve.splines.new("POLY")
        strand.points.add(2)
        strand_points = (
            root + normal * 0.0048,
            root + flow * (length * 0.48) + normal * 0.0054,
            root + flow * length + normal * 0.0046,
        )
        for point_index, point in enumerate(strand_points):
            strand.points[point_index].co = (*point, 1.0)
            strand.points[point_index].radius = (0.48, 0.72, 0.06)[point_index]
        added += 1
    crop = bpy.data.objects.new("HeroHairDirectionalTexture", curve)
    bpy.context.collection.objects.link(crop)
    crop.data.materials.append(hair_material)
    crop["hair_style"] = "surface_hugging_directional_crop_texture"
    crop["strand_count"] = added
    return crop


def parent_to_head(obj, rig):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = "head"
    obj.matrix_world = world


def add_rig(human, hair_objects):
    rig = HumanService.add_builtin_rig(human, "game_engine", import_weights=True)
    rig.name = "FullHeroPrototypeRig"
    # Keep review accessories in authored world space. Bone binding is done in
    # the game-integration stage after conversion to export meshes; direct bone
    # parenting of already-world-authored geometry applies a second head-rest
    # transform in Blender and was the cause of the giant oval seen in review.
    for obj in hair_objects:
        obj["intended_parent_bone"] = "head"
    human["rig_weight_source"] = "MPFB_game_engine_professional_weights"
    return rig


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 820
    scene.render.resolution_percentage = 100
    scene.world.color = (0.018, 0.024, 0.033)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.30
    data = bpy.data.cameras.new("FullHeroPrototypeCamera")
    camera = bpy.data.objects.new("FullHeroPrototypeCamera", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name, location, energy, size, color in (
        ("PrototypeKey", (-2.2, -3.4, 3.5), 620.0, 2.4, (1.0, 0.83, 0.74)),
        ("PrototypeFill", (2.6, -1.5, 2.6), 340.0, 2.8, (0.72, 0.84, 1.0)),
        ("PrototypeRim", (0.6, 3.0, 3.2), 520.0, 2.2, (0.86, 0.93, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        aim(light, (0.0, 0.0, 1.05))
        scene.collection.objects.link(light)
    return camera


def render_reviews(camera):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    views = (
        ("front", (0.0, -5.3, 1.02), (0.0, 0.0, 0.98), 76),
        ("threequarter", (3.55, -4.1, 1.10), (0.0, 0.0, 1.00), 78),
        ("side", (5.3, 0.0, 1.05), (0.0, 0.0, 1.00), 78),
        ("back", (0.0, 5.3, 1.02), (0.0, 0.0, 0.98), 76),
        ("face", (0.0, -1.03, 1.72), (0.0, -0.015, 1.70), 90),
        ("face_threequarter", (0.68, -0.80, 1.72), (0.0, -0.010, 1.70), 92),
        ("face_side", (1.05, 0.0, 1.72), (0.0, 0.0, 1.70), 92),
    )
    for name, location, target, lens in views:
        camera.location = location
        camera.data.lens = lens
        aim(camera, target)
        path = os.path.join(OUTPUT_DIR, name + ".png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"FULL_HERO_PROTOTYPE_RENDER|{name}|{path}")


def validate(human):
    bm = bmesh.new()
    bm.from_mesh(human.data)
    body_group = human.vertex_groups.get("body")
    body_indices = {
        vertex.index for vertex in human.data.vertices
        if group_weight(vertex, body_group.index) > 0.50
    }
    body_boundary = sum(
        1 for edge in bm.edges
        if all(vertex.index in body_indices for vertex in edge.verts)
        and len([face for face in edge.link_faces if all(v.index in body_indices for v in face.verts)]) == 1
    )
    bm.free()
    print(
        f"FULL_HERO_PROTOTYPE|verts={len(human.data.vertices)}|faces={len(human.data.polygons)}|"
        f"height={human.dimensions.z:.5f}|body_boundary={body_boundary}"
    )


def main():
    clear_scene()
    human = create_human()
    anatomical_sculpt(human)
    foundation, triangles, fiber_material = scalp_surface(human)
    texture = build_layered_hair_shells(triangles, fiber_material)
    eyes, eye_centers = build_eyes(human)
    brows = build_brows(human, eye_centers, fiber_material)
    rig = add_rig(human, (foundation, texture, *eyes, brows))
    camera = configure_render()
    validate(human)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    render_reviews(camera)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"FULL_HERO_PROTOTYPE_DONE|{OUTPUT_BLEND}|rig={rig.name}")


if __name__ == "__main__":
    main()
