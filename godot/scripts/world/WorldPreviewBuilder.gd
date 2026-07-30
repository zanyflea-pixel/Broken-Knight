extends RefCounted

const MEADOW_GRASS_SCENE:PackedScene=preload("res://assets/vegetation/meadow_grass_clump.glb")
const REALISTIC_BROADLEAF_SCENE:PackedScene=preload("res://assets/vegetation/realistic_broadleaf_v1.glb")
const REALISTIC_BIRCH_SCENE:PackedScene=preload("res://assets/vegetation/realistic_birch_v1.glb")
const REALISTIC_MAPLE_SCENE:PackedScene=preload("res://assets/vegetation/realistic_maple_v1.glb")
const REALISTIC_PINE_SCENE:PackedScene=preload("res://assets/vegetation/realistic_pine_v1.glb")

var _architecture_textures: Dictionary = {}
var _shared_materials:Dictionary={}
var _broadleaf_canopy_mesh: ArrayMesh
var _leaf_litter_mesh:ArrayMesh
var _meadow_grass_patch_mesh:ArrayMesh
var _shrub_leaf_mesh:ArrayMesh
var _shrub_branch_mesh:ArrayMesh
var _realistic_tree_meshes:Dictionary={}
var _tree_species_mesh_cache:Dictionary={}
var _corridor_segment_buckets:Dictionary={}
const CORRIDOR_BUCKET_SIZE:=192.0

func populate(world_root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var profile_start_usec:=Time.get_ticks_usec()
    _prepare_corridor_spatial_cache(profile)
    var river_root: Node3D = world_root.get_node("RiverRoot")
    var road_root: Node3D = world_root.get_node("RoadRoot")
    var bridge_root: Node3D = world_root.get_node("BridgeRoot")
    var town_root: Node3D = world_root.get_node("TownRoot")
    var props_root: Node3D = world_root.get_node("PropsRoot")

    _clear_root(river_root)
    _clear_root(road_root)
    _clear_root(bridge_root)
    _clear_root(town_root)
    _clear_root(props_root)
    props_root.set_meta("harvestable_tree_registry",[])
    props_root.set_meta("collision_prop_registry",[])
    props_root.set_meta("mineable_rock_registry",[])
    town_root.set_meta("harvestable_tree_registry",[])
    _build_river_ribbons(river_root, profile.get("river_corridors", []), terrain_result, profile)
    _build_ponds(river_root, profile.get("pond_sites", []), terrain_result)
    _build_waterfalls(river_root, profile.get("waterfall_sites", []))
    _build_road_ribbons(road_root, profile.get("road_corridors", []), terrain_result, profile)
    _build_trail_ribbons(road_root, profile.get("trail_corridors", []), terrain_result)
    _build_road_junctions(road_root, profile.get("road_corridors", []), terrain_result)
    _build_roadside_props(road_root, profile, terrain_result)
    _build_wayfinding_landmarks(road_root, profile, terrain_result)
    _build_bridges(bridge_root, profile, terrain_result)
    _profile_preview_step("water_roads_bridges",profile_start_usec)
    _build_forests(props_root, profile, terrain_result)
    _profile_preview_step("forests",profile_start_usec)
    _build_biome_vegetation(props_root, profile, terrain_result)
    _profile_preview_step("biome_vegetation",profile_start_usec)
    _build_rocks(props_root, profile, terrain_result)
    _profile_preview_step("rocks",profile_start_usec)
    _build_grass(props_root, profile, terrain_result)
    _profile_preview_step("grass",profile_start_usec)
    _build_traversal_ground_cover(props_root, profile, terrain_result)
    _profile_preview_step("traversal_cover",profile_start_usec)
    _build_meadow_floor_detail(props_root,profile,terrain_result)
    _profile_preview_step("meadow_detail",profile_start_usec)
    _build_forest_leaf_litter(props_root,terrain_result)
    _profile_preview_step("leaf_litter",profile_start_usec)
    _build_bushes(props_root, profile, terrain_result)
    _profile_preview_step("ground_detail",profile_start_usec)
    # Wildflower stems are disabled until they have proper flower-head meshes;
    # bare colored sticks made the ground dressing less believable.
    # Thin box reeds read as green sticks, especially against moving water.
    # River vegetation returns later as proper cattail and leaf clusters.
    _build_fallen_logs(props_root, profile, terrain_result)
    _build_ground_stones(props_root, profile, terrain_result)
    _build_rock_formations(props_root, profile, terrain_result)
    _build_flower_meadows(props_root, profile, terrain_result)
    _build_flowering_shrubs(props_root,profile,terrain_result)
    _build_stone_landmarks(props_root, profile, terrain_result)
    _profile_preview_step("landmarks",profile_start_usec)
    _build_enterable_towns(town_root, profile, terrain_result)
    _build_town_outskirts(town_root, profile, terrain_result)
    _build_camps(town_root,profile,terrain_result)
    _build_world_landmarks(town_root,terrain_result)
    _profile_preview_step("towns",profile_start_usec)
    # Capture collision from visual-only town dressing before its box meshes
    # are replaced by render batches. This makes lamp posts, planters, market
    # furniture, arches and similar visible solids physical.
    _solidify_static_town_details(town_root)
    _batch_static_town_boxes(town_root)
    _profile_preview_step("batching",profile_start_usec)


func _profile_preview_step(label:String,start_usec:int)->void:
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")!="1":return
    print("WORLD_VISUAL_PROFILE|%s|elapsed_ms=%.1f"%[
        label,
        float(Time.get_ticks_usec()-start_usec)/1000.0,
    ])


func _batch_static_town_boxes(town_root:Node3D)->void:
    # Buildings and the castle are assembled from many box pieces so their
    # collision remains precise, but drawing every piece separately created
    # thousands of draw calls near Crownspire. Replace only their static visual
    # boxes with material-matched MultiMeshes; collision shapes stay untouched.
    var groups:Dictionary={}
    var materials:Dictionary={}
    var shadow_modes:Dictionary={}
    var candidates:Array[MeshInstance3D]=[]
    var stack:Array[Node]=[town_root]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if not node is MeshInstance3D:continue
        var mesh_instance:=node as MeshInstance3D
        if not mesh_instance.mesh is BoxMesh:continue
        var moving_ancestor:=false
        var ancestor:=mesh_instance.get_parent()
        while ancestor and ancestor!=town_root:
            if ancestor.get_script()!=null:
                moving_ancestor=true
                break
            var lower_name:=str(ancestor.name).to_lower()
            if ancestor.is_in_group("interactive_house_door") or "door" in lower_name or "gate" in lower_name or "hinge" in lower_name:
                moving_ancestor=true
                break
            ancestor=ancestor.get_parent()
        if moving_ancestor:continue
        var material:Material=mesh_instance.material_override
        if material==null:continue
        var box:=mesh_instance.mesh as BoxMesh
        var root_transform:=town_root.global_transform.affine_inverse()*mesh_instance.global_transform
        root_transform=root_transform*Transform3D(Basis.IDENTITY.scaled(box.size),Vector3.ZERO)
        var shadow_mode:=int(mesh_instance.cast_shadow)
        var key:="%d|%d"%[material.get_instance_id(),shadow_mode]
        if not groups.has(key):
            var new_group:Array[Transform3D]=[]
            groups[key]=new_group
        var group:Array[Transform3D]=groups[key]
        group.append(root_transform)
        materials[key]=material
        shadow_modes[key]=shadow_mode
        candidates.append(mesh_instance)
    for candidate in candidates:
        var parent:=candidate.get_parent()
        if parent:
            parent.remove_child(candidate)
            candidate.free()
    var unit_box:=BoxMesh.new();unit_box.size=Vector3.ONE
    for key in groups:
        var casts_shadows:=int(shadow_modes[key])!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var transforms:Array[Transform3D]=groups[key]
        # Towns are separated by kilometres, so 800 m cells still cull whole
        # settlements cleanly while halving the small material batches around
        # the capital. The old 260 m cells fragmented Crownspire into hundreds
        # of extra draw submissions.
        _add_material_multimesh(town_root,unit_box,transforms,materials[key],casts_shadows,1250.0,800.0)


func _solidify_static_town_details(town_root:Node3D)->void:
    var body:=StaticBody3D.new()
    body.name="TownDetailCollision"
    body.collision_layer=1
    town_root.add_child(body)
    var stack:Array[Node]=[town_root]
    var added:=0
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():
            if child!=body:stack.append(child)
        if not node is MeshInstance3D:continue
        var mesh_instance:=node as MeshInstance3D
        if mesh_instance.mesh==null or not mesh_instance.visible:continue
        if mesh_instance.get_meta("tree_component",false):continue
        if mesh_instance.get_meta("skip_static_solidify",false):continue
        var ancestor:Node=mesh_instance.get_parent()
        var already_solid:=false
        var dynamic_detail:=false
        while ancestor and ancestor!=town_root:
            if ancestor is CollisionObject3D:
                already_solid=true
                break
            var lower_name:=str(ancestor.name).to_lower()
            if ancestor.is_in_group("interactive_house_door") or "door" in lower_name or "gate" in lower_name or "hinge" in lower_name or "rotor" in lower_name:
                dynamic_detail=true
                break
            ancestor=ancestor.get_parent()
        if already_solid or dynamic_detail:continue
        var bounds:=mesh_instance.mesh.get_aabb()
        if bounds.size.length_squared()<.018:continue
        var collision:=CollisionShape3D.new()
        var shape:=BoxShape3D.new()
        shape.size=bounds.size
        collision.shape=shape
        var relative:=town_root.global_transform.affine_inverse()*mesh_instance.global_transform
        collision.transform=relative*Transform3D(Basis.IDENTITY,bounds.position+bounds.size*.5)
        body.add_child(collision)
        added+=1
    body.set_meta("detail_shape_count",added)


func _build_enterable_towns(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    for site in profile.get("town_sites", []):
        var hub := Node3D.new()
        hub.name = str(site.get("name", "Town"))
        root.add_child(hub)
        if site.get("capital", false):
            _build_capital_city(hub, site, terrain_result,profile.get("road_corridors",[]))
        else:
            _build_regional_town(hub, site, terrain_result,profile.get("road_corridors",[]))


func _build_town_outskirts(root:Node3D,profile:Dictionary,terrain_result:Dictionary)->void:
    var crop_mesh:=_make_ground_cover_mesh()
    var green_crops:Array[Transform3D]=[];var gold_crops:Array[Transform3D]=[]
    var fence_posts:Array[Transform3D]=[];var fence_rails:Array[Transform3D]=[]
    var post_mesh:=BoxMesh.new();post_mesh.size=Vector3(.24,1.45,.24)
    var rail_mesh:=BoxMesh.new();rail_mesh.size=Vector3.ONE
    var sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var world_size:float=profile.get("world_size",7200.0)
    for site in profile.get("town_sites",[]):
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:float=site.get("radius",140.0)
        var road_info:=_nearest_corridor_segment(center,profile.get("road_corridors",[]))
        if road_info.is_empty():continue
        var direction:Vector2=road_info.get("direction",Vector2(0,1)).normalized()
        var normal:=Vector2(-direction.y,direction.x)
        var road_width:float=road_info.get("width",15.0)
        var dry:=_is_dry_biome(center,world_size)

        # Trees frame the last stretch into greener settlements while keeping
        # the carriage lane and building doors completely open.
        if not dry or site.get("capital",false):
            for avenue_step in range(4):
                var along:float=-radius*.72+float(avenue_step)*radius*.13
                for side in [-1.0,1.0]:
                    var tree_point:=center+direction*along+normal*float(side)*(road_width*.72+8.0)
                    _add_tree(root,tree_point,terrain_result,.66+float(avenue_step%2)*.08)

        if site.get("capital",false):continue
        var field_length:=46.0;var field_width:=30.0
        for side in [-1.0,1.0]:
            var field_center:=center-direction*radius*.86+normal*float(side)*radius*.60
            for row in range(6):
                for column in range(13):
                    var point:=field_center+normal*(float(row)-2.5)*4.0+direction*(float(column)-6.0)*3.45
                    var ground:Vector3=sampler.call(point.x,point.y)
                    var scale_factor:=.72+float((row*5+column)%4)*.09
                    var basis:=Basis(Vector3.UP,float(row+column)*.37).scaled(Vector3(scale_factor*1.05,scale_factor*.85,scale_factor))
                    var transform:=Transform3D(basis,ground+Vector3.UP*.025)
                    if dry or (row+column)%4==0:gold_crops.append(transform)
                    else:green_crops.append(transform)

            var corners:=[
                field_center-direction*field_length*.5-normal*field_width*.5,
                field_center+direction*field_length*.5-normal*field_width*.5,
                field_center+direction*field_length*.5+normal*field_width*.5,
                field_center-direction*field_length*.5+normal*field_width*.5,
            ]
            for edge in range(4):
                var a:Vector2=corners[edge];var b:Vector2=corners[(edge+1)%4]
                var segment:=b-a;var length:=segment.length();var tangent:=segment/length
                var steps:=maxi(1,int(ceil(length/7.0)))
                for step in range(steps+1):
                    var p:=a.lerp(b,float(step)/float(steps));var ground:Vector3=sampler.call(p.x,p.y)
                    fence_posts.append(Transform3D(Basis.IDENTITY,ground+Vector3.UP*.725))
                # Build rails between each post instead of stretching one
                # horizontal beam across an entire uneven field edge. Every
                # rail now follows the terrain grade and actually reaches both
                # posts, eliminating the large floating/missing sections.
                for step in range(steps):
                    var rail_a2:=a.lerp(b,float(step)/float(steps))
                    var rail_b2:=a.lerp(b,float(step+1)/float(steps))
                    var rail_a_ground:Vector3=sampler.call(rail_a2.x,rail_a2.y)
                    var rail_b_ground:Vector3=sampler.call(rail_b2.x,rail_b2.y)
                    for rail_height in [.48,1.02]:
                        var rail_a:=rail_a_ground+Vector3.UP*float(rail_height)
                        var rail_b:=rail_b_ground+Vector3.UP*float(rail_height)
                        var rail_delta:=rail_b-rail_a
                        var x_axis:=rail_delta.normalized()
                        var z_axis:=x_axis.cross(Vector3.UP).normalized()
                        var y_axis:=z_axis.cross(x_axis).normalized()
                        var rail_basis:=Basis(x_axis,y_axis,z_axis)
                        rail_basis.x*=rail_delta.length()+.10;rail_basis.y*=.13;rail_basis.z*=.13
                        fence_rails.append(Transform3D(rail_basis,(rail_a+rail_b)*.5))
                    # The fence is one obstacle from ground to top rail. Using
                    # the same short segments as the visuals follows uneven
                    # fields without creating long floating collision walls.
                    var horizontal_delta:=Vector2(rail_b_ground.x-rail_a_ground.x,rail_b_ground.z-rail_a_ground.z)
                    var collision_yaw:=-atan2(horizontal_delta.y,horizontal_delta.x)
                    _add_static_collision_box(
                        root,
                        Vector3(horizontal_delta.length()+.18,1.38,.30),
                        (rail_a_ground+rail_b_ground)*.5+Vector3.UP*.69,
                        Vector3(0,collision_yaw,0)
                    )
    _add_ground_cover_batch(root,crop_mesh,green_crops,Color(.28,.43,.13,1))
    _add_ground_cover_batch(root,crop_mesh,gold_crops,Color(.54,.43,.13,1))
    _add_multimesh_batch(root,post_mesh,fence_posts,Color(.38,.25,.12,1),false)
    _add_multimesh_batch(root,rail_mesh,fence_rails,Color(.34,.21,.10,1),false)


func _build_world_landmarks(root:Node3D,terrain_result:Dictionary)->void:
    _add_highfield_windmill(root,Vector2(-435.0,1590.0),terrain_result)
    _add_ruined_hill_fort(root,Vector2(-1700.0,1720.0),terrain_result)
    _add_roadside_shrine(root,Vector2(-1337.0,-128.0),-.95,terrain_result)
    _add_roadside_shrine(root,Vector2(1168.0,545.0),.42,terrain_result)
    _add_roadside_shrine(root,Vector2(838.0,-878.0),2.62,terrain_result)


func _add_ruined_hill_fort(root:Node3D,center:Vector2,terrain_result:Dictionary)->void:
    var ruin:=Node3D.new();ruin.name="Greywatch Ruins";ruin.set_meta("batch_static_collision",true);root.add_child(ruin)
    var stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.55,.56,.52),1.0,4.0)
    var dark_stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.34,.37,.36),1.0,3.0)
    var radius:=31.0
    # Broken curtain walls follow the hill instead of sitting on a single
    # artificial platform. Deliberate gaps make the ruin explorable.
    for i in range(16):
        if i in [0,1,6,11,12]:continue
        var angle:=float(i)*TAU/16.0
        var point:=center+Vector2(cos(angle),sin(angle))*radius
        var ground:Vector3=terrain_result.height_sampler.call(point.x,point.y)
        var height:=5.2+float((i*7)%5)*.85
        _solid_box_euler(ruin,Vector3(12.4,height,3.0),ground+Vector3.UP*height*.5,Vector3(0,-angle-PI*.5,0),stone)
    # A proper open gate on the east side gives the player an obvious route in.
    var gate:=center+Vector2(radius,0)
    for z_offset in [-5.2,5.2]:
        var pillar_ground:Vector3=terrain_result.height_sampler.call(gate.x,gate.y+z_offset)
        _solid_box(ruin,Vector3(3.4,9.0,3.4),pillar_ground+Vector3.UP*4.5,dark_stone)
    var gate_ground:Vector3=terrain_result.height_sampler.call(gate.x,gate.y)
    _solid_box(ruin,Vector3(3.5,2.2,13.8),gate_ground+Vector3.UP*9.0,dark_stone)
    # Remnants of the inner hall create layered silhouettes and useful cover.
    var hall_ground:Vector3=terrain_result.height_sampler.call(center.x-4.0,center.y)
    _solid_box(ruin,Vector3(18.0,1.0,14.0),hall_ground+Vector3.UP*.5,dark_stone)
    _solid_box(ruin,Vector3(18.0,8.5,2.2),hall_ground+Vector3(0,4.25,6.0),stone)
    _solid_box(ruin,Vector3(2.2,5.6,12.0),hall_ground+Vector3(-8.0,2.8,0),stone)
    _solid_box(ruin,Vector3(5.5,11.5,5.5),hall_ground+Vector3(-18.0,5.75,-17.0),dark_stone)
    _add_battlements(ruin,hall_ground+Vector3(-18.0,12.0,-17.0),5.5,5.5,stone)
    # A restrained rune stone rewards reaching the center without turning the
    # entire landmark into glowing fantasy clutter.
    _solid_box(ruin,Vector3(2.2,6.8,1.7),hall_ground+Vector3(4.0,3.9,-1.0),dark_stone)
    var rune_mat:=_make_lit_window_material(Color(.18,.50,.72))
    for rune_y in [2.3,3.6,4.9]:
        _visual_box(ruin,Vector3(.72,.17,.10),hall_ground+Vector3(4.0,rune_y,-1.90),rune_mat)
    var rune_light:=OmniLight3D.new();rune_light.position=hall_ground+Vector3(4.0,3.6,-2.2);rune_light.light_color=Color(.16,.48,.72);rune_light.light_energy=.34;rune_light.omni_range=5.5;rune_light.shadow_enabled=false;ruin.add_child(rune_light)


func _add_highfield_windmill(root:Node3D,point:Vector2,terrain_result:Dictionary)->void:
    var ground:Vector3=terrain_result.height_sampler.call(point.x,point.y)
    var mill:=Node3D.new();mill.name="Highfield Windmill";mill.position=ground;mill.set_meta("batch_static_collision",true);root.add_child(mill)
    var plaster:=_make_texture_material("res://assets/architecture/aged_plaster_v1.png",Color(.69,.61,.47),1.0,3.0)
    var timber:=_make_texture_material("res://assets/architecture/dark_oak_v1.png",Color(.62,.47,.31),1.0,2.0)
    var stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.72,.72,.67),1.0,3.0)
    var sail:=_make_texture_material("res://assets/architecture/aged_plaster_v1.png",Color(.72,.67,.54),1.0,2.0)
    # Build the mill as four walls rather than one solid box so its front
    # window and doorway are genuine openings instead of bright decals.
    _build_keep_wall_with_openings(mill,Vector3.ZERO,4.75,9.5,13.0,.48,[],plaster)
    _build_keep_wall_with_openings(
        mill,Vector3.ZERO,-4.75,9.5,13.0,.48,
        [
            {"x0":-.68,"x1":.68,"y0":7.22,"y1":8.78},
            {"x0":-1.1,"x1":1.1,"y0":0.0,"y1":3.35},
        ],plaster
    )
    for side in [-1.0,1.0]:
        var mill_side:=Node3D.new();mill_side.position=Vector3(4.75*side,0,0);mill_side.rotation.y=PI*.5;mill.add_child(mill_side)
        _build_keep_wall_with_openings(mill_side,Vector3.ZERO,0.0,9.5,13.0,.48,[],plaster)
    _visual_box(mill,Vector3(10.0,1.1,10.0),Vector3(0,.55,0),stone)
    for x in [-4.1,4.1]:
        _visual_box(mill,Vector3(.42,13.2,.38),Vector3(x,6.6,-4.82),timber)
    for y in [3.8,8.0,12.1]:
        _visual_box(mill,Vector3(8.7,.36,.38),Vector3(0,y,-4.82),timber)
    _visual_box(mill,Vector3(2.2,3.3,.28),Vector3(0,1.7,-4.86),timber)
    var roof_mesh:=CylinderMesh.new();roof_mesh.top_radius=0.0;roof_mesh.bottom_radius=6.4;roof_mesh.height=5.0;roof_mesh.radial_segments=12
    var roof:=MeshInstance3D.new();roof.mesh=roof_mesh;roof.position=Vector3(0,15.5,0);roof.material_override=timber;mill.add_child(roof)
    var axle_mesh:=CylinderMesh.new();axle_mesh.top_radius=.48;axle_mesh.bottom_radius=.48;axle_mesh.height=1.3;axle_mesh.radial_segments=10
    var axle:=MeshInstance3D.new();axle.mesh=axle_mesh;axle.position=Vector3(0,11.2,-5.25);axle.rotation.x=PI*.5;axle.material_override=timber;mill.add_child(axle)
    var rotor:=Node3D.new();rotor.name="Windmill Rotor";rotor.position=Vector3(0,11.2,-5.52)
    rotor.set_script(load("res://scripts/world/WindmillRotor.gd"));mill.add_child(rotor)
    for blade_index in range(4):
        var angle:=PI*.25+float(blade_index)*PI*.5
        var arm:=Node3D.new();arm.rotation.z=angle;rotor.add_child(arm)
        _visual_box(arm,Vector3(.42,8.2,.22),Vector3(0,4.0,0),timber)
        _visual_box(arm,Vector3(1.55,5.8,.15),Vector3(.74,5.0,-.06),sail)


func _add_roadside_shrine(root:Node3D,point:Vector2,yaw:float,terrain_result:Dictionary)->void:
    var ground:Vector3=terrain_result.height_sampler.call(point.x,point.y)
    var shrine:=Node3D.new();shrine.name="Roadside Shrine";shrine.position=ground;shrine.rotation.y=yaw;shrine.set_meta("batch_static_collision",true);root.add_child(shrine)
    var stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.66,.65,.59),1.0,3.0)
    var dark:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.46,.47,.44),1.0,3.0)
    _solid_box(shrine,Vector3(5.0,.55,3.8),Vector3(0,.28,0),stone)
    _solid_box(shrine,Vector3(3.8,4.25,.55),Vector3(0,2.4,.68),stone)
    for x in [-1.72,1.72]:
        _solid_box(shrine,Vector3(.48,3.75,.48),Vector3(x,2.2,-.48),dark)
    var canopy_mesh:=CylinderMesh.new();canopy_mesh.top_radius=0.0;canopy_mesh.bottom_radius=3.15;canopy_mesh.height=2.0;canopy_mesh.radial_segments=4
    var canopy:=MeshInstance3D.new();canopy.mesh=canopy_mesh;canopy.position=Vector3(0,5.45,.05);canopy.rotation.y=PI*.25;canopy.material_override=dark;shrine.add_child(canopy)
    # A recessed icon and warm votive make the landmark read as a shrine from
    # the road without adding another UI marker.
    _visual_box(shrine,Vector3(1.5,2.35,.16),Vector3(0,2.55,.35),dark)
    _visual_box(shrine,Vector3(.55,1.35,.18),Vector3(0,2.65,.22),stone)
    _visual_box(shrine,Vector3(1.25,.30,.18),Vector3(0,2.95,.20),stone)
    _visual_box(shrine,Vector3(.28,.55,.22),Vector3(0,1.25,-.30),_make_lit_window_material(Color(.96,.58,.20)))


func _build_regional_town(root: Node3D, site: Dictionary, terrain_result: Dictionary,roads:Array) -> void:
    var center: Vector2 = site.get("position", Vector2.ZERO)
    var radius: float = site.get("radius", 135.0)
    _add_market_square(root, center, terrain_result, 1.15)
    var house_count := 14
    var occupied:Array[Dictionary]=[]
    for i in range(house_count):
        var ring := radius * (0.37 if i < 7 else 0.62)
        var angle := float(i % 7) * TAU / 7.0 + (0.18 if i < 7 else 0.55)
        var point := center + Vector2(cos(angle), sin(angle)) * ring
        var house_width:=10.0+float(i%3)*1.8
        var house_depth:=8.5+float((i+1)%2)*2.0
        point=_clear_house_from_roads(point,maxf(house_width,house_depth)*.55,roads)
        point=_separate_house_plot(point,maxf(house_width,house_depth)*.62,occupied,center)
        occupied.append({"position":point,"radius":maxf(house_width,house_depth)*.62})
        var ground: Vector3 = terrain_result.height_sampler.call(point.x, point.y)
        _add_enterable_house(root, ground, angle + PI,house_width,house_depth, 6.6 + float(i % 4) * 0.55, i)
    # A larger inn anchors each settlement and breaks the repeated-house look.
    var inn_point := center + Vector2(radius * 0.18, radius * 0.28)
    inn_point=_clear_house_from_roads(inn_point,10.0,roads)
    inn_point=_separate_house_plot(inn_point,10.0,occupied,center)
    _add_enterable_house(root, terrain_result.height_sampler.call(inn_point.x, inn_point.y), PI, 18.0, 12.0, 8.4, 20)
    _add_town_well(root, center + Vector2(-34.0, 4.0), terrain_result)
    _add_town_boundary(root, center, radius * 0.78, terrain_result)
    _add_town_name_marker(root, str(site.get("name", "Town")), center + Vector2(0, radius * 0.70), terrain_result)


func _build_capital_city(root: Node3D, site: Dictionary, terrain_result: Dictionary,roads:Array) -> void:
    var center: Vector2 = site.get("position", Vector2.ZERO)
    var radius: float = site.get("radius", 265.0)
    var ground: Vector3 = terrain_result.height_sampler.call(center.x, center.y)
    var paving := _make_texture_material("res://assets/architecture/town_cobblestone_v1.png", Color(0.82, 0.82, 0.78), 1.0, 18.0)
    # Main north-south boulevard and east-west market street.
    # Stop the boulevard before the castle courtyard instead of layering two
    # almost-coplanar textured surfaces beneath the keep.
    _solid_box(root, Vector3(18.0, 0.16, 200.0), ground + Vector3(0, 0.12, 68), paving)
    # A terrain-following gate apron guarantees the highway, wall opening and
    # internal boulevard meet without the flat slab becoming buried on the
    # sloped approach.
    var gate_apron_points:Array=_subdivide_polyline([
        center+Vector2(0,260),
        center+Vector2(0,120),
    ],5)
    var gate_apron_mesh:=_build_corridor_ribbon_mesh(
        gate_apron_points,
        terrain_result.get("terrain_height_sampler",terrain_result.height_sampler),
        18.0,0.0,.18,false,[],true
    )
    var gate_apron:=MeshInstance3D.new()
    gate_apron.name="CrownspireGateApron"
    gate_apron.mesh=gate_apron_mesh
    gate_apron.material_override=paving
    gate_apron.set_meta("skip_static_solidify",true)
    root.add_child(gate_apron)
    _solid_box(root, Vector3(250.0, 0.16, 14.0), ground + Vector3(0, 0.28, 28), paving)
    _add_city_walls(root, center, 190.0, terrain_result)
    _add_market_square(root, center + Vector2(0, 38), terrain_result, 1.65, false)
    _build_capital_street_furniture(root,center,terrain_result)
    _build_capital_civic_architecture(root,center,terrain_result)

    # Four distinct residential and trade quarters with irregular footprints.
    var plots := [
        Vector2(-118, -15), Vector2(-82, -20), Vector2(-120, 48), Vector2(-80, 66),
        Vector2(82, -18), Vector2(122, -8), Vector2(82, 55), Vector2(124, 72),
        Vector2(-132, 118), Vector2(-88, 132), Vector2(-45, 115),
        Vector2(46, 118), Vector2(88, 136), Vector2(132, 116),
        Vector2(-145, -88), Vector2(-110, -118), Vector2(112, -112), Vector2(148, -82)
    ]
    var occupied:Array[Dictionary]=[]
    for i in range(plots.size()):
        var point: Vector2 = center + plots[i]
        var house_width:=12.0+float(i%4)*2.2
        var house_depth:=9.5+float(i%3)
        point=_clear_house_from_roads(point,maxf(house_width,house_depth)*.55,roads)
        point=_separate_house_plot(point,maxf(house_width,house_depth)*.62,occupied,center)
        occupied.append({"position":point,"radius":maxf(house_width,house_depth)*.62})
        var yaw := atan2(-plots[i].x, -plots[i].y)
        _add_enterable_house(root, terrain_result.height_sampler.call(point.x, point.y), yaw,house_width,house_depth, 7.2 + float(i % 5) * 0.75, i)

    _build_castle_complex(root, center + Vector2(0, -92), terrain_result)
    var city_sign := Label3D.new()
    city_sign.text = "CROWNSPIRE\nROYAL CAPITAL"
    city_sign.position = ground + Vector3(0, 11.0, 178.0)
    city_sign.font_size = 64
    city_sign.modulate = Color(0.95, 0.79, 0.33)
    city_sign.outline_size = 12
    city_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    city_sign.visibility_range_end=620.0
    city_sign.visibility_range_end_margin=70.0
    city_sign.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    root.add_child(city_sign)


func _build_capital_civic_architecture(root:Node3D,center:Vector2,terrain_result:Dictionary)->void:
    var ground:Vector3=terrain_result.height_sampler.call(center.x,center.y)
    var stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.72,.73,.70),1.0,3.0)
    var gold:=_make_material(Color(.70,.48,.10),.82);var hedge:=_make_foliage_material(Color(.13,.31,.10))
    # Two broad civic arches now sit directly on the east-west market road.
    # The former rows were offset from every travel lane and looked stranded.
    for side in [-1.0,1.0]:
        var arch_root:=Node3D.new()
        arch_root.position=ground+Vector3(side*61.0,0,28.0)
        arch_root.rotation.y=PI*.5
        root.add_child(arch_root)
        var arch_center:=Vector3(0,5.5,0)
        _add_arch_crown(arch_root,arch_center,6.4,1.2,stone)
        _solid_box(arch_root,Vector3(1.25,7.0,1.4),arch_center+Vector3(-6.4,-2.0,0),stone)
        _solid_box(arch_root,Vector3(1.25,7.0,1.4),arch_center+Vector3(6.4,-2.0,0),stone)
    # Formal planted courts soften the stone without using green sticks.
    for x in [-52.0,52.0]:
        for z in [8.0,32.0,56.0,80.0]:
            _visual_box(root,Vector3(8.0,.55,4.8),ground+Vector3(x,.32,z),stone)
            _add_static_collision_box(root,Vector3(8.0,.8,4.8),ground+Vector3(x,.40,z))
            var shrub:=MeshInstance3D.new();shrub.mesh=_get_broadleaf_canopy_mesh();shrub.position=ground+Vector3(x,1.25,z);shrub.scale=Vector3(2.8,.75,1.6);shrub.material_override=hedge;root.add_child(shrub)
    # A raised royal fountain/statue anchors the crossing of the main streets.
    var basin:=MeshInstance3D.new();var basin_mesh:=CylinderMesh.new();basin_mesh.top_radius=5.0;basin_mesh.bottom_radius=5.5;basin_mesh.height=.75;basin_mesh.radial_segments=18;basin.mesh=basin_mesh;basin.position=ground+Vector3(0,.50,28);basin.material_override=stone;root.add_child(basin)
    _visual_box(root,Vector3(1.2,7.0,1.2),ground+Vector3(0,4.0,28),stone)
    _add_castle_spire(root,ground+Vector3(0,7.2,28),1.5,3.8,gold,gold)


func _build_capital_street_furniture(root:Node3D,center:Vector2,terrain_result:Dictionary)->void:
    var sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var timber:=_make_texture_material("res://assets/architecture/dark_oak_v1.png",Color(.62,.48,.32),1.0,2.0)
    var iron:=_make_material(Color(.16,.17,.17),.82)
    var lantern:=_make_lit_window_material(Color(1.0,.54,.16))
    var royal:=_make_material(Color(.46,.055,.05),.95)
    var gold:=_make_material(Color(.72,.50,.10),.78)
    var post_mesh:=BoxMesh.new();post_mesh.size=Vector3(.22,3.6,.22)
    var lantern_mesh:=BoxMesh.new();lantern_mesh.size=Vector3(.58,.72,.58)
    var seat_mesh:=BoxMesh.new();seat_mesh.size=Vector3(3.2,.24,.72)
    var back_mesh:=BoxMesh.new();back_mesh.size=Vector3(3.2,1.0,.18)
    var posts:Array[Transform3D]=[];var lanterns:Array[Transform3D]=[];var seats:Array[Transform3D]=[];var backs:Array[Transform3D]=[]
    for z_offset in [82.0,106.0,130.0,154.0]:
        for side in [-1.0,1.0]:
            var p:=center+Vector2(14.5*float(side),z_offset);var ground:Vector3=sampler.call(p.x,p.y)
            posts.append(Transform3D(Basis.IDENTITY,ground+Vector3.UP*1.8))
            lanterns.append(Transform3D(Basis.IDENTITY,ground+Vector3.UP*3.78))
            _add_static_collision_box(root,Vector3(.44,3.65,.44),ground+Vector3.UP*1.825)
        if int(z_offset)%48!=0:
            for side in [-1.0,1.0]:
                var bench2:=center+Vector2(25.0*float(side),z_offset+8.0);var bench_ground:Vector3=sampler.call(bench2.x,bench2.y)
                var yaw:=0.0 if side<0.0 else PI
                seats.append(Transform3D(Basis(Vector3.UP,yaw),bench_ground+Vector3.UP*.62))
                backs.append(Transform3D(Basis(Vector3.UP,yaw),bench_ground+Vector3(0,1.08,-.36*float(side))))
                _add_static_collision_box(root,Vector3(3.2,1.25,.78),bench_ground+Vector3.UP*.63,Vector3(0,yaw,0))
    _add_material_multimesh(root,post_mesh,posts,iron,false)
    _add_material_multimesh(root,lantern_mesh,lanterns,lantern,false)
    _add_material_multimesh(root,seat_mesh,seats,timber,false)
    _add_material_multimesh(root,back_mesh,backs,timber,false)

    # Tall standards turn the southern gate into a recognizable capital entry.
    var gate_ground:Vector3=sampler.call(center.x,center.y+184.0)
    for side in [-1.0,1.0]:
        var x:=19.0*float(side)
        _visual_box(root,Vector3(.28,8.5,.28),gate_ground+Vector3(x,4.25,0),iron)
        var banner_center:=gate_ground+Vector3(x-1.65*float(side),6.0,-.12)
        _visual_box(root,Vector3(3.2,4.6,.18),banner_center,royal)
        _add_broken_crown_crest(root,banner_center+Vector3(0,0,-.13),.86,gold)
        _visual_box(root,Vector3(.22,4.9,.24),gate_ground+Vector3(x,6.0,-.18),gold)


func _add_broken_crown_crest(root:Node3D,center:Vector3,scale_factor:float,gold:Material)->void:
    var river:=_make_material(Color(.68,.78,.84),.34)
    var crest_base:=_visual_box(root,Vector3(1.50,.16,.07)*scale_factor,center+Vector3(0,.46,0),gold)
    crest_base.name="BrokenCrownCrest"
    _visual_box(root,Vector3(.20,.74,.075)*scale_factor,center+Vector3(-.52,.74,0),gold).rotation.z=-.15
    _visual_box(root,Vector3(.20,.74,.075)*scale_factor,center+Vector3(.52,.74,0),gold).rotation.z=.15
    _visual_box(root,Vector3(.18,.50,.075)*scale_factor,center+Vector3(-.08,.82,0),gold).rotation.z=-.07
    _visual_box(root,Vector3(.95,.15,.078)*scale_factor,center+Vector3(-.30,-.42,0),river).rotation.z=.28
    _visual_box(root,Vector3(.95,.15,.078)*scale_factor,center+Vector3(.30,-.42,0),river).rotation.z=-.28


func _add_city_walls(root: Node3D, center: Vector2, half_extent: float, terrain_result: Dictionary) -> void:
    var wall_mat := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(1.08, 1.10, 1.10), 1.0, 7.0)
    var tower_mat := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(0.84, 0.87, 0.89), 1.0, 5.0)
    var center_ground: Vector3 = terrain_result.height_sampler.call(center.x, center.y)
    var segment_length := 32.0
    for side in [-1.0, 1.0]:
        for i in range(-5, 6):
            var x := float(i) * segment_length
            if not (side > 0.0 and i == 0):
                _solid_box(root, Vector3(segment_length, 8.0, 3.2), center_ground + Vector3(x, 4.0, half_extent * side), wall_mat)
    # East and west curtain walls.
    for side in [-1.0, 1.0]:
        for i in range(-5, 6):
            var z := float(i) * segment_length
            _solid_box(root, Vector3(3.2, 8.0, segment_length), center_ground + Vector3(half_extent * side, 4.0, z), wall_mat)
    # A supported south gate replaces the overlapping duplicate wall pieces
    # that shimmered and left the lintel visibly floating.
    _solid_box(root, Vector3(6.0, 8.0, 4.0), center_ground + Vector3(-12.5, 4.0, half_extent), tower_mat)
    _solid_box(root, Vector3(6.0, 8.0, 4.0), center_ground + Vector3(12.5, 4.0, half_extent), tower_mat)
    _solid_box(root, Vector3(19.0, 3.0, 4.0), center_ground + Vector3(0, 9.5, half_extent), wall_mat)
    for corner in [Vector2(-half_extent, -half_extent), Vector2(half_extent, -half_extent), Vector2(-half_extent, half_extent), Vector2(half_extent, half_extent)]:
        _solid_box(root, Vector3(13.0, 15.0, 13.0), center_ground + Vector3(corner.x, 7.5, corner.y), tower_mat)
        _add_battlements(root, center_ground + Vector3(corner.x, 15.3, corner.y), 13.0, 13.0, wall_mat)


func _add_town_boundary(root: Node3D, center: Vector2, radius: float, terrain_result: Dictionary) -> void:
    var timber := _make_texture_material("res://assets/architecture/dark_oak_v1.png", Color(0.68, 0.58, 0.46), 0.98, 2.0)
    var segments:=48
    var segment_length:=TAU*radius/float(segments)
    for i in range(segments):
        # Four deliberate gates keep roads and walking routes usable; every
        # other palisade section overlaps its neighbours slightly.
        if i % 12 == 0:
            continue
        var angle := float(i) * TAU / float(segments)
        var p2 := center + Vector2(cos(angle), sin(angle)) * radius
        var p3: Vector3 = terrain_result.height_sampler.call(p2.x, p2.y)
        _visual_box(root, Vector3(0.32, 2.2, segment_length+.45), p3 + Vector3(0, 1.1, 0), timber).rotation.y = -angle


func _add_market_square(root: Node3D, center: Vector2, terrain_result: Dictionary, scale_factor: float = 1.0, draw_plaza:bool=true) -> void:
    var ground: Vector3 = terrain_result.height_sampler.call(center.x, center.y)
    var plaza_mesh := CylinderMesh.new()
    plaza_mesh.top_radius = 24.0 * scale_factor
    plaza_mesh.bottom_radius = 25.0 * scale_factor
    plaza_mesh.height = 0.18
    if draw_plaza:
        var plaza := MeshInstance3D.new()
        plaza.mesh = plaza_mesh
        plaza.position = ground + Vector3.UP * 0.08
        plaza.material_override = _make_texture_material("res://assets/architecture/town_cobblestone_v1.png", Color(0.86, 0.82, 0.74), 1.0, 11.0)
        root.add_child(plaza)
        plaza.create_trimesh_collision()
    for i in range(6):
        var angle := float(i) * TAU / 6.0
        var local := Vector3(cos(angle) * 17.0 * scale_factor, 0, sin(angle) * 17.0 * scale_factor)
        var stall := Node3D.new()
        stall.set_meta("batch_static_collision",true)
        stall.position = ground + local
        stall.rotation.y = -angle
        root.add_child(stall)
        var stall_wood := _make_texture_material("res://assets/architecture/dark_oak_v1.png", Color(0.78, 0.61, 0.43), 0.96, 2.0)
        _solid_box(stall, Vector3(5.4, 0.20, 3.2), Vector3(0, 0.75, 0), stall_wood)
        for x in [-2.35, 2.35]:
            _solid_box(stall, Vector3(0.16, 2.7, 0.16), Vector3(x, 1.35, 0), stall_wood)
        var canopy_color := Color(0.56, 0.12, 0.08) if i % 3 == 0 else (Color(0.10, 0.27, 0.50) if i % 3 == 1 else Color(0.52, 0.39, 0.09))
        _visual_box(stall, Vector3(5.8, 0.22, 3.6), Vector3(0, 2.65, 0), _make_material(canopy_color, 0.90))
    for i in range(4):
        var angle := float(i) * TAU / 4.0 + PI * 0.25
        var lamp := Node3D.new()
        lamp.position = ground + Vector3(cos(angle) * 25.0 * scale_factor, 0, sin(angle) * 25.0 * scale_factor)
        root.add_child(lamp)
        _visual_box(lamp, Vector3(0.18, 3.4, 0.18), Vector3(0, 1.7, 0), _make_material(Color(0.14, 0.08, 0.03), 1.0))
        var light := OmniLight3D.new()
        light.position = Vector3(0, 3.15, 0)
        light.light_color = Color(1.0, 0.58, 0.22)
        light.light_energy = 0.0
        light.omni_range = 10.0
        light.visible = false
        light.add_to_group("town_torches")
        lamp.add_child(light)
    _add_market_dressing(root, ground, scale_factor)


func _add_market_dressing(root: Node3D, ground: Vector3, scale_factor: float) -> void:
    var timber := _make_texture_material("res://assets/architecture/dark_oak_v1.png", Color(0.76, 0.59, 0.40), 1.0, 2.0)
    var iron := _make_material(Color(0.16, 0.17, 0.17), 0.72)
    var sack := _make_texture_material("res://assets/architecture/aged_plaster_v1.png", Color(0.68, 0.56, 0.39), 1.0, 2.0)
    # Cargo clusters fill dead corners while leaving the central walking route open.
    for i in range(8):
        var angle := float(i) * TAU / 8.0 + 0.25
        var distance := (20.5 + float(i % 2) * 3.0) * scale_factor
        var p := ground + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
        _visual_box(root, Vector3(1.15, 0.90, 1.05), p + Vector3(0, 0.45, 0), timber).rotation.y = angle
        if i % 2 == 0:
            _visual_box(root, Vector3(0.72, 0.62, 0.82), p + Vector3(0.72, 0.31, 0.12), sack).rotation.y = -angle
            _add_static_collision_box(root,Vector3(.72,.62,.82),p+Vector3(.72,.31,.12),Vector3(0,-angle,0))
        _add_static_collision_box(root,Vector3(1.15,.90,1.05),p+Vector3(0,.45,0),Vector3(0,angle,0))
    # A compact two-wheel merchant cart forms a strong market silhouette.
    var cart := Node3D.new()
    cart.position = ground + Vector3(27.0 * scale_factor, 0, -9.0 * scale_factor)
    cart.rotation.y = -0.45
    root.add_child(cart)
    _solid_box(cart, Vector3(4.8, 0.45, 2.6), Vector3(0, 1.35, 0), timber)
    _visual_box(cart, Vector3(0.28, 0.28, 5.5), Vector3(0, 1.15, 3.4), timber)
    for x in [-2.25, 2.25]:
        var wheel_mesh := CylinderMesh.new()
        wheel_mesh.top_radius = 1.05
        wheel_mesh.bottom_radius = 1.05
        wheel_mesh.height = 0.30
        wheel_mesh.radial_segments = 16
        var wheel := MeshInstance3D.new()
        wheel.mesh = wheel_mesh
        wheel.position = Vector3(x, 1.0, 0)
        wheel.rotation.z = PI * 0.5
        wheel.material_override = iron
        cart.add_child(wheel)


func _add_town_name_marker(root: Node3D, town_name: String, point: Vector2, terrain_result: Dictionary) -> void:
    var ground: Vector3 = terrain_result.height_sampler.call(point.x, point.y)
    var marker := Label3D.new()
    marker.text = town_name.to_upper()
    marker.position = ground + Vector3.UP * 5.6
    marker.font_size = 52
    marker.modulate = Color(0.94, 0.77, 0.34)
    marker.outline_size = 10
    marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    marker.visibility_range_end=520.0
    marker.visibility_range_end_margin=60.0
    marker.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    root.add_child(marker)


func _add_town_well(root: Node3D, center: Vector2, terrain_result: Dictionary) -> void:
    var ground: Vector3 = terrain_result.height_sampler.call(center.x, center.y)
    var stone := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(0.92, 0.91, 0.86), 1.0, 3.0)
    var timber := _make_texture_material("res://assets/architecture/dark_oak_v1.png", Color(0.68, 0.56, 0.42), 1.0, 2.0)
    var roof := _make_texture_material("res://assets/architecture/clay_roof_v1.png", Color(0.85, 0.62, 0.52), 0.98, 2.0)
    var ring_mesh := CylinderMesh.new()
    ring_mesh.top_radius = 2.6
    ring_mesh.bottom_radius = 2.9
    ring_mesh.height = 1.25
    ring_mesh.radial_segments = 20
    var ring := MeshInstance3D.new()
    ring.mesh = ring_mesh
    ring.position = ground + Vector3(0, 0.63, 0)
    ring.material_override = stone
    root.add_child(ring)
    var well_body:=StaticBody3D.new();well_body.position=ground+Vector3(0,.63,0);well_body.collision_layer=1;root.add_child(well_body)
    var well_collision:=CollisionShape3D.new();var well_shape:=CylinderShape3D.new();well_shape.radius=2.8;well_shape.height=1.25;well_collision.shape=well_shape;well_body.add_child(well_collision)
    for x in [-2.4, 2.4]:
        _visual_box(root, Vector3(0.30, 4.7, 0.30), ground + Vector3(x, 2.35, 0), timber)
    _visual_box(root, Vector3(5.8, 0.38, 4.4), ground + Vector3(0, 4.75, 0), roof).rotation.z = 0.08
    _visual_box(root, Vector3(0.24, 0.24, 5.2), ground + Vector3(0, 3.35, 0), timber)


func _add_enterable_house(root: Node3D, ground: Vector3, yaw: float, width: float, depth: float, height: float, style: int = 0) -> void:
    var house := Node3D.new()
    house.set_meta("batch_static_collision",true)
    house.position = ground
    house.rotation.y = yaw
    root.add_child(house)
    var plaster_colors := [Color(0.68, 0.55, 0.39), Color(0.62, 0.52, 0.42), Color(0.74, 0.66, 0.51), Color(0.55, 0.48, 0.39)]
    var wall_mat := _make_texture_material("res://assets/architecture/aged_plaster_v1.png", plaster_colors[style % plaster_colors.size()], 0.98, 2.5)
    var beam_mat := _make_texture_material("res://assets/architecture/dark_oak_v1.png", Color(0.62, 0.48, 0.34), 1.0, 2.0)
    var roof_colors := [Color(0.31, 0.09, 0.055), Color(0.24, 0.16, 0.09), Color(0.18, 0.20, 0.17)]
    var roof_mat := _make_texture_material("res://assets/architecture/clay_roof_v1.png", roof_colors[style % roof_colors.size()] * 1.8, 0.96, 3.0)
    var thick := 0.45
    var door_w := 2.2
    var door_h := 3.1
    var rear_openings:Array[Dictionary]=[]
    for x in [-width*.27,width*.27]:
        rear_openings.append({"x0":x-.68,"x1":x+.68,"y0":height*.54-.72,"y1":height*.54+.72})
    _build_keep_wall_with_openings(house,Vector3.ZERO,-depth*.5,width,height,thick,rear_openings,wall_mat)
    for side in [-1.0,1.0]:
        var side_wall:=Node3D.new()
        side_wall.position=Vector3(width*.5*side,0,0)
        side_wall.rotation.y=PI*.5
        house.add_child(side_wall)
        var side_openings:Array[Dictionary]=[{"x0":-depth*.16-.68,"x1":-depth*.16+.68,"y0":height*.54-.68,"y1":height*.54+.68}]
        _build_keep_wall_with_openings(side_wall,Vector3.ZERO,0.0,depth,height,thick,side_openings,wall_mat)
    var side_w := (width - door_w) * 0.5
    var window_w:=1.45;var window_h:=1.55;var window_y:=height*.54
    for facade_side in [-1.0,1.0]:
        var region_center:=float(facade_side)*(door_w+side_w)*.5
        var window_center:=float(facade_side)*width*.27
        var region_left:=region_center-side_w*.5;var region_right:=region_center+side_w*.5
        var window_left:=window_center-window_w*.5;var window_right:=window_center+window_w*.5
        var window_bottom:=window_y-window_h*.5;var window_top:=window_y+window_h*.5
        _solid_box(house,Vector3(side_w,window_bottom,thick),Vector3(region_center,window_bottom*.5,depth*.5),wall_mat)
        _solid_box(house,Vector3(side_w,height-window_top,thick),Vector3(region_center,window_top+(height-window_top)*.5,depth*.5),wall_mat)
        if window_left>region_left:_solid_box(house,Vector3(window_left-region_left,window_h,thick),Vector3((region_left+window_left)*.5,window_y,depth*.5),wall_mat)
        if region_right>window_right:_solid_box(house,Vector3(region_right-window_right,window_h,thick),Vector3((window_right+region_right)*.5,window_y,depth*.5),wall_mat)
        _visual_box(house,Vector3(window_w+.18,.13,.14),Vector3(window_center,window_y-window_h*.5,depth*.5+.08),beam_mat)
        _visual_box(house,Vector3(window_w+.18,.13,.14),Vector3(window_center,window_y+window_h*.5,depth*.5+.08),beam_mat)
        _visual_box(house,Vector3(.13,window_h+.18,.14),Vector3(window_center-window_w*.5,window_y,depth*.5+.08),beam_mat)
        _visual_box(house,Vector3(.13,window_h+.18,.14),Vector3(window_center+window_w*.5,window_y,depth*.5+.08),beam_mat)
    _solid_box(house, Vector3(door_w, height - door_h, thick), Vector3(0, door_h + (height - door_h) * 0.5, depth * 0.5), wall_mat)
    _add_working_house_door(house,door_w,door_h,depth,beam_mat)
    for x in [-width * 0.5, width * 0.5]:
        _visual_box(house, Vector3(0.30, height + 0.25, 0.30), Vector3(x, height * 0.5, depth * 0.51), beam_mat)
    if style % 4 == 3:
        # A tidy parapeted workshop/inn profile breaks up the repeated gables.
        _visual_box(house, Vector3(width + 0.9, 0.42, depth + 0.9), Vector3(0, height + 0.18, 0), roof_mat)
        for z in [-depth * 0.52, depth * 0.52]:
            _visual_box(house, Vector3(width + 1.0, 0.48, 0.28), Vector3(0, height + 0.55, z), beam_mat)
        for x in [-width * 0.52, width * 0.52]:
            _visual_box(house, Vector3(0.28, 0.48, depth + 1.0), Vector3(x, height + 0.55, 0), beam_mat)
    else:
        var roof_angle := 0.34
        var roof_y := height + 1.16
        var left_roof := _visual_box(house, Vector3(width * 0.56, 0.48, depth + 0.8), Vector3(-width * 0.235, roof_y, 0), roof_mat)
        left_roof.rotation.z = roof_angle
        var right_roof := _visual_box(house, Vector3(width * 0.56, 0.48, depth + 0.8), Vector3(width * 0.235, roof_y, 0), roof_mat)
        right_roof.rotation.z = -roof_angle
        _add_house_gables(house, width, depth, height, wall_mat, beam_mat)
    _visual_box(house, Vector3(width - 0.7, 0.16, depth - 0.7), Vector3(0, 0.01, 0), beam_mat)
    # Every window is a literal wall opening. Timber frames remain, but there
    # is no blue glass card or collision pane filling the view.
    for x in [-width*.27,width*.27]:
        for frame_x in [-.70,.70]:_visual_box(house,Vector3(.12,1.54,.16),Vector3(x+frame_x,height*.54,-depth*.52),beam_mat)
        for frame_y in [-.76,.76]:_visual_box(house,Vector3(1.52,.12,.16),Vector3(x,height*.54+frame_y,-depth*.52),beam_mat)
    for side in [-1.0,1.0]:
        for frame_z in [-.70,.70]:_visual_box(house,Vector3(.16,1.48,.12),Vector3(width*.52*side,height*.54,-depth*.16+frame_z),beam_mat)
        for frame_y in [-.72,.72]:_visual_box(house,Vector3(.16,.12,1.52),Vector3(width*.52*side,height*.54+frame_y,-depth*.16),beam_mat)
    _visual_box(house, Vector3(width + 0.15, 0.26, 0.28), Vector3(0, height * 0.68, depth * 0.52), beam_mat)
    _visual_box(house, Vector3(0.85, 3.2, 0.85), Vector3(width * 0.28, height + 1.4, -depth * 0.18), _make_material(Color(0.28, 0.25, 0.22), 1.0))
    # Stone foundation, door lintel and a projecting shop sign add believable
    # street-level detail without blocking the open doorway.
    var foundation := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(0.58, 0.57, 0.53), 1.0, 3.0)
    var foundation_side:=(width-door_w-.36)*.5
    for side in [-1.0,1.0]:_visual_box(house,Vector3(foundation_side,.62,.20),Vector3(float(side)*(door_w*.5+.18+foundation_side*.5),.31,depth*.525),foundation)
    _visual_box(house, Vector3(door_w + 0.7, 0.34, 0.34), Vector3(0, door_h + 0.17, depth * 0.54), beam_mat)
    if style % 3 == 0:
        _visual_box(house, Vector3(0.18, 1.65, 0.18), Vector3(width * 0.36, height * 0.62, depth * 0.72), beam_mat)
        _visual_box(house, Vector3(1.75, 0.95, 0.16), Vector3(width * 0.36, height * 0.48, depth * 0.72), beam_mat)
    _add_house_furniture(house, width, depth, beam_mat, style)
    _add_working_fireplace(house, width, depth, style)
    _optimize_small_detail_node(house,72.0)


func _make_real_window_material()->StandardMaterial3D:
    if _shared_materials.has("real_window_glass"):return _shared_materials.real_window_glass
    var glass:=StandardMaterial3D.new();glass.albedo_color=Color(.20,.38,.46,.34);glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.metallic=.08;glass.roughness=.18;glass.cull_mode=BaseMaterial3D.CULL_DISABLED
    _shared_materials.real_window_glass=glass
    return glass


func _add_working_house_door(house:Node3D,door_width:float,door_height:float,depth:float,material:Material,door_center_x:float=0.0,extra_group:String="")->void:
    var hinge:=Node3D.new();hinge.name="WorkingHouseDoor";hinge.position=Vector3(door_center_x-door_width*.5+.10,0,depth*.5+.08);hinge.add_to_group("interactive_house_door")
    if not extra_group.is_empty():hinge.add_to_group(extra_group)
    hinge.set_meta("door_center_x",door_center_x)
    hinge.set_meta("door_depth",depth)
    house.add_child(hinge)
    var body:=StaticBody3D.new();body.position=Vector3(door_width*.5-.10,door_height*.5,0);body.collision_layer=1;hinge.add_child(body)
    var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(door_width-.20,door_height-.12,.16);mesh.mesh=box;mesh.material_override=material;body.add_child(mesh)
    var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=box.size;collision.shape=shape;body.add_child(collision)
    for y in [-.85,.0,.85]:_visual_box(body,Vector3(door_width-.34,.09,.06),Vector3(0,y,-.11),_make_material(Color(.12,.13,.13),.74))
    var handle:=MeshInstance3D.new();var handle_mesh:=SphereMesh.new();handle_mesh.radius=.08;handle_mesh.height=.16;handle.mesh=handle_mesh;handle.position=Vector3(door_width*.30,0,-.15);handle.material_override=_make_material(Color(.68,.47,.13),.56);body.add_child(handle)


func _add_house_furniture(house: Node3D, width: float, depth: float, timber: Material, style: int) -> void:
    var furniture:=Node3D.new();furniture.name="Interior Detail";house.add_child(furniture)
    var cloth_colors := [Color(0.42, 0.09, 0.07), Color(0.12, 0.25, 0.39), Color(0.34, 0.29, 0.10)]
    var cloth := _make_material(cloth_colors[style % cloth_colors.size()], 0.94)
    var timber_boxes:Array=[]
    # Dining/work table with usable walking clearance around it.
    _solid_box(furniture, Vector3(3.2, 0.28, 1.65), Vector3(0.25, 1.25, 0), timber)
    for x in [-1.25, 1.75]:
        for z in [-0.58, 0.58]:
            timber_boxes.append({"size":Vector3(.20,1.12,.20),"position":Vector3(x,.56,z)})
    for z in [-1.35, 1.35]:
        timber_boxes.append({"size":Vector3(1.35,.25,.42),"position":Vector3(.25,.68,z)})
        timber_boxes.append({"size":Vector3(1.35,.18,1.05),"position":Vector3(.25,1.20,z+(-.38 if z<0 else .38))})
    # Bed, blanket, storage chest and shelf make interiors visibly inhabited.
    var bed_x := -width * 0.28
    var bed_z := -depth * 0.25
    timber_boxes.append({"size":Vector3(2.5,.45,4.0),"position":Vector3(bed_x,.48,bed_z)})
    _visual_box(furniture, Vector3(2.25, 0.20, 3.15), Vector3(bed_x, 0.80, bed_z - 0.18), cloth)
    timber_boxes.append({"size":Vector3(2.2,.72,1.15),"position":Vector3(width*.29,.38,-depth*.30)})
    timber_boxes.append({"size":Vector3(2.8,.22,.70),"position":Vector3(width*.24,2.15,-depth*.46)})
    _add_box_batch(furniture,timber_boxes,timber,false,38.0)
    for entry in timber_boxes:
        _add_static_collision_box(furniture,entry.get("size",Vector3.ONE),entry.get("position",Vector3.ZERO),entry.get("rotation",Vector3.ZERO))
    _optimize_small_detail_node(furniture,38.0)


func _add_house_gables(house: Node3D, width: float, depth: float, height: float, wall_material: Material, beam_material: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var peak_y := height + 2.30
    for z in [-depth * 0.505, depth * 0.505]:
        var a := Vector3(-width * 0.5, height - 0.05, z)
        var b := Vector3(width * 0.5, height - 0.05, z)
        var peak := Vector3(0, peak_y, z)
        st.set_uv(Vector2(0, 1)); st.add_vertex(a)
        st.set_uv(Vector2(0.5, 0)); st.add_vertex(peak)
        st.set_uv(Vector2(1, 1)); st.add_vertex(b)
        st.set_uv(Vector2(1, 1)); st.add_vertex(b)
        st.set_uv(Vector2(0.5, 0)); st.add_vertex(peak)
        st.set_uv(Vector2(0, 1)); st.add_vertex(a)
    st.generate_normals()
    var gables := MeshInstance3D.new()
    gables.mesh = st.commit()
    gables.material_override = wall_material
    house.add_child(gables)
    # One clean horizontal tie beam closes the gable without decorative pieces
    # protruding through the roof panels.
    for z in [-depth * 0.515, depth * 0.515]:
        _visual_box(house, Vector3(width, 0.22, 0.18), Vector3(0, height + 0.05, z), beam_material)


func _add_working_fireplace(house: Node3D, width: float, depth: float, style: int) -> void:
    var stone := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(0.34, 0.31, 0.27), 1.0, 2.5)
    var ember := StandardMaterial3D.new()
    ember.albedo_color = Color(1.0, 0.24, 0.035)
    ember.emission_enabled = true
    ember.emission = Color(1.0, 0.10, 0.015)
    ember.emission_energy_multiplier = 3.8
    var hearth := Node3D.new()
    hearth.name = "WorkingFireplace"
    hearth.position = Vector3(-width * 0.5 + 0.55, 0, -depth * 0.18)
    house.add_child(hearth)
    _visual_box(hearth, Vector3(1.0, 2.7, 3.4), Vector3(-0.18, 1.35, 0), stone)
    _visual_box(hearth, Vector3(0.46, 1.25, 2.0), Vector3(0.36, 0.72, 0), _make_material(Color(0.055, 0.035, 0.02), 1.0))
    for z in [-0.46, 0.46]:
        _visual_box(hearth, Vector3(0.55, 0.20, 0.82), Vector3(0.52, 0.27, z), _make_material(Color(0.19, 0.085, 0.025), 1.0)).rotation.x = 0.22 * (-1.0 if z < 0 else 1.0)
    var flame := _visual_box(hearth, Vector3(0.22, 0.78, 0.62), Vector3(0.56, 0.70, 0), ember)
    flame.rotation.z = -0.18
    if style % 2 == 0:
        var glow := OmniLight3D.new()
        glow.position = Vector3(0.72, 1.35, 0)
        glow.light_color = Color(1.0, 0.40, 0.14)
        glow.light_energy = 0.65
        glow.omni_range = 7.0
        glow.shadow_enabled = false
        glow.distance_fade_enabled = true
        glow.distance_fade_begin = 26.0
        glow.distance_fade_length = 18.0
        hearth.add_child(glow)
    _optimize_small_detail_node(hearth,42.0)


func _build_castle_complex(root: Node3D, center: Vector2, terrain_result: Dictionary) -> void:
    var castle_child_start:=root.get_child_count()
    var ground: Vector3 = terrain_result.height_sampler.call(center.x, center.y)
    var stone := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(1.10, 1.08, 1.01), 1.0, 8.0)
    var dark_stone := _make_texture_material("res://assets/architecture/castle_stone_v1.png", Color(0.72, 0.76, 0.78), 1.0, 6.0)
    var roof_mat := _make_material(Color(0.16, 0.18, 0.21), 0.96)
    var royal_mat := _make_material(Color(0.45, 0.08, 0.075), 0.92)
    var gold_mat := _make_material(Color(0.72, 0.52, 0.12), 0.72)
    var courtyard := _make_texture_material("res://assets/architecture/town_cobblestone_v1.png", Color(0.82, 0.83, 0.81), 1.0, 20.0)
    _solid_box(root, Vector3(142.0, 0.22, 118.0), ground + Vector3(0, 0.15, 0), courtyard)

    # Inner bailey with an open southern gate.
    _solid_box(root, Vector3(142.0, 7.0, 3.2), ground + Vector3(0, 3.5, -59), stone)
    _solid_box(root, Vector3(3.2, 7.0, 118.0), ground + Vector3(-71, 3.5, 0), stone)
    _solid_box(root, Vector3(3.2, 7.0, 118.0), ground + Vector3(71, 3.5, 0), stone)
    _solid_box(root, Vector3(58.0, 7.0, 3.2), ground + Vector3(-42, 3.5, 59), stone)
    _solid_box(root, Vector3(58.0, 7.0, 3.2), ground + Vector3(42, 3.5, 59), stone)
    _solid_box(root, Vector3(3.0, 8.0, 5.0), ground + Vector3(-11.5, 4.0, 58.5), dark_stone)
    _solid_box(root, Vector3(3.0, 8.0, 5.0), ground + Vector3(11.5, 4.0, 58.5), dark_stone)
    _solid_box(root, Vector3(20.0, 3.0, 5.0), ground + Vector3(0, 9.5, 58.5), dark_stone)

    for corner in [Vector2(-71, -59), Vector2(71, -59), Vector2(-71, 59), Vector2(71, 59)]:
        _solid_box(root, Vector3(14.0, 20.0, 14.0), ground + Vector3(corner.x, 10.0, corner.y), dark_stone)
        _solid_box(root,Vector3(14.4,.7,14.4),ground+Vector3(corner.x,20.15,corner.y),stone)
        _add_battlements(root, ground + Vector3(corner.x, 20.0, corner.y), 14.0, 14.0, stone)
        _add_castle_spire(root,ground+Vector3(corner.x,21.0,corner.y),7.3,9.0,roof_mat,gold_mat)
    _add_arch_crown(root,ground+Vector3(0,7.7,59.35),10.8,1.2,dark_stone)

    # Four-storey central keep. The ground floor has a real open entrance and
    # collision walls; upper floors are expressed by masonry bands and windows.
    var keep_center := ground + Vector3(0, 0, -8)
    var keep_width := 58.0
    var keep_depth := 44.0
    var keep_height := 32.0
    var wall_thickness := 1.5
    var rear_openings:Array[Dictionary]=[]
    for floor_index in range(4):
        var rear_y:=float(floor_index)*8.0+4.0
        for slit_x in [-18.0,0.0,18.0]:
            rear_openings.append({"x0":slit_x-.48,"x1":slit_x+.48,"y0":rear_y-1.45,"y1":rear_y+1.45})
    _build_keep_wall_with_openings(root,keep_center,-keep_depth*.5,keep_width,keep_height,wall_thickness,rear_openings,stone)
    for side in [-1.0,1.0]:
        var keep_side:=Node3D.new()
        keep_side.position=keep_center+Vector3(keep_width*.5*side,0,0)
        keep_side.rotation.y=PI*.5
        root.add_child(keep_side)
        var side_openings:Array[Dictionary]=[]
        for floor_index in range(4):
            var side_y:=float(floor_index)*8.0+4.0
            for slit_z in [-11.0,0.0,11.0]:
                side_openings.append({"x0":slit_z-.48,"x1":slit_z+.48,"y0":side_y-1.45,"y1":side_y+1.45})
        _build_keep_wall_with_openings(keep_side,Vector3.ZERO,0.0,keep_depth,keep_height,wall_thickness,side_openings,stone)
    var front_openings: Array[Dictionary] = [{"x0": -3.0, "x1": 3.0, "y0": 0.0, "y1": 5.2}]
    for floor_index in range(1, 4):
        var slit_center_y := float(floor_index) * 8.0 + 4.0
        for slit_x in [-18.0, 18.0]:
            front_openings.append({"x0": slit_x - 0.48, "x1": slit_x + 0.48, "y0": slit_center_y - 1.45, "y1": slit_center_y + 1.45})
    _build_keep_wall_with_openings(root, keep_center, keep_depth * 0.5, keep_width, keep_height, wall_thickness, front_openings, stone)
    # The continuous courtyard is the keep's ground floor. A second thin slab
    # here produced the broad interior shimmer and added no traversal value.
    for floor_index in range(1, 4):
        var floor_y := float(floor_index) * 8.0
        _build_keep_floor(root, keep_center, floor_y, keep_width, keep_depth, dark_stone)
        for x in [-18.0, 18.0]:
            _add_arrow_slit_frame(root, keep_center + Vector3(x, floor_y + 4.0, keep_depth * 0.5), dark_stone)
    # Tall buttresses and a framed entrance break up the keep's broad façade.
    for x in [-keep_width * 0.47, -keep_width * 0.24, keep_width * 0.24, keep_width * 0.47]:
        _visual_box(root, Vector3(2.0, keep_height - 2.0, 2.1), keep_center + Vector3(x, keep_height * 0.5, keep_depth * 0.53), dark_stone)
    _visual_box(root, Vector3(9.0, 1.0, 1.9), keep_center + Vector3(0, 5.4, keep_depth * 0.53), dark_stone)
    _visual_box(root, Vector3(1.0, 6.0, 1.9), keep_center + Vector3(-4.4, 2.9, keep_depth * 0.53), dark_stone)
    _visual_box(root, Vector3(1.0, 6.0, 1.9), keep_center + Vector3(4.4, 2.9, keep_depth * 0.53), dark_stone)
    _add_arch_crown(root,keep_center+Vector3(0,5.1,keep_depth*.54),4.5,1.35,gold_mat)
    _add_battlements(root, keep_center + Vector3(0, keep_height + 0.35, 0), keep_width, keep_depth, stone)
    _build_keep_roof_with_hatch(root,keep_center,keep_width,keep_depth,keep_height+.48,roof_mat)

    # The lower corner masonry supports accessible roof lookout rooms. Their
    # doors, open slit windows, roof slabs and overlapping spires form one
    # continuous assembly instead of floating boxes and cones.
    var roof_surface_y:=keep_height+1.08
    var roof_timber:=_make_texture_material("res://assets/architecture/dark_oak_v1.png",Color(.60,.43,.27),1.0,2.4)
    for tower_x in [-keep_width*.5,keep_width*.5]:
        for tower_z in [-keep_depth*.5,keep_depth*.5]:
            _solid_box(root,Vector3(8.5,roof_surface_y,8.5),keep_center+Vector3(tower_x,roof_surface_y*.5,tower_z),dark_stone)
            var local_door_x:=signf(tower_x)*2.05*(1.0 if tower_z>0.0 else -1.0)
            _build_roof_lookout_tower(root,keep_center+Vector3(tower_x,roof_surface_y,tower_z),tower_z>0.0,local_door_x,stone,dark_stone,roof_timber,roof_mat,gold_mat)
    _build_roof_gallery(root,keep_center+Vector3(0,roof_surface_y,0),keep_width,keep_depth,stone)
    _build_central_roof_watch(root,keep_center+Vector3(0,roof_surface_y,0),dark_stone,stone,roof_timber,roof_mat,gold_mat)
    # Keep the central watch doorway completely clear. The former seven-metre
    # banner crossed its lintel and was later given collision by the town
    # detail pass, making the apparently open entrance unusable.

    # Throne-hall columns are visible and walk-around on the accessible floor.
    for x in [-19.0, 19.0]:
        for z in [-13.0, 0.0, 13.0]:
            _solid_box(root, Vector3(1.5, 6.5, 1.5), keep_center + Vector3(x, 3.25, z), dark_stone)
    _build_grand_throne(root,keep_center,royal_mat,gold_mat,dark_stone)
    var hall_timber := roof_timber
    for z in [-8.0, 3.0, 12.0]:
        _solid_box(root, Vector3(12.0, 0.32, 2.2), keep_center + Vector3(0, 1.15, z), hall_timber)
        for x in [-5.1, 5.1]:
            _visual_box(root, Vector3(0.35, 1.05, 1.5), keep_center + Vector3(x, 0.53, z), hall_timber)
        for side in [-1.0, 1.0]:
            _visual_box(root, Vector3(10.5, 0.28, 0.65), keep_center + Vector3(0, 0.62, z + side * 2.0), hall_timber)
    _visual_box(root, Vector3(4.8, 1.7, 2.0), keep_center + Vector3(-20.5, 0.85, -16.0), hall_timber)
    _build_internal_keep_stairs(root, keep_center, hall_timber, dark_stone)
    _add_castle_roof_ladder(root,keep_center,hall_timber,dark_stone)
    _dress_keep_upper_floors(root, keep_center, hall_timber, royal_mat, gold_mat, dark_stone)
    _add_keep_wall_torches(root, keep_center, dark_stone)
    var keep_interior := Node3D.new()
    keep_interior.position = keep_center
    root.add_child(keep_interior)
    _add_working_fireplace(keep_interior, keep_width, keep_depth, 0)

    # Legacy exterior gallery ramps were removed. They created invisible
    # sampled stairs outside the keep and bypassed the intended interior route.
    for side in [-1.0, 1.0]:
        var hall_banner_center:=keep_center+Vector3(11.0*side,13.0,keep_depth*.52)
        _visual_box(root,Vector3(3.2,8.5,.18),hall_banner_center,royal_mat)
        _add_broken_crown_crest(root,hall_banner_center+Vector3(0,0,.13),.92,gold_mat)
        _visual_box(root, Vector3(0.35, 9.0, 0.35), keep_center + Vector3(13.0 * side, 13.2, keep_depth * 0.54), gold_mat)
    for child_index in range(castle_child_start,root.get_child_count()):
        _optimize_small_detail_node(root.get_child(child_index),82.0)


func _optimize_small_detail_node(node:Node,detail_range:float)->void:
    if node is MeshInstance3D:
        var mesh_instance:=node as MeshInstance3D
        if mesh_instance.mesh:
            var dimensions:=mesh_instance.mesh.get_aabb().size*mesh_instance.scale.abs()
            var maximum_dimension:=maxf(dimensions.x,maxf(dimensions.y,dimensions.z))
            if maximum_dimension<6.0:
                mesh_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
                if mesh_instance.visibility_range_end<=0.0 or mesh_instance.visibility_range_end>detail_range:
                    mesh_instance.visibility_range_end=detail_range
                mesh_instance.visibility_range_end_margin=18.0
                mesh_instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    for child in node.get_children():_optimize_small_detail_node(child,detail_range)


func _build_keep_wall_with_openings(root: Node3D, keep_center: Vector3, z: float, width: float, height: float, thickness: float, openings: Array[Dictionary], material: Material) -> void:
    var x_cuts: Array = [-width * 0.5, width * 0.5]
    var y_cuts: Array = [0.0, height]
    for opening in openings:
        x_cuts.append(clampf(float(opening.x0), -width * 0.5, width * 0.5))
        x_cuts.append(clampf(float(opening.x1), -width * 0.5, width * 0.5))
        y_cuts.append(clampf(float(opening.y0), 0.0, height))
        y_cuts.append(clampf(float(opening.y1), 0.0, height))
    x_cuts.sort()
    y_cuts.sort()
    for xi in range(x_cuts.size() - 1):
        var x0: float = x_cuts[xi]
        var x1: float = x_cuts[xi + 1]
        if x1 - x0 < 0.02:
            continue
        for yi in range(y_cuts.size() - 1):
            var y0: float = y_cuts[yi]
            var y1: float = y_cuts[yi + 1]
            if y1 - y0 < 0.02:
                continue
            var midpoint := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
            var blocked := false
            for opening in openings:
                if midpoint.x > float(opening.x0) and midpoint.x < float(opening.x1) and midpoint.y > float(opening.y0) and midpoint.y < float(opening.y1):
                    blocked = true
                    break
            if not blocked:
                _solid_box(root, Vector3(x1 - x0, y1 - y0, thickness), keep_center + Vector3(midpoint.x, midpoint.y, z), material)


func _build_roof_lookout_tower(root:Node3D,floor_center:Vector3,faces_negative_z:bool,door_center_x:float,stone:Material,dark_stone:Material,timber:Material,roof:Material,gold:Material)->void:
    var lookout:=Node3D.new()
    lookout.name="AccessibleRoofLookout"
    lookout.add_to_group("castle_roof_lookout")
    lookout.position=floor_center
    lookout.rotation.y=PI if faces_negative_z else 0.0
    root.add_child(lookout)
    var width:=8.5
    var depth:=8.5
    var height:=5.8
    var thickness:=.72
    # Offset the entrance toward the open roof. A perpendicular gallery wall
    # meets each tower at its centerline, so the old centered door was built
    # directly around a solid wall end. There is intentionally no window on
    # this face competing with the shifted doorway.
    var front_openings:Array[Dictionary]=[
        {"x0":door_center_x-1.1,"x1":door_center_x+1.1,"y0":0.0,"y1":3.15},
    ]
    _build_keep_wall_with_openings(lookout,Vector3.ZERO,depth*.5,width,height,thickness,front_openings,stone)
    _build_keep_wall_with_openings(
        lookout,Vector3.ZERO,-depth*.5,width,height,thickness,
        [{"x0":-.42,"x1":.42,"y0":2.3,"y1":4.95}],stone
    )
    for side in [-1.0,1.0]:
        var side_wall:=Node3D.new()
        side_wall.position=Vector3(width*.5*side,0,0)
        side_wall.rotation.y=PI*.5
        lookout.add_child(side_wall)
        _build_keep_wall_with_openings(
            side_wall,Vector3.ZERO,0.0,depth,height,thickness,
            [{"x0":-.42,"x1":.42,"y0":2.3,"y1":4.95}],stone
        )
    _add_working_house_door(lookout,2.2,3.15,depth,timber,door_center_x,"castle_roof_door")
    _solid_box(lookout,Vector3(width+.35,.55,depth+.35),Vector3(0,height+.16,0),dark_stone)
    _add_battlements(lookout,Vector3(0,height+.25,0),width,depth,stone)
    # The roof begins inside the connected slab/battlement band; no daylight
    # gap remains below the formerly floating cone.
    _add_castle_spire(lookout,Vector3(0,height+.65,0),4.45,7.2,roof,gold)


func _build_roof_gallery(root:Node3D,roof_center:Vector3,keep_width:float,keep_depth:float,stone:Material)->void:
    var tower_size:=8.5
    var horizontal_span:=keep_width-tower_size
    var side_span:=keep_depth-tower_size
    _build_open_gallery_wall(root,roof_center+Vector3(0,0,-keep_depth*.5),horizontal_span,false,stone)
    _build_open_gallery_wall(root,roof_center+Vector3(0,0,keep_depth*.5),horizontal_span,false,stone)
    _build_open_gallery_wall(root,roof_center+Vector3(-keep_width*.5,0,0),side_span,true,stone)
    _build_open_gallery_wall(root,roof_center+Vector3(keep_width*.5,0,0),side_span,true,stone)


func _build_open_gallery_wall(root:Node3D,base_center:Vector3,width:float,rotated:bool,stone:Material)->void:
    var gallery:=Node3D.new()
    gallery.name="OpenRoofGallery"
    gallery.add_to_group("castle_roof_gallery")
    gallery.position=base_center
    if rotated:gallery.rotation.y=PI*.5
    root.add_child(gallery)
    var openings:Array[Dictionary]=[]
    var bay_count:=maxi(3,floori(width/6.2))
    var bay_width:=width/float(bay_count)
    for bay_index in range(bay_count):
        var center_x:=-width*.5+(float(bay_index)+.5)*bay_width
        openings.append({
            "x0":center_x-bay_width*.34,
            "x1":center_x+bay_width*.34,
            "y0":.78,
            "y1":3.05,
        })
    _build_keep_wall_with_openings(gallery,Vector3.ZERO,0.0,width,3.55,.62,openings,stone)
    _solid_box(gallery,Vector3(width+.25,.28,.86),Vector3(0,3.62,0),stone)


func _build_central_roof_watch(root:Node3D,floor_center:Vector3,stone:Material,trim:Material,timber:Material,roof:Material,gold:Material)->void:
    var watch:=Node3D.new()
    watch.name="AccessibleCentralWatch"
    watch.add_to_group("castle_central_watch")
    watch.position=floor_center
    root.add_child(watch)
    var width:=18.0
    var depth:=14.0
    var height:=9.7
    var thickness:=.78
    var front_openings:Array[Dictionary]=[
        {"x0":-1.15,"x1":1.15,"y0":0.0,"y1":3.25},
        {"x0":-6.0,"x1":-5.1,"y0":4.0,"y1":7.1},
        {"x0":5.1,"x1":6.0,"y0":4.0,"y1":7.1},
    ]
    _build_keep_wall_with_openings(watch,Vector3.ZERO,depth*.5,width,height,thickness,front_openings,stone)
    var rear_openings:Array[Dictionary]=[]
    for x in [-5.5,0.0,5.5]:
        rear_openings.append({"x0":x-.45,"x1":x+.45,"y0":3.7,"y1":7.0})
    _build_keep_wall_with_openings(watch,Vector3.ZERO,-depth*.5,width,height,thickness,rear_openings,stone)
    for side in [-1.0,1.0]:
        var side_wall:=Node3D.new()
        side_wall.position=Vector3(width*.5*side,0,0)
        side_wall.rotation.y=PI*.5
        watch.add_child(side_wall)
        _build_keep_wall_with_openings(
            side_wall,Vector3.ZERO,0.0,depth,height,thickness,
            [
                {"x0":-4.1,"x1":-3.25,"y0":3.7,"y1":7.0},
                {"x0":3.25,"x1":4.1,"y0":3.7,"y1":7.0},
            ],stone
        )
    _add_working_house_door(watch,2.3,3.25,depth,timber,0.0,"castle_roof_door")
    _solid_box(watch,Vector3(width+.4,.58,depth+.4),Vector3(0,height+.18,0),trim)
    _add_battlements(watch,Vector3(0,height+.28,0),width,depth,trim)
    _add_castle_spire(watch,Vector3(0,height+.75,0),7.0,8.5,roof,gold)


func _make_slit_window_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.33, 0.48, 0.52, 0.28)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.18
    material.metallic = 0.08
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _add_arrow_slit_frame(root: Node3D, center: Vector3, frame: Material) -> void:
    for side in [-1.0, 1.0]:
        _visual_box(root, Vector3(0.16, 3.15, 0.34), center + Vector3(0.56 * side, 0, 0), frame)
        _visual_box(root, Vector3(1.12, 0.16, 0.34), center + Vector3(0, 1.58 * side, 0), frame)


func _add_keep_wall_torches(root: Node3D, keep_center: Vector3, bracket_material: Material) -> void:
    var flame_material := _make_lit_window_material(Color(1.0, 0.27, 0.045))
    for floor_index in range(4):
        var y := float(floor_index) * 8.0 + 3.25
        for x in [-12.0, 12.0]:
            var center := keep_center + Vector3(x, y, -20.55)
            _visual_box(root, Vector3(0.22, 1.05, 0.22), center + Vector3(0, -0.38, 0.38), bracket_material).rotation.x = -0.32
            var flame := MeshInstance3D.new()
            var flame_mesh := SphereMesh.new(); flame_mesh.radius = 0.22; flame_mesh.height = 0.62; flame_mesh.radial_segments = 7; flame_mesh.rings = 4
            flame.mesh = flame_mesh; flame.position = center + Vector3(0, 0.27, 0.72); flame.material_override = flame_material; root.add_child(flame)
            var light := OmniLight3D.new(); light.position = center + Vector3(0, 0.42, 1.1); light.light_color = Color(1.0, 0.56, 0.24); light.light_energy = 0.0; light.omni_range = 12.0; light.shadow_enabled = false; light.visible=false; light.distance_fade_enabled=true;light.distance_fade_begin=42.0;light.distance_fade_length=16.0;light.add_to_group("town_torches"); root.add_child(light)


func _build_keep_floor(root: Node3D, keep_center: Vector3, floor_y: float, width: float, depth: float, material: Material) -> void:
    # Each storey now has only the opening its two meeting stair flights need.
    # The former shared 15 x 22.5 m void produced the strange blocky gaps.
    var floor_index:=roundi(floor_y/8.0)
    var holes:Array[Rect2]
    if floor_index==1:
        holes=[Rect2(7.5,-8.8,5.0,11.8)]
    elif floor_index==2:
        holes=[Rect2(15.5,4.0,5.0,12.8)]
    else:
        holes=[Rect2(7.5,-8.8,5.0,11.8)]
    var x_cuts:Array=[-width*.5,width*.5]
    var z_cuts:Array=[-depth*.5+1.0,depth*.5-1.0]
    for hole in holes:
        x_cuts.append(hole.position.x);x_cuts.append(hole.end.x)
        z_cuts.append(hole.position.y);z_cuts.append(hole.end.y)
    x_cuts.sort();z_cuts.sort()
    for xi in range(x_cuts.size()-1):
        for zi in range(z_cuts.size()-1):
            var x0:float=x_cuts[xi];var x1:float=x_cuts[xi+1]
            var z0:float=z_cuts[zi];var z1:float=z_cuts[zi+1]
            var midpoint:=Vector2((x0+x1)*.5,(z0+z1)*.5)
            var inside_hole:=false
            for hole in holes:
                if hole.has_point(midpoint):inside_hole=true;break
            if not inside_hole:
                _solid_box(root,Vector3(x1-x0,.42,z1-z0),keep_center+Vector3(midpoint.x,floor_y,midpoint.y),material)


func _build_keep_roof_with_hatch(root:Node3D,keep_center:Vector3,width:float,depth:float,roof_y:float,material:Material)->void:
    var hatch:=Rect2(15.2,1.5,5.6,10.5)
    var x_cuts:Array=[-width*.5+.9,hatch.position.x,hatch.end.x,width*.5-.9]
    var z_cuts:Array=[-depth*.5+.9,hatch.position.y,hatch.end.y,depth*.5-.9]
    for xi in range(x_cuts.size()-1):
        for zi in range(z_cuts.size()-1):
            var x0:float=x_cuts[xi];var x1:float=x_cuts[xi+1]
            var z0:float=z_cuts[zi];var z1:float=z_cuts[zi+1]
            var midpoint:=Vector2((x0+x1)*.5,(z0+z1)*.5)
            if hatch.has_point(midpoint):continue
            _solid_box(root,Vector3(x1-x0,1.2,z1-z0),keep_center+Vector3(midpoint.x,roof_y,midpoint.y),material)


func _add_castle_roof_ladder(root:Node3D,keep_center:Vector3,timber:Material,stone:Material)->void:
    var ladder:=Node3D.new()
    ladder.name="CastleRoofLadder"
    ladder.add_to_group("climbable_ladder")
    root.add_child(ladder)
    var bottom:=keep_center+Vector3(18.0,24.35,10.5)
    # Both endpoints stay inside the roof hatch. The former top ended beneath
    # the solid roof lip, so climbing up worked but the ladder could not be
    # reacquired from above.
    var top:=keep_center+Vector3(18.0,33.18,2.2)
    ladder.set_meta("climb_bottom",bottom)
    ladder.set_meta("climb_top",top)
    ladder.set_meta("climb_top_dismount",keep_center+Vector3(18.0,33.14,-1.25))
    ladder.set_meta("climb_bottom_dismount",bottom+Vector3.UP*.06)
    ladder.set_meta("climb_label","Castle roof ladder")
    var rail_mesh:=CylinderMesh.new();rail_mesh.top_radius=.12;rail_mesh.bottom_radius=.15;rail_mesh.height=1.0;rail_mesh.radial_segments=8
    for x_offset in [-.82,.82]:
        var rail:=MeshInstance3D.new();rail.name="LadderRail"
        rail.mesh=rail_mesh
        rail.transform=_cylinder_between_transform(bottom+Vector3(x_offset,0,0),top+Vector3(x_offset,0,0),1.0)
        rail.material_override=timber;ladder.add_child(rail)
    var rung_mesh:=CylinderMesh.new();rung_mesh.top_radius=.09;rung_mesh.bottom_radius=.09;rung_mesh.height=1.0;rung_mesh.radial_segments=7
    for rung_index in range(15):
        var t:float=float(rung_index)/14.0
        var center:=bottom.lerp(top,t)
        var rung:=MeshInstance3D.new();rung.name="LadderRung"
        rung.mesh=rung_mesh
        rung.transform=_cylinder_between_transform(center+Vector3(-.82,0,0),center+Vector3(.82,0,0),1.0)
        rung.material_override=timber;ladder.add_child(rung)
    # A dressed hatch curb closes the slab edges without obstructing the climb.
    _solid_box(root,Vector3(6.4,.55,.45),keep_center+Vector3(18.0,33.34,12.25),stone)
    _solid_box(root,Vector3(.45,.55,10.5),keep_center+Vector3(14.95,33.34,6.75),stone)
    _solid_box(root,Vector3(.45,.55,10.5),keep_center+Vector3(21.05,33.34,6.75),stone)


func _build_internal_keep_stairs(root: Node3D, keep_center: Vector3, tread_material: Material, rail_material: Material) -> void:
    var step_count := 26
    var tread_transforms:Array[Transform3D]=[]
    var riser_transforms:Array[Transform3D]=[]
    var post_transforms:Array[Transform3D]=[]
    for floor_index in range(3):
        var base_y := float(floor_index) * 8.0 + (0.21 if floor_index > 0 else 0.0)
        var target_y := float(floor_index + 1) * 8.0 + 0.21
        var reverse := floor_index % 2 == 1
        var stair_x := 10.0 if not reverse else 18.0
        var start_z := -8.2 if reverse else 16.2
        var end_z := 16.2 if reverse else -8.2
        var start2 := Vector2(keep_center.x + stair_x, keep_center.z + start_z)
        var end2 := Vector2(keep_center.x + stair_x, keep_center.z + end_z)
        var ramp_mesh := _build_bridge_ramp_mesh(start2, end2, Vector2(1, 0), 4.35, 4.35, keep_center.y + base_y, keep_center.y + target_y)
        var ramp := MeshInstance3D.new()
        ramp.name = "SmoothCastleStairRamp"
        ramp.mesh = ramp_mesh
        ramp.material_override = tread_material
        # This ramp already owns exact trimesh collision. The town detail pass
        # must not wrap its sloped AABB in a solid box.
        ramp.set_meta("skip_static_solidify",true)
        root.add_child(ramp)
        ramp.create_trimesh_collision()
        # A flush final landing closes the visible end of the ramp and hands
        # the hero directly to the storey slab. Its outer edge matches the
        # floor opening so there is no unsupported strip to fall through.
        var travel_sign:=1.0 if reverse else -1.0
        _solid_box(
            root,
            Vector3(4.48,.12,1.10),
            keep_center+Vector3(stair_x,target_y-.06,end_z+travel_sign*.05),
            tread_material
        )
        # The treads are visual detail only. Traversal rides the uninterrupted
        # ramp beneath them, eliminating the final double-step at every floor.
        for i in range(step_count):
            var progress := (float(i) + 0.5) / float(step_count)
            var z := lerpf(start_z, end_z, progress)
            var step_top := lerpf(base_y, target_y, progress)
            tread_transforms.append(Transform3D(Basis.IDENTITY,keep_center+Vector3(stair_x,step_top+.025,z)))
            var previous_top:=lerpf(base_y,target_y,float(i)/float(step_count))
            var fill_height:=maxf(.10,step_top-previous_top+.08)
            riser_transforms.append(Transform3D(
                Basis.IDENTITY.scaled(Vector3(4.48,fill_height,.86)),
                keep_center+Vector3(stair_x,(step_top+previous_top)*.5,z)
            ))
        for side in [-1.0, 1.0]:
            for post_index in range(6):
                var t := float(post_index) / 5.0
                var post_z := lerpf(start_z, end_z, t)
                post_transforms.append(Transform3D(Basis.IDENTITY,keep_center+Vector3(stair_x+2.3*side,lerpf(base_y,target_y,t)+.65,post_z)))
    var tread_mesh:=BoxMesh.new();tread_mesh.size=Vector3(4.48,.09,.86)
    var riser_mesh:=BoxMesh.new();riser_mesh.size=Vector3.ONE
    var post_mesh:=BoxMesh.new();post_mesh.size=Vector3(.18,1.15,.18)
    _add_material_multimesh(root,tread_mesh,tread_transforms,tread_material,false)
    _add_material_multimesh(root,riser_mesh,riser_transforms,tread_material,false)
    _add_material_multimesh(root,post_mesh,post_transforms,rail_material,false)
    root.add_to_group("castle_stair_assembly")
    root.set_meta("castle_stair_riser_count",riser_transforms.size())


func _dress_keep_upper_floors(root: Node3D, keep_center: Vector3, timber: Material, royal: Material, gold: Material, stone: Material) -> void:
    # Second floor: council chamber with a long table, chairs, wall maps and banners.
    var council_y := 8.21
    _solid_box(root, Vector3(15.0, 0.42, 4.4), keep_center + Vector3(-8.0, council_y + 1.1, -5.0), timber)
    for x in [-14.0, -10.0, -6.0, -2.0]:
        for z in [-8.0, -2.0]:
            _visual_box(root, Vector3(1.4, 1.15, 1.3), keep_center + Vector3(x, council_y + 0.58, z), timber)
    _visual_box(root, Vector3(13.0, 5.2, 0.16), keep_center + Vector3(-8.0, council_y + 4.3, -20.90), royal)
    _visual_box(root, Vector3(8.0, 3.8, 0.18), keep_center + Vector3(10.0, council_y + 4.0, -20.88), royal)
    for x in [-18.0, 18.0]:
        _visual_box(root, Vector3(2.8, 6.0, 0.20), keep_center + Vector3(x, council_y + 4.5, 20.92), royal)

    # Third floor: armory and archive, deliberately unlike the council room.
    var armory_y := 16.21
    for x in [-19.0, -12.0, -5.0]:
        _visual_box(root, Vector3(4.0, 5.5, 0.55), keep_center + Vector3(x, armory_y + 2.8, -20.95), timber)
        for shelf_y in [1.1, 2.6, 4.1]:
            _visual_box(root, Vector3(3.6, 0.20, 1.2), keep_center + Vector3(x, armory_y + shelf_y, -20.2), timber)
    for z in [-12.0, -4.0, 4.0, 12.0]:
        _visual_box(root, Vector3(0.34, 5.8, 0.34), keep_center + Vector3(23.0, armory_y + 3.0, z), gold).rotation.z = 0.18
        _visual_box(root, Vector3(2.1, 0.9, 0.24), keep_center + Vector3(22.85, armory_y + 2.4, z), stone)
    _solid_box(root, Vector3(6.5, 1.1, 3.4), keep_center + Vector3(-12.0, armory_y + 0.55, 10.0), stone)
    _solid_box(root, Vector3(5.0, 1.0, 3.2), keep_center + Vector3(-4.0, armory_y + 0.50, 12.0), timber)

    # Fourth floor: royal solar with beds, chests, rugs and heraldry.
    var solar_y := 24.21
    for x in [-17.0, 3.0]:
        _solid_box(root, Vector3(8.0, 0.65, 4.8), keep_center + Vector3(x, solar_y + 0.42, -10.0), timber)
        _visual_box(root, Vector3(7.3, 0.24, 4.0), keep_center + Vector3(x, solar_y + 0.88, -10.0), royal)
    for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
        _visual_box(root, Vector3(3.8, 5.6, 0.18), keep_center + Vector3(x, solar_y + 3.8, 20.92), royal)
    _visual_box(root, Vector3(18.0, 0.10, 9.0), keep_center + Vector3(-7.0, solar_y + 0.16, 5.0), royal)
    for pos in [Vector3(-22, 0.7, 14), Vector3(6, 0.7, 13), Vector3(20, 0.7, -12)]:
        _solid_box(root, Vector3(3.6, 1.4, 2.4), keep_center + Vector3(pos.x, solar_y + pos.y, pos.z), timber)


func _add_arch_crown(root:Node3D,center:Vector3,radius:float,depth:float,material:Material)->void:
    var segments:=15
    for i in range(segments):
        var angle:=PI*(float(i)+.5)/float(segments)
        var block:=_visual_box(root,Vector3(radius*PI/float(segments)*1.12,1.05,depth),center+Vector3(cos(angle)*radius,sin(angle)*radius,0),material)
        block.rotation.z=angle-PI*.5
    for side in [-1.0,1.0]:
        _visual_box(root,Vector3(1.35,radius*.82,depth),center+Vector3(side*radius,-radius*.38,0),material)


func _add_castle_spire(root:Node3D,base_center:Vector3,radius:float,height:float,roof:Material,gold:Material)->void:
    var spire:=MeshInstance3D.new();var cone:=CylinderMesh.new();cone.top_radius=0.0;cone.bottom_radius=radius;cone.height=height;cone.radial_segments=12;spire.mesh=cone;spire.position=base_center+Vector3.UP*(height*.5);spire.material_override=roof;root.add_child(spire)
    var finial:=MeshInstance3D.new();var finial_mesh:=SphereMesh.new();finial_mesh.radius=.34;finial_mesh.height=.68;finial.mesh=finial_mesh;finial.position=base_center+Vector3.UP*(height+.28);finial.material_override=gold;root.add_child(finial)


func _build_grand_throne(root:Node3D,keep_center:Vector3,royal:Material,gold:Material,stone:Material)->void:
    # Keep the entire throne below the eight-metre upper floor. The previous
    # canopy and crest punched visibly through the room above.
    for step in range(3):
        _solid_box(root,Vector3(9.6-float(step)*1.5,.28,5.8-float(step)*.90),keep_center+Vector3(0,.14+float(step)*.28,-15.2-float(step)*.24),stone)
    _solid_box(root,Vector3(4.0,.58,3.0),keep_center+Vector3(0,1.02,-16.35),royal)
    _solid_box(root,Vector3(4.5,4.7,.58),keep_center+Vector3(0,3.62,-17.72),royal)
    _visual_box(root,Vector3(3.35,3.85,.22),keep_center+Vector3(0,3.70,-18.04),gold)
    for side in [-1.0,1.0]:
        _solid_box(root,Vector3(.58,1.45,3.15),keep_center+Vector3(side*2.25,1.58,-16.30),gold)
        _visual_box(root,Vector3(.38,5.8,.38),keep_center+Vector3(side*3.45,3.55,-18.0),gold)
    _add_arch_crown(root,keep_center+Vector3(0,4.55,-18.05),2.15,.34,gold)
    var crown:=MeshInstance3D.new();var crown_mesh:=CylinderMesh.new();crown_mesh.top_radius=0.0;crown_mesh.bottom_radius=1.20;crown_mesh.height=1.10;crown_mesh.radial_segments=5;crown.mesh=crown_mesh;crown.position=keep_center+Vector3(0,6.45,-17.82);crown.material_override=gold;root.add_child(crown)
    _visual_box(root,Vector3(8.5,.20,5.1),keep_center+Vector3(0,7.18,-16.65),royal)


func _add_battlements(root: Node3D, center: Vector3, width: float, depth: float, material: Material) -> void:
    var x_count := maxi(3, floori(width / 5.0))
    var z_count := maxi(3, floori(depth / 5.0))
    var x_transforms:Array[Transform3D]=[]
    var z_transforms:Array[Transform3D]=[]
    for i in range(x_count + 1):
        var x := lerpf(-width * 0.5, width * 0.5, float(i) / x_count)
        x_transforms.append(Transform3D(Basis.IDENTITY,center+Vector3(x,1.0,-depth*.5)))
        x_transforms.append(Transform3D(Basis.IDENTITY,center+Vector3(x,1.0,depth*.5)))
    for i in range(1, z_count):
        var z := lerpf(-depth * 0.5, depth * 0.5, float(i) / z_count)
        z_transforms.append(Transform3D(Basis.IDENTITY,center+Vector3(-width*.5,1.0,z)))
        z_transforms.append(Transform3D(Basis.IDENTITY,center+Vector3(width*.5,1.0,z)))
    var x_mesh:=BoxMesh.new();x_mesh.size=Vector3(2.2,2.0,1.7)
    var z_mesh:=BoxMesh.new();z_mesh.size=Vector3(1.7,2.0,2.2)
    _add_material_multimesh(root,x_mesh,x_transforms,material)
    _add_material_multimesh(root,z_mesh,z_transforms,material)


func _add_material_multimesh(root:Node3D,mesh:Mesh,transforms:Array[Transform3D],material:Material,cast_shadows:bool=true,visibility_range_end:float=0.0,cell_size:float=0.0)->Dictionary:
    var source_map:Dictionary={}
    if transforms.is_empty():return source_map
    var groups:Dictionary={}
    for source_index in range(transforms.size()):
        var transform:Transform3D=transforms[source_index]
        var key:=Vector2i.ZERO
        if cell_size>0.0:key=Vector2i(floori(transform.origin.x/cell_size),floori(transform.origin.z/cell_size))
        if not groups.has(key):groups[key]=[]
        groups[key].append({"source_index":source_index,"transform":transform})
    for key in groups:
        var chunk_entries:Array=groups[key]
        var chunk_origin:=Vector3.ZERO
        if cell_size>0.0:chunk_origin=Vector3((float(key.x)+.5)*cell_size,0,(float(key.y)+.5)*cell_size)
        var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.instance_count=chunk_entries.size();multimesh.mesh=mesh
        var local_transforms:Array[Transform3D]=[]
        var packed_buffer:=PackedFloat32Array()
        packed_buffer.resize(chunk_entries.size()*12)
        for i in range(chunk_entries.size()):
            var local_transform:Transform3D=chunk_entries[i].transform
            local_transform.origin-=chunk_origin
            local_transforms.append(local_transform)
            var offset:=i*12
            var basis:=local_transform.basis
            packed_buffer[offset+0]=basis.x.x;packed_buffer[offset+1]=basis.y.x;packed_buffer[offset+2]=basis.z.x;packed_buffer[offset+3]=local_transform.origin.x
            packed_buffer[offset+4]=basis.x.y;packed_buffer[offset+5]=basis.y.y;packed_buffer[offset+6]=basis.z.y;packed_buffer[offset+7]=local_transform.origin.y
            packed_buffer[offset+8]=basis.x.z;packed_buffer[offset+9]=basis.y.z;packed_buffer[offset+10]=basis.z.z;packed_buffer[offset+11]=local_transform.origin.z
        multimesh.buffer=packed_buffer
        var instance:=MultiMeshInstance3D.new();instance.position=chunk_origin;instance.multimesh=multimesh;instance.material_override=material
        if not cast_shadows:instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        if visibility_range_end>0.0:
            instance.visibility_range_end=visibility_range_end
            instance.visibility_range_end_margin=minf(70.0,visibility_range_end*.12)
            instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        root.add_child(instance)
        for i in range(chunk_entries.size()):
            source_map[chunk_entries[i].source_index]={"instance":instance,"index":i,"transform":local_transforms[i]}
    return source_map


func _append_tree_registry(root:Node3D,tree_data:Dictionary)->void:
    var registry:Array=root.get_meta("harvestable_tree_registry",[])
    registry.append(tree_data)
    root.set_meta("harvestable_tree_registry",registry)


func _add_box_batch(root:Node3D,entries:Array,material:Material,cast_shadows:bool=false,visibility_range_end:float=0.0)->void:
    if entries.is_empty():return
    var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
    var transforms:Array[Transform3D]=[]
    for entry in entries:
        var size:Vector3=entry.get("size",Vector3.ONE)
        var position:Vector3=entry.get("position",Vector3.ZERO)
        var rotation:Vector3=entry.get("rotation",Vector3.ZERO)
        transforms.append(Transform3D(Basis.from_euler(rotation).scaled(size),position))
    _add_material_multimesh(root,mesh,transforms,material,cast_shadows,visibility_range_end)

func _solid_box(root: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
    var batched:=bool(root.get_meta("batch_static_collision",false))
    var body:StaticBody3D
    if batched:
        body=root.get_node_or_null("BatchedStaticCollision") as StaticBody3D
        if not body:
            body=StaticBody3D.new();body.name="BatchedStaticCollision";body.collision_layer=1;root.add_child(body)
    else:
        body=StaticBody3D.new();body.position=position;body.collision_layer=1;root.add_child(body)
    var local_position:=position if batched else Vector3.ZERO
    var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.position=local_position;mesh.material_override=material;body.add_child(mesh)
    var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;collision.position=local_position;body.add_child(collision)


func _solid_box_euler(root:Node3D,size:Vector3,position:Vector3,rotation:Vector3,material:Material)->void:
    var batched:=bool(root.get_meta("batch_static_collision",false))
    var body:StaticBody3D
    if batched:
        body=root.get_node_or_null("BatchedStaticCollision") as StaticBody3D
        if not body:
            body=StaticBody3D.new();body.name="BatchedStaticCollision";body.collision_layer=1;root.add_child(body)
    else:
        body=StaticBody3D.new();body.position=position;body.rotation=rotation;body.collision_layer=1;root.add_child(body)
    var local_position:=position if batched else Vector3.ZERO
    var local_rotation:=rotation if batched else Vector3.ZERO
    var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.position=local_position;mesh.rotation=local_rotation;mesh.material_override=material;body.add_child(mesh)
    var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;collision.position=local_position;collision.rotation=local_rotation;body.add_child(collision)


func _visual_box(root: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=size; mesh.mesh=box; mesh.position=position; mesh.material_override=material; root.add_child(mesh); return mesh


func _add_static_collision_box(root:Node3D,size:Vector3,position:Vector3,rotation:Vector3=Vector3.ZERO)->void:
    var body:=root.get_node_or_null("DetailCollision") as StaticBody3D
    if not body:
        body=StaticBody3D.new()
        body.name="DetailCollision"
        body.collision_layer=1
        root.add_child(body)
    var collision:=CollisionShape3D.new()
    var shape:=BoxShape3D.new()
    shape.size=size
    collision.shape=shape
    collision.position=position
    collision.rotation=rotation
    body.add_child(collision)


func _clear_root(root: Node) -> void:
    for child in root.get_children():
        # Avoid holding two complete prop/road/town sets during a zone swap.
        # These roots are rebuilt synchronously while gameplay is paused.
        child.free()


func _build_ponds(root: Node3D, ponds: Array, terrain_result: Dictionary) -> void:
    var terrain_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for pond in ponds:
        var center: Vector2 = pond.get("position", Vector2.ZERO)
        var radius: float = pond.get("radius", 70.0) * 1.18
        var water_height: float = pond.get("water_height", 1.2)
        var edge_points: Array[Vector3] = []
        var segments := 40
        for i in range(segments):
            var angle := TAU * float(i) / float(segments)
            var irregularity := 1.0 + sin(angle * 3.0 + center.x * 0.0017) * 0.11 + sin(angle * 7.0 + center.y * 0.0011) * 0.055
            var edge2 := center + Vector2(cos(angle), sin(angle)) * radius * irregularity
            var edge_ground: Vector3 = terrain_sampler.call(edge2.x, edge2.y)
            edge_points.append(Vector3(edge2.x, minf(water_height + 0.035, edge_ground.y + 0.055), edge2.y))
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        for i in range(segments):
            var next_i := (i + 1) % segments
            st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3(center.x, water_height + 0.035, center.y))
            st.set_uv(Vector2(0.5 + (edge_points[next_i].x - center.x) / (radius * 2.6), 0.5 + (edge_points[next_i].z - center.y) / (radius * 2.6))); st.add_vertex(edge_points[next_i])
            st.set_uv(Vector2(0.5 + (edge_points[i].x - center.x) / (radius * 2.6), 0.5 + (edge_points[i].z - center.y) / (radius * 2.6))); st.add_vertex(edge_points[i])
        st.generate_normals()
        var mesh := st.commit()
        var instance := MeshInstance3D.new()
        instance.name = "%s_Water" % pond.get("name", "Pond")
        instance.mesh = mesh
        instance.material_override = _make_water_material()
        root.add_child(instance)


func _build_waterfalls(root: Node3D, sites: Array) -> void:
    for site in sites:
        var point: Vector2 = site.get("position", Vector2.ZERO)
        var width: float = site.get("width", 70.0)
        var drop: float = site.get("drop", 3.0)
        var upper_grade := 2.4 + point.x * 0.00042 + sin(point.x * 0.003) * 0.08
        if point.x > -1125.0:
            upper_grade += 3.2
        if point.x > 2075.0:
            upper_grade += 2.6
        var water_top := upper_grade - 0.6
        var cascade_mesh := BoxMesh.new()
        cascade_mesh.size = Vector3(0.45, drop, width)
        var cascade := MeshInstance3D.new()
        cascade.name = "%s_Cascade" % site.get("name", "Waterfall")
        cascade.mesh = cascade_mesh
        cascade.position = Vector3(point.x, water_top - drop * 0.5, point.y)
        cascade.material_override = _make_water_material()
        root.add_child(cascade)
        var foam_mesh := BoxMesh.new()
        foam_mesh.size = Vector3(5.0, 0.16, width * 0.92)
        var foam := MeshInstance3D.new()
        foam.mesh = foam_mesh
        foam.position = Vector3(point.x - 2.4, water_top - drop + 0.12, point.y)
        foam.material_override = _make_material(Color(0.76, 0.91, 0.94, 0.88), 0.24)
        root.add_child(foam)


func _build_rocks(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var world_size: float = profile.get("world_size", 600.0)
    var controlled: bool = profile.get("controlled_aqueduct", false)
    var rock_count := 1050 if controlled else 220
    var ore_specs:Array[Dictionary]=[
        {"id":"iron","name":"Iron Ore","color":Color(.34,.37,.39),"profile":Vector3(1.30,.70,1.00)},
        {"id":"copper","name":"Copper Ore","color":Color(.48,.285,.16),"profile":Vector3(1.12,.88,1.28)},
        {"id":"silver","name":"Silver Ore","color":Color(.58,.62,.63),"profile":Vector3(1.36,.62,.92)},
        {"id":"gold","name":"Gold Ore","color":Color(.58,.44,.13),"profile":Vector3(.96,.96,1.24)},
    ]
    var grouped_transforms:Array=[[],[],[],[]]
    var grouped_rocks:Array=[[],[],[],[]]
    var collision_body:=StaticBody3D.new()
    collision_body.name="MineableRockCollision"
    collision_body.collision_layer=1
    root.add_child(collision_body)
    var collision_registry:Array=root.get_meta("collision_prop_registry",[])
    var mineable_registry:Array=root.get_meta("mineable_rock_registry",[])
    var rock_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for i in range(rock_count):
        var angle := float(i) * 2.39996323
        var ring := (world_size * (0.08 + 0.38 * fmod(float(i * 47), 419.0) / 419.0)) if controlled else (850.0 + float((i * 173) % 2300))
        var point := Vector2(cos(angle), sin(angle)) * ring
        if absf(point.x) > world_size * 0.46 or absf(point.y) > world_size * 0.43:
            continue
        if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 26.0):
            continue
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
            continue
        if _is_too_close_to_sites(point, profile.get("town_sites", []), 90.0):
            continue
        var ground: Vector3 = rock_sampler.call(point.x, point.y)
        if ground.y <= terrain_result.water_level + 2.0:
            continue
        var scale_factor := (0.45 + float(i % 7) * 0.16) if controlled else (3.0 + float(i % 7) * 1.15)
        var roll:=(i*37)%20
        var ore_index:=0 if roll<9 else (1 if roll<15 else (2 if roll<19 else 3))
        var ore_spec:Dictionary=ore_specs[ore_index]
        var shape_profile:Vector3=ore_spec.profile
        var basis := Basis.from_euler(Vector3(float(i % 5) * 0.08, angle, float(i % 3) * 0.06))
        basis = basis.scaled(shape_profile*scale_factor)
        var transform:=Transform3D(basis,ground+Vector3(0.0,scale_factor*.55,0.0))
        grouped_transforms[ore_index].append(transform)
        var rock_data:={
            "kind":"mineable_rock",
            "ore_id":ore_spec.id,
            "ore_name":ore_spec.name,
            "ore_color":ore_spec.color,
            "position":ground+Vector3(0,scale_factor*.45,0),
            "ground_position":ground,
            "radius":scale_factor*.72,
            "scale":scale_factor,
            "active":true,
            "hits":0,
        }
        var collision:=CollisionShape3D.new()
        var shape:=SphereShape3D.new()
        shape.radius=maxf(.70,scale_factor*.72)
        collision.shape=shape
        collision.position=rock_data.position
        collision_body.add_child(collision)
        rock_data["collision_shape"]=collision
        rock_data["direct_collision"]=true
        collision_registry.append(rock_data)
        mineable_registry.append(rock_data)
        grouped_rocks[ore_index].append(rock_data)
    root.set_meta("collision_prop_registry",collision_registry)
    root.set_meta("mineable_rock_registry",mineable_registry)
    # Four spatially batched silhouettes make metal deposits recognizable in
    # the field without turning hundreds of rocks into individual draw calls.
    for ore_index in range(ore_specs.size()):
        var rock_mesh:=SphereMesh.new()
        rock_mesh.radius=1.0
        rock_mesh.height=1.7+float(ore_index%2)*.16
        rock_mesh.radial_segments=6+ore_index
        rock_mesh.rings=3+int(ore_index/2)
        var ore_spec:Dictionary=ore_specs[ore_index]
        var ore_transforms:Array[Transform3D]=[]
        ore_transforms.assign(grouped_transforms[ore_index])
        var source_map:=_add_material_multimesh(
            root,rock_mesh,ore_transforms,
            _make_material(ore_spec.color,1.0),false,900.0,520.0
        )
        var rock_group:Array=grouped_rocks[ore_index]
        for local_index in range(rock_group.size()):
            if source_map.has(local_index):rock_group[local_index]["batched_part"]=source_map[local_index]


func _build_grass(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    if not profile.get("controlled_aqueduct", false):
        return
    var blade_mesh := _make_ground_cover_mesh()
    var entries: Array[Transform3D] = []
    var world_size: float = profile.get("world_size", 600.0)
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    var grass_rng:=RandomNumberGenerator.new()
    grass_rng.seed=99173
    for i in range(18000):
        var point:=Vector2(
            grass_rng.randf_range(-world_size*.46,world_size*.46),
            grass_rng.randf_range(-world_size*.46,world_size*.46)
        )
        if _is_dry_biome(point,world_size):continue
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
            continue
        if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 2.0):
            continue
        if _is_too_close_to_corridors(point, profile.get("trail_corridors", []), 0.8):
            continue
        if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
            continue
        if _is_on_stone_walkway(point,profile):
            continue
        if point.distance_to(profile.get("spawn_site", {}).get("position", Vector2.ZERO)) < 6.0:
            continue
        var ground: Vector3 = raw_sampler.call(point.x, point.y)
        if ground.y<=float(terrain_result.water_level)+.7:continue
        var scale_factor:=grass_rng.randf_range(.64,1.12)
        var basis:=Basis(Vector3.UP,grass_rng.randf_range(-PI,PI)).scaled(Vector3(scale_factor*grass_rng.randf_range(.9,1.25),scale_factor,scale_factor))
        entries.append(Transform3D(basis, ground + Vector3(0.0, 0.015, 0.0)))
    var grass_material := _make_material(Color(0.16, 0.29, 0.11, 1.0), 0.98).duplicate() as StandardMaterial3D
    grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    # The old realm-wide grass MultiMesh submitted all fourteen thousand
    # blades whenever any part of its huge bounds was visible. Chunking it is
    # the largest safe movement-performance win in this pass.
    _add_material_multimesh(root,blade_mesh,entries,grass_material,false,310.0,360.0)


func _make_grass_tuft_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var height := 0.24
    var half_width := 0.075
    for angle in [0.0, 1.0472, 2.0944]:
        var side := Vector3(cos(angle), 0.0, sin(angle)) * half_width
        var lean := Vector3(-sin(angle), 0.0, cos(angle)) * 0.035
        st.add_vertex(-side)
        st.add_vertex(side)
        st.add_vertex(Vector3(lean.x, height, lean.z))
    st.generate_normals()
    return st.commit()


func _make_ground_cover_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # A tuft is made from broad, curved tapering leaves. It rises visibly from
    # the ground without reverting to the thin vertical boxes that looked like
    # green sticks and shimmered during movement.
    for i in range(9):
        var angle:=float(i)*TAU/9.0+float(i%2)*.13
        var direction := Vector3(cos(angle), 0.0, sin(angle))
        var side := Vector3(-direction.z, 0.0, direction.x)
        var height:=.28+float(i%4)*.055
        var root_center:=direction*.025
        var middle:=direction*(.08+float(i%3)*.018)+Vector3.UP*height*.52
        var tip:=direction*(.17+float(i%2)*.035)+Vector3.UP*height
        var root_width:=.045+float(i%3)*.008
        var middle_width:=root_width*.74
        var root_left:=root_center+side*root_width
        var root_right:=root_center-side*root_width
        var mid_left:=middle+side*middle_width
        var mid_right:=middle-side*middle_width
        st.add_vertex(root_left);st.add_vertex(root_right);st.add_vertex(mid_right)
        st.add_vertex(root_left);st.add_vertex(mid_right);st.add_vertex(mid_left)
        st.add_vertex(mid_left);st.add_vertex(mid_right);st.add_vertex(tip)
    st.generate_normals()
    return st.commit()


func _build_traversal_ground_cover(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var tuft_mesh := _make_ground_cover_mesh()
    var green: Array[Transform3D] = []
    var dry: Array[Transform3D] = []
    var corridors: Array = []
    corridors.append_array(profile.get("road_corridors", []))
    corridors.append_array(profile.get("trail_corridors", []))
    var sample_index := 0
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for corridor in corridors:
        var points: Array = corridor.get("points", [])
        var half_width := float(corridor.get("width", 8.0)) * 0.5
        for segment_index in range(points.size() - 1):
            var a: Vector2 = points[segment_index]
            var b: Vector2 = points[segment_index + 1]
            var segment: Vector2 = b - a
            var length: float = segment.length()
            if length <= 0.01:
                continue
            var tangent: Vector2 = segment / length
            var normal: Vector2 = Vector2(-tangent.y, tangent.x)
            var steps: int = maxi(1, int(ceil(length / 16.0)))
            for step in range(steps):
                var t: float = (float(step) + 0.5) / float(steps)
                var center: Vector2 = a.lerp(b, t)
                for side in [-1.0, 1.0]:
                    for row in range(2):
                        var seed: float = float(sample_index * 37 + row * 19 + segment_index * 11)
                        var lateral: float = half_width + 3.2 + float(row) * 5.4 + (sin(seed * 1.73) + 1.0) * 1.6
                        var along_jitter: float = cos(seed * 0.91) * 4.2
                        var point: Vector2 = center + normal * lateral * float(side) + tangent * along_jitter
                        sample_index += 1
                        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
                            continue
                        if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 0.8):
                            continue
                        if _is_too_close_to_corridors(point, profile.get("trail_corridors", []), 0.35):
                            continue
                        if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
                            continue
                        if _is_on_stone_walkway(point,profile):
                            continue
                        var ground: Vector3 = raw_sampler.call(point.x, point.y)
                        if ground.y <= float(terrain_result.water_level) + 0.8:
                            continue
                        var scale_factor: float = 0.72 + fmod(absf(sin(seed * 0.37)) * 1.4, 0.68)
                        var yaw: float = seed * 0.63
                        var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale_factor * 1.25, scale_factor, scale_factor))
                        var transform: Transform3D = Transform3D(basis, ground + Vector3.UP * 0.018)
                        if int(seed) % 5 == 0:
                            dry.append(transform)
                        else:
                            green.append(transform)
    _add_ground_cover_batch(root, tuft_mesh, green, Color(0.18, 0.32, 0.12, 1.0))
    _add_ground_cover_batch(root, tuft_mesh, dry, Color(0.36, 0.31, 0.14, 1.0))


func _build_meadow_floor_detail(root:Node3D,profile:Dictionary,terrain_result:Dictionary)->void:
    # A seeded random field replaces the modular X/Z lattice and the
    # golden-angle destination spirals. A low-density baseline spans the
    # entire green realm, while independently scattered meadow and forest
    # samples raise density where players actually travel. Their edges feather
    # into the baseline rather than ending at a visible circle.
    var source:=MEADOW_GRASS_SCENE.instantiate()
    var mesh:=_find_first_mesh_resource(source)
    source.free()
    if mesh==null:mesh=_make_ground_cover_mesh()
    mesh=_make_scattered_grass_patch_mesh(mesh)
    var green:Array[Transform3D]=[]
    var dry:Array[Transform3D]=[]
    var world_size:float=profile.get("world_size",7200.0)
    var sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var spawn:Vector2=profile.get("spawn_site",{}).get("position",Vector2.ZERO)
    var grass_rng:=RandomNumberGenerator.new()
    grass_rng.seed=481516

    # Baseline coverage: deliberately irregular and present beyond the named
    # meadow circles, including beneath scattered woodland.
    # Each accepted instance contains seven separately offset grass clumps.
    # The former 36k baseline oversampled the same visible area and spent
    # several seconds on corridor queries during every launch.
    for i in range(24000):
        var point:=Vector2(
            grass_rng.randf_range(-world_size*.455,world_size*.455),
            grass_rng.randf_range(-world_size*.455,world_size*.455)
        )
        if _is_dry_biome(point,world_size):continue
        if _is_too_close_to_corridors(point,profile.get("river_corridors",[]),50.0):continue
        if _is_too_close_to_corridors(point,profile.get("road_corridors",[]),2.5):continue
        if _is_too_close_to_corridors(point,profile.get("trail_corridors",[]),1.0):continue
        if _is_near_bridge_site(point,profile.get("ford_sites",[]),72.0):continue
        if _is_on_stone_walkway(point,profile):continue
        var ground:Vector3=sampler.call(point.x,point.y)
        if ground.y<=float(terrain_result.water_level)+.7:continue
        var scale_value:=grass_rng.randf_range(.78,1.34)
        var yaw:=grass_rng.randf_range(-PI,PI)
        var basis:=Basis(Vector3.UP,yaw).scaled(Vector3(scale_value*grass_rng.randf_range(1.05,1.34),scale_value*grass_rng.randf_range(.92,1.24),scale_value))
        var transform:=Transform3D(basis,ground+Vector3.UP*.018)
        if grass_rng.randf()<.16:dry.append(transform)
        else:green.append(transform)

    # Travel-area meadows are larger than the old 96 m circle and fade through
    # their outer third. This removes the obvious "grass stops here" boundary.
    var destinations:Array=[profile.get("spawn_site",{})]
    destinations.append_array(profile.get("town_sites",[]))
    for site_index in range(destinations.size()):
        var site:Dictionary=destinations[site_index]
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:float=float(site.get("radius",72.0))
        var inner_radius:=16.0 if site_index==0 else radius*.48
        var outer_radius:=maxf(280.0 if site_index==0 else 170.0,radius*1.42)
        var sample_count:=4800 if site_index==0 else 2800
        for local_index in range(sample_count):
            var ratio:=sqrt(grass_rng.randf())
            var edge_weight:=clampf((1.0-ratio)/.30,0.0,1.0)
            if ratio>.70 and grass_rng.randf()>edge_weight:continue
            var radial:=lerpf(inner_radius,outer_radius,ratio)
            var angle:=grass_rng.randf_range(-PI,PI)
            var point:=center+Vector2(cos(angle),sin(angle))*radial
            if _is_dry_biome(point,world_size):continue
            if _is_too_close_to_corridors(point,profile.get("river_corridors",[]),50.0):continue
            if _is_too_close_to_corridors(point,profile.get("road_corridors",[]),2.5):continue
            if _is_too_close_to_corridors(point,profile.get("trail_corridors",[]),1.0):continue
            if _is_near_bridge_site(point,profile.get("ford_sites",[]),72.0):continue
            if _is_on_stone_walkway(point,profile):continue
            var ground:Vector3=sampler.call(point.x,point.y)
            if ground.y<=float(terrain_result.water_level)+.7:continue
            var scale_value:=grass_rng.randf_range(.82,1.30)
            var yaw:=grass_rng.randf_range(-PI,PI)
            var basis:=Basis(Vector3.UP,yaw).scaled(Vector3(scale_value*grass_rng.randf_range(1.08,1.38),scale_value*grass_rng.randf_range(1.0,1.22),scale_value))
            var transform:=Transform3D(basis,ground+Vector3.UP*.018)
            if grass_rng.randf()<.10:dry.append(transform)
            else:green.append(transform)

    # Forest cores receive their own uncorrelated grass distribution, so
    # entering the trees no longer makes all upright ground cover disappear.
    for forest in profile.get("forest_regions",[]):
        var center:Vector2=forest.get("center",Vector2.ZERO)
        var radius:float=forest.get("radius",260.0)
        var forest_samples:=maxi(1800,roundi(radius*10.0))
        for local_index in range(forest_samples):
            var ratio:=sqrt(grass_rng.randf())
            if ratio>.76 and grass_rng.randf()>clampf((1.0-ratio)/.24,0.0,1.0):continue
            var angle:=grass_rng.randf_range(-PI,PI)
            var point:=center+Vector2(cos(angle),sin(angle))*radius*ratio
            if _is_dry_biome(point,world_size):continue
            if _is_too_close_to_corridors(point,profile.get("river_corridors",[]),50.0):continue
            if _is_too_close_to_corridors(point,profile.get("road_corridors",[]),2.5):continue
            if _is_too_close_to_sites(point,profile.get("pond_sites",[]),4.0):continue
            if _is_on_stone_walkway(point,profile):continue
            var ground:Vector3=sampler.call(point.x,point.y)
            if ground.y<=float(terrain_result.water_level)+.7:continue
            var scale_value:=grass_rng.randf_range(.74,1.16)
            var yaw:=grass_rng.randf_range(-PI,PI)
            var basis:=Basis(Vector3.UP,yaw).scaled(Vector3(scale_value*grass_rng.randf_range(1.0,1.28),scale_value,scale_value))
            var transform:=Transform3D(basis,ground+Vector3.UP*.018)
            if grass_rng.randf()<.22:dry.append(transform)
            else:green.append(transform)
    _add_ground_cover_batch(root,mesh,green,Color(.15,.29,.105,1.0))
    _add_ground_cover_batch(root,mesh,dry,Color(.38,.32,.15,1.0))
    root.set_meta("meadow_grass_count",green.size()+dry.size())


func _make_scattered_grass_patch_mesh(source_mesh:Mesh)->ArrayMesh:
    if _meadow_grass_patch_mesh!=null:return _meadow_grass_patch_mesh
    # One MultiMesh instance contains an irregular micro-patch instead of one
    # lonely clump. This makes green land read as grassland without needing
    # millions of realm-wide instances, and the offsets contain no rows.
    var offsets:Array=[
        [Vector3.ZERO,0.0,1.0],
        [Vector3(1.62,0.0,.48),.71,.86],
        [Vector3(-1.38,0.0,.92),-1.17,.94],
        [Vector3(.43,0.0,-1.73),2.04,.78],
        [Vector3(-.92,0.0,-1.46),-2.48,1.08],
        [Vector3(2.08,0.0,-1.10),1.46,.72],
        [Vector3(-2.14,0.0,-.61),-.39,.81]
    ]
    var st:=SurfaceTool.new()
    for patch in offsets:
        var offset:Vector3=patch[0]
        var yaw:float=patch[1]
        var scale_value:float=patch[2]
        var transform:=Transform3D(
            Basis(Vector3.UP,yaw).scaled(Vector3(scale_value,scale_value,scale_value)),
            offset
        )
        for surface_index in range(source_mesh.get_surface_count()):
            st.append_from(source_mesh,surface_index,transform)
    _meadow_grass_patch_mesh=st.commit()
    return _meadow_grass_patch_mesh


func _build_forest_leaf_litter(root:Node3D,terrain_result:Dictionary)->void:
    var registry:Array=root.get_meta("harvestable_tree_registry",[])
    if registry.is_empty():return
    var leaf_mesh:=_make_leaf_litter_mesh()
    var brown:Array[Transform3D]=[]
    var ochre:Array[Transform3D]=[]
    var dark:Array[Transform3D]=[]
    var sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var litter_rng:=RandomNumberGenerator.new()
    litter_rng.seed=739391
    for tree_value in registry:
        if not tree_value is Dictionary:continue
        var tree:Dictionary=tree_value
        var ground:Vector3=tree.get("position",Vector3.ZERO)
        var scale_value:=clampf(float(tree.get("scale",1.0)),.58,1.65)
        var kind:=str(tree.get("kind","broadleaf"))
        var scatter_count:=3 if kind=="broadleaf" else 1
        for scatter_index in range(scatter_count):
            var angle:=litter_rng.randf_range(-PI,PI)
            var distance:=litter_rng.randf_range(.28,2.2)*scale_value
            var point:=Vector2(ground.x+cos(angle)*distance,ground.z+sin(angle)*distance)
            var litter_ground:Vector3=sampler.call(point.x,point.y)
            var s:=litter_rng.randf_range(.78,1.28)*scale_value
            var basis:=Basis(Vector3.UP,litter_rng.randf_range(-PI,PI)).scaled(Vector3(s,s,s))
            var transform:=Transform3D(basis,litter_ground+Vector3.UP*.026)
            if kind=="conifer":dark.append(transform)
            elif litter_rng.randf()<.34:ochre.append(transform)
            else:brown.append(transform)
    _add_leaf_litter_batch(root,leaf_mesh,brown,Color(.34,.19,.075))
    _add_leaf_litter_batch(root,leaf_mesh,ochre,Color(.52,.31,.075))
    _add_leaf_litter_batch(root,leaf_mesh,dark,Color(.20,.145,.07))
    root.set_meta("leaf_litter_count",brown.size()+ochre.size()+dark.size())


func _make_leaf_litter_mesh()->ArrayMesh:
    if _leaf_litter_mesh!=null:return _leaf_litter_mesh
    var st:=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(13):
        var angle:=float(i)*2.399963+sin(float(i)*1.71)*.38
        var radius:=.22+float(i%5)*.31
        var center:=Vector3(cos(angle)*radius,.003+float(i%3)*.002,sin(angle)*radius)
        var forward:=Vector3(cos(angle*.73),0,sin(angle*.73))
        var side:=Vector3(-forward.z,0,forward.x)
        var length:=.15+float(i%4)*.024
        var width:=length*(.46+float(i%3)*.06)
        var tip:=center+forward*length
        var tail:=center-forward*length*.72
        var left:=center+side*width+Vector3.UP*.006
        var right:=center-side*width+Vector3.UP*.006
        for vertex in [tail,left,tip,tail,tip,right]:st.add_vertex(vertex)
    st.generate_normals()
    _leaf_litter_mesh=st.commit()
    return _leaf_litter_mesh


func _add_leaf_litter_batch(root:Node3D,mesh:Mesh,transforms:Array[Transform3D],color:Color)->void:
    var material:=_make_material(color,1.0).duplicate() as StandardMaterial3D
    material.cull_mode=BaseMaterial3D.CULL_DISABLED
    _add_material_multimesh(root,mesh,transforms,material,false,170.0,180.0)


func _find_first_mesh_resource(node:Node)->Mesh:
    if node is MeshInstance3D:return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var found:=_find_first_mesh_resource(child)
        if found!=null:return found
    return null


func _build_bushes(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var world_size: float = profile.get("world_size", 7200.0)
    var leaf_mesh:=_make_shrub_leaf_mesh()
    var branch_mesh:=_make_shrub_branch_mesh()
    var dark_transforms:Array[Transform3D]=[]
    var light_transforms:Array[Transform3D]=[]
    var branch_transforms:Array[Transform3D]=[]
    var collision_registry:Array=root.get_meta("collision_prop_registry",[])
    var collision_body:=StaticBody3D.new()
    collision_body.name="BushCollision"
    collision_body.collision_layer=1
    root.add_child(collision_body)
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    # Each shrub is one batched branching frame plus a cluster of individual
    # angular leaf bunches. This keeps the silhouette open and woody instead
    # of reading as three green boulders.
    for i in range(1450):
        var x := world_size * (fmod(float(i * 193), 1451.0) / 1451.0 - 0.5) * 0.90
        var z := world_size * (fmod(float(i * 317), 1453.0) / 1453.0 - 0.5) * 0.90
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
            continue
        if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 4.0):
            continue
        if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
            continue
        if point.distance_to(profile.get("spawn_site", {}).get("position", Vector2.ZERO)) < 24.0:
            continue
        var ground: Vector3 = raw_sampler.call(x, z)
        var s:=1.10+float(i%7)*.12
        var yaw:=float(i)*.73
        var facing:=Vector3(cos(yaw),0,sin(yaw))
        var across:=Vector3(-facing.z,0,facing.x)
        var shrub_basis:=Basis(Vector3.UP,yaw).scaled(Vector3(s*1.28,s,s*1.10))
        var shrub_transform:=Transform3D(shrub_basis,ground)
        branch_transforms.append(shrub_transform)
        if i%4==0:light_transforms.append(shrub_transform)
        else:dark_transforms.append(shrub_transform)
        var collision:=CollisionShape3D.new()
        var shape:=SphereShape3D.new()
        shape.radius=maxf(.62,1.02*s)
        collision.shape=shape
        collision.position=ground+Vector3(0,.62*s,0)
        collision_body.add_child(collision)
        collision_registry.append({"kind":"bush","position":collision.position,"radius":shape.radius,"active":true,"direct_collision":true})
    root.set_meta("collision_prop_registry",collision_registry)
    _add_multimesh_batch(root,branch_mesh,branch_transforms,Color(.24,.12,.055,1.0),false)
    _add_multimesh_batch(root,leaf_mesh,dark_transforms,Color(.12,.31,.085,1.0))
    _add_multimesh_batch(root,leaf_mesh,light_transforms,Color(.27,.43,.12,1.0),false)


func _make_shrub_leaf_mesh()->ArrayMesh:
    if _shrub_leaf_mesh!=null:return _shrub_leaf_mesh
    var st:=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var centers:Array[Vector3]=[
        Vector3(0,.72,0),Vector3(.46,.61,.08),Vector3(-.43,.58,.16),
        Vector3(.18,.92,-.34),Vector3(-.18,.88,-.30),Vector3(.62,.45,-.22),
        Vector3(-.60,.43,-.18),Vector3(.34,.42,.39),Vector3(-.31,.40,.41),
    ]
    for i in range(centers.size()):
        var extents:=Vector3(.34+float(i%3)*.045,.34+float(i%2)*.055,.28+float((i+1)%3)*.035)
        _append_octahedron(st,centers[i],extents)
    st.generate_normals()
    _shrub_leaf_mesh=st.commit()
    return _shrub_leaf_mesh


func _make_shrub_branch_mesh()->ArrayMesh:
    if _shrub_branch_mesh!=null:return _shrub_branch_mesh
    var st:=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for end in [
        Vector3(.48,.68,.10),Vector3(-.46,.65,.16),Vector3(.18,.94,-.28),
        Vector3(-.20,.88,-.27),Vector3(.32,.53,.38),Vector3(-.35,.50,.36),
    ]:
        _append_tapered_branch(st,Vector3(0,.06,0),end,.055,.022)
    st.generate_normals()
    _shrub_branch_mesh=st.commit()
    return _shrub_branch_mesh


func _append_octahedron(st:SurfaceTool,center:Vector3,extents:Vector3)->void:
    var top:=center+Vector3.UP*extents.y
    var bottom:=center-Vector3.UP*extents.y
    var ring:Array[Vector3]=[
        center+Vector3(extents.x,0,0),center+Vector3(0,0,extents.z),
        center-Vector3(extents.x,0,0),center-Vector3(0,0,extents.z),
    ]
    for i in range(4):
        var next:=(i+1)%4
        st.add_vertex(top);st.add_vertex(ring[i]);st.add_vertex(ring[next])
        st.add_vertex(bottom);st.add_vertex(ring[next]);st.add_vertex(ring[i])


func _append_tapered_branch(st:SurfaceTool,start:Vector3,finish:Vector3,start_radius:float,end_radius:float)->void:
    var direction:=(finish-start).normalized()
    var axis_a:=direction.cross(Vector3.FORWARD).normalized()
    if axis_a.length_squared()<.1:axis_a=direction.cross(Vector3.RIGHT).normalized()
    var axis_b:=direction.cross(axis_a).normalized()
    var start_ring:Array[Vector3]=[
        start+axis_a*start_radius,start+axis_b*start_radius,
        start-axis_a*start_radius,start-axis_b*start_radius,
    ]
    var end_ring:Array[Vector3]=[
        finish+axis_a*end_radius,finish+axis_b*end_radius,
        finish-axis_a*end_radius,finish-axis_b*end_radius,
    ]
    for i in range(4):
        var next:=(i+1)%4
        st.add_vertex(start_ring[i]);st.add_vertex(start_ring[next]);st.add_vertex(end_ring[next])
        st.add_vertex(start_ring[i]);st.add_vertex(end_ring[next]);st.add_vertex(end_ring[i])


func _build_wildflowers(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var world_size: float = profile.get("world_size", 7200.0)
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.09, 0.38, 0.09)
    var gold: Array[Transform3D] = []
    var purple: Array[Transform3D] = []
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for i in range(2600):
        var x := world_size * (fmod(float(i * 157), 2609.0) / 2609.0 - 0.5) * 0.88
        var z := world_size * (fmod(float(i * 283), 2617.0) / 2617.0 - 0.5) * 0.88
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
            continue
        if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
            continue
        var ground: Vector3 = raw_sampler.call(x, z)
        var transform := Transform3D(Basis(Vector3.UP, float(i) * 1.17), ground + Vector3(0.0, 0.19, 0.0))
        if i % 3 == 0:
            purple.append(transform)
        else:
            gold.append(transform)
    _add_multimesh_batch(root, mesh, gold, Color(0.82, 0.62, 0.12, 1.0), false)
    _add_multimesh_batch(root, mesh, purple, Color(0.46, 0.24, 0.62, 1.0), false)


func _build_river_reeds(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.07, 0.85, 0.07)
    var transforms: Array[Transform3D] = []
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for river in profile.get("river_corridors", []):
        var points: Array = river.get("points", [])
        var width: float = river.get("width", 50.0)
        for segment_idx in range(points.size() - 1):
            var a: Vector2 = points[segment_idx]
            var b: Vector2 = points[segment_idx + 1]
            var tangent := (b - a).normalized()
            var normal := Vector2(-tangent.y, tangent.x)
            for j in range(12):
                var t := (float(j) + 0.35) / 12.0
                var center := a.lerp(b, t)
                for side in [-1.0, 1.0]:
                    var offset := width * 0.5 + 2.5 + float((j * 7 + segment_idx * 3) % 5)
                    var point := center + normal * offset * float(side)
                    if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
                        continue
                    var ground: Vector3 = raw_sampler.call(point.x, point.y)
                    var s := 0.75 + float((j + segment_idx) % 5) * 0.10
                    var basis := Basis(Vector3.UP, float(j) * 0.91).scaled(Vector3(s, s, s))
                    transforms.append(Transform3D(basis, ground + Vector3(0.0, 0.42 * s, 0.0)))
    _add_multimesh_batch(root, mesh, transforms, Color(0.18, 0.31, 0.075, 1.0), false)


func _add_multimesh_batch(root: Node3D, mesh: Mesh, transforms: Array[Transform3D], color: Color, cast_shadows: bool = true) -> void:
    if transforms.is_empty():
        return
    # Small world dressing is only useful near the player. Spatial cells stop
    # realm-wide bushes, reeds, stones, flowers and loose branches from being
    # submitted to the GPU on every frame.
    _add_material_multimesh(root,mesh,transforms,_make_material(color,.96),cast_shadows,900.0,520.0)


func _add_ground_cover_batch(root: Node3D, mesh: Mesh, transforms: Array[Transform3D], color: Color) -> void:
    if transforms.is_empty():
        return
    var material := _make_material(color, 1.0).duplicate() as StandardMaterial3D
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _add_material_multimesh(root,mesh,transforms,material,false,320.0,360.0)


func _build_fallen_logs(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.22
    mesh.bottom_radius = 0.30
    mesh.height = 3.4
    mesh.radial_segments = 7
    var transforms: Array[Transform3D] = []
    var log_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for region in profile.get("forest_regions", []):
        var center: Vector2 = region.get("center", Vector2.ZERO)
        var radius: float = region.get("radius", 300.0)
        for i in range(32):
            var angle := float(i) * 2.39996323 + center.x * 0.001
            var point := center + Vector2(cos(angle), sin(angle)) * radius * (0.18 + float(i % 7) * 0.10)
            if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
                continue
            if _is_near_bridge_site(point, profile.get("ford_sites", []), 76.0):
                continue
            if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 5.0):
                continue
            var ground: Vector3 = log_sampler.call(point.x, point.y)
            var basis := Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, angle)
            basis = basis.scaled(Vector3(0.8 + float(i % 3) * 0.16, 1.0, 0.8))
            transforms.append(Transform3D(basis, ground + Vector3(0.0, 0.28, 0.0)))
    _add_multimesh_batch(root, mesh, transforms, Color(0.30, 0.18, 0.085, 1.0))


func _build_ground_stones(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 0.24
    mesh.height = 0.32
    mesh.radial_segments = 6
    mesh.rings = 3
    var transforms: Array[Transform3D] = []
    var world_size: float = profile.get("world_size", 7200.0)
    var stone_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for i in range(2600):
        var x := world_size * (fmod(float(i * 211), 2609.0) / 2609.0 - 0.5) * 0.90
        var z := world_size * (fmod(float(i * 359), 2621.0) / 2621.0 - 0.5) * 0.90
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 48.0):
            continue
        if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 0.8):
            continue
        if point.distance_to(profile.get("spawn_site", {}).get("position", Vector2.ZERO)) < 14.0:
            continue
        var ground: Vector3 = stone_sampler.call(x, z)
        var s := 0.55 + float(i % 6) * 0.13
        var basis := Basis(Vector3.UP, float(i) * 0.91).scaled(Vector3(s * 1.25, s * 0.62, s))
        transforms.append(Transform3D(basis, ground + Vector3(0.0, 0.10 * s, 0.0)))
    _add_multimesh_batch(root, mesh, transforms, Color(0.48, 0.46, 0.40, 1.0), false)


func _build_rock_formations(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 1.7
    mesh.radial_segments = 7
    mesh.rings = 4
    var transforms: Array[Transform3D] = []
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for chain in profile.get("mountain_chains", []):
        var center: Vector2 = chain.get("center", Vector2.ZERO)
        var width: float = chain.get("width", 300.0)
        for cluster in range(7):
            var cluster_angle := float(cluster) * 2.39996323
            var cluster_center := center + Vector2(cos(cluster_angle), sin(cluster_angle)) * width * (0.28 + float(cluster % 3) * 0.16)
            for stone in range(5):
                var angle := cluster_angle + float(stone) * 1.2566
                var point := cluster_center + Vector2(cos(angle), sin(angle)) * (3.0 + float(stone % 3) * 2.8)
                var ground: Vector3 = raw_sampler.call(point.x, point.y)
                var s := 1.6 + float((cluster + stone) % 5) * 0.72
                var basis := Basis(Vector3.UP, angle).scaled(Vector3(s * 1.35, s * (0.75 + float(stone % 2) * 0.22), s))
                transforms.append(Transform3D(basis, ground + Vector3(0.0, s * 0.62, 0.0)))
    _add_multimesh_batch(root, mesh, transforms, Color(0.43, 0.43, 0.39, 1.0))


func _build_flower_meadows(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.085
    head_mesh.height = 0.13
    head_mesh.radial_segments = 5
    head_mesh.rings = 3
    var gold: Array[Transform3D] = []
    var blue: Array[Transform3D] = []
    var white: Array[Transform3D] = []
    var stems:Array[Transform3D]=[]
    var leaf_tufts:Array[Transform3D]=[]
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    var centers:Array[Vector2]=[Vector2(-610.0, 360.0), Vector2(280.0, 520.0), Vector2(760.0, -520.0), Vector2(-690.0, 1320.0), Vector2(1180.0, -980.0)]
    centers.append(profile.get("spawn_site",{}).get("position",Vector2.ZERO)+Vector2(46,34))
    for town in profile.get("town_sites",[]):
        var town_center:Vector2=town.get("position",Vector2.ZERO)
        centers.append(town_center+Vector2(float(31+(centers.size()%3)*14),float(-26+(centers.size()%2)*49)))
    for meadow_idx in range(centers.size()):
        var center: Vector2 = centers[meadow_idx]
        for i in range(420):
            var angle := float(i) * 2.39996323
            var radius := 18.0 + sqrt(float(i) / 420.0) * (78.0 + float(meadow_idx % 3) * 18.0)
            var point := center + Vector2(cos(angle), sin(angle)) * radius
            if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 50.0):
                continue
            if _is_too_close_to_corridors(point, profile.get("trail_corridors", []), 1.5):
                continue
            if _is_too_close_to_corridors(point, profile.get("road_corridors", []), 2.0):
                continue
            var ground: Vector3 = raw_sampler.call(point.x, point.y)
            var s := 0.75 + float(i % 4) * 0.12
            var stem_height:=.36+float(i%4)*.045
            var yaw:=float(i)*1.713
            stems.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(s,stem_height,s)),ground+Vector3.UP*stem_height*.5))
            leaf_tufts.append(Transform3D(Basis(Vector3.UP,-yaw*.73).scaled(Vector3(s*.42,s*.34,s*.42)),ground+Vector3.UP*.01))
            var transform := Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(s, s, s)), ground + Vector3(0.0, stem_height+.035, 0.0))
            if i % 7 == 0:
                blue.append(transform)
            elif i % 3 == 0:
                white.append(transform)
            else:
                gold.append(transform)
    var stem_mesh:=CylinderMesh.new();stem_mesh.top_radius=.014;stem_mesh.bottom_radius=.021;stem_mesh.height=1.0;stem_mesh.radial_segments=5
    _add_material_multimesh(root,stem_mesh,stems,_make_material(Color(.19,.34,.10),1.0),false,210.0,180.0)
    _add_ground_cover_batch(root,_make_ground_cover_mesh(),leaf_tufts,Color(.17,.31,.10))
    _add_multimesh_batch(root, head_mesh, gold, Color(0.86, 0.58, 0.07, 1.0), false)
    _add_multimesh_batch(root, head_mesh, blue, Color(0.25, 0.36, 0.66, 1.0), false)
    _add_multimesh_batch(root, head_mesh, white, Color(0.78, 0.78, 0.66, 1.0), false)


func _build_flowering_shrubs(root:Node3D,profile:Dictionary,terrain_result:Dictionary)->void:
    # Low leafy plants with visible blossoms replace the old bare green-stick
    # treatment. Each plant has a broad crown and several raised flower heads.
    var world_size:float=profile.get("world_size",7200.0)
    var raw_sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var leaf_mesh:=_get_broadleaf_canopy_mesh();var head_mesh:=SphereMesh.new();head_mesh.radius=.075;head_mesh.height=.11;head_mesh.radial_segments=6;head_mesh.rings=3
    var leaves:Array[Transform3D]=[];var gold:Array[Transform3D]=[];var rose:Array[Transform3D]=[];var blue:Array[Transform3D]=[]
    for i in range(1350):
        var x:=world_size*(fmod(float(i*173),1361.0)/1361.0-.5)*.86
        var z:=world_size*(fmod(float(i*317),1367.0)/1367.0-.5)*.86
        var point:=Vector2(x,z)
        if _is_too_close_to_corridors(point,profile.get("river_corridors",[]),48.0) or _is_too_close_to_corridors(point,profile.get("road_corridors",[]),5.0) or _is_near_bridge_site(point,profile.get("ford_sites",[]),76.0):continue
        var ground:Vector3=raw_sampler.call(x,z);var s:=.24+float(i%6)*.045;var yaw:=float(i)*2.39996323
        leaves.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(s*1.55,s*.72,s*1.35)),ground+Vector3.UP*(s*.72)))
        for blossom in range(3):
            var angle:=yaw+float(blossom)*TAU/3.0;var offset:=Vector3(cos(angle)*s*.70,s*.95+float(blossom%2)*.07,sin(angle)*s*.70)
            var transform:=Transform3D(Basis().scaled(Vector3.ONE*(.75+float((i+blossom)%3)*.12)),ground+offset)
            if (i+blossom)%7==0:blue.append(transform)
            elif (i+blossom)%3==0:rose.append(transform)
            else:gold.append(transform)
    _add_material_multimesh(root,leaf_mesh,leaves,_make_foliage_material(Color(.16,.34,.11)),false,260.0,420.0)
    _add_multimesh_batch(root,head_mesh,gold,Color(.92,.67,.10),false)
    _add_multimesh_batch(root,head_mesh,rose,Color(.72,.20,.30),false)
    _add_multimesh_batch(root,head_mesh,blue,Color(.28,.42,.78),false)


func _build_stone_landmarks(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.2, 4.8, 0.85)
    var transforms: Array[Transform3D] = []
    var centers := [Vector2(-930.0, 850.0), Vector2(580.0, 720.0), Vector2(1380.0, -1260.0), Vector2(-420.0, 2780.0)]
    for center_idx in range(centers.size()):
        var center: Vector2 = centers[center_idx]
        for i in range(7):
            var angle := float(i) / 7.0 * TAU
            var point := center + Vector2(cos(angle), sin(angle)) * (14.0 + float(center_idx) * 2.0)
            var ground: Vector3 = terrain_result.height_sampler.call(point.x, point.y)
            var s := 0.72 + float((i + center_idx) % 4) * 0.13
            var basis := Basis(Vector3.UP, angle + 0.4).scaled(Vector3(s, s, s))
            transforms.append(Transform3D(basis, ground + Vector3(0.0, 2.35 * s, 0.0)))
    _add_multimesh_batch(root, mesh, transforms, Color(0.23, 0.24, 0.21, 1.0))




func _add_town_markers(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var all_sites: Array = []
    all_sites.append(profile.get("spawn_site", {}))
    all_sites.append_array(profile.get("town_sites", []))

    for site in all_sites:
        if site.is_empty():
            continue
        var point: Vector2 = site.get("position", Vector2.ZERO)
        var radius: float = site.get("radius", 90.0)
        var pos3: Vector3 = terrain_result.height_sampler.call(point.x, point.y)

        _add_town_cluster(root, point, pos3, radius, terrain_result, site.get("name", "Town"))
        if site.get("name", "") == profile.get("spawn_site", {}).get("name", ""):
            _add_start_town_landmarks(root, point, pos3, radius, terrain_result)


func _build_river_ribbons(root: Node3D, corridors: Array, terrain_result: Dictionary, profile: Dictionary) -> void:
    for corridor_index in range(corridors.size()):
        var corridor: Dictionary = corridors[corridor_index]
        var controlled: bool = profile.get("controlled_aqueduct", false)
        # Terrain uses a compact curve for fast height generation. Add a second
        # render-only Catmull pass here so water and the visible banks stay
        # rounded without multiplying terrain-query cost.
        # More curve samples keep long world-scale bends from exposing the
        # individual bank triangles as sharp zig-zags. This adds only a few
        # dozen vertices per river and is far cheaper than refining terrain.
        var points: Array = _catmull_resample(corridor.get("points", []), 8)
        if points.size() < 2:
            continue
        # Keep visible water inside the carved channel. The old ribbon extended
        # beyond the authored width to hide cracks; on curved bridge approaches
        # that overlap could project across the bank and look like flooding.
        # A narrow exposed shelf now forms the shoreline and absorbs coarse
        # terrain-grid variation without opening a noticeable dry trench.
        var authored_width: float = float(corridor.get("width", 48.0))
        # Keep water clearly inside the carved bed. A narrower moving stream
        # restores readable banks and prevents bends from looking flooded.
        # Leave a narrow wet shelf rather than the broad brown "coast" that
        # made the river read as a small stream inside an oversized trench.
        var width: float = maxf(8.0, authored_width * 0.84)
        var river_sampler: Callable = terrain_result.get("river_height_sampler", terrain_result.height_sampler)
        var junction_depth_offset:=0.0 if corridor_index==0 else -0.035
        var mesh: ArrayMesh = _build_corridor_ribbon_mesh(
            points,
            river_sampler,
            width,
            terrain_result.water_level + 0.82+junction_depth_offset,
            2.32 if controlled else 0.0,
            not controlled,
            [],
            false,
            Callable()
        )
        if mesh == null:
            continue

        var river: MeshInstance3D = MeshInstance3D.new()
        river.name = "%s_Water" % corridor.get("name", "River")
        river.mesh = mesh
        river.material_override = _make_water_material()
        root.add_child(river)
        # Keep the support transition local. The former grid-sized strip could
        # climb tens of metres up a hillside as a visibly different green wall.
        var bank_outer:=width*.5+15.0
        _build_smooth_river_banks(root, points, width, bank_outer, terrain_result, str(corridor.get("name", "River")), corridors)


func _build_smooth_river_banks(root:Node3D,points:Array,water_width:float,outer_distance:float,terrain_result:Dictionary,river_name:String,all_corridors:Array)->void:
    if points.size()<2:return
    var river_sampler:Callable=terrain_result.get("river_height_sampler",terrain_result.height_sampler)
    var raw_sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    # Start just outside the water ribbon.  The previous overlap hid the soil
    # shelf beneath the transparent water and made this edge look green.
    var inner_distance:=water_width*.5+.12
    # A compact shelf reads as a natural exposed bank.  A wider strip looked
    # like a second field laid beside the river when viewed from eye level.
    var shore_distance:=water_width*.5+8.0
    for bank_side in [-1.0,1.0]:
        var side:=float(bank_side)
        var inner_vertices:Array[Vector3]=[]
        var shore_vertices:Array[Vector3]=[]
        var outer_vertices:Array[Vector3]=[]
        for i in range(points.size()):
            var point:Vector2=points[i]
            var tangent:=_polyline_tangent(points,i)
            if tangent.length_squared()<=.0001:continue
            var normal:=Vector2(-tangent.y,tangent.x).normalized()*side
            var inner2:=point+normal*inner_distance
            var shore2:=point+normal*shore_distance
            var outer2:=point+normal*outer_distance
            var inner_ground:Vector3=river_sampler.call(inner2.x,inner2.y)
            var shore_ground:Vector3=raw_sampler.call(shore2.x,shore2.y)
            var outer_ground:Vector3=raw_sampler.call(outer2.x,outer2.y)
            # The visible water ribbon is authored against the profile water
            # level.  Pinning the first bank row to that same datum closes the
            # occasional gap created by the lower channel-bed sampler.
            # Controlled rivers are rendered 2.32 m above river_sampler, not
            # against the profile's global water datum. The old global datum
            # submerged this entire soil strip beneath the graded river and
            # exposed the hidden green terrain support instead.
            var rendered_water_y:=inner_ground.y+2.32
            var inner_y:=rendered_water_y+.095
            # Keep the brown alluvial shore nearly level with the water. Hills
            # begin after this shelf instead of dragging the water edge uphill.
            var shore_y:=clampf(shore_ground.y+.08,inner_y+.10,inner_y+.30)
            var outer_y:=maxf(outer_ground.y+.06,shore_y+.06)
            inner_vertices.append(Vector3(inner2.x,inner_y,inner2.y))
            shore_vertices.append(Vector3(shore2.x,shore_y,shore2.y))
            outer_vertices.append(Vector3(outer2.x,outer_y,outer2.y))
        if inner_vertices.size()<2:continue
        var side_name:="Left" if side<0.0 else "Right"
        _add_river_bank_strip(root,points,inner_vertices,shore_vertices,river_name,side_name+" Shore",all_corridors,_make_river_bank_material())
        # The terrain support already rises immediately behind the soil lip.
        # A second green overlay here duplicated the terrain, shimmered, and
        # exposed long triangular wedges on bends, so let authored terrain
        # continue naturally from the narrow brown shoreline.


func _add_river_bank_strip(root:Node3D,points:Array,inner_vertices:Array[Vector3],outer_vertices:Array[Vector3],river_name:String,strip_name:String,all_corridors:Array,material:Material)->void:
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(inner_vertices.size()-1):
        var segment_mid:=Vector2(points[i]).lerp(Vector2(points[i+1]),.5)
        if _near_other_river(segment_mid,river_name,all_corridors):continue
        var uv0:=float(i)/maxf(1.0,float(inner_vertices.size()-1))*18.0
        var uv1:=float(i+1)/maxf(1.0,float(inner_vertices.size()-1))*18.0
        st.set_uv(Vector2(uv0,0));st.add_vertex(inner_vertices[i])
        st.set_uv(Vector2(uv0,1));st.add_vertex(outer_vertices[i])
        st.set_uv(Vector2(uv1,0));st.add_vertex(inner_vertices[i+1])
        st.set_uv(Vector2(uv1,0));st.add_vertex(inner_vertices[i+1])
        st.set_uv(Vector2(uv0,1));st.add_vertex(outer_vertices[i])
        st.set_uv(Vector2(uv1,1));st.add_vertex(outer_vertices[i+1])
    st.generate_normals()
    var bank:=MeshInstance3D.new();bank.name="%s_%s"%[river_name,strip_name];bank.mesh=st.commit();bank.material_override=material;bank.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(bank)
    bank.create_trimesh_collision()


func _near_other_river(point:Vector2,current_name:String,corridors:Array)->bool:
    for other in corridors:
        if str(other.get("name","River"))==current_name:continue
        var mouth_clearance:=float(other.get("width",48.0))*.58+7.0
        if _distance_to_polyline(point,other.get("points",[]))<mouth_clearance:return true
    return false


func _build_river_channel_walls(root: Node3D, points: Array, width: float, terrain_result: Dictionary, river_name: String) -> void:
    if points.size() < 2:
        return
    var bottom_y: float = terrain_result.water_level + 0.14
    var water_y: float = terrain_result.water_level + 0.82
    for side in [-1.0, 1.0]:
        var side_value: float = float(side)
        var tops: Array[Vector3] = []
        var bottoms: Array[Vector3] = []
        for i in range(points.size()):
            var point: Vector2 = points[i]
            var tangent: Vector2 = _polyline_tangent(points, i)
            if tangent.length_squared() <= 0.0001:
                continue
            var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized() * side_value
            var edge2: Vector2 = point + normal * (width * 0.50)
            var outside2: Vector2 = point + normal * (width * 0.78)
            var outside_ground: Vector3 = terrain_result.height_sampler.call(outside2.x, outside2.y)
            var top_y := maxf(outside_ground.y, water_y + 0.55)
            tops.append(Vector3(edge2.x, top_y, edge2.y))
            bottoms.append(Vector3(edge2.x, bottom_y, edge2.y))
        if tops.size() < 2:
            continue
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        for i in range(tops.size() - 1):
            st.add_vertex(tops[i])
            st.add_vertex(bottoms[i])
            st.add_vertex(tops[i + 1])
            st.add_vertex(tops[i + 1])
            st.add_vertex(bottoms[i])
            st.add_vertex(bottoms[i + 1])
        st.generate_normals()
        var wall := MeshInstance3D.new()
        wall.name = "%s_%sWall" % [river_name, "Left" if side_value < 0.0 else "Right"]
        wall.mesh = st.commit()
        wall.material_override = _make_channel_wall_material()
        root.add_child(wall)


func _build_road_ribbons(root: Node3D, corridors: Array, terrain_result: Dictionary, profile: Dictionary = {}) -> void:
    var road_ground_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for corridor in corridors:
        var points: Array = _subdivide_polyline(corridor.get("points", []), 5)
        if points.size() < 2:
            continue
        var bridge_gaps := _road_bridge_gaps(corridor, profile)
        var width: float = corridor.get("width", 26.0) * 0.48
        var mesh: ArrayMesh = _build_corridor_ribbon_mesh(
            points,
            road_ground_sampler,
            width,
            0.0,
            0.14,
            false,
            bridge_gaps,
            true
        )
        if mesh == null:
            continue

        var road: MeshInstance3D = MeshInstance3D.new()
        road.mesh = mesh
        road.material_override = _make_road_material()
        root.add_child(road)


func _build_trail_ribbons(root: Node3D, corridors: Array, terrain_result: Dictionary) -> void:
    var raw_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for corridor in corridors:
        var points: Array = _subdivide_polyline(corridor.get("points", []), 5)
        if points.size() < 2:
            continue
        # Use the proven road ribbon construction at footpath scale. This keeps
        # the mesh continuous while remaining visibly narrower than a road.
        var width := maxf(2.4, float(corridor.get("width", 5.0)) * 0.48)
        var mesh := _build_corridor_ribbon_mesh(points, raw_sampler, width, 0.0, 0.14, false, [], true)
        if mesh == null:
            continue
        var trail := MeshInstance3D.new()
        trail.name = str(corridor.get("name", "Footpath"))
        trail.mesh = mesh
        trail.material_override = _make_trail_material()
        root.add_child(trail)


func _build_road_junctions(root:Node3D,corridors:Array,terrain_result:Dictionary)->void:
    var road_ground_sampler:Callable=terrain_result.get("terrain_height_sampler",terrain_result.height_sampler)
    var candidates:Array[Vector2]=[]
    for corridor in corridors:
        for point in corridor.get("points",[]):
            var matches:=0
            for other in corridors:
                for other_point in other.get("points",[]):
                    if point.distance_to(other_point)<9.0:matches+=1
            if matches>=2:
                var duplicate:=false
                for existing in candidates:
                    if existing.distance_to(point)<12.0:duplicate=true
                if not duplicate:candidates.append(point)
    for center in candidates:
        var radius:=7.5
        for corridor in corridors:
            if _distance_to_polyline(center,corridor.get("points",[]))<10.0:
                radius=maxf(radius,float(corridor.get("width",15.0))*.48*.5+3.0)
        var segments:=40;var center3:Vector3=road_ground_sampler.call(center.x,center.y);center3.y+=.205
        var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
        for i in range(segments):
            var a:=TAU*i/segments;var b:=TAU*(i+1)/segments
            var pa2:=center+Vector2(cos(a),sin(a))*radius;var pb2:=center+Vector2(cos(b),sin(b))*radius
            var pa:Vector3=road_ground_sampler.call(pa2.x,pa2.y);var pb:Vector3=road_ground_sampler.call(pb2.x,pb2.y);pa.y+=.205;pb.y+=.205
            st.set_uv(Vector2(.5,.5));st.add_vertex(center3);st.set_uv(Vector2(.5+cos(b)*.5,.5+sin(b)*.5));st.add_vertex(pb);st.set_uv(Vector2(.5+cos(a)*.5,.5+sin(a)*.5));st.add_vertex(pa)
        st.generate_normals();var junction:=MeshInstance3D.new();junction.name="RoadJunction";junction.mesh=st.commit();junction.material_override=_make_road_material();root.add_child(junction)


func _build_bridges(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var road_corridors: Array = profile.get("road_corridors", [])
    var trail_corridors: Array = profile.get("trail_corridors", [])
    var river_corridors: Array = profile.get("river_corridors", [])
    var crossings: Array[Dictionary] = []
    for road in road_corridors:
        var road_points: Array = road.get("points", [])
        if road_points.size() < 2:
            continue
        var road_width: float = road.get("width", 28.0)

        for river in river_corridors:
            var river_points: Array = river.get("points", [])
            if river_points.size() < 2:
                continue
            var river_width: float = river.get("width", 52.0)

            for road_idx in range(road_points.size() - 1):
                var ra: Vector2 = road_points[road_idx]
                var rb: Vector2 = road_points[road_idx + 1]
                for river_idx in range(river_points.size() - 1):
                    var va: Vector2 = river_points[river_idx]
                    var vb: Vector2 = river_points[river_idx + 1]
                    var hit: Variant = _segment_intersection(ra, rb, va, vb)
                    if hit == null:
                        continue
                    _register_bridge_crossing(crossings, hit, rb - ra, road_width, river_width)

    # Named crossing sites remain the authoritative fallback when a road and a
    # river meet at almost, but not exactly, the same authored control point.
    for ford in profile.get("ford_sites", []):
        var site: Vector2 = ford.get("position", Vector2.ZERO)
        var nearest_river: Dictionary = _nearest_corridor_segment(site, river_corridors)
        if nearest_river.is_empty() or float(nearest_river.distance) > 28.0:
            continue
        if ford.get("standalone", false):
            var river_direction: Vector2 = nearest_river.direction
            var crossing_direction := Vector2(-river_direction.y, river_direction.x).normalized()
            var nearest_trail: Dictionary = _nearest_corridor_segment(site, trail_corridors)
            var approach_width: float = float(ford.get("bridge_width", 10.0))
            if not nearest_trail.is_empty():
                approach_width = float(nearest_trail.width)
            _register_bridge_crossing(
                crossings,
                site,
                crossing_direction,
                float(ford.get("bridge_width", 10.0)),
                nearest_river.width,
                approach_width
            )
            continue
        var nearest_road: Dictionary = _nearest_corridor_segment(site, road_corridors)
        if nearest_road.is_empty() or float(nearest_road.distance) > 28.0:
            continue
        _register_bridge_crossing(
            crossings,
            site,
            nearest_road.direction,
            nearest_road.width,
            nearest_river.width
        )

    for crossing in crossings:
        _add_bridge(
            root,
            crossing.point,
            crossing.road_dir,
            crossing.road_width,
            crossing.river_width,
            crossing.get("approach_width", crossing.road_width),
            terrain_result
        )


func _register_bridge_crossing(crossings: Array[Dictionary], point: Vector2, road_dir: Vector2, road_width: float, river_width: float, approach_width: float = -1.0) -> void:
    for existing in crossings:
        var existing_point: Vector2 = existing.get("point", Vector2.ZERO)
        if existing_point.distance_to(point) < maxf(20.0, river_width * 0.35):
            return
    crossings.append({
        "point": point,
        "road_dir": road_dir.normalized(),
        "road_width": road_width,
        "river_width": river_width,
        "approach_width": road_width if approach_width < 0.0 else approach_width,
    })


func _nearest_corridor_segment(point: Vector2, corridors: Array) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for corridor in corridors:
        var points: Array = corridor.get("points", [])
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var direction := b - a
            var length_squared := direction.length_squared()
            if length_squared <= 0.0001:
                continue
            var t := clampf((point - a).dot(direction) / length_squared, 0.0, 1.0)
            var distance := point.distance_to(a + direction * t)
            if distance < best_distance:
                best_distance = distance
                best = {
                    "distance": distance,
                    "direction": direction.normalized(),
                    "width": float(corridor.get("width", 16.0)),
                    "closest_point":a+direction*t,
                }
    return best


func _clear_house_from_roads(point:Vector2,footprint_radius:float,roads:Array)->Vector2:
    var info:=_nearest_corridor_segment(point,roads)
    if info.is_empty():return point
    var clearance:float=float(info.get("width",16.0))*.5+footprint_radius+3.0
    var distance:float=float(info.get("distance",INF))
    if distance>=clearance:return point
    var closest:Vector2=info.get("closest_point",point)
    var away:=point-closest
    if away.length_squared()<.001:
        var direction:Vector2=info.get("direction",Vector2.RIGHT)
        away=Vector2(-direction.y,direction.x)
    return closest+away.normalized()*clearance


func _separate_house_plot(point:Vector2,radius:float,occupied:Array[Dictionary],town_center:Vector2)->Vector2:
    var result:=point
    for iteration in range(5):
        var moved:=false
        for plot in occupied:
            var other:Vector2=plot.get("position",Vector2.ZERO)
            var clearance:=radius+float(plot.get("radius",8.0))+2.5
            var delta:=result-other
            if delta.length_squared()>=clearance*clearance:continue
            if delta.length_squared()<.01:
                delta=(result-town_center).normalized()
                if delta.length_squared()<.01:delta=Vector2.RIGHT
            result=other+delta.normalized()*clearance
            moved=true
        if not moved:break
    return result


func _add_town_cluster(root: Node3D, center2: Vector2, center3: Vector3, radius: float, terrain_result: Dictionary, site_name: String) -> void:
    var hub: Node3D = Node3D.new()
    hub.name = "%s_Cluster" % site_name.replace(" ", "_")
    root.add_child(hub)

    var building_count: int = 8 if radius >= 100.0 else 5
    var angle_offset: float = 0.27

    for i in range(building_count):
        var frac: float = float(i) / float(max(1, building_count))
        var angle: float = frac * TAU + angle_offset
        var ring_radius: float = radius * (0.18 + 0.18 * float(i % 3))
        var footprint: Vector2 = center2 + Vector2(cos(angle), sin(angle)) * ring_radius
        var ground: Vector3 = terrain_result.height_sampler.call(footprint.x, footprint.y)

        var building: MeshInstance3D = MeshInstance3D.new()
        var body: BoxMesh = BoxMesh.new()
        var width: float = 8.0 + float(i % 3) * 2.5
        var depth: float = 7.0 + float((i + 1) % 3) * 2.0
        var height: float = 6.0 + float(i % 4) * 2.2
        body.size = Vector3(width, height, depth)
        building.mesh = body
        building.position = ground + Vector3(0.0, height * 0.5, 0.0)
        building.rotation.y = angle + PI * 0.5
        building.material_override = _make_material(Color(0.84, 0.72, 0.56, 1.0), 0.96)
        hub.add_child(building)

        var roof: MeshInstance3D = MeshInstance3D.new()
        var roof_mesh: BoxMesh = BoxMesh.new()
        roof_mesh.size = Vector3(width * 1.16, 2.2, depth * 1.16)
        roof.mesh = roof_mesh
        roof.position = building.position + Vector3(0.0, height * 0.5 + 1.0, 0.0)
        roof.rotation.y = building.rotation.y
        roof.material_override = _make_material(Color(0.44, 0.20, 0.17, 1.0), 0.88)
        hub.add_child(roof)

        var trim: MeshInstance3D = MeshInstance3D.new()
        var trim_mesh: BoxMesh = BoxMesh.new()
        trim_mesh.size = Vector3(width * 1.02, 0.40, depth * 1.02)
        trim.mesh = trim_mesh
        trim.position = building.position + Vector3(0.0, -height * 0.42, 0.0)
        trim.rotation.y = building.rotation.y
        trim.material_override = _make_material(Color(0.38, 0.28, 0.19, 1.0), 0.96)
        hub.add_child(trim)

        var door: MeshInstance3D = MeshInstance3D.new()
        var door_mesh: BoxMesh = BoxMesh.new()
        door_mesh.size = Vector3(1.5, 2.8, 0.22)
        door.mesh = door_mesh
        door.position = building.position + Vector3(0.0, -height * 0.18, depth * 0.52)
        door.rotation.y = building.rotation.y
        door.material_override = _make_material(Color(0.24, 0.16, 0.10, 1.0), 0.98)
        hub.add_child(door)

        var window_left: MeshInstance3D = MeshInstance3D.new()
        var window_mesh: BoxMesh = BoxMesh.new()
        window_mesh.size = Vector3(1.2, 1.2, 0.16)
        window_left.mesh = window_mesh
        window_left.position = building.position + Vector3(width * 0.22, 0.5, depth * 0.52)
        window_left.rotation.y = building.rotation.y
        window_left.material_override = _make_material(Color(0.86, 0.83, 0.52, 1.0), 0.35)
        hub.add_child(window_left)

        var window_right: MeshInstance3D = MeshInstance3D.new()
        window_right.mesh = window_mesh.duplicate()
        window_right.position = building.position + Vector3(-width * 0.22, 0.5, depth * 0.52)
        window_right.rotation.y = building.rotation.y
        window_right.material_override = _make_material(Color(0.86, 0.83, 0.52, 1.0), 0.35)
        hub.add_child(window_right)

        var chimney: MeshInstance3D = MeshInstance3D.new()
        var chimney_mesh: BoxMesh = BoxMesh.new()
        chimney_mesh.size = Vector3(1.2, 2.8, 1.2)
        chimney.mesh = chimney_mesh
        chimney.position = roof.position + Vector3(width * 0.22, 1.4, -depth * 0.14)
        chimney.rotation.y = building.rotation.y
        chimney.material_override = _make_material(Color(0.50, 0.48, 0.44, 1.0), 1.0)
        hub.add_child(chimney)

    var well: MeshInstance3D = MeshInstance3D.new()
    var well_mesh: CylinderMesh = CylinderMesh.new()
    well_mesh.top_radius = 3.2
    well_mesh.bottom_radius = 3.8
    well_mesh.height = 2.0
    well.mesh = well_mesh
    well.position = center3 + Vector3(0.0, 1.0, 0.0)
    well.material_override = _make_material(Color(0.68, 0.67, 0.62, 1.0), 1.0)
    hub.add_child(well)

    var plaza: MeshInstance3D = MeshInstance3D.new()
    var plaza_mesh: CylinderMesh = CylinderMesh.new()
    plaza_mesh.top_radius = radius * 0.20
    plaza_mesh.bottom_radius = radius * 0.22
    plaza_mesh.height = 0.24
    plaza.mesh = plaza_mesh
    plaza.position = center3 + Vector3(0.0, 0.12, 0.0)
    plaza.material_override = _make_material(Color(0.71, 0.64, 0.50, 1.0), 0.97)
    hub.add_child(plaza)


func _build_forests(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    for region in profile.get("forest_regions", []):
        var center: Vector2 = region.get("center", Vector2.ZERO)
        var radius: float = region.get("radius", 180.0)
        var density: float = region.get("density", 0.65)
        # MultiMesh keeps several thousand trees inexpensive; favor a real
        # forest silhouette instead of sparse decorative clusters.
        var tree_count: int = int(maxf(48.0, radius * density * 1.18))
        var accepted: Array[Dictionary] = []
        for i in range(tree_count):
            var angle: float = float(i) * 2.39996323
            var pos2:Vector2
            if i%5==0:
                var scatter_dist:=radius*(.18+.72*sqrt(fmod(float(i*47),float(tree_count))/maxf(1.0,float(tree_count))))
                pos2=center+Vector2(cos(angle),sin(angle))*scatter_dist
            else:
                var cluster_index:=i%9
                var cluster_angle:=float(cluster_index)*2.39996323+center.x*.0007
                var cluster_dist:=radius*(.16+.055*float(cluster_index%6))
                var cluster_center:=center+Vector2(cos(cluster_angle),sin(cluster_angle))*cluster_dist
                var local_radius:=radius*(.025+.16*sqrt(fmod(float(i*53),97.0)/97.0))
                pos2=cluster_center+Vector2(cos(angle),sin(angle))*local_radius
            if _is_dry_biome(pos2, float(profile.get("world_size", 7200.0))):
                continue
            if _is_too_close_to_corridors(pos2, profile.get("road_corridors", []), 16.0):
                continue
            if _is_too_close_to_corridors(pos2, profile.get("river_corridors", []), 52.0):
                continue
            if _is_too_close_to_sites(pos2,profile.get("pond_sites",[]),48.0):
                continue
            if _tree_overlaps_authored_site(pos2,profile,10.0):
                continue
            if pos2.distance_to(profile.get("spawn_site", {}).get("position", Vector2.ZERO)) < 64.0:
                continue
            accepted.append({
                "position": pos2,
                "scale": 0.78 + float(i % 11) * 0.105,
            })
        _add_forest_batch(root, accepted, terrain_result)


func _is_dry_biome(point: Vector2, world_size: float) -> bool:
    return point.y < -world_size * 0.18 and point.x > -world_size * 0.10


func _build_biome_vegetation(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var world_size: float = profile.get("world_size", 7200.0)
    var terrain_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    var spawn: Vector2 = profile.get("spawn_site", {}).get("position", Vector2.ZERO)

    # Broadleaf trees scatter outside the authored forest cores, while broad
    # open sight-lines remain near towns, roads and the starting location.
    var scattered: Array[Dictionary] = []
    for i in range(2600):
        var anchor_index:=i/6
        var anchor_x:=world_size*(fmod(float(anchor_index*149),439.0)/439.0-.5)*.88
        var anchor_z:=world_size*(fmod(float(anchor_index*283),443.0)/443.0-.5)*.86
        var local_angle:=float(i)*2.39996323
        var local_radius:=10.0+float(i%6)*7.0
        var x:=anchor_x+cos(local_angle)*local_radius
        var z:=anchor_z+sin(local_angle)*local_radius
        var point := Vector2(x, z)
        if _is_dry_biome(point, world_size):
            continue
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 54.0) or _is_too_close_to_corridors(point, profile.get("road_corridors", []), 20.0):
            continue
        if _is_too_close_to_sites(point,profile.get("pond_sites",[]),48.0):
            continue
        if _tree_overlaps_authored_site(point,profile,10.0) or point.distance_to(spawn) < 80.0:
            continue
        scattered.append({"position": point, "scale": 0.58 + float(i % 13) * 0.090})
    _add_forest_batch(root, scattered, terrain_result)

    # Colder northern uplands use the authored Blender pine rather than the
    # old cylinder-and-cone stand-in.
    var pine_transforms: Array[Transform3D] = []
    var conifer_ground:Array[Vector3]=[]
    var conifer_scales:Array[float]=[]
    for i in range(1900):
        var x := world_size * (fmod(float(i * 181), 1901.0) / 1901.0 - 0.5) * 0.90
        var z := world_size * (0.10 + fmod(float(i * 307), 1913.0) / 1913.0 * 0.34)
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 55.0) or _is_too_close_to_corridors(point, profile.get("road_corridors", []), 18.0):
            continue
        if _is_too_close_to_sites(point,profile.get("pond_sites",[]),48.0):
            continue
        if _tree_overlaps_authored_site(point,profile,8.0):
            continue
        var ground: Vector3 = terrain_sampler.call(x, z)
        var scale_factor := 0.88 + float(i % 9) * 0.072
        var yaw := float(i) * 2.39996323
        var lean:=Basis(Vector3.FORWARD,deg_to_rad(sin(float(i)*1.77)*1.4))
        var basis:=Basis(Vector3.UP,yaw)*lean
        basis=basis.scaled(Vector3(scale_factor,scale_factor,scale_factor))
        pine_transforms.append(Transform3D(basis,ground))
        conifer_ground.append(ground)
        conifer_scales.append(scale_factor)
    var pine_maps:Array=_add_tree_species_batch(root,"pine",pine_transforms)
    for tree_index in range(conifer_ground.size()):
        _append_tree_registry(root,{"position":conifer_ground[tree_index],"scale":conifer_scales[tree_index],"kind":"conifer","species":"pine","batched_parts":[pine_maps[0].get(tree_index,{}),pine_maps[1].get(tree_index,{}),pine_maps[2].get(tree_index,{})],"active":true,"hits":0})

    # The southern drylands deliberately stay open and carry cactus, dead
    # brush and tumbleweed rather than green forest.
    var cactus_trunks: Array[Transform3D] = []
    var cactus_arms: Array[Transform3D] = []
    var tumble_branches: Array[Transform3D] = []
    for i in range(820):
        var x := lerpf(-world_size * 0.08, world_size * 0.43, fmod(float(i * 127), 823.0) / 823.0)
        var z := lerpf(-world_size * 0.43, -world_size * 0.19, fmod(float(i * 251), 827.0) / 827.0)
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 58.0) or _is_too_close_to_corridors(point, profile.get("road_corridors", []), 15.0) or _is_too_close_to_sites(point, profile.get("town_sites", []), 62.0):
            continue
        var ground: Vector3 = terrain_sampler.call(x, z)
        var s := 0.72 + float(i % 7) * 0.08
        var yaw := float(i) * 1.73
        cactus_trunks.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), ground + Vector3.UP * 1.75 * s))
        if i % 2 == 0:
            var arm_basis := Basis.from_euler(Vector3(0, yaw, PI * 0.5)).scaled(Vector3(s * 0.72, s * 0.72, s * 0.72))
            cactus_arms.append(Transform3D(arm_basis, ground + Vector3(cos(yaw) * 0.42, 1.8 * s, sin(yaw) * 0.42)))
    for i in range(760):
        var x := lerpf(-world_size * 0.08, world_size * 0.43, fmod(float(i * 167), 761.0) / 761.0)
        var z := lerpf(-world_size * 0.43, -world_size * 0.19, fmod(float(i * 313), 769.0) / 769.0)
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 54.0) or _is_too_close_to_corridors(point, profile.get("road_corridors", []), 9.0):
            continue
        var ground: Vector3 = terrain_sampler.call(x, z)
        for branch_index in range(5):
            var rotation := Vector3(float(branch_index) * 0.63, float(i) * 0.87 + branch_index, PI * (0.33 + float(branch_index) * 0.08))
            tumble_branches.append(Transform3D(Basis.from_euler(rotation), ground + Vector3.UP * 0.58))
    var cactus_mesh := CylinderMesh.new(); cactus_mesh.top_radius = 0.25; cactus_mesh.bottom_radius = 0.32; cactus_mesh.height = 3.5; cactus_mesh.radial_segments = 7
    var arm_mesh := CylinderMesh.new(); arm_mesh.top_radius = 0.17; arm_mesh.bottom_radius = 0.20; arm_mesh.height = 1.25; arm_mesh.radial_segments = 6
    var branch_mesh := CylinderMesh.new(); branch_mesh.top_radius = 0.025; branch_mesh.bottom_radius = 0.035; branch_mesh.height = 1.35; branch_mesh.radial_segments = 5
    _add_multimesh_batch(root, cactus_mesh, cactus_trunks, Color(0.20, 0.40, 0.20, 1.0))
    _add_multimesh_batch(root, arm_mesh, cactus_arms, Color(0.22, 0.42, 0.21, 1.0))
    _add_multimesh_batch(root, branch_mesh, tumble_branches, Color(0.34, 0.245, 0.135, 1.0), false)

    var ground_branches: Array[Transform3D] = []
    for i in range(2800):
        var x := world_size * (fmod(float(i * 233), 2801.0) / 2801.0 - 0.5) * 0.90
        var z := world_size * (fmod(float(i * 397), 2819.0) / 2819.0 - 0.5) * 0.90
        var point := Vector2(x, z)
        if _is_too_close_to_corridors(point, profile.get("river_corridors", []), 51.0) or _is_too_close_to_corridors(point, profile.get("road_corridors", []), 5.0) or _is_too_close_to_sites(point, profile.get("town_sites", []), 48.0):
            continue
        var ground: Vector3 = terrain_sampler.call(x, z)
        var yaw := float(i) * 1.914
        var s := 0.55 + float(i % 6) * 0.11
        var branch_basis := Basis.from_euler(Vector3(0.08 * float(i % 3), yaw, PI * 0.5)).scaled(Vector3(s, s, s))
        ground_branches.append(Transform3D(branch_basis, ground + Vector3.UP * 0.08))
    var ground_branch_mesh := CylinderMesh.new(); ground_branch_mesh.top_radius = 0.055; ground_branch_mesh.bottom_radius = 0.085; ground_branch_mesh.height = 2.1; ground_branch_mesh.radial_segments = 6
    _add_multimesh_batch(root, ground_branch_mesh, ground_branches, Color(0.34, 0.22, 0.11, 1.0), false)


func _build_camps(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var canvas:=_make_texture_material("res://assets/architecture/aged_plaster_v1.png",Color(.42,.30,.18),1.0,2.0)
    var timber:=_make_texture_material("res://assets/architecture/dark_oak_v1.png",Color(.42,.29,.16),1.0,2.0)
    var stone:=_make_texture_material("res://assets/architecture/castle_stone_v1.png",Color(.48,.47,.42),1.0,3.0)
    var camps:Array=profile.get("camp_sites", [])
    for camp_index in range(camps.size()):
        var camp:Dictionary=camps[camp_index]
        var pos2: Vector2 = camp.get("position", Vector2.ZERO)
        var ground: Vector3 = terrain_result.height_sampler.call(pos2.x, pos2.y)
        var camp_root:=Node3D.new();camp_root.name=str(camp.get("name","Camp"));camp_root.set_meta("batch_static_collision",true);root.add_child(camp_root)
        var yaw:=.35+float(camp_index)*1.18
        _add_canvas_tent(camp_root,pos2+Vector2(-7.5,-3.5),yaw,terrain_result,canvas,timber)
        _add_canvas_tent(camp_root,pos2+Vector2(8.0,4.5),yaw+PI,terrain_result,canvas,timber)
        _add_campfire(camp_root,ground+Vector3(0,.12,0),stone,timber)
        # Bedrolls, supply crates and a rough drying rack make the sites look
        # occupied without introducing expensive character AI.
        for side in [-1.0,1.0]:
            var roll:=_visual_box(camp_root,Vector3(1.7,.32,3.4),ground+Vector3(side*4.2,.22,-1.2),canvas);roll.rotation.y=yaw
        _solid_box(camp_root,Vector3(2.1,1.6,2.0),ground+Vector3(10.5,.8,-5.0),timber)
        _solid_box(camp_root,Vector3(1.7,1.25,1.6),ground+Vector3(12.3,.62,-3.8),timber)
        for rack_x in [-2.1,2.1]:
            _solid_box_euler(camp_root,Vector3(.20,4.0,.20),ground+Vector3(rack_x,2.0,8.5),Vector3(0,0,(-.18 if rack_x<0 else .18)),timber)
        _visual_box(camp_root,Vector3(4.7,.18,.18),ground+Vector3(0,3.55,8.5),timber)


func _add_canvas_tent(root:Node3D,point:Vector2,yaw:float,terrain_result:Dictionary,canvas:Material,timber:Material)->void:
    var ground:Vector3=terrain_result.height_sampler.call(point.x,point.y)
    var tent:=Node3D.new();tent.position=ground;tent.rotation.y=yaw;tent.set_meta("batch_static_collision",true);root.add_child(tent)
    _solid_box_euler(tent,Vector3(3.7,.18,5.8),Vector3(-1.08,1.65,0),Vector3(0,0,.87),canvas)
    _solid_box_euler(tent,Vector3(3.7,.18,5.8),Vector3(1.08,1.65,0),Vector3(0,0,-.87),canvas)
    var pole_mesh:=CylinderMesh.new();pole_mesh.top_radius=.10;pole_mesh.bottom_radius=.13;pole_mesh.height=6.25;pole_mesh.radial_segments=6
    var ridge:=MeshInstance3D.new();ridge.mesh=pole_mesh;ridge.position=Vector3(0,3.05,0);ridge.rotation.x=PI*.5;ridge.material_override=timber;tent.add_child(ridge)
    for z in [-2.85,2.85]:
        _visual_box(tent,Vector3(.18,3.25,.18),Vector3(0,1.62,z),timber)


func _add_campfire(root:Node3D,position:Vector3,stone:Material,timber:Material)->void:
    var pebble_mesh:=SphereMesh.new();pebble_mesh.radius=.34;pebble_mesh.height=.45;pebble_mesh.radial_segments=7;pebble_mesh.rings=4
    var stones:Array[Transform3D]=[]
    for i in range(10):
        var angle:=float(i)*TAU/10.0
        stones.append(Transform3D(Basis(Vector3.UP,angle),position+Vector3(cos(angle)*1.15,.18,sin(angle)*1.15)))
    _add_material_multimesh(root,pebble_mesh,stones,stone,false)
    for angle in [-.72,.72]:
        _solid_box_euler(root,Vector3(.34,.34,2.05),position+Vector3(0,.30,0),Vector3(0,angle,PI*.5),timber)
    var outer_flame:=CylinderMesh.new();outer_flame.top_radius=0.0;outer_flame.bottom_radius=.54;outer_flame.height=1.65;outer_flame.radial_segments=7
    var flame:=MeshInstance3D.new();flame.mesh=outer_flame;flame.position=position+Vector3.UP*1.05;flame.material_override=_make_lit_window_material(Color(1.0,.25,.035));root.add_child(flame)
    var inner_flame:=CylinderMesh.new();inner_flame.top_radius=0.0;inner_flame.bottom_radius=.28;inner_flame.height=1.15;inner_flame.radial_segments=7
    var core:=MeshInstance3D.new();core.mesh=inner_flame;core.position=position+Vector3(0,.78,-.08);core.material_override=_make_lit_window_material(Color(1.0,.72,.16));root.add_child(core)
    var glow:=OmniLight3D.new();glow.position=position+Vector3.UP*1.25;glow.light_color=Color(1.0,.42,.12);glow.light_energy=1.4;glow.omni_range=9.0;glow.shadow_enabled=false;glow.distance_fade_enabled=true;glow.distance_fade_begin=38.0;glow.distance_fade_length=18.0;glow.set_script(load("res://scripts/world/CampfireFlicker.gd"));root.add_child(glow)


func _add_start_town_landmarks(root: Node3D, center2: Vector2, center3: Vector3, radius: float, terrain_result: Dictionary) -> void:
    var plaza: MeshInstance3D = MeshInstance3D.new()
    var plaza_mesh: CylinderMesh = CylinderMesh.new()
    plaza_mesh.top_radius = radius * 0.22
    plaza_mesh.bottom_radius = radius * 0.24
    plaza_mesh.height = 0.8
    plaza.mesh = plaza_mesh
    plaza.position = center3 + Vector3(0.0, 0.4, 0.0)
    plaza.material_override = _make_material(Color(0.58, 0.55, 0.50, 1.0), 1.0)
    root.add_child(plaza)

    var hall: MeshInstance3D = MeshInstance3D.new()
    var hall_mesh: BoxMesh = BoxMesh.new()
    hall_mesh.size = Vector3(18.0, 12.0, 14.0)
    hall.mesh = hall_mesh
    hall.position = center3 + Vector3(0.0, 6.0, -radius * 0.12)
    hall.material_override = _make_material(Color(0.76, 0.64, 0.44, 1.0), 0.92)
    root.add_child(hall)

    var hall_roof: MeshInstance3D = MeshInstance3D.new()
    var hall_roof_mesh: BoxMesh = BoxMesh.new()
    hall_roof_mesh.size = Vector3(20.0, 1.8, 16.0)
    hall_roof.mesh = hall_roof_mesh
    hall_roof.position = hall.position + Vector3(0.0, 6.9, 0.0)
    hall_roof.material_override = _make_material(Color(0.33, 0.20, 0.16, 1.0), 0.88)
    root.add_child(hall_roof)

    var wall_radius: float = radius * 0.66
    var wall_segments: int = 12
    for i in range(wall_segments):
        if i == 0 or i == wall_segments / 2:
            continue
        var angle: float = float(i) / float(wall_segments) * TAU
        var pos2: Vector2 = center2 + Vector2(cos(angle), sin(angle)) * wall_radius
        var ground: Vector3 = terrain_result.height_sampler.call(pos2.x, pos2.y)
        var wall: MeshInstance3D = MeshInstance3D.new()
        var wall_mesh: BoxMesh = BoxMesh.new()
        wall_mesh.size = Vector3(10.0, 5.0, 2.6)
        wall.mesh = wall_mesh
        wall.position = ground + Vector3(0.0, 2.6, 0.0)
        wall.rotation.y = angle
        wall.material_override = _make_material(Color(0.60, 0.58, 0.54, 1.0), 1.0)
        root.add_child(wall)

    for gate_sign in [-1, 1]:
        var gate_pos2: Vector2 = center2 + Vector2(0.0, wall_radius * gate_sign)
        var gate_ground: Vector3 = terrain_result.height_sampler.call(gate_pos2.x, gate_pos2.y)
        var gate: MeshInstance3D = MeshInstance3D.new()
        var gate_mesh: BoxMesh = BoxMesh.new()
        gate_mesh.size = Vector3(16.0, 6.0, 3.0)
        gate.mesh = gate_mesh
        gate.position = gate_ground + Vector3(0.0, 3.0, 0.0)
        gate.material_override = _make_material(Color(0.53, 0.42, 0.28, 1.0), 0.94)
        root.add_child(gate)


func _get_broadleaf_canopy_mesh()->ArrayMesh:
    if _broadleaf_canopy_mesh!=null:return _broadleaf_canopy_mesh
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var segments:=14
    var levels:=[[ -1.0,.56],[-.62,1.00],[.02,1.16],[.58,.93],[1.03,.38]]
    var rings:Array=[]
    for level_index in range(levels.size()):
        var ring:Array[Vector3]=[]
        var y:float=levels[level_index][0];var radius:float=levels[level_index][1]
        var offset:=float(level_index%2)*PI/float(segments)
        for i in range(segments):
            var angle:=TAU*float(i)/float(segments)+offset
            # Deep, differently phased scallops stop each crown cluster from
            # reading as a smooth low-poly ball while keeping one cheap mesh.
            var irregular:=1.0+sin(float(i*7+level_index*11))*.19+cos(float(i*3-level_index*5))*.105+sin(float(i*11+level_index*2))*.055
            var edge_jitter:=sin(float(i*5+level_index*13))*.075
            ring.append(Vector3(cos(angle)*radius*irregular,y+edge_jitter,sin(angle)*radius*irregular))
        rings.append(ring)
    for level_index in range(rings.size()-1):
        var lower:Array=rings[level_index];var upper:Array=rings[level_index+1]
        for i in range(segments):
            var next:=(i+1)%segments
            for vertex in [lower[i],lower[next],upper[next],lower[i],upper[next],upper[i]]:st.add_vertex(vertex)
    var bottom:=Vector3(0,-1.08,0);var top:=Vector3(0,1.12,0)
    for i in range(segments):
        var next:=(i+1)%segments
        st.add_vertex(bottom);st.add_vertex(rings[0][next]);st.add_vertex(rings[0][i])
        st.add_vertex(top);st.add_vertex(rings[-1][i]);st.add_vertex(rings[-1][next])
    st.generate_normals();_broadleaf_canopy_mesh=st.commit();return _broadleaf_canopy_mesh


func _add_tree(root: Node3D, pos2: Vector2, terrain_result: Dictionary, scale_factor: float) -> void:
    var tree_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    var ground: Vector3 = tree_sampler.call(pos2.x, pos2.y)
    var tint_mix := absf(pos2.x * 0.003 + pos2.y * 0.002)
    tint_mix = tint_mix - floor(tint_mix)
    var crown_tint := Color(0.18, 0.32, 0.13, 1.0).lerp(Color(0.30, 0.43, 0.17, 1.0), clampf(tint_mix, 0.0, 1.0))
    var meshes:=_get_realistic_tree_meshes()
    var nodes:Array[Node3D]=[]
    var yaw:=pos2.x*.017+pos2.y*.011
    for spec in [
        ["trunk",_make_bark_material(Color(.86,.78,.66)),650.0],
        ["branches",_make_bark_material(Color(.78,.69,.57)),520.0],
        ["leaves",_make_foliage_material(crown_tint),320.0],
    ]:
        var instance:=MeshInstance3D.new()
        instance.name="RealisticTree_%s"%str(spec[0]).capitalize()
        instance.mesh=meshes.get(spec[0])
        instance.position=ground
        instance.rotation.y=yaw
        instance.scale=Vector3.ONE*scale_factor
        instance.material_override=spec[1]
        instance.visibility_range_end=spec[2]
        instance.visibility_range_end_margin=48.0
        instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        instance.set_meta("tree_component",true)
        root.add_child(instance)
        nodes.append(instance)
    _append_tree_registry(root,{"position":ground,"scale":scale_factor,"kind":"broadleaf","nodes":nodes,"active":true,"hits":0})


func _add_forest_batch(root: Node3D, entries: Array, terrain_result: Dictionary) -> void:
    if entries.is_empty():
        return

    var transforms_by_species:Dictionary={
        "oak":[],
        "birch":[],
        "maple":[],
    }
    var tree_render_refs:Array[Dictionary]=[]
    var tree_ground:Array[Vector3]=[]
    var tree_scales:Array[float]=[]

    var tree_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for i in range(entries.size()):
        var entry: Dictionary = entries[i]
        var pos2: Vector2 = entry.get("position", Vector2.ZERO)
        var scale_factor: float = entry.get("scale", 1.0)
        var ground: Vector3 = tree_sampler.call(pos2.x, pos2.y)
        tree_ground.append(ground)
        tree_scales.append(scale_factor)

        var yaw := float(i) * 2.39996323
        var tree_style:=i%5
        var stretch:=1.0+float(tree_style-2)*.035
        var basis:=Basis(Vector3.UP,yaw).scaled(Vector3(scale_factor*stretch,scale_factor*(1.0+float(tree_style%2)*.035),scale_factor/stretch))
        var species:="birch" if i%8==0 else ("maple" if i%11==1 else "oak")
        var species_transforms:Array=transforms_by_species[species]
        tree_render_refs.append({"species":species,"index":species_transforms.size()})
        species_transforms.append(Transform3D(basis,ground))

    # Spatial chunks let the renderer reject entire distant forest cells.
    # The former realm-wide MultiMeshes forced every tree through the GPU even
    # when only a small valley was visible.
    var render_maps:Dictionary={}
    for species in transforms_by_species:
        render_maps[species]=_add_tree_species_batch(root,species,transforms_by_species[species])
    for tree_index in range(tree_ground.size()):
        var ref:Dictionary=tree_render_refs[tree_index]
        var maps:Array=render_maps[ref.species]
        var local_index:int=ref.index
        _append_tree_registry(root,{"position":tree_ground[tree_index],"scale":tree_scales[tree_index],"kind":"broadleaf","species":ref.species,"batched_parts":[maps[0].get(local_index,{}),maps[1].get(local_index,{}),maps[2].get(local_index,{})],"active":true,"hits":0})


func _get_realistic_tree_meshes()->Dictionary:
    return _get_tree_species_meshes("oak")


func _get_tree_species_meshes(species:String)->Dictionary:
    if _tree_species_mesh_cache.has(species):return _tree_species_mesh_cache[species]
    var packed:PackedScene=REALISTIC_BROADLEAF_SCENE
    if species=="birch":packed=REALISTIC_BIRCH_SCENE
    elif species=="maple":packed=REALISTIC_MAPLE_SCENE
    elif species=="pine":packed=REALISTIC_PINE_SCENE
    var source:=packed.instantiate()
    var meshes:={
        "trunk":_find_named_mesh_resource(source,"TreeTrunk"),
        "branches":_find_named_mesh_resource(source,"TreeBranches"),
        "leaves":_find_named_mesh_resource(source,"TreeLeaves"),
    }
    source.free()
    _tree_species_mesh_cache[species]=meshes
    if species=="oak":_realistic_tree_meshes=meshes
    return meshes


func _add_tree_species_batch(root:Node3D,species:String,transforms:Array)->Array:
    var meshes:=_get_tree_species_meshes(species)
    var typed_transforms:Array[Transform3D]=[]
    typed_transforms.assign(transforms)
    var bark_tint:=Color(.82,.74,.63)
    var leaf_tint:=Color(.20,.36,.135,1)
    if species=="birch":
        bark_tint=Color(1.24,1.17,1.03)
        leaf_tint=Color(.27,.48,.13,1)
    elif species=="maple":
        bark_tint=Color(.72,.59,.43)
        leaf_tint=Color(.27,.43,.10,1)
    elif species=="pine":
        bark_tint=Color(.64,.52,.39)
        leaf_tint=Color(.12,.38,.17,1)
    var bark:=_make_bark_material(bark_tint)
    return [
        _add_material_multimesh(root,meshes.trunk,typed_transforms,bark,true,680.0,360.0),
        _add_material_multimesh(root,meshes.branches,typed_transforms,bark,true,520.0,320.0),
        _add_material_multimesh(root,meshes.leaves,typed_transforms,_make_foliage_material(leaf_tint),false,320.0,240.0),
    ]


func _find_named_mesh_resource(node:Node,target:String)->Mesh:
    if node is MeshInstance3D and str(node.name).contains(target):
        return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var found:=_find_named_mesh_resource(child,target)
        if found!=null:return found
    return null


func _cylinder_between_transform(start:Vector3,finish:Vector3,radius:float)->Transform3D:
    var delta:=finish-start
    var length:=maxf(.01,delta.length())
    var y_axis:=delta/length
    var x_axis:=Vector3.UP.cross(y_axis)
    if x_axis.length_squared()<.001:x_axis=Vector3.RIGHT
    x_axis=x_axis.normalized()
    var z_axis:=x_axis.cross(y_axis).normalized()
    var basis:=Basis(x_axis*radius,y_axis*length,z_axis*radius)
    return Transform3D(basis,(start+finish)*.5)


func _add_bridge(root: Node3D, point: Vector2, road_dir: Vector2, road_width: float, river_width: float, approach_width: float, terrain_result: Dictionary) -> void:
    var tangent: Vector2 = road_dir.normalized()
    if tangent.length_squared() <= 0.0001:
        return

    var span: float = maxf(river_width + 10.0, road_width * 2.15)
    var deck_width := maxf(road_width * 0.72, 8.5)
    var yaw := atan2(tangent.x, tangent.y)
    var side_normal := Vector2(-tangent.y, tangent.x).normalized()
    var deck_start2 := point - tangent * (span * 0.5)
    var deck_end2 := point + tangent * (span * 0.5)
    var deck_start_y: float = terrain_result.height_sampler.call(deck_start2.x, deck_start2.y).y
    var deck_end_y: float = terrain_result.height_sampler.call(deck_end2.x, deck_end2.y).y
    var bridge_root := Node3D.new()
    bridge_root.name = "Bridge_%d_%d" % [roundi(point.x), roundi(point.y)]
    root.add_child(bridge_root)

    # A single continuous deck grade joins the banks without large steps.
    var deck_material := _make_material(Color(0.34, 0.235, 0.13, 1.0), 0.98).duplicate() as StandardMaterial3D
    deck_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    var seam_material := _make_material(Color(0.17, 0.105, 0.055, 1.0), 1.0)
    var deck_mesh := _build_bridge_ramp_mesh(deck_start2, deck_end2, side_normal, deck_width, deck_width, deck_start_y, deck_end_y)
    if deck_mesh:
        var deck := MeshInstance3D.new()
        deck.name = "ContinuousBridgeDeck"
        deck.mesh = deck_mesh
        deck.material_override = deck_material
        bridge_root.add_child(deck)
        deck.create_trimesh_collision()

    # Visible structure beneath the deck keeps the crossing from reading as a
    # floating ribbon. Long timber stringers carry the span into stone piers.
    var support_stone := _make_material(Color(0.255, 0.265, 0.25, 1.0), 1.0)
    var support_timber := _make_material(Color(0.19, 0.115, 0.058, 1.0), 0.99)
    var average_deck_y := (deck_start_y + deck_end_y) * 0.5
    for lateral_fraction in [-0.34, 0.0, 0.34]:
        var stringer := MeshInstance3D.new()
        stringer.name = "DeckStringer"
        var stringer_mesh := BoxMesh.new()
        stringer_mesh.size = Vector3(0.42, 0.46, maxf(4.0, span - 2.0))
        stringer.mesh = stringer_mesh
        stringer.position = Vector3(point.x, average_deck_y - 0.30, point.y) + Vector3(
            side_normal.x * deck_width * float(lateral_fraction),
            0.0,
            side_normal.y * deck_width * float(lateral_fraction)
        )
        stringer.rotation.y = yaw
        stringer.material_override = support_timber
        bridge_root.add_child(stringer)

    var river_bed_sampler: Callable = terrain_result.get("river_height_sampler", terrain_result.height_sampler)

    # The deck height sampler makes the top of the bridge traversable, but it
    # cannot know whether the player approached from a road end or from the
    # water below. Collision curtains beneath the visible side rails prevent
    # that sideways height-snap while leaving both bridge ends fully open.
    var center_bed_y: float = river_bed_sampler.call(point.x, point.y).y
    var barrier_bottom := center_bed_y - 0.35
    var barrier_top := maxf(deck_start_y, deck_end_y) + 1.55
    var barrier_height := maxf(2.0, barrier_top - barrier_bottom)
    for barrier_side in [-1.0, 1.0]:
        var side_barrier := StaticBody3D.new()
        side_barrier.name = "BridgeSideBarrier"
        side_barrier.collision_layer = 1
        side_barrier.position = Vector3(point.x, (barrier_top + barrier_bottom) * 0.5, point.y) + Vector3(
            side_normal.x * deck_width * 0.52 * float(barrier_side),
            0.0,
            side_normal.y * deck_width * 0.52 * float(barrier_side)
        )
        side_barrier.rotation.y = yaw
        var barrier_shape_node := CollisionShape3D.new()
        var barrier_shape := BoxShape3D.new()
        barrier_shape.size = Vector3(0.55, barrier_height, maxf(4.0, span - 1.0))
        barrier_shape_node.shape = barrier_shape
        side_barrier.add_child(barrier_shape_node)
        bridge_root.add_child(side_barrier)

    for pier_sign in [-1.0, 1.0]:
        var pier2 := point + tangent * (river_width * 0.22 * float(pier_sign))
        var pier_deck_y: float = terrain_result.height_sampler.call(pier2.x, pier2.y).y
        var pier_bed_y: float = river_bed_sampler.call(pier2.x, pier2.y).y
        var pier_height := maxf(1.0, pier_deck_y - pier_bed_y - 0.18)
        var pier := MeshInstance3D.new()
        pier.name = "RiverbedPier"
        var pier_mesh := BoxMesh.new()
        pier_mesh.size = Vector3(deck_width * 0.64, pier_height, 1.85)
        pier.mesh = pier_mesh
        pier.position = Vector3(pier2.x, pier_bed_y + pier_height * 0.5, pier2.y)
        pier.rotation.y = yaw
        pier.material_override = support_stone
        bridge_root.add_child(pier)

        var cap := MeshInstance3D.new()
        cap.name = "PierCap"
        var cap_mesh := BoxMesh.new()
        cap_mesh.size = Vector3(deck_width * 0.90, 0.38, 2.55)
        cap.mesh = cap_mesh
        cap.position = Vector3(pier2.x, pier_deck_y - 0.22, pier2.y)
        cap.rotation.y = yaw
        cap.material_override = support_stone
        bridge_root.add_child(cap)

    var seam_count := maxi(8, ceili(span / 7.0))
    for i in range(1, seam_count):
        var along := -span * 0.5 + float(i) * span / float(seam_count)
        var sample2 := point + tangent * along
        var sample_y: float = terrain_result.height_sampler.call(sample2.x, sample2.y).y
        var seam := MeshInstance3D.new()
        var seam_mesh := BoxMesh.new()
        seam_mesh.size = Vector3(deck_width + 0.12, 0.035, 0.11)
        seam.mesh = seam_mesh
        seam.position = Vector3(sample2.x, sample_y + 0.035, sample2.y)
        seam.rotation.y = yaw
        seam.material_override = seam_material
        bridge_root.add_child(seam)

    var rail_material := _make_material(Color(0.22, 0.135, 0.07, 1.0), 0.99)
    for side in [-1.0, 1.0]:
        for half in [-0.25, 0.25]:
            var along: float = float(half) * span
            var sample2: Vector2 = point + tangent * along
            var rail: MeshInstance3D = MeshInstance3D.new()
            var rail_y: float = terrain_result.height_sampler.call(sample2.x, sample2.y).y
            var rail_mesh := BoxMesh.new()
            rail_mesh.size = Vector3(0.26, 0.28, span * 0.5)
            rail.mesh = rail_mesh
            rail.position = Vector3(sample2.x, rail_y, sample2.y) + Vector3(side_normal.x * deck_width * 0.49 * side, 1.05, side_normal.y * deck_width * 0.49 * side)
            rail.rotation.y = yaw
            rail.material_override = rail_material
            bridge_root.add_child(rail)

    var post_count: int = maxi(4, ceili(span / 12.0))
    for i in range(post_count + 1):
        var frac := float(i) / float(post_count)
        var along := (frac - 0.5) * span
        var sample2 := point + tangent * along
        var post_y: float = terrain_result.height_sampler.call(sample2.x, sample2.y).y
        for side in [-1.0, 1.0]:
            var post: MeshInstance3D = MeshInstance3D.new()
            var post_mesh: BoxMesh = BoxMesh.new()
            post_mesh.size = Vector3(0.38, 1.45, 0.38)
            post.mesh = post_mesh
            post.position = Vector3(sample2.x, post_y, sample2.y) + Vector3(side_normal.x * deck_width * 0.49 * side, 0.72, side_normal.y * deck_width * 0.49 * side)
            post.material_override = rail_material
            bridge_root.add_child(post)

    var stone_material := _make_material(Color(0.29, 0.285, 0.26, 1.0), 1.0)
    var raw_height_sampler: Callable = terrain_result.get("terrain_height_sampler", terrain_result.height_sampler)
    for end_sign in [-1.0, 1.0]:
        var end2: Vector2 = point + tangent * (span * 0.5 * float(end_sign))
        var end_y: float = terrain_result.height_sampler.call(end2.x, end2.y).y
        var foundation := MeshInstance3D.new()
        foundation.name = "StoneBankFoundation"
        var foundation_mesh := BoxMesh.new()
        foundation_mesh.size = Vector3(deck_width + 1.4, 1.35, 2.8)
        foundation.mesh = foundation_mesh
        foundation.position = Vector3(end2.x, end_y - 0.68, end2.y)
        foundation.rotation.y = yaw
        foundation.material_override = stone_material
        bridge_root.add_child(foundation)
        for side in [-1.0, 1.0]:
            var abutment := MeshInstance3D.new()
            var stone := BoxMesh.new()
            stone.size = Vector3(1.2, 0.70, 1.8)
            abutment.mesh = stone
            abutment.position = Vector3(end2.x, end_y - 0.25, end2.y) + Vector3(
                side_normal.x * (deck_width * 0.5 + 0.7) * side,
                0.25,
                side_normal.y * (deck_width * 0.5 + 0.7) * side
            ) + Vector3(tangent.x * end_sign * 0.7, 0.0, tangent.y * end_sign * 0.7)
            abutment.rotation.y = yaw
            abutment.material_override = stone_material
            bridge_root.add_child(abutment)

        var ramp_run := 10.0
        var bank2 := point + tangent * ((span * 0.5 + ramp_run) * float(end_sign))
        var bank_ground: Vector3 = raw_height_sampler.call(bank2.x, bank2.y)
        var ramp_mesh := _build_bridge_ramp_mesh(
            end2,
            bank2,
            side_normal,
            deck_width,
            maxf(3.0, approach_width * 0.48),
            end_y,
            bank_ground.y + 0.185
        )
        if ramp_mesh:
            var ramp := MeshInstance3D.new()
            ramp.name = "TaperedBridgeApproach_%s" % ("A" if end_sign < 0.0 else "B")
            ramp.mesh = ramp_mesh
            ramp.material_override = deck_material
            bridge_root.add_child(ramp)
            ramp.create_trimesh_collision()

func _build_bridge_ramp_mesh(inner2: Vector2, outer2: Vector2, side_normal: Vector2, inner_width: float, outer_width: float, inner_y: float, outer_y: float) -> ArrayMesh:
    var inner_left := Vector3(inner2.x + side_normal.x * inner_width * 0.5, inner_y, inner2.y + side_normal.y * inner_width * 0.5)
    var inner_right := Vector3(inner2.x - side_normal.x * inner_width * 0.5, inner_y, inner2.y - side_normal.y * inner_width * 0.5)
    var outer_left := Vector3(outer2.x + side_normal.x * outer_width * 0.5, outer_y, outer2.y + side_normal.y * outer_width * 0.5)
    var outer_right := Vector3(outer2.x - side_normal.x * outer_width * 0.5, outer_y, outer2.y - side_normal.y * outer_width * 0.5)
    var thickness := 0.22
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_uv(Vector2(0.0, 0.0));st.add_vertex(inner_left)
    st.set_uv(Vector2(0.0, 1.0));st.add_vertex(outer_left)
    st.set_uv(Vector2(1.0, 0.0));st.add_vertex(inner_right)
    st.set_uv(Vector2(1.0, 0.0));st.add_vertex(inner_right)
    st.set_uv(Vector2(0.0, 1.0));st.add_vertex(outer_left)
    st.set_uv(Vector2(1.0, 1.0));st.add_vertex(outer_right)
    for pair in [[inner_left, outer_left], [outer_right, inner_right]]:
        var a: Vector3 = pair[0]
        var b: Vector3 = pair[1]
        st.add_vertex(a);st.add_vertex(b);st.add_vertex(a - Vector3.UP * thickness)
        st.add_vertex(a - Vector3.UP * thickness);st.add_vertex(b);st.add_vertex(b - Vector3.UP * thickness)
    st.generate_normals()
    return st.commit()


func _build_corridor_ribbon_mesh(points: Array, height_sampler: Callable, width: float, fixed_y: float, y_lift: float, force_flat: bool, exclusion_sites: Array = [], taper_edges: bool = false, edge_height_sampler: Callable = Callable()) -> ArrayMesh:
    if points.size() < 2:
        return null

    var left_side: Array[Vector3] = []
    var center_side: Array[Vector3] = []
    var right_side: Array[Vector3] = []
    var distances: Array[float] = []
    var accumulated:=0.0

    for i in range(points.size()):
        var point: Vector2 = points[i]
        var tangent: Vector2 = _polyline_tangent(points, i)
        if tangent.length_squared() <= 0.0001:
            continue
        var normal := Vector2(-tangent.y, tangent.x).normalized()
        var left2: Vector2 = point + normal * (width * 0.5)
        var right2: Vector2 = point - normal * (width * 0.5)

        var left3: Vector3 = height_sampler.call(left2.x, left2.y)
        var center3: Vector3 = height_sampler.call(point.x, point.y)
        var right3: Vector3 = height_sampler.call(right2.x, right2.y)
        if force_flat:
            # Rivers use one explicit waterline. The terrain builder guarantees
            # the entire channel floor is below it, so water cannot disappear
            # behind locally sampled terrain or break into isolated patches.
            left3.y = fixed_y
            center3.y = fixed_y
            right3.y = fixed_y
        elif edge_height_sampler.is_valid():
            # The terrain mesh is deliberately coarse for traversal performance.
            # Sample its actual interpolated collision surface at each shoreline
            # and bring only the outer water vertices down to meet it. This seals
            # the bank without widening the river or breaking its center grade.
            var surface_y := center3.y + y_lift
            var left_ground: Vector3 = edge_height_sampler.call(left2.x, left2.y)
            var right_ground: Vector3 = edge_height_sampler.call(right2.x, right2.y)
            center3.y = surface_y
            left3.y = minf(surface_y, left_ground.y + 0.035)
            right3.y = minf(surface_y, right_ground.y + 0.035)
        else:
            # Keep road and trail shoulders above coarse terrain triangles.
            # The former 0.02 edge offset was swallowed between grid vertices,
            # creating intermittent missing patches.
            var edge_lift := minf(0.08, y_lift) if taper_edges else y_lift
            left3.y += edge_lift
            center3.y += y_lift
            right3.y += edge_lift

        left_side.append(left3)
        center_side.append(center3)
        right_side.append(right3)
        if left_side.size()>1:
            var prev_center:Vector3=(left_side[-2]+right_side[-2])*.5
            accumulated+=prev_center.distance_to((left3+right3)*.5)
        distances.append(accumulated)

    if left_side.size() < 2 or right_side.size() < 2:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for i in range(left_side.size() - 1):
        var a_left: Vector3 = left_side[i]
        var a_center: Vector3 = center_side[i]
        var a_right: Vector3 = right_side[i]
        var b_left: Vector3 = left_side[i + 1]
        var b_center: Vector3 = center_side[i + 1]
        var b_right: Vector3 = right_side[i + 1]

        var quad_center := Vector2(
            (a_center.x + b_center.x) * 0.5,
            (a_center.z + b_center.z) * 0.5
        )
        if _inside_bridge_road_gap(quad_center, exclusion_sites):
            continue

        var va:=distances[i]/14.0;var vb:=distances[i+1]/14.0
        st.set_uv(Vector2(0,va));st.add_vertex(a_left)
        st.set_uv(Vector2(0,vb));st.add_vertex(b_left)
        st.set_uv(Vector2(.5,va));st.add_vertex(a_center)
        st.set_uv(Vector2(.5,va));st.add_vertex(a_center)
        st.set_uv(Vector2(0,vb));st.add_vertex(b_left)
        st.set_uv(Vector2(.5,vb));st.add_vertex(b_center)
        st.set_uv(Vector2(.5,va));st.add_vertex(a_center)
        st.set_uv(Vector2(.5,vb));st.add_vertex(b_center)
        st.set_uv(Vector2(1,va));st.add_vertex(a_right)
        st.set_uv(Vector2(1,va));st.add_vertex(a_right)
        st.set_uv(Vector2(.5,vb));st.add_vertex(b_center)
        st.set_uv(Vector2(1,vb));st.add_vertex(b_right)

    st.generate_normals()
    return st.commit()


func _inside_bridge_road_gap(point: Vector2, gaps: Array) -> bool:
    for gap in gaps:
        var center: Vector2 = gap.get("center", Vector2.ZERO)
        var direction: Vector2 = gap.get("direction", Vector2(0.0, 1.0))
        var offset := point - center
        if (
            absf(offset.dot(direction)) <= float(gap.get("half_length", 0.0))
            and absf(offset.cross(direction)) <= float(gap.get("half_width", 12.0))
        ):
            return true
    return false


func _road_bridge_gaps(road: Dictionary, profile: Dictionary) -> Array[Dictionary]:
    var gaps: Array[Dictionary] = []
    var road_points: Array = road.get("points", [])
    var road_width: float = float(road.get("width", 14.0))
    if road_points.size() < 2:
        return gaps
    for site in profile.get("ford_sites", []):
        var center: Vector2 = site.get("position", Vector2.ZERO)
        var road_info := _nearest_corridor_segment(center, [road])
        if road_info.is_empty() or float(road_info.get("distance", INF)) > 26.0:
            continue
        var river_info := _nearest_corridor_segment(center, profile.get("river_corridors", []))
        if river_info.is_empty() or float(river_info.get("distance", INF)) > 30.0:
            continue
        var river_width: float = float(river_info.get("width", 52.0))
        var deck_half := maxf(river_width + 10.0, road_width * 2.15) * 0.5
        gaps.append({
            "center": center,
            "direction": road_info.get("direction", Vector2(0.0, 1.0)),
            # The tapered ramp extends 10 units beyond the deck. Ending the
            # cutout one unit early tucks the dirt edge beneath its road end.
            "half_length": deck_half + 8.2,
            "half_width": maxf(10.0, road_width * 0.90),
        })
    return gaps


func _subdivide_polyline(points: Array, passes: int) -> Array:
    var result: Array = points.duplicate()
    for _pass in range(passes):
        if result.size() < 2:
            return result
        var next: Array = [result[0]]
        for i in range(result.size() - 1):
            var a: Vector2 = result[i]
            var b: Vector2 = result[i + 1]
            next.append(a.lerp(b, 0.25))
            next.append(a.lerp(b, 0.75))
        next.append(result[result.size() - 1])
        result = next
    return result


func _catmull_resample(points: Array, steps_per_segment: int) -> Array:
    if points.size() < 3 or steps_per_segment < 2:
        return points.duplicate()
    var result: Array = []
    var last := points.size() - 1
    for i in range(last):
        var p0: Vector2 = points[maxi(0, i - 1)]
        var p1: Vector2 = points[i]
        var p2: Vector2 = points[i + 1]
        var p3: Vector2 = points[mini(last, i + 2)]
        for step in range(steps_per_segment):
            var t := float(step) / float(steps_per_segment)
            var t2 := t * t
            var t3 := t2 * t
            result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
    result.append(points[last])
    return result


func _polyline_tangent(points: Array, index: int) -> Vector2:
    var current: Vector2 = points[index]
    if index == 0:
        return (points[1] - current).normalized()
    if index == points.size() - 1:
        return (current - points[index - 1]).normalized()
    var prev: Vector2 = (current - points[index - 1]).normalized()
    var next: Vector2 = (points[index + 1] - current).normalized()
    var blend: Vector2 = (prev + next).normalized()
    if blend.length_squared() <= 0.0001:
        return next
    return blend


func _segment_intersection(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Variant:
    var r: Vector2 = a2 - a1
    var s: Vector2 = b2 - b1
    var denom: float = r.cross(s)
    if absf(denom) <= 0.0001:
        return null
    var delta: Vector2 = b1 - a1
    var t: float = delta.cross(s) / denom
    var u: float = delta.cross(r) / denom
    if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
        return null
    return a1 + r * t


func _is_too_close_to_corridors(point: Vector2, corridors: Array, extra: float) -> bool:
    var cache_key:=_corridor_cache_key(corridors)
    if _corridor_segment_buckets.has(cache_key):
        var cache:Dictionary=_corridor_segment_buckets[cache_key]
        var bucket_key:=Vector2i(
            floori(point.x/CORRIDOR_BUCKET_SIZE),
            floori(point.y/CORRIDOR_BUCKET_SIZE)
        )
        for segment_data in cache.get(bucket_key,[]):
            var width:float=float(segment_data.width)*.5+extra
            if _distance_to_segment(point,segment_data.a,segment_data.b)<width:return true
        return false
    for corridor in corridors:
        var width: float = corridor.get("width", 24.0) * 0.5 + extra
        if _distance_to_polyline(point, corridor.get("points", [])) < width:
            return true
    return false


func _prepare_corridor_spatial_cache(profile:Dictionary)->void:
    _corridor_segment_buckets.clear()
    for corridor_kind in ["river_corridors","road_corridors","trail_corridors"]:
        var corridors:Array=profile.get(corridor_kind,[])
        var cache_key:=_corridor_cache_key(corridors)
        if cache_key.is_empty():continue
        var buckets:Dictionary={}
        for corridor in corridors:
            var points:Array=corridor.get("points",[])
            var width:=float(corridor.get("width",24.0))
            var padding:=width*.5+80.0
            for index in range(points.size()-1):
                var a:Vector2=points[index]
                var b:Vector2=points[index+1]
                var min_bucket:=Vector2i(
                    floori((minf(a.x,b.x)-padding)/CORRIDOR_BUCKET_SIZE),
                    floori((minf(a.y,b.y)-padding)/CORRIDOR_BUCKET_SIZE)
                )
                var max_bucket:=Vector2i(
                    floori((maxf(a.x,b.x)+padding)/CORRIDOR_BUCKET_SIZE),
                    floori((maxf(a.y,b.y)+padding)/CORRIDOR_BUCKET_SIZE)
                )
                var segment_data:={"a":a,"b":b,"width":width}
                for bucket_x in range(min_bucket.x,max_bucket.x+1):
                    for bucket_y in range(min_bucket.y,max_bucket.y+1):
                        var key:=Vector2i(bucket_x,bucket_y)
                        if not buckets.has(key):buckets[key]=[]
                        buckets[key].append(segment_data)
        _corridor_segment_buckets[cache_key]=buckets


func _corridor_cache_key(corridors:Array)->String:
    if corridors.is_empty():return ""
    var first_points:Array=corridors[0].get("points",[])
    if first_points.is_empty():return ""
    var last_points:Array=corridors[-1].get("points",[])
    var first:Vector2=first_points[0]
    var last:Vector2=last_points[-1] if not last_points.is_empty() else first
    return "%d|%d|%.3f|%.3f|%.3f|%.3f"%[
        corridors.size(),
        first_points.size(),
        first.x,
        first.y,
        last.x,
        last.y,
    ]


func _is_too_close_to_sites(point: Vector2, sites: Array, extra: float) -> bool:
    for site in sites:
        var center: Vector2 = site.get("position", Vector2.ZERO)
        var radius: float = site.get("radius", 90.0) * 0.42 + extra
        if point.distance_squared_to(center) < radius * radius:
            return true
    return false


func _tree_overlaps_authored_site(point:Vector2,profile:Dictionary,canopy_radius:float)->bool:
    # Tree trunks and crowns must stay outside complete settlement and camp
    # footprints. The generic proximity helper intentionally uses a reduced
    # radius for small ground dressing, which was not safe for full-size trees.
    var sites:Array=[]
    sites.append_array(profile.get("town_sites",[]))
    sites.append_array(profile.get("camp_sites",[]))
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty():sites.append(spawn_site)
    for site_value in sites:
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var center:Vector2=site.get("position",Vector2.ZERO)
        var clearance:=maxf(18.0,float(site.get("radius",0.0))+canopy_radius)
        if point.distance_squared_to(center)<clearance*clearance:return true
    return false


func _is_on_stone_walkway(point:Vector2,profile:Dictionary)->bool:
    for site_value in profile.get("town_sites",[]):
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var center:Vector2=site.get("position",Vector2.ZERO)
        var rel:=point-center
        if site.get("capital",false):
            # Crownspire's authored boulevard, market crossing and inner
            # bailey use raised stone slabs. Vegetation must not poke through
            # any of those surfaces.
            if absf(rel.x)<=11.5 and rel.y>=-34.0 and rel.y<=270.0:return true
            if absf(rel.y-28.0)<=9.0 and absf(rel.x)<=128.0:return true
            var bailey_rel:=point-(center+Vector2(0,-92))
            if absf(bailey_rel.x)<=73.0 and absf(bailey_rel.y)<=61.0:return true
        elif point.distance_to(center)<=30.0:
            # Regional market circles are also paved.
            return true
    return false


func _is_near_bridge_site(point: Vector2, sites: Array, clearance: float) -> bool:
    for site in sites:
        var center: Vector2 = site.get("position", Vector2.ZERO)
        if point.distance_squared_to(center) < clearance * clearance:
            return true
    return false


func _distance_to_polyline(point: Vector2, points: Array) -> float:
    if points.size() < 2:
        return INF
    var best_squared: float = INF
    for i in range(points.size() - 1):
        var a: Vector2 = points[i]
        var b: Vector2 = points[i + 1]
        var dx := maxf(maxf(minf(a.x, b.x) - point.x, 0.0), point.x - maxf(a.x, b.x))
        var dy := maxf(maxf(minf(a.y, b.y) - point.y, 0.0), point.y - maxf(a.y, b.y))
        if dx * dx + dy * dy >= best_squared:
            continue
        var ab := b - a
        var len2 := ab.length_squared()
        var distance_squared: float
        if len2 <= 0.0001:
            distance_squared = point.distance_squared_to(a)
        else:
            var t := clampf((point - a).dot(ab) / len2, 0.0, 1.0)
            distance_squared = point.distance_squared_to(a + ab * t)
        best_squared = minf(best_squared, distance_squared)
    return sqrt(best_squared)


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
    var ab: Vector2 = b - a
    var len2: float = ab.length_squared()
    if len2 <= 0.0001:
        return point.distance_to(a)
    var t: float = clampf((point - a).dot(ab) / len2, 0.0, 1.0)
    return point.distance_to(a + ab * t)


func _make_road_material() -> StandardMaterial3D:
    if _shared_materials.has("road"):return _shared_materials.road
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.70, 0.67, 0.62, 1.0)
    material.albedo_texture = load("res://assets/terrain/medieval_dirt_road_v1.png")
    material.uv1_scale = Vector3.ONE
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.roughness = 0.95
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.vertex_color_use_as_albedo = false
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials.road=material
    return material


func _make_trail_material() -> StandardMaterial3D:
    if _shared_materials.has("trail"):return _shared_materials.trail
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.86, 0.78, 0.62, 1.0)
    material.albedo_texture = load("res://assets/terrain/medieval_dirt_road_v1.png")
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials.trail=material
    return material


func _make_lit_window_material(color: Color) -> StandardMaterial3D:
    var key:="lit|"+color.to_html(true)
    if _shared_materials.has(key):return _shared_materials[key]
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color * 0.62
    material.emission_energy_multiplier = 1.6
    material.roughness = 0.28
    _shared_materials[key]=material
    return material


func _make_foliage_material(color: Color) -> ShaderMaterial:
    var key:="foliage|"+color.to_html(true)
    if _shared_materials.has(key):return _shared_materials[key]
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec4 leaf_color : source_color = vec4(0.18, 0.38, 0.17, 1.0);
uniform sampler2D foliage_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
varying float tree_tint;

void vertex() {
    vec3 anchor = MODEL_MATRIX[3].xyz;
    tree_tint = sin(anchor.x * 0.071 + anchor.z * 0.053) * 0.5 + 0.5;
    float height_mask = smoothstep(-0.85, 0.8, VERTEX.y);
    float breeze = sin(TIME * 0.72 + anchor.x * 0.017 + anchor.z * 0.013);
    float flutter = sin(TIME * 1.31 + anchor.x * 0.009 - anchor.z * 0.021);
    VERTEX.x += (breeze * 0.030 + flutter * 0.012) * height_mask;
    VERTEX.z += (flutter * 0.024) * height_mask;
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
    float variation = sin(world_position.x * 0.43 + world_position.z * 0.37) * 0.045;
    vec3 weights = pow(abs(normalize(world_normal)), vec3(4.0));
    weights /= max(0.001, weights.x + weights.y + weights.z);
    vec3 sample_position = world_position * 0.28;
    vec3 foliage = texture(foliage_texture, sample_position.zy).rgb * weights.x;
    foliage += texture(foliage_texture, sample_position.xz).rgb * weights.y;
    foliage += texture(foliage_texture, sample_position.xy).rgb * weights.z;
    vec3 normalized_tint = leaf_color.rgb / max(0.15, max(leaf_color.r, max(leaf_color.g, leaf_color.b)));
    foliage *= mix(vec3(0.84), normalized_tint * 1.10, 0.34);
    foliage *= mix(vec3(0.98,1.05,0.96), vec3(1.20,1.22,1.02), tree_tint);
    ALBEDO = foliage * (0.96 + variation);
    ROUGHNESS = 0.92;
    SPECULAR = 0.08;
    BACKLIGHT = ALBEDO * 0.16;
}
"""
    material.shader = shader
    material.set_shader_parameter("leaf_color", color)
    material.set_shader_parameter("foliage_texture",load("res://assets/vegetation/temperate_foliage_v1.png"))
    _shared_materials[key]=material
    return material


func _make_water_material() -> ShaderMaterial:
    if _shared_materials.has("water"):return _shared_materials.water
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // World-space ripples stay continuous where separate river ribbons join.
    // UV-space waves exposed every tributary mouth as a rectangular texture
    // reset even when the underlying water surfaces overlapped correctly.
    float along_a = sin(world_position.x * 0.047 + world_position.z * 0.083 - TIME * 1.05);
    float along_b = sin(world_position.x * -0.071 + world_position.z * 0.121 - TIME * 0.62);
    float cross_wave = sin(world_position.x * 0.145 - world_position.z * 0.039 + TIME * 0.34);
    float small_ripple = sin((world_position.x + world_position.z) * 0.31 - TIME * 1.55);
    vec3 ripple = normalize(vec3(
        (cross_wave * 0.050 + along_b * 0.025),
        1.0,
        (along_a * 0.060 + small_ripple * 0.018)
    ));
    NORMAL = normalize(mix(NORMAL, ripple, 0.68));

    float raw_depth = texture(depth_texture, SCREEN_UV).r;
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
    scene_view.xyz /= max(scene_view.w, 0.0001);
    vec4 surface_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
    surface_view.xyz /= max(surface_view.w, 0.0001);
    float water_depth = clamp((-scene_view.z) - (-surface_view.z), 0.0, 12.0);
    float depth_mix = smoothstep(0.15, 4.8, water_depth);

    vec2 distortion = NORMAL.xz * mix(0.003, 0.011, depth_mix);
    vec3 refracted = textureLod(screen_texture, SCREEN_UV + distortion, depth_mix * 0.24).rgb;
    vec3 shallow_water = vec3(0.018, 0.205, 0.29);
    vec3 deep_water = vec3(0.004, 0.052, 0.125);
    vec3 water_tint = mix(shallow_water, deep_water, depth_mix);
    vec3 transmitted = mix(refracted * vec3(0.52, 0.72, 0.77), water_tint, 0.74 + depth_mix * 0.12);
    float caustic_a = sin(world_position.x * 0.092 + world_position.z * 0.138 - TIME * 1.18);
    float caustic_b = sin(world_position.x * -0.127 + world_position.z * 0.104 - TIME * 0.83);
    float caustics = pow(max(0.0, caustic_a * caustic_b), 3.0) * (1.0 - depth_mix);
    transmitted += vec3(0.025, 0.060, 0.055) * caustics;

    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
    float flow_glint = smoothstep(0.72, 0.98, along_a * 0.5 + along_b * 0.28 + 0.64);
    // Strong ribbon-edge foam exposed every overlapping tributary mesh as a
    // white diagonal at confluences. Keep only a restrained shoreline glint.
    float bank_edge = smoothstep(0.47, 0.50, abs(UV.x - 0.5)) * 0.14;
    float foam_noise = sin(world_position.x * 0.113 + world_position.z * 0.067 - TIME * 0.9) * 0.5 + 0.5;
    float foam = clamp(bank_edge * foam_noise * 0.38, 0.0, 0.38);
    vec3 reflected_sky = vec3(0.13, 0.34, 0.47);
    vec3 final_color = mix(transmitted, reflected_sky, fresnel * 0.38 + flow_glint * 0.035);
    final_color = mix(final_color, vec3(0.025, 0.12, 0.13), bank_edge * (1.0 - foam) * 0.16);
    final_color = mix(final_color, vec3(0.76, 0.86, 0.84), foam);

    ALBEDO = final_color;
    ROUGHNESS = clamp(0.075 + foam * 0.18 + (small_ripple * 0.5 + 0.5) * 0.035, 0.07, 0.28);
    METALLIC = 0.0;
    SPECULAR = 0.92;
    ALPHA = clamp(0.90 + depth_mix * 0.06 + fresnel * 0.025 + foam * 0.025, 0.90, 0.985);
}
"""
    material.shader = shader
    _shared_materials.water=material
    return material


func _make_river_bank_material() -> StandardMaterial3D:
    if _shared_materials.has("river_bank"):return _shared_materials.river_bank
    var material := StandardMaterial3D.new()
    # The project environment has a cool green grade; use a warmer multiplier
    # so the soil texture still reads brown in the final lit scene.
    material.albedo_color = Color(.98,.66,.34,1.0)
    var texture:=load("res://assets/terrain/woodland_soil_v1.png") as Texture2D
    if texture:material.albedo_texture=texture
    material.uv1_triplanar=true
    material.uv1_world_triplanar=true
    material.uv1_scale=Vector3(.045,.045,.045)
    material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.roughness = 1.0
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials.river_bank=material
    return material


func _make_river_slope_material()->StandardMaterial3D:
    if _shared_materials.has("river_slope"):return _shared_materials.river_slope
    var material:=StandardMaterial3D.new()
    # This is ordinary turf rising behind the small soil shelf, not more
    # shoreline.  Keeping it green prevents the bank colour climbing hills.
    material.albedo_color=Color(.58,.82,.48,1.0)
    var texture:=load("res://assets/terrain/meadow_soil_realistic_v3.png") as Texture2D
    if texture:material.albedo_texture=texture
    material.uv1_triplanar=true
    material.uv1_world_triplanar=true
    material.uv1_scale=Vector3.ONE*.052
    material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.roughness=1.0
    material.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials.river_slope=material
    return material


func _make_channel_wall_material() -> StandardMaterial3D:
    if _shared_materials.has("channel_wall"):return _shared_materials.channel_wall
    var material := StandardMaterial3D.new()
    # This is exposed earth below the turf lip, not a constructed wall.  A
    # soil texture makes the narrow water edge readable without painting a
    # wide brown band up the surrounding hills.
    material.albedo_color = Color(.78,.62,.40,1.0)
    var texture:=load("res://assets/terrain/woodland_soil_v1.png") as Texture2D
    if texture:material.albedo_texture=texture
    material.uv1_triplanar=true
    material.uv1_world_triplanar=true
    material.uv1_scale=Vector3.ONE*.065
    material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials.channel_wall=material
    return material


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
    var key:="basic|%.4f|%.4f|%.4f|%.4f|%.3f"%[color.r,color.g,color.b,color.a,roughness]
    if _shared_materials.has(key):return _shared_materials[key]
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    _shared_materials[key]=material
    return material


func _make_texture_material(path: String, tint: Color, roughness: float, uv_scale: float) -> StandardMaterial3D:
    var key:="texture|%s|%s|%.3f|%.3f"%[path,tint.to_html(true),roughness,uv_scale]
    if _shared_materials.has(key):return _shared_materials[key]
    var material := _make_material(tint, roughness).duplicate() as StandardMaterial3D
    var texture: Texture2D = _architecture_textures.get(path)
    if not texture:
        texture=load(path) as Texture2D
        if texture:_architecture_textures[path]=texture
    if texture:
        material.albedo_texture = texture
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        material.texture_repeat = true
        # World-space triplanar mapping keeps stone and plaster at a consistent
        # physical scale across long plaza slabs and tall castle walls. This
        # removes both stretched masonry and the near-coplanar UV shimmer.
        material.uv1_triplanar=true
        material.uv1_world_triplanar=true
        # Castle stone and paving carry high-contrast detail. At the old
        # repeat frequency the texels collapsed into crawling noise while the
        # camera moved. A larger physical texel footprint, mipmaps and
        # anisotropic filtering keep the pattern stable at traversal distance.
        var stable_scale:=.15+minf(uv_scale,4.0)*.018
        if "dark_oak" in path:stable_scale=.24
        material.uv1_scale = Vector3.ONE*stable_scale
    _shared_materials[key]=material
    return material


func _make_bark_material(tint:Color=Color.WHITE)->StandardMaterial3D:
    return _make_texture_material("res://assets/vegetation/temperate_bark_v1.png",tint,1.0,3.2)


func _build_roadside_props(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var marker_mesh := BoxMesh.new()
    marker_mesh.size = Vector3(0.7, 1.2, 0.7)
    var transforms: Array[Transform3D] = []
    for road in profile.get("road_corridors", []):
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var width: float = road.get("width", 26.0)
        for i in range(1, points.size() - 1):
            var point: Vector2 = points[i]
            var tangent: Vector2 = (points[i + 1] - points[i - 1]).normalized()
            if tangent.length_squared() <= 0.0001:
                continue
            var normal := Vector2(-tangent.y, tangent.x).normalized()
            for side in [-1.0, 1.0]:
                var marker_pos2: Vector2 = point + normal * (width * 1.15 * side)
                if _is_too_close_to_corridors(marker_pos2, profile.get("river_corridors", []), 52.0):
                    continue
                var ground: Vector3 = terrain_result.height_sampler.call(marker_pos2.x, marker_pos2.y)
                var yaw := float(i) * 0.71 + float(side) * 0.18
                transforms.append(Transform3D(Basis(Vector3.UP, yaw), ground + Vector3(0.0, 0.6, 0.0)))
    _add_multimesh_batch(root, marker_mesh, transforms, Color(0.48, 0.46, 0.40, 1.0))


func _build_wayfinding_landmarks(root: Node3D, profile: Dictionary, terrain_result: Dictionary) -> void:
    var timber := _make_material(Color(0.20, 0.115, 0.055, 1.0), 0.98)
    var carved_wood := _make_material(Color(0.34, 0.20, 0.09, 1.0), 0.95).duplicate() as StandardMaterial3D
    carved_wood.emission_enabled = true
    carved_wood.emission = Color(0.055, 0.028, 0.010)
    carved_wood.emission_energy_multiplier = 0.35
    var lantern_material := _make_material(Color(0.92, 0.55, 0.12, 1.0), 0.45).duplicate() as StandardMaterial3D
    lantern_material.emission_enabled = true
    lantern_material.emission = Color(0.95, 0.38, 0.06)
    lantern_material.emission_energy_multiplier = 1.8

    for site in profile.get("ford_sites", []):
        var center: Vector2 = site.get("position", Vector2.ZERO)
        var road_info := _nearest_corridor_segment(center, profile.get("road_corridors", []))
        if road_info.is_empty():
            continue
        var direction: Vector2 = road_info.get("direction", Vector2(0.0, 1.0))
        var normal := Vector2(-direction.y, direction.x).normalized()
        var radius: float = float(site.get("radius", 62.0))
        var road_width: float = float(road_info.get("width", 14.0))
        for end_sign in [-1.0, 1.0]:
            var side_sign := float(end_sign)
            var marker2 := center + direction * (radius + 13.0) * side_sign + normal * road_width * 0.72 * side_sign
            if _is_too_close_to_corridors(marker2, profile.get("river_corridors", []), 54.0):
                marker2 += direction * 42.0 * side_sign
            var ground: Vector3 = terrain_result.height_sampler.call(marker2.x, marker2.y)
            var marker := Node3D.new()
            marker.position = ground
            marker.rotation.y = atan2(direction.x, direction.y)
            root.add_child(marker)
            _solid_box(marker, Vector3(0.32, 3.2, 0.32), Vector3(0.0, 1.6, 0.0), timber)
            _visual_box(marker, Vector3(0.72, 0.58, 0.72), Vector3(0.0, 3.25, 0.0), lantern_material)
            if end_sign < 0.0:
                # Project the board in front of the post so the upright cannot
                # show through its center.
                _solid_box(marker, Vector3(3.4, 0.72, 0.22), Vector3(0.0, 2.45, 0.28), carved_wood)
                var label := Label3D.new()
                label.text = str(site.get("name", "Bridge")).to_upper()
                label.position = Vector3(0.0, 2.45, 0.405)
                label.font_size = 42
                label.pixel_size = 0.008
                label.outline_size = 7
                label.modulate = Color(0.94, 0.82, 0.55)
                label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
                label.double_sided = false
                label.no_depth_test = false
                marker.add_child(label)

    var spawn: Vector2 = profile.get("spawn_site", {}).get("position", Vector2.ZERO)
    var sign2 := spawn + Vector2(15.0, 14.0)
    var sign_ground: Vector3 = terrain_result.height_sampler.call(sign2.x, sign2.y)
    var signpost := Node3D.new()
    signpost.position = sign_ground
    signpost.rotation.y = -0.48
    root.add_child(signpost)
    _solid_box(signpost, Vector3(0.38, 4.5, 0.38), Vector3(0.0, 2.25, 0.0), timber)
    _solid_box(signpost, Vector3(5.2, 1.55, 0.26), Vector3(0.0, 3.45, 0.30), carved_wood)
    _add_front_sign_label(signpost, "HIGHFIELD  ↑\nWESTMERE  ←   →  EASTREACH\nSOUTHBANK  ↓", Vector3(0.0, 3.45, 0.445), 34, 0.0075)


func _add_front_sign_label(root: Node3D, text: String, center: Vector3, font_size: int, pixel_size: float) -> void:
    var label := Label3D.new()
    label.text = text
    label.position = center
    label.font_size = font_size
    label.pixel_size = pixel_size
    label.outline_size = 7
    label.modulate = Color(0.96, 0.86, 0.62)
    label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
    label.double_sided = false
    label.no_depth_test = false
    root.add_child(label)
