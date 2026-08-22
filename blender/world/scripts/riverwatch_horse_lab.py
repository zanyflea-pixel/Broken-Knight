# V94_FIXED_PLANE_LIMB_GEOMETRY

import bpy
import bmesh
import importlib.util

from pathlib import Path
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
TUNING_FILE = Path(__file__).resolve().with_name("riverwatch_horse_tuning.py")
BLEND_FILE = ROOT / "blender" / "world" / "animals" / "riverwatch_horse.blend"
GLB_FILE = ROOT / "godot" / "assets" / "animals" / "riverwatch_horse.glb"


RING_12 = [
    (0.00, 1.00),
    (0.55, 0.90),
    (0.88, 0.55),
    (1.00, 0.15),
    (0.92, -0.35),
    (0.55, -0.82),
    (0.00, -1.00),
    (-0.55, -0.82),
    (-0.92, -0.35),
    (-1.00, 0.15),
    (-0.88, 0.55),
    (-0.55, 0.90),
]

RING_10 = [
    (0.00, 1.00),
    (0.59, 0.81),
    (0.95, 0.31),
    (0.95, -0.31),
    (0.59, -0.81),
    (0.00, -1.00),
    (-0.59, -0.81),
    (-0.95, -0.31),
    (-0.95, 0.31),
    (-0.59, 0.81),
]


def load_tuning():
    spec = importlib.util.spec_from_file_location(
        "riverwatch_horse_tuning_live",
        TUNING_FILE,
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
    ):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)


def make_material(name, color, roughness=0.72, metallic=0.0):
    material = bpy.data.materials.new(name=name)
    material.diffuse_color = color
    material.use_nodes = True

    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

    return material


def recalc_normals(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)

    if bm.faces:
        bmesh.ops.recalc_face_normals(
            bm,
            faces=list(bm.faces),
        )

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def smooth_object(obj):
    if obj.type != "MESH":
        return

    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def add_subdivision(obj, levels=1):
    modifier = obj.modifiers.new(
        "RiverwatchControlledSubdivision",
        "SUBSURF",
    )
    modifier.subdivision_type = "CATMULL_CLARK"
    modifier.levels = levels
    modifier.render_levels = levels


def add_bevel(obj, width, segments=2):
    modifier = obj.modifiers.new(
        "RiverwatchEdgeSoftening",
        "BEVEL",
    )
    modifier.width = width
    modifier.segments = segments


def mesh_object(
    name,
    vertices,
    faces,
    materials,
    root,
    region,
    smooth=True,
):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_normals(mesh)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    for material in materials:
        obj.data.materials.append(material)

    obj.parent = root
    obj["broken_knight_region"] = region

    if smooth:
        smooth_object(obj)

    return obj


def connect_rings(faces, ring_count, ring_size):
    for station_index in range(ring_count - 1):
        current = station_index * ring_size
        following = (station_index + 1) * ring_size

        for ring_index in range(ring_size):
            next_index = (ring_index + 1) % ring_size
            faces.append(
                (
                    current + ring_index,
                    current + next_index,
                    following + next_index,
                    following + ring_index,
                )
            )


def append_caps(faces, ring_count, ring_size):
    faces.append(tuple(reversed(range(ring_size))))

    last_start = (ring_count - 1) * ring_size
    faces.append(
        tuple(
            last_start + index
            for index in range(ring_size)
        )
    )


def fixed_y_loft(
    name,
    stations,
    materials,
    root,
    region,
    ring=RING_12,
    subdivide=True,
):
    vertices = []
    faces = []
    ring_size = len(ring)

    for station in stations:
        (
            y,
            center_z,
            half_width,
            top_depth,
            lower_depth,
            upper_width,
            lower_width,
        ) = station

        for x_normal, z_normal in ring:
            width_factor = upper_width if z_normal >= 0.0 else lower_width
            depth = top_depth if z_normal >= 0.0 else lower_depth

            vertices.append(
                (
                    x_normal * half_width * width_factor,
                    y,
                    center_z + z_normal * depth,
                )
            )

    connect_rings(
        faces,
        len(stations),
        ring_size,
    )

    append_caps(
        faces,
        len(stations),
        ring_size,
    )

    obj = mesh_object(
        name,
        vertices,
        faces,
        materials,
        root,
        region,
        True,
    )

    if subdivide:
        add_subdivision(obj, 1)

    return obj


def path_loft(
    name,
    stations,
    materials,
    root,
    region,
    ring=RING_12,
    subdivide=True,
):
    vertices = []
    faces = []
    ring_size = len(ring)

    centers = [
        Vector(
            (
                station[0],
                station[1],
                station[2],
            )
        )
        for station in stations
    ]

    for station_index, station in enumerate(stations):
        center = centers[station_index]

        if station_index == 0:
            tangent = centers[1] - centers[0]

        elif station_index == len(stations) - 1:
            tangent = centers[-1] - centers[-2]

        else:
            tangent = (
                centers[station_index + 1]
                - centers[station_index - 1]
            )

        if tangent.length < 0.00001:
            tangent = Vector((0.0, -1.0, 0.0))

        tangent.normalize()

        side = Vector((1.0, 0.0, 0.0))
        up = tangent.cross(side)

        if up.length < 0.00001:
            up = Vector((0.0, 0.0, 1.0))
        else:
            up.normalize()

        if up.z < 0.0:
            up = -up

        (
            x_center,
            y_center,
            z_center,
            half_width,
            upper_depth,
            lower_depth,
            upper_width,
            lower_width,
        ) = station

        for x_normal, z_normal in ring:
            width_factor = (
                upper_width
                if z_normal >= 0.0
                else lower_width
            )

            depth = (
                upper_depth
                if z_normal >= 0.0
                else lower_depth
            )

            point = (
                center
                + side
                * (
                    x_normal
                    * half_width
                    * width_factor
                )
                + up
                * (
                    z_normal
                    * depth
                )
            )

            vertices.append(tuple(point))

    connect_rings(
        faces,
        len(stations),
        ring_size,
    )

    append_caps(
        faces,
        len(stations),
        ring_size,
    )

    obj = mesh_object(
        name,
        vertices,
        faces,
        materials,
        root,
        region,
        True,
    )

    if subdivide:
        add_subdivision(obj, 1)

    return obj


def fixed_z_limb_loft(
    name,
    x_center,
    stations,
    materials,
    root,
    region,
    subdivide=True,
):
    """
    V94 limb construction.

    Every cross-section remains horizontal in Z instead of
    rotating to the local tangent. The limb centerline can move
    forward/backward through elbow, stifle, and hock without the
    cross-section itself becoming a diagonal wedge.
    """

    vertices = []
    faces = []
    ring_size = len(RING_10)

    for (
        y_center,
        z_center,
        half_width,
        half_depth,
    ) in stations:

        for x_normal, y_normal in RING_10:

            vertices.append(
                (
                    x_center
                    + x_normal
                    * half_width,

                    y_center
                    + y_normal
                    * half_depth,

                    z_center,
                )
            )

    connect_rings(
        faces,
        len(stations),
        ring_size,
    )

    append_caps(
        faces,
        len(stations),
        ring_size,
    )

    obj = mesh_object(
        name,
        vertices,
        faces,
        materials,
        root,
        region,
        True,
    )

    if subdivide:
        add_subdivision(obj, 1)

    return obj


def assign_dark_lower_leg(
    obj,
    dark_threshold,
):

    if len(obj.data.materials) < 2:
        return

    for polygon in obj.data.polygons:

        average_z = 0.0

        for vertex_index in polygon.vertices:
            average_z += obj.data.vertices[vertex_index].co.z

        average_z /= max(
            1,
            len(polygon.vertices),
        )

        polygon.material_index = (
            1
            if average_z < dark_threshold
            else 0
        )


def assign_head_muzzle(
    obj,
    muzzle_start=-1.625,
):

    if len(obj.data.materials) < 2:
        return

    for polygon in obj.data.polygons:

        average_y = 0.0

        for vertex_index in polygon.vertices:
            average_y += obj.data.vertices[vertex_index].co.y

        average_y /= max(
            1,
            len(polygon.vertices),
        )

        polygon.material_index = (
            1
            if average_y < muzzle_start
            else 0
        )


def create_hoof(
    name,
    x,
    center_y,
    width,
    length,
    height,
    hoof_material,
    root,
):
    """
    Eight-sided hoof with a narrower heel and a sloping coronary
    surface. This replaces the flat rectangular block silhouette.
    """

    bottom_z = 0.018

    bottom_local = [
        (-0.30, 0.45),
        (0.30, 0.45),
        (0.47, 0.18),
        (0.50, -0.28),
        (0.34, -0.52),
        (-0.34, -0.52),
        (-0.50, -0.28),
        (-0.47, 0.18),
    ]

    top_local = [
        (-0.25, 0.34),
        (0.25, 0.34),
        (0.37, 0.12),
        (0.39, -0.22),
        (0.28, -0.40),
        (-0.28, -0.40),
        (-0.39, -0.22),
        (-0.37, 0.12),
    ]

    vertices = []

    for local_x, local_y in bottom_local:

        vertices.append(
            (
                x
                + local_x
                * width,

                center_y
                + local_y
                * length,

                bottom_z,
            )
        )

    for local_x, local_y in top_local:

        toe_amount = max(
            0.0,
            min(
                1.0,
                (-local_y + 0.40) / 0.80,
            ),
        )

        top_z = height * (
            0.78
            + 0.22
            * toe_amount
        )

        vertices.append(
            (
                x
                + local_x
                * width,

                center_y
                + local_y
                * length,

                top_z,
            )
        )

    faces = [
        tuple(
            reversed(
                range(
                    0,
                    8,
                )
            )
        ),

        tuple(
            range(
                8,
                16,
            )
        ),
    ]

    for index in range(8):

        next_index = (
            index + 1
        ) % 8

        faces.append(
            (
                index,
                next_index,
                8 + next_index,
                8 + index,
            )
        )

    hoof_obj = mesh_object(
        name,
        vertices,
        faces,
        [
            hoof_material
        ],
        root,
        "hoof",
        False,
    )

    add_bevel(
        hoof_obj,
        0.012,
        2,
    )

    return hoof_obj


# V94_EAR_PROFILE
def create_ear(
    name,
    side_sign,
    coat,
    dark,
    root,
):

    base_inner = (
        side_sign
        * 0.060
    )

    base_outer = (
        side_sign
        * 0.170
    )

    tip_x = (
        side_sign
        * 0.115
    )

    base_front_y = -1.075
    base_rear_y = -0.985

    tip_front_y = -1.045
    tip_rear_y = -1.015

    base_z = 2.155
    tip_z = 2.440

    vertices = [

        (
            base_inner,
            base_front_y,
            base_z,
        ),

        (
            base_outer,
            base_front_y,
            base_z + 0.020,
        ),

        (
            tip_x,
            tip_front_y,
            tip_z,
        ),

        (
            base_inner,
            base_rear_y,
            base_z,
        ),

        (
            base_outer,
            base_rear_y,
            base_z + 0.020,
        ),

        (
            tip_x,
            tip_rear_y,
            tip_z,
        ),
    ]

    faces = [
        (0, 1, 2),
        (3, 5, 4),
        (0, 3, 4, 1),
        (1, 4, 5, 2),
        (2, 5, 3, 0),
    ]

    ear = mesh_object(
        name,
        vertices,
        faces,
        [
            coat
        ],
        root,
        "ear",
        True,
    )

    add_bevel(
        ear,
        0.009,
        2,
    )

    inner_offset = (
        side_sign
        * 0.004
    )

    inner_vertices = [

        (
            side_sign
            * 0.082
            + inner_offset,

            base_front_y
            - 0.003,

            base_z
            + 0.045,
        ),

        (
            side_sign
            * 0.148
            + inner_offset,

            base_front_y
            - 0.003,

            base_z
            + 0.060,
        ),

        (
            side_sign
            * 0.115
            + inner_offset,

            tip_front_y
            - 0.003,

            tip_z
            - 0.065,
        ),
    ]

    inner = mesh_object(
        name + "Inner",
        inner_vertices,
        [
            (
                0,
                1,
                2,
            )
        ],
        [
            dark
        ],
        root,
        "ear_detail",
        False,
    )

    return (
        ear,
        inner,
    )


def sphere_detail(
    name,
    location,
    scale,
    material,
    root,
    region,
    segments=16,
    rings=8,
):

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location,
    )

    obj = bpy.context.object

    obj.name = name
    obj.scale = scale

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True,
    )

    obj.data.materials.append(
        material
    )

    obj.parent = root

    obj[
        "broken_knight_region"
    ] = region

    smooth_object(
        obj
    )

    return obj


def create_mane(
    root_points,
    drop_points,
    dark,
    root,
):

    if len(root_points) != len(drop_points):

        raise RuntimeError(
            "Mane root/drop counts differ."
        )

    vertices = []

    for root_point, drop_point in zip(
        root_points,
        drop_points,
    ):

        vertices.append(
            root_point
        )

        vertices.append(
            drop_point
        )

    faces = []

    for index in range(
        len(root_points) - 1
    ):

        base = (
            index
            * 2
        )

        following = (
            (
                index + 1
            )
            * 2
        )

        faces.append(
            (
                base,
                following,
                following + 1,
                base + 1,
            )
        )

    mane = mesh_object(
        "RiverwatchV94Mane",
        vertices,
        faces,
        [
            dark
        ],
        root,
        "mane",
        True,
    )

    solidify = mane.modifiers.new(
        "RiverwatchManeThickness",
        "SOLIDIFY",
    )

    solidify.thickness = 0.050
    solidify.offset = 0.0

    add_bevel(
        mane,
        0.010,
        2,
    )

    return mane


def create_forelock(
    dark,
    root,
):

    vertices = [
        (-0.065, -1.045, 2.195),
        (0.060, -1.045, 2.195),
        (0.045, -1.220, 2.055),
        (-0.018, -1.340, 1.985),
        (-0.090, -1.235, 2.025),
    ]

    faces = [
        (
            0,
            1,
            2,
            3,
            4,
        )
    ]

    forelock = mesh_object(
        "RiverwatchV94Forelock",
        vertices,
        faces,
        [
            dark
        ],
        root,
        "mane",
        True,
    )

    solidify = forelock.modifiers.new(
        "RiverwatchForelockThickness",
        "SOLIDIFY",
    )

    solidify.thickness = 0.025
    solidify.offset = 0.0

    add_bevel(
        forelock,
        0.007,
        2,
    )

    return forelock


def create_tail_fan(
    center_stations,
    dark,
    root,
):

    offsets = [
        -0.070,
        -0.035,
        0.000,
        0.035,
        0.070,
    ]

    objects = []

    count = len(
        center_stations
    )

    for strand_index, offset in enumerate(
        offsets
    ):

        strand_stations = []

        for index, station in enumerate(
            center_stations
        ):

            (
                y,
                z,
                radius,
            ) = station

            progress = (
                index
                / max(
                    1,
                    count - 1,
                )
            )

            spread = (
                0.28
                + progress
                * 0.72
            )

            x = (
                offset
                * spread
            )

            strand_y = (
                y
                + abs(
                    offset
                )
                * progress
                * 0.12
            )

            strand_z = (
                z
                + (
                    0.012
                    if strand_index in (
                        0,
                        2,
                        4,
                    )
                    else -0.008
                )
                * progress
            )

            if strand_index in (
                0,
                4,
            ):
                radius_factor = 0.72

            elif strand_index in (
                1,
                3,
            ):
                radius_factor = 0.82

            else:
                radius_factor = 0.92

            strand_radius = (
                radius
                * radius_factor
            )

            strand_stations.append(
                (
                    x,
                    strand_y,
                    strand_z,
                    strand_radius,
                    strand_radius,
                    strand_radius,
                    1.0,
                    1.0,
                )
            )

        tail_obj = path_loft(
            "RiverwatchV94TailStrand"
            + str(
                strand_index + 1
            ),
            strand_stations,
            [
                dark
            ],
            root,
            "tail",
            RING_10,
            True,
        )

        objects.append(
            tail_obj
        )

    return objects


def create_root(
    tuning
):

    root = bpy.data.objects.new(
        "RiverwatchHorseV94Root",
        None,
    )

    bpy.context.collection.objects.link(
        root
    )

    root[
        "broken_knight_horse_detail"
    ] = "v94_fixed_plane_limb_checkpoint"

    root[
        "broken_knight_horse_version"
    ] = tuning.VERSION

    root[
        "broken_knight_horse_method"
    ] = "fixed_skull_fixed_plane_limbs_shaped_hooves"

    root[
        "broken_knight_horse_base"
    ] = "fresh_v80_family_rebuild"

    root[
        "broken_knight_horse_body"
    ] = "measured_fixed_axis_station_cage"

    root[
        "broken_knight_horse_neck"
    ] = "forward_arch_surface_loft"

    root[
        "broken_knight_horse_head"
    ] = "fixed_axis_equine_skull_cage"

    root[
        "broken_knight_horse_legs"
    ] = "fixed_z_anatomical_limb_cages"

    root[
        "broken_knight_horse_hooves"
    ] = "sloped_eight_sided_hoof_wedges"

    root[
        "broken_knight_horse_tail"
    ] = "five_clustered_continuous_hair_masses"

    root[
        "broken_knight_horse_tack"
    ] = "intentionally_removed_for_anatomy_checkpoint"

    root[
        "broken_knight_horse_goal"
    ] = "reach_strong_naked_anatomy_before_tack"

    return root


def build():

    tuning = load_tuning()

    clear_scene()

    coat = make_material(
        "Riverwatch V94 Warm Bay",
        tuning.COAT,
        0.76,
    )

    dark = make_material(
        "Riverwatch V94 Dark Points",
        tuning.DARK,
        0.70,
    )

    hoof = make_material(
        "Riverwatch V94 Hoof",
        tuning.HOOF,
        0.84,
    )

    muzzle = make_material(
        "Riverwatch V94 Muzzle",
        tuning.MUZZLE,
        0.90,
    )

    eye = make_material(
        "Riverwatch V94 Eye",
        tuning.EYE,
        0.24,
    )

    highlight = make_material(
        "Riverwatch V94 Eye Highlight",
        tuning.EYE_HIGHLIGHT,
        0.18,
    )

    root = create_root(
        tuning
    )

    fixed_y_loft(
        "RiverwatchV94Body",
        tuning.BODY_STATIONS,
        [
            coat
        ],
        root,
        "anatomy",
        RING_12,
        True,
    )

    path_loft(
        "RiverwatchV94Neck",
        tuning.NECK_STATIONS,
        [
            coat
        ],
        root,
        "anatomy",
        RING_12,
        True,
    )

    head = fixed_y_loft(
        "RiverwatchV94Head",
        tuning.HEAD_STATIONS,
        [
            coat,
            muzzle,
        ],
        root,
        "anatomy",
        RING_12,
        True,
    )

    assign_head_muzzle(
        head,
        -1.625,
    )

    front_near = fixed_z_limb_loft(
        "RiverwatchV94FrontLegNear",
        -tuning.FRONT_LEG_X,
        tuning.FRONT_LEG_STATIONS,
        [
            coat,
            dark,
        ],
        root,
        "front_leg",
        True,
    )

    front_far = fixed_z_limb_loft(
        "RiverwatchV94FrontLegFar",
        tuning.FRONT_LEG_X,
        tuning.FRONT_LEG_STATIONS,
        [
            coat,
            dark,
        ],
        root,
        "front_leg",
        True,
    )

    assign_dark_lower_leg(
        front_near,
        0.525,
    )

    assign_dark_lower_leg(
        front_far,
        0.525,
    )

    hind_near = fixed_z_limb_loft(
        "RiverwatchV94HindLegNear",
        -tuning.HIND_LEG_X,
        tuning.HIND_LEG_STATIONS,
        [
            coat,
            dark,
        ],
        root,
        "hind_leg",
        True,
    )

    hind_far = fixed_z_limb_loft(
        "RiverwatchV94HindLegFar",
        tuning.HIND_LEG_X,
        tuning.HIND_LEG_STATIONS,
        [
            coat,
            dark,
        ],
        root,
        "hind_leg",
        True,
    )

    assign_dark_lower_leg(
        hind_near,
        0.500,
    )

    assign_dark_lower_leg(
        hind_far,
        0.500,
    )

    for side_sign, suffix in (
        (
            -1.0,
            "Near"
        ),
        (
            1.0,
            "Far"
        ),
    ):

        create_hoof(
            "RiverwatchV94FrontHoof"
            + suffix,

            side_sign
            * tuning.FRONT_LEG_X,

            tuning.FRONT_HOOF[
                "center_y"
            ],

            tuning.FRONT_HOOF[
                "width"
            ],

            tuning.FRONT_HOOF[
                "length"
            ],

            tuning.FRONT_HOOF[
                "height"
            ],

            hoof,
            root,
        )

        create_hoof(
            "RiverwatchV94HindHoof"
            + suffix,

            side_sign
            * tuning.HIND_LEG_X,

            tuning.HIND_HOOF[
                "center_y"
            ],

            tuning.HIND_HOOF[
                "width"
            ],

            tuning.HIND_HOOF[
                "length"
            ],

            tuning.HIND_HOOF[
                "height"
            ],

            hoof,
            root,
        )

    create_ear(
        "RiverwatchV94EarNear",
        -1.0,
        coat,
        dark,
        root,
    )

    create_ear(
        "RiverwatchV94EarFar",
        1.0,
        coat,
        dark,
        root,
    )

    for side_sign, suffix in (
        (
            -1.0,
            "Near"
        ),
        (
            1.0,
            "Far"
        ),
    ):

        sphere_detail(
            "RiverwatchV94Eye"
            + suffix,

            (
                side_sign
                * 0.195,

                -1.245,
                2.060,
            ),

            (
                0.030,
                0.036,
                0.034,
            ),

            eye,
            root,
            "eye",
            16,
            8,
        )

        sphere_detail(
            "RiverwatchV94EyeHighlight"
            + suffix,

            (
                side_sign
                * 0.216,

                -1.260,
                2.072,
            ),

            (
                0.007,
                0.007,
                0.007,
            ),

            highlight,
            root,
            "eye_detail",
            12,
            6,
        )

        sphere_detail(
            "RiverwatchV94Nostril"
            + suffix,

            (
                side_sign
                * 0.100,

                -1.805,
                1.690,
            ),

            (
                0.026,
                0.015,
                0.019,
            ),

            dark,
            root,
            "muzzle_detail",
            14,
            7,
        )

    create_mane(
        tuning.MANE_ROOT,
        tuning.MANE_DROP,
        dark,
        root,
    )

    create_forelock(
        dark,
        root,
    )

    create_tail_fan(
        tuning.TAIL_CENTER_STATIONS,
        dark,
        root,
    )

    bpy.context.scene[
        "broken_knight_horse_version"
    ] = tuning.VERSION

    bpy.context.scene[
        "broken_knight_horse_checkpoint"
    ] = "ANATOMY_ONLY"

    bpy.context.scene[
        "broken_knight_horse_tack_status"
    ] = "DEFERRED"

    bpy.context.scene[
        "broken_knight_horse_structural_pass"
    ] = "V94_FIXED_PLANE_LIMBS"

    BLEND_FILE.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    GLB_FILE.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    bpy.ops.wm.save_as_mainfile(
        filepath=str(
            BLEND_FILE
        )
    )

    bpy.ops.object.select_all(
        action="SELECT"
    )

    bpy.ops.export_scene.gltf(
        filepath=str(
            GLB_FILE
        ),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_lights=False,
        export_cameras=False,
        export_apply=True,
    )

    mesh_objects = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
    ]

    total_vertices = sum(
        len(
            obj.data.vertices
        )
        for obj in mesh_objects
    )

    total_polygons = sum(
        len(
            obj.data.polygons
        )
        for obj in mesh_objects
    )

    print(
        "============================================================"
    )

    print(
        "RIVERWATCH_HORSE_V94_BUILT"
    )

    print(
        "VERSION=%s"
        % tuning.VERSION
    )

    print(
        "METHOD=V94_FIXED_PLANE_LIMB_GEOMETRY"
    )

    print(
        "CHECKPOINT=ANATOMY_ONLY"
    )

    print(
        "MESH_OBJECTS=%d"
        % len(
            mesh_objects
        )
    )

    print(
        "EDITABLE_VERTICES=%d"
        % total_vertices
    )

    print(
        "EDITABLE_POLYGONS=%d"
        % total_polygons
    )

    print(
        "BLEND=%s"
        % BLEND_FILE
    )

    print(
        "GLB=%s"
        % GLB_FILE
    )

    print(
        "============================================================"
    )


if __name__ == "__main__":

    build()
