"""Build a genuinely continuous hero head, neck, collar, and body mesh.

This pass keeps the accepted professional face above the lower neck.  It
removes the sealed overlap cap and bridges the head into the body's open
collar with two weight-blended transition rings.  The result is one closed,
skinned surface instead of two overlapping shells.
"""

import bmesh
import bpy
from collections import defaultdict
from mathutils import Vector
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_DIR = os.path.dirname(os.path.abspath(bpy.data.filepath))
EXPECTED_INPUT = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master.blend")
OUTPUT_BLEND = os.path.join(BLEND_DIR, "BrokenKnight_Hero_Master_HeadBody_WIP.blend")
HEAD_JOIN_Z = 1.59780


def ensure_object_mode():
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def remove_head_overlap_below_join(head):
    """Discard only the four old overlap/cap levels below the neck join."""
    bm = bmesh.new()
    bm.from_mesh(head.data)
    remove = [vertex for vertex in bm.verts if vertex.co.z < HEAD_JOIN_Z]
    if not remove:
        bm.free()
        raise RuntimeError("The professional head has no removable overlap cap")
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(head.data)
    bm.free()
    head.data.update()

    # Bring the hidden lower neck back toward the torso centerline and give
    # the rear neck enough mass to meet the trapezius without a thin shelf.
    for vertex in head.data.vertices:
        if vertex.co.z >= 1.667:
            continue
        amount = max(0.0, min(1.0, (1.667 - vertex.co.z) / (1.667 - HEAD_JOIN_Z)))
        amount = amount * amount * (3.0 - 2.0 * amount)
        # Keep the jaw/upper neck authored shape, then open the base into a
        # stronger sternocleidomastoid/trapezius transition instead of the
        # straight-sided tower produced by the old sealed overlap.
        vertex.co.x *= 1.0 + 0.070 * amount
        center_y = -0.030
        vertex.co.y = center_y + (vertex.co.y - center_y) * (1.0 + 0.090 * amount)
        vertex.co.y += 0.011 * amount
        if vertex.co.y > 0.0:
            vertex.co.y += 0.010 * amount * min(1.0, vertex.co.y / 0.045)
    head.data.update()


def boundary_components(bm):
    edges = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    adjacency = defaultdict(list)
    for edge in edges:
        a, b = edge.verts
        adjacency[a].append(b)
        adjacency[b].append(a)
    components = []
    unseen = set(adjacency)
    while unseen:
        seed = unseen.pop()
        stack = [seed]
        component = {seed}
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    stack.append(neighbor)
                    component.add(neighbor)
        if any(len(adjacency[vertex]) != 2 for vertex in component):
            raise RuntimeError("A head/body boundary is not a simple closed loop")
        components.append((component, adjacency))
    return components


def ordered_loop(component, adjacency):
    start = min(component, key=lambda vertex: (vertex.co.y, abs(vertex.co.x), vertex.co.x))
    ordered = [start]
    previous = None
    current = start
    while True:
        candidates = [neighbor for neighbor in adjacency[current] if neighbor is not previous]
        if not candidates:
            raise RuntimeError("Open chain found while ordering neck boundary")
        next_vertex = candidates[0]
        if next_vertex is start:
            break
        if next_vertex in ordered:
            if len(candidates) > 1 and candidates[1] not in ordered:
                next_vertex = candidates[1]
            else:
                raise RuntimeError("Self-intersecting neck boundary traversal")
        ordered.append(next_vertex)
        previous, current = current, next_vertex
        if len(ordered) > len(component):
            raise RuntimeError("Neck boundary traversal did not terminate")
    if len(ordered) != len(component):
        raise RuntimeError(f"Incomplete neck boundary: {len(ordered)} of {len(component)} vertices")

    area = 0.0
    for index, vertex in enumerate(ordered):
        following = ordered[(index + 1) % len(ordered)]
        area += vertex.co.x * following.co.y - following.co.x * vertex.co.y
    if area < 0.0:
        ordered = [ordered[0], *reversed(ordered[1:])]
    return ordered


def perimeter_parameters(loop):
    lengths = []
    total = 0.0
    for index, vertex in enumerate(loop):
        length = (loop[(index + 1) % len(loop)].co - vertex.co).length
        lengths.append(length)
        total += length
    if total <= 1e-8:
        raise RuntimeError("Degenerate neck boundary perimeter")
    parameters = [0.0]
    running = 0.0
    for length in lengths[:-1]:
        running += length
        parameters.append(running / total)
    return parameters, lengths, total


def sample_loop(loop, parameters, lengths, total, value, deform_layer):
    value %= 1.0
    for index, start in enumerate(parameters):
        end = parameters[index + 1] if index + 1 < len(parameters) else 1.0
        if value <= end + 1e-10:
            span = max(end - start, 1e-10)
            factor = max(0.0, min(1.0, (value - start) / span))
            a = loop[index]
            b = loop[(index + 1) % len(loop)]
            coordinate = a.co.lerp(b.co, factor)
            weights = defaultdict(float)
            for group, weight in a[deform_layer].items():
                weights[group] += weight * (1.0 - factor)
            for group, weight in b[deform_layer].items():
                weights[group] += weight * factor
            return coordinate, weights
    raise RuntimeError("Failed to sample neck boundary")


def mixed_weights(lower, upper, amount):
    result = defaultdict(float)
    for group, weight in lower.items():
        result[group] += weight * (1.0 - amount)
    for group, weight in upper.items():
        result[group] += weight * amount
    total = sum(result.values())
    if total <= 1e-8:
        raise RuntimeError("Generated an unweighted neck transition vertex")
    return {group: weight / total for group, weight in result.items() if weight / total > 1e-6}


def create_transition_ring(bm, body_loop, body_params, body_lengths, body_total,
                           head_loop, head_params, deform_layer, amount):
    ring = []
    for index, head_vertex in enumerate(head_loop):
        parameter = head_params[index]
        body_co, body_weights = sample_loop(
            body_loop, body_params, body_lengths, body_total, parameter, deform_layer,
        )
        smooth = amount * amount * (3.0 - 2.0 * amount)
        coordinate = body_co.lerp(head_vertex.co, smooth)

        # The body's existing collar hole spans far into both clavicles. Pull
        # the lower bridge inward before it reaches the actual neck so the
        # surface reads as sloped trapezius rather than a vertical rectangle.
        collar = 1.0 - smooth
        coordinate.x *= 1.0 - 0.105 * collar

        # The rear lower transition is trapezius, not a straight conical tube.
        posterior = max(0.0, min(1.0, (coordinate.y + 0.005) / 0.090))
        lower_bias = max(0.0, 1.0 - amount)
        coordinate.y += 0.006 * posterior * lower_bias
        coordinate.z += 0.004 * posterior * lower_bias

        vertex = bm.verts.new(coordinate)
        weights = mixed_weights(body_weights, dict(head_vertex[deform_layer]), smooth)
        for group, weight in weights.items():
            vertex[deform_layer][group] = weight
        ring.append(vertex)
    return ring


def add_face(bm, vertices):
    compact = []
    for vertex in vertices:
        if not compact or compact[-1] is not vertex:
            compact.append(vertex)
    if len(compact) >= 3 and compact[0] is compact[-1]:
        compact.pop()
    if len(set(compact)) < 3:
        return None
    try:
        return bm.faces.new(compact)
    except ValueError as error:
        raise RuntimeError("Duplicate or invalid face while bridging the neck") from error


def bridge_parameterized(bm, lower, lower_parameters, upper, upper_parameters):
    lower_closed = lower + [lower[0]]
    upper_closed = upper + [upper[0]]
    lower_t = lower_parameters + [1.0]
    upper_t = upper_parameters + [1.0]
    i = 0
    j = 0
    faces = []
    epsilon = 1e-8
    while i < len(lower) or j < len(upper):
        next_lower = lower_t[i + 1] if i < len(lower) else float("inf")
        next_upper = upper_t[j + 1] if j < len(upper) else float("inf")
        if abs(next_lower - next_upper) <= epsilon:
            face = add_face(bm, (lower_closed[i], lower_closed[i + 1], upper_closed[j + 1], upper_closed[j]))
            i += 1
            j += 1
        elif next_lower < next_upper:
            face = add_face(bm, (lower_closed[i], lower_closed[i + 1], upper_closed[j]))
            i += 1
        else:
            face = add_face(bm, (lower_closed[i], upper_closed[j + 1], upper_closed[j]))
            j += 1
        if face is not None:
            faces.append(face)
    return faces


def bridge_equal_rings(bm, lower, upper):
    if len(lower) != len(upper):
        raise RuntimeError("Equal-ring bridge received mismatched loops")
    faces = []
    for index in range(len(lower)):
        faces.append(
            add_face(
                bm,
                (
                    lower[index], lower[(index + 1) % len(lower)],
                    upper[(index + 1) % len(upper)], upper[index],
                ),
            )
        )
    return [face for face in faces if face is not None]


def join_and_bridge(body, head, rig):
    # The active body owns the one final modifier stack. The redundant head
    # armature modifier must not survive the object join.
    for modifier in list(head.modifiers):
        if modifier.type == "ARMATURE":
            head.modifiers.remove(modifier)
    ensure_object_mode()
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    head.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()

    if bpy.data.objects.get("ProfessionalHead") is not None:
        raise RuntimeError("ProfessionalHead remained separate after mesh join")
    if body.name != "ConnectedBody":
        body.name = "ConnectedBody"

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    deform_layer = bm.verts.layers.deform.verify()
    components = boundary_components(bm)
    if len(components) != 2:
        bm.free()
        raise RuntimeError(f"Expected body and head openings; found {len(components)} boundary components")
    loops = [ordered_loop(component, adjacency) for component, adjacency in components]
    loops.sort(key=lambda loop: sum(vertex.co.z for vertex in loop) / len(loop))
    body_loop, head_loop = loops
    if len(body_loop) != 44 or len(head_loop) != 102:
        bm.free()
        raise RuntimeError(f"Unexpected connection loops: body={len(body_loop)}, head={len(head_loop)}")

    body_params, body_lengths, body_total = perimeter_parameters(body_loop)
    head_params, _head_lengths, _head_total = perimeter_parameters(head_loop)
    lower_transition = create_transition_ring(
        bm, body_loop, body_params, body_lengths, body_total,
        head_loop, head_params, deform_layer, 0.30,
    )
    upper_transition = create_transition_ring(
        bm, body_loop, body_params, body_lengths, body_total,
        head_loop, head_params, deform_layer, 0.64,
    )
    faces = []
    faces.extend(bridge_parameterized(bm, body_loop, body_params, lower_transition, head_params))
    faces.extend(bridge_equal_rings(bm, lower_transition, upper_transition))
    faces.extend(bridge_equal_rings(bm, upper_transition, head_loop))
    for face in faces:
        face.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()

    material = bpy.data.materials.get("HeroSkin.ProfessionalWIP")
    if material is None:
        raise RuntimeError("Professional skin material is missing")
    body.data.materials.clear()
    body.data.materials.append(material)
    for polygon in body.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
    material.diffuse_color[3] = 1.0
    if material.use_nodes:
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            alpha = node.inputs.get("Alpha")
            if alpha is not None:
                for link in list(alpha.links):
                    material.node_tree.links.remove(link)
                alpha.default_value = 1.0

    armatures = [modifier for modifier in body.modifiers if modifier.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Unified body has {len(armatures)} armature modifiers")
    armatures[0].object = rig
    armatures[0].use_deform_preserve_volume = True
    for modifier in body.modifiers:
        if modifier.type == "SUBSURF":
            modifier.levels = 1
            modifier.render_levels = 1

    body["head_replacement"] = "ProfessionalHeadTopologyUnified"
    body["neck_topology"] = "continuous_head_body_three_ring_bridge"
    body["head_body_connection"] = "single_closed_skinned_surface"
    body["integration_state"] = "WIP_reviewed_not_canonical"
    return body, len(faces)


def validate(body, rig, face_count):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    boundary_edges = sum(1 for edge in bm.edges if len(edge.link_faces) == 1)
    nonmanifold_edges = sum(1 for edge in bm.edges if len(edge.link_faces) != 2)
    bm.free()
    if boundary_edges or nonmanifold_edges:
        raise RuntimeError(
            f"Unified hero is not closed: boundary={boundary_edges}, nonmanifold={nonmanifold_edges}"
        )

    underweighted = 0
    minimum = 10.0
    maximum = 0.0
    for vertex in body.data.vertices:
        total = sum(membership.weight for membership in vertex.groups)
        minimum = min(minimum, total)
        maximum = max(maximum, total)
        if total < 0.999:
            underweighted += 1
    if underweighted:
        raise RuntimeError(f"Unified hero has {underweighted} underweighted vertices")

    actions = sorted(action.name for action in bpy.data.actions)
    for required in ("Idle", "Walk", "Jump", "Roll", "SwordSlash"):
        if required not in actions:
            raise RuntimeError(f"Required action was lost: {required}")
    print(
        f"HEAD_BODY_UNIFIED|object={body.name}|verts={len(body.data.vertices)}|"
        f"faces={len(body.data.polygons)}|bridge_faces={face_count}|"
        f"boundary_edges={boundary_edges}|nonmanifold_edges={nonmanifold_edges}"
    )
    print(
        f"HEAD_BODY_WEIGHTS|min={minimum:.6f}|max={maximum:.6f}|"
        f"underweighted={underweighted}|rig={rig.name}"
    )
    print(f"HEAD_BODY_ACTIONS|preserved={len(actions)}")


def main():
    current = os.path.normcase(os.path.abspath(bpy.data.filepath))
    allowed = os.path.normcase(os.path.abspath(os.environ.get("BK_HEAD_BODY_INPUT", EXPECTED_INPUT)))
    if current != allowed:
        raise RuntimeError(f"Run only against approved head/body input; got {bpy.data.filepath}")
    body = bpy.data.objects.get("ConnectedBody")
    head = bpy.data.objects.get("ProfessionalHead")
    rig = bpy.data.objects.get("HeroRig")
    if body is None or body.type != "MESH":
        raise RuntimeError("ConnectedBody is missing")
    if head is None or head.type != "MESH":
        raise RuntimeError("ProfessionalHead is missing")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("HeroRig is missing")

    actions_before = sorted(action.name for action in bpy.data.actions)
    remove_head_overlap_below_join(head)
    body, face_count = join_and_bridge(body, head, rig)
    if sorted(action.name for action in bpy.data.actions) != actions_before:
        raise RuntimeError("Animation actions changed during head/body unification")
    validate(body, rig, face_count)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"HEAD_BODY_WIP_DONE|{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
