import bpy
import json
import sys

from pathlib import Path
from mathutils import Vector


def safe_value(value):

    if value is None:
        return None

    if isinstance(
        value,
        (
            str,
            int,
            float,
            bool
        )
    ):
        return value

    if hasattr(
        value,
        "to_list"
    ):

        try:
            return value.to_list()
        except Exception:
            pass

    if isinstance(
        value,
        (
            list,
            tuple
        )
    ):

        return [
            safe_value(item)
            for item in value
        ]

    try:
        return str(value)
    except Exception:
        return "<unprintable>"


def vector_list(value):

    return [
        round(float(value.x), 6),
        round(float(value.y), 6),
        round(float(value.z), 6),
    ]


def world_bounds(obj):

    if obj.type != "MESH":
        return None

    if not obj.bound_box:
        return None

    points = []

    matrix = obj.matrix_world

    for corner in obj.bound_box:

        points.append(
            matrix
            @ Vector(corner)
        )

    if not points:
        return None

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

    return {
        "min": vector_list(minimum),
        "max": vector_list(maximum),
    }


def custom_properties(obj):

    result = {}

    for key in obj.keys():

        if key == "_RNA_UI":
            continue

        try:
            result[key] = safe_value(
                obj[key]
            )
        except Exception as error:

            result[key] = (
                "<error: %s>"
                % error
            )

    return result


if "--" not in sys.argv:

    raise RuntimeError(
        "Missing output argument."
    )


args = sys.argv[
    sys.argv.index("--") + 1:
]


if len(args) < 1:

    raise RuntimeError(
        "Expected output JSON path."
    )


output_path = Path(
    args[0]
).resolve()


output_path.parent.mkdir(
    parents=True,
    exist_ok=True
)


objects = []


for obj in sorted(
    bpy.data.objects,
    key=lambda item: item.name.lower()
):

    entry = {
        "name": obj.name,
        "type": obj.type,
        "parent": (
            obj.parent.name
            if obj.parent
            else None
        ),
        "location": vector_list(
            obj.location
        ),
        "rotation_euler": vector_list(
            obj.rotation_euler
        ),
        "scale": vector_list(
            obj.scale
        ),
        "dimensions": vector_list(
            obj.dimensions
        ),
        "world_bounds": world_bounds(
            obj
        ),
        "collections": [
            collection.name
            for collection in obj.users_collection
        ],
        "custom_properties": custom_properties(
            obj
        ),
        "modifiers": [],
        "materials": [],
    }

    for modifier in obj.modifiers:

        entry[
            "modifiers"
        ].append(
            {
                "name": modifier.name,
                "type": modifier.type,
            }
        )

    for slot in obj.material_slots:

        material_name = None

        if slot.material:

            material_name = (
                slot.material.name
            )

        entry[
            "materials"
        ].append(
            material_name
        )

    if obj.type == "MESH":

        entry[
            "mesh"
        ] = {
            "data_name": obj.data.name,
            "vertices": len(
                obj.data.vertices
            ),
            "edges": len(
                obj.data.edges
            ),
            "polygons": len(
                obj.data.polygons
            ),
            "materials": len(
                obj.data.materials
            ),
        }

    if obj.type == "ARMATURE":

        entry[
            "armature"
        ] = {
            "data_name": obj.data.name,
            "bones": [
                bone.name
                for bone in obj.data.bones
            ],
            "bone_count": len(
                obj.data.bones
            ),
        }

    objects.append(
        entry
    )


scene_properties = {}


for key in bpy.context.scene.keys():

    if key == "_RNA_UI":
        continue

    scene_properties[
        key
    ] = safe_value(
        bpy.context.scene[key]
    )


data = {
    "status": "HORSE_BLEND_INVENTORY_READY",
    "blender_version": bpy.app.version_string,
    "blend_file": bpy.data.filepath,
    "scene_name": bpy.context.scene.name,
    "scene_custom_properties": scene_properties,
    "object_count": len(objects),
    "mesh_object_count": len(
        [
            obj
            for obj in bpy.data.objects
            if obj.type == "MESH"
        ]
    ),
    "armature_object_count": len(
        [
            obj
            for obj in bpy.data.objects
            if obj.type == "ARMATURE"
        ]
    ),
    "objects": objects,
}


with output_path.open(
    "w",
    encoding="utf-8"
) as handle:

    json.dump(
        data,
        handle,
        indent=2,
        ensure_ascii=False
    )


print(
    "HORSE_BLEND_INVENTORY_READY"
)

print(
    "OBJECT_COUNT=%d"
    % data[
        "object_count"
    ]
)

print(
    "MESH_OBJECT_COUNT=%d"
    % data[
        "mesh_object_count"
    ]
)

print(
    "OUTPUT=%s"
    % output_path
)