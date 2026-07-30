"""Report disconnected geometry islands in the accepted hero body mesh."""

import bpy


obj = bpy.data.objects["ConnectedBody"]
mesh = obj.data
neighbors = [[] for _ in mesh.vertices]
for edge in mesh.edges:
    a, b = edge.vertices
    neighbors[a].append(b)
    neighbors[b].append(a)

remaining = set(range(len(mesh.vertices)))
components = []
while remaining:
    seed = remaining.pop()
    stack = [seed]
    indices = [seed]
    while stack:
        current = stack.pop()
        for neighbor in neighbors[current]:
            if neighbor in remaining:
                remaining.remove(neighbor)
                stack.append(neighbor)
                indices.append(neighbor)
    components.append(indices)

components.sort(key=len, reverse=True)
print(f"COMPONENTS|{len(components)}")
for number, indices in enumerate(components):
    coords = [mesh.vertices[index].co for index in indices]
    low = tuple(min(co[axis] for co in coords) for axis in range(3))
    high = tuple(max(co[axis] for co in coords) for axis in range(3))
    print(
        "COMP|%d|verts=%d|bounds=(%.4f,%.4f,%.4f)-(%.4f,%.4f,%.4f)"
        % (number, len(indices), *low, *high)
    )
