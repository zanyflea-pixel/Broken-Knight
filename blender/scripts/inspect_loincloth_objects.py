"""Print construction and bounds for every live loincloth object."""

import bpy


PREFIXES = ("Loincloth", "ClothWaistCord", "LoinTie", "LoinKnot", "LoinTail")
for obj in sorted((item for item in bpy.data.objects if item.name.startswith(PREFIXES)), key=lambda item: item.name):
    coords = []
    if obj.type == "MESH":
        coords = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    elif obj.type == "CURVE":
        for spline in obj.data.splines:
            points = spline.bezier_points if spline.type == "BEZIER" else spline.points
            coords.extend(obj.matrix_world @ point.co.xyz for point in points)
    bounds = "empty"
    if coords:
        bounds = "x=%.4f,%.4f|y=%.4f,%.4f|z=%.4f,%.4f" % (
            min(point.x for point in coords), max(point.x for point in coords),
            min(point.y for point in coords), max(point.y for point in coords),
            min(point.z for point in coords), max(point.z for point in coords),
        )
    print(
        "LOIN_OBJECT|%s|type=%s|parent=%s|parent_type=%s|bone=%s|loc=%s|mods=%s|%s"
        % (
            obj.name, obj.type, obj.parent.name if obj.parent else "", obj.parent_type,
            obj.parent_bone, tuple(round(value, 5) for value in obj.location),
            [(modifier.name, modifier.type) for modifier in obj.modifiers], bounds,
        )
    )
