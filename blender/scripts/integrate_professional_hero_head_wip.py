"""Graft the approved professional-topology head onto a master-copy WIP.

The canonical master is never overwritten by this script.  The old face and
hair are removed only from the WIP copy, while the existing body, rig, armor,
materials, equipment, and every action remain intact.
"""

import bmesh
import bpy
from math import exp, pi, sin
from mathutils import Vector
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
SOURCE_HEAD_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Head_Professional_WIP.blend")
OUTPUT_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master_HeadRebuild_WIP.blend")
OUTPUT_DIR = os.path.join(BLEND_DIR, "previews", "hero_head_integration_wip")

SOURCE_CUT_Z = 1.60000
OLD_BODY_CUT_Z = 1.605
SOURCE_EYE_Z = 1.74205
TARGET_EYE_Z = 1.7597
SOURCE_MALE_Z_SHIFT = SOURCE_EYE_Z - 1.6116
SOURCE_LIP_Z = 1.6671
SOURCE_BROW_Z = 1.7678
LOWER_Z_SCALE = 0.900
UPPER_Z_SCALE = 1.050

HEAD_SOURCE_OBJECTS = (
    "HeroProfessionalTopology",
    "Eyes.ProfessionalWIP",
    "Iris.L",
    "Iris.R",
    "Pupil.L",
    "Pupil.R",
    "Brows.RootedGroom",
    "Face.RootedStubble",
    "Hair.ShortGroom",
    "Hair.DirectionalClumps",
)

OLD_HEAD_OBJECTS = {
    "Hair",
    "Brow.-1", "Brow.1",
    "Eye.-1", "Eye.1",
    "EyeHighlight.-1", "EyeHighlight.1",
    "Iris.-1", "Iris.1",
    "Pupil.-1", "Pupil.1",
    "UpperLid.-1", "UpperLid.1",
    "Nostril.-1", "Nostril.1",
    "MouthCreaseSurface", "MouthLowerSurface", "MouthUpperSurface",
}


def map_z(value):
    scale = LOWER_Z_SCALE if value <= SOURCE_EYE_Z else UPPER_Z_SCALE
    return TARGET_EYE_Z + (value - SOURCE_EYE_Z) * scale


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def map_x(value):
    # The source is already a broad adult male. Keep its internal facial
    # proportions coherent; the old nonlinear 9-38% widening distorted the
    # jaw, ears, eye spacing and cranium into separate-looking regions.
    return value * 1.065


def map_y(value, source_z):
    # Preserve the authored profile. Only the hidden neck overlap receives a
    # small depth increase to meet the legacy torso.
    amount = smoothstep((source_z - SOURCE_CUT_Z) / 0.080)
    scale = 1.10 * (1.0 - amount) + 1.00 * amount
    offset = 0.008 * (1.0 - amount)
    return value * scale + offset


def mapped_point(point):
    return Vector((map_x(point.x), map_y(point.y, point.z), map_z(point.z)))


def append_head_sources():
    if not os.path.isfile(SOURCE_HEAD_BLEND):
        raise RuntimeError(f"Professional head WIP is missing: {SOURCE_HEAD_BLEND}")
    with bpy.data.libraries.load(SOURCE_HEAD_BLEND, link=False) as (source, target):
        missing = sorted(set(HEAD_SOURCE_OBJECTS) - set(source.objects))
        if missing:
            raise RuntimeError(f"Professional head WIP is missing objects: {missing}")
        target.objects = list(HEAD_SOURCE_OBJECTS)
    appended = {}
    for obj in target.objects:
        bpy.context.scene.collection.objects.link(obj)
        appended[obj.name] = obj
    return appended


def evaluated_mesh(source, output_name):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(
        evaluated, depsgraph=depsgraph, preserve_all_data_layers=True,
    )
    mesh.name = output_name + ".Mesh"
    mesh.transform(source.matrix_world)
    obj = bpy.data.objects.new(output_name, mesh)
    return obj


def clear_deform_data(obj):
    while len(obj.vertex_groups):
        obj.vertex_groups.remove(obj.vertex_groups[0])
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    deform = bm.verts.layers.deform.active
    if deform is not None:
        for vertex in bm.verts:
            vertex[deform].clear()
    bm.to_mesh(obj.data)
    bm.free()


def transform_mesh(obj):
    for vertex in obj.data.vertices:
        vertex.co = mapped_point(vertex.co)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def crop_source_head(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Plane-bisect the continuous source topology instead of deleting whole
    # rows. Deleting produced the obvious saw-toothed neck boundary.
    bmesh.ops.bisect_plane(
        bm,
        geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        dist=0.00001,
        plane_co=(0.0, 0.0, SOURCE_CUT_Z),
        plane_no=(0.0, 0.0, 1.0),
        clear_inner=True,
        clear_outer=False,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    if not obj.data.polygons:
        raise RuntimeError("Professional head crop produced an empty mesh")


def taper_hidden_lower_neck(obj):
    """Narrow only the overlap ring behind the jaw, never the face itself."""
    center_y = -0.010
    for vertex in obj.data.vertices:
        if vertex.co.z >= 1.695 or vertex.co.y <= -0.100:
            continue
        amount = smoothstep((vertex.co.z - 1.647) / 0.048)
        x_scale = 0.64 + 0.36 * amount
        y_scale = 0.80 + 0.20 * amount
        vertex.co.x *= x_scale
        vertex.co.y = center_y + (vertex.co.y - center_y) * y_scale
    obj.data.update()


def sculpt_integrated_masculine_planes(obj):
    """Strengthen adult hero planes without changing attachment topology."""
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        # Stronger lower jaw corners: modest side expansion and shallower
        # hollowing, fading out before the cheeks and neck overlap.
        if 1.715 < z < 1.790 and 0.050 < ax < 0.125:
            z_factor = sin(pi * max(0.0, min(1.0, (z - 1.715) / 0.075)))
            x_factor = max(0.0, min(1.0, (ax - 0.050) / 0.060))
            vertex.co.x *= 1.0 + 0.065 * z_factor * x_factor
            vertex.co.y += 0.0050 * z_factor * x_factor
        # Brow/temple mass: bring the supraorbital area subtly forward while
        # leaving the eyelid loops themselves unchanged.
        if 1.805 < z < 1.845 and 0.018 < ax < 0.095 and y < -0.045:
            vertex.co.y -= 0.0050 * sin(pi * (z - 1.805) / 0.040)
        # Adult cheek planes: increase zygomatic projection laterally while
        # keeping the nasolabial and eyelid topology continuous.
        if 1.765 < z < 1.820 and 0.040 < ax < 0.098 and y < -0.042:
            cheek_z = sin(pi * (z - 1.765) / 0.055)
            cheek_x = sin(pi * max(0.0, min(1.0, (ax - 0.040) / 0.058)))
            vertex.co.y -= 0.0042 * cheek_z * cheek_x
        # Keep the adult-male source eyelid aperture intact. It already has
        # natural lid coverage; the prior post-graft closing pass caused the
        # characteristic squint in otherwise neutral poses.
    obj.data.update()


def extend_continuous_neck(obj):
    """Extrude the head's own neck loop into a sealed torso-overlap graft."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    boundary = [
        edge for edge in bm.edges
        if len(edge.link_faces) == 1
        and max(vertex.co.z for vertex in edge.verts) < 1.645
    ]
    if not boundary:
        bm.free()
        raise RuntimeError("Professional head has no usable neck boundary loop")
    current_edges = boundary
    top_z = sum(vertex.co.z for edge in boundary for vertex in edge.verts) / (2.0 * len(boundary))
    steps = (
        (top_z - 0.016, 1.01, 1.010, -0.001),
        (top_z - 0.034, 1.020, 1.015, -0.001),
        (top_z - 0.054, 1.030, 1.020, -0.001),
        (top_z - 0.070, 1.040, 1.025, -0.001),
    )
    original_center_y = -0.010
    for target_z, scale_x, scale_y, center_shift in steps:
        result = bmesh.ops.extrude_edge_only(bm, edges=current_edges, use_select_history=False)
        new_verts = [element for element in result["geom"] if isinstance(element, bmesh.types.BMVert)]
        new_edges = [element for element in result["geom"] if isinstance(element, bmesh.types.BMEdge)]
        if not new_verts or not new_edges:
            bm.free()
            raise RuntimeError("Continuous neck extrusion failed")
        for vertex in new_verts:
            vertex.co.x *= scale_x
            vertex.co.y = original_center_y + (vertex.co.y - original_center_y) * scale_y + center_shift
            vertex.co.z = target_z
        current_edges = [edge for edge in new_edges if len(edge.link_faces) == 1]
    bmesh.ops.holes_fill(bm, edges=current_edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj["neck_topology"] = "continuous_extruded_sealed_graft"


def bind_head_mesh(obj, rig, blended_neck=False):
    clear_deform_data(obj)
    head_group = obj.vertex_groups.new(name="head")
    if blended_neck:
        neck_group = obj.vertex_groups.new(name="neck")
        for vertex in obj.data.vertices:
            t = max(0.0, min(1.0, (vertex.co.z - 1.660) / 0.055))
            t = t * t * (3.0 - 2.0 * t)
            if t > 1e-6:
                head_group.add((vertex.index,), t, "REPLACE")
            if 1.0 - t > 1e-6:
                neck_group.add((vertex.index,), 1.0 - t, "REPLACE")
    else:
        head_group.add(tuple(vertex.index for vertex in obj.data.vertices), 1.0, "REPLACE")
    modifier = obj.modifiers.new("HeroRig", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj["professional_head_component"] = True
    obj["rig_binding"] = "HeroRig"


def adjust_transformed_skin_shader(material):
    if material is None or not material.use_nodes:
        return
    nodes = material.node_tree.nodes
    required = (
        "LipXScale", "LipZCenter", "LipZScale", "LipFrontLimit",
        "StubbleXFalloff", "StubbleYFalloff", "StubbleUpperFalloff", "StubbleLowerFalloff",
        "BrowCenterX", "BrowXScale", "BrowArch", "BrowZScale", "BrowFrontLimit",
        "ScalpYGradient", "ScalpBackDrop", "ScalpFrontZ", "ScalpSoftMask",
    )
    missing = [name for name in required if nodes.get(name) is None]
    if missing:
        raise RuntimeError(f"Head shader controls missing: {missing}")

    nodes["LipXScale"].inputs[1].default_value = map_x(0.033)
    nodes["LipZCenter"].inputs[1].default_value = map_z(SOURCE_LIP_Z)
    nodes["LipZScale"].inputs[1].default_value = 0.0120 * LOWER_Z_SCALE
    nodes["LipFrontLimit"].inputs[1].default_value = map_y(-0.140, SOURCE_LIP_Z)

    x_falloff = nodes["StubbleXFalloff"]
    x_falloff.inputs["From Min"].default_value = map_x(0.056)
    x_falloff.inputs["From Max"].default_value = map_x(0.086)
    y_falloff = nodes["StubbleYFalloff"]
    y_falloff.inputs["From Min"].default_value = map_y(-0.020, SOURCE_LIP_Z)
    y_falloff.inputs["From Max"].default_value = map_y(0.055, SOURCE_LIP_Z)
    upper = nodes["StubbleUpperFalloff"]
    upper.inputs["From Min"].default_value = map_z(1.690)
    upper.inputs["From Max"].default_value = map_z(1.725)
    lower = nodes["StubbleLowerFalloff"]
    lower.inputs["From Min"].default_value = map_z(1.565)
    lower.inputs["From Max"].default_value = map_z(1.610)

    nodes["BrowCenterX"].inputs[1].default_value = map_x(0.032)
    nodes["BrowXScale"].inputs[1].default_value = map_x(0.053) - map_x(0.032)
    brow_arch = nodes["BrowArch"]
    brow_arch.inputs[1].default_value = -0.0060 * UPPER_Z_SCALE
    brow_arch.inputs[2].default_value = map_z(SOURCE_BROW_Z)
    nodes["BrowZScale"].inputs[1].default_value = 0.00235 * UPPER_Z_SCALE
    nodes["BrowFrontLimit"].inputs[1].default_value = map_y(-0.075, SOURCE_BROW_Z)
    scalp_y = nodes["ScalpYGradient"]
    scalp_y.inputs["From Min"].default_value = map_y(-0.060, 1.795)
    scalp_y.inputs["From Max"].default_value = map_y(0.100, 1.795)
    nodes["ScalpBackDrop"].inputs[1].default_value = 0.070 * UPPER_Z_SCALE
    nodes["ScalpFrontZ"].inputs[0].default_value = map_z(1.795)
    scalp_mask = nodes["ScalpSoftMask"]
    scalp_mask.inputs["From Min"].default_value = -0.016 * UPPER_Z_SCALE
    scalp_mask.inputs["From Max"].default_value = 0.018 * UPPER_Z_SCALE
    material["coordinate_space"] = "BrokenKnight_master_rest_space"


def remove_old_head_objects():
    removed = []
    for name in sorted(OLD_HEAD_OBJECTS):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            removed.append(name)
            bpy.data.objects.remove(obj, do_unlink=True)
    return removed


def cut_old_connected_body():
    body = bpy.data.objects.get("ConnectedBody")
    if body is None or body.type != "MESH":
        raise RuntimeError("ConnectedBody mesh was not found")
    before = len(body.data.vertices)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    remove = [vertex for vertex in bm.verts if vertex.co.z > OLD_BODY_CUT_Z]
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    body["head_replacement"] = "ProfessionalHead"
    return before, len(body.data.vertices)


def hide_legacy_neck_surface(body):
    """Remove the inward-facing jagged legacy neck layer under the new bridge."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    remove = []
    for vertex in bm.verts:
        if not (1.555 < vertex.co.z < 1.605):
            continue
        radial = (vertex.co.x ** 2 + (vertex.co.y + 0.006) ** 2) ** 0.5
        if radial < 0.175:
            remove.append(vertex)
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def trim_legacy_body_hair_from_neck():
    hair = bpy.data.objects.get("BodyHair")
    if hair is None or hair.type != "MESH":
        return (0, 0)
    before = len(hair.data.vertices)
    bm = bmesh.new()
    bm.from_mesh(hair.data)
    remove = [vertex for vertex in bm.verts if vertex.co.z > 1.555]
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bm.to_mesh(hair.data)
    bm.free()
    hair.data.update()
    return before, len(hair.data.vertices)


def make_neck_transition_material(head_material):
    """Use the body shader at the base and the head micro-albedo at the jaw."""
    body_material = bpy.data.materials.get("Skin")
    if body_material is None:
        return head_material
    material = body_material.copy()
    material.name = "HeroSkin.ProfessionalNeckBlend"
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    base_input = bsdf.inputs.get("Base Color")
    if base_input is None or not base_input.is_linked:
        return material
    body_color_socket = base_input.links[0].from_socket
    links.remove(base_input.links[0])

    skin_texture = next(
        (node for node in head_material.node_tree.nodes if node.bl_idname == "ShaderNodeTexImage"), None,
    )
    if skin_texture is None or skin_texture.image is None:
        return material
    geometry = nodes.new("ShaderNodeNewGeometry")
    separate = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], separate.inputs["Vector"])
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "SCALE"
    scale.inputs["Scale"].default_value = 4.0
    links.new(geometry.outputs["Position"], scale.inputs["Vector"])
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = skin_texture.image
    texture.extension = "REPEAT"
    texture.projection = "BOX"
    texture.projection_blend = 0.28
    links.new(scale.outputs["Vector"], texture.inputs["Vector"])
    grade = nodes.new("ShaderNodeHueSaturation")
    grade.inputs["Saturation"].default_value = 1.12
    grade.inputs["Value"].default_value = 0.62
    links.new(texture.outputs["Color"], grade.inputs["Color"])
    gradient = nodes.new("ShaderNodeMapRange")
    gradient.clamp = True
    gradient.inputs["From Min"].default_value = 1.620
    gradient.inputs["From Max"].default_value = 1.705
    gradient.inputs["To Min"].default_value = 0.0
    gradient.inputs["To Max"].default_value = 1.0
    links.new(separate.outputs["Z"], gradient.inputs["Value"])
    mix = nodes.new("ShaderNodeMixRGB")
    links.new(gradient.outputs["Result"], mix.inputs[0])
    links.new(body_color_socket, mix.inputs[1])
    links.new(grade.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs["Color"], base_input)
    return material


def build_neck_transition(material, rig, collection):
    """Bridge torso to jaw with an adult tapered neck and muscular base."""
    from math import cos, pi, sin
    rings = (
        (1.550, 0.122, 0.091, -0.002),
        (1.562, 0.123, 0.087, -0.006),
        (1.574, 0.124, 0.082, -0.011),
        (1.586, 0.125, 0.077, -0.016),
        (1.597, 0.126, 0.072, -0.020),
        (1.606, 0.126, 0.069, -0.023),
    )
    segments = 64
    vertices = []
    for z, radius_x, radius_y, center_y in rings:
        for index in range(segments):
            angle = 2.0 * pi * index / segments
            # Slight front/back anatomical flattening avoids a pipe-like neck.
            x = radius_x * cos(angle)
            y = center_y + radius_y * sin(angle)
            frontness = max(0.0, -sin(angle))
            vertical = (z - rings[0][0]) / (rings[-1][0] - rings[0][0])
            muscle_x = 0.030 + 0.017 * vertical
            ridge = exp(-((abs(x) - muscle_x) / 0.016) ** 2)
            # Paired sternocleidomastoid planes and a mild central throat
            # recess stop the bridge reading as a featureless cone.
            y -= 0.0060 * frontness * ridge
            center_recess = exp(-((x / 0.020) ** 2))
            y += 0.0024 * frontness * center_recess * (0.35 + 0.65 * vertical)
            vertices.append((x, y, z))
    faces = []
    for ring in range(len(rings) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = ring * segments + index
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + index
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new("ProfessionalNeckTransition.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    neck = bpy.data.objects.new("ProfessionalNeckTransition", mesh)
    bpy.context.scene.collection.objects.link(neck)
    move_to_collection(neck, collection)
    # Share the head skin directly. The former separate neck material was
    # visibly paler and made the bridge read as a detached cone.
    neck.data.materials.append(material)
    for polygon in neck.data.polygons:
        polygon.use_smooth = True
    subdivision = neck.modifiers.new("AnatomicalNeckSmoothing", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 2
    subdivision.render_levels = 2
    clear_deform_data(neck)
    neck_group = neck.vertex_groups.new(name="neck")
    neck_group.add(tuple(vertex.index for vertex in neck.data.vertices), 1.0, "REPLACE")
    modifier = neck.modifiers.new("HeroRig", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    neck["rig_binding"] = "HeroRig.neck"
    neck["professional_head_component"] = True
    neck["purpose"] = "sealed anatomical overlap bridge"
    return neck


def make_collection():
    old = bpy.data.collections.get("Hero_Head_Professional")
    if old is not None:
        bpy.data.collections.remove(old)
    collection = bpy.data.collections.new("Hero_Head_Professional")
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)


def build_integrated_head():
    rig = bpy.data.objects.get("HeroRig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("HeroRig armature was not found")
    action_names_before = sorted(action.name for action in bpy.data.actions)
    appended = append_head_sources()
    collection = make_collection()

    human_source = appended["HeroProfessionalTopology"]
    head = evaluated_mesh(human_source, "ProfessionalHead")
    crop_source_head(head)
    transform_mesh(head)
    extend_continuous_neck(head)
    sculpt_integrated_masculine_planes(head)
    bpy.context.scene.collection.objects.link(head)
    move_to_collection(head, collection)
    bind_head_mesh(head, rig, blended_neck=True)
    head["source"] = "custom-shaped MPFB professional topology"
    head["integration_state"] = "WIP_reviewed_not_canonical"
    adjust_transformed_skin_shader(head.active_material)

    component_map = {
        "Eyes.ProfessionalWIP": "ProfessionalEyes",
        "Iris.L": "ProfessionalIris.L",
        "Iris.R": "ProfessionalIris.R",
        "Pupil.L": "ProfessionalPupil.L",
        "Pupil.R": "ProfessionalPupil.R",
        "Brows.RootedGroom": "ProfessionalBrows",
        "Face.RootedStubble": "ProfessionalFaceStubble",
        "Hair.ShortGroom": "ProfessionalHairStrands",
        "Hair.DirectionalClumps": "ProfessionalHairClumps",
    }
    components = []
    for source_name, output_name in component_map.items():
        source = appended[source_name]
        component = evaluated_mesh(source, output_name)
        transform_mesh(component)
        bpy.context.scene.collection.objects.link(component)
        move_to_collection(component, collection)
        bind_head_mesh(component, rig, blended_neck=False)
        components.append(component)

    for source in appended.values():
        if source.name in bpy.data.objects:
            bpy.data.objects.remove(source, do_unlink=True)

    removed = remove_old_head_objects()
    body_counts = cut_old_connected_body()
    hide_legacy_neck_surface(bpy.data.objects["ConnectedBody"])
    body_hair_counts = trim_legacy_body_hair_from_neck()
    action_names_after = sorted(action.name for action in bpy.data.actions)
    if action_names_after != action_names_before:
        raise RuntimeError("Animation actions changed during head integration")

    new_bottom = min(vertex.co.z for vertex in head.data.vertices)
    bridge_bottom = min(vertex.co.z for vertex in head.data.vertices)
    new_top = max(vertex.co.z for vertex in head.data.vertices)
    if bridge_bottom >= OLD_BODY_CUT_Z:
        raise RuntimeError("Neck overlap was lost; integration would expose a seam")
    if new_top < 1.865:
        raise RuntimeError("Integrated skull is unexpectedly short")
    print(f"HEAD_INTEGRATION|head_vertices={len(head.data.vertices)}|components={len(components)}")
    print(f"HEAD_INTEGRATION|old_body_vertices={body_counts[0]}->{body_counts[1]}")
    print(f"HEAD_INTEGRATION|body_hair_vertices={body_hair_counts[0]}->{body_hair_counts[1]}")
    print(f"HEAD_INTEGRATION|neck_overlap={OLD_BODY_CUT_Z-bridge_bottom:.5f}|head_top={new_top:.5f}")
    print(f"HEAD_INTEGRATION|removed_old={','.join(removed)}")
    print(f"HEAD_INTEGRATION|actions_preserved={len(action_names_after)}")
    return head, components, rig


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_reviews(head, components, rig):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    original_pose_position = rig.data.pose_position
    rig.data.pose_position = "REST"
    original_visibility = {obj.name: obj.hide_render for obj in scene.objects}
    allowed = {"ConnectedBody", "BodyHair", head.name, *(obj.name for obj in components)}
    for obj in scene.objects:
        if obj.type in {"MESH", "CURVE"}:
            keep = obj.name in allowed or obj.name.startswith(("Loin", "Fingernail", "Thumbnail", "Toenail"))
            obj.hide_render = not keep

    review_objects = []
    camera_data = bpy.data.cameras.new("HeadIntegrationReviewCamera")
    camera = bpy.data.objects.new("HeadIntegrationReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    review_objects.append(camera)
    scene.camera = camera
    target = (0.0, 0.015, 1.76)
    for name, location, energy, size, color in (
        ("HeadReviewKey", (-0.58, -0.68, 2.20), 58.0, 0.58, (1.0, 0.82, 0.72)),
        ("HeadReviewFill", (0.66, -0.42, 1.98), 28.0, 0.72, (0.72, 0.84, 1.0)),
        ("HeadReviewRim", (0.26, 0.52, 2.12), 42.0, 0.52, (0.84, 0.92, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        aim(light, target)
        scene.collection.objects.link(light)
        review_objects.append(light)

    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.020, 0.025, 0.034)
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.35
    scene.render.resolution_x = 720
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    for name, location, target, lens in (
        ("head_front", (0.0, -1.22, 1.77), (0.0, 0.010, 1.76), 92),
        ("head_threequarter", (0.72, -0.94, 1.78), (0.0, 0.018, 1.76), 94),
        ("head_profile", (1.22, 0.018, 1.77), (0.0, 0.025, 1.755), 96),
    ):
        camera.location = location
        camera.data.lens = lens
        aim(camera, target)
        scene.render.filepath = os.path.join(OUTPUT_DIR, name + ".png")
        bpy.ops.render.render(write_still=True)
        print(f"HEAD_INTEGRATION_RENDER|{name}|{scene.render.filepath}")

    if os.environ.get("BK_HEAD_FAST_REVIEW") != "1":
        scene.render.resolution_x = 720
        scene.render.resolution_y = 900
        for name, location, target, lens in (
            ("full_front", (0.0, -5.0, 1.02), (0.0, 0.0, 0.98), 72),
            ("full_threequarter", (2.65, -4.15, 1.10), (0.0, 0.0, 0.98), 74),
        ):
            camera.location = location
            camera.data.lens = lens
            aim(camera, target)
            scene.render.filepath = os.path.join(OUTPUT_DIR, name + ".png")
            bpy.ops.render.render(write_still=True)
            print(f"HEAD_INTEGRATION_RENDER|{name}|{scene.render.filepath}")

    for obj in review_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    for name, visible in original_visibility.items():
        obj = bpy.data.objects.get(name)
        if obj is not None:
            obj.hide_render = visible
    rig.data.pose_position = original_pose_position


def main():
    expected = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master.blend")
    allowed_input = os.path.abspath(os.environ.get("BK_HEAD_INTEGRATION_INPUT", expected))
    if os.path.normcase(os.path.abspath(bpy.data.filepath)) != os.path.normcase(allowed_input):
        raise RuntimeError(f"Run against approved master input only; got {bpy.data.filepath}")
    head, components, rig = build_integrated_head()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    render_reviews(head, components, rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"HEAD_INTEGRATION_WIP_DONE|{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
