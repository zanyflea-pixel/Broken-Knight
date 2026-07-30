import bpy
import math
import random
from mathutils import Vector
from pathlib import Path


OUTPUT_DIR = Path(r"C:\Users\Jimmy\Desktop\Broken Knight\godot\assets\vegetation")
BLEND_PATH = Path(__file__).resolve().parent / "realistic_broadleaf_v1.blend"
GLB_PATH = OUTPUT_DIR / "realistic_broadleaf_v1.glb"
random.seed(240731)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.8):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.roughness = roughness
    return value


def mesh_object(name, vertices, faces, mat):
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def frame_for(direction):
    axis = Vector(direction).normalized()
    reference = Vector((0, 0, 1))
    if abs(axis.dot(reference)) > 0.92:
        reference = Vector((1, 0, 0))
    side = axis.cross(reference).normalized()
    other = axis.cross(side).normalized()
    return axis, side, other


def append_tapered_segment(vertices, faces, start, end, start_radius, end_radius, sides=9):
    start = Vector(start)
    end = Vector(end)
    _, side, other = frame_for(end - start)
    base = len(vertices)
    for center, radius in ((start, start_radius), (end, end_radius)):
        for index in range(sides):
            angle = math.tau * index / sides
            vertices.append(tuple(center + side * math.cos(angle) * radius + other * math.sin(angle) * radius))
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((base + index, base + nxt, base + sides + nxt, base + sides + index))
    faces.append(tuple(base + index for index in reversed(range(sides))))
    faces.append(tuple(base + sides + index for index in range(sides)))


def build_trunk(mat):
    vertices = []
    faces = []
    rings = [
        ((0.00, 0.00, 0.00), 0.56),
        ((0.05, -0.03, 1.25), 0.50),
        ((-0.08, 0.06, 2.65), 0.42),
        ((0.10, 0.02, 4.00), 0.33),
        ((-0.03, -0.08, 5.25), 0.24),
        ((0.08, 0.02, 6.35), 0.13),
    ]
    sides = 12
    for center, radius in rings:
        for index in range(sides):
            angle = math.tau * index / sides
            irregular = 1.0 + math.sin(index * 2.71 + center[2] * 1.3) * 0.08
            vertices.append((center[0] + math.cos(angle) * radius * irregular,
                             center[1] + math.sin(angle) * radius * irregular,
                             center[2]))
    for ring in range(len(rings) - 1):
        for index in range(sides):
            nxt = (index + 1) % sides
            a = ring * sides + index
            b = ring * sides + nxt
            c = (ring + 1) * sides + nxt
            d = (ring + 1) * sides + index
            faces.append((a, b, c, d))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(rings) - 1) * sides + index for index in range(sides)))
    return mesh_object("TreeTrunk", vertices, faces, mat)


def build_branches(mat):
    vertices = []
    faces = []
    endpoints = []
    for index in range(9):
        angle = index * math.tau / 9.0 + (0.23 if index % 2 else -0.12)
        start_z = 3.65 + (index % 4) * 0.38
        reach = 2.25 + (index % 3) * 0.42
        rise = 1.65 + (index % 4) * 0.36
        start = Vector((0.02 * math.sin(index), 0.02 * math.cos(index), start_z))
        elbow = Vector((math.cos(angle) * reach * 0.48,
                        math.sin(angle) * reach * 0.48,
                        start_z + rise * 0.52))
        end = Vector((math.cos(angle) * reach,
                      math.sin(angle) * reach,
                      start_z + rise))
        append_tapered_segment(vertices, faces, start, elbow, 0.22, 0.14, 8)
        append_tapered_segment(vertices, faces, elbow, end, 0.145, 0.065, 7)
        fork_angle = angle + (-0.42 if index % 2 else 0.48)
        fork = end + Vector((math.cos(fork_angle) * 0.95,
                             math.sin(fork_angle) * 0.95,
                             0.62 + (index % 3) * 0.14))
        append_tapered_segment(vertices, faces, end * 0.96 + elbow * 0.04, fork, 0.075, 0.028, 6)
        endpoints.extend([end, fork])
    for index in range(4):
        angle = 0.7 + index * math.tau / 4.0
        start = Vector((0.04, -0.02, 5.2))
        end = Vector((math.cos(angle) * (1.1 + index * 0.12),
                      math.sin(angle) * (1.1 + index * 0.12),
                      7.25 + (index % 2) * 0.45))
        append_tapered_segment(vertices, faces, start, end, 0.14, 0.038, 7)
        endpoints.append(end)
    return mesh_object("TreeBranches", vertices, faces, mat), endpoints


def append_leaf(vertices, faces, center, forward, width, length, thickness):
    forward = Vector(forward).normalized()
    reference = Vector((0, 0, 1))
    if abs(forward.dot(reference)) > 0.88:
        reference = Vector((1, 0, 0))
    side = forward.cross(reference).normalized()
    normal = side.cross(forward).normalized()
    center = Vector(center)
    base = len(vertices)
    vertices.extend([
        tuple(center + forward * length),
        tuple(center - forward * length * 0.78),
        tuple(center + side * width),
        tuple(center - side * width),
        tuple(center + normal * thickness),
        tuple(center - normal * thickness),
    ])
    faces.extend([
        (base + 0, base + 2, base + 4), (base + 2, base + 1, base + 4),
        (base + 1, base + 3, base + 4), (base + 3, base + 0, base + 4),
        (base + 2, base + 0, base + 5), (base + 1, base + 2, base + 5),
        (base + 3, base + 1, base + 5), (base + 0, base + 3, base + 5),
    ])


def build_leaves(mat, endpoints):
    vertices = []
    faces = []
    clusters = list(endpoints)
    clusters.extend([
        Vector((0.0, 0.0, 6.9)),
        Vector((0.7, -0.3, 7.6)),
        Vector((-0.7, 0.4, 7.25)),
        Vector((0.2, 0.8, 6.5)),
    ])
    for index in range(1050):
        cluster = clusters[index % len(clusters)]
        radial = Vector((random.gauss(0, 0.42), random.gauss(0, 0.42), random.gauss(0, 0.31)))
        center = cluster + radial
        forward = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.55, 0.75)))
        if forward.length_squared < 0.01:
            forward = Vector((1, 0, 0))
        scale = random.uniform(0.80, 1.22)
        append_leaf(vertices, faces, center, forward, 0.16 * scale, 0.29 * scale, 0.025)
    return mesh_object("TreeLeaves", vertices, faces, mat)


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    bark = material("Bark", (0.20, 0.105, 0.045), 0.95)
    leaves = material("Leaves", (0.11, 0.29, 0.075), 0.82)
    build_trunk(bark)
    _, endpoints = build_branches(bark)
    build_leaves(leaves, endpoints)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"REALISTIC_TREE_EXPORT|blend={BLEND_PATH}|glb={GLB_PATH}")


if __name__ == "__main__":
    main()
