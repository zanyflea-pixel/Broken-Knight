# V84_FEATURE_ALIGNMENT
# V83_FEATURE_ALIGNMENT
import bpy
import bmesh
import importlib.util
import math

from pathlib import Path
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]

TUNING_FILE = (
    Path(__file__).resolve().with_name(
        "riverwatch_horse_tuning.py"
    )
)

BLEND_FILE = (
    ROOT
    / "blender"
    / "world"
    / "animals"
    / "riverwatch_horse.blend"
)

GLB_FILE = (
    ROOT
    / "godot"
    / "assets"
    / "animals"
    / "riverwatch_horse.glb"
)


RING_12 = [

    (
        0.0,
        1.0
    ),

    (
        0.55,
        0.90
    ),

    (
        0.88,
        0.55
    ),

    (
        1.0,
        0.15
    ),

    (
        0.92,
        -0.35
    ),

    (
        0.55,
        -0.82
    ),

    (
        0.0,
        -1.0
    ),

    (
        -0.55,
        -0.82
    ),

    (
        -0.92,
        -0.35
    ),

    (
        -1.0,
        0.15
    ),

    (
        -0.88,
        0.55
    ),

    (
        -0.55,
        0.90
    ),
]


RING_8 = [

    (
        0.0,
        1.0
    ),

    (
        0.72,
        0.70
    ),

    (
        1.0,
        0.0
    ),

    (
        0.72,
        -0.70
    ),

    (
        0.0,
        -1.0
    ),

    (
        -0.72,
        -0.70
    ),

    (
        -1.0,
        0.0
    ),

    (
        -0.72,
        0.70
    ),
]


def load_tuning():

    spec = importlib.util.spec_from_file_location(
        "riverwatch_horse_tuning_live",
        TUNING_FILE
    )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


def clear_scene():

    if (
        bpy.context.object
        and
        bpy.context.object.mode != "OBJECT"
    ):

        bpy.ops.object.mode_set(
            mode="OBJECT"
        )

    bpy.ops.object.select_all(
        action="SELECT"
    )

    bpy.ops.object.delete(
        use_global=False
    )

    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
    ):

        for datablock in list(
            collection
        ):

            if datablock.users == 0:

                collection.remove(
                    datablock
                )


def make_material(
    name,
    color,
    roughness=0.72,
    metallic=0.0
):

    material = bpy.data.materials.new(
        name=name
    )

    material.diffuse_color = color

    material.use_nodes = True

    bsdf = material.node_tree.nodes.get(
        "Principled BSDF"
    )

    if bsdf is not None:

        bsdf.inputs[
            "Base Color"
        ].default_value = color

        bsdf.inputs[
            "Roughness"
        ].default_value = roughness

        bsdf.inputs[
            "Metallic"
        ].default_value = metallic

    return material


def recalc_normals(
    mesh
):

    bm = bmesh.new()

    bm.from_mesh(
        mesh
    )

    if bm.faces:

        bmesh.ops.recalc_face_normals(
            bm,
            faces=list(
                bm.faces
            )
        )

    bm.to_mesh(
        mesh
    )

    bm.free()

    mesh.update()


def smooth_object(
    obj
):

    if obj.type != "MESH":
        return

    for polygon in obj.data.polygons:

        polygon.use_smooth = True


def add_subdivision(
    obj,
    levels=1
):

    modifier = obj.modifiers.new(
        "RiverwatchControlledSubdivision",
        "SUBSURF"
    )

    modifier.subdivision_type = "CATMULL_CLARK"

    modifier.levels = levels
    modifier.render_levels = levels


def add_bevel(
    obj,
    width,
    segments=2
):

    modifier = obj.modifiers.new(
        "RiverwatchEdgeSoftening",
        "BEVEL"
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
    smooth=True
):

    mesh = bpy.data.meshes.new(
        name + "Mesh"
    )

    mesh.from_pydata(
        vertices,
        [],
        faces
    )

    mesh.update()

    recalc_normals(
        mesh
    )

    obj = bpy.data.objects.new(
        name,
        mesh
    )

    bpy.context.collection.objects.link(
        obj
    )

    for material in materials:

        obj.data.materials.append(
            material
        )

    obj.parent = root

    obj[
        "broken_knight_region"
    ] = region

    if smooth:

        smooth_object(
            obj
        )

    return obj


def append_caps(
    faces,
    ring_count,
    ring_size
):

    first = tuple(
        reversed(
            range(
                0,
                ring_size
            )
        )
    )

    last_start = (
        ring_count - 1
    ) * ring_size

    last = tuple(
        last_start + index
        for index in range(
            ring_size
        )
    )

    faces.append(
        first
    )

    faces.append(
        last
    )


def body_mesh(
    name,
    stations,
    coat,
    root
):

    vertices = []
    faces = []

    ring_size = len(
        RING_12
    )

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

        for (
            x_normal,
            z_normal
        ) in RING_12:

            width_factor = (
                upper_width
                if z_normal >= 0.0
                else lower_width
            )

            x = (
                x_normal
                * half_width
                * width_factor
            )

            depth = (
                top_depth
                if z_normal >= 0.0
                else lower_depth
            )

            z = (
                center_z
                + z_normal
                * depth
            )

            vertices.append(
                (
                    x,
                    y,
                    z
                )
            )

    for station_index in range(
        len(stations) - 1
    ):

        current = (
            station_index
            * ring_size
        )

        following = (
            (
                station_index + 1
            )
            * ring_size
        )

        for ring_index in range(
            ring_size
        ):

            next_index = (
                ring_index + 1
            ) % ring_size

            faces.append(
                (
                    current
                    + ring_index,

                    current
                    + next_index,

                    following
                    + next_index,

                    following
                    + ring_index,
                )
            )

    append_caps(
        faces,
        len(stations),
        ring_size
    )

    obj = mesh_object(
        name,
        vertices,
        faces,
        [
            coat
        ],
        root,
        "anatomy",
        True
    )

    add_subdivision(
        obj,
        1
    )

    return obj


def path_loft(
    name,
    stations,
    materials,
    root,
    region,
    ring=RING_12,
    subdivide=True
):

    vertices = []
    faces = []

    ring_size = len(
        ring
    )

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

    for station_index, station in enumerate(
        stations
    ):

        center = centers[
            station_index
        ]

        if station_index == 0:

            tangent = (
                centers[1]
                - centers[0]
            )

        elif station_index == len(
            stations
        ) - 1:

            tangent = (
                centers[-1]
                - centers[-2]
            )

        else:

            tangent = (
                centers[
                    station_index + 1
                ]
                - centers[
                    station_index - 1
                ]
            )

        if tangent.length < 0.00001:

            tangent = Vector(
                (
                    0.0,
                    -1.0,
                    0.0
                )
            )

        tangent.normalize()

        side = Vector(
            (
                1.0,
                0.0,
                0.0
            )
        )

        up = tangent.cross(
            side
        )

        if up.length < 0.00001:

            up = Vector(
                (
                    0.0,
                    0.0,
                    1.0
                )
            )

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

        for (
            x_normal,
            z_normal
        ) in ring:

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

            vertices.append(
                tuple(
                    point
                )
            )

    for station_index in range(
        len(stations) - 1
    ):

        current = (
            station_index
            * ring_size
        )

        following = (
            (
                station_index + 1
            )
            * ring_size
        )

        for ring_index in range(
            ring_size
        ):

            next_index = (
                ring_index + 1
            ) % ring_size

            faces.append(
                (
                    current
                    + ring_index,

                    current
                    + next_index,

                    following
                    + next_index,

                    following
                    + ring_index,
                )
            )

    append_caps(
        faces,
        len(stations),
        ring_size
    )

    obj = mesh_object(
        name,
        vertices,
        faces,
        materials,
        root,
        region,
        True
    )

    if subdivide:

        add_subdivision(
            obj,
            1
        )

    return obj


def limb_stations(
    x,
    data
):

    result = []

    for (
        y,
        z,
        half_width,
        depth
    ) in data:

        result.append(
            (
                x,
                y,
                z,
                half_width,
                depth,
                depth,
                1.0,
                1.0,
            )
        )

    return result


def assign_dark_lower_leg(
    obj,
    dark_threshold
):

    if len(
        obj.data.materials
    ) < 2:

        return

    for polygon in obj.data.polygons:

        average_z = 0.0

        for vertex_index in polygon.vertices:

            average_z += (
                obj.data.vertices[
                    vertex_index
                ].co.z
            )

        average_z /= max(
            1,
            len(
                polygon.vertices
            )
        )

        if average_z < dark_threshold:

            polygon.material_index = 1

        else:

            polygon.material_index = 0


def assign_head_muzzle(
    obj
):

    if len(
        obj.data.materials
    ) < 2:

        return

    for polygon in obj.data.polygons:

        average_y = 0.0
        average_z = 0.0

        for vertex_index in polygon.vertices:

            vertex = obj.data.vertices[
                vertex_index
            ].co

            average_y += vertex.y
            average_z += vertex.z

        divisor = max(
            1,
            len(
                polygon.vertices
            )
        )

        average_y /= divisor
        average_z /= divisor

        if (
            average_y < -1.585
            and
            average_z < 1.950
        ):

            polygon.material_index = 1

        else:

            polygon.material_index = 0


def create_hoof(
    name,
    x,
    center_y,
    width,
    length,
    height,
    hoof_material,
    root
):

    half_width = (
        width
        * 0.5
    )

    bottom_z = 0.018
    top_z = height

    toe_y = (
        center_y
        - length
        * 0.60
    )

    heel_y = (
        center_y
        + length
        * 0.40
    )

    top_toe_y = (
        center_y
        - length
        * 0.47
    )

    top_heel_y = (
        center_y
        + length
        * 0.30
    )

    top_width = (
        half_width
        * 0.82
    )

    vertices = [

        (
            x - half_width,
            heel_y,
            bottom_z
        ),

        (
            x + half_width,
            heel_y,
            bottom_z
        ),

        (
            x + half_width,
            toe_y,
            bottom_z
        ),

        (
            x - half_width,
            toe_y,
            bottom_z
        ),

        (
            x - top_width,
            top_heel_y,
            top_z
        ),

        (
            x + top_width,
            top_heel_y,
            top_z
        ),

        (
            x + top_width,
            top_toe_y,
            top_z
        ),

        (
            x - top_width,
            top_toe_y,
            top_z
        ),
    ]

    faces = [

        (
            0,
            1,
            2,
            3
        ),

        (
            4,
            7,
            6,
            5
        ),

        (
            0,
            4,
            5,
            1
        ),

        (
            1,
            5,
            6,
            2
        ),

        (
            2,
            6,
            7,
            3
        ),

        (
            3,
            7,
            4,
            0
        ),
    ]

    obj = mesh_object(
        name,
        vertices,
        faces,
        [
            hoof_material
        ],
        root,
        "hoof",
        False
    )

    add_bevel(
        obj,
        0.014,
        2
    )

    return obj


def create_ear(
    name,
    side_sign,
    coat,
    dark,
    root
):

    base_inner = (
        side_sign
        * 0.075
    )

    base_outer = (
        side_sign
        * 0.180
    )

    tip_x = (
        side_sign
        * 0.132
    )

    front_y = -1.035
    rear_y = -0.965

    base_z = 2.135
    tip_z = 2.360

    vertices = [

        (
            base_inner,
            front_y,
            base_z
        ),

        (
            base_outer,
            front_y,
            base_z + 0.025
        ),

        (
            tip_x,
            front_y,
            tip_z
        ),

        (
            base_inner,
            rear_y,
            base_z
        ),

        (
            base_outer,
            rear_y,
            base_z + 0.025
        ),

        (
            tip_x,
            rear_y,
            tip_z
        ),
    ]

    faces = [

        (
            0,
            1,
            2
        ),

        (
            3,
            5,
            4
        ),

        (
            0,
            3,
            4,
            1
        ),

        (
            1,
            4,
            5,
            2
        ),

        (
            2,
            5,
            3,
            0
        ),
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
        True
    )

    add_bevel(
        ear,
        0.008,
        2
    )

    inner_offset = (
        side_sign
        * 0.004
    )

    inner_vertices = [

        (
            side_sign * 0.095 + inner_offset,
            front_y - 0.004,
            base_z + 0.050
        ),

        (
            side_sign * 0.155 + inner_offset,
            front_y - 0.004,
            base_z + 0.060
        ),

        (
            side_sign * 0.130 + inner_offset,
            front_y - 0.004,
            tip_z - 0.060
        ),
    ]

    inner = mesh_object(
        name + "Inner",
        inner_vertices,
        [
            (
                0,
                1,
                2
            )
        ],
        [
            dark
        ],
        root,
        "ear_detail",
        False
    )

    return (
        ear,
        inner
    )


def sphere_detail(
    name,
    location,
    scale,
    material,
    root,
    region,
    segments=16,
    rings=8
):

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location
    )

    obj = bpy.context.object

    obj.name = name

    obj.scale = scale

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
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
    root
):

    if len(
        root_points
    ) != len(
        drop_points
    ):

        raise RuntimeError(
            "Mane root/drop counts differ."
        )

    vertices = []

    for (
        root_point,
        drop_point
    ) in zip(
        root_points,
        drop_points
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
        "RiverwatchV80Mane",
        vertices,
        faces,
        [
            dark
        ],
        root,
        "mane",
        True
    )

    solidify = mane.modifiers.new(
        "RiverwatchManeThickness",
        "SOLIDIFY"
    )

    solidify.thickness = 0.032
    solidify.offset = 0.0

    add_bevel(
        mane,
        0.010,
        2
    )

    return mane


def create_forelock(
    dark,
    root
):

    vertices = [

        (
            -0.055,
            -1.010,
            2.235
        ),

        (
            0.050,
            -1.015,
            2.235
        ),

        (
            0.035,
            -1.215,
            2.060
        ),

        (
            -0.075,
            -1.285,
            2.025
        ),
    ]

    faces = [

        (
            0,
            1,
            2,
            3
        )
    ]

    forelock = mesh_object(
        "RiverwatchV80Forelock",
        vertices,
        faces,
        [
            dark
        ],
        root,
        "mane",
        True
    )

    solidify = forelock.modifiers.new(
        "RiverwatchForelockThickness",
        "SOLIDIFY"
    )

    solidify.thickness = 0.025
    solidify.offset = 0.0

    add_bevel(
        forelock,
        0.008,
        2
    )

    return forelock


def create_root(
    tuning
):

    root = bpy.data.objects.new(
        "RiverwatchHorseV80Root",
        None
    )

    bpy.context.collection.objects.link(
        root
    )

    root[
        "broken_knight_horse_detail"
    ] = "v80_fresh_anatomy_checkpoint"

    root[
        "broken_knight_horse_version"
    ] = tuning.VERSION

    root[
        "broken_knight_horse_method"
    ] = "fresh_authored_surface_cages"

    root[
        "broken_knight_horse_base"
    ] = "none_fresh_rebuild"

    root[
        "broken_knight_horse_body"
    ] = "measured_continuous_station_cage"

    root[
        "broken_knight_horse_neck"
    ] = "forward_arch_asymmetric_surface_loft"

    root[
        "broken_knight_horse_head"
    ] = "broad_cheek_short_face_integrated_muzzle"

    root[
        "broken_knight_horse_legs"
    ] = "continuous_anatomical_limb_lofts_no_ball_joints"

    root[
        "broken_knight_horse_tack"
    ] = "intentionally_removed_for_anatomy_checkpoint"

    root[
        "broken_knight_horse_animation_acceptance"
    ] = "ignored_during_visual_modeling"

    root[
        "broken_knight_horse_goal"
    ] = "reach_strong_anatomy_before_reinstalling_tack"

    return root


def build():

    tuning = load_tuning()

    clear_scene()

    coat = make_material(
        "Riverwatch V80 Warm Bay",
        tuning.COAT,
        0.76
    )

    dark = make_material(
        "Riverwatch V80 Dark Points",
        tuning.DARK,
        0.70
    )

    hoof = make_material(
        "Riverwatch V80 Hoof",
        tuning.HOOF,
        0.84
    )

    muzzle = make_material(
        "Riverwatch V80 Muzzle",
        tuning.MUZZLE,
        0.90
    )

    eye = make_material(
        "Riverwatch V80 Eye",
        tuning.EYE,
        0.24
    )

    highlight = make_material(
        "Riverwatch V80 Eye Highlight",
        tuning.EYE_HIGHLIGHT,
        0.18
    )

    root = create_root(
        tuning
    )

    body = body_mesh(
        "RiverwatchV80Body",
        tuning.BODY_STATIONS,
        coat,
        root
    )

    neck = path_loft(
        "RiverwatchV80Neck",
        tuning.NECK_STATIONS,
        [
            coat
        ],
        root,
        "anatomy",
        RING_12,
        True
    )

    head = path_loft(
        "RiverwatchV80Head",
        tuning.HEAD_STATIONS,
        [
            coat,
            muzzle
        ],
        root,
        "anatomy",
        RING_12,
        True
    )

    assign_head_muzzle(
        head
    )

    front_near = path_loft(
        "RiverwatchV80FrontUpperNear",
        limb_stations(
            -tuning.FRONT_LEG_X,
            tuning.FRONT_LEG_STATIONS
        ),
        [
            coat,
            dark
        ],
        root,
        "front_leg",
        RING_8,
        True
    )

    front_far = path_loft(
        "RiverwatchV80FrontUpperFar",
        limb_stations(
            tuning.FRONT_LEG_X,
            tuning.FRONT_LEG_STATIONS
        ),
        [
            coat,
            dark
        ],
        root,
        "front_leg",
        RING_8,
        True
    )

    assign_dark_lower_leg(
        front_near,
        0.530
    )

    assign_dark_lower_leg(
        front_far,
        0.530
    )

    hind_near = path_loft(
        "RiverwatchV80ThighNear",
        limb_stations(
            -tuning.HIND_LEG_X,
            tuning.HIND_LEG_STATIONS
        ),
        [
            coat,
            dark
        ],
        root,
        "hind_leg",
        RING_8,
        True
    )

    hind_far = path_loft(
        "RiverwatchV80ThighFar",
        limb_stations(
            tuning.HIND_LEG_X,
            tuning.HIND_LEG_STATIONS
        ),
        [
            coat,
            dark
        ],
        root,
        "hind_leg",
        RING_8,
        True
    )

    assign_dark_lower_leg(
        hind_near,
        0.500
    )

    assign_dark_lower_leg(
        hind_far,
        0.500
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
            "RiverwatchV80FrontHoof"
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
            root
        )

        create_hoof(
            "RiverwatchV80HindHoof"
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
            root
        )

    create_ear(
        "RiverwatchV80EarNear",
        -1.0,
        coat,
        dark,
        root
    )

    create_ear(
        "RiverwatchV80EarFar",
        1.0,
        coat,
        dark,
        root
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

        eye_x = (
            side_sign
            * 0.250
        )

        sphere_detail(
            "RiverwatchV80Eye"
            + suffix,

            (
                eye_x,
                -1.235,
                2.055
            ),

            (
                0.038,
                0.048,
                0.046
            ),

            eye,
            root,
            "eye",
            16,
            8
        )

        sphere_detail(
            "RiverwatchV80EyeHighlight"
            + suffix,

            (
                side_sign
                * 0.276,

                -1.255,
                2.072
            ),

            (
                0.010,
                0.010,
                0.010
            ),

            highlight,
            root,
            "eye_detail",
            12,
            6
        )

        sphere_detail(
            "RiverwatchV80Nostril"
            + suffix,

            (
                side_sign
                * 0.125,

                -1.690,
                1.795
            ),

            (
                0.033,
                0.021,
                0.025
            ),

            dark,
            root,
            "muzzle_detail",
            14,
            7
        )

    create_mane(
        tuning.MANE_ROOT,
        tuning.MANE_DROP,
        dark,
        root
    )

    create_forelock(
        dark,
        root
    )

    tail = path_loft(
        "RiverwatchV80Tail",
        tuning.TAIL_STATIONS,
        [
            dark
        ],
        root,
        "tail",
        RING_8,
        True
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

    BLEND_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    GLB_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
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
        "RIVERWATCH_HORSE_V80_BUILT"
    )

    print(
        "VERSION=%s"
        % tuning.VERSION
    )

    print(
        "METHOD=FRESH_AUTHORED_SURFACE_CAGES"
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