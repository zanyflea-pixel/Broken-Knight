"""Build, rig, animate, preview, and export the Broken Knight cave dragon."""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "blender", "cave_dragon.blend")
GLB_OUT = os.path.join(ROOT, "godot", "assets", "enemies", "cave_dragon.glb")
PREVIEW_OUT = os.path.join(ROOT, "blender", "previews", "cave_dragon_preview.png")
TEXTURE_DIR = os.path.join(ROOT, "godot", "assets", "enemies", "textures")


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=.72, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = .28
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = 5.0
    return mat


def textured_scale_material():
    mat = material("Dragon Obsidian Scales", (.075, .010, .008, 1), .66)
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")

    color_image = bpy.data.images.load(
        os.path.join(TEXTURE_DIR, "cave_dragon_scales_v1.png"),
        check_existing=True,
    )
    normal_image = bpy.data.images.load(
        os.path.join(TEXTURE_DIR, "cave_dragon_scales_normal_v1.png"),
        check_existing=True,
    )
    roughness_image = bpy.data.images.load(
        os.path.join(TEXTURE_DIR, "cave_dragon_scales_roughness_v1.png"),
        check_existing=True,
    )
    normal_image.colorspace_settings.name = "Non-Color"
    roughness_image.colorspace_settings.name = "Non-Color"

    color = tree.nodes.new("ShaderNodeTexImage")
    color.name = "DragonScaleBaseColor"
    color.image = color_image
    color.extension = "REPEAT"
    tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])

    normal_texture = tree.nodes.new("ShaderNodeTexImage")
    normal_texture.name = "DragonScaleNormal"
    normal_texture.image = normal_image
    normal_texture.extension = "REPEAT"
    normal_map = tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = .72
    tree.links.new(normal_texture.outputs["Color"], normal_map.inputs["Color"])
    tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

    roughness = tree.nodes.new("ShaderNodeTexImage")
    roughness.name = "DragonScaleRoughness"
    roughness.image = roughness_image
    roughness.extension = "REPEAT"
    tree.links.new(roughness.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def build_armature():
    data = bpy.data.armatures.new("DragonRig")
    arm = bpy.data.objects.new("DragonRig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specs = {
        "root": ((0, 0, .05), (0, 0, 1.0), None),
        "pelvis": ((0, -1.1, 2.25), (0, -.15, 3.05), "root"),
        "spine": ((0, -.15, 3.05), (0, .85, 3.75), "pelvis"),
        "chest": ((0, .85, 3.75), (0, 1.85, 4.35), "spine"),
        "neck.1": ((0, 1.85, 4.35), (0, 2.85, 5.05), "chest"),
        "neck.2": ((0, 2.85, 5.05), (0, 3.75, 5.55), "neck.1"),
        "head": ((0, 3.75, 5.55), (0, 5.55, 5.65), "neck.2"),
        "jaw": ((0, 4.75, 5.35), (0, 6.25, 5.20), "head"),
        "tail.1": ((0, -1.15, 2.45), (0, -2.55, 2.10), "pelvis"),
        "tail.2": ((0, -2.55, 2.10), (0, -4.05, 1.70), "tail.1"),
        "tail.3": ((0, -4.05, 1.70), (0, -5.55, 1.35), "tail.2"),
        "tail.4": ((0, -5.55, 1.35), (0, -7.00, 1.05), "tail.3"),
        "tail.5": ((0, -7.00, 1.05), (0, -8.25, .82), "tail.4"),
        "tail.6": ((0, -8.25, .82), (0, -9.35, .65), "tail.5"),
        "thigh.L": ((-1.10, -.78, 2.75), (-2.00, -.25, 1.55), "pelvis"),
        "shin.L": ((-2.00, -.25, 1.55), (-1.70, .52, .48), "thigh.L"),
        "foot.L": ((-1.70, .52, .48), (-1.65, 2.45, .18), "shin.L"),
        "thigh.R": ((1.10, -.78, 2.75), (2.00, -.25, 1.55), "pelvis"),
        "shin.R": ((2.00, -.25, 1.55), (1.70, .52, .48), "thigh.R"),
        "foot.R": ((1.70, .52, .48), (1.65, 2.45, .18), "shin.R"),
        "upper_arm.L": ((-.95, 1.25, 3.82), (-1.65, 1.62, 2.35), "chest"),
        "forearm.L": ((-1.65, 1.62, 2.35), (-1.40, 2.55, .48), "upper_arm.L"),
        "hand.L": ((-1.40, 2.55, .48), (-1.35, 3.85, .16), "forearm.L"),
        "upper_arm.R": ((.95, 1.25, 3.82), (1.65, 1.62, 2.35), "chest"),
        "forearm.R": ((1.65, 1.62, 2.35), (1.40, 2.55, .48), "upper_arm.R"),
        "hand.R": ((1.40, 2.55, .48), (1.35, 3.85, .16), "forearm.R"),
        "wing_upper.L": ((-.85, 1.15, 4.45), (-3.35, 1.10, 6.75), "chest"),
        "wing_fore.L": ((-3.35, 1.10, 6.75), (-5.75, .10, 6.05), "wing_upper.L"),
        "wing_hand.L": ((-5.75, .10, 6.05), (-7.25, -1.10, 4.05), "wing_fore.L"),
        "wing_upper.R": ((.85, 1.15, 4.45), (3.35, 1.10, 6.75), "chest"),
        "wing_fore.R": ((3.35, 1.10, 6.75), (5.75, .10, 6.05), "wing_upper.R"),
        "wing_hand.R": ((5.75, .10, 6.05), (7.25, -1.10, 4.05), "wing_fore.R"),
    }
    for name, (head, tail, parent) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="POSE")
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.select_set(False)
    return arm


def mesh_object(name, vertices, faces, vertex_weights, mat, arm, uvs=None, smooth=True, thickness=0.0):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    if uvs:
        layer = obj.data.uv_layers.new(name="DragonUV")
        for loop_index, loop in enumerate(obj.data.loops):
            layer.data[loop_index].uv = uvs[loop.vertex_index]
    groups = {}
    for weights in vertex_weights:
        for bone_name in weights:
            if bone_name not in groups:
                groups[bone_name] = obj.vertex_groups.new(name=bone_name)
    for index, weights in enumerate(vertex_weights):
        total = sum(weights.values()) or 1.0
        for bone_name, weight in weights.items():
            groups[bone_name].add([index], weight / total, "REPLACE")
    modifier = obj.modifiers.new("DragonArmature", "ARMATURE")
    modifier.object = arm
    obj.parent = arm
    if thickness:
        solid = obj.modifiers.new("OrganicThickness", "SOLIDIFY")
        solid.thickness = thickness
        solid.offset = 0.0
    return obj


def loft_object(name, rings, mat, arm, segments=20, uv_repeat=(2.0, 6.0), exponent=2.0):
    """Create a continuous organic shell from X/Z cross-sections along Y."""
    vertices = []
    uvs = []
    weights = []
    for ring_index, ring in enumerate(rings):
        y, z, radius_x, radius_z, bone_name = ring
        next_bone = rings[min(ring_index + 1, len(rings) - 1)][4]
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = radius_x * math.copysign(abs(cosine) ** (2.0 / exponent), cosine)
            ring_z = z + radius_z * math.copysign(abs(sine) ** (2.0 / exponent), sine)
            vertices.append((x, y, ring_z))
            uvs.append((segment / segments * uv_repeat[0], ring_index / max(1, len(rings) - 1) * uv_repeat[1]))
            if next_bone != bone_name and ring_index < len(rings) - 1:
                weights.append({bone_name: .72, next_bone: .28})
            else:
                weights.append({bone_name: 1.0})
    faces = []
    for ring_index in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring_index * segments + segment
            b = ring_index * segments + nxt
            c = (ring_index + 1) * segments + nxt
            d = (ring_index + 1) * segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(range(segments - 1, -1, -1)))
    final = (len(rings) - 1) * segments
    faces.append(tuple(final + index for index in range(segments)))
    return mesh_object(name, vertices, faces, weights, mat, arm, uvs, True)


def tube_object(name, points, radii, bones, mat, arm, segments=14, uv_repeat=(1.0, 2.0)):
    vertices = []
    uvs = []
    weights = []
    for point_index, point in enumerate(points):
        center = Vector(point)
        previous = Vector(points[max(0, point_index - 1)])
        following = Vector(points[min(len(points) - 1, point_index + 1)])
        tangent = (following - previous).normalized()
        reference = Vector((0, 0, 1)) if abs(tangent.z) < .86 else Vector((0, 1, 0))
        normal_a = tangent.cross(reference).normalized()
        normal_b = tangent.cross(normal_a).normalized()
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            position = center + normal_a * math.cos(angle) * radii[point_index] + normal_b * math.sin(angle) * radii[point_index]
            vertices.append(tuple(position))
            uvs.append((segment / segments * uv_repeat[0], point_index / max(1, len(points) - 1) * uv_repeat[1]))
            weights.append({bones[point_index]: 1.0})
    faces = []
    for point_index in range(len(points) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = point_index * segments + segment
            b = point_index * segments + nxt
            c = (point_index + 1) * segments + nxt
            d = (point_index + 1) * segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(range(segments - 1, -1, -1)))
    final = (len(points) - 1) * segments
    faces.append(tuple(final + index for index in range(segments)))
    return mesh_object(name, vertices, faces, weights, mat, arm, uvs, True)


def append_tube(vertices, faces, weights, points, radii, bone_name, segments=10):
    base = len(vertices)
    for point_index, point in enumerate(points):
        center = Vector(point)
        previous = Vector(points[max(0, point_index - 1)])
        following = Vector(points[min(len(points) - 1, point_index + 1)])
        tangent = (following - previous).normalized()
        reference = Vector((0, 0, 1)) if abs(tangent.z) < .86 else Vector((0, 1, 0))
        normal_a = tangent.cross(reference).normalized()
        normal_b = tangent.cross(normal_a).normalized()
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            pos = center + normal_a * math.cos(angle) * radii[point_index] + normal_b * math.sin(angle) * radii[point_index]
            vertices.append(tuple(pos))
            weights.append({bone_name: 1.0})
    for point_index in range(len(points) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = base + point_index * segments + segment
            b = base + point_index * segments + nxt
            c = base + (point_index + 1) * segments + nxt
            d = base + (point_index + 1) * segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(base + index for index in range(segments - 1, -1, -1)))
    final = base + (len(points) - 1) * segments
    faces.append(tuple(final + index for index in range(segments)))


def ellipsoid(name, location, scale, mat, arm, bone, segments=28, rings=18):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("DragonArmature", "ARMATURE")
    modifier.object = arm
    obj.parent = arm
    obj.select_set(False)
    return obj


def build_dragon(arm):
    scales = textured_scale_material()
    belly = material("Dragon Ventral Scutes", (.18, .035, .012, 1), .79)
    horn = material("Dragon Horn and Claw", (.34, .24, .13, 1), .58)
    horn_tip = material("Dragon Horn Tips", (.055, .035, .025, 1), .50)
    wing = material("Dragon Wing Membrane", (.16, .012, .018, 1), .88)
    mouth = material("Dragon Mouth", (.075, .002, .006, 1), .92)
    gum = material("Dragon Gums", (.20, .008, .012, 1), .76)
    tongue = material("Dragon Tongue", (.24, .010, .018, 1), .68)
    plate_scale = material("Dragon Raised Armor Scales", (.070, .009, .008, 1), .66)
    wing_vein = material("Dragon Wing Veins", (.065, .006, .010, 1), .84)
    eye = material("Dragon Ember Eyes", (.28, .055, .003, 1), .42, emission=(.62, .065, .002, 1))
    eye.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.25
    pupil = material("Dragon Eye Slits", (.005, .001, .001, 1), .42)

    body_rings = [
        (-9.35, .67, .055, .055, "tail.6"),
        (-8.25, .84, .16, .14, "tail.5"),
        (-7.00, 1.04, .30, .24, "tail.4"),
        (-5.55, 1.35, .52, .38, "tail.3"),
        (-4.05, 1.70, .76, .54, "tail.2"),
        (-2.55, 2.12, 1.02, .72, "tail.1"),
        (-1.30, 2.62, 1.55, 1.15, "pelvis"),
        (-.35, 3.02, 1.72, 1.42, "pelvis"),
        (.55, 3.45, 1.82, 1.55, "spine"),
        (1.40, 3.95, 1.72, 1.38, "chest"),
        (2.15, 4.47, 1.24, 1.03, "neck.1"),
        (2.85, 5.03, .98, .84, "neck.1"),
        (3.55, 5.46, .78, .68, "neck.2"),
        (4.05, 5.62, .72, .62, "neck.2"),
    ]
    loft_object("DragonBody", body_rings, scales, arm, 26, (3.0, 11.0), 2.25)

    head_rings = [
        (3.75, 5.62, .73, .64, "neck.2"),
        (4.25, 5.83, .92, .74, "head"),
        (4.80, 5.93, 1.06, .76, "head"),
        (5.35, 5.83, .92, .62, "head"),
        (5.92, 5.62, .70, .43, "head"),
        (6.45, 5.53, .47, .30, "head"),
        (6.72, 5.50, .24, .20, "head"),
    ]
    loft_object("DragonSkull", head_rings, scales, arm, 24, (2.0, 3.0), 2.45)

    jaw_rings = [
        (4.85, 5.30, .78, .29, "jaw"),
        (5.55, 5.20, .80, .27, "jaw"),
        (6.18, 5.19, .56, .21, "jaw"),
        (6.72, 5.24, .30, .12, "jaw"),
    ]
    loft_object("DragonJaw", jaw_rings, scales, arm, 20, (1.0, 1.5), 2.3)

    # Muscular continuous limbs, each authored as one organic tube.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        sx = float(side)
        tube_object(
            f"DragonForeleg{suffix}",
            [
                (sx*.92, 1.15, 3.90),
                (sx*1.30, 1.38, 3.25),
                (sx*1.68, 1.65, 2.35),
                (sx*1.56, 2.02, 1.48),
                (sx*1.40, 2.55, .52),
                (sx*1.38, 3.20, .28),
                (sx*1.36, 3.92, .18),
            ],
            [.70, .62, .48, .40, .28, .34, .16],
            [
                f"upper_arm.{suffix}", f"upper_arm.{suffix}", f"forearm.{suffix}",
                f"forearm.{suffix}", f"forearm.{suffix}", f"hand.{suffix}", f"hand.{suffix}",
            ],
            scales, arm, 18, (1.6, 4.0),
        )
        tube_object(
            f"DragonHindleg{suffix}",
            [
                (sx*1.02, -.85, 2.82),
                (sx*1.58, -.62, 2.35),
                (sx*2.05, -.22, 1.55),
                (sx*1.90, .15, .95),
                (sx*1.70, .55, .48),
                (sx*1.68, 1.50, .25),
                (sx*1.66, 2.70, .16),
            ],
            [.92, .88, .68, .52, .36, .50, .19],
            [
                f"thigh.{suffix}", f"thigh.{suffix}", f"shin.{suffix}",
                f"shin.{suffix}", f"shin.{suffix}", f"foot.{suffix}", f"foot.{suffix}",
            ],
            scales, arm, 20, (1.7, 4.0),
        )

    # Wing membranes use a scalloped trailing edge and are skinned across three bones.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        s = float(side)
        wing_points = [
            (s*.82, 1.15, 4.45),
            (s*3.35, 1.10, 6.75),
            (s*5.75, .10, 6.05),
            (s*7.25, -1.10, 4.05),
            (s*6.15, -1.80, 3.05),
            (s*5.05, -1.50, 3.55),
            (s*4.15, -2.35, 2.45),
            (s*3.10, -1.80, 3.05),
            (s*2.10, -2.15, 2.65),
            (s*1.15, -1.05, 3.55),
        ]
        wing_weights = [
            {f"wing_upper.{suffix}": 1}, {f"wing_upper.{suffix}": 1},
            {f"wing_fore.{suffix}": 1}, {f"wing_hand.{suffix}": 1},
            {f"wing_hand.{suffix}": 1}, {f"wing_fore.{suffix}": 1},
            {f"wing_fore.{suffix}": 1}, {f"wing_upper.{suffix}": 1},
            {f"wing_upper.{suffix}": 1}, {"chest": 1},
        ]
        wing_faces = [
            (0, 1, 9), (1, 8, 9), (1, 2, 8), (2, 7, 8),
            (2, 6, 7), (2, 3, 6), (3, 4, 5, 6),
        ]
        wing_uvs = [(abs(point[0]) / 7.5, (point[2] - 2.2) / 4.8) for point in wing_points]
        mesh_object(
            f"DragonWingMembrane{suffix}", wing_points, wing_faces,
            wing_weights, wing, arm, wing_uvs, True, .035,
        )

        spar_vertices, spar_faces, spar_weights = [], [], []
        append_tube(spar_vertices, spar_faces, spar_weights, [wing_points[0], wing_points[1]], [.18, .13], f"wing_upper.{suffix}", 12)
        append_tube(spar_vertices, spar_faces, spar_weights, [wing_points[1], wing_points[2]], [.14, .09], f"wing_fore.{suffix}", 12)
        append_tube(spar_vertices, spar_faces, spar_weights, [wing_points[2], wing_points[3]], [.10, .025], f"wing_hand.{suffix}", 10)
        for index, trailing in enumerate((wing_points[4], wing_points[6], wing_points[8])):
            bone = f"wing_hand.{suffix}" if index == 0 else (f"wing_fore.{suffix}" if index == 1 else f"wing_upper.{suffix}")
            append_tube(spar_vertices, spar_faces, spar_weights, [wing_points[1], trailing], [.075, .018], bone, 9)
        mesh_object(f"DragonWingSpars{suffix}", spar_vertices, spar_faces, spar_weights, horn_tip, arm, smooth=True)

        # Secondary branching veins sit directly on the membrane and keep the
        # broad wing from reading as a single flat polygon.
        vein_vertices, vein_faces, vein_weights = [], [], []
        vein_paths = (
            ([wing_points[0], (s*2.20, -.65, 3.72), wing_points[8]], f"wing_upper.{suffix}"),
            ([wing_points[1], (s*3.62, -.48, 4.48), wing_points[7]], f"wing_fore.{suffix}"),
            ([wing_points[2], (s*4.92, -.72, 4.56), wing_points[5]], f"wing_fore.{suffix}"),
            ([wing_points[2], (s*5.62, -1.18, 3.82), wing_points[4]], f"wing_hand.{suffix}"),
        )
        for path, bone in vein_paths:
            append_tube(
                vein_vertices, vein_faces, vein_weights,
                path, [.030, .020, .008], bone, 8,
            )
        mesh_object(
            f"DragonWingVeins{suffix}", vein_vertices, vein_faces,
            vein_weights, wing_vein, arm, smooth=True,
        )

    # Horns, facial spikes, dorsal spines, claws and teeth are consolidated.
    detail_vertices, detail_faces, detail_weights = [], [], []
    for side in (-1, 1):
        s = float(side)
        append_tube(
            detail_vertices, detail_faces, detail_weights,
            [
                (s*.56, 4.45, 6.30),
                (s*.92, 4.04, 6.78),
                (s*1.28, 3.60, 7.02),
                (s*1.64, 3.15, 6.98),
                (s*1.98, 2.72, 6.72),
            ],
            [.25, .20, .13, .065, .012], "head", 14,
        )
        append_tube(
            detail_vertices, detail_faces, detail_weights,
            [(s*.72, 5.48, 6.05), (s*1.26, 5.05, 6.30), (s*1.84, 4.57, 6.14)],
            [.19, .105, .012], "head", 12,
        )
        # Four claws per foot on fore and hind legs.
        for claw in range(4):
            offset = (claw - 1.5) * .18
            append_tube(
                detail_vertices, detail_faces, detail_weights,
                [(s*(1.36+offset), 3.68, .20), (s*(1.37+offset*1.08), 4.10, .12), (s*(1.38+offset*1.12), 4.48, .055)],
                [.090, .052, .006], f"hand.{'L' if side < 0 else 'R'}", 10,
            )
            append_tube(
                detail_vertices, detail_faces, detail_weights,
                [(s*(1.66+offset), 2.40, .18), (s*(1.67+offset*1.08), 2.88, .10), (s*(1.68+offset*1.12), 3.30, .045)],
                [.102, .058, .007], f"foot.{'L' if side < 0 else 'R'}", 10,
            )
        # Rear dewclaws add a predatory hooked silhouette at each ankle.
        append_tube(
            detail_vertices, detail_faces, detail_weights,
            [(s*1.64, 1.02, .42), (s*1.92, .80, .31), (s*2.06, .62, .22)],
            [.10, .055, .006], f"shin.{'L' if side < 0 else 'R'}", 10,
        )

    spine_specs = [
        (-4.4, 2.18, .28, "tail.2"), (-3.2, 2.55, .42, "tail.1"),
        (-2.0, 3.05, .62, "tail.1"), (-.9, 3.72, .82, "pelvis"),
        (.1, 4.35, 1.00, "spine"), (.9, 4.85, 1.08, "chest"),
        (1.7, 5.20, .94, "chest"), (2.4, 5.62, .78, "neck.1"),
        (3.05, 5.98, .62, "neck.2"), (3.65, 6.18, .48, "neck.2"),
    ]
    for y, z, height, bone in spine_specs:
        append_tube(
            detail_vertices, detail_faces, detail_weights,
            [(0, y, z-.05), (0, y-.06, z+height)],
            [.19, .008], bone, 8,
        )
    # A short crown and nose spike sharpen the frontal silhouette.
    for y, base_z, height in ((4.25, 6.34, .66), (4.82, 6.48, .52), (5.32, 6.38, .36)):
        append_tube(
            detail_vertices, detail_faces, detail_weights,
            [(0, y, base_z), (0, y-.05, base_z+height)],
            [.15, .007], "head", 9,
        )
    append_tube(
        detail_vertices, detail_faces, detail_weights,
        [(0, 6.18, 5.84), (0, 6.56, 6.08), (0, 6.82, 6.27)],
        [.105, .055, .006], "head", 10,
    )
    # Interlocking upper and lower fangs follow the tapered jaw rather than
    # forming a straight picket fence.
    for side in (-1, 1):
        for index in range(6):
            y = 5.28 + index*.245
            width = .70 - index*.075
            append_tube(
                detail_vertices, detail_faces, detail_weights,
                [(side*width, y, 5.36), (side*(width-.018), y+.035, 5.04)],
                [.060 if index not in (0,5) else .075, .005], "head", 9,
            )
            append_tube(
                detail_vertices, detail_faces, detail_weights,
                [(side*(width-.055), y+.075, 5.18), (side*(width-.045), y+.095, 5.40)],
                [.048, .005], "jaw", 9,
            )
    mesh_object("DragonHornsClawsSpines", detail_vertices, detail_faces, detail_weights, horn_tip, arm, smooth=True)

    # Heavy swept brow ridges shade the forward-set eyes.
    ridge_vertices, ridge_faces, ridge_weights = [], [], []
    for side in (-1, 1):
        s = float(side)
        append_tube(
            ridge_vertices, ridge_faces, ridge_weights,
            [
                (s*.16, 5.82, 6.18),
                (s*.42, 5.99, 6.13),
                (s*.66, 5.96, 6.04),
                (s*.82, 5.76, 5.94),
            ],
            [.125, .115, .070, .018], "head", 12,
        )
    ridge_material = material("Dragon Cranial Ridges", (.065, .006, .006, 1), .74)
    mesh_object("DragonCranialRidges", ridge_vertices, ridge_faces, ridge_weights, ridge_material, arm, smooth=True)

    # Recessed side seams define the closed jaws without creating a pasted-on lip.
    mouth_vertices, mouth_faces, mouth_weights = [], [], []
    for side in (-1, 1):
        s = float(side)
        append_tube(
            mouth_vertices, mouth_faces, mouth_weights,
            [
                (s*.74, 4.98, 5.38),
                (s*.82, 5.34, 5.34),
                (s*.75, 5.78, 5.31),
                (s*.58, 6.18, 5.31),
                (s*.28, 6.60, 5.34),
            ],
            [.012, .015, .014, .012, .008], "jaw", 8,
        )
    seam_base = len(mouth_vertices)
    mouth_vertices.extend([
        (-.28, 6.625, 5.355), (.28, 6.625, 5.355),
        (.25, 6.642, 5.330), (-.25, 6.642, 5.330),
    ])
    mouth_faces.append((seam_base, seam_base+1, seam_base+2, seam_base+3))
    mouth_weights.extend([{"jaw": 1.0}] * 4)
    mesh_object("DragonMouthSeam", mouth_vertices, mouth_faces, mouth_weights, mouth, arm, smooth=True)

    # Ventral armor plates are one close-set mesh following the underside.
    plate_vertices, plate_faces, plate_weights = [], [], []
    for index in range(12):
        y = -1.10 + index * .38
        z = 1.47 + index * .31
        width = 1.18 - abs(index - 5.5) * .035
        depth = .34
        base = len(plate_vertices)
        bone = "pelvis" if index < 3 else ("spine" if index < 7 else ("chest" if index < 10 else "neck.1"))
        plate_vertices.extend([
            (-width, y-depth*.42, z), (width, y-depth*.42, z),
            (width*.88, y+depth*.58, z-.08), (0, y+depth*.72, z-.15),
            (-width*.88, y+depth*.58, z-.08),
        ])
        plate_faces.extend([(base, base+1, base+2, base+3, base+4)])
        plate_weights.extend([{bone: 1.0}] * 5)
    mesh_object("DragonVentralScutes", plate_vertices, plate_faces, plate_weights, belly, arm, smooth=True, thickness=.045)

    # Raised shoulder and flank scales provide real silhouette breakup above
    # the PBR micro-scale texture. They are consolidated into one skinned mesh.
    armor_vertices, armor_faces, armor_weights = [], [], []
    armor_rows = (
        (-1.35, 2.62, 1.48, 1.08, "pelvis"),
        (-.68, 2.92, 1.64, 1.28, "pelvis"),
        (.02, 3.26, 1.76, 1.46, "spine"),
        (.72, 3.60, 1.74, 1.42, "spine"),
        (1.42, 3.98, 1.62, 1.28, "chest"),
        (2.08, 4.45, 1.18, .98, "neck.1"),
        (2.72, 4.96, .90, .76, "neck.1"),
        (3.34, 5.40, .72, .64, "neck.2"),
    )
    for y, center_z, radius_x, radius_z, bone in armor_rows:
        for side in (-1, 1):
            for vertical in (-.34, 0.0, .34):
                dz = vertical * radius_z
                surface_x = radius_x * math.sqrt(max(.08, 1.0-(dz/radius_z)**2))
                x = side*(surface_x+.020)
                center_index = len(armor_vertices)
                armor_vertices.extend([
                    (x, y-.22, center_z+dz),
                    (x, y, center_z+dz+.16),
                    (x, y+.22, center_z+dz),
                    (x, y, center_z+dz-.16),
                    (side*(surface_x+.036), y, center_z+dz),
                ])
                armor_faces.extend([
                    (center_index, center_index+1, center_index+4),
                    (center_index+1, center_index+2, center_index+4),
                    (center_index+2, center_index+3, center_index+4),
                    (center_index+3, center_index, center_index+4),
                ])
                armor_weights.extend([{bone: 1.0}] * 5)
    mesh_object(
        "DragonRaisedArmorScales", armor_vertices, armor_faces,
        armor_weights, plate_scale, arm, smooth=True, thickness=.008,
    )

    # A thick tongue and gum rails make the roar/fire-breath mouth read as an
    # anatomical cavity instead of an empty opening between two shells.
    ellipsoid(
        "DragonTongue", (0, 5.76, 5.125), (.27, .78, .060),
        tongue, arm, "jaw", 30, 16,
    )
    gum_vertices, gum_faces, gum_weights = [], [], []
    for side in (-1, 1):
        s = float(side)
        append_tube(
            gum_vertices, gum_faces, gum_weights,
            [(s*.68, 5.16, 5.22), (s*.66, 5.70, 5.18), (s*.50, 6.20, 5.20), (s*.24, 6.60, 5.24)],
            [.038, .034, .026, .010], "jaw", 9,
        )
    mesh_object("DragonGumRails", gum_vertices, gum_faces, gum_weights, gum, arm, smooth=True)

    # Forward-lateral eyes read clearly from the combat camera while remaining recessed.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        ellipsoid(f"DragonEye{suffix}", (side*.53, 6.015, 5.94), (.112, .033, .076), eye, arm, "head", 24, 14)
        ellipsoid(f"DragonPupil{suffix}", (side*.53, 6.046, 5.94), (.018, .009, .060), pupil, arm, "head", 18, 12)
        ellipsoid(f"DragonNostril{suffix}", (side*.18, 6.62, 5.62), (.050, .030, .025), mouth, arm, "head", 18, 10)


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def key_pose(arm, frame, transforms):
    reset_pose(arm)
    for name, values in transforms.items():
        bone = arm.pose.bones[name]
        if "rot" in values:
            bone.rotation_euler = tuple(math.radians(value) for value in values["rot"])
        if "loc" in values:
            bone.location = values["loc"]
        if "scale" in values:
            bone.scale = values["scale"]
    for bone in arm.pose.bones:
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


def action(arm, name, keys, end_frame):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    act.frame_start = 1
    act.frame_end = end_frame
    return act


def make_animations(arm):
    idle_base = {
        "pelvis": {"loc": (0, 0, -.035)},
        "spine": {"rot": (2, 0, 0)},
        "chest": {"rot": (-2, 0, 0)},
        "neck.1": {"rot": (2, 0, 0)},
        "head": {"rot": (-2, 0, 0)},
        "jaw": {"rot": (3, 0, 0)},
        "wing_upper.L": {"rot": (0, -5, -4)},
        "wing_upper.R": {"rot": (0, 5, 4)},
    }
    idle = action(arm, "Idle", [
        (1, idle_base),
        (25, {**idle_base, "chest": {"rot": (-4, 0, 1), "scale": (1.02, 1.02, 1.025)}, "neck.2": {"rot": (2, -3, 0)}, "tail.2": {"rot": (0, 7, 0)}, "tail.4": {"rot": (0, -12, 0)}}),
        (49, {**idle_base, "head": {"rot": (-1, 4, 1)}, "tail.1": {"rot": (0, -5, 0)}, "tail.3": {"rot": (0, 11, 0)}, "wing_fore.L": {"rot": (0, 0, -3)}, "wing_fore.R": {"rot": (0, 0, 3)}}),
        (73, {**idle_base, "jaw": {"rot": (5, 0, 0)}, "neck.1": {"rot": (1, 3, 0)}, "tail.5": {"rot": (0, 14, 0)}}),
        (97, idle_base),
    ], 97)

    walk_keys = []
    for frame, phase in ((1, 1), (13, -1), (25, 1), (37, -1), (49, 1)):
        walk_keys.append((frame, {
            "root": {"loc": (0, 0, .05 if frame in (13, 37) else 0)},
            "pelvis": {"rot": (3, 0, phase*3), "loc": (0, 0, -.07 if frame in (1, 25, 49) else .02)},
            "spine": {"rot": (-2, 0, -phase*2)},
            "chest": {"rot": (2, 0, -phase*3)},
            "neck.1": {"rot": (-2, 0, phase*2)},
            "head": {"rot": (-3, 0, phase*2)},
            "thigh.L": {"rot": (phase*22, 0, 0)}, "thigh.R": {"rot": (-phase*22, 0, 0)},
            "shin.L": {"rot": (-phase*15+12, 0, 0)}, "shin.R": {"rot": (phase*15+12, 0, 0)},
            "foot.L": {"rot": (phase*-9, 0, 0)}, "foot.R": {"rot": (phase*9, 0, 0)},
            "upper_arm.L": {"rot": (-phase*18, 0, 0)}, "upper_arm.R": {"rot": (phase*18, 0, 0)},
            "forearm.L": {"rot": (phase*8+10, 0, 0)}, "forearm.R": {"rot": (-phase*8+10, 0, 0)},
            "tail.1": {"rot": (0, -phase*5, 0)}, "tail.2": {"rot": (0, phase*10, 0)},
            "tail.3": {"rot": (0, -phase*15, 0)}, "tail.5": {"rot": (0, phase*20, 0)},
            "wing_upper.L": {"rot": (0, -4, -5)}, "wing_upper.R": {"rot": (0, 4, 5)},
        }))
    walk = action(arm, "Walk", walk_keys, 49)

    attack = action(arm, "Attack", [
        (1, idle_base),
        (9, {"pelvis": {"rot": (-5, 0, 0)}, "spine": {"rot": (-8, 0, 0)}, "chest": {"rot": (-12, 0, 0)}, "neck.1": {"rot": (-20, 0, 0)}, "neck.2": {"rot": (-18, 0, 0)}, "head": {"rot": (-14, 0, 0)}, "jaw": {"rot": (8, 0, 0)}, "wing_upper.L": {"rot": (0, -12, -14)}, "wing_upper.R": {"rot": (0, 12, 14)}}),
        (18, {"root": {"loc": (0, .30, .04)}, "spine": {"rot": (8, 0, 0)}, "chest": {"rot": (14, 0, 0)}, "neck.1": {"rot": (24, 0, 0)}, "neck.2": {"rot": (22, 0, 0)}, "head": {"rot": (18, 0, 0)}, "jaw": {"rot": (32, 0, 0)}, "upper_arm.L": {"rot": (-18, 0, -10)}, "upper_arm.R": {"rot": (-18, 0, 10)}, "wing_upper.L": {"rot": (0, -18, -24)}, "wing_upper.R": {"rot": (0, 18, 24)}}),
        (28, {"root": {"loc": (0, .12, 0)}, "head": {"rot": (4, 0, 0)}, "jaw": {"rot": (18, 0, 0)}, "tail.2": {"rot": (0, 15, 0)}}),
        (41, idle_base),
    ], 41)

    roar = action(arm, "Roar", [
        (1, idle_base),
        (12, {"chest": {"rot": (-10, 0, 0), "scale": (1.04, 1.04, 1.05)}, "neck.1": {"rot": (-18, 0, 0)}, "neck.2": {"rot": (-22, 0, 0)}, "head": {"rot": (-24, 0, 0)}, "jaw": {"rot": (38, 0, 0)}, "wing_upper.L": {"rot": (0, -16, -28)}, "wing_upper.R": {"rot": (0, 16, 28)}}),
        (42, {"chest": {"rot": (-8, 0, 0), "scale": (1.03, 1.03, 1.04)}, "head": {"rot": (-18, 4, 0)}, "jaw": {"rot": (42, 0, 0)}, "wing_fore.L": {"rot": (0, 0, -10)}, "wing_fore.R": {"rot": (0, 0, 10)}}),
        (61, idle_base),
    ], 61)

    fire = action(arm, "FireBreath", [
        (1, idle_base),
        (10, {"spine": {"rot": (-6, 0, 0)}, "neck.1": {"rot": (-18, 0, 0)}, "neck.2": {"rot": (-15, 0, 0)}, "head": {"rot": (-12, 0, 0)}, "jaw": {"rot": (28, 0, 0)}}),
        (22, {"root": {"loc": (0, .18, .02)}, "chest": {"rot": (8, 0, 0)}, "neck.1": {"rot": (16, 0, 0)}, "neck.2": {"rot": (18, 0, 0)}, "head": {"rot": (12, 0, 0)}, "jaw": {"rot": (36, 0, 0)}, "wing_upper.L": {"rot": (0, -12, -18)}, "wing_upper.R": {"rot": (0, 12, 18)}}),
        (46, {"head": {"rot": (8, -8, 0)}, "jaw": {"rot": (34, 0, 0)}, "tail.2": {"rot": (0, 12, 0)}}),
        (64, idle_base),
    ], 64)

    death = action(arm, "Death", [
        (1, idle_base),
        (18, {"root": {"loc": (0, 0, -.10)}, "pelvis": {"rot": (-9, 0, -4)}, "spine": {"rot": (-14, 0, -6)}, "neck.1": {"rot": (16, 0, 5)}, "head": {"rot": (20, 8, 4)}, "wing_upper.L": {"rot": (0, -8, -18)}, "wing_upper.R": {"rot": (0, 8, 18)}}),
        (42, {"root": {"loc": (0, .08, -.48)}, "pelvis": {"rot": (-22, 0, -6)}, "spine": {"rot": (-30, 0, -8)}, "chest": {"rot": (-28, 0, -6)}, "neck.1": {"rot": (26, 0, 8)}, "neck.2": {"rot": (28, 0, 7)}, "head": {"rot": (30, 0, 6)}, "jaw": {"rot": (18, 0, 0)}, "wing_upper.L": {"rot": (0, -10, -36)}, "wing_upper.R": {"rot": (0, 10, 36)}, "wing_fore.L": {"rot": (0, 0, 30)}, "wing_fore.R": {"rot": (0, 0, -30)}, "thigh.L": {"rot": (26, 0, 0)}, "thigh.R": {"rot": (18, 0, 0)}, "shin.L": {"rot": (32, 0, 0)}, "shin.R": {"rot": (26, 0, 0)}, "upper_arm.L": {"rot": (24, 0, 0)}, "upper_arm.R": {"rot": (18, 0, 0)}}),
        (72, {"root": {"loc": (0, .18, -.98)}, "pelvis": {"rot": (-34, 0, -7)}, "spine": {"rot": (-44, 0, -10)}, "chest": {"rot": (-40, 0, -8)}, "neck.1": {"rot": (32, 0, 10)}, "neck.2": {"rot": (36, 0, 9)}, "head": {"rot": (40, 0, 8)}, "jaw": {"rot": (24, 0, 0)}, "tail.1": {"rot": (0, 18, 0)}, "tail.2": {"rot": (0, 26, 0)}, "wing_upper.L": {"rot": (0, -12, -44)}, "wing_upper.R": {"rot": (0, 12, 44)}, "wing_fore.L": {"rot": (0, 0, 42)}, "wing_fore.R": {"rot": (0, 0, -42)}, "wing_hand.L": {"rot": (0, 0, 22)}, "wing_hand.R": {"rot": (0, 0, -22)}, "thigh.L": {"rot": (34, 0, 0)}, "thigh.R": {"rot": (28, 0, 0)}, "shin.L": {"rot": (42, 0, 0)}, "shin.R": {"rot": (36, 0, 0)}, "upper_arm.L": {"rot": (38, 0, 0)}, "upper_arm.R": {"rot": (32, 0, 0)}, "forearm.L": {"rot": (34, 0, 0)}, "forearm.R": {"rot": (28, 0, 0)}}),
        (91, {"root": {"loc": (0, .20, -1.02)}, "pelvis": {"rot": (-36, 0, -7)}, "spine": {"rot": (-46, 0, -10)}, "chest": {"rot": (-42, 0, -8)}, "neck.1": {"rot": (34, 0, 10)}, "neck.2": {"rot": (38, 0, 9)}, "head": {"rot": (42, 0, 8)}, "jaw": {"rot": (20, 0, 0)}, "tail.2": {"rot": (0, 28, 0)}, "wing_upper.L": {"rot": (0, -12, -46)}, "wing_upper.R": {"rot": (0, 12, 46)}, "wing_fore.L": {"rot": (0, 0, 44)}, "wing_fore.R": {"rot": (0, 0, -44)}, "wing_hand.L": {"rot": (0, 0, 24)}, "wing_hand.R": {"rot": (0, 0, -24)}, "thigh.L": {"rot": (36, 0, 0)}, "thigh.R": {"rot": (30, 0, 0)}, "shin.L": {"rot": (44, 0, 0)}, "shin.R": {"rot": (38, 0, 0)}, "upper_arm.L": {"rot": (40, 0, 0)}, "upper_arm.R": {"rot": (34, 0, 0)}, "forearm.L": {"rot": (36, 0, 0)}, "forearm.R": {"rot": (30, 0, 0)}}),
    ], 91)

    arm.animation_data.action = None
    for act in (idle, walk, attack, roar, fire, death):
        track = arm.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, int(act.frame_start), act)
    return [idle, walk, attack, roar, fire, death]


def setup_preview(arm):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = PREVIEW_OUT
    scene.world.color = (.006, .004, .006)

    bpy.ops.mesh.primitive_plane_add(size=35, location=(0, 0, 0))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(material("Dragon Preview Floor", (.018, .012, .012, 1), .96))

    bpy.ops.object.camera_add(location=(12.5, 15.5, 8.8))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    scene.camera = camera
    target = Vector((0, -.35, 3.45))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 52

    lights = []
    for location, energy, color, size in (
        ((-7, 8, 12), 1800, (1.0, .18, .05), 7.0),
        ((8, 5, 8), 1300, (.12, .22, 1.0), 6.0),
        ((0, -8, 10), 2100, (1.0, .055, .01), 5.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
        lights.append(light)

    arm.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(25)
    os.makedirs(os.path.dirname(PREVIEW_OUT), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for obj in [floor, camera] + lights:
        obj.hide_render = True


def export(arm):
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "ARMATURE"} and not obj.name.startswith("Preview"):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_lights=False,
        export_cameras=False,
        export_apply=False,
    )


clear_scene()
armature = build_armature()
build_dragon(armature)
actions = make_animations(armature)
setup_preview(armature)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
export(armature)
print(
    "DRAGON_COMPLETE|blend=%s|glb=%s|preview=%s|animations=%s"
    % (BLEND_OUT, GLB_OUT, PREVIEW_OUT, ",".join(action.name for action in actions))
)
