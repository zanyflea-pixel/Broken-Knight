"""Fit a detailed blue-and-gold Royal Vanguard armor set to the rigged hero."""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RIGGED = os.path.join(ROOT, "blender", "hero_restart_rigged.blend")
PREFIX = "RoyalArmor_"


def mat(name, color, metallic, roughness):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    material["export_metallic"] = metallic
    material["export_roughness"] = roughness
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def textured_mat(name, color, metallic, roughness, image_path, normal_path=None, roughness_path=None):
    material=mat(name,color,metallic,roughness)
    tree=material.node_tree
    bsdf=tree.nodes.get("Principled BSDF")
    for node in list(tree.nodes):
        if node.name in (
            "RoyalSurfaceTexture","RoyalNormalTexture","RoyalNormalMap",
            "RoyalRoughnessTexture","RoyalPlateBaseColor","RoyalSubtleEngravingMix",
        ):
            tree.nodes.remove(node)
    image=bpy.data.images.load(image_path,check_existing=True)
    texture=tree.nodes.new("ShaderNodeTexImage")
    texture.name="RoyalSurfaceTexture"
    texture.label="Royal Cobalt Filigree"
    texture.image=image
    texture.extension="REPEAT"
    base=tree.nodes.new("ShaderNodeRGB")
    base.name="RoyalPlateBaseColor"
    base.outputs[0].default_value=color
    mix=tree.nodes.new("ShaderNodeMixRGB")
    mix.name="RoyalSubtleEngravingMix"
    mix.blend_type="MIX"
    mix.inputs[0].default_value=.23
    tree.links.new(base.outputs[0],mix.inputs[1])
    tree.links.new(texture.outputs["Color"],mix.inputs[2])
    tree.links.new(mix.outputs["Color"],bsdf.inputs["Base Color"])
    if normal_path:
        normal_image=bpy.data.images.load(normal_path,check_existing=True)
        normal_image.colorspace_settings.name="Non-Color"
        normal_texture=tree.nodes.new("ShaderNodeTexImage")
        normal_texture.name="RoyalNormalTexture"
        normal_texture.image=normal_image
        normal_texture.extension="REPEAT"
        normal_map=tree.nodes.new("ShaderNodeNormalMap")
        normal_map.name="RoyalNormalMap"
        normal_map.inputs["Strength"].default_value=.30
        tree.links.new(normal_texture.outputs["Color"],normal_map.inputs["Color"])
        tree.links.new(normal_map.outputs["Normal"],bsdf.inputs["Normal"])
    if roughness_path:
        roughness_image=bpy.data.images.load(roughness_path,check_existing=True)
        roughness_image.colorspace_settings.name="Non-Color"
        roughness_texture=tree.nodes.new("ShaderNodeTexImage")
        roughness_texture.name="RoyalRoughnessTexture"
        roughness_texture.image=roughness_image
        roughness_texture.extension="REPEAT"
        tree.links.new(roughness_texture.outputs["Color"],bsdf.inputs["Roughness"])
    return material


def remove_previous():
    for obj in list(bpy.data.objects):
        if obj.name.startswith(PREFIX):
            bpy.data.objects.remove(obj, do_unlink=True)


def skin(obj, arm, bone, material, smooth=True):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    obj.data.materials.append(material)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("RoyalArmorRig", "ARMATURE")
    modifier.object = arm
    obj.parent = arm
    obj.select_set(False)
    return obj


def sphere(slot, name, location, scale, material, arm, bone, segments=28, rings=18):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = f"{PREFIX}{slot}_{name}"
    obj.scale = scale
    return skin(obj, arm, bone, material)


def box(slot, name, location, size, material, arm, bone, rotation=(0, 0, 0), bevel=.008):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = f"{PREFIX}{slot}_{name}"
    obj.scale = Vector(size) * .5
    skin(obj, arm, bone, material, False)
    if bevel > 0:
        mod = obj.modifiers.new("ForgedEdges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def cone_between(slot, name, start, end, r1, r2, material, arm, bone, vertices=24):
    start, end = Vector(start), Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=delta.length, location=(start + end) * .5)
    obj = bpy.context.object
    obj.name = f"{PREFIX}{slot}_{name}"
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return skin(obj, arm, bone, material)


def cylinder(slot, name, location, radius, depth, material, arm, bone, rotation=(0, 0, 0), vertices=28):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = f"{PREFIX}{slot}_{name}"
    return skin(obj, arm, bone, material)


def torus(slot, name, location, major, minor, material, arm, bone, rotation=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=10, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = f"{PREFIX}{slot}_{name}"
    obj.scale = scale
    return skin(obj, arm, bone, material)


def plate(slot, name, vertices, faces, material, arm, bone):
    mesh = bpy.data.meshes.new(f"{PREFIX}{slot}_{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"{PREFIX}{slot}_{name}", mesh)
    bpy.context.collection.objects.link(obj)
    return skin(obj, arm, bone, material, False)


def forged_prism(slot, name, outline, front_y, back_y, material, arm, bone, bevel=.006):
    """Build a closed tapered plate from an X/Z outline."""
    count=len(outline)
    vertices=[(x,front_y,z) for x,z in outline]+[(x,back_y,z) for x,z in outline]
    faces=[tuple(range(count)),tuple(range(count*2-1,count-1,-1))]
    for index in range(count):
        nxt=(index+1)%count
        faces.append((index,nxt,nxt+count,index+count))
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    if bevel>0:
        modifier=obj.modifiers.new("HandRolledEdges","BEVEL");modifier.width=bevel;modifier.segments=3
    return obj


def convex_panel(slot, name, boundary, center, material, arm, bone, thickness=.006, bevel=.003, accent_material=None):
    """Create a shallow forged panel with a deliberately crowned center."""
    vertices=list(boundary)+[center]
    hub=len(boundary)
    faces=[]
    for index in range(len(boundary)):
        faces.append((index,(index+1)%len(boundary),hub))
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    if accent_material is not None:
        obj.data.materials.append(accent_material)
        for polygon in obj.data.polygons:
            if polygon.index%2:
                polygon.material_index=1
    solid=obj.modifiers.new("ForgedThickness","SOLIDIFY");solid.thickness=thickness;solid.offset=0.0
    edge=obj.modifiers.new("SoftForgedEdge","BEVEL");edge.width=bevel;edge.segments=2
    for polygon in obj.data.polygons:polygon.use_smooth=True
    return obj


def bordered_panel(slot, name, boundary, center, material, border_material, arm, bone, inset=.13, thickness=.008, bevel=.003):
    """One crowned plate with an integrated contrasting border.

    The border and center share vertices and deform as one object, so this
    replaces the loose trim rods that used to hover in side views.
    """
    outer=[Vector(point) for point in boundary]
    hub=Vector(center)
    inner=[point.lerp(hub,inset) for point in outer]
    vertices=[tuple(point) for point in outer+inner]+[tuple(hub)]
    count=len(outer)
    hub_index=count*2
    faces=[]
    materials=[]
    for index in range(count):
        nxt=(index+1)%count
        faces.append((index,nxt,nxt+count,index+count))
        materials.append(1)
    for index in range(count):
        nxt=(index+1)%count
        faces.append((index+count,nxt+count,hub_index))
        materials.append(0)
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    obj.data.materials.append(border_material)
    for polygon,material_index in zip(obj.data.polygons,materials):
        polygon.material_index=material_index
        polygon.use_smooth=True
    solid=obj.modifiers.new("IntegratedPlateThickness","SOLIDIFY")
    solid.thickness=thickness
    solid.offset=0.0
    edge=obj.modifiers.new("IntegratedRolledEdge","BEVEL")
    edge.width=bevel
    edge.segments=3
    return obj


def lofted_cuirass(slot, name, rings, material, arm, bone, segments=40):
    """Forge a continuous super-elliptic torso shell from measured rings."""
    vertices=[]
    exponent=2.08
    for z,half_x,front_depth,back_depth in rings:
        for index in range(segments):
            angle=2*math.pi*index/segments
            cosine=math.cos(angle)
            sine=math.sin(angle)
            x=half_x*math.copysign(abs(cosine)**(2.0/exponent),cosine)
            depth=back_depth if sine>=0 else front_depth
            y=depth*math.copysign(abs(sine)**(2.0/exponent),sine)
            if sine<0:
                front_weight=abs(sine)**5
                center_weight=max(0.0,1.0-abs(x)/(half_x*.70))
                y-=.013*front_weight*center_weight
            vertices.append((x,y,z))
    faces=[]
    for row in range(len(rings)-1):
        for index in range(segments):
            nxt=(index+1)%segments
            a=row*segments+index
            b=row*segments+nxt
            c=(row+1)*segments+nxt
            d=(row+1)*segments+index
            faces.append((a,b,c,d))
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    uv_layer=obj.data.uv_layers.new(name="RoyalPlateUV")
    max_x=max(ring[1] for ring in rings)
    min_x=-max_x
    min_z=rings[0][0]
    max_z=rings[-1][0]
    for loop_index,loop in enumerate(obj.data.loops):
        vertex=obj.data.vertices[loop.vertex_index].co
        uv_layer.data[loop_index].uv=(
            ((vertex.x-min_x)/(max_x-min_x))*1.25,
            ((vertex.z-min_z)/(max_z-min_z))*1.25,
        )
    for polygon in obj.data.polygons:
        polygon.use_smooth=True
    solid=obj.modifiers.new("SingleForgedShell","SOLIDIFY")
    solid.thickness=.012
    solid.offset=-.20
    edge=obj.modifiers.new("HandPlanishedEdges","BEVEL")
    edge.width=.004
    edge.segments=3
    return obj


def subset_weighted_surface(slot, name, material, keep_vertex, outward=.010, thickness=.0, bevel=.0, source_vertex_filter=None):
    """Build only the selected weighted surface instead of cloning the hero.

    Direct face extraction cuts compile memory by orders of magnitude while
    retaining every original blended armature weight.
    """
    source=bpy.data.objects.get("ConnectedBody")
    if source is None:
        raise RuntimeError("ConnectedBody was not found")
    keep_flags=[
        bool(keep_vertex(vertex.co))
        and (source_vertex_filter is None or bool(source_vertex_filter(vertex)))
        for vertex in source.data.vertices
    ]
    kept_polygons=[
        tuple(polygon.vertices)
        for polygon in source.data.polygons
        if all(keep_flags[index] for index in polygon.vertices)
    ]
    used_indices=sorted({index for face in kept_polygons for index in face})
    if not used_indices:
        raise RuntimeError(f"No body surface selected for {name}")
    remap={old:new for new,old in enumerate(used_indices)}
    vertices=[
        tuple(source.data.vertices[index].co+source.data.vertices[index].normal*outward)
        for index in used_indices
    ]
    faces=[tuple(remap[index] for index in face) for face in kept_polygons]
    mesh=bpy.data.meshes.new(f"{PREFIX}{slot}_{name}Mesh")
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(f"{PREFIX}{slot}_{name}",mesh)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world=source.matrix_world.copy()
    obj.data.materials.append(material)
    for source_group in source.vertex_groups:
        obj.vertex_groups.new(name=source_group.name)
    for old_index,new_index in remap.items():
        for assignment in source.data.vertices[old_index].groups:
            obj.vertex_groups[assignment.group].add([new_index],assignment.weight,"REPLACE")
    arm=source.find_armature() or bpy.data.objects.get("HeroRig")
    modifier=obj.modifiers.new("RoyalArmorRig","ARMATURE")
    modifier.object=arm
    obj.parent=arm
    for polygon in obj.data.polygons:
        polygon.use_smooth=True
        polygon.material_index=0
    if thickness:
        solid=obj.modifiers.new("FittedPlateThickness","SOLIDIFY")
        solid.thickness=thickness
        solid.offset=-.15
    if bevel:
        edge=obj.modifiers.new("FittedSoftEdge","BEVEL")
        edge.width=bevel
        edge.segments=2
    return obj


def fitted_body_piece(slot, name, material, keep_vertex, outward=.012, thickness=.004):
    """Create a seamless fitted armor piece from the hero's weighted surface."""
    return subset_weighted_surface(
        slot,name,material,keep_vertex,
        outward=outward,thickness=thickness,bevel=.0025,
    )


def fitted_body_piece_by_group(slot, name, material, group_names, z_min, z_max, outward=.012, thickness=.004, minimum_weight=.035):
    """Extract a complete limb circumference using the rig's painted weights."""
    source=bpy.data.objects.get("ConnectedBody")
    indices={
        source.vertex_groups[group_name].index
        for group_name in group_names
        if source.vertex_groups.get(group_name)
    }
    if not indices:
        raise RuntimeError(f"Missing body weight groups for {name}: {group_names}")

    def weighted_for_piece(vertex):
        return any(
            assignment.group in indices and assignment.weight>=minimum_weight
            for assignment in vertex.groups
        )

    return subset_weighted_surface(
        slot,name,material,
        lambda co: z_min<co.z<z_max,
        outward=outward,thickness=thickness,bevel=.0025,
        source_vertex_filter=weighted_for_piece,
    )


def fitted_body_piece_by_group_region(slot, name, material, group_names, keep_coordinate, outward=.012, thickness=.004, minimum_weight=.035):
    """Extract a close-fitted regional plate while retaining blended weights."""
    source=bpy.data.objects.get("ConnectedBody")
    indices={
        source.vertex_groups[group_name].index
        for group_name in group_names
        if source.vertex_groups.get(group_name)
    }
    if not indices:
        raise RuntimeError(f"Missing body weight groups for {name}: {group_names}")

    def weighted_for_piece(vertex):
        return any(
            assignment.group in indices and assignment.weight>=minimum_weight
            for assignment in vertex.groups
        )

    return subset_weighted_surface(
        slot,name,material,keep_coordinate,
        outward=outward,thickness=thickness,bevel=.0025,
        source_vertex_filter=weighted_for_piece,
    )


def continuous_shoulder_mantle(slot, name, material, edge_material, accent_material, arm, bone):
    """Build one smooth annular yoke from gorget to both shoulder caps."""
    radial_steps=6
    segments=72
    vertices=[]
    for radial_index in range(radial_steps):
        t=radial_index/(radial_steps-1)
        radius_x=.176+(.454-.176)*t
        radius_y=.166+(.222-.166)*t
        for column in range(segments):
            angle=math.tau*column/segments
            x=radius_x*math.cos(angle)
            y=radius_y*math.sin(angle)
            # The yoke slopes from the gorget into the pauldrons and sits a
            # little lower over sternum/back so it follows the torso curve.
            z=1.540-.116*t-.018*abs(math.sin(angle))*t
            vertices.append((x,y,z))
    faces=[]
    for radial_index in range(radial_steps-1):
        for column in range(segments):
            nxt=(column+1)%segments
            a=radial_index*segments+column
            b=radial_index*segments+nxt
            c=(radial_index+1)*segments+nxt
            d=(radial_index+1)*segments+column
            faces.append((a,b,c,d))
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    obj.data.materials.append(edge_material)
    obj.data.materials.append(accent_material)
    for polygon in obj.data.polygons:
        radial_index=polygon.index//segments
        column=polygon.index%segments
        angle=math.tau*(column+.5)/segments
        polygon.use_smooth=True
        if radial_index==0:
            polygon.material_index=1
        elif radial_index==radial_steps-2:
            polygon.material_index=2
        elif abs(math.cos(angle))>.72:
            polygon.material_index=2
    solid=obj.modifiers.new("ContinuousMantleThickness","SOLIDIFY")
    solid.thickness=.010
    solid.offset=-.25
    bevel=obj.modifiers.new("ContinuousMantleRolledEdges","BEVEL")
    bevel.width=.0035
    bevel.segments=3
    obj["continuous_shoulders"]=True
    return obj


def lateral_shoulder_bridge(slot, name, side, material, edge_material, underside_material, arm):
    """Forge one clavicle-to-pauldron saddle without crossing the breastplate.

    The former annular mantle wrapped across the upper chest and visually sat
    on top of the cuirass.  Real harness uses short lateral shoulder bridges:
    the breastplate remains unobstructed while these saddles disappear beneath
    the mobile pauldrons.
    """
    radial_steps = 6
    angular_steps = 18
    center_angle = 0.0 if side > 0 else math.pi
    vertices = []
    for radial_index in range(radial_steps):
        t = radial_index / (radial_steps - 1)
        radius_x = .158 + (.414 - .158) * t
        radius_y = .146 + (.202 - .146) * t
        for angular_index in range(angular_steps):
            u = -1.0 + 2.0 * angular_index / (angular_steps - 1)
            angle = center_angle + u * .68
            x = radius_x * math.cos(angle)
            y = radius_y * math.sin(angle)
            # A shallow saddle follows the clavicle and dives under the outer
            # pauldron.  The front/back edges are lower than its crown.
            z = 1.535 - .105 * t - .014 * u * u
            vertices.append((x, y, z))
    faces = []
    for radial_index in range(radial_steps - 1):
        for angular_index in range(angular_steps - 1):
            a = radial_index * angular_steps + angular_index
            b = a + 1
            c = (radial_index + 1) * angular_steps + angular_index + 1
            d = (radial_index + 1) * angular_steps + angular_index
            faces.append((a, b, c, d) if side > 0 else (d, c, b, a))
    obj = plate(slot, name, vertices, faces, material, arm, "chest")
    obj.data.materials.append(edge_material)
    obj.data.materials.append(underside_material)
    columns = angular_steps - 1
    for polygon in obj.data.polygons:
        radial_index = polygon.index // columns
        angular_index = polygon.index % columns
        polygon.use_smooth = True
        if radial_index == radial_steps - 2:
            polygon.material_index = 1
        elif angular_index in (0, columns - 1):
            polygon.material_index = 2
    solid = obj.modifiers.new("ForgedShoulderBridgeThickness", "SOLIDIFY")
    solid.thickness = .008
    solid.offset = -1.0
    bevel = obj.modifiers.new("SeatedShoulderBridgeEdges", "BEVEL")
    bevel.width = .0028
    bevel.segments = 3
    obj["lateral_bridge"] = True
    obj["crosses_breastplate"] = False
    return obj


def continuous_rear_culet(slot, name, material, edge_material, accent_material, arm):
    """Forge one curved rear pelvis shell that telescopes under the fauld."""
    sections=(
        (.900,.236,-.050,.228),
        (.840,.250,-.060,.205),
        (.790,.282,-.075,.218),
        (.715,.271,-.072,.213),
        (.650,.248,-.058,.198),
    )
    columns=29
    vertices=[]
    for z,width,side_y,center_y in sections:
        for column in range(columns):
            u=-1.0+2.0*column/(columns-1)
            crown=max(0.0,1.0-u*u)**.62
            x=width*u
            y=side_y+(center_y-side_y)*crown
            vertices.append((x,y,z))
    faces=[]
    for row in range(len(sections)-1):
        for column in range(columns-1):
            a=row*columns+column
            b=a+1
            c=(row+1)*columns+column+1
            d=(row+1)*columns+column
            faces.append((a,b,c,d))
    obj=plate(slot,name,vertices,faces,material,arm,"pelvis")
    obj.data.materials.append(edge_material)
    obj.data.materials.append(accent_material)
    for polygon in obj.data.polygons:
        row=polygon.index//(columns-1)
        polygon.use_smooth=True
        if row==len(sections)-2:
            polygon.material_index=1
    # Keep the open side boundaries flush.  A solidified wall becomes a
    # detached-looking vertical rod when the pelvis rotates during a walk.
    obj["continuous_rear_armor"]=True
    return obj


def pauldron_point(side, center, radii, theta, phi):
    cx,cy,cz=center;rx,ry,rz=radii
    radial=math.sin(theta)
    return (cx+side*rx*radial*math.cos(phi),cy+ry*radial*math.sin(phi),cz+rz*math.cos(theta))


def curved_pauldron(slot, name, side, center, radii, material, arm, bone, edge_material=None):
    """Build a true ellipsoidal shoulder shell instead of a sphere or box."""
    # Wrap past the shoulder apex on both the chest and back sides.  The old
    # -1.22..1.05 arc never crossed cos(phi)==0, so every vertex sat outboard
    # of the arm-bone center and the pauldron looked detached from the torso.
    is_grand="GrandPauldron" in name
    # The grand plate is a shallow crown.  Extending it all the way down to
    # theta 1.88 created a complete half-sphere and hid the articulated lames,
    # which is why the shoulder read as a single blob.
    theta_end=1.30 if is_grand else 1.88
    theta_steps=8 if is_grand else 11
    phi_steps=17
    vertices=[]
    for ti in range(theta_steps):
        theta=.16+(theta_end-.16)*ti/(theta_steps-1)
        for pi in range(phi_steps):
            phi=-2.05+(4.10)*pi/(phi_steps-1)
            point=Vector(pauldron_point(side,center,radii,theta,phi))
            if is_grand:
                # Integral forged flutes add structure to the broad dome.  The
                # vertices move along the shell normal, so these details can
                # never detach or hover like separate trim pieces.
                crown_t=(theta-.16)/(theta_end-.16)
                crown_profile=max(0.0,math.sin(crown_t*math.pi))
                # Push the middle third outward into a restrained Gothic
                # shoulder point instead of retaining a circular silhouette.
                point.x+=side*.028*(crown_profile**1.6)*max(0.0,1.0-abs(phi)/1.35)
                relief=0.0
                for flute_phi in (-.78,0.0,.78):
                    relief=max(relief,.011*max(0.0,1.0-abs(phi-flute_phi)/.22)*crown_profile)
                if relief>0:
                    point+=(point-Vector(center)).normalized()*relief
            vertices.append(tuple(point))
    faces=[]
    for ti in range(theta_steps-1):
        for pi in range(phi_steps-1):
            a=ti*phi_steps+pi;b=a+1;c=a+phi_steps+1;d=a+phi_steps
            faces.append((a,b,c,d) if side>0 else (d,c,b,a))
    mesh=bpy.data.meshes.new(f"{PREFIX}{slot}_{name}Mesh");mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(f"{PREFIX}{slot}_{name}",mesh);bpy.context.collection.objects.link(obj)
    # Slightly faceted crown panels read as forged plate; the lower arm shells
    # retain smooth shading.
    skin(obj,arm,bone,material,not is_grand)
    if edge_material is not None:
        obj.data.materials.append(edge_material)
        columns=phi_steps-1
        for polygon in obj.data.polygons:
            row=polygon.index//columns
            column=polygon.index%columns
            if row==theta_steps-2:
                polygon.material_index=1
            elif is_grand:
                phi_center=-2.05+4.10*(column+.5)/(phi_steps-1)
                if min(abs(phi_center-flute_phi) for flute_phi in (-.78,0.0,.78))<.10:
                    polygon.material_index=1
    solid=obj.modifiers.new("CurvedPlateThickness","SOLIDIFY");solid.thickness=.013;solid.offset=0.0
    bevel=obj.modifiers.new("CurvedRolledEdge","BEVEL");bevel.width=.005;bevel.segments=2
    return obj


def articulated_shoulder_skirt(slot, name, side, center, radii, material, dark_material, brass_material, arm, bone):
    """Build three overlapping shoulder lames as one fitted articulated unit.

    The previous lower shoulder was a second ellipsoid beneath the crown and
    read as two blue blobs.  These shallow, descending bands overlap the crown
    and each other, while remaining one skinned object attached to the arm.
    """
    theta_bands=((.94,1.27,1.00),(1.20,1.50,.955),(1.43,1.72,.905))
    phi_steps=19
    theta_steps=5
    vertices=[]
    faces=[]
    face_materials=[]
    for band_index,(theta_start,theta_end,scale) in enumerate(theta_bands):
        band_start=len(vertices)
        for theta_index in range(theta_steps):
            theta=theta_start+(theta_end-theta_start)*theta_index/(theta_steps-1)
            for phi_index in range(phi_steps):
                phi=-2.02+4.04*phi_index/(phi_steps-1)
                point=Vector(pauldron_point(
                    side,
                    (center[0],center[1]+band_index*.002,center[2]-band_index*.010),
                    (radii[0]*scale,radii[1]*(1.0-band_index*.025),radii[2]),
                    theta,phi,
                ))
                # A restrained center ridge is forged into each lame.  It adds
                # readable medieval articulation without a separate floating
                # ornament.
                ridge=max(0.0,1.0-abs(phi)/.28)*math.sin(
                    math.pi*theta_index/(theta_steps-1)
                )*.0045
                point+=(point-Vector(center)).normalized()*ridge
                vertices.append(tuple(point))
        for theta_index in range(theta_steps-1):
            for phi_index in range(phi_steps-1):
                a=band_start+theta_index*phi_steps+phi_index
                b=a+1
                c=a+phi_steps+1
                d=a+phi_steps
                faces.append((a,b,c,d) if side>0 else (d,c,b,a))
                # Blackened rolled lower edges separate the overlapping lames;
                # the top seam receives a narrow gilt line integrated through
                # material assignment, not detached geometry.
                if theta_index==theta_steps-2:
                    face_materials.append(1)
                elif theta_index==0 and band_index==0:
                    face_materials.append(2)
                else:
                    face_materials.append(0)
    mesh=bpy.data.meshes.new(f"{PREFIX}{slot}_{name}Mesh")
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(f"{PREFIX}{slot}_{name}",mesh)
    bpy.context.collection.objects.link(obj)
    skin(obj,arm,bone,material,True)
    obj.data.materials.append(dark_material)
    obj.data.materials.append(brass_material)
    for polygon,material_index in zip(obj.data.polygons,face_materials):
        polygon.material_index=material_index
    solid=obj.modifiers.new("ArticulatedLameThickness","SOLIDIFY")
    solid.thickness=.011
    solid.offset=0.0
    bevel=obj.modifiers.new("RolledLameEdges","BEVEL")
    bevel.width=.004
    bevel.segments=2
    obj["connected_articulated_shoulder"]=True
    return obj


def sabaton_shell(slot,name,x,material,arm,bone,accent_material=None,dark_material=None):
    """Closed, planted medieval shoe shell with integrated articulation bands."""
    sections=[
        (.075,.074,.096,.058),
        (.020,.084,.095,.055),
        (-.055,.094,.091,.050),
        (-.135,.103,.086,.044),
        (-.215,.101,.080,.037),
        (-.300,.082,.074,.029),
    ]
    radial_steps=14
    vertices=[]
    for y,width,center_z,radius_z in sections:
        for radial in range(radial_steps):
            angle=2*math.pi*radial/radial_steps
            px=x+width*math.cos(angle)
            pz=max(.034,center_z+radius_z*math.sin(angle))
            vertices.append((px,y,pz))
    faces=[]
    for row in range(len(sections)-1):
        for radial in range(radial_steps):
            nxt=(radial+1)%radial_steps
            a=row*radial_steps+radial
            b=row*radial_steps+nxt
            c=(row+1)*radial_steps+nxt
            d=(row+1)*radial_steps+radial
            faces.append((a,b,c,d))
    faces.append(tuple(range(radial_steps-1,-1,-1)))
    last=(len(sections)-1)*radial_steps
    faces.append(tuple(last+index for index in range(radial_steps)))
    mesh=bpy.data.meshes.new(f"{PREFIX}{slot}_{name}Mesh")
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(f"{PREFIX}{slot}_{name}",mesh)
    bpy.context.collection.objects.link(obj)
    skin(obj,arm,bone,material,True)
    if accent_material is not None:
        obj.data.materials.append(accent_material)
    if dark_material is not None:
        obj.data.materials.append(dark_material)
    for polygon in obj.data.polygons:
        row=polygon.index//radial_steps
        if accent_material is not None and row in (1,3):
            polygon.material_index=1
        elif dark_material is not None and row==0:
            polygon.material_index=2
    bevel=obj.modifiers.new("SabatonRolledEdges","BEVEL")
    bevel.width=.004
    bevel.segments=3
    return obj


def yz_prism(slot,name,outline,half_x,material,arm,bone,bevel=.004):
    """Closed prism extruded across X from a Y/Z outline."""
    count=len(outline)
    vertices=[(-half_x,y,z) for y,z in outline]+[(half_x,y,z) for y,z in outline]
    faces=[tuple(range(count)),tuple(range(count*2-1,count-1,-1))]
    for index in range(count):
        nxt=(index+1)%count
        faces.append((index,nxt,nxt+count,index+count))
    obj=plate(slot,name,vertices,faces,material,arm,bone)
    if bevel>0:
        modifier=obj.modifiers.new("FeatherSoftEdges","BEVEL");modifier.width=bevel;modifier.segments=3
    return obj


def ducal_plume(arm, crimson, crimson_dark, brass):
    """A transverse ducal/centurion crest of overlapping feather blades."""
    # The socket is deliberately sunk into the sallet crown; no visible air gap.
    box("head","DucalCrestSocket",(0,.006,1.904),(.246,.090,.038),crimson_dark,arm,"head",bevel=.012)
    box("head","DucalCrestRail",(0,.000,1.920),(.326,.066,.028),brass,arm,"head",bevel=.008)
    heights=(2.006,2.042,2.074,2.096,2.106,2.098,2.080,2.050,2.014)
    for index,root_x in enumerate((-.136,-.102,-.068,-.034,0,.034,.068,.102,.136)):
        top=heights[index]
        outline=[
            (root_x-.019,1.916),(root_x+.019,1.916),
            (root_x+.030,top-.032),(root_x+.010,top),
            (root_x-.016,top-.030),
        ]
        material=crimson if index%3 else crimson_dark
        forged_prism("head",f"DucalPlumeFeather{index}",outline,-.036,.036,material,arm,"head",.005)


def weighted_body_garment(slot, name, material, z_min, z_max, x_limit, outward=.006):
    """Cut a garment from the hero surface while retaining original body weights."""
    return subset_weighted_surface(
        slot,name,material,
        lambda co: z_min<=co.z<=z_max and abs(co.x)<=x_limit,
        outward=outward,thickness=0.0,bevel=0.0,
    )


def ducal_cuirass_shell(arm, cobalt, bright, brass, dark):
    """One coherent forged torso shell with integrated ridges and color inlays."""
    rings=[
        (.985,.247,.150,-.002),
        (1.075,.266,.166,-.001),
        (1.195,.292,.194,.000),
        (1.330,.324,.210,.002),
        (1.445,.304,.192,.004),
        (1.510,.246,.156,.006),
    ]
    segments=32
    vertices=[]
    for z,rx,ry,center_y in rings:
        for index in range(segments):
            angle=2*math.pi*index/segments
            x=rx*math.cos(angle)
            y=center_y+ry*math.sin(angle)
            # Forge a real central tapul into the plate surface.
            if math.sin(angle)<0:
                center_weight=max(0.0,1.0-abs(x)/(rx*.55))
                y-=.016*center_weight
            vertices.append((x,y,z))
    faces=[]
    for row in range(len(rings)-1):
        for index in range(segments):
            nxt=(index+1)%segments
            a=row*segments+index
            b=row*segments+nxt
            c=(row+1)*segments+nxt
            d=(row+1)*segments+index
            faces.append((a,b,c,d))
    mesh=bpy.data.meshes.new(f"{PREFIX}chest_DucalUnifiedCuirassMesh")
    mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(f"{PREFIX}chest_DucalUnifiedCuirass",mesh)
    bpy.context.collection.objects.link(obj)
    skin(obj,arm,"chest",cobalt,True)
    obj.data.materials.append(bright)
    obj.data.materials.append(brass)
    obj.data.materials.append(dark)
    for polygon in obj.data.polygons:
        row=polygon.index//segments
        column=polygon.index%segments
        angle=2*math.pi*(column+.5)/segments
        front_delta=abs((angle-1.5*math.pi+math.pi)%(2*math.pi)-math.pi)
        if row in (0,len(rings)-2):
            polygon.material_index=3
        elif front_delta<.115:
            polygon.material_index=3
        elif .23<front_delta<.38:
            polygon.material_index=1
        elif .73<front_delta<.86 and row>=2:
            polygon.material_index=2
    solid=obj.modifiers.new("ForgedCuirassThickness","SOLIDIFY")
    solid.thickness=.012;solid.offset=-.15
    bevel=obj.modifiers.new("ForgedCuirassEdges","BEVEL")
    bevel.width=.003;bevel.segments=2
    return obj


def weighted_body_garment_by_bones(slot, name, material, bone_names, outward=.006):
    """Create a seamless under-armor layer from selected weighted body regions."""
    source=bpy.data.objects.get("ConnectedBody")
    if source is None:raise RuntimeError("ConnectedBody was not found")
    obj=source.copy();obj.data=source.data.copy();obj.name=f"{PREFIX}{slot}_{name}";bpy.context.collection.objects.link(obj)
    for modifier in list(obj.modifiers):
        if modifier.type=="SUBSURF":obj.modifiers.remove(modifier)
    while len(obj.data.materials):obj.data.materials.pop(index=0)
    obj.data.materials.append(material)
    allowed={obj.vertex_groups[name].index for name in bone_names if obj.vertex_groups.get(name)}
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="DESELECT");bpy.ops.object.mode_set(mode="OBJECT")
    for vertex in obj.data.vertices:
        keep=any(group.group in allowed and group.weight>.04 for group in vertex.groups)
        vertex.select=not keep
        if keep:vertex.co+=vertex.normal*outward
    bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.delete(type="VERT");bpy.ops.object.mode_set(mode="OBJECT")
    for polygon in obj.data.polygons:polygon.material_index=0;polygon.use_smooth=True
    obj.select_set(False)
    return obj


def add_helmet(arm, blue, gold, dark, black, ruby):
    # Close-fitted bascinet shell with a flared rear neck guard.
    sphere("head","BlueDome",(0,-.002,1.770),(.124,.113,.142),blue,arm,"head",40,26)
    sphere("head","LowerSkull",(0,.018,1.690),(.121,.108,.095),dark,arm,"head",36,22)
    forged_prism("head","RearNeckGuard",[(-.108,1.718),(.108,1.718),(.126,1.655),(.092,1.606),(-.092,1.606),(-.126,1.655)],.066,.100,dark,arm,"head",.007)
    torus("head","CrownBand",(0,-.004,1.798),.113,.006,gold,arm,"head",scale=(1.0,.92,1.0))

    # A crowned, tapered visor replaces the rectangular face box.
    visor_outline=[(-.103,1.780),(.103,1.780),(.119,1.731),(.102,1.666),(.052,1.620),(0,1.602),(-.052,1.620),(-.102,1.666),(-.119,1.731)]
    forged_prism("head","CrownedVisor",visor_outline,-.154,-.105,blue,arm,"head",.007)
    box("head","EyeSlit",(0,-.181,1.748),(.185,.010,.016),black,arm,"head",bevel=.003)
    cone_between("head","BrowTrimL",(-.108,-.183,1.777),(0,-.188,1.764),.006,.005,gold,arm,"head",14)
    cone_between("head","BrowTrimR",(0,-.188,1.764),(.108,-.183,1.777),.005,.006,gold,arm,"head",14)
    cone_between("head","VisorJawTrimL",(-.092,-.176,1.654),(0,-.181,1.610),.005,.004,gold,arm,"head",14)
    cone_between("head","VisorJawTrimR",(0,-.181,1.610),(.092,-.176,1.654),.004,.005,gold,arm,"head",14)
    box("head","NasalRidge",(0,-.184,1.705),(.014,.010,.116),gold,arm,"head",bevel=.003)
    # Small punched breaths sit in the visor instead of oversized vertical bars.
    for row,z in enumerate((1.700,1.677)):
        for side in (-1,1):
            for column in range(3):
                x=side*(.030+column*.021)
                sphere("head",f"BreathHole{row}{side}{column}",(x,-.181,z),(.006,.003,.006),black,arm,"head",12,8)
    for side in (-1,1):
        cheek_outline=[(side*.116,1.720),(side*.121,1.653),(side*.077,1.605),(side*.055,1.636),(side*.075,1.710)]
        forged_prism("head",f"CheekGuard{side}",cheek_outline,-.160,-.092,dark,arm,"head",.005)
        cone_between("head",f"CheekEdge{side}",(side*.118,-.169,1.710),(side*.083,-.170,1.620),.004,.003,gold,arm,"head",12)
        cylinder("head",f"Hinge{side}",(side*.124,-.030,1.724),.024,.017,gold,arm,"head",rotation=(0,math.pi/2,0))
        cylinder("head",f"HingeInset{side}",(side*.133,-.030,1.724),.013,.019,blue,arm,"head",rotation=(0,math.pi/2,0))
        sphere("head",f"HingeRuby{side}",(side*.144,-.030,1.724),(.006,.009,.006),ruby,arm,"head",16,10)

    # Low swept crown fin: still royal, but no longer a tall cage on the head.
    crest=[(-.010,-.055,1.892),(-.010,.080,1.905),(-.010,.142,1.850),(.010,-.055,1.892),(.010,.080,1.905),(.010,.142,1.850)]
    plate("head","GoldCrest",crest,[(0,1,2),(3,5,4),(0,3,4),(0,4,1),(1,4,5),(1,5,2),(2,5,3),(2,3,0)],gold,arm,"head")
    plate("head","BlueCrestInset",[(-.011,-.038,1.888),(-.011,.071,1.896),(-.011,.121,1.854),(.011,-.038,1.888),(.011,.071,1.896),(.011,.121,1.854)],[(0,1,2),(3,5,4)],blue,arm,"head")
    sphere("head","CrestRuby",(0,-.064,1.875),(.017,.010,.017),ruby,arm,"head",18,12)


def add_breastplate(arm, blue, gold, dark, leather, ruby, undercloth):
    # A fitted arming doublet covers the clavicles, shoulder sockets, armpits,
    # upper arms and neck base using the hero's original blended weights.
    # A clean coordinate cut avoids the ragged weight-threshold border that was
    # visible beneath the pauldrons and along the back of the arms.
    weighted_body_garment("chest","ArmingDoublet",undercloth,.825,1.675,.410,.009)
    # The main cuirass is cut directly from the weighted hero surface. It keeps
    # the ribcage anatomy and shoulder blending instead of hovering as a large
    # primitive or a flat shield-shaped panel.
    weighted_body_garment("chest","FittedCuirassSurface",blue,.985,1.505,.340,.020)
    for side in (-1,1):
        cone_between("chest",f"ClavicleRoll{side}",(0,-.218,1.474),(side*.215,-.195,1.425),.006,.004,gold,arm,"chest",14)
        # Separate crowned breastplate halves create real forged planes while
        # the weighted cuirass below keeps every seam closed in deformation.
        boundary=[(side*.012,-.226,1.455),(side*.200,-.207,1.430),(side*.245,-.198,1.342),(side*.198,-.205,1.282),(side*.020,-.220,1.296)]
        center=(side*.112,-.230,1.365)
        convex_panel("chest",f"CrownedPectoral{side}",boundary,center,blue,arm,"chest",.008,.004)
        cone_between("chest",f"PectoralUpperEdge{side}",(side*.014,-.239,1.455),(side*.205,-.216,1.430),.0045,.0035,gold,arm,"chest",12)
        cone_between("chest",f"PectoralLowerSeam{side}",(side*.020,-.232,1.296),(side*.205,-.208,1.282),.0035,.003,dark,arm,"chest",12)
        # Two shallow abdominal lames overlap rather than floating as bands.
        for row,(z,width) in enumerate(((1.235,.205),(1.155,.190))):
            lame=[(side*.012,-.218,z+.032),(side*width,-.202,z+.022),(side*(width+.016),-.196,z-.028),(side*.018,-.211,z-.038)]
            convex_panel("chest",f"AbdominalLame{side}{row}",lame,(side*.105,-.222,z),blue,arm,"spine",.005,.003)
            cone_between("chest",f"AbdominalEdge{side}{row}",(side*.018,-.225,z+.030),(side*width,-.210,z+.020),.0035,.0025,gold,arm,"spine",10)
    # The fitted cuirass already protects the back.  Use a thin spinal inset,
    # not the old rectangular backpack-like slab.
    back_outline=[(-.120,1.445),(.120,1.445),(.155,1.390),(.125,1.245),(0,1.185),(-.125,1.245),(-.155,1.390)]
    plate("chest","BackShieldInset",[(x,.224,z) for x,z in back_outline],[(0,1,2),(0,2,3),(0,3,4),(0,4,5),(0,5,6)],dark,arm,"chest")
    box("chest", "BackplateSpine", (0, .229, 1.325), (.014,.009,.245), gold, arm, "chest", bevel=.003)
    cone_between("chest","BackChevronLeft",(-.125,.230,1.365),(0,.230,1.285),.005,.004,gold,arm,"chest",12)
    cone_between("chest","BackChevronRight",(.125,.230,1.365),(0,.230,1.285),.005,.004,gold,arm,"chest",12)
    sphere("chest","BackRubySetting",(0,.234,1.405),(.020,.006,.020),gold,arm,"chest",18,10)
    sphere("chest","BackRuby",(0,.240,1.405),(.011,.003,.012),ruby,arm,"chest",16,10)
    for index in range(len(back_outline)):
        a=back_outline[index];b=back_outline[(index+1)%len(back_outline)]
        cone_between("chest",f"BackplateEdge{index}",(a[0],.230,a[1]),(b[0],.230,b[1]),.0045,.0045,gold,arm,"chest",12)
    # Crowned left/right back plates follow the shoulder blades and remove the
    # plain wetsuit appearance from the rear view.
    for side in (-1,1):
        boundary=[(side*.014,.215,1.470),(side*.190,.202,1.438),(side*.248,.188,1.345),(side*.190,.198,1.232),(side*.022,.216,1.250)]
        center=(side*.112,.231,1.350)
        convex_panel("chest",f"ScapularPlate{side}",boundary,center,blue,arm,"chest",.007,.004)
        cone_between("chest",f"ScapularUpperEdge{side}",(side*.016,.226,1.467),(side*.188,.213,1.438),.004,.0035,gold,arm,"chest",12)
        cone_between("chest",f"ScapularLowerSeam{side}",(side*.024,.226,1.250),(side*.188,.208,1.232),.0035,.003,dark,arm,"chest",12)
    for index, z in enumerate((1.035, .990)):
        sphere("chest", f"FauldBlue{index}", (0, -.004-index*.003, z), (.235-index*.012,.128,.030), blue, arm, "pelvis", 30, 12)
        torus("chest",f"FauldGoldBand{index}",(0,-.004-index*.003,z+.008),.225-index*.011,.006,gold,arm,"pelvis",scale=(1.0,.58,1.0))

    # Compact articulated gorget closes the old bare shoulder shelf.
    torus("chest", "GorgetGold", (0, -.002, 1.515), .170, .012, gold, arm, "chest", scale=(1.12,.72,1))
    torus("chest", "GorgetDark", (0, -.004, 1.520), .152, .014, dark, arm, "chest", scale=(1.08,.70,1))
    box("chest","GorgetFront",(0,-.176,1.480),(.235,.032,.072),dark,arm,"chest",bevel=.014)
    box("chest","GorgetFrontTrim",(0,-.196,1.458),(.185,.012,.013),gold,arm,"chest",bevel=.004)
    box("chest", "CenterRidge", (0,-.224,1.300), (.014,.008,.205), gold, arm, "chest", bevel=.003)
    sphere("chest", "HeartRubySetting", (0,-.230,1.400), (.023,.007,.023), gold, arm, "chest", 20, 12)
    sphere("chest", "HeartRuby", (0,-.237,1.400), (.013,.004,.014), ruby, arm, "chest", 18, 12)

    # Restrained dark fluting makes the shell read as forged plate without the
    # previous gold spider-like lines.
    for side in (-1, 1):
        cone_between("chest",f"RibFluteUpper{side}",(side*.040,-.216,1.300),(side*.215,-.185,1.260),.004,.0025,dark,arm,"chest",12)
        cone_between("chest",f"RibFluteLower{side}",(side*.036,-.207,1.220),(side*.190,-.178,1.185),.0035,.002,dark,arm,"chest",12)
        box("chest",f"WaistClasp{side}",(side*.222,-.140,1.090),(.040,.014,.028),gold,arm,"spine",bevel=.004)
    box("chest","SternumInset",(0,-.217,1.305),(.038,.007,.118),dark,arm,"chest",bevel=.006)

    # A compact heraldic shield replaces the oversized insect-like lion.
    crest=[(-.060,-.229,1.365),(.060,-.229,1.365),(.050,-.232,1.305),(0,-.235,1.275),(-.050,-.232,1.305)]
    plate("chest","HeraldicShield",crest,[(0,1,2),(0,2,3),(0,3,4)],dark,arm,"chest")
    for index,(a,b) in enumerate(zip(crest,crest[1:]+crest[:1])):
        cone_between("chest",f"HeraldicEdge{index}",a,b,.0045,.0045,gold,arm,"chest",10)
    box("chest","HeraldicBlade",(0,-.240,1.320),(.009,.005,.070),gold,arm,"chest",bevel=.002)
    box("chest","HeraldicGuard",(0,-.242,1.340),(.046,.005,.008),gold,arm,"chest",bevel=.002)
    for index, x in enumerate((-.255,-.200,.200,.255)):
        for row,z in enumerate((1.175,1.410)):
            sphere("chest",f"Rivet{index}_{row}",(x*.90,-.158,z),(.007,.004,.007),gold,arm,"chest",14,8)

    # Side leather straps, gold buckles and hanging tassets protect the hips.
    for side in (-1,1):
        box("chest",f"SideStrap{side}",(side*.306,-.005,1.205),(.045,.205,.055),leather,arm,"chest",rotation=(side*.04,0,0),bevel=.006)
        torus("chest",f"SideBuckle{side}",(side*.330,-.090,1.205),.030,.006,gold,arm,"chest",rotation=(math.pi/2,0,0),scale=(.75,1.0,1.0))
        sphere("chest",f"TassetBlue{side}",(side*.178,-.012,.905),(.105,.090,.125),blue,arm,"pelvis",24,14)
        box("chest",f"TassetGoldBand{side}",(side*.178,-.102,.948),(.170,.010,.014),gold,arm,"pelvis",bevel=.003)


def add_shoulders(arm, blue, gold, dark, undercloth):
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        bone = f"upper_arm.{suffix}"
        # True curved shell generated as an ellipsoidal patch. It wraps the
        # shoulder front-to-back and reads as forged plate in every view.
        center=(side*.292,-.004,1.402);radii=(.165,.132,.142)
        curved_pauldron("shoulders",f"CurvedPauldron{suffix}",side,center,radii,blue,arm,bone)
        sphere("shoulders",f"InnerMantle{suffix}",(side*.225,-.001,1.445),(.085,.070,.041),dark,arm,"chest",30,18)
        # Rolled border follows the actual curved surface.
        lower=[];front=[];crown=[]
        for index in range(12):
            phi=-1.22+2.27*index/11
            lower.append(pauldron_point(side,center,radii,1.88,phi))
        for index in range(10):
            theta=.16+(1.88-.16)*index/9
            front.append(pauldron_point(side,center,radii,theta,-1.22))
            crown.append(pauldron_point(side,center,radii,theta,0.0))
        for index in range(len(lower)-1):
            a=lower[index];b=lower[index+1]
            cone_between("shoulders",f"LowerRim{suffix}{index}",a,b,.0048,.0048,gold,arm,bone,12)
        for index in range(len(front)-1):
            cone_between("shoulders",f"FrontRim{suffix}{index}",front[index],front[index+1],.0042,.0042,gold,arm,bone,12)
        # A restrained central flute breaks up the broad surface without
        # turning it into a heraldic signboard.
        for index in range(2,len(crown)-2):
            a=crown[index];b=crown[index+1]
            cone_between("shoulders",f"CrownFlute{suffix}{index}",(a[0],a[1]-.008,a[2]),(b[0],b[1]-.008,b[2]),.003,.0025,dark,arm,bone,10)
        for index,phi in enumerate((-.78,-.25,.30,.78)):
            point=pauldron_point(side,center,radii,1.67,phi)
            sphere("shoulders",f"LowerRivet{suffix}{index}",(point[0],point[1]-.006,point[2]),(.006,.004,.006),gold,arm,bone,12,8)


def add_gauntlets(arm, blue, gold, dark, leather):
    for side in (-1,1):
        suffix = "L" if side < 0 else "R"
        forearm=f"forearm.{suffix}";hand=f"hand.{suffix}"
        x=.34*side
        # Tapered vambrace overlaps the elbow and opens into a rolled cuff.
        cone_between("hands",f"BlueVambrace{suffix}",(x,.006,1.125),(x,.002,.925),.093,.070,blue,arm,forearm,32)
        torus("hands",f"UpperCuff{suffix}",(x,-.004,1.112),.085,.007,gold,arm,forearm,scale=(1.0,.86,1.0))
        torus("hands",f"WristCuff{suffix}",(x,-.006,.928),.068,.006,gold,arm,forearm,scale=(1.0,.88,1.0))
        # Crowned front plate and central ridge give the forearm a forged plane.
        outline=[(x-.060,1.086),(x+.060,1.086),(x+.052,.958),(x,.934),(x-.052,.958)]
        forged_prism("hands",f"VambraceFace{suffix}",outline,-.096,-.074,dark,arm,forearm,.004)
        cone_between("hands",f"VambraceRidge{suffix}",(x,-.106,1.073),(x,-.104,.951),.004,.003,gold,arm,forearm,10)
        for z in (1.045,.980):
            for edge in (-1,1):sphere("hands",f"VambraceRivet{suffix}{z}{edge}",(x+edge*.045,-.106,z),(.005,.003,.005),gold,arm,forearm,12,8)
        box("hands",f"BracerStrap{suffix}",(x,.073,1.015),(.038,.014,.125),leather,arm,forearm,bevel=.003)
        sphere("hands",f"HandBlueShell{suffix}",(x,-.024,.850),(.070,.060,.061),blue,arm,hand,28,16)
        forged_prism("hands",f"KnuckleGuard{suffix}",[(x-.067,.830),(x+.067,.830),(x+.057,.792),(x-.057,.792)],-.099,-.065,dark,arm,hand,.004)
        for index in range(4):
            dx=(index-1.5)*.033
            sphere("hands",f"FingerPlate{suffix}{index}",(x+dx,-.073,.779-index%2*.004),(.014,.028,.023),blue,arm,hand,18,10)
            box("hands",f"FingerGold{suffix}{index}",(x+dx,-.101,.779-index%2*.004),(.022,.006,.008),gold,arm,hand,bevel=.002)


def add_greaves(arm, blue, gold, dark, leather):
    for side in (-1,1):
        suffix="L" if side<0 else "R";shin=f"shin.{suffix}";foot=f"foot.{suffix}";x=.131*side
        # Angular poleyn protects the knee without the old spherical kneecap.
        knee_outline=[(x-.098,.602),(x+.098,.602),(x+.112,.558),(x+.070,.505),(x,.462),(x-.070,.505),(x-.112,.558)]
        forged_prism("feet",f"ForgedPoleyn{suffix}",knee_outline,-.130,-.025,blue,arm,shin,.008)
        for index in range(len(knee_outline)):
            a=knee_outline[index];b=knee_outline[(index+1)%len(knee_outline)]
            cone_between("feet",f"PoleynRim{suffix}{index}",(a[0],-.140,a[1]),(b[0],-.140,b[1]),.0045,.0045,gold,arm,shin,12)
        sphere("feet",f"PoleynBoss{suffix}",(x,-.148,.552),(.023,.007,.023),dark,arm,shin,18,10)
        sphere("feet",f"PoleynRivet{suffix}",(x,-.155,.552),(.010,.004,.010),gold,arm,shin,14,8)

        # Close-fitted greave with a crowned shin face; no rectangular back box.
        cone_between("feet",f"BlueGreave{suffix}",(x,.010,.505),(x,.012,.150),.098,.073,blue,arm,shin,32)
        shin_outline=[(x-.072,.475),(x+.072,.475),(x+.060,.195),(x,.158),(x-.060,.195)]
        convex_panel("feet",f"CrownedShin{suffix}",[(px,-.100,pz) for px,pz in shin_outline],(x,-.116,.325),blue,arm,shin,.007,.004)
        cone_between("feet",f"ShinRidge{suffix}",(x,-.124,.454),(x,-.124,.180),.005,.003,gold,arm,shin,12)
        for edge in (-1,1):
            cone_between("feet",f"GreaveEdge{suffix}{edge}",(x+edge*.070,-.108,.463),(x+edge*.056,-.104,.194),.004,.003,dark,arm,shin,10)
        torus("feet",f"GreaveTopRoll{suffix}",(x,-.005,.484),.091,.006,gold,arm,shin,scale=(1.0,.90,1.0))
        torus("feet",f"AnkleRoll{suffix}",(x,-.004,.157),.069,.0055,gold,arm,shin,scale=(1.0,.90,1.0))
        for index,z in enumerate((.400,.265)):
            box("feet",f"GreaveStrap{suffix}{index}",(x,.082,z),(.052,.016,.050),leather,arm,shin,bevel=.004)

        # One continuous low sabaton, then overlapping metatarsal lames.
        sabaton_shell("feet",f"SabatonShell{suffix}",x,blue,arm,foot)
        for index,(y,width) in enumerate(((-.045,.086),(-.125,.099),(-.205,.108))):
            box("feet",f"SabatonLame{suffix}{index}",(x,y-.006,.112-index*.017),(width*1.85,.020,.026),blue,arm,foot,bevel=.006)
            box("feet",f"SabatonLameEdge{suffix}{index}",(x,y-.018,.120-index*.017),(width*1.72,.006,.006),gold,arm,foot,bevel=.002)


def add_pants(arm, cloth, cloth_dark, leather, gold, blue):
    """Fitted royal trousers broken at joints so the existing rig deforms cleanly."""
    # The base is an offset copy of the actual weighted hero surface. It follows
    # blended pelvis/thigh/shin weights exactly, eliminating exposed skin seams.
    weighted_body_garment("pants","TailoredWeightedBase",cloth,.145,1.025,.305,.007)
    sphere("pants","ReinforcedSeat",(0,.122,.900),(.252,.050,.128),cloth_dark,arm,"pelvis",28,16)
    torus("pants","LeatherWaistband",(0,.005,1.010),.250,.020,leather,arm,"pelvis",scale=(1.0,.66,1.0))
    torus("pants","GoldWaistPiping",(0,-.002,1.022),.255,.006,gold,arm,"pelvis",scale=(1.0,.66,1.0))
    box("pants","FrontFly",(0,-.178,.925),(.038,.014,.145),cloth_dark,arm,"pelvis",bevel=.004)
    box("pants","BackSeam",(0,.190,.908),(.022,.012,.155),cloth_dark,arm,"pelvis",bevel=.003)
    box("pants","RoyalBuckle",(0,-.192,1.020),(.072,.018,.048),gold,arm,"pelvis",bevel=.008)
    box("pants","BuckleInset",(0,-.204,1.020),(.042,.010,.024),blue,arm,"pelvis",bevel=.004)
    for side in (-1,1):
        suffix="L" if side<0 else "R";thigh=f"thigh.{suffix}";shin=f"shin.{suffix}";x=.135*side
        sphere("pants",f"KneeQuilt{suffix}",(x,-.104,.565),(.102,.038,.105),cloth_dark,arm,shin,24,14)
        sphere("pants",f"InnerThigh{suffix}",(x-side*.055,.070,.765),(.062,.052,.155),leather,arm,thigh,20,14)
        # Gold side piping continues as a readable tailored seam.
        cone_between("pants",f"OuterPipingUpper{suffix}",(x+side*.126,-.002,.905),(x+side*.105,-.002,.615),.006,.004,gold,arm,thigh,10)
        cone_between("pants",f"OuterPipingLower{suffix}",(x+side*.100,-.002,.610),(x+side*.078,.006,.200),.005,.003,gold,arm,shin,10)
        for row,z in enumerate((.350,.275,.205)):
            box("pants",f"LeatherWrap{suffix}{row}",(x,-.090,z),(.180,.028,.045),leather,arm,shin,rotation=(0,side*(.18 if row%2==0 else -.18),0),bevel=.006)
        # Three small hip lames echo the armor without turning pants into a skirt.
        for row,(z,sx) in enumerate(((.980,.108),(.930,.102),(.882,.095))):
            box("pants",f"HipLame{suffix}{row}",(side*.260,-.012,z),(sx,.090,.043),blue,arm,"pelvis",rotation=(0,side*.10,side*.04),bevel=.007)
            box("pants",f"HipLameEdge{suffix}{row}",(side*.266,-.062,z-.017),(sx*.84,.009,.008),gold,arm,"pelvis",rotation=(0,side*.10,side*.04),bevel=.002)


def add_gothic_helmet(arm, steel, dark, brass, black, mail, blue_cloth):
    """Royal sallet with a faceted visor, articulated bevor, and ducal crest."""
    sphere("head","SalletSkull",(0,.002,1.775),(.126,.116,.145),steel,arm,"head",44,28)
    sphere("head","SalletLowerShell",(0,.020,1.700),(.124,.108,.092),dark,arm,"head",40,24)
    # A sallet's rear is a curved, descending tail--never a flat signboard.
    # Three crowned lames overlap the skull and taper into the bevor/gorget.
    for index,(top,bottom,half,edge_y,hub_y) in enumerate((
        (1.724,1.665,.126,.090,.151),
        (1.675,1.615,.132,.099,.157),
        (1.625,1.574,.122,.106,.160),
    )):
        boundary=[(-half,edge_y,top),(half,edge_y,top),(half*.88,edge_y+.010,bottom),(0,edge_y+.018,bottom-.012),(-half*.88,edge_y+.010,bottom)]
        convex_panel("head",f"SalletRearLame{index}",boundary,(0,hub_y,(top+bottom)*.5),steel if index!=1 else dark,arm,"head",.011,.005)

    # The visor is split into crowned left/right panels so the face projects
    # into a central prow rather than remaining a flat plate.
    visor_left=[
        (-.128,-.130,1.794),(0,-.150,1.776),
        (0,-.158,1.732),(-.112,-.136,1.741),
    ]
    visor_right=[
        (0,-.150,1.776),(.128,-.130,1.794),
        (.112,-.136,1.741),(0,-.158,1.732),
    ]
    bordered_panel("head","FacetedVisorL",visor_left,(-.062,-.190,1.760),bright_steel,brass,arm,"head",.12,.012,.005)
    bordered_panel("head","FacetedVisorR",visor_right,(.062,-.190,1.760),bright_steel,brass,arm,"head",.12,.012,.005)
    box("head","RecessedEyeVoid",(0,-.146,1.719),(.222,.036,.023),black,arm,"head",bevel=.003)

    cheek_left=[
        (-.116,-.133,1.708),(-.010,-.158,1.704),
        (0,-.166,1.576),(-.072,-.143,1.607),
    ]
    cheek_right=[
        (.010,-.158,1.704),(.116,-.133,1.708),
        (.072,-.143,1.607),(0,-.166,1.576),
    ]
    bordered_panel("head","BevorCheekL",cheek_left,(-.062,-.188,1.654),steel,brass,arm,"head",.11,.012,.005)
    bordered_panel("head","BevorCheekR",cheek_right,(.062,-.188,1.654),steel,brass,arm,"head",.11,.012,.005)
    chin=[
        (-.038,-.158,1.624),(.038,-.158,1.624),
        (.050,-.148,1.585),(0,-.178,1.557),(-.050,-.148,1.585),
    ]
    bordered_panel("head","DucalChinPlate",chin,(0,-.194,1.590),dark,brass,arm,"head",.11,.011,.005)
    for row,z in enumerate((1.676,1.651,1.626)):
        for side in (-1,1):
            for column in range(2):
                x=side*(.034+column*.025)
                sphere("head",f"BevorVent{row}{side}{column}",(x,-.194,z),(.0055,.0025,.0055),black,arm,"head",12,8)
    for side in (-1,1):
        cylinder("head",f"VisorPivot{side}",(side*.128,-.020,1.735),.023,.017,brass,arm,"head",rotation=(0,math.pi/2,0))
        cylinder("head",f"VisorPivotInset{side}",(side*.137,-.020,1.735),.012,.019,dark,arm,"head",rotation=(0,math.pi/2,0))
    # Articulated neck lames and a full ducal horsehair crest complete it.
    for index,(z,radius) in enumerate(((1.612,.126),(1.584,.135),(1.557,.145))):
        torus("head",f"NeckLame{index}",(0,.006,z),radius,.006,steel if index<2 else dark,arm,"head",scale=(1.0,.72,1.0))
    ducal_plume(arm,crimson_plume,crimson_shadow,brass)


def add_gothic_cuirass(arm, steel, dark, brass, mail, leather, blue_cloth):
    # Start from the hero's actual weighted ribcage, then smooth the anatomy
    # into a forged surface.  This preserves the human taper without copying
    # every abdominal groove into the steel.
    cuirass=subset_weighted_surface(
        "chest","PlanishedDucalCuirass",cobalt_filigree,
        lambda co: .965 < co.z < 1.535 and abs(co.x) < .350,
        outward=.025,thickness=0.0,bevel=0.0,
    )
    uv_layer=cuirass.data.uv_layers.new(name="RoyalCuirassPlanarUV")
    for loop_index,loop in enumerate(cuirass.data.loops):
        vertex=cuirass.data.vertices[loop.vertex_index].co
        uv_layer.data[loop_index].uv=(
            ((vertex.x+.350)/.700)*1.10,
            ((vertex.z-.965)/.570)*1.10,
        )
    smooth=cuirass.modifiers.new("PlanishedAnatomy","LAPLACIANSMOOTH")
    smooth.iterations=5
    smooth.lambda_factor=.100
    smooth.use_volume_preserve=True
    solid=cuirass.modifiers.new("ForgedCuirassThickness","SOLIDIFY")
    solid.thickness=.010
    solid.offset=-.15
    edge=cuirass.modifiers.new("SoftRolledCuirassEdge","BEVEL")
    edge.width=.003
    edge.segments=3
    # Fitted clavicle mantle remains behind the cuirass and pauldrons, closing
    # skin gaps without becoming a projected horizontal collar bar.
    mantle=subset_weighted_surface(
        "chest","ClosedClavicleMantle",dark,
        lambda co: 1.485 < co.z < 1.590 and abs(co.x) < .430,
        outward=.018,thickness=0.0,bevel=0.0,
    )
    mantle_smooth=mantle.modifiers.new("MantlePlanishing","LAPLACIANSMOOTH")
    mantle_smooth.iterations=3
    mantle_smooth.lambda_factor=.080
    mantle_smooth.use_volume_preserve=True
    mantle_solid=mantle.modifiers.new("MantleThickness","SOLIDIFY")
    mantle_solid.thickness=.004
    mantle_solid.offset=-.15
    mantle_edge=mantle.modifiers.new("MantleRolledEdge","BEVEL")
    mantle_edge.width=.002
    mantle_edge.segments=2

    # One closed gorget replaces the old stack of visibly separate rings.
    lofted_cuirass(
        "chest","ClosedDucalGorget",
        [
            (1.485,.170,.154,.142),
            (1.520,.158,.145,.136),
            (1.555,.146,.136,.129),
            (1.585,.135,.126,.121),
        ],
        dark,arm,"chest",36,
    )

    # Mail voiders are tucked beneath the shells, never placed in front of them.
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        sphere("chest",f"MailShoulderVoid{suffix}",(side*.294,.025,1.401),(.083,.076,.112),mail,arm,f"upper_arm.{suffix}",28,18)
        sleeve=cone_between(
            "chest",f"MailUpperSleeve{suffix}",
            (side*.340,.012,1.370),(side*.340,.010,1.245),
            .071,.066,mail,arm,f"upper_arm.{suffix}",28,
        )
        sleeve.scale=(1.0,.94,1.0)

    # One continuous fauld shell overlaps the waist instead of three hovering
    # flattened spheres.  The dark lower edge is assigned on this same mesh.
    fauld_rings=[
        (.915,.226,.212,.186),
        (.934,.231,.216,.189),
        (.956,.238,.222,.193),
        (.980,.244,.227,.197),
        (1.005,.246,.229,.199),
        (1.027,.242,.225,.195),
    ]
    fauld=lofted_cuirass("chest","ArticulatedFauld",fauld_rings,steel,arm,"pelvis",40)
    fauld.data.materials.append(dark)
    fauld.data.materials.append(bright_steel)
    fauld.data.materials.append(brass)
    for polygon in fauld.data.polygons:
        row=polygon.index//40
        if row==0:
            polygon.material_index=1
        elif row==2:
            polygon.material_index=2
        elif row==4:
            polygon.material_index=3

    # Two close-set tasset lames per thigh.  Gold borders are faces of the same
    # mesh, not rods placed in front of it.
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        cx=side*.153
        for row,(top,bottom,half) in enumerate(((.942,.830,.106),(.848,.715,.100))):
            boundary=[
                (cx-half,-.184,top),
                (cx+half,-.184,top),
                (cx+half*.88,-.195,bottom),
                (cx,-.218,bottom-.018),
                (cx-half*.88,-.195,bottom),
            ]
            center=(cx,-.222,(top+bottom)*.5)
            bordered_panel(
                "chest",f"IntegratedTasset{suffix}{row}",boundary,center,
                steel if row==0 else dark,brass,arm,
                "pelvis" if row==0 else f"thigh.{suffix}",
                inset=.11,thickness=.010,bevel=.004,
            )
        # Matching rear culet lames sit against the seat and cover the open
        # upper edges of the fitted cuisses.
        rear_cx=side*.142
        for row,(top,bottom,half) in enumerate(((.945,.825,.110),(.842,.715,.103))):
            rear_boundary=[
                (rear_cx-half,.184,top),
                (rear_cx-half*.90,.197,bottom),
                (rear_cx,.218,bottom-.016),
                (rear_cx+half*.90,.197,bottom),
                (rear_cx+half,.184,top),
            ]
            rear_center=(rear_cx,.226,(top+bottom)*.5)
            bordered_panel(
                "chest",f"IntegratedCulet{suffix}{row}",rear_boundary,rear_center,
                dark if row==0 else steel,brass,arm,
                "pelvis" if row==0 else f"thigh.{suffix}",
                inset=.11,thickness=.009,bevel=.004,
            )


def add_gothic_arms(arm, steel, dark, brass, mail, leather):
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        upper=f"upper_arm.{suffix}"
        fore=f"forearm.{suffix}"
        x=.340*side

        # A close shoulder shell with its gilt border assigned to edge faces.
        # Nothing is suspended in front of the pauldron.
        center=(side*.292,-.003,1.405)
        radii=(.151,.116,.130)
        curved_pauldron(
            "shoulders",f"IntegratedPauldron{suffix}",
            side,center,radii,steel,arm,upper,brass,
        )

        # Exact weighted arm surfaces retain the full anatomical wrap.  The
        # very low threshold prevents the old longitudinal missing strip.
        fitted_body_piece_by_group(
            "shoulders",f"FittedRerebrace{suffix}",steel,
            (upper,),1.125,1.365,
            outward=.018,thickness=.005,minimum_weight=.0001,
        )
        torus(
            "shoulders",f"RerebraceUpperRoll{suffix}",
            (x,-.002,1.350),.094,.007,dark,arm,upper,
            scale=(1.0,.86,1.0),
        )
        fitted_body_piece_by_group(
            "hands",f"FittedVambrace{suffix}",steel,
            (fore,),.905,1.165,
            outward=.019,thickness=.005,minimum_weight=.0001,
        )

        # A single fitted hand shell preserves the existing fingers and closes
        # every old knuckle seam.  The cuff overlaps the vambrace.
        fitted_body_piece_by_group(
            "hands",f"AnatomicalGauntlet{suffix}",bright_steel,
            (f"hand.{suffix}",),.730,.925,
            outward=.010,thickness=.0035,
        )
        torus(
            "hands",f"IntegratedWristCuff{suffix}",
            (x,-.002,.918),.061,.007,dark,arm,f"hand.{suffix}",
            scale=(1.0,.84,1.0),
        )


def add_gothic_legs(arm, steel, dark, brass, mail, leather, blue_cloth):
    weighted_body_garment("pants","WoolHoseAndArmingBase",blue_cloth,.120,1.025,.310,.006)
    torus("pants","RecessedArmingBelt",(0,.002,1.008),.244,.015,leather,arm,"pelvis",scale=(1.0,.65,1.0))
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        thigh=f"thigh.{suffix}"
        shin=f"shin.{suffix}"
        x=.131*side

        # A blended-weight mail voider spans the knee before rigid thigh/shin
        # shells are added.  It prevents skin exposure in deep Walk/Jump bends.
        subset_weighted_surface(
            "pants",f"BlendedKneeMail{suffix}",mail,
            lambda co,s=side: .030 < co.x*s < .290 and .485 < co.z < .675,
            outward=.018,thickness=.002,bevel=.001,
        )

        # Exact anatomical copies of the weighted thighs and calves give the
        # armor a human silhouette instead of the old oversized cylinders.
        cuisse=fitted_body_piece_by_group(
            "pants",f"FittedCuisse{suffix}",steel,
            (thigh,),.625,.915,
            outward=.016,thickness=.006,
        )
        cuisse.data.materials.append(dark)
        for polygon in cuisse.data.polygons:
            center=sum((cuisse.data.vertices[i].co for i in polygon.vertices),Vector())/len(polygon.vertices)
            if center.z < .670:
                polygon.material_index=1

        greave=fitted_body_piece_by_group(
            "feet",f"FittedGreave{suffix}",steel,
            (shin,),.145,.535,
            outward=.015,thickness=.006,
        )
        greave.data.materials.append(dark)
        for polygon in greave.data.polygons:
            center=sum((greave.data.vertices[i].co for i in polygon.vertices),Vector())/len(polygon.vertices)
            if center.z < .185:
                polygon.material_index=1

        # Compact poleyn cup overlaps both fitted leg shells.
        sphere("feet",f"PoleynCup{suffix}",(x,-.010,.557),(.086,.072,.074),bright_steel,arm,shin,30,18)

        # Smooth closed sabaton with articulated color bands built into the
        # same mesh; the individual human toes remain hidden inside.
        sabaton_shell(
            "feet",f"ClosedDucalSabaton{suffix}",x,steel,arm,f"foot.{suffix}",
            accent_material=bright_steel,dark_material=dark,
        )


def add_apex_helmet(arm, steel, cobalt, dark, brass, black, crimson, crimson_dark):
    """A closed armet whose visor, bevor and gorget visibly overlap.

    The former version used two face panels and three torus rings.  From the
    front those read as a floating mask above loose hoops.  This version starts
    with a single load-bearing visor shell, attaches it to both pivots with
    hinge cheeks, and sleeves the whole assembly into a continuous gorget.
    """
    sphere("head","ApexArmetSkull",(0,.004,1.776),(.132,.122,.151),steel,arm,"head",56,36)
    sphere("head","ApexArmetOccipital",(0,.048,1.704),(.133,.116,.105),dark,arm,"head",48,28)

    # Rear neck defense overlaps the skull above and the chest gorget below.
    rear_tail=[
        (-.126,.103,1.735),(.126,.103,1.735),
        (.142,.132,1.636),(.105,.154,1.574),
        (0,.164,1.552),(-.105,.154,1.574),(-.142,.132,1.636),
    ]
    bordered_panel(
        "head","ApexCrownedRearTail",rear_tail,(0,.172,1.650),
        dark,brass,arm,"head",.060,.014,.005,
    )

    # Continuous visor: all front facets, border, and central crown share the
    # same vertices.  It reaches the temple plates instead of hovering forward.
    visor=[
        (-.134,-.119,1.817),(0,-.142,1.833),(.134,-.119,1.817),
        (.137,-.137,1.711),(.077,-.164,1.681),(0,-.181,1.661),
        (-.077,-.164,1.681),(-.137,-.137,1.711),
    ]
    bordered_panel(
        "head","ApexContinuousVisor",visor,(0,-.188,1.748),
        cobalt,brass,arm,"head",.070,.014,.004,
    )
    # A brow rail overlaps both visor and skull, making the upper attachment
    # unambiguous even in silhouette.
    brow=[
        (-.139,-.112,1.823),(.139,-.112,1.823),
        (.132,-.145,1.791),(-.132,-.145,1.791),
    ]
    bordered_panel(
        "head","ApexVisorBrowRail",brow,(0,-.153,1.807),
        dark,brass,arm,"head",.055,.011,.003,
    )
    box("head","ApexEyeVoid",(0,-.194,1.766),(.224,.010,.021),black,arm,"head",bevel=.003)
    box("head","ApexNasalKeel",(0,-.202,1.704),(.014,.010,.120),brass,arm,"head",bevel=.003)

    # One bevor overlaps the visor by 20–30 mm and closes the jaw continuously.
    bevor=[
        (-.132,-.137,1.727),(.132,-.137,1.727),
        (.126,-.151,1.632),(.081,-.169,1.585),
        (0,-.189,1.560),(-.081,-.169,1.585),(-.126,-.151,1.632),
    ]
    bordered_panel(
        "head","ApexContinuousBevor",bevor,(0,-.207,1.648),
        dark,brass,arm,"head",.075,.014,.004,
    )
    chin=[
        (-.072,-.177,1.621),(.072,-.177,1.621),
        (.060,-.187,1.577),(0,-.211,1.548),(-.060,-.187,1.577),
    ]
    bordered_panel("head","ApexChin",chin,(0,-.218,1.584),steel,brass,arm,"head",.075,.012,.004)
    for row,z in enumerate((1.676,1.650,1.624)):
        for side in (-1,1):
            for column in range(2):
                x=side*(.032+column*.026)
                sphere("head",f"ApexVent{row}{side}{column}",(x,-.211,z),(.0055,.0025,.0055),black,arm,"head",12,8)
    for side in (-1,1):
        # Large side cheek plate bridges skull, visor, and bevor.
        temple=[
            (side*.104,-.099,1.815),(side*.143,-.074,1.784),
            (side*.143,-.083,1.682),(side*.111,-.124,1.627),
            (side*.094,-.135,1.708),
        ]
        bordered_panel(
            "head",f"ApexHingedTemple{'L' if side<0 else 'R'}",temple,
            (side*.145,-.116,1.722),steel,brass,arm,"head",.070,.012,.0035,
        )
        pivot=(side*.139,-.086,1.748)
        cylinder("head",f"ApexVisorPivot{side}",pivot,.024,.022,brass,arm,"head",rotation=(0,math.pi/2,0))
        cylinder("head",f"ApexPivotInset{side}",(side*.151,-.086,1.748),.012,.024,dark,arm,"head",rotation=(0,math.pi/2,0))
        # Hinge arms physically run from the pivots into the visor brow.
        cone_between(
            "head",f"ApexVisorHingeArm{side}",pivot,
            (side*.118,-.130,1.800),.010,.007,dark,arm,"head",16,
        )
        sphere("head",f"ApexTempleRivet{side}",(side*.119,-.132,1.804),(.008,.004,.008),brass,arm,"head",16,10)

    # A solid three-lame neck sleeve replaces the visibly floating torus rings.
    upper_gorget=lofted_cuirass(
        "head","ApexUpperGorget",
        [
            (1.535,.172,.158,.154),
            (1.558,.169,.157,.152),
            (1.583,.160,.151,.147),
            (1.608,.151,.144,.141),
            (1.630,.143,.137,.135),
        ],
        steel,arm,"head",40,
    )
    upper_gorget.data.materials.append(dark)
    upper_gorget.data.materials.append(brass)
    for polygon in upper_gorget.data.polygons:
        row=polygon.index//40
        polygon.material_index=2 if row in (0,2) else (1 if row==1 else 0)

    # A narrow fore-aft crest replaces the old transverse billboard.
    yz_prism(
        "head","ApexCrestComb",
        [(-.112,1.876),(.104,1.884),(.140,1.910),(.102,1.944),(-.095,1.936)],
        .027,dark,arm,"head",.005,
    )
    box("head","ApexCrestGiltRail",(0,.006,1.902),(.072,.265,.022),brass,arm,"head",bevel=.006)
    for index,y in enumerate((-.092,-.070,-.048,-.026,-.004,.018,.040,.062,.084,.106)):
        height=.185+(.045*(1.0-abs(index-4.5)/4.5))
        lean=.040+index*.004
        cone_between(
            "head",f"ApexHorsehair{index}",
            (0,y,1.914),(0,y+lean,1.914+height),
            .015,.003,crimson if index%3 else crimson_dark,arm,"head",12,
        )
        cone_between(
            "head",f"ApexHorsehairTail{index}",
            (0,y+lean,1.914+height),(0,y+.105,1.875+height*.58),
            .010,.002,crimson_dark if index%2 else crimson,arm,"head",10,
        )


def add_unified_apex_helmet(arm, steel, cobalt, dark, brass, black, crimson, crimson_dark):
    """Forge skull, visor, bevor, chin and gorget as one continuous shell.

    There are no face plates hovering over a dome in this revision.  Profile
    changes in the shared ring vertices create the brow and nasal relief, while
    material regions create the eye slit, ventilation and gilt engraving on the
    same watertight surface.
    """
    segments=96
    rings=[
        # z, half width, front depth, rear depth, superellipse exponent
        # The neck lames flare gently into the gorget, then taper immediately
        # into a close jaw.  This removes the old pot-shaped lower silhouette.
        (1.525,.166,.154,.150,2.34),
        (1.548,.162,.160,.147,2.36),
        (1.574,.140,.174,.141,2.40),
        (1.600,.124,.184,.136,2.44),
        (1.628,.126,.192,.132,2.48),
        (1.658,.132,.194,.129,2.50),
        (1.688,.138,.191,.127,2.50),
        (1.718,.144,.186,.126,2.46),
        (1.742,.148,.181,.125,2.42),
        # Eye aperture and brow share the same shell but step inward enough to
        # read as a working visor rather than a painted cylinder.
        (1.750,.149,.172,.125,2.40),
        (1.775,.149,.172,.125,2.38),
        (1.783,.150,.182,.125,2.34),
        (1.807,.151,.164,.124,2.28),
        (1.830,.148,.149,.122,2.20),
        (1.852,.136,.135,.119,2.10),
        (1.874,.128,.121,.114,2.02),
        (1.895,.114,.105,.104,2.00),
        (1.913,.092,.084,.086,2.00),
        (1.927,.064,.057,.060,2.00),
        (1.937,.033,.030,.032,2.00),
        (1.942,.009,.008,.009,2.00),
    ]
    vertices=[]
    for z,half_x,front_depth,rear_depth,exponent in rings:
        for column in range(segments):
            angle=math.tau*column/segments
            cosine=math.cos(angle)
            sine=math.sin(angle)
            x=half_x*math.copysign(abs(cosine)**(2.0/exponent),cosine)
            depth=rear_depth if sine>=0 else front_depth
            y=depth*math.copysign(abs(sine)**(2.0/exponent),sine)
            if sine<0:
                frontness=abs(sine)**7
                # The nasal keel and brow are embossed from the shell itself.
                keel=max(0.0,1.0-abs(x)/.028)
                if 1.600<=z<=1.823:
                    y-=.0105*keel*frontness
                if 1.775<=z<=1.823:
                    brow=max(0.0,1.0-abs(x)/(.135))
                    y-=.0060*brow*frontness
                # A modest chin prow gives the lower helmet a forged profile
                # without adding a separate chin object.
                if 1.548<=z<=1.625:
                    chin=max(0.0,1.0-abs(x)/.075)
                    y-=.0070*chin*frontness
                # Two swept repoussé ribs are raised directly from the cheek
                # surface.  They provide authored relief without separate rods.
                if .016<=abs(x)<=.130 and 1.600<=z<=1.720:
                    for crest_z,slope,width,depth in (
                        (1.714,.62,.0060,.0042),
                        (1.672,.43,.0055,.0034),
                    ):
                        target=crest_z-slope*(abs(x)-.016)
                        distance=abs(z-target)
                        if distance<width:
                            y-=depth*(1.0-distance/width)*frontness
                # The gilt perimeter is a shallow rolled step in the same mesh.
                edge_band=1.0-abs(abs(x)-.124)/.014
                if 1.600<=z<=1.823 and edge_band>0:
                    y-=.0030*min(1.0,edge_band)*frontness
            vertices.append((x,y,z))
    faces=[]
    for row in range(len(rings)-1):
        for column in range(segments):
            nxt=(column+1)%segments
            a=row*segments+column
            b=row*segments+nxt
            c=(row+1)*segments+nxt
            d=(row+1)*segments+column
            faces.append((a,b,c,d))
    top_start=(len(rings)-1)*segments
    faces.append(tuple(top_start+column for column in range(segments)))
    shell=plate("head","ApexUnifiedHelmetShell",vertices,faces,steel,arm,"head")
    for material in (cobalt,dark,brass,black):
        shell.data.materials.append(material)
    for polygon in shell.data.polygons[:-1]:
        row=polygon.index//segments
        column=polygon.index%segments
        z0=rings[row][0]
        z1=rings[row+1][0]
        zmid=(z0+z1)*.5
        angle=math.tau*(column+.5)/segments
        front_delta=abs((angle-1.5*math.pi+math.pi)%math.tau-math.pi)
        material_index=0
        # Cobalt visor and bevor fields are regions of this
        # shell, not independently offset panels.
        if front_delta<.78 and 1.783<=zmid<=1.830:
            material_index=1
        elif front_delta<.78 and 1.600<=zmid<1.742:
            material_index=1
        elif front_delta<.72 and 1.750<=z0 and z1<=1.775:
            material_index=4
        # Thin integral gilt brows above/below the eye aperture.
        if front_delta<.78 and (
            (1.742<=z0 and z1<=1.750) or
            (1.775<=z0 and z1<=1.783)
        ):
            material_index=3
        # Rolled gilt perimeter and central nasal ridge are face assignments on
        # the embossed vertices; they cannot float away from the helmet.
        if .715<front_delta<.790 and 1.600<zmid<1.823:
            material_index=3
        if front_delta<.025 and 1.600<zmid<1.823:
            material_index=3
        # The lowest shared rings read as articulated gorget lames without
        # breaking the helmet into separate hoops.
        if zmid<1.600:
            material_index=3 if row in (0,2) else (2 if row==1 else 0)
        polygon.material_index=material_index
        polygon.use_smooth=True
    shell.data.polygons[-1].material_index=0
    shell.data.polygons[-1].use_smooth=True
    uv=shell.data.uv_layers.new(name="UnifiedHelmetUV")
    for loop_index,loop in enumerate(shell.data.loops):
        vertex=shell.data.vertices[loop.vertex_index].co
        uv.data[loop_index].uv=((vertex.x+.18)/.36,(vertex.z-1.525)/.417)
    solid=shell.modifiers.new("UnifiedForgedThickness","SOLIDIFY")
    solid.thickness=.012
    solid.offset=-1.0
    bevel=shell.modifiers.new("UnifiedPlanishedEdges","BEVEL")
    bevel.width=.0028
    bevel.segments=3
    shell["continuous_shell"]=True
    shell["embossed_relief"]=True
    shell["separate_faceplates"]=0

    # Crest hardware is seated through the crown.  It is the only external
    # helmet assembly because it is mechanically removable on real armor.
    yz_prism(
        "head","ApexUnifiedCrestComb",
        [(-.104,1.904),(.096,1.914),(.128,1.938),(.094,1.958),(-.090,1.948)],
        .024,dark,arm,"head",.004,
    )
    box("head","ApexEmbeddedCrestRail",(0,.004,1.927),(.064,.224,.018),brass,arm,"head",bevel=.004)
    for index,y in enumerate((-.082,-.060,-.038,-.016,.006,.028,.050,.072,.094)):
        height=.172+(.038*(1.0-abs(index-4)/4))
        lean=.036+index*.004
        cone_between(
            "head",f"ApexUnifiedHorsehair{index}",
            (0,y,1.932),(0,y+lean,1.932+height),
            .014,.003,crimson if index%3 else crimson_dark,arm,"head",12,
        )
        cone_between(
            "head",f"ApexUnifiedHorsehairTail{index}",
            (0,y+lean,1.932+height),(0,y+.096,1.900+height*.60),
            .009,.002,crimson_dark if index%2 else crimson,arm,"head",10,
        )


def add_apex_cuirass(arm, steel, cobalt, bright, dark, brass, mail, leather):
    """Rigid closed harness with seated relief, gorget and shoulder bridges."""
    # Mail is the only visible flexible foundation.  It deliberately fills the
    # armpits and joint recesses without resembling exposed skin.
    # Stop the flexible foundation below the cuirass/gorget overlap.  The old
    # high band remained visible across the whole upper breast and was easily
    # mistaken for shoulder armor laid over the chest plate.
    weighted_body_garment("chest","ApexArmingFoundation",mail,.930,1.545,.520,.012)
    # A narrow blackened clavicle foundation fills only the collar opening.
    # It sits beneath both cuirass and gorget, removing exposed skin without
    # recreating the broad shoulder mantle rejected in the previous pass.
    # Continue the flexible dark arming layer high enough to remain under the
    # gorget and pauldrons when both arms lift for a spell.  This is not an
    # exterior shoulder plate: it follows the original blended body weights
    # and prevents animated skin wedges from reopening around the collar.
    weighted_body_garment("chest","ApexClavicleFoundation",dark,1.465,1.650,.380,.014)
    # Two short lateral saddles protect the clavicle joints without laying a
    # false shoulder plate across the front or back of the breastplate.
    for side in (-1, 1):
        suffix = "L" if side < 0 else "R"
        lateral_shoulder_bridge(
            "shoulders",f"ApexLateralShoulderBridge{suffix}",side,
            cobalt,dark,dark,arm,
        )
    cuirass=lofted_cuirass(
        "chest","ApexWaistedCuirass",
        [
            (.970,.242,.155,.150),
            (1.055,.262,.170,.161),
            (1.165,.300,.190,.177),
            (1.300,.330,.205,.187),
            (1.420,.334,.202,.188),
            (1.485,.318,.190,.180),
            (1.525,.292,.178,.170),
        ],
        cobalt,arm,"chest",48,
    )
    cuirass.data.materials.append(bright)
    cuirass.data.materials.append(dark)
    cuirass.data.materials.append(brass)
    # Raise one sternum keel and paired peascod flutes from the breastplate
    # itself.  This creates connected forged detail without adding ornaments
    # that can float away from the animated shell.
    for vertex in cuirass.data.vertices:
        co=vertex.co
        if co.y<-.080 and 1.015<co.z<1.495:
            vertical_profile=max(0.0,math.sin((co.z-1.015)/.480*math.pi))
            sternum=.0055*max(0.0,1.0-abs(co.x)/.020)*vertical_profile
            flute_target=.035+(co.z-1.015)*.235
            paired=.0045*max(0.0,1.0-abs(abs(co.x)-flute_target)/.025)*vertical_profile
            co.y-=sternum+paired
    for polygon in cuirass.data.polygons:
        row=polygon.index//48
        column=polygon.index%48
        angle=2*math.pi*(column+.5)/48
        front_delta=abs((angle-1.5*math.pi+math.pi)%(2*math.pi)-math.pi)
        back_delta=abs((angle-.5*math.pi+math.pi)%(2*math.pi)-math.pi)
        if row in (0,5):
            polygon.material_index=2
        elif back_delta<.72:
            # Keep the back a single deep royal blue plate.  A broad bright
            # stripe across this region read as a pale-blue floating panel.
            polygon.material_index=0
        elif .58<front_delta<1.08:
            # The planished side fields appeared light blue in Godot.  Use
            # blackened inset plate for contrast while preserving deep cobalt.
            polygon.material_index=2
        elif front_delta<.050:
            polygon.material_index=3

    # Closed lower gorget telescopes inside the helmet sleeve and outside the
    # cuirass collar, leaving no throat or neck strip exposed.
    lower_gorget=lofted_cuirass(
        "chest","ApexClosedGorget",
        [
            # The bottom lame flares over both clavicles and seats behind the
            # breastplate.  This closes the exposed skin wedges without
            # putting a shoulder mantle across the face of the cuirass.
            (1.475,.280,.170,.166),(1.500,.250,.170,.164),
            (1.528,.214,.166,.159),(1.556,.181,.158,.153),
            (1.580,.166,.153,.148),
        ],
        steel,arm,"chest",40,
    )
    lower_gorget.data.materials.append(dark)
    lower_gorget.data.materials.append(brass)
    for polygon in lower_gorget.data.polygons:
        row=polygon.index//40
        polygon.material_index=2 if row in (0,2) else (1 if row==1 else 0)
    fauld=lofted_cuirass(
        "chest","ApexArticulatedFauld",
        [
            (.845,.222,.210,.208),(.875,.230,.216,.216),(.905,.238,.222,.222),
            (.935,.244,.227,.226),(.965,.248,.230,.230),(.995,.248,.228,.228),
            (1.025,.240,.220,.220),
        ],
        steel,arm,"pelvis",44,
    )
    fauld.data.materials.append(cobalt)
    fauld.data.materials.append(dark)
    fauld.data.materials.append(brass)
    for polygon in fauld.data.polygons:
        row=polygon.index//44
        polygon.material_index=(1 if row in (0,1,3,5) else (2 if row==4 else 0))

    # Large fitted front tassets wrap each moving thigh independently.
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        groups=("pelvis",f"thigh.{suffix}")
        front_tasset=fitted_body_piece_by_group_region(
            "chest",f"ApexUnifiedFrontTasset{suffix}",cobalt,groups,
            lambda co,s=side: co.x*s>.002 and .600<co.z<1.005 and co.y<.045,
            outward=.016,thickness=.002,minimum_weight=.012,
        )
        front_tasset.data.materials.append(bright)
    # One continuous forged culet follows the pelvis and seats directly below
    # the fauld.  It replaces body-derived butt halves and their center void.
    continuous_rear_culet(
        "chest","ApexUnifiedRearCulet",cobalt,dark,steel,arm,
    )


def add_apex_arms(arm, steel, cobalt, bright, dark, brass, mail, leather):
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        clavicle=f"clavicle.{suffix}"
        upper=f"upper_arm.{suffix}"
        fore=f"forearm.{suffix}"
        hand=f"hand.{suffix}"
        x=.340*side
        # The body-weighted gusset below is the flexible armpit closure.  Do not
        # add a clavicle-hung mail sphere here: from the front it covered the
        # designed pauldron with a large vertical oval and read as another blob.
        sphere("shoulders",f"ApexMailVoid{suffix}",(side*.286,.010,1.382),(.108,.095,.132),mail,arm,upper,32,20)
        fitted_body_piece_by_group_region(
            "shoulders",f"ApexArticulatedMailGusset{suffix}",mail,
            (clavicle,upper,"chest"),
            lambda co,s=side: .165<co.x*s<.520 and 1.135<co.z<1.535,
            outward=.010,thickness=.003,minimum_weight=.006,
        )
        curved_pauldron(
            "shoulders",f"ApexGrandPauldron{suffix}",side,
            (side*.298,-.002,1.438),(.212,.154,.164),
            # The crown hangs from the clavicle suspension point; the lower
            # skirt follows the upper arm beneath it.  This real pauldron-like
            # articulation keeps the crown over the shoulder during attacks
            # instead of dragging the whole dome across the breastplate.
            cobalt,arm,clavicle,brass,
        )
        # Three shallow overlapping lames replace the second full dome.  They
        # read as a designed pauldron skirt while retaining a continuous
        # overlap with both crown and rerebrace during arm motion.
        articulated_shoulder_skirt(
            "shoulders",f"ApexUnifiedShoulderSkirt{suffix}",side,
            (side*.310,.002,1.430),(.186,.138,.182),
            cobalt,dark,brass,arm,upper,
        )
        fitted_body_piece_by_group(
            "shoulders",f"ApexRerebrace{suffix}",cobalt,(upper,),
            1.075,1.420,outward=.038,thickness=.007,minimum_weight=.110,
        )
        # The earlier torus read edge-on as a loose gold rod between the
        # pauldron and breastplate.  The overlapping skirt/rerebrace now forms
        # the complete articulated transition without that detached accent.

        # Angular elbow couter with an outer wing and recessed pivot.
        elbow_outline=[
            (x-.090,1.205),(x+.090,1.205),(x+.105,1.155),
            (x+.066,1.095),(x,1.068),(x-.066,1.095),(x-.105,1.155),
        ]
        forged_prism("hands",f"ApexCouter{suffix}",elbow_outline,-.118,-.028,cobalt,arm,fore,.006)
        sphere("hands",f"ApexElbowBoss{suffix}",(x,-.130,1.145),(.025,.008,.025),brass,arm,fore,18,10)
        fitted_body_piece_by_group(
            "hands",f"ApexVambrace{suffix}",cobalt,(fore,),
            .900,1.150,outward=.016,thickness=.006,minimum_weight=.150,
        )
        torus("hands",f"ApexWristRoll{suffix}",(x,-.002,.920),.062,.007,dark,arm,hand,scale=(1.0,.84,1.0))

        fitted_body_piece_by_group(
            "hands",f"ApexGauntlet{suffix}",steel,(hand,),
            .730,.925,outward=.012,thickness=.004,minimum_weight=.150,
        )
        # The fitted gauntlet is the backhand plate.  Separate bordered panels
        # and bead-like knuckles became detached spikes in flexed walk poses.
        # Keep the hand as one continuous, deformation-safe shell.


def add_apex_legs(arm, steel, cobalt, bright, dark, brass, mail, leather, blue_cloth):
    weighted_body_garment("pants","ApexArmingHose",blue_cloth,.120,1.025,.310,.007)
    torus("pants","ApexHarnessBelt",(0,.002,1.008),.244,.015,leather,arm,"pelvis",scale=(1.0,.65,1.0))
    box("pants","ApexRoyalBuckle",(0,-.176,1.012),(.066,.020,.047),brass,arm,"pelvis",bevel=.007)
    for side in (-1,1):
        suffix="L" if side<0 else "R"
        thigh=f"thigh.{suffix}"
        shin=f"shin.{suffix}"
        foot=f"foot.{suffix}"
        x=.131*side
        subset_weighted_surface(
            "pants",f"ApexKneeVoid{suffix}",mail,
            lambda co,s=side: .025<co.x*s<.295 and .480<co.z<.680,
            outward=.017,thickness=.002,bevel=.001,
        )
        cuisse=fitted_body_piece_by_group(
            "pants",f"ApexCuisse{suffix}",cobalt,(thigh,),
            .620,.918,outward=.018,thickness=.006,
        )
        cuisse.data.materials.append(dark)
        for polygon in cuisse.data.polygons:
            center=sum((cuisse.data.vertices[i].co for i in polygon.vertices),Vector())/len(polygon.vertices)
            if center.z<.665:polygon.material_index=1
        torus("pants",f"ApexCuisseTopRoll{suffix}",(x,-.002,.900),.106,.006,dark,arm,thigh,scale=(1.0,.86,1.0))

        knee_outline=[
            (x-.104,.650),(x+.104,.650),(x+.118,.590),
            (x+.072,.526),(x,.487),(x-.072,.526),(x-.118,.590),
        ]
        forged_prism("feet",f"ApexPoleyn{suffix}",knee_outline,-.132,-.030,steel,arm,shin,.007)
        sphere("feet",f"ApexPoleynBoss{suffix}",(x,-.146,.580),(.026,.008,.026),brass,arm,shin,18,10)
        greave=fitted_body_piece_by_group(
            "feet",f"ApexGreave{suffix}",steel,(shin,),
            .145,.540,outward=.017,thickness=.006,
        )
        greave.data.materials.append(dark)
        for polygon in greave.data.polygons:
            center=sum((greave.data.vertices[i].co for i in polygon.vertices),Vector())/len(polygon.vertices)
            if center.z<.185:polygon.material_index=1
        for z in (.430,.335,.240):
            sphere("feet",f"ApexGreaveRivet{suffix}{z}",(x,-.121,z),(.006,.003,.006),bright,arm,shin,12,8)

        # Long pointed sabatons with overlapping metatarsal lames.
        sabaton_shell("feet",f"ApexSabaton{suffix}",x,dark,arm,foot,accent_material=steel,dark_material=cobalt)
        for index,(y,width,z) in enumerate(((-.042,.088,.128),(-.124,.098,.112),(-.210,.104,.095),(-.292,.086,.078))):
            box("feet",f"ApexSabatonLame{suffix}{index}",(x,y,z),(width*1.82,.025,.028),steel if index%2==0 else cobalt,arm,foot,bevel=.006)
            box("feet",f"ApexSabatonGilt{suffix}{index}",(x,y-.014,z+.010),(width*1.68,.006,.006),brass,arm,foot,bevel=.002)


armature = bpy.data.objects.get("HeroRig")
if armature is None:
    raise RuntimeError("HeroRig was not found in the open Blender file")
remove_previous()

steel = mat("Royal Blued Steel", (.045,.062,.088,1), .92, .34)
bright_steel = mat("Royal Planished Edge Steel", (.215,.255,.310,1), .94, .31)
dark = mat("Royal Blackened Steel", (.012,.018,.028,1), .90, .40)
brass = mat("Royal Gilt Brass", (.470,.235,.038,1), .90, .34)
ruby = mat("Royal Cabochon Ruby", (.300,.006,.012,1), .42, .24)
black = mat("Helmet Interior", (.004,.005,.007,1), .22, .72)
mail = mat("Riveted Mail", (.090,.105,.125,1), .82, .58)
leather = mat("Harness Leather", (.080,.032,.014,1), .05, .82)
blue_cloth = mat("Royal Blue Arming Cloth", (.010,.020,.052,1), .02, .93)
crimson_plume = mat("Ducal Crimson Horsehair", (.280,.012,.018,1), .02, .62)
crimson_shadow = mat("Ducal Horsehair Shadow", (.070,.004,.007,1), .01, .78)
cobalt_filigree = textured_mat(
    "Royal Cobalt Filigree Plate",
    (.028,.075,.190,1),
    .78,
    .32,
    os.path.join(ROOT,"godot","assets","hero","textures","royal_cobalt_filigree_v1.png"),
    os.path.join(ROOT,"godot","assets","hero","textures","royal_cobalt_filigree_normal_v1.png"),
    os.path.join(ROOT,"godot","assets","hero","textures","royal_cobalt_filigree_roughness_v1.png"),
)

add_unified_apex_helmet(armature,steel,cobalt_filigree,dark,brass,black,crimson_plume,crimson_shadow)
add_apex_cuirass(armature,steel,cobalt_filigree,bright_steel,dark,brass,mail,leather)
add_apex_arms(armature,steel,cobalt_filigree,bright_steel,dark,brass,mail,leather)
add_apex_legs(armature,steel,cobalt_filigree,bright_steel,dark,brass,mail,leather,blue_cloth)

# Armor is hidden in Blender by default so the base hero remains inspectable;
# the Godot equipment system reveals individual slot prefixes after import.
for obj in bpy.data.objects:
    if obj.name.startswith(PREFIX):
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False

bpy.ops.wm.save_as_mainfile(filepath=RIGGED)
counts={slot:len([o for o in bpy.data.objects if o.name.startswith(f"{PREFIX}{slot}_")]) for slot in ("head","chest","shoulders","hands","feet","pants")}
print("ROYAL_ARMOR_BUILT|%s|%s"%(RIGGED,counts))
