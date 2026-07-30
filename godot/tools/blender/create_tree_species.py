import bpy
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import create_realistic_broadleaf as common

ASSET_DIR = Path(r"C:\Users\Jimmy\Desktop\Broken Knight\godot\assets\vegetation")


def export_species(name):
    blend_path = SCRIPT_DIR / f"realistic_{name}_v1.blend"
    glb_path = ASSET_DIR / f"realistic_{name}_v1.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"TREE_SPECIES_EXPORT|species={name}|blend={blend_path}|glb={glb_path}")


def add_segment_mesh(name, segments, material):
    vertices = []
    faces = []
    for start, end, r0, r1, sides in segments:
        common.append_tapered_segment(vertices, faces, start, end, r0, r1, sides)
    return common.mesh_object(name, vertices, faces, material)


def build_birch():
    random.seed(31071)
    common.clear_scene()
    bark = common.material("BirchBark", (0.72, 0.69, 0.58), 0.88)
    leaf_mat = common.material("BirchLeaves", (0.19, 0.42, 0.10), 0.78)
    trunk_segments = [
        ((0, 0, 0), (0.04, -0.02, 2.5), .38, .30, 11),
        ((0.04, -.02, 2.5), (-.06, .05, 5.1), .30, .19, 10),
        ((-.06, .05, 5.1), (.08, -.03, 7.5), .19, .075, 9),
    ]
    common.mesh_object("TreeTrunk", *_segments_to_mesh(trunk_segments), bark)
    branch_segments = []
    endpoints = []
    for index in range(14):
        angle = index * math.tau / 14.0 + .19 * (index % 3)
        start = Vector((0, 0, 2.9 + (index % 7) * .55))
        reach = 1.25 + (index % 4) * .28
        end = Vector((math.cos(angle) * reach, math.sin(angle) * reach, start.z + .85 + (index % 3) * .24))
        branch_segments.append((start, end, .105, .025, 6))
        endpoints.append(end)
    add_segment_mesh("TreeBranches", branch_segments, bark)
    vertices, faces = [], []
    for index in range(760):
        center = endpoints[index % len(endpoints)] + Vector((
            random.gauss(0, .38), random.gauss(0, .38), random.gauss(0, .46)
        ))
        forward = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-.4, .9)))
        common.append_leaf(vertices, faces, center, forward, .115, .235, .018)
    common.mesh_object("TreeLeaves", vertices, faces, leaf_mat)
    export_species("birch")


def build_maple():
    random.seed(42117)
    common.clear_scene()
    bark = common.material("MapleBark", (.27, .17, .085), .93)
    leaf_mat = common.material("MapleLeaves", (.23, .39, .075), .80)
    trunk_segments = [
        ((0, 0, 0), (.09, -.04, 2.25), .55, .40, 12),
        ((.09, -.04, 2.25), (-.06, .09, 4.35), .40, .24, 11),
        ((-.06, .09, 4.35), (.03, .03, 6.65), .24, .085, 9),
    ]
    common.mesh_object("TreeTrunk", *_segments_to_mesh(trunk_segments), bark)
    branch_segments = []
    endpoints = []
    # A broad, upward-growing crown replaces the former hanging branches.
    # Every primary and secondary limb gains height as it leaves the trunk.
    for index in range(12):
        angle = index * math.tau / 12.0 + .17 * (index % 3)
        start = Vector((.02, 0, 2.85 + (index % 6) * .48))
        reach = 2.25 + (index % 4) * .24
        elbow = Vector((math.cos(angle) * reach * .52, math.sin(angle) * reach * .52, start.z + .82))
        end = Vector((math.cos(angle) * reach, math.sin(angle) * reach, start.z + 1.48 + (index % 3) * .18))
        branch_segments.append((start, elbow, .19, .10, 8))
        branch_segments.append((elbow, end, .105, .035, 7))
        endpoints.append(end)
        fork_angle = angle + (-.42 if index % 2 else .46)
        fork = end + Vector((math.cos(fork_angle) * .82, math.sin(fork_angle) * .82, .58))
        branch_segments.append((end, fork, .045, .016, 6))
        endpoints.append(fork)
    add_segment_mesh("TreeBranches", branch_segments, bark)
    vertices, faces = [], []
    crown_centers = endpoints + [
        Vector((0, 0, 6.7)),
        Vector((.85, .25, 6.9)),
        Vector((-.75, -.35, 6.75)),
    ]
    for index in range(1250):
        center = crown_centers[index % len(crown_centers)] + Vector((
            random.gauss(0, .48), random.gauss(0, .48), random.gauss(0, .38)
        ))
        forward = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-.35, .85)))
        common.append_leaf(vertices, faces, center, forward, .17, .31, .024)
    common.mesh_object("TreeLeaves", vertices, faces, leaf_mat)
    export_species("maple")


def build_pine():
    random.seed(58129)
    common.clear_scene()
    bark = common.material("PineBark", (.18, .09, .035), .96)
    needle_mat = common.material("PineNeedles", (.075, .30, .115), .86)
    trunk_segments = [
        ((0, 0, 0), (.02, -.02, 3.2), .46, .34, 10),
        ((.02, -.02, 3.2), (-.03, .02, 6.2), .34, .21, 9),
        ((-.03, .02, 6.2), (0, 0, 9.4), .21, .045, 8),
    ]
    common.mesh_object("TreeTrunk", *_segments_to_mesh(trunk_segments), bark)
    branch_segments = []
    endpoints = []
    for level in range(9):
        z = 2.1 + level * .72
        radius = 3.05 - level * .27
        count = 8 if level < 5 else 6
        for index in range(count):
            angle = index * math.tau / count + level * .41
            start = Vector((0, 0, z))
            end = Vector((math.cos(angle) * radius, math.sin(angle) * radius, z - .25 + level * .05))
            branch_segments.append((start, end, .11 - level * .006, .018, 6))
            endpoints.append(end)
    add_segment_mesh("TreeBranches", branch_segments, bark)
    vertices, faces = [], []
    # Dense, overlapping needle sprays keep the silhouette full in motion
    # without resorting to the old stack of cone primitives.
    for index in range(1900):
        endpoint = endpoints[index % len(endpoints)]
        direction = Vector((endpoint.x, endpoint.y, -.12)).normalized()
        center = endpoint * random.uniform(.30, 1.02) + Vector((
            random.gauss(0, .23), random.gauss(0, .23), random.gauss(0, .28)
        ))
        forward = (direction + Vector((
            random.uniform(-.34, .34), random.uniform(-.34, .34), random.uniform(-.34, .34)
        ))).normalized()
        common.append_leaf(vertices, faces, center, forward, .085, .55, .018)
    common.mesh_object("TreeLeaves", vertices, faces, needle_mat)
    export_species("pine")


def _segments_to_mesh(segments):
    vertices, faces = [], []
    for start, end, r0, r1, sides in segments:
        common.append_tapered_segment(vertices, faces, start, end, r0, r1, sides)
    return vertices, faces


if __name__ == "__main__":
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    build_birch()
    build_maple()
    build_pine()
