import bpy
import bmesh
import json
from math import radians, exp
import os

FAST_PREVIEW = os.environ.get("BK_FAST_PREVIEW", "1") == "1"
FAST_LOOP = os.environ.get("BK_HERO_FAST_LOOP", "1") == "1"


def fast_segments(segments, rings=None):
    if not FAST_LOOP:
        return segments, rings
    seg = max(12, int(round(segments * 0.6)))
    if rings is None:
        return seg, rings
    ring = max(8, int(round(rings * 0.6)))
    return seg, ring


def fast_subdivisions(subdivisions):
    if not FAST_LOOP:
        return subdivisions
    return max(1, subdivisions - 1)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)


def make_mat(name, color, roughness=0.8):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_uv_sphere(name, location, scale, mat, segments=32, rings=16):
    segments, rings = fast_segments(segments, rings)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_ico_sphere(name, location, scale, mat, subdivisions=3):
    subdivisions = fast_subdivisions(subdivisions)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_uv_sphere_rot(name, location, scale, rotation, mat, segments=32, rings=16):
    segments, rings = fast_segments(segments, rings)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_cube(name, location, scale, mat):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    bevel = obj.modifiers.new(name="Bevel", type="BEVEL")
    bevel.width = 0.04
    bevel.segments = 2
    return obj


def add_capsule(name, location, scale, mat, z_offset=0.55):
    parts = []
    core = add_cylinder(f"{name}.Core", location, (scale[0], scale[1], scale[2]), mat, vertices=24)
    top = add_uv_sphere(f"{name}.Top", (location[0], location[1], location[2] + scale[2] * z_offset), (scale[0], scale[1], scale[0]), mat, segments=24, rings=12)
    bottom = add_uv_sphere(f"{name}.Bottom", (location[0], location[1], location[2] - scale[2] * z_offset), (scale[0], scale[1], scale[0]), mat, segments=24, rings=12)
    parts.extend([core, top, bottom])
    return join_objects(name, parts)


def soften_object(obj, factor=0.35, iterations=6):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_add(type="SMOOTH")
    smooth = obj.modifiers[-1]
    smooth.factor = factor
    smooth.iterations = iterations
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    bpy.ops.object.shade_smooth()
    return obj


def add_plane(name, location, scale, mat):
    bpy.ops.mesh.primitive_plane_add(location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_cone(name, location, scale, mat, vertices=24, taper=0.55):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=1.0, radius2=taper, depth=2.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_cylinder(name, location, scale, mat, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=1.0, depth=2.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if mat:
        obj.data.materials.append(mat)
    return obj


def parent_many(parent, children):
    for child in children:
        child.parent = parent


def join_objects(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def voxel_remesh(obj, voxel_size=0.035, smooth_passes=4):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_add(type="REMESH")
    remesh = obj.modifiers[-1]
    remesh.mode = "VOXEL"
    remesh_scale = 1.35 if FAST_PREVIEW else 1.0
    if FAST_LOOP:
        remesh_scale *= 1.25
    remesh.voxel_size = voxel_size * remesh_scale
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth_scale = 0.55 if FAST_PREVIEW else 1.0
    if FAST_LOOP:
        smooth_scale *= 0.65
    applied_smooth_passes = max(2, int(round(smooth_passes * smooth_scale)))
    for _ in range(applied_smooth_passes):
        bpy.ops.object.modifier_add(type="SMOOTH")
        smooth = obj.modifiers[-1]
        smooth.factor = 0.5
        if FAST_LOOP:
            smooth.iterations = 3
        else:
            smooth.iterations = 5 if FAST_PREVIEW else 8
        bpy.ops.object.modifier_apply(modifier=smooth.name)
    bpy.ops.object.shade_smooth()
    return obj


def sculpt_head_mesh(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    for v in bm.verts:
        x, y, z = v.co.x, v.co.y, v.co.z

        # Stable skull silhouette with a clearer face-side split.
        if z > 0.08:
            top_t = min(1.0, (z - 0.08) / 0.28)
            v.co.z -= 0.012 * top_t
            v.co.x *= 1.0 - 0.035 * top_t
            v.co.y += 0.006 * top_t
        if z < -0.10:
            jaw_t = min(1.0, (-z - 0.10) / 0.070)
            # Pull the lower jaw into an adult oval instead of allowing the
            # sphere's full width to survive as a broad horizontal muzzle.
            v.co.x *= 1.0 - 0.145 * jaw_t
            v.co.y += 0.003 * jaw_t
            v.co.z += 0.006 * jaw_t

        # Create a flatter facial mask on the front instead of a balloon face.
        if y < 0.04:
            front_t = min(1.0, (0.04 - y) / 0.24)
            v.co.y += 0.010 * front_t

        # Local masks.
        cx = max(0.0, 1.0 - abs(x) / 0.12)
        nose_core = max(0.0, 1.0 - abs(x) / 0.050)
        nose_tip_core = max(0.0, 1.0 - abs(x) / 0.060)
        left_eye = max(0.0, 1.0 - abs(x + 0.048) / 0.043)
        right_eye = max(0.0, 1.0 - abs(x - 0.048) / 0.043)
        eye_pair = max(left_eye, right_eye)
        orbital_pair = max(0.0, 1.0 - abs(abs(x) - 0.048) / 0.060)
        front_face = max(0.0, 1.0 - abs(x) / 0.16)
        centerline = max(0.0, 1.0 - abs(x) / 0.052)

        forehead_z = max(0.0, 1.0 - abs(z - 0.080) / 0.090)
        brow_z = max(0.0, 1.0 - abs(z - 0.010) / 0.055)
        socket_z = max(0.0, 1.0 - abs(z + 0.008) / 0.052)
        eye_slit_z = max(0.0, 1.0 - abs(z + 0.018) / 0.010)
        nose_z = max(0.0, 1.0 - abs(z + 0.055) / 0.092)
        tip_z = max(0.0, 1.0 - abs(z + 0.106) / 0.030)
        # These masks must live inside the scaled head's vertical extent
        # (about +/-0.158 m). The previous centers sat below the mesh and
        # accidentally shaped the underside of the jaw instead of the face.
        philtrum_z = max(0.0, 1.0 - abs(z + 0.082) / 0.018)
        mouth_z = max(0.0, 1.0 - abs(z + 0.104) / 0.024)
        lower_lip_z = max(0.0, 1.0 - abs(z + 0.122) / 0.020)
        mouth_line_z = max(0.0, 1.0 - abs(z + 0.106) / 0.010)
        upper_lip_z = max(0.0, 1.0 - abs(z + 0.096) / 0.016)
        mouth_width = max(0.0, 1.0 - abs(x) / 0.052)
        mouth_corner = max(0.0, 1.0 - abs(abs(x) - 0.046) / 0.014)
        chin_z = max(0.0, 1.0 - abs(z + 0.142) / 0.026)
        cheek_z = max(0.0, 1.0 - abs(z + 0.062) / 0.084)
        cheek_side = max(0.0, 1.0 - abs(abs(x) - 0.088) / 0.060)
        temple_z = max(0.0, 1.0 - abs(z + 0.000) / 0.120)
        temple_side = max(0.0, 1.0 - abs(abs(x) - 0.115) / 0.040)
        midface_z = max(0.0, 1.0 - abs(z + 0.086) / 0.062)
        jawline_z = max(0.0, 1.0 - abs(z + 0.128) / 0.045)
        jaw_side = max(0.0, 1.0 - abs(abs(x) - 0.094) / 0.050)
        muzzle_z = max(0.0, 1.0 - abs(z + 0.086) / 0.050)
        orbital_z = max(0.0, 1.0 - abs(z + 0.020) / 0.090)
        nasal_side = max(0.0, 1.0 - abs(abs(x) - 0.028) / 0.030)
        alar_z = max(0.0, 1.0 - abs(z + 0.106) / 0.050)
        nostril_z = max(0.0, 1.0 - abs(z + 0.112) / 0.016)
        face_plane_z = max(0.0, 1.0 - abs(z + 0.085) / 0.190)
        center_slab_z = max(0.0, 1.0 - abs(z + 0.095) / 0.170)
        facial_cap_z = max(0.0, 1.0 - abs(z + 0.090) / 0.235)
        front_bowl_z = max(0.0, 1.0 - abs(z + 0.050) / 0.220)

        # Forehead slope and temples.
        forehead_strength = cx * forehead_z
        if forehead_strength > 0.0 and y < 0.03:
            v.co.y -= 0.008 * forehead_strength
            v.co.z -= 0.001 * forehead_strength
        temple_strength = temple_z * temple_side
        if temple_strength > 0.0:
            v.co.x *= 1.0 - 0.060 * temple_strength
            v.co.y += 0.008 * temple_strength

        # Round the skull before adding facial structure so the face is working
        # with a fuller head rather than a front-flattened wedge.
        if z > -0.02 and z < 0.18:
            skull_round = max(0.0, 1.0 - abs(z - 0.06) / 0.20)
            side_round = max(0.0, 1.0 - abs(x) / 0.22)
            if skull_round > 0.0 and side_round > 0.0:
                v.co.y += 0.010 * skull_round * side_round

        # Widen and soften the lower cranium so the head stays globe-like and
        # doesn't collapse into a narrow cone under the face.
        if z < 0.00:
            lower_head = min(1.0, (-z) / 0.22)
            v.co.x *= 1.0 + 0.014 * lower_head
            v.co.y += 0.000 * lower_head
        if z > 0.02:
            upper_head = min(1.0, (z - 0.02) / 0.24)
            v.co.x *= 1.0 + 0.012 * upper_head
        if z > -0.04 and z < 0.10:
            muzzle_round = max(0.0, 1.0 - abs(z - 0.01) / 0.14)
            v.co.y += 0.000 * muzzle_round * max(0.0, 1.0 - abs(x) / 0.16)
        if z > -0.02 and z < 0.08:
            lower_face_round = max(0.0, 1.0 - abs(z + 0.00) / 0.10)
            v.co.x *= 1.0 + 0.006 * lower_face_round * max(0.0, 1.0 - abs(x) / 0.18)

        # One shared front facial plane so the face reads on the front of the
        # head instead of as two side clusters.
        face_plane_strength = front_face * face_plane_z
        if face_plane_strength > 0.0 and y < 0.06:
            v.co.y -= 0.012 * face_plane_strength
        centerline_strength = centerline * face_plane_z
        if centerline_strength > 0.0:
            v.co.y -= 0.008 * centerline_strength
        center_slab_strength = centerline * center_slab_z
        if center_slab_strength > 0.0:
            v.co.x *= 1.0 - 0.028 * center_slab_strength
            v.co.y -= 0.007 * center_slab_strength
        facial_cap_strength = front_face * facial_cap_z
        if facial_cap_strength > 0.0 and y < 0.03:
            v.co.y -= 0.014 * facial_cap_strength
            v.co.x *= 1.0 - 0.014 * facial_cap_strength

        # Explicitly blend the front of the head toward a unified facial
        # surface so the face belongs to the front volume, not the side walls.
        front_surface_strength = front_face * front_bowl_z
        if front_surface_strength > 0.0 and y < 0.02:
            target_y = -0.036
            target_y -= 0.004 * cx * brow_z
            target_y -= 0.012 * cx * nose_z
            target_y -= 0.010 * cx * tip_z
            target_y += 0.003 * cx * mouth_z
            target_y += 0.002 * cx * chin_z
            blend = min(0.84, 0.66 * front_surface_strength)
            v.co.y = v.co.y * (1.0 - blend) + target_y * blend

        # Explicit profile staging: give the face separate depth planes so it
        # doesn't collapse into one continuous soft protrusion.
        profile_strength = centerline * max(0.0, 1.0 - abs(y + 0.01) / 0.08)
        forehead_profile = profile_strength * max(0.0, 1.0 - abs(z - 0.090) / 0.070)
        brow_profile = profile_strength * max(0.0, 1.0 - abs(z - 0.015) / 0.040)
        nose_profile = profile_strength * max(0.0, 1.0 - abs(z + 0.060) / 0.065)
        lip_profile = profile_strength * max(0.0, 1.0 - abs(z + 0.106) / 0.028)
        chin_profile = profile_strength * max(0.0, 1.0 - abs(z + 0.141) / 0.024)
        if forehead_profile > 0.0:
            v.co.y += 0.014 * forehead_profile
        if brow_profile > 0.0:
            v.co.y -= 0.006 * brow_profile
            v.co.z += 0.003 * brow_profile
        if nose_profile > 0.0:
            v.co.y -= 0.012 * nose_profile
        if lip_profile > 0.0:
            v.co.y -= 0.004 * lip_profile
            v.co.z -= 0.001 * lip_profile
        if chin_profile > 0.0:
            v.co.y -= 0.006 * chin_profile
            v.co.z -= 0.001 * chin_profile

        # Extra upper-face structure so the sockets don't just melt into the
        # front plane.
        brow_bar = centerline * brow_z * max(0.0, 1.0 - abs(y + 0.005) / 0.05)
        if brow_bar > 0.0:
            v.co.y -= 0.008 * brow_bar
            v.co.z += 0.002 * brow_bar

        inner_socket = centerline * socket_z * max(0.0, 1.0 - abs(y + 0.01) / 0.05)
        if inner_socket > 0.0:
            v.co.y += 0.010 * inner_socket
            v.co.z -= 0.004 * inner_socket

        # Build a clearer orbital mask so the upper face isn't just a soft blob.
        orbital_strength = orbital_pair * orbital_z
        if orbital_strength > 0.0 and y < 0.045:
            v.co.y += 0.012 * orbital_strength
            v.co.z -= 0.002 * orbital_strength
            v.co.x *= 1.0 + 0.001 * orbital_strength

        # Brow ridge.
        brow_strength = eye_pair * brow_z
        if brow_strength > 0.0 and y < 0.03:
            v.co.y -= 0.014 * brow_strength
            v.co.z += 0.005 * brow_strength

        # Eye sockets.
        socket_strength = eye_pair * socket_z
        if socket_strength > 0.0 and y < 0.05:
            v.co.y += 0.009 * socket_strength
            v.co.z -= 0.002 * socket_strength
        eye_slit = eye_pair * eye_slit_z
        if eye_slit > 0.0 and y < 0.025:
            v.co.y += 0.006 * eye_slit
            v.co.z -= 0.001 * eye_slit

        # Nose bridge and tip.
        bridge_strength = nose_core * nose_z
        if bridge_strength > 0.0 and y < 0.05:
            v.co.y -= 0.032 * bridge_strength
            v.co.x *= 1.0 - 0.008 * bridge_strength
        tip_strength = nose_tip_core * tip_z
        if tip_strength > 0.0:
            v.co.y -= 0.030 * tip_strength
            v.co.z -= 0.003 * tip_strength

        # Give the nose sidewalls and nostril zone some structure.
        nasal_strength = nasal_side * nose_z
        if nasal_strength > 0.0:
            v.co.y -= 0.014 * nasal_strength
        alar_strength = nasal_side * alar_z
        if alar_strength > 0.0:
            v.co.x *= 1.0 + 0.006 * alar_strength
            v.co.y -= 0.005 * alar_strength
        nostril_strength = nasal_side * nostril_z
        if nostril_strength > 0.0 and y < 0.025:
            v.co.y += 0.012 * nostril_strength

        # Pull the face itself together so the features feel attached.
        midface_strength = cx * midface_z
        if midface_strength > 0.0 and y < 0.04:
            v.co.y -= 0.018 * midface_strength
            v.co.x *= 1.0 - 0.010 * midface_strength
        face_core_strength = front_face * midface_z
        if face_core_strength > 0.0 and y < 0.04:
            v.co.y -= 0.018 * face_core_strength
            v.co.x *= 1.0 - 0.002 * face_core_strength

        # Add a central nose-cheek wedge so the face becomes a readable front
        # form instead of only a shallow depression pattern.
        if front_face > 0.0 and nose_z > 0.0 and y < 0.02:
            v.co.y -= 0.010 * front_face * nose_z
        if front_face > 0.0 and mouth_z > 0.0 and y < 0.02:
            v.co.y += 0.003 * front_face * mouth_z

        # Cheeks.
        cheek_strength = cheek_z * cheek_side
        if cheek_strength > 0.0:
            v.co.y -= 0.008 * cheek_strength
            v.co.x *= 1.0 + 0.024 * cheek_strength
            v.co.z += 0.003 * cheek_strength

        # Muzzle / upper-lip block so the mouth area belongs to the face.
        muzzle_strength = cx * muzzle_z
        if muzzle_strength > 0.0:
            v.co.y += 0.005 * muzzle_strength
        muzzle_core = front_face * muzzle_z
        if muzzle_core > 0.0:
            v.co.y += 0.003 * muzzle_core

        # Jaw corners so the lower face stops collapsing into a soft cone.
        jaw_strength = jawline_z * jaw_side
        if jaw_strength > 0.0:
            v.co.x *= 1.0 + 0.018 * jaw_strength
            v.co.y += 0.001 * jaw_strength

        # Philtrum and mouth transition.
        philtrum_strength = centerline * philtrum_z
        if philtrum_strength > 0.0:
            v.co.y += 0.007 * philtrum_strength
            v.co.z -= 0.002 * philtrum_strength

        # Mouth and chin.
        mouth_line = mouth_width * mouth_line_z
        if mouth_line > 0.0 and y < 0.04:
            v.co.y += 0.008 * mouth_line
            v.co.z -= 0.002 * mouth_line
        corner_line = mouth_corner * mouth_line_z
        if corner_line > 0.0 and y < 0.04:
            v.co.y += 0.006 * corner_line
            v.co.z += 0.002 * corner_line
        upper_lip = mouth_width * upper_lip_z
        if upper_lip > 0.0 and y < 0.04:
            v.co.y -= 0.006 * upper_lip
        lower_lip = mouth_width * lower_lip_z
        if lower_lip > 0.0 and y < 0.04:
            v.co.y -= 0.005 * lower_lip
        if cx > 0.0 and mouth_z > 0.0:
            v.co.y += 0.002 * cx * mouth_z
            v.co.z -= 0.004 * cx * mouth_z
        if cx > 0.0 and lower_lip_z > 0.0:
            v.co.y += 0.004 * cx * lower_lip_z
            v.co.z -= 0.004 * cx * lower_lip_z
        if cx > 0.0 and chin_z > 0.0:
            v.co.y -= 0.014 * cx * chin_z
            v.co.z -= 0.004 * cx * chin_z
            v.co.x *= 1.0 + 0.010 * cx * chin_z

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    bpy.ops.object.shade_smooth()
    return obj


def sculpt_head_mesh_clean(obj):
    """Build one coherent face surface without stacked post-remesh masks."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    subdivision = obj.modifiers.new(name="FaceSourceSubdivision", type="SUBSURF")
    subdivision.subdivision_type = "SIMPLE"
    subdivision.levels = 2
    subdivision.render_levels = 2
    bpy.ops.object.modifier_apply(modifier=subdivision.name)

    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def gaussian(value, center, width):
        return exp(-((value - center) / width) ** 2)

    for v in bm.verts:
        x, y, z = v.co.x, v.co.y, v.co.z
        v.co.x *= 0.965
        x = v.co.x
        rear = max(0.0, min(1.0, (y + 0.005) / 0.115))
        if rear > 0.0:
            v.co.y *= 1.0 - 0.14 * rear
            y = v.co.y
        temple_band = gaussian(z, 0.012, 0.034)
        parietal_band = gaussian(z, 0.072, 0.042)
        v.co.x *= 1.0 - 0.026 * temple_band + 0.015 * parietal_band
        if z > 0.045:
            top = min(1.0, (z - 0.045) / 0.105)
            v.co.z -= 0.016 * top
            v.co.x *= 1.0 - 0.022 * top
        if z < -0.045:
            jaw = min(1.0, (-z - 0.045) / 0.105)
            v.co.x *= 1.0 - 0.17 * jaw
            center_chin = gaussian(x, 0.0, 0.050)
            v.co.z -= 0.004 * jaw * center_chin
        jaw_angle = gaussian(abs(x), 0.074, 0.032) * gaussian(z, -0.092, 0.034)
        v.co.x *= 1.0 + 0.12 * jaw_angle

        front = max(0.0, min(1.0, (-0.010 - y) / 0.095))
        if front <= 0.0:
            continue

        abs_x = abs(x)
        eyes = max(gaussian(x, -0.043, 0.024), gaussian(x, 0.043, 0.024))
        facial_oval = gaussian(x, 0.0, 0.105) * gaussian(z, -0.035, 0.145)
        v.co.y += 0.006 * front * facial_oval
        forehead_plane = gaussian(x, 0.0, 0.090) * gaussian(z, 0.070, 0.050)
        v.co.y += 0.0070 * front * forehead_plane

        brow = eyes * gaussian(z, 0.018, 0.022)
        socket = eyes * gaussian(z, -0.006, 0.027)
        eye_line = eyes * gaussian(z, -0.012, 0.0055)
        upper_lid = eyes * gaussian(z, -0.004, 0.008)
        lower_lid = eyes * gaussian(z, -0.021, 0.008)
        v.co.y -= 0.0065 * front * brow
        v.co.y += 0.0080 * front * socket
        v.co.y += 0.0048 * front * eye_line
        v.co.y -= 0.0027 * front * upper_lid
        v.co.y -= 0.0018 * front * lower_lid

        bridge = gaussian(x, 0.0, 0.020) * gaussian(z, -0.025, 0.060)
        tip = gaussian(x, 0.0, 0.030) * gaussian(z, -0.073, 0.023)
        wings = gaussian(abs_x, 0.024, 0.013) * gaussian(z, -0.079, 0.015)
        nostrils = gaussian(abs_x, 0.021, 0.008) * gaussian(z, -0.084, 0.006)
        v.co.y -= 0.029 * front * bridge
        v.co.y -= 0.023 * front * tip
        v.co.y -= 0.005 * front * wings
        v.co.y += 0.003 * front * nostrils

        cheeks = gaussian(abs_x, 0.071, 0.035) * gaussian(z, -0.055, 0.050)
        v.co.y -= 0.0045 * front * cheeks

        muzzle_support = gaussian(x, 0.0, 0.058) * gaussian(z, -0.106, 0.034)
        chin_support = gaussian(x, 0.0, 0.050) * gaussian(z, -0.142, 0.021)
        v.co.y -= 0.014 * front * muzzle_support
        v.co.y -= 0.006 * front * chin_support

        mouth_width = gaussian(x, 0.0, 0.036)
        mouth_line = mouth_width * gaussian(z, -0.108, 0.0045)
        upper_lip = mouth_width * gaussian(z, -0.100, 0.007)
        lower_lip = mouth_width * gaussian(z, -0.117, 0.008)
        philtrum = gaussian(x, 0.0, 0.012) * gaussian(z, -0.092, 0.013)
        mouth_corners = gaussian(abs_x, 0.034, 0.008) * gaussian(z, -0.108, 0.006)
        chin = gaussian(x, 0.0, 0.043) * gaussian(z, -0.143, 0.020)
        v.co.y += 0.0022 * front * mouth_line
        v.co.y += 0.0010 * front * mouth_corners
        v.co.y -= 0.0020 * front * upper_lip
        v.co.y -= 0.0017 * front * lower_lip
        v.co.y += 0.0018 * front * philtrum
        v.co.y -= 0.0045 * front * chin

    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.object.shade_smooth()
    return obj


def refine_clean_face_after_remesh(obj):
    """Restore small anatomical breaks after the isolated fine head remesh."""
    bpy.context.view_layer.objects.active = obj
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def gaussian(value, center, width):
        return exp(-((value - center) / width) ** 2)

    for v in bm.verts:
        x, y, z_world = v.co.x, v.co.y, v.co.z
        z = z_world - 1.002
        if z < -0.158 or z > 0.055:
            continue
        front = max(0.0, min(1.0, (-0.070 - y) / 0.065))
        if front <= 0.0:
            continue

        abs_x = abs(x)
        eyes = max(gaussian(x, -0.043, 0.022), gaussian(x, 0.043, 0.022))
        brow = eyes * gaussian(z, 0.017, 0.012)
        upper_lid = eyes * gaussian(z, -0.006, 0.0055)
        eye_crease = eyes * gaussian(z, -0.013, 0.0032)
        lower_lid = eyes * gaussian(z, -0.020, 0.0055)
        globe_support = eyes * gaussian(z, -0.013, 0.011)
        inner_corner = gaussian(abs_x, 0.022, 0.0055) * gaussian(z, -0.013, 0.004)
        outer_corner = gaussian(abs_x, 0.064, 0.0065) * gaussian(z, -0.013, 0.0045)
        brow_arch_center = 0.015 + 0.006 * gaussian(abs_x, 0.050, 0.018)
        brow_arch = eyes * gaussian(z, brow_arch_center, 0.007)
        glabella = gaussian(x, 0.0, 0.017) * gaussian(z, 0.010, 0.018)
        outer_corner_lift = gaussian(abs_x, 0.060, 0.010) * gaussian(z, -0.013, 0.009)
        v.co.y -= 0.0023 * front * brow
        v.co.y -= 0.0020 * front * brow_arch
        v.co.y -= 0.0010 * front * glabella
        v.co.y -= 0.0018 * front * globe_support
        v.co.y -= 0.0018 * front * upper_lid
        v.co.y += 0.0050 * front * eye_crease
        v.co.y -= 0.0015 * front * lower_lid
        v.co.z += 0.0022 * front * upper_lid
        v.co.z -= 0.0015 * front * lower_lid
        v.co.y += 0.0010 * front * inner_corner
        v.co.y += 0.0008 * front * outer_corner
        v.co.z += 0.0020 * front * outer_corner_lift

        nostrils = gaussian(abs_x, 0.018, 0.0065) * gaussian(z, -0.084, 0.0045)
        nose_column = gaussian(x, 0.0, 0.013) * gaussian(z, -0.066, 0.030)
        nose_tip = gaussian(x, 0.0, 0.028) * gaussian(z, -0.073, 0.016)
        columella = gaussian(x, 0.0, 0.010) * gaussian(z, -0.087, 0.007)
        alar_break = gaussian(abs_x, 0.025, 0.007) * gaussian(z, -0.083, 0.008)
        alar_volume = gaussian(abs_x, 0.022, 0.012) * gaussian(z, -0.080, 0.014)
        lower_sidewall = gaussian(abs_x, 0.018, 0.014) * gaussian(z, -0.060, 0.026)
        v.co.y += 0.0018 * front * nostrils
        v.co.y -= 0.0008 * front * nose_column
        v.co.y -= 0.0045 * front * nose_tip
        v.co.y -= 0.0012 * front * columella
        v.co.y += 0.0012 * front * alar_break
        side_sign = -1.0 if x < 0.0 else 1.0
        v.co.x += side_sign * 0.0016 * front * alar_volume
        v.co.x += side_sign * 0.0008 * front * lower_sidewall

        mouth_width = gaussian(x, 0.0, 0.036)
        mouth_crease = mouth_width * gaussian(z, -0.108, 0.0032)
        upper_lip = mouth_width * gaussian(z, -0.101, 0.0050)
        lower_lip = mouth_width * gaussian(z, -0.116, 0.0055)
        corners = gaussian(abs_x, 0.034, 0.006) * gaussian(z, -0.108, 0.004)
        chin_break = gaussian(x, 0.0, 0.035) * gaussian(z, -0.131, 0.006)
        philtrum_columns = gaussian(abs_x, 0.008, 0.004) * gaussian(z, -0.092, 0.010)
        philtrum_groove = gaussian(x, 0.0, 0.005) * gaussian(z, -0.092, 0.010)
        cupid_peaks = gaussian(abs_x, 0.010, 0.005) * gaussian(z, -0.101, 0.0045)
        cupid_notch = gaussian(x, 0.0, 0.005) * gaussian(z, -0.101, 0.004)
        lower_lip_center = gaussian(x, 0.0, 0.026) * gaussian(z, -0.116, 0.005)
        chin_pad = gaussian(x, 0.0, 0.034) * gaussian(z, -0.145, 0.014)
        v.co.y += 0.0032 * front * mouth_crease
        v.co.y += 0.0012 * front * corners
        v.co.y -= 0.0020 * front * upper_lip
        v.co.y -= 0.0018 * front * lower_lip
        v.co.z += 0.0010 * front * upper_lip
        v.co.z -= 0.0010 * front * lower_lip
        v.co.y += 0.0025 * front * chin_break
        v.co.y -= 0.0014 * front * philtrum_columns
        v.co.y += 0.0010 * front * philtrum_groove
        v.co.y -= 0.0018 * front * cupid_peaks
        v.co.y += 0.0010 * front * cupid_notch
        v.co.y -= 0.0022 * front * lower_lip_center
        v.co.y -= 0.0032 * front * chin_pad

        cheek_plane = gaussian(abs_x, 0.066, 0.030) * gaussian(z, -0.052, 0.036)
        mandibular_plane = gaussian(abs_x, 0.071, 0.028) * gaussian(z, -0.108, 0.030)
        nasolabial_transition = gaussian(abs_x, 0.038, 0.010) * gaussian(z, -0.092, 0.025)
        v.co.y -= 0.0030 * front * cheek_plane
        v.co.y += 0.0020 * front * mandibular_plane
        v.co.y += 0.0012 * front * nasolabial_transition

        left_brow_asym = gaussian(x, -0.043, 0.024) * gaussian(z, 0.014, 0.016)
        right_cheek_asym = gaussian(x, 0.064, 0.030) * gaussian(z, -0.055, 0.040)
        nose_asym = gaussian(x, 0.0, 0.024) * gaussian(z, -0.073, 0.020)
        left_mouth_asym = gaussian(x, -0.034, 0.010) * gaussian(z, -0.108, 0.009)
        v.co.z += 0.0008 * front * left_brow_asym
        v.co.y -= 0.0007 * front * right_cheek_asym
        v.co.x += 0.0007 * front * nose_asym
        v.co.z += 0.0005 * front * left_mouth_asym

    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.object.shade_smooth()
    return obj


def sculpt_torso_mesh(obj):
    """Shape one continuous trunk instead of blending stacked primitives."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    for v in bm.verts:
        # TorsoMass is 0.72 m tall after scale application.
        t = max(-1.0, min(1.0, v.co.z / 0.36))
        chest = exp(-((t - 0.42) ** 2) / 0.12)
        waist = exp(-((t + 0.04) ** 2) / 0.075)
        hips = exp(-((t + 0.58) ** 2) / 0.11)
        upper_taper = exp(-((t - 0.92) ** 2) / 0.045)

        v.co.x *= 1.0 + 0.30 * chest - 0.17 * waist + 0.24 * hips - 0.08 * upper_taper
        v.co.y *= 1.0 + 0.10 * chest - 0.06 * waist + 0.12 * hips
        if v.co.y < 0.0:
            v.co.y -= 0.010 * exp(-((t + 0.10) ** 2) / 0.16)

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    bpy.ops.object.shade_smooth()
    return obj


def reinforce_face_after_remesh(obj):
    """Restore restrained facial planes that the final body remesh softens."""
    bpy.context.view_layer.objects.active = obj
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for v in bm.verts:
        x = v.co.x
        y = v.co.y
        z = v.co.z - 1.002
        if z < -0.165 or z > 0.155:
            continue
        front = max(0.0, min(1.0, (-0.015 - y) / 0.045))
        if front <= 0.0:
            continue
        left_eye = max(0.0, 1.0 - abs(x + 0.046) / 0.038)
        right_eye = max(0.0, 1.0 - abs(x - 0.046) / 0.038)
        eye_pair = max(left_eye, right_eye)
        brow_z = max(0.0, 1.0 - abs(z - 0.010) / 0.035)
        socket_z = max(0.0, 1.0 - abs(z + 0.018) / 0.022)
        eye_line_z = max(0.0, 1.0 - abs(z + 0.018) / 0.006)
        upper_lid_z = max(0.0, 1.0 - abs(z + 0.010) / 0.010)
        lower_lid_z = max(0.0, 1.0 - abs(z + 0.027) / 0.009)
        nose_core = max(0.0, 1.0 - abs(x) / 0.050)
        nose_z = max(0.0, 1.0 - abs(z + 0.058) / 0.070)
        tip_z = max(0.0, 1.0 - abs(z + 0.106) / 0.026)
        nostril_pair = max(0.0, 1.0 - abs(abs(x) - 0.020) / 0.012)
        nostril_z = max(0.0, 1.0 - abs(z + 0.111) / 0.009)
        mouth_width = max(0.0, 1.0 - abs(x) / 0.052)
        mouth_line_z = max(0.0, 1.0 - abs(z + 0.106) / 0.009)
        mouth_corner = max(0.0, 1.0 - abs(abs(x) - 0.042) / 0.012)
        mouth_corner_z = max(0.0, 1.0 - abs(z + 0.106) / 0.012)
        philtrum = max(0.0, 1.0 - abs(x) / 0.014)
        philtrum_z = max(0.0, 1.0 - abs(z + 0.087) / 0.018)
        upper_lip_z = max(0.0, 1.0 - abs(z + 0.095) / 0.014)
        lower_lip_z = max(0.0, 1.0 - abs(z + 0.121) / 0.014)
        chin_z = max(0.0, 1.0 - abs(z + 0.143) / 0.022)

        v.co.y -= 0.0025 * front * eye_pair * brow_z
        v.co.y += 0.004 * front * eye_pair * socket_z
        v.co.y += 0.008 * front * eye_pair * eye_line_z
        v.co.y -= 0.004 * front * eye_pair * upper_lid_z
        v.co.y -= 0.0025 * front * eye_pair * lower_lid_z
        v.co.y -= 0.008 * front * nose_core * nose_z
        v.co.y -= 0.010 * front * nose_core * tip_z
        v.co.y += 0.003 * front * nostril_pair * nostril_z
        v.co.y += 0.006 * front * mouth_width * mouth_line_z
        v.co.y += 0.004 * front * mouth_corner * mouth_corner_z
        v.co.y += 0.003 * front * philtrum * philtrum_z
        v.co.y -= 0.004 * front * mouth_width * upper_lip_z
        v.co.y -= 0.003 * front * mouth_width * lower_lip_z
        v.co.y -= 0.005 * front * nose_core * chin_z

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    bpy.ops.object.shade_smooth()
    return obj


def build_body():
    clear_scene()

    skin = make_mat("HeroSkin", (0.71, 0.57, 0.47, 1.0), 0.92)
    sclera = make_mat("HeroEye", (0.92, 0.93, 0.95, 1.0), 0.55)
    cloth = make_mat("HeroCloth", (0.44, 0.30, 0.16, 1.0), 0.84)
    dark_cloth = make_mat("HeroClothDark", (0.18, 0.11, 0.08, 1.0), 0.88)
    hair = make_mat("HeroHair", (0.15, 0.10, 0.08, 1.0), 0.75)
    boot = make_mat("HeroBoot", (0.19, 0.13, 0.10, 1.0), 0.85)
    ground = make_mat("Ground", (0.48, 0.64, 0.41, 1.0), 1.0)

    root = bpy.data.objects.new("HeroBase", None)
    bpy.context.collection.objects.link(root)

    # Long overlapping trunk masses avoid the segmented "stack of spheres"
    # contour while preserving explicit control over chest, waist, and pelvis.
    # Keep the lower abdomen from projecting as a separate round dome. Shift
    # these masses slightly rearward and reduce front-to-back depth while
    # preserving the hip width needed to meet the thighs.
    hips = add_uv_sphere("Hips", (0.0, 0.018, 0.158), (0.145, 0.075, 0.148), skin)
    pelvis = add_uv_sphere("Pelvis", (0.0, 0.024, 0.270), (0.142, 0.074, 0.152), skin)
    waist = add_uv_sphere("Waist", (0.0, 0.026, 0.386), (0.116, 0.069, 0.154), skin)
    abdomen = add_uv_sphere("Abdomen", (0.0, 0.032, 0.494), (0.128, 0.080, 0.164), skin)
    ribcage = add_uv_sphere("Ribcage", (0.0, 0.044, 0.592), (0.162, 0.098, 0.196), skin)
    chest = add_uv_sphere("Chest", (0.0, 0.044, 0.674), (0.176, 0.104, 0.184), skin)
    upper_chest = add_uv_sphere("UpperChest", (0.0, 0.030, 0.735), (0.164, 0.092, 0.105), skin)
    sternum = add_capsule("Sternum", (0.0, 0.076, 0.614), (0.012, 0.022, 0.078), skin, z_offset=0.118)
    chest_side_l = add_capsule("ChestSide.L", (-0.118, 0.074, 0.620), (0.018, 0.028, 0.078), skin, z_offset=0.104)
    chest_side_r = add_capsule("ChestSide.R", (0.118, 0.074, 0.620), (0.018, 0.028, 0.078), skin, z_offset=0.104)
    lat_l = add_capsule("Lat.L", (-0.108, 0.044, 0.518), (0.026, 0.034, 0.110), skin, z_offset=0.114)
    lat_r = add_capsule("Lat.R", (0.108, 0.044, 0.518), (0.026, 0.034, 0.110), skin, z_offset=0.114)
    torso_plane = add_capsule("TorsoPlane", (0.0, 0.048, 0.548), (0.026, 0.016, 0.132), skin, z_offset=0.100)
    sternum_plane = add_capsule("SternumPlane", (0.0, 0.062, 0.612), (0.008, 0.010, 0.036), skin, z_offset=0.090)
    clavicle = add_capsule("Clavicle", (0.0, -0.004, 0.792), (0.040, 0.026, 0.176), skin, z_offset=0.048)
    clavicle.rotation_euler = (0.0, radians(90), 0.0)
    neck = add_cone(
        "Neck", (0.0, 0.002, 0.842), (0.070, 0.061, 0.075), skin, vertices=48, taper=0.84
    )
    head = add_uv_sphere_rot(
        "Head",
        (0.0, -0.004, 1.002),
        (0.125, 0.120, 0.150),
        (0.0, 0.0, 0.0),
        skin,
        segments=48,
        rings=24,
    )
    sculpt_head_mesh_clean(head)
    eye_l = add_uv_sphere_rot(
        "Eye.L",
        (-0.046, -0.127, 1.010),
        (0.015, 0.008, 0.009),
        (0.0, 0.0, 0.0),
        sclera,
        segments=24,
        rings=12,
    )
    eye_r = add_uv_sphere_rot(
        "Eye.R",
        (0.046, -0.127, 1.010),
        (0.015, 0.008, 0.009),
        (0.0, 0.0, 0.0),
        sclera,
        segments=24,
        rings=12,
    )
    ear_l = add_uv_sphere_rot(
        "Ear.L",
        (-0.139, -0.002, 1.091),
        (0.012, 0.014, 0.030),
        (0.0, radians(90), 0.0),
        skin,
        segments=18,
        rings=10,
    )
    ear_r = add_uv_sphere_rot(
        "Ear.R",
        (0.139, -0.002, 1.091),
        (0.012, 0.014, 0.030),
        (0.0, radians(-90), 0.0),
        skin,
        segments=18,
        rings=10,
    )

    # Sink the shoulder girdle and upper arms into each other deeply.  The old
    # layout left a visible shelf at the deltoid/arm junction and read as a set
    # of attached cylinders instead of an arm growing out of the ribcage.
    left_shoulder = add_uv_sphere("Shoulder.L", (-0.158, 0.024, 0.680), (0.048, 0.046, 0.062), skin)
    right_shoulder = add_uv_sphere("Shoulder.R", (0.158, 0.024, 0.680), (0.048, 0.046, 0.062), skin)
    left_armpit = add_ico_sphere("Armpit.L", (-0.151, 0.024, 0.620), (0.042, 0.034, 0.046), skin)
    right_armpit = add_ico_sphere("Armpit.R", (0.151, 0.024, 0.620), (0.042, 0.034, 0.046), skin)
    left_deltoid = add_uv_sphere("Deltoid.L", (-0.158, 0.022, 0.620), (0.056, 0.046, 0.108), skin, segments=32, rings=20)
    right_deltoid = add_uv_sphere("Deltoid.R", (0.158, 0.022, 0.620), (0.056, 0.046, 0.108), skin, segments=32, rings=20)
    left_deltoid.rotation_euler = (radians(180), radians(-4), radians(3))
    right_deltoid.rotation_euler = (radians(180), radians(4), radians(-3))
    left_socket = add_capsule("Socket.L", (-0.162, 0.004, 0.646), (0.022, 0.012, 0.056), skin, z_offset=0.068)
    right_socket = add_capsule("Socket.R", (0.162, 0.004, 0.646), (0.022, 0.012, 0.056), skin, z_offset=0.068)
    left_trap = add_capsule("Trap.L", (-0.062, -0.010, 0.776), (0.048, 0.022, 0.066), skin, z_offset=0.074)
    right_trap = add_capsule("Trap.R", (0.062, -0.010, 0.776), (0.048, 0.022, 0.066), skin, z_offset=0.074)
    clavicle_l = add_capsule("Clavicle.L", (-0.090, 0.002, 0.734), (0.028, 0.012, 0.086), skin, z_offset=0.046)
    clavicle_r = add_capsule("Clavicle.R", (0.090, 0.002, 0.734), (0.028, 0.012, 0.086), skin, z_offset=0.046)
    clavicle_l.rotation_euler = (0.0, radians(90), radians(12))
    clavicle_r.rotation_euler = (0.0, radians(90), radians(-12))

    # Ellipsoids give the relaxed arm a continuous muscular taper. Cone caps
    # survived remeshing as horizontal ledges at the deltoid and elbow.
    left_upper_arm = add_uv_sphere("UpperArm.L", (-0.169, 0.023, 0.498), (0.046, 0.040, 0.164), skin, segments=32, rings=20)
    right_upper_arm = add_uv_sphere("UpperArm.R", (0.169, 0.023, 0.498), (0.046, 0.040, 0.164), skin, segments=32, rings=20)
    left_upper_arm.rotation_euler = (radians(179), radians(-5), radians(4))
    right_upper_arm.rotation_euler = (radians(181), radians(5), radians(-4))
    left_elbow = add_ico_sphere("Elbow.L", (-0.180, 0.028, 0.370), (0.027, 0.027, 0.028), skin)
    right_elbow = add_ico_sphere("Elbow.R", (0.180, 0.028, 0.370), (0.027, 0.027, 0.028), skin)
    left_forearm = add_uv_sphere("Forearm.L", (-0.180, 0.030, 0.246), (0.040, 0.034, 0.140), skin, segments=32, rings=20)
    right_forearm = add_uv_sphere("Forearm.R", (0.180, 0.030, 0.246), (0.040, 0.034, 0.140), skin, segments=32, rings=20)
    left_forearm.rotation_euler = (radians(178), radians(-1), radians(3))
    right_forearm.rotation_euler = (radians(182), radians(1), radians(-3))
    left_wrist = add_ico_sphere("Wrist.L", (-0.184, 0.038, 0.126), (0.030, 0.026, 0.030), skin)
    right_wrist = add_ico_sphere("Wrist.R", (0.184, 0.038, 0.126), (0.030, 0.026, 0.030), skin)
    left_hand = add_uv_sphere("Hand.L", (-0.180, 0.034, 0.052), (0.030, 0.023, 0.062), skin, segments=28, rings=18)
    right_hand = add_uv_sphere("Hand.R", (0.180, 0.034, 0.052), (0.030, 0.023, 0.062), skin, segments=28, rings=18)
    left_hand.rotation_euler = (radians(180), radians(-2), radians(2))
    right_hand.rotation_euler = (radians(180), radians(2), radians(-2))
    left_thumb = add_uv_sphere("Thumb.L", (-0.155, 0.020, 0.064), (0.014, 0.016, 0.034), skin, segments=20, rings=12)
    right_thumb = add_uv_sphere("Thumb.R", (0.155, 0.020, 0.064), (0.014, 0.016, 0.034), skin, segments=20, rings=12)
    left_thumb.rotation_euler = (radians(178), radians(-18), radians(-8))
    right_thumb.rotation_euler = (radians(182), radians(18), radians(8))

    # Rounded limb masses replace the capped cones that left hard horizontal
    # shelves at the groin and knees. Their overlap preserves a continuous leg
    # while still narrowing naturally toward each joint.
    left_thigh = add_uv_sphere("Thigh.L", (-0.078, 0.006, -0.106), (0.068, 0.056, 0.236), skin, segments=40, rings=24)
    right_thigh = add_uv_sphere("Thigh.R", (0.084, 0.008, -0.106), (0.068, 0.056, 0.236), skin, segments=40, rings=24)
    left_thigh.rotation_euler = (radians(180), radians(3.0), radians(-1.5))
    right_thigh.rotation_euler = (radians(180), radians(-3.0), radians(1.5))
    # These are bridging volumes, not visible ball joints. Keep them inside the
    # pelvis and limb envelopes so the final remesh forms shallow transitions.
    left_hip_joint = add_ico_sphere("HipJoint.L", (-0.072, 0.010, 0.032), (0.038, 0.037, 0.050), skin)
    right_hip_joint = add_ico_sphere("HipJoint.R", (0.076, 0.012, 0.032), (0.038, 0.037, 0.050), skin)
    left_knee = add_ico_sphere("Knee.L", (-0.084, 0.016, -0.326), (0.028, 0.031, 0.029), skin)
    right_knee = add_ico_sphere("Knee.R", (0.090, 0.018, -0.326), (0.028, 0.031, 0.029), skin)
    left_calf = add_uv_sphere("Calf.L", (-0.079, 0.024, -0.478), (0.052, 0.046, 0.190), skin, segments=40, rings=24)
    right_calf = add_uv_sphere("Calf.R", (0.085, 0.026, -0.478), (0.052, 0.046, 0.190), skin, segments=40, rings=24)
    left_calf.rotation_euler = (radians(179), radians(2.0), 0.0)
    right_calf.rotation_euler = (radians(181), radians(-2.0), 0.0)
    left_ankle = add_ico_sphere("Ankle.L", (-0.074, 0.030, -0.654), (0.031, 0.029, 0.035), skin)
    right_ankle = add_ico_sphere("Ankle.R", (0.080, 0.032, -0.654), (0.031, 0.029, 0.035), skin)
    # The face points toward negative Y, so the toes must project toward
    # negative Y as well. Positive offsets made both feet point backward.
    left_foot = add_capsule("Foot.L", (-0.080, -0.104, -0.722), (0.052, 0.108, 0.034), boot, z_offset=0.58)
    right_foot = add_capsule("Foot.R", (0.086, -0.108, -0.722), (0.052, 0.108, 0.034), boot, z_offset=0.58)

    # Overlapping ellipsoids produce a tapered, body-following tunic. Cylindrical
    # capsules made the chest read as a rigid rectangular slab after remeshing.
    shirt = add_uv_sphere("Shirt", (0.0, -0.018, 0.450), (0.178, 0.118, 0.330), cloth, segments=48, rings=32)
    shirt_hem = add_uv_sphere("ShirtHem", (0.0, 0.030, 0.410), (0.142, 0.080, 0.126), cloth)
    shirt_side_l = add_uv_sphere("ShirtSide.L", (-0.108, 0.034, 0.492), (0.050, 0.076, 0.116), cloth)
    shirt_side_r = add_uv_sphere("ShirtSide.R", (0.108, 0.034, 0.492), (0.050, 0.076, 0.116), cloth)
    loin_front = add_cone("LoinFront", (0.0, 0.050, 0.102), (0.036, 0.010, 0.030), cloth, vertices=20)
    loin_front.rotation_euler = (radians(90), 0.0, 0.0)
    loin_back = add_cone("LoinBack", (0.0, 0.020, 0.094), (0.018, 0.006, 0.018), cloth, vertices=20)
    loin_back.rotation_euler = (radians(90), 0.0, 0.0)
    belt = add_capsule("Belt", (0.0, 0.024, 0.154), (0.126, 0.010, 0.010), dark_cloth, z_offset=0.06)
    belt.rotation_euler = (0.0, radians(90), 0.0)
    chest_wrap = add_capsule("ChestWrap", (0.0, 0.064, 0.618), (0.160, 0.020, 0.026), dark_cloth, z_offset=0.094)
    chest_wrap.rotation_euler = (0.0, radians(90), 0.0)
    sleeve_l = add_cone("Sleeve.L", (-0.205, 0.026, 0.606), (0.064, 0.050, 0.082), cloth, vertices=24)
    sleeve_r = add_cone("Sleeve.R", (0.205, 0.026, 0.606), (0.064, 0.050, 0.082), cloth, vertices=24)
    bracer_l = add_capsule("Bracer.L", (-0.198, 0.044, 0.200), (0.040, 0.036, 0.052), dark_cloth, z_offset=0.68)
    bracer_r = add_capsule("Bracer.R", (0.198, 0.044, 0.200), (0.040, 0.036, 0.052), dark_cloth, z_offset=0.68)
    boot_l = add_cone("Boot.L", (-0.076, -0.044, -0.692), (0.040, 0.036, 0.052), dark_cloth, vertices=24, taper=0.78)
    boot_r = add_cone("Boot.R", (0.076, -0.044, -0.692), (0.040, 0.036, 0.052), dark_cloth, vertices=24, taper=0.78)
    hair_cap = add_uv_sphere_rot(
        "HairCap",
        (0.0, 0.004, 1.180),
        (0.132, 0.117, 0.034),
        (radians(5), 0.0, 0.0),
        hair,
    )
    hair_cap.hide_render = True
    floor = add_plane("Floor", (0.0, 0.0, -1.24), (3.0, 3.0, 1.0), ground)

    for obj in [clavicle, upper_chest, sternum, left_deltoid, right_deltoid, left_trap, right_trap, shirt, shirt_hem, shirt_side_l, shirt_side_r, sleeve_l, sleeve_r, boot_l, boot_r, belt, chest_wrap, bracer_l, bracer_r]:
        soften_object(obj, factor=0.28, iterations=10)

    for block_form in [clavicle, torso_plane, sternum_plane, chest_side_l, chest_side_r, left_socket, right_socket, clavicle_l, clavicle_r]:
        block_form.hide_render = True

    body_core = join_objects("BodyCore", [
        hips, pelvis, waist, abdomen, ribcage, chest, upper_chest, sternum,
        lat_l, lat_r,
        left_shoulder, right_shoulder, left_armpit, right_armpit, left_trap, right_trap
    ])
    voxel_remesh(body_core, voxel_size=0.016, smooth_passes=30)
    body_core.data.materials.clear()
    body_core.data.materials.append(skin)

    left_arm = join_objects("Arm.L", [left_deltoid, left_upper_arm, left_elbow, left_forearm, left_wrist, left_hand, left_thumb])
    voxel_remesh(left_arm, voxel_size=0.016, smooth_passes=20)
    left_arm.data.materials.clear()
    left_arm.data.materials.append(skin)

    right_arm = join_objects("Arm.R", [right_deltoid, right_upper_arm, right_elbow, right_forearm, right_wrist, right_hand, right_thumb])
    voxel_remesh(right_arm, voxel_size=0.016, smooth_passes=20)
    right_arm.data.materials.clear()
    right_arm.data.materials.append(skin)
    left_leg = join_objects("Leg.L", [left_hip_joint, left_thigh, left_knee, left_calf, left_ankle])
    right_leg = join_objects("Leg.R", [right_hip_joint, right_thigh, right_knee, right_calf, right_ankle])
    # Resolve the leg primitives as continuous limbs before the final whole-body
    # remesh. Without this pass, cone ends survived as hard ledges at the knees.
    voxel_remesh(left_leg, voxel_size=0.016, smooth_passes=14)
    left_leg.data.materials.clear()
    left_leg.data.materials.append(skin)
    voxel_remesh(right_leg, voxel_size=0.016, smooth_passes=14)
    right_leg.data.materials.clear()
    right_leg.data.materials.append(skin)

    # Resolve the head independently at facial resolution. Folding it into the
    # whole-body remesh both blurred the face and made local facial masks land
    # on the abdomen because SkinBody retained the hips object's transform.
    bpy.context.view_layer.objects.active = neck
    neck.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    head_core = join_objects("HeadCore", [neck, head])
    bpy.context.view_layer.objects.active = head_core
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    voxel_remesh(head_core, voxel_size=0.003, smooth_passes=2)
    refine_clean_face_after_remesh(head_core)
    head_core.data.materials.clear()
    head_core.data.materials.append(skin)

    skin_body = join_objects("SkinBody", [
        body_core,
        left_arm, right_arm,
        left_leg, right_leg,
    ])
    # Preserve the facial planes after the broad body forms have already been
    # smoothed independently; the prior coarse final remesh blurred the eyes,
    # nose, and lips back into a mask.
    voxel_remesh(skin_body, voxel_size=0.012, smooth_passes=2)
    skin_body.data.materials.clear()
    skin_body.data.materials.append(skin)

    # Keep the tunic as one continuous authored surface. Remeshing the earlier
    # multi-part shell created holes and rectangular cutouts.
    shirt.name = "ShirtShell"
    shirt_shell = shirt
    shirt_hem.hide_render = True
    shirt_side_l.hide_render = True
    shirt_side_r.hide_render = True

    # Keep the proportion study readable. These small costume blocks can return
    # after the body silhouette is established; at this stage they obscure the
    # abdomen and create false gaps in the shoulder/waist read.
    loin_front.hide_render = True
    loin_back.hide_render = True
    chest_wrap.hide_render = True
    ear_l.hide_render = True
    ear_r.hide_render = True
    eye_l.hide_render = True
    eye_r.hide_render = True
    sleeve_l.hide_render = True
    sleeve_r.hide_render = True
    bracer_l.hide_render = True
    bracer_r.hide_render = True
    belt.hide_render = True
    shirt_shell.hide_render = True

    parent_many(root, [
        skin_body,
        head_core,
        eye_l, eye_r,
        shirt_shell, sleeve_l, sleeve_r, bracer_l, bracer_r, boot_l, boot_r,
        loin_front, loin_back, belt, chest_wrap, hair_cap,
    ])
    floor.parent = root

    # Clean stage for modeling
    bpy.ops.object.light_add(type="SUN", location=(2.0, -2.0, 4.0))
    sun = bpy.context.active_object
    sun.data.energy = 2.4
    sun.rotation_euler = (radians(42), radians(0), radians(32))

    bpy.ops.object.camera_add(location=(0.0, -5.2, 0.52), rotation=(radians(83), 0.0, 0.0))
    cam = bpy.context.active_object
    cam.rotation_euler = (radians(82), 0.0, 0.0)
    cam.data.lens = 55
    bpy.context.scene.camera = cam

    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    screen = getattr(bpy.context, "screen", None)
    if screen:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.shading.type = "MATERIAL"
                        break


def save_blend():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    blend_dir = os.path.abspath(os.path.join(script_dir, ".."))
    blend_path = os.path.join(blend_dir, "hero_base.blend")
    backup_path = blend_path + "@"
    temp_path = os.path.join(blend_dir, "hero_base_tmp.blend")
    status_path = os.path.join(blend_dir, "build_status.json")
    if os.path.exists(backup_path):
        try:
            os.remove(backup_path)
        except OSError:
            pass
    if os.path.exists(temp_path):
        try:
            os.remove(temp_path)
        except OSError:
            pass
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=temp_path, copy=False)
    if os.path.exists(backup_path):
        try:
            os.remove(backup_path)
        except OSError:
            pass
    promoted = False
    active_path = temp_path
    error = None
    try:
        if os.path.exists(blend_path):
            os.replace(temp_path, blend_path)
        else:
            os.rename(temp_path, blend_path)
        promoted = True
        active_path = blend_path
    except OSError as exc:
        error = str(exc)
    status = {
        "promoted": promoted,
        "active_blend_path": active_path,
        "live_blend_path": blend_path,
        "temp_blend_path": temp_path,
        "error": error,
    }
    with open(status_path, "w", encoding="utf-8") as f:
        json.dump(status, f, indent=2)
    if promoted:
        print(f"Saved hero base blend to: {blend_path}")
    else:
        print(f"Saved hero base blend to temp only: {temp_path}")
        print(f"Promotion skipped: {error}")
    print(f"Build status written to: {status_path}")


if __name__ == "__main__":
    build_body()
    save_blend()
