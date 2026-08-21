"""Report open topology and rig data at the professional head/body junction."""

import bmesh
import bpy
from collections import defaultdict


def boundary_loops(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    boundary = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    adjacency = defaultdict(list)
    for edge in boundary:
        a, b = edge.verts
        adjacency[a.index].append(b.index)
        adjacency[b.index].append(a.index)
    unseen = set(adjacency)
    loops = []
    while unseen:
        seed = unseen.pop()
        stack = [seed]
        component = [seed]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    stack.append(neighbor)
                    component.append(neighbor)
        coords = [bm.verts[index].co.copy() for index in component]
        loops.append(
            {
                "count": len(component),
                "xmin": min(co.x for co in coords),
                "xmax": max(co.x for co in coords),
                "ymin": min(co.y for co in coords),
                "ymax": max(co.y for co in coords),
                "zmin": min(co.z for co in coords),
                "zmax": max(co.z for co in coords),
                "degrees": sorted({len(adjacency[index]) for index in component}),
            }
        )
    bm.free()
    return sorted(loops, key=lambda item: item["zmax"], reverse=True)


for name in ("ConnectedBody", "ProfessionalHead"):
    obj = bpy.data.objects.get(name)
    if obj is None:
        print(f"CONNECTION|{name}|MISSING")
        continue
    print(
        f"CONNECTION|{name}|verts={len(obj.data.vertices)}|faces={len(obj.data.polygons)}|"
        f"materials={[material.name if material else 'None' for material in obj.data.materials]}|"
        f"groups={[group.name for group in obj.vertex_groups]}|"
        f"modifiers={[modifier.type + ':' + modifier.name for modifier in obj.modifiers]}"
    )
    loops = boundary_loops(obj)
    print(f"CONNECTION|{name}|boundary_components={len(loops)}")
    for index, loop in enumerate(loops[:12]):
        print(
            f"CONNECTION_LOOP|{name}|{index}|count={loop['count']}|"
            f"x={loop['xmin']:.5f}:{loop['xmax']:.5f}|"
            f"y={loop['ymin']:.5f}:{loop['ymax']:.5f}|"
            f"z={loop['zmin']:.5f}:{loop['zmax']:.5f}|degree={loop['degrees']}"
        )

    if name == "ConnectedBody" and loops:
        mesh = obj.data
        edge_counts = defaultdict(int)
        for polygon in mesh.polygons:
            verts = polygon.vertices
            for offset, a in enumerate(verts):
                b = verts[(offset + 1) % len(verts)]
                edge_counts[tuple(sorted((a, b)))] += 1
        boundary_indices = sorted({index for edge, count in edge_counts.items() if count == 1 for index in edge})
        dominant = defaultdict(int)
        totals = []
        for index in boundary_indices:
            vertex = mesh.vertices[index]
            weights = [(membership.weight, obj.vertex_groups[membership.group].name) for membership in vertex.groups]
            totals.append(sum(weight for weight, _name in weights))
            if weights:
                dominant[max(weights)[1]] += 1
        print(
            f"BODY_BOUNDARY_WEIGHTS|dominant={dict(sorted(dominant.items()))}|"
            f"min_total={min(totals):.6f}|max_total={max(totals):.6f}"
        )

head = bpy.data.objects.get("ProfessionalHead")
if head is not None:
    min_z = min(vertex.co.z for vertex in head.data.vertices)
    for threshold in (min_z + 0.001, 1.580, 1.600, 1.620, 1.640):
        selected = [vertex for vertex in head.data.vertices if vertex.co.z <= threshold]
        if selected:
            print(
                f"HEAD_LOWER|threshold={threshold:.5f}|count={len(selected)}|"
                f"x={min(vertex.co.x for vertex in selected):.5f}:{max(vertex.co.x for vertex in selected):.5f}|"
                f"y={min(vertex.co.y for vertex in selected):.5f}:{max(vertex.co.y for vertex in selected):.5f}|"
                f"z={min(vertex.co.z for vertex in selected):.5f}:{max(vertex.co.z for vertex in selected):.5f}"
            )
    z_counts = defaultdict(int)
    for vertex in head.data.vertices:
        if vertex.co.z < 1.640:
            z_counts[round(vertex.co.z, 5)] += 1
    print("HEAD_Z_LAYERS|" + ",".join(f"{z}:{count}" for z, count in sorted(z_counts.items())[:24]))
