"""Build a reference-driven fitted royal armor candidate on the locked hero.

Unlike the rejected block/prism pass, every visible panel is sampled from the
hero or its supporting cuirass.  The result uses curved, seated hard-surface
plates with buried edge trim and keeps the accepted body and rig untouched.
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.abspath(os.environ.get(
    "BK_REFERENCE_FITTED_OUTPUT",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_ReferenceFittedArmorCandidate.blend"),
))
PASS_ID = "ReferenceFittedRoyalArmor20260813V1"
PREFIX = "RoyalArmor_"
BODY = bpy.data.objects["ConnectedBody"]
RIG = bpy.data.objects["HeroRig"]


def mat(name):
    result = bpy.data.materials.get(name)
    if result is None:
        raise RuntimeError("Missing material: " + name)
    return result


COBALT = mat("Royal Cobalt Filigree Plate")
STEEL = mat("Royal Blued Steel")
DARK = mat("Royal Blackened Steel")
BRASS = mat("Royal Gilt Brass")
BRIGHT = mat("Royal Planished Edge Steel")
MAIL = mat("Riveted Mail")
CRIMSON = mat("Ducal Crimson Horsehair")
CRIMSON_DARK = mat("Ducal Horsehair Shadow")


def armor_collection(slot):
    root = bpy.data.collections.get("10_ROYAL_ARMOR")
    if root is None:
        root = bpy.data.collections.new("10_ROYAL_ARMOR")
        bpy.context.scene.collection.children.link(root)
    name = {
        "head": "10A_ARMOR_HEAD", "chest": "10B_ARMOR_CHEST",
        "shoulders": "10C_ARMOR_SHOULDERS", "hands": "10D_ARMOR_HANDS",
        "pants": "10E_ARMOR_PANTS", "feet": "10F_ARMOR_FEET",
    }[slot]
    result = bpy.data.collections.get(name)
    if result is None:
        result = bpy.data.collections.new(name)
        root.children.link(result)
    return result


def remove_slot(slot):
    prefix = f"{PREFIX}{slot}_"
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefix):
            bpy.data.objects.remove(obj, do_unlink=True)


def mesh_object(slot, part, vertices, faces, materials, smooth=False):
    name = f"{PREFIX}{slot}_{part}"
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    armor_collection(slot).objects.link(obj)
    for material in materials:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    obj["bk_geometry_pass"] = PASS_ID
    obj["bk_reference_fitted"] = True
    return obj


def armature(obj):
    obj.parent = RIG
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = RIG


def rigid_skin(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    armature(obj)


def group_indices(names):
    result = set()
    for name in names:
        group = BODY.vertex_groups.get(name)
        if group is not None:
            result.add(group.index)
    if not result:
        raise RuntimeError("No body groups for " + ", ".join(names))
    return result


def vertex_has_group(vertex, indices, minimum=.002):
    return any(item.group in indices and item.weight >= minimum for item in vertex.groups)


def body_front_y(x, z, groups):
    indices = group_indices(groups)
    candidates = []
    for vertex in BODY.data.vertices:
        if not vertex_has_group(vertex, indices):
            continue
        distance = ((vertex.co.x - x) / .055) ** 2 + ((vertex.co.z - z) / .055) ** 2
        candidates.append((distance, vertex.co.y))
    if not candidates:
        raise RuntimeError(f"No body surface near x={x:.3f}, z={z:.3f}")
    candidates.sort(key=lambda item: item[0])
    nearby = sorted(value for _, value in candidates[:36])
    return sum(nearby[:max(3, len(nearby) // 5)]) / max(3, len(nearby) // 5)


def object_front_y(obj, x, z):
    candidates = []
    for vertex in obj.data.vertices:
        point = obj.matrix_world @ vertex.co
        distance = ((point.x - x) / .060) ** 2 + ((point.z - z) / .060) ** 2
        candidates.append((distance, point.y))
    candidates.sort(key=lambda item: item[0])
    nearby = sorted(value for _, value in candidates[:48])
    return sum(nearby[:max(4, len(nearby) // 6)]) / max(4, len(nearby) // 6)


def tube(slot, part, points, radius, material, bone, sides=8):
    radii = [radius] * len(points) if isinstance(radius, (int, float)) else list(radius)
    vertices = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
        if normal.length < .00001:
            normal = tangent.cross(Vector((0.0, 1.0, 0.0)))
        normal.normalize()
        binormal = tangent.cross(normal).normalized()
        for side in range(sides):
            angle = math.tau * side / sides
            offset = normal * math.cos(angle) * radii[index] + binormal * math.sin(angle) * radii[index]
            vertices.append(tuple(Vector(point) + offset))
    faces = []
    for ring in range(len(points) - 1):
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((ring * sides + side, ring * sides + nxt, (ring + 1) * sides + nxt, (ring + 1) * sides + side))
    obj = mesh_object(slot, part, vertices, faces, [material], True)
    rigid_skin(obj, bone)
    return obj


def surface_patch(slot, part, rows, source, source_groups, plate_material, bone, outward=.014, columns=12, bulge=.004, thickness=.006):
    """Create a curved grid patch following a body or armor front surface.

    rows are (z, left_x, right_x).  The patch perimeter follows those rows;
    all interior points sample the supporting surface before a restrained
    convex planishing offset is applied.
    """
    vertices = []
    points_by_row = []
    for z, left, right in rows:
        row_points = []
        for column in range(columns):
            ratio = column / (columns - 1)
            x = left + (right - left) * ratio
            base_y = body_front_y(x, z, source_groups) if source is BODY else object_front_y(source, x, z)
            crown = math.sin(math.pi * ratio) * bulge
            point = (x, base_y - outward - crown, z)
            row_points.append(point)
            vertices.append(point)
        points_by_row.append(row_points)
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            current = row * columns + column
            faces.append((current, current + 1, current + columns + 1, current + columns))
    obj = mesh_object(slot, part, vertices, faces, [plate_material, BRASS, DARK], True)
    rigid_skin(obj, bone)
    solidify = obj.modifiers.new("SeatedForgedThickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = 1.0
    solidify.material_offset_rim = 1
    bevel = obj.modifiers.new("RolledPlatePerimeter", "BEVEL")
    bevel.width = .0022
    bevel.segments = 3

    # A single closed perimeter tube is centred only 1 mm outside the panel,
    # leaving most of the gilt edge buried in the plate.
    outline = []
    outline.extend(points_by_row[0])
    outline.extend(row[-1] for row in points_by_row[1:])
    outline.extend(reversed(points_by_row[-1][:-1]))
    outline.extend(row[0] for row in reversed(points_by_row[1:-1]))
    outline.append(outline[0])
    outline = [(x, y - .001, z) for x, y, z in outline]
    tube(slot, part + "IntegralGiltEdge", outline, .0032, BRASS, bone, 7)
    return obj


def build_face_patch():
    for obj in list(bpy.data.objects):
        if obj.name.startswith("ProfessionalHelmetFace"):
            bpy.data.objects.remove(obj, do_unlink=True)
    indices = group_indices(("head", "neck"))
    keep = [
        vertex_has_group(vertex, indices, .005)
        and 1.585 < vertex.co.z < 1.845
        and abs(vertex.co.x) < .115
        and vertex.co.y < -.055
        for vertex in BODY.data.vertices
    ]
    polygons = [tuple(poly.vertices) for poly in BODY.data.polygons if all(keep[index] for index in poly.vertices)]
    used = sorted({index for polygon in polygons for index in polygon})
    remap = {source: target for target, source in enumerate(used)}
    vertices = [tuple(BODY.data.vertices[index].co + BODY.data.vertices[index].normal * .0005) for index in used]
    faces = [tuple(remap[index] for index in polygon) for polygon in polygons]
    mesh = bpy.data.meshes.new("ProfessionalHelmetFace_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate();mesh.update()
    obj = bpy.data.objects.new("ProfessionalHelmetFace", mesh)
    BODY.users_collection[0].objects.link(obj)
    skin_material = next((material for material in BODY.data.materials if material and "skin" in material.name.lower()), BODY.data.materials[0])
    mesh.materials.append(skin_material)
    for polygon in mesh.polygons:polygon.use_smooth=True
    for group in BODY.vertex_groups:obj.vertex_groups.new(name=group.name)
    for source, target in remap.items():
        for item in BODY.data.vertices[source].groups:
            obj.vertex_groups[item.group].add([target], item.weight, "REPLACE")
    armature(obj)
    obj.hide_render = True
    obj["bk_helmet_face_patch"] = True


def helmet_surface(rings, x, z):
    lower = rings[0]
    upper = rings[-1]
    for index in range(len(rings) - 1):
        if rings[index][0] <= z <= rings[index + 1][0]:
            lower, upper = rings[index], rings[index + 1]
            break
    ratio = (z - lower[0]) / max(.0001, upper[0] - lower[0])
    rx = lower[1] + (upper[1] - lower[1]) * ratio
    front = lower[2] + (upper[2] - lower[2]) * ratio
    normalized = min(.999, abs(x) / max(.001, rx))
    return -front * math.sqrt(max(.001, 1.0 - normalized * normalized))


def build_helmet():
    remove_slot("head")
    rings = [
        (1.575, .118, .154, .116), (1.635, .130, .178, .120),
        (1.705, .138, .184, .118), (1.770, .140, .174, .115),
        (1.825, .136, .151, .111), (1.875, .119, .119, .103),
        (1.915, .080, .078, .075), (1.935, .018, .018, .018),
    ]
    segments = 80
    vertices = []
    for z, half_x, front, rear in rings:
        for column in range(segments):
            angle = math.tau * column / segments
            x = half_x * math.cos(angle)
            y = (rear if math.sin(angle) >= 0 else front) * math.sin(angle)
            vertices.append((x, y, z))
    faces = []
    materials = []
    for row in range(len(rings) - 1):
        z_mid = (rings[row][0] + rings[row + 1][0]) * .5
        for column in range(segments):
            nxt = (column + 1) % segments
            angle = math.tau * (column + .5) / segments
            front_delta = abs((angle - math.pi * 1.5 + math.pi) % math.tau - math.pi)
            if z_mid < 1.805 and front_delta < .78:
                continue
            faces.append((row * segments + column, row * segments + nxt, (row + 1) * segments + nxt, (row + 1) * segments + column))
            materials.append(1 if front_delta < 1.25 else (2 if z_mid < 1.66 else 0))
    faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
    materials.append(0)
    shell = mesh_object("head", "ReferenceOpenCrownedArmet", vertices, faces, [STEEL, COBALT, DARK, BRASS], True)
    rigid_skin(shell, "head")
    for polygon, material_index in zip(shell.data.polygons, materials):polygon.material_index=material_index
    solidify=shell.modifiers.new("ForgedHelmetThickness","SOLIDIFY");solidify.thickness=.008;solidify.offset=-1.0
    bevel=shell.modifiers.new("RolledFaceOpening","BEVEL");bevel.width=.0025;bevel.segments=3

    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        rows = [
            (1.790, side * .128, side * .082),
            (1.735, side * .137, side * .073),
            (1.660, side * .132, side * .078),
            (1.600, side * .118, side * .090),
        ]
        ordered=[]
        for z,a,b in rows:ordered.append((z,min(a,b),max(a,b)))
        points=[];cols=7
        for z,left,right in ordered:
            for column in range(cols):
                ratio=column/(cols-1);x=left+(right-left)*ratio
                points.append((x,helmet_surface(rings,x,z)-.006,z))
        faces=[]
        for row in range(len(ordered)-1):
            for column in range(cols-1):
                i=row*cols+column;faces.append((i,i+1,i+cols+1,i+cols))
        guard=mesh_object("head",f"ReferenceCurvedCheekGuard{suffix}",points,faces,[COBALT,BRASS,DARK],True)
        rigid_skin(guard,"head")
        solid=guard.modifiers.new("CurvedCheekThickness","SOLIDIFY");solid.thickness=.006;solid.offset=1.0;solid.material_offset_rim=1
        edge=guard.modifiers.new("CheekRolledEdge","BEVEL");edge.width=.002;edge.segments=3
        inner=[]
        for z,left,right in ordered:
            x=right if side<0 else left
            inner.append((x,helmet_surface(rings,x,z)-.008,z))
        tube("head",f"ReferenceCheekInsetEdge{suffix}",inner,.0035,BRASS,"head",7)

    brow=[]
    for index in range(17):
        x=-.128+index*.016
        brow.append((x,helmet_surface(rings,x,1.792)-.009,1.792+.010*math.cos(x/.128*math.pi*.5)))
    tube("head","ReferenceIntegralCrownBrow",brow,.0055,BRASS,"head",8)
    # Three restrained seated prongs form a crown without a row of pasted-on
    # triangles.  Each is a thick tapered tube rooted inside the brow rail.
    for index,x in enumerate((-.070,0.0,.070)):
        y=helmet_surface(rings,x,1.80)-.008
        top=1.865 if index==1 else 1.840
        tube("head",f"ReferenceSeatedCrownProng{index}",[(x,y,1.795),(x,y+.003,top)],(.0065,.003),BRASS,"head",8)

    # A broad layered horsehair silhouette made from swept ribbons, not wires.
    for index in range(15):
        lateral=(index-7)*.0065
        layer=(index%3)*.012
        path=[
            (lateral,-.002+layer,1.925),
            (lateral*.95,.055+layer,2.015),
            (lateral*.85,.145+layer,2.070+.008*math.sin(index)),
            (lateral*.75,.255+layer,2.045),
            (lateral*.65,.370+layer,1.955-.006*(index%4)),
            (lateral*.55,.465+layer,1.820-.008*(index%5)),
        ]
        width=.010 if index%2 else .013
        verts=[]
        for point_index,point in enumerate(path):
            taper=1.0-point_index/(len(path)-1)*.72
            verts.append((point[0]-width*taper*.5,point[1],point[2]))
            verts.append((point[0]+width*taper*.5,point[1],point[2]))
        ribbon_faces=[]
        for row in range(len(path)-1):ribbon_faces.append((row*2,row*2+1,row*2+3,row*2+2))
        ribbon=mesh_object("head",f"ReferenceSweptHorsehair{index:02d}",verts,ribbon_faces,[CRIMSON if index%4 else CRIMSON_DARK],True)
        rigid_skin(ribbon,"head")
        solid=ribbon.modifiers.new("HorsehairRibbonBody","SOLIDIFY");solid.thickness=.003;solid.offset=0
        bevel=ribbon.modifiers.new("SoftHorsehairEdge","BEVEL");bevel.width=.001;bevel.segments=2


def build_chest_layers():
    chest = bpy.data.objects.get("RoyalArmor_chest_SovereignConsolidated")
    if chest is None:
        raise RuntimeError("Accepted consolidated cuirass is missing")
    surface_patch("chest","ReferencePectoralPlateL",[(1.505,-.275,-.025),(1.405,-.300,-.020),(1.300,-.265,-.035)],chest,None,STEEL,"chest",.008,11,.004,.006)
    surface_patch("chest","ReferencePectoralPlateR",[(1.505,.025,.275),(1.405,.020,.300),(1.300,.035,.265)],chest,None,STEEL,"chest",.008,11,.004,.006)
    # A low V plackart overlaps the lower edges of both breast plates and the
    # accepted shell, creating the reference's tapered waist construction.
    surface_patch("chest","ReferenceWaistedPlackart",[(1.315,-.260,.260),(1.190,-.275,.275),(1.075,-.235,.235)],chest,None,COBALT,"chest",.010,13,.003,.006)

    for side in (-1.0,1.0):
        suffix="L" if side<0 else "R"
        if side<0: rows=[(.930,-.255,-.045),(.790,-.245,-.055),(.635,-.205,-.075)]
        else: rows=[(.930,.045,.255),(.790,.055,.245),(.635,.075,.205)]
        surface_patch("chest",f"ReferenceSuspendedTasset{suffix}",rows,BODY,("pelvis",f"thigh.{suffix}"),COBALT,"pelvis",.030,11,.005,.007)


def build_leg_layers():
    for side in (-1.0,1.0):
        suffix="L" if side<0 else "R"
        center=-.145 if side<0 else .145
        surface_patch("pants",f"ReferenceCuisse{suffix}",[(.910,center-.080,center+.080),(.720,center-.090,center+.090),(.515,center-.060,center+.060)],BODY,(f"thigh.{suffix}",),STEEL,f"thigh.{suffix}",.026,11,.004,.007)
        surface_patch("feet",f"ReferencePoleyn{suffix}",[(.620,center-.070,center+.070),(.545,center-.098,center+.098),(.445,center-.066,center+.066)],BODY,(f"thigh.{suffix}",f"shin.{suffix}"),COBALT,f"shin.{suffix}",.034,11,.006,.008)
        surface_patch("feet",f"ReferenceGreave{suffix}",[(.495,center-.078,center+.078),(.300,center-.074,center+.074),(.105,center-.055,center+.055)],BODY,(f"shin.{suffix}",),STEEL,f"shin.{suffix}",.028,11,.004,.007)


def main():
    RIG.data.pose_position="REST";bpy.context.scene.frame_set(1)
    build_face_patch()
    build_helmet()
    build_chest_layers()
    build_leg_layers()
    RIG.data.pose_position="POSE"
    RIG.animation_data.action=bpy.data.actions.get("WarriorIdle") or bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.scene["bk_armor_visual_pass"]=PASS_ID
    bpy.context.scene["bk_reference_build_method"]="curved_surface_sampled_no_planar_prisms"
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT,check_existing=False)
    print("REFERENCE_FITTED_ARMOR|file=%s|pass=%s"%(OUTPUT,PASS_ID))


if __name__=="__main__":main()
