import bpy
import math
import sys

from pathlib import Path
from mathutils import Vector


def log(value=""):
    print(value, flush=True)


# ============================================================
# ARGUMENTS
# ============================================================

if "--" not in sys.argv:
    raise RuntimeError(
        "Missing -- arguments."
    )

args = sys.argv[
    sys.argv.index("--") + 1:
]

if len(args) < 2:
    raise RuntimeError(
        "Expected INPUT_GLB OUTPUT_FOLDER."
    )

source_glb = Path(
    args[0]
).resolve()

output_dir = Path(
    args[1]
).resolve()

output_dir.mkdir(
    parents=True,
    exist_ok=True
)

log("")
log("============================================================")
log(" HORSE AUTO RENDER BLENDER 5.1 SAFE")
log("============================================================")
log("")
log("SOURCE=%s" % source_glb)
log("OUTPUT=%s" % output_dir)
log("")


if not source_glb.exists():
    raise RuntimeError(
        "Input horse GLB does not exist: %s"
        % source_glb
    )


# ============================================================
# CLEAN SCENE
# ============================================================

bpy.ops.object.select_all(
    action="SELECT"
)

bpy.ops.object.delete(
    use_global=False
)


# ============================================================
# IMPORT GLB
# ============================================================

log("IMPORTING_GLTF=YES")

bpy.ops.import_scene.gltf(
    filepath=str(
        source_glb
    )
)

horse_objects = [
    obj
    for obj in bpy.context.scene.objects
    if obj.type == "MESH"
]

if not horse_objects:
    raise RuntimeError(
        "Horse GLB imported zero mesh objects."
    )

log(
    "HORSE_MESH_COUNT=%d"
    % len(horse_objects)
)


# ============================================================
# BOUNDS
# ============================================================

def get_bounds(objects):

    points = []

    for obj in objects:

        matrix = obj.matrix_world

        for corner in obj.bound_box:

            points.append(
                matrix @ Vector(corner)
            )

    if not points:
        raise RuntimeError(
            "No bounding-box points."
        )

    minimum = Vector(
        (
            min(point.x for point in points),
            min(point.y for point in points),
            min(point.z for point in points),
        )
    )

    maximum = Vector(
        (
            max(point.x for point in points),
            max(point.y for point in points),
            max(point.z for point in points),
        )
    )

    return minimum, maximum


minimum, maximum = get_bounds(
    horse_objects
)

center = (
    minimum + maximum
) * 0.5

size = (
    maximum - minimum
)

largest = max(
    size.x,
    size.y,
    size.z
)

if largest <= 0.001:
    raise RuntimeError(
        "Horse bounds are invalid."
    )

log(
    "BOUND_WIDTH_X=%.5f"
    % size.x
)

log(
    "BOUND_LENGTH_Y=%.5f"
    % size.y
)

log(
    "BOUND_HEIGHT_Z=%.5f"
    % size.z
)


# ============================================================
# SCENE
#
# Leave Blender's active render engine alone.
#
# That avoids version-specific engine enum failures.
# ============================================================

scene = bpy.context.scene

scene.render.resolution_x = 420
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100

scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"

scene.render.film_transparent = False


# ============================================================
# WORLD
# ============================================================

scene.world.use_nodes = True

world_background = scene.world.node_tree.nodes.get(
    "Background"
)

if world_background is not None:

    world_background.inputs[
        "Color"
    ].default_value = (
        0.018,
        0.021,
        0.028,
        1.0
    )

    world_background.inputs[
        "Strength"
    ].default_value = 0.35


# ============================================================
# FLOOR
# ============================================================

floor_z = (
    minimum.z - 0.022
)

bpy.ops.mesh.primitive_plane_add(
    size=largest * 8.0,
    location=(
        center.x,
        center.y,
        floor_z
    )
)

floor = bpy.context.object

floor.name = "HorseReviewFloor"

floor_material = bpy.data.materials.new(
    name="HorseReviewFloorMaterial"
)

floor_material.diffuse_color = (
    0.30,
    0.31,
    0.33,
    1.0
)

floor.data.materials.append(
    floor_material
)


# ============================================================
# CAMERA / LIGHT HELPERS
# ============================================================

def point_at(
    obj,
    target
):

    direction = (
        Vector(target)
        - obj.location
    )

    obj.rotation_euler = direction.to_track_quat(
        "-Z",
        "Y"
    ).to_euler()


def create_area(
    location,
    energy,
    size_value
):

    bpy.ops.object.light_add(
        type="AREA",
        location=location
    )

    light = bpy.context.object

    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size_value

    point_at(
        light,
        center
    )

    return light


# ============================================================
# LIGHTING
# ============================================================

create_area(
    (
        center.x - largest * 1.35,
        center.y - largest * 1.25,
        center.z + largest * 1.90
    ),
    1100.0,
    largest * 1.8
)

create_area(
    (
        center.x + largest * 1.45,
        center.y + largest * 0.45,
        center.z + largest * 1.45
    ),
    750.0,
    largest * 1.6
)

create_area(
    (
        center.x,
        center.y + largest * 1.30,
        center.z + largest * 1.30
    ),
    500.0,
    largest * 1.5
)

bpy.ops.object.light_add(
    type="SUN",
    location=(
        center.x,
        center.y,
        center.z + largest * 3.0
    )
)

sun = bpy.context.object

sun.data.energy = 1.0

sun.rotation_euler = (
    math.radians(32.0),
    math.radians(-24.0),
    math.radians(-35.0)
)


# ============================================================
# CAMERA
# ============================================================

bpy.ops.object.camera_add()

camera = bpy.context.object

camera.name = "HorseReviewCamera"

camera.data.type = "ORTHO"

scene.camera = camera


def set_camera(
    location,
    target,
    scale
):

    camera.location = Vector(
        location
    )

    point_at(
        camera,
        target
    )

    camera.data.ortho_scale = scale


distance = (
    largest * 3.25
)


# ============================================================
# FIND DETAIL OBJECTS
# ============================================================

def objects_containing(tokens):

    lowered = [
        token.lower()
        for token in tokens
    ]

    result = []

    for obj in horse_objects:

        object_name = obj.name.lower()

        if any(
            token in object_name
            for token in lowered
        ):

            result.append(
                obj
            )

    return result


def detail_region(
    objects,
    fallback_center,
    fallback_scale,
    padding
):

    if not objects:

        return (
            Vector(fallback_center),
            fallback_scale
        )

    region_minimum, region_maximum = get_bounds(
        objects
    )

    region_center = (
        region_minimum
        + region_maximum
    ) * 0.5

    region_size = (
        region_maximum
        - region_minimum
    )

    region_scale = max(
        region_size.x,
        region_size.y,
        region_size.z
    ) * padding

    return (
        region_center,
        max(
            region_scale,
            fallback_scale * 0.25
        )
    )


head_objects = objects_containing(
    (
        "head",
        "muzzle",
        "eye",
        "nostril",
        "ear",
        "forelock",
        "bridle",
        "bitring",
        "noseband",
        "browband"
    )
)

front_objects = objects_containing(
    (
        "frontupper",
        "frontcannon",
        "frontpastern",
        "fronthoof",
        "shoulder",
        "pectoral"
    )
)

rear_objects = objects_containing(
    (
        "thigh",
        "gaskin",
        "hindcannon",
        "hindpastern",
        "hindhoof",
        "tail"
    )
)


head_center, head_scale = detail_region(
    head_objects,
    (
        center.x,
        minimum.y,
        center.z + size.z * 0.25
    ),
    largest * 0.40,
    1.45
)

front_center, front_scale = detail_region(
    front_objects,
    (
        center.x,
        center.y - size.y * 0.20,
        minimum.z + size.z * 0.42
    ),
    largest * 0.46,
    1.34
)

rear_center, rear_scale = detail_region(
    rear_objects,
    (
        center.x,
        center.y + size.y * 0.25,
        minimum.z + size.z * 0.48
    ),
    largest * 0.48,
    1.34
)


# ============================================================
# VIEWS
# ============================================================

views = [
    (
        "01_side_left",
        (
            center.x - distance,
            center.y,
            center.z + size.z * 0.05
        ),
        center,
        max(size.y, size.z) * 1.18
    ),

    (
        "02_front_3q",
        (
            center.x - distance * 0.72,
            center.y - distance * 0.72,
            center.z + size.z * 0.10
        ),
        center,
        largest * 1.15
    ),

    (
        "03_front",
        (
            center.x,
            center.y - distance,
            center.z + size.z * 0.04
        ),
        center,
        max(size.x, size.z) * 1.23
    ),

    (
        "04_side_right",
        (
            center.x + distance,
            center.y,
            center.z + size.z * 0.05
        ),
        center,
        max(size.y, size.z) * 1.18
    ),

    (
        "05_rear_3q",
        (
            center.x - distance * 0.72,
            center.y + distance * 0.72,
            center.z + size.z * 0.10
        ),
        center,
        largest * 1.15
    ),

    (
        "06_head_detail",
        (
            head_center.x - distance * 0.32,
            head_center.y - distance * 0.32,
            head_center.z + head_scale * 0.07
        ),
        head_center,
        head_scale
    ),

    (
        "07_front_detail",
        (
            front_center.x - distance * 0.29,
            front_center.y - distance * 0.29,
            front_center.z + front_scale * 0.07
        ),
        front_center,
        front_scale
    ),

    (
        "08_rear_detail",
        (
            rear_center.x - distance * 0.29,
            rear_center.y + distance * 0.29,
            rear_center.z + rear_scale * 0.08
        ),
        rear_center,
        rear_scale
    ),
]


# ============================================================
# RENDER
# ============================================================

for (
    view_name,
    camera_location,
    target,
    ortho_scale
) in views:

    set_camera(
        camera_location,
        target,
        ortho_scale
    )

    destination = (
        output_dir
        / (
            view_name + ".png"
        )
    )

    scene.render.filepath = str(
        destination
    )

    log(
        "RENDERING=%s"
        % view_name
    )

    bpy.ops.render.render(
        write_still=True
    )

    if not destination.exists():

        raise RuntimeError(
            "Render did not create: %s"
            % destination
        )

    log(
        "CAPTURED=%s"
        % destination
    )


log("")
log("HORSE_AUTO_RENDER_SUCCESS")
log("")