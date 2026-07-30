"""Build an isolated, disposable head study without touching hero_base.blend."""

import bpy
import bmesh
import importlib.util
import json
import os
from math import exp, radians


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
BASE_SCRIPT = os.path.join(SCRIPT_DIR, "build_hero_base.py")
OUTPUT_BLEND = os.path.join(BLEND_DIR, "hero_head_test.blend")
STATUS_PATH = os.path.join(BLEND_DIR, "head_test_status.json")


def load_base_module():
    spec = importlib.util.spec_from_file_location("broken_knight_hero_base", BASE_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mesh_components(bm):
    remaining = set(bm.verts)
    count = 0
    while remaining:
        count += 1
        seed = remaining.pop()
        stack = [seed]
        while stack:
            vert = stack.pop()
            for edge in vert.link_edges:
                other = edge.other_vert(vert)
                if other in remaining:
                    remaining.remove(other)
                    stack.append(other)
    return count


def validate_head(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()

    boundary_edges = sum(1 for edge in bm.edges if edge.is_boundary)
    non_manifold_edges = sum(1 for edge in bm.edges if not edge.is_manifold)
    components = mesh_components(bm)
    vertex_count = len(bm.verts)
    face_count = len(bm.faces)
    world_coords = [obj.matrix_world @ vert.co for vert in bm.verts]
    xs = [co.x for co in world_coords]
    ys = [co.y for co in world_coords]
    zs = [co.z for co in world_coords]
    bounds = {
        "x": [min(xs), max(xs)],
        "y": [min(ys), max(ys)],
        "z": [min(zs), max(zs)],
    }
    bm.free()

    material_slots = len(obj.data.materials)
    checks = {
        "single_connected_surface": components == 1,
        "no_boundary_edges": boundary_edges == 0,
        "manifold": non_manifold_edges == 0,
        "single_material": material_slots == 1,
        "sufficient_resolution": vertex_count >= 800 and face_count >= 800,
        "sane_width": bounds["x"][0] > -0.30 and bounds["x"][1] < 0.30,
        "sane_depth": bounds["y"][0] > -0.30 and bounds["y"][1] < 0.30,
        "sane_height": bounds["z"][0] > 0.65 and bounds["z"][1] < 1.30,
    }
    return {
        "valid": all(checks.values()),
        "checks": checks,
        "metrics": {
            "vertices": vertex_count,
            "faces": face_count,
            "components": components,
            "boundary_edges": boundary_edges,
            "non_manifold_edges": non_manifold_edges,
            "material_slots": material_slots,
            "bounds": bounds,
        },
    }


def add_stage():
    bpy.ops.object.light_add(type="SUN", location=(2.0, -2.0, 4.0))
    sun = bpy.context.active_object
    sun.name = "HeadTestSun"
    sun.data.energy = 2.0
    sun.rotation_euler = (radians(42), 0.0, radians(32))

    bpy.ops.object.camera_add(location=(0.0, -1.55, 1.08))
    camera = bpy.context.active_object
    camera.name = "HeadTestCamera"
    camera.data.lens = 95
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def clean_sculpt_head(obj):
    """One coherent facial surface pass, kept isolated until visually approved."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Give the deformation enough source topology to form lids and lips before
    # the final voxel pass. This is cheap on a head and avoids pinched features.
    subdivision = obj.modifiers.new(name="FaceSourceSubdivision", type="SUBSURF")
    subdivision.subdivision_type = "SIMPLE"
    subdivision.levels = 2
    subdivision.render_levels = 2
    bpy.ops.object.modifier_apply(modifier=subdivision.name)

    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def gaussian(value, center, width):
        return exp(-((value - center) / width) ** 2)

    for vert in bm.verts:
        x, y, z = vert.co.x, vert.co.y, vert.co.z

        # Narrow the cranium slightly so the front silhouette reads as a head,
        # not a near-perfect circle.
        vert.co.x *= 0.965
        x = vert.co.x

        # Reduce the oversized posterior bowl while leaving the forehead and
        # authored facial planes alone. The smooth falloff preserves a readable
        # occiput instead of flattening the back of the head.
        rear = max(0.0, min(1.0, (y + 0.005) / 0.115))
        if rear > 0.0:
            vert.co.y *= 1.0 - 0.14 * rear
            y = vert.co.y

        temple_band = gaussian(z, 0.012, 0.034)
        parietal_band = gaussian(z, 0.072, 0.042)
        vert.co.x *= 1.0 - 0.026 * temple_band + 0.015 * parietal_band

        # Adult oval: modest temples, a tapered but present jaw, and a flatter
        # crown. Keep this broad so it changes silhouette rather than adding
        # small cosmetic noise.
        if z > 0.045:
            top = min(1.0, (z - 0.045) / 0.105)
            vert.co.z -= 0.016 * top
            vert.co.x *= 1.0 - 0.022 * top
        if z < -0.045:
            jaw = min(1.0, (-z - 0.045) / 0.105)
            vert.co.x *= 1.0 - 0.17 * jaw
            center_chin = gaussian(x, 0.0, 0.050)
            vert.co.z -= 0.004 * jaw * center_chin
        jaw_angle = gaussian(abs(x), 0.074, 0.032) * gaussian(z, -0.092, 0.034)
        vert.co.x *= 1.0 + 0.12 * jaw_angle

        # Only move the forward shell. Side and rear skull remain continuous.
        front = max(0.0, min(1.0, (-0.010 - y) / 0.095))
        if front <= 0.0:
            continue

        abs_x = abs(x)
        eye_l = gaussian(x, -0.043, 0.024)
        eye_r = gaussian(x, 0.043, 0.024)
        eyes = max(eye_l, eye_r)

        # Flatten the central facial plane gently, then stage features from it.
        facial_oval = gaussian(x, 0.0, 0.105) * gaussian(z, -0.035, 0.145)
        vert.co.y += 0.006 * front * facial_oval

        # Set the forehead slightly behind the supraorbital ridge so the upper
        # profile has an adult forehead/brow break instead of one spherical arc.
        forehead_plane = gaussian(x, 0.0, 0.090) * gaussian(z, 0.070, 0.050)
        vert.co.y += 0.0070 * front * forehead_plane

        # Brow and orbital bowl. The eye line is a shallow crease between two
        # lid rolls, not a punched hole or pasted-on eyeball.
        brow = eyes * gaussian(z, 0.018, 0.022)
        socket = eyes * gaussian(z, -0.006, 0.027)
        eye_line = eyes * gaussian(z, -0.012, 0.0055)
        upper_lid = eyes * gaussian(z, -0.004, 0.008)
        lower_lid = eyes * gaussian(z, -0.021, 0.008)
        vert.co.y -= 0.0065 * front * brow
        vert.co.y += 0.0080 * front * socket
        vert.co.y += 0.0048 * front * eye_line
        vert.co.y -= 0.0027 * front * upper_lid
        vert.co.y -= 0.0018 * front * lower_lid

        # A narrow bridge, readable tip, and small alar wings. Centers are
        # deliberately above the mouth so the nose no longer merges into it.
        bridge = gaussian(x, 0.0, 0.020) * gaussian(z, -0.025, 0.060)
        tip = gaussian(x, 0.0, 0.030) * gaussian(z, -0.073, 0.023)
        wings = gaussian(abs_x, 0.024, 0.013) * gaussian(z, -0.079, 0.015)
        nostrils = gaussian(abs_x, 0.021, 0.008) * gaussian(z, -0.084, 0.006)
        vert.co.y -= 0.029 * front * bridge
        vert.co.y -= 0.023 * front * tip
        vert.co.y -= 0.005 * front * wings
        vert.co.y += 0.003 * front * nostrils

        # Cheek planes bridge sockets into the muzzle and prevent the center
        # features from reading like chunks attached to a sphere.
        cheeks = gaussian(abs_x, 0.071, 0.035) * gaussian(z, -0.055, 0.050)
        vert.co.y -= 0.0045 * front * cheeks

        # Carry the mouth and chin forward as one broad lower-face plane. The
        # ellipsoid otherwise leaves the lips far behind the nose in profile.
        muzzle_support = gaussian(x, 0.0, 0.058) * gaussian(z, -0.106, 0.034)
        chin_support = gaussian(x, 0.0, 0.050) * gaussian(z, -0.142, 0.021)
        vert.co.y -= 0.014 * front * muzzle_support
        vert.co.y -= 0.006 * front * chin_support

        # Restrained neutral mouth with separate lip rolls and a supported chin.
        mouth_width = gaussian(x, 0.0, 0.036)
        mouth_line = mouth_width * gaussian(z, -0.108, 0.0045)
        upper_lip = mouth_width * gaussian(z, -0.100, 0.007)
        lower_lip = mouth_width * gaussian(z, -0.117, 0.008)
        philtrum = gaussian(x, 0.0, 0.012) * gaussian(z, -0.092, 0.013)
        mouth_corners = gaussian(abs_x, 0.034, 0.008) * gaussian(z, -0.108, 0.006)
        chin = gaussian(x, 0.0, 0.043) * gaussian(z, -0.143, 0.020)
        vert.co.y += 0.0022 * front * mouth_line
        vert.co.y += 0.0010 * front * mouth_corners
        vert.co.y -= 0.0020 * front * upper_lip
        vert.co.y -= 0.0017 * front * lower_lip
        vert.co.y += 0.0018 * front * philtrum
        vert.co.y -= 0.0045 * front * chin

    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.object.shade_smooth()
    return obj


def refine_face_after_remesh(obj):
    """Restore small anatomical breaks after the fine head voxel pass."""
    bpy.context.view_layer.objects.active = obj
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def gaussian(value, center, width):
        return exp(-((value - center) / width) ** 2)

    for vert in bm.verts:
        x, y, z_world = vert.co.x, vert.co.y, vert.co.z

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
        vert.co.y -= 0.0023 * front * brow
        vert.co.y -= 0.0020 * front * brow_arch
        vert.co.y -= 0.0010 * front * glabella
        vert.co.y -= 0.0018 * front * globe_support
        vert.co.y -= 0.0018 * front * upper_lid
        vert.co.y += 0.0050 * front * eye_crease
        vert.co.y -= 0.0015 * front * lower_lid
        vert.co.z += 0.0022 * front * upper_lid
        vert.co.z -= 0.0015 * front * lower_lid
        vert.co.y += 0.0010 * front * inner_corner
        vert.co.y += 0.0008 * front * outer_corner
        vert.co.z += 0.0020 * front * outer_corner_lift

        # Define the alar break without turning it into a separate dark patch.
        nostrils = gaussian(abs_x, 0.018, 0.0065) * gaussian(z, -0.084, 0.0045)
        nose_column = gaussian(x, 0.0, 0.013) * gaussian(z, -0.066, 0.030)
        nose_tip = gaussian(x, 0.0, 0.028) * gaussian(z, -0.073, 0.016)
        columella = gaussian(x, 0.0, 0.010) * gaussian(z, -0.087, 0.007)
        alar_break = gaussian(abs_x, 0.025, 0.007) * gaussian(z, -0.083, 0.008)
        alar_volume = gaussian(abs_x, 0.022, 0.012) * gaussian(z, -0.080, 0.014)
        lower_sidewall = gaussian(abs_x, 0.018, 0.014) * gaussian(z, -0.060, 0.026)
        vert.co.y += 0.0018 * front * nostrils
        vert.co.y -= 0.0008 * front * nose_column
        vert.co.y -= 0.0045 * front * nose_tip
        vert.co.y -= 0.0012 * front * columella
        vert.co.y += 0.0012 * front * alar_break
        side_sign = -1.0 if x < 0.0 else 1.0
        vert.co.x += side_sign * 0.0016 * front * alar_volume
        vert.co.x += side_sign * 0.0008 * front * lower_sidewall

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
        vert.co.y += 0.0032 * front * mouth_crease
        vert.co.y += 0.0012 * front * corners
        vert.co.y -= 0.0020 * front * upper_lip
        vert.co.y -= 0.0018 * front * lower_lip
        vert.co.z += 0.0010 * front * upper_lip
        vert.co.z -= 0.0010 * front * lower_lip
        vert.co.y += 0.0025 * front * chin_break
        vert.co.y -= 0.0014 * front * philtrum_columns
        vert.co.y += 0.0010 * front * philtrum_groove
        vert.co.y -= 0.0018 * front * cupid_peaks
        vert.co.y += 0.0010 * front * cupid_notch
        vert.co.y -= 0.0022 * front * lower_lip_center
        vert.co.y -= 0.0032 * front * chin_pad

        cheek_plane = gaussian(abs_x, 0.066, 0.030) * gaussian(z, -0.052, 0.036)
        mandibular_plane = gaussian(abs_x, 0.071, 0.028) * gaussian(z, -0.108, 0.030)
        nasolabial_transition = gaussian(abs_x, 0.038, 0.010) * gaussian(z, -0.092, 0.025)
        vert.co.y -= 0.0030 * front * cheek_plane
        vert.co.y += 0.0020 * front * mandibular_plane
        vert.co.y += 0.0012 * front * nasolabial_transition

        # Controlled natural asymmetry. Keep every offset near or below one
        # millimeter so the result feels authored rather than visibly skewed.
        left_brow_asym = gaussian(x, -0.043, 0.024) * gaussian(z, 0.014, 0.016)
        right_cheek_asym = gaussian(x, 0.064, 0.030) * gaussian(z, -0.055, 0.040)
        nose_asym = gaussian(x, 0.0, 0.024) * gaussian(z, -0.073, 0.020)
        left_mouth_asym = gaussian(x, -0.034, 0.010) * gaussian(z, -0.108, 0.009)
        vert.co.z += 0.0008 * front * left_brow_asym
        vert.co.y -= 0.0007 * front * right_cheek_asym
        vert.co.x += 0.0007 * front * nose_asym
        vert.co.z += 0.0005 * front * left_mouth_asym

    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.object.shade_smooth()
    return obj


def main():
    base = load_base_module()
    base.clear_scene()
    skin = base.make_mat("HeroSkin", (0.71, 0.57, 0.47, 1.0), roughness=0.92)

    neck = base.add_cone(
        "Neck", (0.0, 0.002, 0.842), (0.070, 0.061, 0.075), skin, vertices=48, taper=0.84
    )
    # add_capsule keeps its active cylinder's scale on the joined object. Apply
    # it before combining with the head so voxel size and validation bounds are
    # measured in actual scene units.
    bpy.context.view_layer.objects.active = neck
    neck.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    head = base.add_uv_sphere_rot(
        "Head",
        (0.0, -0.004, 1.002),
        (0.125, 0.120, 0.150),
        (0.0, 0.0, 0.0),
        skin,
        segments=48,
        rings=24,
    )
    clean_sculpt_head(head)
    head_test = base.join_objects("HeadTest", [neck, head])
    bpy.context.view_layer.objects.active = head_test
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Facial masks are only a few millimeters wide. A body-scale 12 mm voxel
    # turns eyelids and lips into isolated pinches; the isolated test can afford
    # the resolution the face actually needs without remeshing the full hero.
    base.voxel_remesh(head_test, voxel_size=0.003, smooth_passes=2)
    refine_face_after_remesh(head_test)
    head_test.data.materials.clear()
    head_test.data.materials.append(skin)

    result = validate_head(head_test)
    result["blend_path"] = OUTPUT_BLEND
    result["source_script"] = BASE_SCRIPT

    add_stage()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    with open(STATUS_PATH, "w", encoding="utf-8") as status_file:
        json.dump(result, status_file, indent=2)

    print(json.dumps(result, indent=2))
    if not result["valid"]:
        raise RuntimeError("Head test failed automatic mesh validation")


if __name__ == "__main__":
    main()
