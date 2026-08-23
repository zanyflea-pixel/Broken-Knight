import bpy
import json
import math
import sys

from pathlib import Path


if "--" not in sys.argv:
    raise RuntimeError("Missing V101 arguments")


args = sys.argv[sys.argv.index("--") + 1:]


if len(args) != 2:
    raise RuntimeError(
        "Expected GLB output and report output"
    )


glb_path = Path(args[0]).resolve()
report_path = Path(args[1]).resolve()


glb_path.parent.mkdir(
    parents=True,
    exist_ok=True
)

report_path.parent.mkdir(
    parents=True,
    exist_ok=True
)


scene = bpy.context.scene

scene.frame_set(1)


# ============================================================
# REAL EXISTING V67/V100 MESH
# ============================================================

meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
]


if not meshes:
    raise RuntimeError(
        "V100 contains no mesh objects"
    )


main = max(
    meshes,
    key=lambda obj: len(
        obj.data.vertices
    )
)


mesh = main.data


if not mesh.vertices:
    raise RuntimeError(
        "Main V100 mesh has no vertices"
    )


print(
    "V101_MAIN_OBJECT=%s"
    % main.name,
    flush=True
)

print(
    "V101_SOURCE_VERTICES=%d"
    % len(mesh.vertices),
    flush=True
)

print(
    "V101_SOURCE_POLYGONS=%d"
    % len(mesh.polygons),
    flush=True
)


# ============================================================
# MATERIAL-AWARE ANATOMY MASKS
#
# This is important:
#
# We want to move HORSE anatomy, not saddle/brass/steel/etc.
# ============================================================

material_names = {}


for index, slot in enumerate(
    main.material_slots
):

    if slot.material is None:
        material_names[index] = ""
    else:
        material_names[index] = (
            slot.material.name.lower()
        )


body_vertices = set()
dark_vertices = set()
hoof_vertices = set()
tack_vertices = set()
other_vertices = set()


for polygon in mesh.polygons:

    name = material_names.get(
        polygon.material_index,
        ""
    )

    ids = set(
        polygon.vertices
    )

    if (
        "warm bay" in name or
        "bay" in name
    ):
        body_vertices.update(ids)

    elif "dark point" in name:
        dark_vertices.update(ids)

    elif "hoof" in name:
        hoof_vertices.update(ids)

    elif (
        "royal blue" in name or
        "saddle" in name or
        "brass" in name or
        "steel" in name
    ):
        tack_vertices.update(ids)

    else:
        other_vertices.update(ids)


anatomy_vertices = (
    body_vertices |
    dark_vertices |
    hoof_vertices
)


# Fallback only if historical material naming somehow differs.

material_mask_fallback = False


if len(anatomy_vertices) < 100:

    material_mask_fallback = True

    anatomy_vertices = set(
        range(
            len(mesh.vertices)
        )
    )

    anatomy_vertices -= tack_vertices


print(
    "V101_BODY_VERTICES=%d"
    % len(body_vertices),
    flush=True
)

print(
    "V101_DARK_VERTICES=%d"
    % len(dark_vertices),
    flush=True
)

print(
    "V101_HOOF_VERTICES=%d"
    % len(hoof_vertices),
    flush=True
)

print(
    "V101_TACK_VERTICES_EXCLUDED=%d"
    % len(tack_vertices),
    flush=True
)


# ============================================================
# ORIGINAL BOUNDS / HORSE ORIENTATION
# ============================================================

source_coords = {
    vertex.index: vertex.co.copy()
    for vertex in mesh.vertices
}


usable = [
    source_coords[index]
    for index in anatomy_vertices
]


xs = [
    value.x
    for value in usable
]

ys = [
    value.y
    for value in usable
]

zs = [
    value.z
    for value in usable
]


xmin = min(xs)
xmax = max(xs)

ymin = min(ys)
ymax = max(ys)

zmin = min(zs)
zmax = max(zs)


yrange = max(
    ymax - ymin,
    0.000001
)

zrange = max(
    zmax - zmin,
    0.000001
)


# Horse length runs on Y.
#
# Determine which end is front by comparing the average height
# of vertices near each end. Head/neck end should be taller.

end_margin = (
    yrange *
    0.18
)


low_end = [
    value
    for value in usable
    if value.y <= (
        ymin +
        end_margin
    )
]


high_end = [
    value
    for value in usable
    if value.y >= (
        ymax -
        end_margin
    )
]


def avg_z(values):

    if not values:
        return 0.0

    return sum(
        value.z
        for value in values
    ) / len(values)


front_is_max_y = (
    avg_z(high_end) >
    avg_z(low_end)
)


front_sign = (
    1.0
    if front_is_max_y
    else -1.0
)


def front_t_from_co(co):

    if front_is_max_y:

        return (
            co.y -
            ymin
        ) / yrange

    return (
        ymax -
        co.y
    ) / yrange


def height_t_from_co(co):

    return (
        co.z -
        zmin
    ) / zrange


print(
    "V101_FRONT_IS_MAX_Y=%s"
    % front_is_max_y,
    flush=True
)


# ============================================================
# HELPERS
# ============================================================

def clamp01(value):

    return max(
        0.0,
        min(
            1.0,
            value
        )
    )


def gaussian(
    value,
    center,
    width
):

    if width <= 0.0:
        return 0.0

    delta = (
        value -
        center
    ) / width

    return math.exp(
        -0.5 *
        delta *
        delta
    )


def linear_fit(
    pairs
):

    if not pairs:

        return (
            0.0,
            0.0
        )

    n = float(
        len(pairs)
    )

    sx = sum(
        item[0]
        for item in pairs
    )

    sy = sum(
        item[1]
        for item in pairs
    )

    sxx = sum(
        item[0] * item[0]
        for item in pairs
    )

    sxy = sum(
        item[0] * item[1]
        for item in pairs
    )

    denominator = (
        n * sxx -
        sx * sx
    )

    if abs(denominator) < 1e-12:

        return (
            0.0,
            sy / n
        )

    slope = (
        n * sxy -
        sx * sy
    ) / denominator

    intercept = (
        sy -
        slope * sx
    ) / n

    return (
        slope,
        intercept
    )


moved = set()

move_counts = {
    "forelegs": 0,
    "hindlegs": 0,
    "hooves": 0,
    "shoulder": 0,
}


# ============================================================
# BUILD FOUR LEG CLUSTERS
#
# front/hind + left/right
# ============================================================

clusters = {
    "FORE_NEG": [],
    "FORE_POS": [],
    "HIND_NEG": [],
    "HIND_POS": [],
}


leg_source = (
    anatomy_vertices -
    tack_vertices
)


for index in leg_source:

    co = source_coords[index]

    t = front_t_from_co(
        co
    )

    zt = height_t_from_co(
        co
    )


    if zt >= 0.47:
        continue


    side = (
        "NEG"
        if co.x < 0.0
        else "POS"
    )


    if 0.50 <= t <= 0.79:

        clusters[
            "FORE_" +
            side
        ].append(
            index
        )


    elif t <= 0.45:

        clusters[
            "HIND_" +
            side
        ].append(
            index
        )


# ============================================================
# DIRECT LEG DEFORMATION
#
# Existing vertices only.
#
# Goals:
# - stronger cannon bone dimensions
# - readable knee / hock
# - defined fetlock
# - tapered pastern
# - preserve original leg angle
#
# Centerline is fit against Z so we expand around the original
# angled leg instead of turning it into a vertical cylinder.
# ============================================================

for cluster_name, indices in clusters.items():

    if len(indices) < 5:
        continue


    x_fit = linear_fit(
        [
            (
                source_coords[index].z,
                source_coords[index].x
            )
            for index in indices
        ]
    )


    y_fit = linear_fit(
        [
            (
                source_coords[index].z,
                source_coords[index].y
            )
            for index in indices
        ]
    )


    is_fore = (
        cluster_name.startswith(
            "FORE"
        )
    )


    for index in indices:

        vertex = mesh.vertices[index]

        original = source_coords[index]

        zt = height_t_from_co(
            original
        )


        center_x = (
            x_fit[0] *
            original.z +
            x_fit[1]
        )

        center_y = (
            y_fit[0] *
            original.z +
            y_fit[1]
        )


        rx = (
            original.x -
            center_x
        )

        ry = (
            original.y -
            center_y
        )


        # Cannon/body of lower leg.
        lower = clamp01(
            (
                0.42 -
                zt
            ) / 0.30
        )


        # Foreleg knee or hindleg hock.
        joint_center = (
            0.335
            if is_fore
            else 0.305
        )


        joint = gaussian(
            zt,
            joint_center,
            0.050
        )


        # Fetlock above pastern.
        fetlock = gaussian(
            zt,
            0.165,
            0.038
        )


        # Pastern should taper again.
        pastern = gaussian(
            zt,
            0.105,
            0.030
        )


        scale_x = (
            1.0 +
            0.055 * lower +
            0.105 * joint +
            0.135 * fetlock -
            0.035 * pastern
        )


        scale_y = (
            1.0 +
            0.040 * lower +
            0.085 * joint +
            0.105 * fetlock -
            0.025 * pastern
        )


        vertex.co.x = (
            center_x +
            rx *
            scale_x
        )


        vertex.co.y = (
            center_y +
            ry *
            scale_y
        )


        # Knee reads slightly forward.
        if is_fore:

            vertex.co.y += (
                front_sign *
                yrange *
                0.007 *
                joint
            )


        # Hock reads slightly rearward.
        else:

            vertex.co.y -= (
                front_sign *
                yrange *
                0.012 *
                joint
            )


        # Natural pastern inclination toward hoof.
        if 0.065 <= zt <= 0.18:

            pastern_angle = clamp01(
                (
                    0.18 -
                    zt
                ) / 0.115
            )

            vertex.co.y += (
                front_sign *
                yrange *
                0.010 *
                pastern_angle
            )


        moved.add(
            index
        )


        if is_fore:
            move_counts["forelegs"] += 1
        else:
            move_counts["hindlegs"] += 1


# ============================================================
# DIRECT HOOF DEFORMATION
#
# Existing hoof-material vertices only.
#
# - wider
# - longer front/back
# - actual toe projection
# - retains original hoof mesh
# ============================================================

hoof_clusters = {
    "FORE_NEG": [],
    "FORE_POS": [],
    "HIND_NEG": [],
    "HIND_POS": [],
}


for index in hoof_vertices:

    original = source_coords[index]

    t = front_t_from_co(
        original
    )

    side = (
        "NEG"
        if original.x < 0.0
        else "POS"
    )


    if t >= 0.50:

        hoof_clusters[
            "FORE_" +
            side
        ].append(
            index
        )

    else:

        hoof_clusters[
            "HIND_" +
            side
        ].append(
            index
        )


for cluster_name, indices in hoof_clusters.items():

    if len(indices) < 3:
        continue


    center_x = sum(
        source_coords[index].x
        for index in indices
    ) / len(indices)


    center_y = sum(
        source_coords[index].y
        for index in indices
    ) / len(indices)


    for index in indices:

        vertex = mesh.vertices[index]

        original = source_coords[index]


        dx = (
            original.x -
            center_x
        )

        dy = (
            original.y -
            center_y
        )


        vertex.co.x = (
            center_x +
            dx *
            1.13
        )


        vertex.co.y = (
            center_y +
            dy *
            1.18
        )


        forward_part = (
            dy *
            front_sign
        )


        if forward_part > 0.0:

            vertex.co.y += (
                front_sign *
                yrange *
                0.010
            )


        moved.add(
            index
        )

        move_counts["hooves"] += 1


# ============================================================
# SHOULDER / CHEST
#
# Very restrained.
#
# We intentionally do NOT alter:
# - back
# - belly midsection
# - croup
# - neck proportions
# - head proportions
#
# Only warm-bay body vertices are eligible here.
# ============================================================

shoulder_source = (
    body_vertices -
    tack_vertices
)


for index in shoulder_source:

    vertex = mesh.vertices[index]

    original = source_coords[index]

    t = front_t_from_co(
        original
    )

    zt = height_t_from_co(
        original
    )


    if not (
        0.50 <= t <= 0.74 and
        0.27 <= zt <= 0.70
    ):
        continue


    longitudinal = (
        1.0 -
        abs(
            t -
            0.62
        ) / 0.12
    )


    longitudinal = clamp01(
        longitudinal
    )


    vertical = (
        1.0 -
        abs(
            zt -
            0.47
        ) / 0.23
    )


    vertical = clamp01(
        vertical
    )


    weight = (
        longitudinal *
        vertical
    )


    if weight <= 0.0:
        continue


    # More dimensional shoulder/chest width.
    vertex.co.x *= (
        1.0 +
        0.040 *
        weight
    )


    # Slightly more forward shoulder mass.
    vertex.co.y += (
        front_sign *
        yrange *
        0.005 *
        weight
    )


    # Deepen only the lower chest portion.
    lower_chest = clamp01(
        (
            0.50 -
            zt
        ) / 0.20
    )


    vertex.co.z -= (
        zrange *
        0.010 *
        weight *
        lower_chest
    )


    moved.add(
        index
    )

    move_counts["shoulder"] += 1


# ============================================================
# MARK V101
# ============================================================

scene["broken_knight_horse_version"] = "V101"

scene["broken_knight_horse_method"] = (
    "DIRECT_VERTEX_ANATOMY_EDIT_FROM_V100"
)

scene["broken_knight_horse_source"] = (
    "V100_EXACT_V67_BASELINE"
)

scene["broken_knight_horse_procedural_rebuild"] = False

scene["broken_knight_horse_remesh"] = False

scene["broken_knight_horse_focus"] = (
    "shoulders_legs_joints_pasterns_hooves"
)


main["broken_knight_horse_version"] = "V101"

main["broken_knight_direct_vertex_edit"] = True


# ============================================================
# SAVE V101
# ============================================================

bpy.ops.wm.save_as_mainfile(
    filepath=bpy.data.filepath
)


# ============================================================
# EXPORT REVIEW GLB
# ============================================================

for armature in [
    obj
    for obj in scene.objects
    if obj.type == "ARMATURE"
]:

    try:
        armature.data.pose_position = "REST"
    except Exception:
        pass


bpy.ops.object.select_all(
    action="DESELECT"
)


review_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
]


for obj in review_meshes:
    obj.select_set(True)


bpy.context.view_layer.objects.active = main


bpy.ops.export_scene.gltf(
    filepath=str(glb_path),
    export_format="GLB",
    use_selection=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
    export_apply=True,
)


# ============================================================
# REPORT
# ============================================================

report = {
    "status": "V101_DIRECT_EDIT_READY",
    "version": "V101",
    "source": "V100 exact V67 baseline",
    "method": "DIRECT_VERTEX_ANATOMY_EDIT",
    "procedural_rebuild": False,
    "remesh": False,
    "main_object": main.name,
    "mesh_vertices": len(mesh.vertices),
    "mesh_polygons": len(mesh.polygons),
    "front_is_max_y": front_is_max_y,
    "material_mask_fallback": material_mask_fallback,
    "body_vertex_count": len(body_vertices),
    "dark_vertex_count": len(dark_vertices),
    "hoof_vertex_count": len(hoof_vertices),
    "tack_vertices_excluded": len(tack_vertices),
    "moved_unique_vertices": len(moved),
    "move_counts": move_counts,
    "changes": [
        "increase lower-leg dimensionality",
        "define foreleg knee mass",
        "define hind hock mass",
        "define fetlock mass",
        "taper pastern region",
        "add pastern forward inclination",
        "widen and lengthen existing hoof geometry",
        "extend hoof toe",
        "modestly widen shoulder/chest",
        "slightly deepen lower chest",
    ],
    "preserved": [
        "V67 torso proportions",
        "V67 croup",
        "V67 neck proportions",
        "V67 head proportions",
        "tack material vertices",
        "V100 baseline file",
        "V94 live horse",
        "runtime horse",
    ],
}


with report_path.open(
    "w",
    encoding="utf-8"
) as handle:

    json.dump(
        report,
        handle,
        indent=2
    )


print(
    "V101_DIRECT_EDIT_SUCCESS",
    flush=True
)

print(
    "V101_MOVED_UNIQUE_VERTICES=%d"
    % len(moved),
    flush=True
)

print(
    "V101_FORELEG_EDITS=%d"
    % move_counts["forelegs"],
    flush=True
)

print(
    "V101_HINDLEG_EDITS=%d"
    % move_counts["hindlegs"],
    flush=True
)

print(
    "V101_HOOF_EDITS=%d"
    % move_counts["hooves"],
    flush=True
)

print(
    "V101_SHOULDER_EDITS=%d"
    % move_counts["shoulder"],
    flush=True
)

print(
    "V101_PROCEDURAL_REBUILD=NO",
    flush=True
)