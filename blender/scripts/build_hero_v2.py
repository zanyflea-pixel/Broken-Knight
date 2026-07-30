"""Build Broken Knight hero v2 from explicit anatomical lofts and quad topology."""

import bpy
import bmesh
import os
from math import cos, exp, pi, radians, sin
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
OUTPUT_PATH = os.path.join(BLEND_DIR, "hero_v2.blend")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def material(name, color, roughness=0.82):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def mesh_object(name, vertices, faces, mat, subdivision=1):
    mesh = bpy.data.meshes.new(f"{name}.Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    if subdivision:
        modifier = obj.modifiers.new("AnatomySubdivision", "SUBSURF")
        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = subdivision
        modifier.render_levels = subdivision
    return obj


def capped_faces(ring_count, sides):
    faces = []
    for ring in range(ring_count - 1):
        a = ring * sides
        b = (ring + 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((a + side, a + nxt, b + nxt, b + side))
    faces.append(tuple(reversed(tuple(range(sides)))))
    start = (ring_count - 1) * sides
    faces.append(tuple(start + side for side in range(sides)))
    return faces


def create_vertical_loft(name, rings, mat, sides=20, subdivision=2):
    """Rings: (z, center_x, center_y, radius_x, radius_y)."""
    vertices = []
    for z, cx, cy, rx, ry in rings:
        for side in range(sides):
            angle = 2.0 * pi * side / sides
            vertices.append((cx + rx * cos(angle), cy + ry * sin(angle), z))
    return mesh_object(name, vertices, capped_faces(len(rings), sides), mat, subdivision)


def create_path_limb(name, points, mat, sides=16, subdivision=2):
    """Points: ((x,y,z), lateral_radius, depth_radius)."""
    vertices = []
    centers = [Vector(item[0]) for item in points]
    for index, (center, rx, ry) in enumerate(zip(centers, [p[1] for p in points], [p[2] for p in points])):
        if index == 0:
            tangent = centers[1] - center
        elif index == len(centers) - 1:
            tangent = center - centers[index - 1]
        else:
            tangent = centers[index + 1] - centers[index - 1]
        tangent.normalize()
        lateral = Vector((tangent.z, 0.0, -tangent.x))
        if lateral.length < 0.001:
            lateral = Vector((1.0, 0.0, 0.0))
        lateral.normalize()
        depth = tangent.cross(lateral).normalized()
        for side in range(sides):
            angle = 2.0 * pi * side / sides
            co = center + lateral * (rx * cos(angle)) + depth * (ry * sin(angle))
            vertices.append(tuple(co))
    return mesh_object(name, vertices, capped_faces(len(points), sides), mat, subdivision)


def create_foot(name, x, mat, sides=16):
    # Longitudinal rings deliberately put the toes toward negative Y.
    rings = [
        (0.075, 0.105, 0.060, 0.050),
        (0.025, 0.095, 0.075, 0.060),
        (-0.075, 0.085, 0.095, 0.065),
        (-0.175, 0.075, 0.085, 0.055),
        (-0.230, 0.060, 0.045, 0.035),
    ]
    vertices = []
    for y, z, rx, rz in rings:
        for side in range(sides):
            angle = 2.0 * pi * side / sides
            vertices.append((x + rx * cos(angle), y, z + rz * sin(angle)))
    return mesh_object(name, vertices, capped_faces(len(rings), sides), mat, subdivision=2)


def gaussian(value, center, width):
    return exp(-((value - center) / width) ** 2)


def add_scaled_sphere(name, location, scale, mat, segments=32, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=1.0, location=location
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def create_hair_cap(mat):
    cap = add_scaled_sphere(
        "Hair", (0.0, -0.001, 1.897), (0.115, 0.100, 0.145), mat, 48, 28
    )
    bm = bmesh.new()
    bm.from_mesh(cap.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.012], context="VERTS")
    bm.to_mesh(cap.data)
    bm.free()
    return cap


def create_head(skin, eye_white, iris, lip):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=64,
        ring_count=40,
        radius=1.0,
        location=(0.0, -0.004, 1.884),
    )
    head = bpy.context.active_object
    head.name = "Head"
    head.scale = (0.112, 0.096, 0.145)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    head.data.materials.append(skin)

    bm = bmesh.new()
    bm.from_mesh(head.data)
    for vert in bm.verts:
        x, y, z = vert.co.x, vert.co.y, vert.co.z
        front = max(0.0, min(1.0, (-0.015 - y) / 0.080))

        if z > 0.065:
            crown = min(1.0, (z - 0.065) / 0.080)
            vert.co.z -= 0.007 * crown
            vert.co.x *= 1.0 - 0.035 * crown
        if z < -0.035:
            jaw = min(1.0, (-z - 0.035) / 0.105)
            vert.co.x *= 1.0 - 0.30 * jaw
            vert.co.y *= 1.0 - 0.08 * jaw
        if y > 0.0:
            rear = min(1.0, y / 0.112)
            vert.co.y *= 1.0 - 0.11 * rear

        if front <= 0.0:
            continue

        eyes = max(gaussian(x, -0.037, 0.022), gaussian(x, 0.037, 0.022))
        socket = eyes * gaussian(z, 0.014, 0.018)
        brow = eyes * gaussian(z, 0.036, 0.014)
        nose_bridge = gaussian(x, 0.0, 0.016) * gaussian(z, -0.010, 0.050)
        nose_tip = gaussian(x, 0.0, 0.023) * gaussian(z, -0.047, 0.018)
        cheeks = gaussian(abs(x), 0.055, 0.026) * gaussian(z, -0.035, 0.036)
        muzzle = gaussian(x, 0.0, 0.045) * gaussian(z, -0.073, 0.025)
        chin = gaussian(x, 0.0, 0.040) * gaussian(z, -0.116, 0.018)

        vert.co.y += 0.006 * front * socket
        vert.co.y -= 0.004 * front * brow
        vert.co.y -= 0.019 * front * nose_bridge
        vert.co.y -= 0.026 * front * nose_tip
        vert.co.y -= 0.004 * front * cheeks
        vert.co.y -= 0.006 * front * muzzle
        vert.co.y -= 0.005 * front * chin

    bm.to_mesh(head.data)
    bm.free()
    for poly in head.data.polygons:
        poly.use_smooth = True
    subdivision = head.modifiers.new("HeadSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1

    # Embedded eyes and ears establish readable landmarks without changing the head silhouette.
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        add_scaled_sphere(
            f"Eye.{suffix}", (0.037 * side, -0.091, 1.898),
            (0.015, 0.007, 0.007), eye_white, 28, 16
        )
        add_scaled_sphere(
            f"Iris.{suffix}", (0.037 * side, -0.100, 1.898),
            (0.0045, 0.0025, 0.0045), iris, 24, 14
        )
        add_scaled_sphere(
            f"Ear.{suffix}", (0.105 * side, -0.001, 1.880),
            (0.014, 0.010, 0.029), skin, 24, 14
        )

    # A shallow horizontal lip line avoids the vertical crater produced by the rejected pass.
    curve_data = bpy.data.curves.new("MouthLine.Curve", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.bevel_depth = 0.0017
    curve_data.bevel_resolution = 3
    spline = curve_data.splines.new("BEZIER")
    spline.bezier_points.add(2)
    for point, co in zip(spline.bezier_points, [(-0.030, -0.095, 1.814), (0.0, -0.099, 1.810), (0.030, -0.095, 1.814)]):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    mouth = bpy.data.objects.new("MouthLine", curve_data)
    bpy.context.collection.objects.link(mouth)
    mouth.data.materials.append(lip)

    # Low, straight brows pull the expression away from the rejected doll-like stare.
    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        brow_data = bpy.data.curves.new(f"Brow.{suffix}.Curve", type="CURVE")
        brow_data.dimensions = "3D"
        brow_data.bevel_depth = 0.0019
        brow_data.bevel_resolution = 2
        brow_spline = brow_data.splines.new("POLY")
        brow_spline.points.add(2)
        xs = [0.022, 0.037, 0.052]
        for p, x, z in zip(brow_spline.points, xs, [1.916, 1.920, 1.917]):
            p.co = (x * side, -0.094, z, 1.0)
        brow_obj = bpy.data.objects.new(f"Brow.{suffix}", brow_data)
        bpy.context.collection.objects.link(brow_obj)
        brow_obj.data.materials.append(iris)

    create_hair_cap(iris)
    return head


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build():
    clear_scene()
    skin = material("HeroV2Skin", (0.55, 0.31, 0.20, 1.0), 0.88)
    eye_white = material("EyeWhite", (0.72, 0.70, 0.63, 1.0), 0.62)
    iris = material("Iris", (0.045, 0.030, 0.020, 1.0), 0.55)
    lip = material("Lip", (0.24, 0.075, 0.055, 1.0), 0.78)
    cloth = material("TunicCloth", (0.055, 0.105, 0.125, 1.0), 0.92)
    trousers = material("Trousers", (0.095, 0.085, 0.075, 1.0), 0.96)
    leather = material("WornLeather", (0.12, 0.052, 0.026, 1.0), 0.84)
    belt_metal = material("BeltMetal", (0.22, 0.20, 0.16, 1.0), 0.48)
    ground = material("HeroV2Ground", (0.12, 0.14, 0.12, 1.0), 1.0)

    torso = create_vertical_loft("Torso", [
        (0.91, 0.0, 0.008, 0.205, 0.135),
        (1.00, 0.0, 0.004, 0.218, 0.143),
        (1.10, 0.0, 0.000, 0.178, 0.120),
        (1.22, 0.0, -0.004, 0.184, 0.130),
        (1.35, 0.0, -0.010, 0.218, 0.150),
        (1.47, 0.0, -0.010, 0.250, 0.158),
        (1.56, 0.0, -0.006, 0.270, 0.150),
        (1.62, 0.0, 0.000, 0.220, 0.125),
    ], skin, sides=24, subdivision=2)

    create_vertical_loft("Neck", [
        (1.59, 0.0, 0.000, 0.095, 0.082),
        (1.68, 0.0, -0.002, 0.072, 0.065),
        (1.76, 0.0, -0.004, 0.070, 0.062),
    ], skin, sides=20, subdivision=2)

    # Pelvis bridges the torso and thigh roots so the body reads as one mass.
    create_vertical_loft("Pelvis", [
        (0.88, 0.0, 0.010, 0.180, 0.120),
        (0.94, 0.0, 0.008, 0.215, 0.140),
        (1.01, 0.0, 0.004, 0.220, 0.145),
        (1.07, 0.0, 0.000, 0.190, 0.128),
    ], skin, sides=24, subdivision=2)

    # A fitted sleeveless jerkin exposes the body proportions while making this a hero blockout.
    create_vertical_loft("Jerkin", [
        (0.96, 0.0, 0.006, 0.212, 0.142),
        (1.08, 0.0, 0.000, 0.185, 0.127),
        (1.22, 0.0, -0.004, 0.192, 0.137),
        (1.36, 0.0, -0.010, 0.226, 0.157),
        (1.48, 0.0, -0.008, 0.255, 0.166),
        (1.55, 0.0, -0.004, 0.263, 0.156),
    ], cloth, sides=24, subdivision=2)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.204, minor_radius=0.018, major_segments=40,
                                    minor_segments=10, location=(0.0, 0.0, 0.985))
    belt = bpy.context.active_object
    belt.name = "Belt"
    belt.data.materials.append(leather)
    add_scaled_sphere("BeltBuckle", (0.0, -0.148, 0.985), (0.030, 0.010, 0.026), belt_metal, 20, 12)

    for side, suffix in [(-1.0, "L"), (1.0, "R")]:
        x = 0.135 * side
        create_path_limb(f"Leg.{suffix}", [
            ((x, 0.010, 1.01), 0.120, 0.128),
            ((x + 0.012 * side, 0.000, 0.86), 0.112, 0.120),
            ((x + 0.006 * side, -0.006, 0.68), 0.095, 0.105),
            ((x, 0.000, 0.53), 0.074, 0.082),
            ((x - 0.004 * side, 0.020, 0.40), 0.084, 0.098),
            ((x, 0.025, 0.25), 0.068, 0.078),
            ((x, 0.020, 0.125), 0.056, 0.064),
        ], skin, sides=18, subdivision=2)
        create_path_limb(f"Trouser.{suffix}", [
            ((x, 0.008, 1.00), 0.126, 0.133),
            ((x + 0.010 * side, 0.000, 0.84), 0.116, 0.124),
            ((x + 0.006 * side, -0.004, 0.66), 0.098, 0.108),
            ((x, 0.002, 0.52), 0.078, 0.087),
            ((x, 0.015, 0.43), 0.081, 0.092),
        ], trousers, sides=18, subdivision=2)
        create_path_limb(f"Boot.{suffix}", [
            ((x, 0.018, 0.45), 0.087, 0.099),
            ((x, 0.022, 0.32), 0.079, 0.091),
            ((x, 0.020, 0.18), 0.068, 0.078),
            ((x, 0.018, 0.115), 0.061, 0.069),
        ], leather, sides=18, subdivision=2)
        create_foot(f"Foot.{suffix}", x, leather)

        shoulder_x = 0.252 * side
        create_path_limb(f"Arm.{suffix}", [
            ((shoulder_x, 0.000, 1.53), 0.100, 0.105),
            ((0.305 * side, 0.000, 1.42), 0.092, 0.097),
            ((0.350 * side, 0.006, 1.27), 0.076, 0.081),
            ((0.372 * side, 0.012, 1.12), 0.066, 0.071),
            ((0.385 * side, 0.018, 0.98), 0.071, 0.076),
            ((0.386 * side, 0.020, 0.83), 0.055, 0.061),
            ((0.383 * side, 0.018, 0.72), 0.045, 0.050),
            ((0.383 * side, 0.010, 0.66), 0.047, 0.043),
            ((0.386 * side, -0.002, 0.58), 0.052, 0.036),
            ((0.386 * side, -0.008, 0.51), 0.040, 0.030),
        ], skin, sides=18, subdivision=2)
        create_path_limb(f"Bracer.{suffix}", [
            ((0.385 * side, 0.019, 0.88), 0.060, 0.066),
            ((0.386 * side, 0.020, 0.78), 0.054, 0.061),
            ((0.383 * side, 0.018, 0.71), 0.049, 0.055),
        ], leather, sides=18, subdivision=2)

    create_head(skin, eye_white, iris, lip)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.name = "Floor"
    floor.data.materials.append(ground)

    bpy.ops.object.light_add(type="AREA", location=(-2.8, -4.0, 4.8))
    key = bpy.context.active_object
    key.name = "Key"
    key.data.energy = 650
    key.data.shape = "DISK"
    key.data.size = 4.0
    bpy.ops.object.light_add(type="AREA", location=(3.0, -1.0, 2.8))
    fill = bpy.context.active_object
    fill.name = "Fill"
    fill.data.energy = 260
    fill.data.size = 3.0
    bpy.ops.object.light_add(type="AREA", location=(0.0, 2.5, 3.5))
    rim = bpy.context.active_object
    rim.name = "Rim"
    rim.data.energy = 350
    rim.data.size = 3.0

    bpy.ops.object.camera_add(location=(0.0, -5.8, 1.10))
    camera = bpy.context.active_object
    camera.name = "HeroV2Camera"
    camera.data.lens = 68
    point_camera(camera, (0.0, 0.0, 1.05))
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.unit_settings.system = "METRIC"
    world = scene.world or bpy.data.worlds.new("HeroV2World")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.035, 0.040, 0.050, 1.0)
        background.inputs[1].default_value = 0.16

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_PATH, copy=False)
    print(f"Saved hero v2 to: {OUTPUT_PATH}")


if __name__ == "__main__":
    build()
