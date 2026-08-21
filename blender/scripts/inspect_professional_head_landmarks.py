"""Print source-head landmarks used by the integration transform."""

import bpy
from mathutils import Vector


def bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    lo = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    hi = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    return lo, hi


for name in (
    "HeroProfessionalTopology",
    "Eyes.ProfessionalWIP",
    "HairScalp.ProfessionalWIP",
    "Brows.RootedGroom",
    "Face.RootedStubble",
    "Hair.ShortGroom",
    "Hair.DirectionalClumps",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        print(f"LANDMARK_MISSING|{name}")
        continue
    if obj.type == "MESH":
        lo, hi = bounds(obj)
        print(
            f"LANDMARK_BOUNDS|{name}|"
            f"min={lo.x:.6f},{lo.y:.6f},{lo.z:.6f}|"
            f"max={hi.x:.6f},{hi.y:.6f},{hi.z:.6f}|verts={len(obj.data.vertices)}"
        )
    elif obj.type == "CURVE":
        points = [point.co.xyz for spline in obj.data.splines for point in spline.points]
        lo = Vector(tuple(min(point[i] for point in points) for i in range(3)))
        hi = Vector(tuple(max(point[i] for point in points) for i in range(3)))
        print(
            f"LANDMARK_CURVE|{name}|"
            f"min={lo.x:.6f},{lo.y:.6f},{lo.z:.6f}|"
            f"max={hi.x:.6f},{hi.y:.6f},{hi.z:.6f}|splines={len(obj.data.splines)}"
        )
        longest = sorted(
            (
                ((spline.points[-1].co.xyz - spline.points[0].co.xyz).length, index)
                for index, spline in enumerate(obj.data.splines)
                if len(spline.points) > 1
            ),
            reverse=True,
        )[:5]
        print(f"LANDMARK_CURVE_LONGEST|{name}|{longest}")

human = bpy.data.objects.get("HeroProfessionalTopology")
if human is not None:
    evaluated = human.evaluated_get(bpy.context.evaluated_depsgraph_get())
    for z_center in (1.48, 1.50, 1.52, 1.54, 1.56, 1.58, 1.60, 1.62, 1.64):
        band = [
            vertex.co for vertex in evaluated.data.vertices
            if abs(vertex.co.z - z_center) < 0.004
        ]
        if band:
            print(
                f"LANDMARK_SLICE|z={z_center:.3f}|count={len(band)}|"
                f"x={min(p.x for p in band):.5f},{max(p.x for p in band):.5f}|"
                f"y={min(p.y for p in band):.5f},{max(p.y for p in band):.5f}"
            )
    for group in human.vertex_groups:
        lower = group.name.lower()
        if not any(token in lower for token in ("mouth", "lip", "chin", "jaw", "head", "neck")):
            continue
        indices = []
        for vertex in human.data.vertices:
            if any(member.group == group.index and member.weight > 0.01 for member in vertex.groups):
                indices.append(vertex.index)
        if not indices:
            continue
        points = [human.data.vertices[index].co for index in indices]
        lo = Vector(tuple(min(point[i] for point in points) for i in range(3)))
        hi = Vector(tuple(max(point[i] for point in points) for i in range(3)))
        print(
            f"LANDMARK_GROUP|{group.name}|min={lo.x:.6f},{lo.y:.6f},{lo.z:.6f}|"
            f"max={hi.x:.6f},{hi.y:.6f},{hi.z:.6f}|verts={len(indices)}"
        )
        if max(indices) < len(evaluated.data.vertices):
            eval_points = [evaluated.data.vertices[index].co for index in indices]
            eval_lo = Vector(tuple(min(point[i] for point in eval_points) for i in range(3)))
            eval_hi = Vector(tuple(max(point[i] for point in eval_points) for i in range(3)))
            print(
                f"LANDMARK_GROUP_EVAL|{group.name}|"
                f"min={eval_lo.x:.6f},{eval_lo.y:.6f},{eval_lo.z:.6f}|"
                f"max={eval_hi.x:.6f},{eval_hi.y:.6f},{eval_hi.z:.6f}"
            )

eyes = bpy.data.objects.get("Eyes.ProfessionalWIP")
if eyes is not None:
    for label, sign in (("L", 1.0), ("R", -1.0)):
        points = [vertex.co for vertex in eyes.data.vertices if vertex.co.x * sign > 0.0]
        lo = Vector(tuple(min(point[i] for point in points) for i in range(3)))
        hi = Vector(tuple(max(point[i] for point in points) for i in range(3)))
        center = (lo + hi) * 0.5
        print(f"LANDMARK_EYE|{label}|center={center.x:.6f},{center.y:.6f},{center.z:.6f}")
