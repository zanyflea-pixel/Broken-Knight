"""Connected-topology restart for the Broken Knight hero."""

import os
import sys
import bpy
import bmesh
from math import exp, sin, cos, sqrt, acos, atan2, pi
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from build_hero_v2 import (
    clear_scene, material, add_scaled_sphere, point_camera, create_vertical_loft,
    create_path_limb, mesh_object
)


OUT = os.path.abspath(os.path.join(HERE, "..", "hero_restart.blend"))


def bell(value, center, width):
    return exp(-((value - center) / width) ** 2)


def skin_material():
    """Lighter skin with restrained color breakup and pore-scale roughness."""
    mat = material("Skin", (.62, .39, .28, 1), .74)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.82
    bsdf.inputs["Specular IOR Level"].default_value = 0.32
    geometry = nodes.new("ShaderNodeNewGeometry")
    tone = nodes.new("ShaderNodeTexNoise")
    tone.inputs["Scale"].default_value = 9.0
    tone.inputs["Detail"].default_value = 3.0
    tone.inputs["Roughness"].default_value = 0.62
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (.36, .170, .095, 1)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (.50, .285, .170, 1)
    links.new(geometry.outputs["Position"], tone.inputs["Vector"])
    links.new(tone.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    pores = nodes.new("ShaderNodeTexNoise")
    pores.inputs["Scale"].default_value = 82.0
    pores.inputs["Detail"].default_value = 2.5
    pores.inputs["Roughness"].default_value = 0.72
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.16
    bump.inputs["Distance"].default_value = 0.00055
    links.new(geometry.outputs["Position"], pores.inputs["Vector"])
    links.new(pores.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # Localized abdominal normal detail: affects only the front torso and never
    # changes topology, so it cannot create holes or pasted-on geometry.
    separate = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], separate.inputs["Vector"])
    front_mask = nodes.new("ShaderNodeMath")
    front_mask.operation = "LESS_THAN"
    front_mask.inputs[1].default_value = -0.045
    links.new(separate.outputs["Y"], front_mask.inputs[0])
    ab_sum = None
    for center_x, center_z, x_factor, z_factor, weight in [
        (-0.038, 1.280, 900.0, 500.0, 1.0), (0.038, 1.280, 900.0, 500.0, 1.0),
        (-0.038, 1.195, 900.0, 500.0, 1.0), (0.038, 1.195, 900.0, 500.0, 1.0),
        (-0.038, 1.110, 980.0, 455.0, 1.0), (0.038, 1.110, 980.0, 455.0, 1.0),
        (-0.070, 1.400, 170.0, 330.0, 0.70), (0.070, 1.400, 170.0, 330.0, 0.70),
    ]:
        x_sub = nodes.new("ShaderNodeMath"); x_sub.operation = "SUBTRACT"
        x_sub.inputs[1].default_value = center_x
        links.new(separate.outputs["X"], x_sub.inputs[0])
        x_sq = nodes.new("ShaderNodeMath"); x_sq.operation = "MULTIPLY"
        links.new(x_sub.outputs[0], x_sq.inputs[0]); links.new(x_sub.outputs[0], x_sq.inputs[1])
        x_norm = nodes.new("ShaderNodeMath"); x_norm.operation = "MULTIPLY"
        x_norm.inputs[1].default_value = x_factor
        links.new(x_sq.outputs[0], x_norm.inputs[0])
        z_sub = nodes.new("ShaderNodeMath"); z_sub.operation = "SUBTRACT"
        z_sub.inputs[1].default_value = center_z
        links.new(separate.outputs["Z"], z_sub.inputs[0])
        z_sq = nodes.new("ShaderNodeMath"); z_sq.operation = "MULTIPLY"
        links.new(z_sub.outputs[0], z_sq.inputs[0]); links.new(z_sub.outputs[0], z_sq.inputs[1])
        z_norm = nodes.new("ShaderNodeMath"); z_norm.operation = "MULTIPLY"
        z_norm.inputs[1].default_value = z_factor
        links.new(z_sq.outputs[0], z_norm.inputs[0])
        distance = nodes.new("ShaderNodeMath"); distance.operation = "ADD"
        links.new(x_norm.outputs[0], distance.inputs[0]); links.new(z_norm.outputs[0], distance.inputs[1])
        falloff = nodes.new("ShaderNodeMapRange")
        falloff.clamp = True
        falloff.inputs["From Min"].default_value = 0.0
        falloff.inputs["From Max"].default_value = 1.0
        falloff.inputs["To Min"].default_value = 1.0
        falloff.inputs["To Max"].default_value = 0.0
        links.new(distance.outputs[0], falloff.inputs["Value"])
        masked = nodes.new("ShaderNodeMath"); masked.operation = "MULTIPLY"
        links.new(falloff.outputs["Result"], masked.inputs[0]); links.new(front_mask.outputs[0], masked.inputs[1])
        contribution = masked
        if weight != 1.0:
            weighted = nodes.new("ShaderNodeMath"); weighted.operation = "MULTIPLY"
            weighted.inputs[1].default_value = weight
            links.new(masked.outputs[0], weighted.inputs[0])
            contribution = weighted
        if ab_sum is None:
            ab_sum = contribution
        else:
            add = nodes.new("ShaderNodeMath"); add.operation = "ADD"
            links.new(ab_sum.outputs[0], add.inputs[0]); links.new(contribution.outputs[0], add.inputs[1])
            ab_sum = add
    line_x_sq = nodes.new("ShaderNodeMath"); line_x_sq.operation = "MULTIPLY"
    links.new(separate.outputs["X"], line_x_sq.inputs[0]); links.new(separate.outputs["X"], line_x_sq.inputs[1])
    line_x_norm = nodes.new("ShaderNodeMath"); line_x_norm.operation = "MULTIPLY"
    line_x_norm.inputs[1].default_value = 15625.0
    links.new(line_x_sq.outputs[0], line_x_norm.inputs[0])
    line_z_sub = nodes.new("ShaderNodeMath"); line_z_sub.operation = "SUBTRACT"
    line_z_sub.inputs[1].default_value = 1.195
    links.new(separate.outputs["Z"], line_z_sub.inputs[0])
    line_z_sq = nodes.new("ShaderNodeMath"); line_z_sq.operation = "MULTIPLY"
    links.new(line_z_sub.outputs[0], line_z_sq.inputs[0]); links.new(line_z_sub.outputs[0], line_z_sq.inputs[1])
    line_z_norm = nodes.new("ShaderNodeMath"); line_z_norm.operation = "MULTIPLY"
    line_z_norm.inputs[1].default_value = 44.5
    links.new(line_z_sq.outputs[0], line_z_norm.inputs[0])
    line_distance = nodes.new("ShaderNodeMath"); line_distance.operation = "ADD"
    links.new(line_x_norm.outputs[0], line_distance.inputs[0]); links.new(line_z_norm.outputs[0], line_distance.inputs[1])
    line_falloff = nodes.new("ShaderNodeMapRange"); line_falloff.clamp = True
    line_falloff.inputs["From Min"].default_value = 0.0
    line_falloff.inputs["From Max"].default_value = 1.0
    line_falloff.inputs["To Min"].default_value = 1.0
    line_falloff.inputs["To Max"].default_value = 0.0
    links.new(line_distance.outputs[0], line_falloff.inputs["Value"])
    line_masked = nodes.new("ShaderNodeMath"); line_masked.operation = "MULTIPLY"
    links.new(line_falloff.outputs["Result"], line_masked.inputs[0]); links.new(front_mask.outputs[0], line_masked.inputs[1])
    line_weight = nodes.new("ShaderNodeMath"); line_weight.operation = "MULTIPLY"
    line_weight.inputs[1].default_value = 0.32
    links.new(line_masked.outputs[0], line_weight.inputs[0])
    shaped_abs = nodes.new("ShaderNodeMath"); shaped_abs.operation = "SUBTRACT"
    links.new(ab_sum.outputs[0], shaped_abs.inputs[0]); links.new(line_weight.outputs[0], shaped_abs.inputs[1])
    ab_sum = shaped_abs
    ab_bump = nodes.new("ShaderNodeBump")
    # Geometry now carries the major abdominal forms; keep the shader contribution
    # low so it does not look like six airbrushed lights on the stomach.
    ab_bump.inputs["Strength"].default_value = 0.42
    ab_bump.inputs["Distance"].default_value = 0.0018
    links.new(ab_sum.outputs[0], ab_bump.inputs["Height"])
    links.new(bump.outputs["Normal"], ab_bump.inputs["Normal"])
    links.new(ab_bump.outputs["Normal"], bsdf.inputs["Normal"])

    # Integrated lip pigmentation.  This operates in the skin shader itself,
    # so the color follows the unified head surface instead of floating on it.
    lip_x_sq = nodes.new("ShaderNodeMath"); lip_x_sq.operation = "MULTIPLY"
    links.new(separate.outputs["X"], lip_x_sq.inputs[0]); links.new(separate.outputs["X"], lip_x_sq.inputs[1])
    lip_x_norm = nodes.new("ShaderNodeMath"); lip_x_norm.operation = "MULTIPLY"
    lip_x_norm.inputs[1].default_value = 1275.0
    links.new(lip_x_sq.outputs[0], lip_x_norm.inputs[0])
    lip_z_sub = nodes.new("ShaderNodeMath"); lip_z_sub.operation = "SUBTRACT"
    # Facial objects are lowered by shorten_neck_and_align_head() after union.
    lip_z_sub.inputs[1].default_value = 1.6775
    links.new(separate.outputs["Z"], lip_z_sub.inputs[0])
    lip_z_sq = nodes.new("ShaderNodeMath"); lip_z_sq.operation = "MULTIPLY"
    links.new(lip_z_sub.outputs[0], lip_z_sq.inputs[0]); links.new(lip_z_sub.outputs[0], lip_z_sq.inputs[1])
    lip_z_norm = nodes.new("ShaderNodeMath"); lip_z_norm.operation = "MULTIPLY"
    lip_z_norm.inputs[1].default_value = 11800.0
    links.new(lip_z_sq.outputs[0], lip_z_norm.inputs[0])
    lip_distance = nodes.new("ShaderNodeMath"); lip_distance.operation = "ADD"
    links.new(lip_x_norm.outputs[0], lip_distance.inputs[0]); links.new(lip_z_norm.outputs[0], lip_distance.inputs[1])
    lip_falloff = nodes.new("ShaderNodeMapRange"); lip_falloff.clamp = True
    lip_falloff.inputs["From Min"].default_value = 0.52
    lip_falloff.inputs["From Max"].default_value = 1.0
    lip_falloff.inputs["To Min"].default_value = 1.0
    lip_falloff.inputs["To Max"].default_value = 0.0
    links.new(lip_distance.outputs[0], lip_falloff.inputs["Value"])
    lip_front = nodes.new("ShaderNodeMath"); lip_front.operation = "LESS_THAN"
    lip_front.inputs[1].default_value = -0.045
    links.new(separate.outputs["Y"], lip_front.inputs[0])
    lip_mask = nodes.new("ShaderNodeMath"); lip_mask.operation = "MULTIPLY"
    links.new(lip_falloff.outputs["Result"], lip_mask.inputs[0]); links.new(lip_front.outputs[0], lip_mask.inputs[1])
    lip_strength = nodes.new("ShaderNodeMath"); lip_strength.operation = "MULTIPLY"
    lip_strength.inputs[1].default_value = 0.60
    links.new(lip_mask.outputs[0], lip_strength.inputs[0])
    lip_mix = nodes.new("ShaderNodeMixRGB")
    lip_mix.blend_type = "MIX"
    lip_mix.inputs[2].default_value = (.38, .13, .11, 1)
    links.new(ramp.outputs["Color"], lip_mix.inputs[1])
    links.new(lip_strength.outputs[0], lip_mix.inputs[0])
    # A very thin integrated mouth crease replaces the old floating curve object.
    mouth_x_sq = nodes.new("ShaderNodeMath"); mouth_x_sq.operation = "MULTIPLY"
    links.new(separate.outputs["X"], mouth_x_sq.inputs[0]); links.new(separate.outputs["X"], mouth_x_sq.inputs[1])
    mouth_x_norm = nodes.new("ShaderNodeMath"); mouth_x_norm.operation = "MULTIPLY"
    mouth_x_norm.inputs[1].default_value = 1375.0
    links.new(mouth_x_sq.outputs[0], mouth_x_norm.inputs[0])
    mouth_z_sub = nodes.new("ShaderNodeMath"); mouth_z_sub.operation = "SUBTRACT"
    mouth_z_sub.inputs[1].default_value = 1.6775
    links.new(separate.outputs["Z"], mouth_z_sub.inputs[0])
    mouth_z_sq = nodes.new("ShaderNodeMath"); mouth_z_sq.operation = "MULTIPLY"
    links.new(mouth_z_sub.outputs[0], mouth_z_sq.inputs[0]); links.new(mouth_z_sub.outputs[0], mouth_z_sq.inputs[1])
    mouth_z_norm = nodes.new("ShaderNodeMath"); mouth_z_norm.operation = "MULTIPLY"
    mouth_z_norm.inputs[1].default_value = 220000.0
    links.new(mouth_z_sq.outputs[0], mouth_z_norm.inputs[0])
    mouth_distance = nodes.new("ShaderNodeMath"); mouth_distance.operation = "ADD"
    links.new(mouth_x_norm.outputs[0], mouth_distance.inputs[0]); links.new(mouth_z_norm.outputs[0], mouth_distance.inputs[1])
    mouth_falloff = nodes.new("ShaderNodeMapRange"); mouth_falloff.clamp = True
    mouth_falloff.inputs["From Min"].default_value = 0.0
    mouth_falloff.inputs["From Max"].default_value = 1.0
    mouth_falloff.inputs["To Min"].default_value = 1.0
    mouth_falloff.inputs["To Max"].default_value = 0.0
    links.new(mouth_distance.outputs[0], mouth_falloff.inputs["Value"])
    mouth_mask = nodes.new("ShaderNodeMath"); mouth_mask.operation = "MULTIPLY"
    links.new(mouth_falloff.outputs["Result"], mouth_mask.inputs[0]); links.new(lip_front.outputs[0], mouth_mask.inputs[1])
    mouth_strength = nodes.new("ShaderNodeMath"); mouth_strength.operation = "MULTIPLY"
    mouth_strength.inputs[1].default_value = 0.96
    links.new(mouth_mask.outputs[0], mouth_strength.inputs[0])
    mouth_mix = nodes.new("ShaderNodeMixRGB")
    mouth_mix.inputs[2].default_value = (.035, .012, .009, 1)
    links.new(lip_mix.outputs["Color"], mouth_mix.inputs[1])
    links.new(mouth_strength.outputs[0], mouth_mix.inputs[0])
    def ellipse_mask(center_x, center_z, x_factor, z_factor, inner=0.70):
        x_sub = nodes.new("ShaderNodeMath"); x_sub.operation = "SUBTRACT"
        x_sub.inputs[1].default_value = center_x
        links.new(separate.outputs["X"], x_sub.inputs[0])
        x_sq = nodes.new("ShaderNodeMath"); x_sq.operation = "MULTIPLY"
        links.new(x_sub.outputs[0], x_sq.inputs[0]); links.new(x_sub.outputs[0], x_sq.inputs[1])
        x_norm = nodes.new("ShaderNodeMath"); x_norm.operation = "MULTIPLY"
        x_norm.inputs[1].default_value = x_factor
        links.new(x_sq.outputs[0], x_norm.inputs[0])
        z_sub = nodes.new("ShaderNodeMath"); z_sub.operation = "SUBTRACT"
        z_sub.inputs[1].default_value = center_z
        links.new(separate.outputs["Z"], z_sub.inputs[0])
        z_sq = nodes.new("ShaderNodeMath"); z_sq.operation = "MULTIPLY"
        links.new(z_sub.outputs[0], z_sq.inputs[0]); links.new(z_sub.outputs[0], z_sq.inputs[1])
        z_norm = nodes.new("ShaderNodeMath"); z_norm.operation = "MULTIPLY"
        z_norm.inputs[1].default_value = z_factor
        links.new(z_sq.outputs[0], z_norm.inputs[0])
        distance = nodes.new("ShaderNodeMath"); distance.operation = "ADD"
        links.new(x_norm.outputs[0], distance.inputs[0]); links.new(z_norm.outputs[0], distance.inputs[1])
        falloff = nodes.new("ShaderNodeMapRange"); falloff.clamp = True
        falloff.inputs["From Min"].default_value = inner
        falloff.inputs["From Max"].default_value = 1.0
        falloff.inputs["To Min"].default_value = 1.0
        falloff.inputs["To Max"].default_value = 0.0
        links.new(distance.outputs[0], falloff.inputs["Value"])
        masked = nodes.new("ShaderNodeMath"); masked.operation = "MULTIPLY"
        links.new(falloff.outputs["Result"], masked.inputs[0]); links.new(lip_front.outputs[0], masked.inputs[1])
        return masked

    def sum_masks(masks):
        result = masks[0]
        for mask in masks[1:]:
            add = nodes.new("ShaderNodeMath"); add.operation = "ADD"; add.use_clamp = True
            links.new(result.outputs[0], add.inputs[0]); links.new(mask.outputs[0], add.inputs[1])
            result = add
        return result

    def color_layer(base_output, mask, color, strength=1.0):
        factor = mask
        if strength != 1.0:
            weighted = nodes.new("ShaderNodeMath"); weighted.operation = "MULTIPLY"
            weighted.inputs[1].default_value = strength
            links.new(mask.outputs[0], weighted.inputs[0])
            factor = weighted
        mix = nodes.new("ShaderNodeMixRGB")
        mix.inputs[2].default_value = color
        links.new(base_output, mix.inputs[1]); links.new(factor.outputs[0], mix.inputs[0])
        return mix.outputs["Color"]

    # All visible eye and brow detail is now painted onto the curved unified head.
    eye_masks = [ellipse_mask(-0.037, 1.767, 4200.0, 40000.0),
                 ellipse_mask(0.037, 1.767, 4200.0, 40000.0)]
    face_color = color_layer(mouth_mix.outputs["Color"], sum_masks(eye_masks),
                             (.50, .485, .445, 1), 0.96)
    iris_masks = [ellipse_mask(-0.037, 1.767, 57000.0, 57000.0),
                  ellipse_mask(0.037, 1.767, 57000.0, 57000.0)]
    face_color = color_layer(face_color, sum_masks(iris_masks), (.115, .047, .018, 1))
    pupil_masks = [ellipse_mask(-0.037, 1.767, 390000.0, 390000.0),
                   ellipse_mask(0.037, 1.767, 390000.0, 390000.0)]
    face_color = color_layer(face_color, sum_masks(pupil_masks), (.012, .008, .006, 1))
    lid_masks = [ellipse_mask(-0.037, 1.7712, 7560.0, 280000.0),
                 ellipse_mask(0.037, 1.7712, 7560.0, 280000.0)]
    face_color = color_layer(face_color, sum_masks(lid_masks), (.055, .025, .018, 1), 0.72)
    brow_masks = [ellipse_mask(-0.038, 1.7845, 2500.0, 180000.0),
                  ellipse_mask(0.038, 1.7845, 2500.0, 180000.0)]
    face_color = color_layer(face_color, sum_masks(brow_masks), (.045, .020, .014, 1), 0.88)
    highlight_masks = [ellipse_mask(-0.0358, 1.7685, 1300000.0, 1300000.0),
                       ellipse_mask(0.0358, 1.7685, 1300000.0, 1300000.0)]
    face_color = color_layer(face_color, sum_masks(highlight_masks), (.72, .70, .64, 1), 0.90)
    # Soft anatomical color variation over the real geometric face. These use
    # fully feathered masks so they read as circulation, not painted patches.
    tone_color = mouth_mix.outputs["Color"]
    cheek_masks = [ellipse_mask(-0.054, 1.724, 820.0, 900.0, 0.0),
                   ellipse_mask(0.054, 1.724, 820.0, 900.0, 0.0)]
    tone_color = color_layer(tone_color, sum_masks(cheek_masks),
                             (.58, .255, .185, 1), 0.23)
    nose_warmth = ellipse_mask(0.0, 1.716, 1750.0, 520.0, 0.0)
    tone_color = color_layer(tone_color, nose_warmth,
                             (.60, .245, .175, 1), 0.21)
    under_eye_masks = [ellipse_mask(-0.037, 1.752, 1650.0, 7600.0, 0.0),
                       ellipse_mask(0.037, 1.752, 1650.0, 7600.0, 0.0)]
    tone_color = color_layer(tone_color, sum_masks(under_eye_masks),
                             (.34, .225, .185, 1), 0.10)
    beard_zone = ellipse_mask(0.0, 1.642, 180.0, 360.0, 0.0)
    tone_color = color_layer(tone_color, beard_zone,
                             (.25, .175, .145, 1), 0.105)
    # The visible eye pass below uses deeply embedded thin geometry with real irises.
    links.new(tone_color, bsdf.inputs["Base Color"])
    return mat


def connected_body(mat):
    # A single graph: spine branches into shoulders and hips, then continues to extremities.
    verts = [
        (0, 0.010, 0.98), (0, 0.000, 1.15), (0, -0.005, 1.36), (0, 0.000, 1.52), (0, 0.000, 1.72),
        (-0.225, 0.000, 1.48), (-0.278, 0.000, 1.40), (-0.318, 0.006, 1.27), (-0.334, 0.012, 1.14), (-0.342, 0.015, 1.00), (-0.345, -0.002, 0.90),
        (0.225, 0.000, 1.48), (0.278, 0.000, 1.40), (0.318, 0.006, 1.27), (0.334, 0.012, 1.14), (0.342, 0.015, 1.00), (0.345, -0.002, 0.90),
        (-0.115, 0.005, 0.95), (-0.125, 0.000, 0.78), (-0.130, 0.000, 0.58), (-0.130, 0.012, 0.43), (-0.130, 0.020, 0.25), (-0.130, 0.020, 0.12), (-0.132, -0.015, 0.085), (-0.132, -0.060, 0.065),
        (0.115, 0.005, 0.95), (0.125, 0.000, 0.78), (0.130, 0.000, 0.58), (0.130, 0.012, 0.43), (0.130, 0.020, 0.25), (0.130, 0.020, 0.12), (0.132, -0.015, 0.085), (0.132, -0.060, 0.065),
        (0, -0.002, 1.605),
        (-0.130, 0.035, 0.075), (0.130, 0.035, 0.075),
    ]
    edges = [(0,1),(1,2),(2,3),(3,33),(33,4),
             (3,5),(5,6),(6,7),(7,8),(8,9),(9,10),
             (3,11),(11,12),(12,13),(13,14),(14,15),(15,16),
             (0,17),(17,18),(18,19),(19,20),(20,21),(21,22),(22,23),(23,24),
             (0,25),(25,26),(26,27),(27,28),(28,29),(29,30),(30,31),(31,32),
             (22,34),(30,35)]
    radii = [
        (.190,.145), (.180,.132), (.225,.165), (.170,.132), (.073,.066),
        (.100,.105), (.084,.091), (.069,.075), (.055,.060), (.061,.066), (.035,.038),
        (.100,.105), (.084,.091), (.069,.075), (.055,.060), (.061,.066), (.035,.038),
        (.122,.130), (.114,.122), (.073,.079), (.093,.103), (.070,.079), (.047,.053), (.036,.036), (.030,.025),
        (.122,.130), (.114,.122), (.073,.079), (.093,.103), (.070,.079), (.047,.053), (.036,.036), (.030,.025),
        (.073,.064),
        (.022,.022), (.022,.022),
    ]
    # Keep the graph continuous through both wrists.  A separate forearm shell
    # produced a cuff at its capped upper end; the hand now begins only inside
    # the wrist overlap below.
    removed = set()
    remap = {}
    filtered_verts = []
    filtered_radii = []
    for old_index, (vertex, radius) in enumerate(zip(verts, radii)):
        if old_index in removed:
            continue
        remap[old_index] = len(filtered_verts)
        filtered_verts.append(vertex)
        filtered_radii.append(radius)
    edges = [(remap[a], remap[b]) for a, b in edges
             if a in remap and b in remap]
    verts = filtered_verts
    radii = filtered_radii
    mesh = bpy.data.meshes.new("ConnectedBody.Mesh")
    mesh.from_pydata(verts, edges, [])
    mesh.update()
    obj = bpy.data.objects.new("ConnectedBody", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    skin = obj.modifiers.new("ContinuousHumanSurface", "SKIN")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.view_layer.update()
    skin_layer = obj.data.skin_vertices[0].data
    for datum, radius in zip(skin_layer, radii):
        datum.radius = radius
    skin_layer[0].use_root = True
    bpy.ops.object.modifier_apply(modifier=skin.name)
    # Establish a human torso rhythm before adding surface detail: expanded ribcage,
    # a visible but restrained waist, and a supporting pelvic flare.  Limit this
    # to the central mass so the connected shoulder and arm topology is preserved.
    for vert in obj.data.vertices:
        x, y, z = vert.co
        if 0.90 < z < 1.57 and abs(x) < 0.275:
            ribcage = bell(z, 1.365, 0.165)
            waist = bell(z, 1.115, 0.105)
            pelvis = bell(z, 0.965, 0.085)
            side_weight = min(1.0, abs(x) / 0.115)
            scale = 1.0 + side_weight * (0.065 * ribcage - 0.125 * waist + 0.085 * pelvis)
            vert.co.x *= scale
    # Add front/back anatomical depth while retaining the connected topology.
    for vert in obj.data.vertices:
        x, y, z = vert.co
        central = max(0.0, min(1.0, (0.27 - abs(x)) / 0.10))
        if central > 0.0 and z > 0.90:
            if y < 0.0:
                vert.co.y -= central * (
                    0.027 * bell(z, 1.40, 0.17) +
                    0.017 * bell(z, 1.12, 0.13)
                )
            else:
                vert.co.y += central * (
                    0.021 * bell(z, 1.42, 0.18) +
                    0.034 * bell(z, 0.96, 0.11)
                )
        if abs(x) < 0.23 and z < 0.92:
            if y > 0.0:
                vert.co.y += 0.014 * bell(z, 0.34, 0.13)
            else:
                vert.co.y -= 0.008 * bell(z, 0.56, 0.08)
        if z < 0.16 and y < 0.06:
            foot_center = 0.125 if x >= 0.0 else -0.125
            vert.co.x = foot_center + (x - foot_center) * 1.18
            if vert.co.z < 0.030:
                vert.co.z = 0.030
    # One applied subdivision provides enough vertices for broad anatomical planes.
    density = obj.modifiers.new("BodySurfaceDensity", "SUBSURF")
    density.levels = 2
    density.render_levels = 2
    bpy.ops.object.modifier_apply(modifier=density.name)
    for vert in obj.data.vertices:
        x, y, z = vert.co
        if y < 0.0 and abs(x) < 0.245 and 0.98 < z < 1.56:
            pectoral = max(bell(x, -0.100, 0.108), bell(x, 0.100, 0.108)) * bell(z, 1.425, 0.115)
            sternum = bell(x, 0.0, 0.018) * bell(z, 1.385, 0.165)
            rectus = bell(x, 0.0, 0.060) * bell(z, 1.175, 0.190)
            linea = bell(x, 0.0, 0.010) * bell(z, 1.185, 0.180)
            navel = bell(x, 0.0, 0.014) * bell(z, 1.090, 0.016)
            clavicle = max(bell(x, -0.085, 0.085), bell(x, 0.085, 0.085)) * bell(z, 1.490, 0.026)
            ab_pairs = max(bell(x, -0.040, 0.028), bell(x, 0.040, 0.028))
            ab_rows = (bell(z, 1.285, 0.040) + bell(z, 1.195, 0.040) +
                       0.82 * bell(z, 1.105, 0.044))
            six_pack = ab_pairs * ab_rows
            transverse = (bell(z, 1.242, 0.012) + bell(z, 1.150, 0.012)) * bell(x, 0.0, 0.090)
            semilunaris = max(bell(x, -0.082, 0.014), bell(x, 0.082, 0.014)) * bell(z, 1.190, 0.175)
            vert.co.y -= 0.022 * pectoral + 0.007 * rectus + 0.007 * six_pack
            vert.co.y += 0.012 * sternum + 0.012 * linea + 0.008 * navel + 0.008 * clavicle
            vert.co.y += 0.009 * transverse + 0.008 * semilunaris
        if y > 0.0 and abs(x) < 0.235 and 1.22 < z < 1.53:
            scapula = max(bell(x, -0.095, 0.065), bell(x, 0.095, 0.065)) * bell(z, 1.385, 0.120)
            spine_groove = bell(x, 0.0, 0.018) * bell(z, 1.350, 0.190)
            vert.co.y += 0.014 * scapula
            vert.co.y -= 0.005 * spine_groove
        if y > 0.0 and abs(x) < 0.220 and 0.78 < z < 1.04:
            glute = max(bell(x, -0.075, 0.062), bell(x, 0.075, 0.062)) * bell(z, 0.905, 0.075)
            cleft = bell(x, 0.0, 0.018) * bell(z, 0.925, 0.100)
            fold = bell(z, 0.825, 0.018) * max(bell(x, -0.075, 0.070), bell(x, 0.075, 0.070))
            vert.co.y += 0.044 * glute
            vert.co.y -= 0.010 * cleft + 0.006 * fold
        if abs(x) > 0.245 and 1.02 < z < 1.46:
            arm_mass = bell(abs(x), 0.315, 0.080)
            if y < 0.0:
                vert.co.y -= 0.010 * arm_mass * bell(z, 1.285, 0.100)
            else:
                vert.co.y += 0.012 * arm_mass * bell(z, 1.315, 0.115)
        if 0.075 < abs(x) < 0.225 and 0.52 < z < 0.94:
            if y < 0.0:
                vert.co.y -= 0.011 * bell(z, 0.755, 0.145)
            else:
                vert.co.y += 0.010 * bell(z, 0.720, 0.150)
        if 0.075 < abs(x) < 0.215 and 0.18 < z < 0.53 and y > 0.0:
            vert.co.y += 0.014 * bell(z, 0.385, 0.105)
        if z < 0.155 and y < 0.060:
            side = 1.0 if x >= 0.0 else -1.0
            foot_center = 0.132 * side
            forefoot = bell(y, -0.185, 0.085)
            vert.co.x = foot_center + (x - foot_center) * (1.0 + 0.18 * forefoot)
            toe_taper = max(0.0, min(1.0, (-y - 0.135) / 0.120))
            vert.co.z = 0.030 + (z - 0.030) * (1.0 - 0.24 * toe_taper)
            inner = max(0.0, 1.0 - abs(x - foot_center + side * 0.030) / 0.055)
            arch = bell(y, -0.045, 0.070) * inner
            if vert.co.z < 0.075:
                vert.co.z += 0.010 * arch
    for poly in obj.data.polygons:
        poly.use_smooth = True
    sub = obj.modifiers.new("BodySubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    return obj


def anatomical_bridges(mat):
    """Overlapping anatomical masses that will be unioned into the body surface."""
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        # Pectoral/lat web closes the unnaturally deep Skin-graph armpit.
        add_scaled_sphere(
            f"AxillaryFill.{suffix}",
            (0.205 * side, 0.008, 1.365),
            (0.060, 0.077, 0.102), mat, 28, 18
        )
        # Broad pectoral plane, mostly buried so it reads as anatomy after union.
        add_scaled_sphere(
            f"PectoralMass.{suffix}",
            (0.092 * side, -0.145, 1.455),
            (0.108, 0.016, 0.050), mat, 34, 20
        )
        # Continuous rectus column; existing mesh grooves provide segmentation.
        add_scaled_sphere(
            f"RectusMass.{suffix}",
            (0.040 * side, -0.132, 1.190),
            (0.043, 0.012, 0.145), mat, 30, 22
        )


def joint_blends(mat):
    """Buried transition masses remove hard union rings without hiding anatomy."""
    add_scaled_sphere("NeckBlend", (0.0, -0.001, 1.670),
                      (0.071, 0.063, 0.060), mat, 32, 20)
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        add_scaled_sphere(f"AxillaryBlend.{suffix}",
                          (0.218 * side, 0.008, 1.392),
                          (0.064, 0.073, 0.090), mat, 30, 20)
        add_scaled_sphere(f"WristBlend.{suffix}",
                          (0.345 * side, 0.000, 0.945),
                          (0.041, 0.044, 0.052), mat, 28, 18)
        add_scaled_sphere(f"AnkleBlend.{suffix}",
                          (0.130 * side, 0.018, 0.115),
                          (0.047, 0.044, 0.058), mat, 28, 18)


def apply_all_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def unify_skin(body, skin_mat):
    """Union every overlapping skin component into the connected body mesh."""
    apply_all_modifiers(body)
    priority = {
        "AxillaryBlend": 0, "WristBlend": 1, "AnkleBlend": 2,
        "NeckBlend": 3, "Head": 4, "Ear": 5, "Hand": 6,
        "Finger": 7, "Thumb": 8, "Foot": 9, "Toe": 10,
    }
    attachments = []
    for obj in list(bpy.context.scene.objects):
        if obj == body or obj.type != "MESH" or not obj.data.materials:
            continue
        if obj.data.materials[0] != skin_mat:
            continue
        key = next((rank for prefix, rank in priority.items() if obj.name.startswith(prefix)), 20)
        attachments.append((key, obj.name, obj))
    for _, _, operand in sorted(attachments, key=lambda item: (item[0], item[1])):
        if operand.name not in bpy.context.scene.objects:
            continue
        apply_all_modifiers(operand)
        bpy.context.view_layer.objects.active = body
        body.select_set(True)
        boolean = body.modifiers.new(f"Union.{operand.name}", "BOOLEAN")
        boolean.operation = "UNION"
        boolean.solver = "EXACT"
        boolean.object = operand
        bpy.ops.object.modifier_apply(modifier=boolean.name)
        if operand.name in bpy.data.objects:
            bpy.data.objects.remove(operand, do_unlink=True)
        body.select_set(False)
    for poly in body.data.polygons:
        poly.use_smooth = True
    smooth = body.modifiers.new("UnifiedSkinSmoothing", "SUBSURF")
    smooth.levels = 2
    smooth.render_levels = 2
    return body


def watertight_skin_remesh(body, voxel_size=0.0045):
    """Replace all Boolean junction topology with one continuous voxel surface."""
    apply_all_modifiers(body)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    body.data.remesh_voxel_size = voxel_size
    body.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    body.select_set(False)
    return body


def sculpt_abs(body):
    """Create visible abdominal and pectoral structure in the unified body vertices."""
    for vert in body.data.vertices:
        x, y, z = vert.co
        if y >= -0.050:
            continue
        if abs(x) < 0.125 and 1.035 < z < 1.350:
            paired = max(bell(x, -0.040, 0.024), bell(x, 0.040, 0.024))
            rows = (bell(z, 1.285, 0.033) +
                    bell(z, 1.198, 0.033) +
                    0.86 * bell(z, 1.112, 0.036))
            lobes = paired * rows
            linea_alba = bell(x, 0.0, 0.009) * bell(z, 1.198, 0.155)
            horizontal = (bell(z, 1.244, 0.009) + bell(z, 1.156, 0.009)) * bell(x, 0.0, 0.090)
            outer_edge = max(bell(x, -0.086, 0.012), bell(x, 0.086, 0.012)) * bell(z, 1.195, 0.155)
            vert.co.y -= 0.020 * lobes
            vert.co.y += 0.021 * linea_alba + 0.009 * horizontal + 0.008 * outer_edge
        if abs(x) < 0.230 and 1.325 < z < 1.535:
            pecs = max(bell(x, -0.105, 0.105), bell(x, 0.105, 0.105)) * bell(z, 1.462, 0.066)
            sternum = bell(x, 0.0, 0.012) * bell(z, 1.448, 0.090)
            lower_border = bell(z, 1.405, 0.011) * bell(x, 0.0, 0.180)
            clavicle_break = bell(z, 1.500, 0.014) * bell(x, 0.0, 0.165)
            vert.co.y -= 0.034 * pecs
            vert.co.y += 0.014 * sternum + 0.007 * lower_border + 0.011 * clavicle_break
    return body


def nipples(areola_mat, nipple_mat, body):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        x = 0.100 * side
        nipple_z = 1.445
        hit = tree.ray_cast(Vector((x, -0.42, nipple_z)), Vector((0.0, 1.0, 0.0)), 0.8)
        surface_y = hit[0].y if hit[0] is not None else -0.157
        segments = 32
        areola_verts = [(x, surface_y - 0.00080, nipple_z)]
        for step in range(segments):
            angle = 2.0 * pi * step / segments
            areola_verts.append((x + 0.0105 * cos(angle),
                                 surface_y - 0.00080,
                                 nipple_z + 0.0105 * sin(angle)))
        areola_faces = [(0, step + 1, ((step + 1) % segments) + 1)
                        for step in range(segments)]
        mesh_object(f"Areola.{suffix}", areola_verts, areola_faces,
                    areola_mat, subdivision=0)
        add_scaled_sphere(
            f"Nipple.{suffix}", (x, surface_y - 0.0014, nipple_z),
            (0.0028, 0.0007, 0.0028), nipple_mat, 22, 14
        )


def sculpt_muscle_tone(body):
    """Broad connected definition for limbs, back, obliques, and glutes."""
    for vert in body.data.vertices:
        x, y, z = vert.co
        ax = abs(x)
        side = -1.0 if x < 0.0 else 1.0
        if 0.205 < ax < 0.410 and 0.96 < z < 1.50:
            deltoid = bell(z, 1.405, 0.070) * bell(ax, 0.245, 0.075)
            vert.co.x += side * 0.027 * deltoid
            if y < 0.0:
                biceps = bell(z, 1.285, 0.075) * bell(ax, 0.305, 0.090)
                forearm = bell(z, 1.075, 0.070) * bell(ax, 0.340, 0.075)
                elbow_break = bell(z, 1.145, 0.026) * bell(ax, 0.337, 0.060)
                vert.co.y -= 0.028 * biceps + 0.017 * forearm
                # No transverse procedural elbow band; it read as an assembly seam.
            else:
                triceps = bell(z, 1.300, 0.085) * bell(ax, 0.300, 0.090)
                extensor = bell(z, 1.060, 0.075) * bell(ax, 0.340, 0.075)
                vert.co.y += 0.029 * triceps + 0.016 * extensor
        if 0.070 < ax < 0.225 and 0.52 < z < 0.97:
            thigh = bell(z, 0.765, 0.145)
            vert.co.x += side * 0.020 * thigh
            if y < 0.0:
                vastus = max(bell(x, -0.145, 0.055), bell(x, 0.145, 0.055))
                rectus = bell(ax, 0.125, 0.032) * bell(z, 0.770, 0.150)
                outer_quad = bell(ax, 0.178, 0.035) * bell(z, 0.725, 0.145)
                vert.co.y -= 0.034 * thigh * vastus + 0.016 * rectus + 0.012 * outer_quad
            else:
                hamstring = bell(z, 0.725, 0.135)
                ham_heads = max(bell(ax, 0.105, 0.030), bell(ax, 0.160, 0.032))
                ham_groove = bell(ax, 0.132, 0.015)
                vert.co.y += 0.028 * hamstring + 0.013 * hamstring * ham_heads
                vert.co.y -= 0.0050 * hamstring * ham_groove
        if 0.070 < ax < 0.210 and 0.17 < z < 0.54:
            calf = bell(z, 0.385, 0.095)
            vert.co.x += side * 0.012 * calf
            if y > 0.0:
                calf_height = bell(z, 0.405, 0.105)
                calf_heads = max(bell(ax, 0.105, 0.027), bell(ax, 0.157, 0.027))
                vert.co.y += 0.028 * calf_height + 0.011 * calf_height * calf_heads
                vert.co.y -= 0.0038 * calf_height * bell(ax, 0.132, 0.012)
            else:
                # Keep the tibial face comparatively straight; the old outward
                # knot on the lower front leg read as an anatomical dent/bulge.
                vert.co.y += 0.004 * bell(z, 0.335, 0.105)
        if y < 0.0 and 0.085 < ax < 0.175 and 1.04 < z < 1.32:
            vert.co.y -= 0.009 * bell(ax, 0.120, 0.030) * bell(z, 1.185, 0.150)
        if y < 0.0 and 0.105 < ax < 0.215 and 1.22 < z < 1.40:
            serratus_rows = (bell(z, 1.335, 0.025) +
                             0.85 * bell(z, 1.285, 0.025) +
                             0.70 * bell(z, 1.238, 0.026))
            vert.co.y -= 0.006 * bell(ax, 0.155, 0.045) * serratus_rows
        if y < 0.0 and ax < 0.205 and 1.455 < z < 1.545:
            upper_chest = max(bell(x, -0.105, 0.070), bell(x, 0.105, 0.070))
            vert.co.y -= 0.007 * upper_chest * bell(z, 1.492, 0.038)
        if y > 0.0 and ax < 0.220 and 1.12 < z < 1.52:
            scapula = max(bell(x, -0.095, 0.055), bell(x, 0.095, 0.055)) * bell(z, 1.375, 0.110)
            spine = bell(x, 0.0, 0.016) * bell(z, 1.340, 0.180)
            lat = max(bell(x, -0.145, 0.055), bell(x, 0.145, 0.055)) * bell(z, 1.275, 0.145)
            erectors = max(bell(x, -0.038, 0.022), bell(x, 0.038, 0.022)) * bell(z, 1.285, 0.175)
            vert.co.y += 0.030 * scapula + 0.029 * lat + 0.015 * erectors
            vert.co.y -= 0.014 * spine
        if y > 0.0 and ax < 0.205 and 0.78 < z < 1.02:
            glute = max(bell(x, -0.075, 0.060), bell(x, 0.075, 0.060)) * bell(z, 0.900, 0.070)
            vert.co.y += 0.018 * glute
    return body


def sculpt_anatomical_landmarks(body):
    """Break up the doll-smooth surface with restrained skeletal landmarks."""
    for vert in body.data.vertices:
        x, y, z = vert.co
        ax = abs(x)
        if y < -0.035 and z > 1.0:
            clavicles = max(bell(x, -0.095, 0.070), bell(x, 0.095, 0.070)) * bell(z, 1.495, 0.022)
            deltopectoral = max(bell(x, -0.190, 0.018), bell(x, 0.190, 0.018)) * bell(z, 1.425, 0.085)
            navel = bell(x, 0.0, 0.013) * bell(z, 1.085, 0.014)
            vert.co.y -= 0.010 * clavicles
            vert.co.y += 0.011 * deltopectoral + 0.009 * navel
        if y < 0.0 and 0.075 < ax < 0.210 and 0.46 < z < 0.64:
            patella = bell(z, 0.555, 0.038) * max(bell(x, -0.130, 0.050), bell(x, 0.130, 0.050))
            knee_break = (bell(z, 0.625, 0.020) + bell(z, 0.480, 0.020)) * patella
            vert.co.y -= 0.009 * patella
            vert.co.y += 0.004 * knee_break
        if y > 0.0 and 0.085 < ax < 0.180 and 0.12 < z < 0.34:
            achilles = max(bell(x, -0.130, 0.022), bell(x, 0.130, 0.022)) * bell(z, 0.225, 0.095)
            vert.co.y += 0.005 * achilles
    return body


def relax_joint_seams(body):
    """Locally relax Boolean transition rings while preserving the whole figure."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for iteration in range(11):
        wrists = [v for v in bm.verts
                  if abs(v.co.x) > 0.285 and 0.855 < v.co.z < 1.100]
        finger_roots = [v for v in bm.verts
                        if abs(v.co.x) > 0.285 and 0.790 < v.co.z < 0.860
                        and -0.035 < v.co.y < 0.015]
        ankles = [v for v in bm.verts
                  if 0.070 < abs(v.co.x) < 0.205 and -0.075 < v.co.y < 0.095
                  and 0.045 < v.co.z < 0.190]
        toe_bases = [v for v in bm.verts
                     if v.co.y < -0.115 and v.co.y > -0.205 and v.co.z < 0.095]
        foot_surface = [v for v in bm.verts
                        if 0.070 < abs(v.co.x) < 0.220
                        and -0.130 < v.co.y < 0.100 and v.co.z < 0.160]
        neck_join = [v for v in bm.verts
                     if abs(v.co.x) < 0.115 and 1.625 < v.co.z < 1.745]
        bmesh.ops.smooth_vert(bm, verts=wrists, factor=0.42,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=finger_roots, factor=0.26,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=ankles, factor=0.36,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=toe_bases, factor=0.14,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=foot_surface, factor=0.22,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=neck_join, factor=0.34,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # Additional relaxation is intentionally limited to the forefoot/toe roots.
    for _ in range(1):
        bmesh.ops.smooth_vert(bm, verts=toe_bases, factor=0.08,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # Remove the old isolated calf dents while retaining the broad gastrocnemius mass.
    lower_legs = [v for v in bm.verts
                  if 0.070 < abs(v.co.x) < 0.205 and 0.155 < v.co.z < 0.535]
    for _ in range(4):
        bmesh.ops.smooth_vert(bm, verts=lower_legs, factor=0.16,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # Relax the complete arm lightly. The old heavy forearm-only selection
    # stopped at z=1.36 and manufactured a visible horizontal ring there.
    arm_surface = [v for v in bm.verts
                   if abs(v.co.x) > 0.245 and 0.900 < v.co.z < 1.470]
    for _ in range(4):
        bmesh.ops.smooth_vert(bm, verts=arm_surface, factor=0.14,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    shoulder_joins = [v for v in bm.verts
                      if 0.155 < abs(v.co.x) < 0.305 and 1.375 < v.co.z < 1.555]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=shoulder_joins, factor=0.22,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return body


def shorten_neck_and_align_head(body, amount=0.034):
    """Compress the neck and move every authored facial part with the head."""
    for vert in body.data.vertices:
        z = vert.co.z
        if z <= 1.555:
            continue
        weight = max(0.0, min(1.0, (z - 1.555) / 0.095))
        weight = weight * weight * (3.0 - 2.0 * weight)
        vert.co.z -= amount * weight
        # Fill the pinched head/neck union without thickening the shoulders.
        neck_fill = bell(z, 1.650, 0.055)
        vert.co.x *= 1.0 + 0.075 * neck_fill
        vert.co.y *= 1.0 + 0.045 * neck_fill
        if vert.co.y < 0.0:
            front_center = max(0.0, 1.0 - abs(vert.co.x) / 0.090)
            vert.co.y -= 0.0080 * neck_fill * front_center
    bm = bmesh.new()
    bm.from_mesh(body.data)
    neck_vertices = [vert for vert in bm.verts
                     if abs(vert.co.x) < 0.125 and 1.555 < vert.co.z < 1.720]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=neck_vertices, factor=0.28,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()

    for obj in list(bpy.context.scene.objects):
        if obj == body or obj.name.startswith(("Areola", "Nipple")):
            continue
        if obj.type not in {"MESH", "CURVE"}:
            continue
        if obj.type == "CURVE":
            points = []
            for spline in obj.data.splines:
                points.extend(point.co for point in spline.bezier_points)
                points.extend(point.co.xyz for point in spline.points)
            if points and sum(point.z for point in points) / len(points) > 1.62:
                for spline in obj.data.splines:
                    for point in spline.bezier_points:
                        point.co.z -= amount
                    for point in spline.points:
                        point.co.z -= amount
        elif obj.matrix_world.translation.z > 1.62:
            obj.location.z -= amount
    return body


def finalize_mouth_geometry(body, lip_mat, dark_mat):
    """Sculpt a visible mouth into the unified head at locally dense resolution."""
    # Add topology before sculpting the mouth.  Subdividing after the coarse
    # deformation merely interpolated a few large body faces, leaving the lips
    # as obvious horizontal/rectangular steps in close views.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    mouth_edges = [edge for edge in bm.edges
                   if any(vertex.co.y < -0.050 and abs(vertex.co.x) < 0.052
                          and 1.653 < vertex.co.z < 1.698
                          for vertex in edge.verts)]
    if mouth_edges:
        bmesh.ops.subdivide_edges(bm, edges=mouth_edges, cuts=14,
                                  use_grid_fill=True)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()

    for vert in body.data.vertices:
        x, y, z = vert.co
        if y >= -0.050 or abs(x) > 0.050 or not 1.655 < z < 1.695:
            continue
        crease = bell(x, 0.0, 0.031) * bell(z, 1.6775, 0.0032)
        upper = max(bell(x, -0.010, 0.015), bell(x, 0.010, 0.015)) * bell(z, 1.6822, 0.0045)
        lower = bell(x, 0.0, 0.028) * bell(z, 1.6718, 0.0052)
        corners = max(bell(x, -0.030, 0.006), bell(x, 0.030, 0.006)) * bell(z, 1.6775, 0.0050)
        philtrum = bell(x, 0.0, 0.0065) * bell(z, 1.6910, 0.010)
        # Positive Y moves the front surface inward; negative Y builds lip pads.
        vert.co.y += 0.0065 * crease + 0.0020 * corners + 0.0020 * philtrum
        vert.co.y -= 0.0048 * upper + 0.0042 * lower
    body.data.update()
    # The locally dense faces make a real viewport-visible lip material smooth
    # enough to avoid the old coarse polygon steps. Keep the dark opening thin.
    lip_slot = len(body.data.materials)
    body.data.materials.append(lip_mat)
    mouth_slot = len(body.data.materials)
    body.data.materials.append(dark_mat)
    for polygon in body.data.polygons:
        center = sum((body.data.vertices[index].co for index in polygon.vertices),
                     Vector((0.0, 0.0, 0.0))) / len(polygon.vertices)
        if center.y >= -0.050:
            continue
        distance = (center.x / 0.032) ** 2 + ((center.z - 1.6775) / 0.0105) ** 2
        if distance <= 1.0:
            polygon.material_index = (mouth_slot
                                      if abs(center.x) < 0.028 and
                                      abs(center.z - 1.6775) < 0.0013
                                      else lip_slot)
    return body


def body_hair(body, mat):
    """Sparse, surface-projected chest, forearm, and shin hair."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    tree = BVHTree.FromObject(body, depsgraph)
    curve = bpy.data.curves.new("BodyHair.Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.00016
    curve.bevel_resolution = 1
    curve.resolution_u = 1

    seeds = []
    for index in range(44):
        u = (index * 0.61803398875) % 1.0
        v = (index * 0.41421356237 + 0.19) % 1.0
        x = -0.145 + 0.290 * u
        z = 1.075 + 0.365 * v
        if abs(x) < 0.025 and z > 1.33:
            continue
        seeds.append((x, z, 0.0030 + 0.0022 * ((index * 0.37) % 1.0)))
    for side in (-1.0, 1.0):
        for index in range(14):
            seeds.append((side * (0.325 + 0.035 * ((index * 0.43) % 1.0)),
                          0.985 + 0.205 * ((index * 0.61) % 1.0), 0.0032))
        for index in range(13):
            seeds.append((side * (0.105 + 0.050 * ((index * 0.47) % 1.0)),
                          0.205 + 0.285 * ((index * 0.59) % 1.0), 0.0030))

    for index, (x, z, length) in enumerate(seeds):
        hit = tree.ray_cast(Vector((x, -0.50, z)), Vector((0.0, 1.0, 0.0)), 1.0)
        location, normal = hit[0], hit[1]
        if location is None or normal is None or normal.y > -0.12:
            continue
        root = location + normal * 0.0006
        side_drift = 0.32 * sin(index * 1.91)
        tangent = Vector((side_drift, 0.0, -1.0)).normalized()
        tip = root + tangent * length + normal * 0.0009
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        spline.points[0].co = (*root, 1.0)
        spline.points[1].co = (*tip, 1.0)
    obj = bpy.data.objects.new("BodyHair", curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def head(mat, dark, white, iris, lip, brow_mat):
    h = add_scaled_sphere("Head", (0, -0.004, 1.790), (.097, .090, .144), mat, 80, 56)
    bm = bmesh.new(); bm.from_mesh(h.data)
    for v in bm.verts:
        x,y,z = v.co
        # Establish distinct adult head planes instead of one uninterrupted oval:
        # cranial vault, narrower temples, cheekbone shelf, cheek hollow, and jaw.
        v.co.x *= 1.0 + 0.025 * bell(z, 0.090, 0.038)
        v.co.x *= 1.0 - 0.070 * bell(z, 0.043, 0.038)
        v.co.x *= 1.0 + 0.055 * bell(z, -0.020, 0.032)
        v.co.x *= 1.0 - 0.022 * bell(z, -0.054, 0.019)
        if z < -0.025:
            jaw_taper = min(1.0, (-z-.025)/.105)
            v.co.x *= 1.0 - 0.18 * jaw_taper
            v.co.y *= 1.0 - 0.03 * min(1.0, (-z-.025)/.105)
            # A distinct mandibular angle and narrower chin break the balloon oval.
            v.co.x *= 1.0 + 0.145 * bell(z, -0.071, 0.024)
            v.co.x *= 1.0 + 0.030 * bell(z, -0.118, 0.018)
            # Extend the central chin slightly below the jaw without lengthening
            # the entire face or creating a pointed beard-like tip.
            chin_center = bell(x, 0.0, 0.065) * bell(z, -0.118, 0.025)
            v.co.z -= 0.006 * chin_center
        front = max(0.0, min(1.0, (-.015-y)/.07))
        if front > 0.0:
            eyes = max(bell(x, -0.032, 0.022), bell(x, 0.032, 0.022))
            socket = eyes * bell(z, 0.012, 0.015)
            brow = eyes * bell(z, 0.034, 0.014)
            bridge = bell(x, 0.0, 0.013) * bell(z, -0.016, 0.029)
            nose_tip = bell(x, 0.0, 0.019) * bell(z, -0.041, 0.012)
            cheek = max(bell(x, -0.054, 0.025), bell(x, 0.054, 0.025)) * bell(z, -0.030, 0.034)
            muzzle = bell(x, 0.0, 0.042) * bell(z, -0.066, 0.025)
            mouth_fold = bell(x, 0.0, 0.034) * bell(z, -0.076, 0.0055)
            upper_lip = max(bell(x, -0.010, 0.015), bell(x, 0.010, 0.015)) * bell(z, -0.073, 0.0060)
            lower_lip = bell(x, 0.0, 0.027) * bell(z, -0.082, 0.0075)
            chin = bell(x, 0.0, 0.050) * bell(z, -0.111, 0.020)
            mentolabial = bell(x, 0.0, 0.040) * bell(z, -0.091, 0.009)
            under_chin = bell(x, 0.0, 0.065) * bell(z, -0.132, 0.013)
            alar = max(bell(x, -0.012, 0.008), bell(x, 0.012, 0.008)) * bell(z, -0.045, 0.012)
            philtrum = bell(x, 0.0, 0.007) * bell(z, -0.064, 0.013)
            nasolabial = max(bell(x, -0.031, 0.0065), bell(x, 0.031, 0.0065)) * bell(z, -0.063, 0.026)
            lower_cheek_hollow = max(bell(x, -0.050, 0.020), bell(x, 0.050, 0.020)) * bell(z, -0.077, 0.025)
            v.co.y += front * 0.013 * socket
            v.co.y -= front * 0.010 * brow
            # Form the nose directly from the head surface. Separate alar/tip
            # meshes read as pellets even after the body union.
            v.co.y -= front * (0.015 * bridge + 0.021 * nose_tip + 0.0050 * alar)
            v.co.y -= front * (0.017 * cheek + 0.010 * muzzle + 0.040 * chin)
            v.co.y += front * (0.007 * mentolabial + 0.008 * under_chin)
            v.co.y += front * (0.0035 * nasolabial + 0.0030 * lower_cheek_hollow)
            v.co.y -= front * (0.0220 * upper_lip + 0.0190 * lower_lip)
            v.co.y += front * (0.0060 * mouth_fold + 0.0040 * philtrum)
    bm.to_mesh(h.data); bm.free()
    for s in (-1,1):
        # Very thin eye layers are buried into the sculpted sockets. Their front
        # surface is nearly 3 mm behind the rejected protruding version.
        add_scaled_sphere(f"Eye.{s}", (.0320*s,-.0823,1.801),(.0155,.0012,.0051),white,40,24)
        add_scaled_sphere(f"Iris.{s}",(.0320*s,-.08345,1.801),(.00425,.00032,.00425),iris,24,16)
        add_scaled_sphere(f"Pupil.{s}",(.0320*s,-.08372,1.801),(.00175,.00016,.00175),dark,18,10)
        add_scaled_sphere(f"EyeHighlight.{s}",(.0307*s,-.08390,1.8027),(.00058,.00008,.00058),white,12,8)
        add_scaled_sphere(f"Ear.{s}", (.097*s,-.001,1.787),(.013,.009,.025),mat,24,14)

        brow_data = bpy.data.curves.new(f"Brow.{s}.Curve", type="CURVE")
        brow_data.dimensions = "3D"
        brow_data.bevel_depth = 0.00105
        brow_data.bevel_resolution = 2
        brow = brow_data.splines.new("BEZIER")
        brow.bezier_points.add(3)
        for point, bx, bz, radius in zip(
                brow.bezier_points, (0.014, 0.026, 0.039, 0.052),
                (1.817, 1.8225, 1.821, 1.814), (0.78, 1.08, 1.0, 0.52)):
            point.co = (bx*s, -0.0842, bz)
            point.radius = radius
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        brow_obj = bpy.data.objects.new(f"Brow.{s}", brow_data)
        bpy.context.collection.objects.link(brow_obj)
        brow_obj.data.materials.append(brow_mat)

        lid_data = bpy.data.curves.new(f"UpperLid.{s}.Curve", type="CURVE")
        lid_data.dimensions = "3D"
        lid_data.bevel_depth = 0.00024
        lid_data.bevel_resolution = 2
        lid = lid_data.splines.new("BEZIER")
        lid.bezier_points.add(2)
        for point, lx, lz in zip(lid.bezier_points, (0.016, 0.032, 0.048),
                                 (1.802, 1.807, 1.802)):
            point.co = (lx*s, -0.0839, lz)
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        lid_obj = bpy.data.objects.new(f"UpperLid.{s}", lid_data)
        bpy.context.collection.objects.link(lid_obj)
        lid_obj.data.materials.append(dark)

    for s in (-1, 1):
        add_scaled_sphere(
            f"Nostril.{s}", (0.0098*s, -0.1148, 1.7432),
            (0.00325, 0.00065, 0.00125), dark, 24, 14
        )
    # Lips are part of the sculpted head surface above. The mouth curve supplies
    # separation without two floating capsule shapes.
    return h


def hair(mat):
    # Preserve the established close-crop layout, but use only the continuous
    # cap surface. Individual curve fibers created the unwanted pokey silhouette.
    cap = add_scaled_sphere("Hair", (0.0, 0.003, 1.807),
                            (0.103, 0.099, 0.146), mat, 176, 112)
    bm = bmesh.new()
    bm.from_mesh(cap.data)
    delete = []
    for vert in bm.verts:
        x, y, z = vert.co
        edge_breakup = 0.00045 * sin(61.0 * x) + 0.00030 * sin(47.0 * y + 0.7)
        center_peak = -0.0065 * bell(x, 0.0, 0.038)
        temple_recession = 0.010 * bell(abs(x), 0.076, 0.020)
        side_sweep = 0.004 * x / 0.103
        front_line = 0.035 + center_peak + temple_recession + side_sweep
        nape_curve = -0.007 * bell(x, 0.0, 0.060)
        # A tapered nape: lower at center back, rising naturally behind the ears.
        back_line = (-0.016 - 0.030 * bell(x, 0.0, 0.055) +
                     0.008 * bell(abs(x), 0.082, 0.020))
        # Blend around the temples instead of switching abruptly at y=0.
        front_weight = max(0.0, min(1.0, (0.024 - y) / 0.052))
        front_weight = front_weight * front_weight * (3.0 - 2.0 * front_weight)
        hairline = back_line * (1.0 - front_weight) + front_line * front_weight + edge_breakup
        if z < hairline:
            delete.append(vert)
        else:
            if z > 0.055:
                vert.co.z = 0.055 + (z - 0.055) * 0.88
            # Broad, shallow clumps follow the scalp from crown to hairline.
            # Relief fades at the cut edge, preventing the old pokey silhouette.
            azimuth = atan2(x, -y)
            height = max(0.0, min(1.0, (z + 0.020) / 0.165))
            phase = 7.5 * azimuth - 3.6 * height + 0.55 * sin(2.0 * azimuth)
            secondary = 11.5 * azimuth - 5.2 * height + 0.8
            clump = 0.68 * cos(phase) + 0.32 * cos(secondary)
            edge_fade = max(0.0, min(1.0, (z - hairline) / 0.020))
            crown_fade = max(0.06, 1.0 - bell(z, 0.143, 0.020))
            relief = 0.00265 * clump * edge_fade * crown_fade
            normal = Vector((x / (0.103 ** 2), y / (0.099 ** 2),
                             vert.co.z / (0.146 ** 2))).normalized()
            vert.co += normal * relief
    bmesh.ops.delete(bm, geom=delete, context="VERTS")
    # The deletion follows latitude rings, so its raw boundary can staircase.
    # Project the surviving open edge onto the analytical hairline for a clean cut.
    for vert in bm.verts:
        if not any(edge.is_boundary for edge in vert.link_edges):
            continue
        x, y, _ = vert.co
        edge_breakup = 0.00045 * sin(61.0 * x) + 0.00030 * sin(47.0 * y + 0.7)
        center_peak = -0.0065 * bell(x, 0.0, 0.038)
        temple_recession = 0.010 * bell(abs(x), 0.076, 0.020)
        side_sweep = 0.004 * x / 0.103
        front_line = 0.035 + center_peak + temple_recession + side_sweep
        back_line = (-0.016 - 0.030 * bell(x, 0.0, 0.055) +
                     0.008 * bell(abs(x), 0.082, 0.020))
        front_weight = max(0.0, min(1.0, (0.024 - y) / 0.052))
        front_weight = front_weight * front_weight * (3.0 - 2.0 * front_weight)
        vert.co.z = back_line * (1.0 - front_weight) + front_line * front_weight + edge_breakup
    # Weight a narrow band above the open cut edge for surface conformation.
    bm.verts.index_update()
    hairline_weights = {}
    for vert in bm.verts:
        x, y, z = vert.co
        edge_breakup = 0.00045 * sin(61.0 * x) + 0.00030 * sin(47.0 * y + 0.7)
        center_peak = -0.0065 * bell(x, 0.0, 0.038)
        temple_recession = 0.010 * bell(abs(x), 0.076, 0.020)
        side_sweep = 0.004 * x / 0.103
        front_line = 0.035 + center_peak + temple_recession + side_sweep
        back_line = (-0.016 - 0.030 * bell(x, 0.0, 0.055) +
                     0.008 * bell(abs(x), 0.082, 0.020))
        front_weight = max(0.0, min(1.0, (0.024 - y) / 0.052))
        front_weight = front_weight * front_weight * (3.0 - 2.0 * front_weight)
        local_line = back_line * (1.0 - front_weight) + front_line * front_weight + edge_breakup
        distance = max(0.0, z - local_line)
        if distance < 0.060:
            weight = 1.0 - distance / 0.060
            hairline_weights[vert.index] = weight * weight * (3.0 - 2.0 * weight)
    bm.to_mesh(cap.data)
    bm.free()
    group = cap.vertex_groups.new(name="HairlineConform")
    for index, weight in hairline_weights.items():
        group.add([index], weight, "REPLACE")
    return cap


def conform_head_details(body, hair_obj):
    """Seat the weighted hairline band onto the final unified head surface."""
    hair_wrap = hair_obj.modifiers.new("ConnectedHairline", "SHRINKWRAP")
    hair_wrap.target = body
    hair_wrap.wrap_method = "NEAREST_SURFACEPOINT"
    hair_wrap.wrap_mode = "ON_SURFACE"
    hair_wrap.offset = 0.0015
    hair_wrap.vertex_group = "HairlineConform"
    return hair_obj


def hands(mat):
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        x = 0.345 * side
        # The palm is part of ConnectedBody's skin graph. Only the digits are
        # unioned here, avoiding a separate palm-to-wrist Boolean ring.
        finger_offsets = (-0.025, -0.008, 0.008, 0.025)
        finger_lengths = (0.069, 0.076, 0.071, 0.055)
        finger_widths = (0.0094, 0.0099, 0.0095, 0.0083)
        finger_splays = (-0.0015, -0.0005, 0.0005, 0.0015)
        for index, (offset, length, width, splay) in enumerate(
                zip(finger_offsets, finger_lengths, finger_widths, finger_splays), 1):
            fx = x + side * offset
            tip_x = fx + side * splay
            root_z = 0.840
            create_path_limb(f"Finger{index}.{suffix}", [
                ((fx, -0.010, root_z), width * 1.16, width * 1.02),
                ((fx, -0.013, root_z - length * 0.25), width * 0.93, width * 0.88),
                ((fx + side * splay * 0.35, -0.018, root_z - length * 0.50),
                 width * 0.99, width * 0.91),
                ((fx + side * splay * 0.72, -0.022, root_z - length * 0.77),
                 width * 0.80, width * 0.77),
                ((tip_x, -0.024, root_z - length), width * 0.66, width * 0.68),
            ], mat, sides=12, subdivision=2)
        create_path_limb(f"Thumb.{suffix}", [
            ((x - side * 0.026, -0.006, 0.858), 0.0115, 0.0105),
            ((x - side * 0.040, -0.011, 0.837), 0.0094, 0.0089),
            ((x - side * 0.049, -0.016, 0.819), 0.0100, 0.0090),
            ((x - side * 0.057, -0.017, 0.802), 0.0074, 0.0072),
        ], mat, sides=12, subdivision=2)


def integrated_hands(mat):
    """Build each palm and all five digits as one locally remeshed hand."""
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        x = 0.345 * side
        parts = []
        palm = create_path_limb(f"HandPalm.{suffix}", [
            # The connected body graph owns shoulder, arm, forearm, and wrist.
            # Start the hand inside that wrist so there is no exposed end cap.
            ((x, 0.002, 0.936), 0.035, 0.039),
            ((x, 0.000, 0.912), 0.033, 0.036),
            ((x, -0.004, 0.878), 0.039, 0.031),
            ((x, -0.009, 0.844), 0.043, 0.026),
            ((x, -0.012, 0.816), 0.040, 0.023),
        ], mat, sides=18, subdivision=2)
        parts.append(palm)
        offsets = (-0.026, -0.009, 0.009, 0.026)
        lengths = (0.060, 0.073, 0.069, 0.053)
        widths = (0.0090, 0.0102, 0.0097, 0.0083)
        for index, (offset, length, width) in enumerate(zip(offsets, lengths, widths), 1):
            fx = x + side * offset
            splay = side * offset * 0.055
            finger = create_path_limb(f"HandFinger{index}.{suffix}", [
                ((fx, -0.012, 0.836), width * 1.12, width * 0.98),
                ((fx, -0.017, 0.814), width, width * 0.90),
                ((fx + splay * 0.45, -0.021, 0.836 - length * 0.62), width * 0.86, width * 0.82),
                ((fx + splay, -0.022, 0.836 - length), width * 0.67, width * 0.70),
            ], mat, sides=12, subdivision=2)
            parts.append(finger)
        thumb = create_path_limb(f"HandThumb.{suffix}", [
            ((x - side * 0.027, -0.007, 0.858), 0.0122, 0.0110),
            ((x - side * 0.043, -0.012, 0.838), 0.0105, 0.0096),
            ((x - side * 0.054, -0.016, 0.817), 0.0092, 0.0088),
            ((x - side * 0.061, -0.017, 0.799), 0.0072, 0.0070),
        ], mat, sides=12, subdivision=2)
        parts.append(thumb)
        for part in parts:
            apply_all_modifiers(part)
        bpy.ops.object.select_all(action="DESELECT")
        for part in parts:
            part.select_set(True)
        bpy.context.view_layer.objects.active = palm
        bpy.ops.object.join()
        palm.name = f"HandIntegrated.{suffix}"
        palm.data.remesh_voxel_size = 0.0017
        palm.data.remesh_voxel_adaptivity = 0.0
        bpy.ops.object.voxel_remesh()
        bm = bmesh.new()
        bm.from_mesh(palm.data)
        for _ in range(9):
            bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=0.24,
                                  use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bm.to_mesh(palm.data)
        bm.free()
        for polygon in palm.data.polygons:
            polygon.use_smooth = True
        palm.select_set(False)


def forearm_seam_bridges(mat):
    """Buried matched-radius masses eliminate the upper/lower arm Boolean ring."""
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        add_scaled_sphere(f"ForearmSeamBridge.{suffix}",
                          (0.311 * side, 0.007, 1.245),
                          (0.065, 0.070, 0.078), mat, 36, 24)


def fingernails(nail_mat):
    """Small embedded nail plates finish the remeshed fingers."""
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        x = 0.345 * side
        offsets = (-0.026, -0.009, 0.009, 0.026)
        lengths = (0.060, 0.073, 0.069, 0.053)
        widths = (0.0090, 0.0102, 0.0097, 0.0083)
        for index, (offset, length, width) in enumerate(zip(offsets, lengths, widths), 1):
            fx = x + side * offset
            splay = side * offset * 0.055
            add_scaled_sphere(f"Fingernail{index}.{suffix}",
                              (fx + splay, -0.0227, 0.838 - length),
                              (width * 0.54, 0.00055, width * 0.66),
                              nail_mat, 18, 10)
        add_scaled_sphere(f"Thumbnail.{suffix}",
                          (x - side * 0.061, -0.0178, 0.800),
                          (0.0043, 0.00055, 0.0055), nail_mat, 18, 10)


def feet(mat):
    """Explicit anatomical foot shell: heel, ankle, instep, ball, and toe base."""
    result = {}
    sides = 20
    rings = [
        (0.052, 0.075, 0.043, 0.030),
        (0.010, 0.082, 0.048, 0.045),
        (-0.060, 0.071, 0.052, 0.041),
        (-0.125, 0.061, 0.062, 0.032),
        (-0.168, 0.056, 0.073, 0.026),
        (-0.198, 0.052, 0.070, 0.021),
    ]
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        center_x = 0.132 * side
        verts = []
        for y, center_z, half_width, half_height in rings:
            for step in range(sides):
                angle = 2.0 * 3.141592653589793 * step / sides
                x = center_x + half_width * cos(angle)
                z = max(0.030, center_z + half_height * sin(angle))
                # A slightly higher inner arch avoids another inflated capsule.
                inner = max(0.0, 1.0 - abs(x - center_x + side * 0.026) / 0.040)
                if -0.105 < y < -0.010 and z < 0.060:
                    z += 0.008 * inner
                verts.append((x, y, z))
        faces = []
        for ring in range(len(rings) - 1):
            for step in range(sides):
                nxt = (step + 1) % sides
                a = ring * sides + step
                b = ring * sides + nxt
                c = (ring + 1) * sides + nxt
                d = (ring + 1) * sides + step
                faces.append((a, b, c, d))
        faces.append(tuple(reversed(tuple(range(sides)))))
        last = (len(rings) - 1) * sides
        faces.append(tuple(last + step for step in range(sides)))
        foot = mesh_object(f"Foot.{suffix}", verts, faces, mat, subdivision=1)
        for poly in foot.data.polygons:
            poly.use_smooth = True
        result[suffix] = foot
    return result


def toes(mat, nail, foot_shells):
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        center = 0.132 * side
        toe_parts = []
        # Inner (big) toe to outer toe, mirrored per foot and buried into the ball.
        offsets = (-0.050, -0.025, 0.000, 0.025, 0.048)
        lengths = (0.071, 0.076, 0.070, 0.061, 0.052)
        radii = (0.022, 0.0180, 0.0160, 0.0140, 0.0115)
        splays = (-0.0014, -0.0007, 0.000, 0.0007, 0.0014)
        for index, (offset, length, radius, splay) in enumerate(zip(offsets, lengths, radii, splays), 1):
            x = center + offset * side
            tip_x = x + side * splay
            middle_x = x + side * splay * 0.45
            tip_y = -0.150 - length * 1.10
            toe = create_path_limb(
                f"Toe{index}.{suffix}",
                [
                    ((x, -0.152, 0.060), radius * 0.87, radius * 0.60),
                    ((middle_x, -0.184 - length * 0.10, 0.063), radius, radius * 0.70),
                    ((tip_x, tip_y, 0.058), radius * 0.70, radius * 0.52),
                ],
                mat, sides=14, subdivision=2
            )
            toe_parts.append(toe)
            add_scaled_sphere(
                f"Toenail{index}.{suffix}",
                (tip_x, tip_y + length * 0.15, 0.058 + radius * 0.49),
                (radius * 0.57, length * 0.13, 0.0010),
                nail, 18, 10
            )
        # Fuse shell and digits locally before the foot touches the body. This
        # leaves one ankle Boolean instead of five exposed toe-root Booleans.
        components = [foot_shells[suffix]] + toe_parts
        for component in components:
            apply_all_modifiers(component)
        bpy.ops.object.select_all(action="DESELECT")
        for component in components:
            component.select_set(True)
        foot = foot_shells[suffix]
        bpy.context.view_layer.objects.active = foot
        bpy.ops.object.join()
        foot.name = f"FootIntegrated.{suffix}"
        foot.data.remesh_voxel_size = 0.0018
        foot.data.remesh_voxel_adaptivity = 0.0
        bpy.ops.object.voxel_remesh()
        bm = bmesh.new()
        bm.from_mesh(foot.data)
        for _ in range(12):
            bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=0.30,
                                  use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bm.to_mesh(foot.data)
        bm.free()
        foot.data.update()
        for polygon in foot.data.polygons:
            polygon.use_smooth = True
        foot.select_set(False)


def loincloth(mat, cord_mat, body):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.166, minor_radius=0.006,
                                    major_segments=40, minor_segments=10,
                                    location=(0.0, 0.0, 0.990))
    band = bpy.context.object
    band.name = "ClothWaistCord"
    band.scale.y = 0.77
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    band.data.materials.append(cord_mat)

    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        tie_data = bpy.data.curves.new(f"LoinTie.{suffix}.Curve", type="CURVE")
        tie_data.dimensions = "3D"
        tie_data.bevel_depth = 0.0042
        tie_data.bevel_resolution = 3
        tie = tie_data.splines.new("BEZIER")
        tie.bezier_points.add(3)
        tie_points = [
            (0.105 * side, -0.148, 0.995),
            (0.168 * side, -0.070, 0.998),
            (0.176 * side, 0.070, 0.997),
            (0.108 * side, 0.178, 0.995),
        ]
        for point, co in zip(tie.bezier_points, tie_points):
            point.co = co
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        tie_obj = bpy.data.objects.new(f"LoinTie.{suffix}", tie_data)
        bpy.context.collection.objects.link(tie_obj)
        tie_obj.data.materials.append(cord_mat)
        add_scaled_sphere(f"LoinKnot.{suffix}", (0.176 * side, -0.002, 0.993),
                          (0.010, 0.009, 0.010), cord_mat, 20, 12)
        tail_data = bpy.data.curves.new(f"LoinTail.{suffix}.Curve", type="CURVE")
        tail_data.dimensions = "3D"
        tail_data.bevel_depth = 0.0034
        tail_data.bevel_resolution = 3
        tail = tail_data.splines.new("BEZIER")
        tail.bezier_points.add(2)
        for point, co in zip(tail.bezier_points, [
            (0.176 * side, -0.002, 0.993),
            (0.184 * side, -0.010, 0.940),
            (0.174 * side, 0.000, 0.885),
        ]):
            point.co = co
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        tail_obj = bpy.data.objects.new(f"LoinTail.{suffix}", tail_data)
        bpy.context.collection.objects.link(tail_obj)
        tail_obj.data.materials.append(cord_mat)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    body_tree = BVHTree.FromObject(body, depsgraph)

    def flap(name, front):
        direction = -1.0 if front else 1.0
        if front:
            rows = [
                (0.990, 0.128, 0.112), (0.950, 0.132, 0.111),
                (0.910, 0.134, 0.108), (0.865, 0.132, 0.103),
                (0.820, 0.126, 0.090), (0.780, 0.118, 0.079),
                (0.748, 0.111, 0.070),
            ]
        else:
            rows = [
                (0.990, 0.139, 0.113), (0.950, 0.152, 0.114),
                (0.910, 0.164, 0.112), (0.865, 0.166, 0.108),
                (0.820, 0.156, 0.101), (0.780, 0.139, 0.094),
                (0.748, 0.121, 0.087),
            ]
        verts = []
        columns = (-1.0, -0.84, -0.68, -0.52, -0.34, -0.17, 0.0,
                   0.17, 0.34, 0.52, 0.68, 0.84, 1.0)
        for row_index, (z, depth, half_width) in enumerate(rows):
            for column in columns:
                center_drape = 0.0012 * (1.0 - column * column)
                fold = 0.0065 * sin((column + 1.0) * pi * 3.0) * (0.30 + 0.70 * row_index / (len(rows)-1))
                if front:
                    surface_wrap = -0.010 * column * column
                else:
                    # Conform to the glute/thigh surface instead of bowing away.
                    surface_wrap = -0.008 * column * column
                top_dip = -0.007 * (1.0 - column * column) if row_index == 0 else 0.0
                curved_hem = ((0.018 * abs(column) + 0.004 * sin(2.3 * column + 0.4))
                              if row_index == len(rows) - 1 else 0.0)
                x_co = half_width * column
                z_co = z + top_dip + curved_hem
                y_co = direction * (depth + center_drape + fold + surface_wrap)
                if not front:
                    # Project the rear panel onto the actual glute/thigh surface;
                    # fixed depth rows bowed away from the body in profile.
                    hit = body_tree.ray_cast(Vector((x_co, 0.50, z_co)),
                                             Vector((0.0, -1.0, 0.0)), 1.0)
                    if hit[0] is not None:
                        # Use the body as a minimum clearance, not a literal
                        # shrink-wrap: cloth bridges the glute cleft instead of
                        # diving into it and exposing skin through the panel.
                        projected_y = hit[0].y + 0.008 + 0.30 * abs(fold)
                        y_co = max(y_co, projected_y)
                verts.append((x_co, y_co, z_co))
        faces = []
        for row in range(len(rows) - 1):
            for column in range(len(columns) - 1):
                a = row * len(columns) + column
                b = a + len(columns)
                faces.append((a, a+1, b+1, b))
        obj = mesh_object(name, verts, faces, mat, subdivision=0)
        sub = obj.modifiers.new("ClothDrape", "SUBSURF")
        sub.levels = 2
        sub.render_levels = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=sub.name)
        obj.select_set(False)
        solid = obj.modifiers.new("ClothThickness", "SOLIDIFY")
        solid.thickness = 0.0016
        bevel = obj.modifiers.new("SoftClothEdge", "BEVEL")
        bevel.width = 0.0016
        bevel.segments = 2
        return obj

    flap("Loincloth.Front", True)
    flap("Loincloth.Back", False)


def under_tunic(cloth, leather, metal):
    create_vertical_loft("UnderTunic", [
        (0.900, 0.0, 0.010, 0.184, 0.137),
        (1.000, 0.0, 0.006, 0.183, 0.135),
        (1.145, 0.0, 0.000, 0.176, 0.130),
        (1.330, 0.0, -0.006, 0.205, 0.152),
        (1.455, 0.0, -0.003, 0.218, 0.158),
        (1.520, 0.0, 0.000, 0.158, 0.122),
    ], cloth, sides=24, subdivision=2)
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        create_path_limb(f"TunicSleeve.{suffix}", [
            ((0.215*side, 0.000, 1.470), 0.086, 0.094),
            ((0.285*side, 0.000, 1.360), 0.081, 0.089),
            ((0.330*side, 0.006, 1.200), 0.075, 0.081),
            ((0.350*side, 0.012, 1.060), 0.059, 0.065),
            ((0.355*side, 0.015, 0.920), 0.064, 0.071),
            ((0.355*side, 0.005, 0.855), 0.049, 0.054),
        ], cloth, sides=16, subdivision=2)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.165, minor_radius=0.013,
                                    major_segments=40, minor_segments=10,
                                    location=(0.0, 0.0, 0.995))
    belt = bpy.context.object
    belt.name = "WornBelt"
    belt.scale.y = 0.76
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    belt.data.materials.append(leather)
    add_scaled_sphere("BeltBuckle", (0.0, -0.132, 0.995),
                      (0.025, 0.008, 0.020), metal, 20, 12)


def build():
    clear_scene()
    skin = skin_material()
    dark = material("Dark", (.025,.018,.014,1), .75)
    white = material("Eyes", (.68,.655,.595,1), .7)
    iris = material("IrisBrown", (.18,.070,.024,1), .58)
    lip = material("LipTone", (.34,.15,.13,1), .92)
    hair_mat = material("HairBrown", (.055,.020,.009,1), .88)
    brow_mat = material("BrowBrown", (.020,.006,.0025,1), .92)
    hair_mat.use_nodes = True
    hair_nodes = hair_mat.node_tree.nodes
    hair_bsdf = next(node for node in hair_nodes if node.type == "BSDF_PRINCIPLED")
    hair_bsdf.inputs["Roughness"].default_value = 0.84
    hair_bsdf.inputs["Specular IOR Level"].default_value = 0.28
    hair_bsdf.inputs["Anisotropic"].default_value = 0.10
    hair_links = hair_mat.node_tree.links
    hair_coord = hair_nodes.new("ShaderNodeTexCoord")
    hair_mapping = hair_nodes.new("ShaderNodeMapping")
    hair_mapping.inputs["Scale"].default_value = (7.5, 7.5, 1.35)
    hair_noise = hair_nodes.new("ShaderNodeTexNoise")
    hair_noise.inputs["Scale"].default_value = 4.8
    hair_noise.inputs["Detail"].default_value = 2.4
    hair_noise.inputs["Roughness"].default_value = 0.56
    hair_bump = hair_nodes.new("ShaderNodeBump")
    hair_bump.inputs["Strength"].default_value = 0.48
    hair_bump.inputs["Distance"].default_value = 0.0038
    hair_roughness = hair_nodes.new("ShaderNodeValToRGB")
    hair_roughness.color_ramp.elements[0].color = (0.76, 0.76, 0.76, 1)
    hair_roughness.color_ramp.elements[1].color = (0.92, 0.92, 0.92, 1)
    hair_color = hair_nodes.new("ShaderNodeValToRGB")
    hair_color.color_ramp.elements[0].position = 0.22
    hair_color.color_ramp.elements[0].color = (.038, .012, .005, 1)
    hair_color.color_ramp.elements[1].position = 0.78
    hair_color.color_ramp.elements[1].color = (.072, .023, .010, 1)
    hair_links.new(hair_coord.outputs["Generated"], hair_mapping.inputs["Vector"])
    hair_links.new(hair_mapping.outputs["Vector"], hair_noise.inputs["Vector"])
    hair_links.new(hair_noise.outputs["Fac"], hair_bump.inputs["Height"])
    hair_links.new(hair_bump.outputs["Normal"], hair_bsdf.inputs["Normal"])
    hair_links.new(hair_noise.outputs["Fac"], hair_roughness.inputs["Fac"])
    hair_links.new(hair_roughness.outputs["Color"], hair_bsdf.inputs["Roughness"])
    hair_links.new(hair_noise.outputs["Fac"], hair_color.inputs["Fac"])
    hair_links.new(hair_color.outputs["Color"], hair_bsdf.inputs["Base Color"])
    nail_mat = material("Nails", (.72,.455,.390,1), .72)
    areola_mat = material("AreolaTone", (.25,.100,.065,1), .84)
    nipple_mat = material("NippleTone", (.15,.040,.025,1), .86)
    loincloth_mat = material("PlainLoincloth", (.22,.105,.050,1), .96)
    cord_mat = material("LoinCord", (.105,.040,.014,1), .88)
    body_hair_mat = material("BodyHairBrown", (.032,.012,.006,1), .92)
    for tuned_mat, roughness, specular in [
        (dark, 0.82, 0.30), (white, 0.76, 0.34), (iris, 0.68, 0.34),
        (lip, 0.88, 0.30), (nail_mat, 0.82, 0.30),
        (areola_mat, 0.84, 0.30), (nipple_mat, 0.83, 0.30),
        (loincloth_mat, 0.97, 0.20), (cord_mat, 0.94, 0.22),
        (body_hair_mat, 0.94, 0.18),
    ]:
        tuned_bsdf = next(node for node in tuned_mat.node_tree.nodes
                          if node.type == "BSDF_PRINCIPLED")
        tuned_bsdf.inputs["Roughness"].default_value = roughness
        tuned_bsdf.inputs["Specular IOR Level"].default_value = specular
    loincloth_mat.use_nodes = True
    cloth_nodes = loincloth_mat.node_tree.nodes
    cloth_links = loincloth_mat.node_tree.links
    cloth_bsdf = next(node for node in cloth_nodes if node.type == "BSDF_PRINCIPLED")
    cloth_noise = cloth_nodes.new("ShaderNodeTexNoise")
    cloth_noise.inputs["Scale"].default_value = 48.0
    cloth_noise.inputs["Detail"].default_value = 2.0
    cloth_color = cloth_nodes.new("ShaderNodeValToRGB")
    cloth_color.color_ramp.elements[0].position = 0.28
    cloth_color.color_ramp.elements[0].color = (.145, .052, .020, 1)
    cloth_color.color_ramp.elements[1].position = 0.74
    cloth_color.color_ramp.elements[1].color = (.285, .125, .046, 1)
    cloth_bump = cloth_nodes.new("ShaderNodeBump")
    cloth_bump.inputs["Strength"].default_value = 0.24
    cloth_bump.inputs["Distance"].default_value = 0.0013
    cloth_links.new(cloth_noise.outputs["Fac"], cloth_bump.inputs["Height"])
    cloth_links.new(cloth_bump.outputs["Normal"], cloth_bsdf.inputs["Normal"])
    cloth_links.new(cloth_noise.outputs["Fac"], cloth_color.inputs["Fac"])
    cloth_links.new(cloth_color.outputs["Color"], cloth_bsdf.inputs["Base Color"])
    ground = material("Ground", (.11,.12,.12,1), 1)
    body = connected_body(skin)
    integrated_hands(skin)
    head(skin,dark,white,iris,lip,brow_mat)
    hair_obj = hair(hair_mat)
    foot_shells = feet(skin)
    toes(skin, nail_mat, foot_shells)
    unify_skin(body, skin)
    relax_joint_seams(body)
    # Definition is applied after seam relaxation so the broad smoothing pass
    # cannot erase the deltoids, limb groups, abs, knees, or back landmarks.
    sculpt_abs(body)
    sculpt_muscle_tone(body)
    sculpt_anatomical_landmarks(body)
    shorten_neck_and_align_head(body)
    finalize_mouth_geometry(body, lip, dark)
    conform_head_details(body, hair_obj)
    nipples(areola_mat, nipple_mat, body)
    fingernails(nail_mat)
    loincloth(loincloth_mat, cord_mat, body)
    body_hair(body, body_hair_mat)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0,0,0)); bpy.context.object.data.materials.append(ground)
    for loc,energy,size in [((-3,-4,4.5),700,4),((3,-2,3),300,3),((0,3,4),400,3)]:
        bpy.ops.object.light_add(type="AREA",location=loc); l=bpy.context.object; l.data.energy=energy; l.data.shape="DISK"; l.data.size=size
    bpy.ops.object.camera_add(location=(0,-5.3,1.05)); cam=bpy.context.object; cam.data.lens=72; point_camera(cam,(0,0,1.02)); bpy.context.scene.camera=cam
    scene=bpy.context.scene; scene.render.engine="BLENDER_EEVEE"; scene.unit_settings.system="METRIC"
    scene.world.color=(.025,.025,.03)
    # Make material colors visible immediately when the blend opens in Solid mode.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.type = "MATERIAL"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("Saved",OUT)


if __name__ == "__main__":
    build()
