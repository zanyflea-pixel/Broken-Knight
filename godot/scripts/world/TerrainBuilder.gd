extends RefCounted

const TERRAIN_MATERIAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const TERRAIN_CACHE_VERSION:=63
const TERRAIN_MESH_CACHE_VERSION:=3
const ENGINEERED_ROUTE_CACHE_VERSION:=1
const ENGINEERED_ROUTE_BAKE_DIR:="res://assets/world/generated/terrain_routes"
const TERRAIN_PROFILE_PATH:="res://data/world/profile.json"
const MAX_RIVER_BANK_GRADE:=0.42
const RIVER_TERRAIN_INFLUENCE:=620.0
const MAX_TERRAIN_CELL_GRADE:=0.28

var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _valley_noise: FastNoiseLite
var _biome_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _bridge_sites_cache: Array[Dictionary] = []
var _engineered_route_buckets:Dictionary={}
var _river_segment_buckets:Dictionary={}
var _river_walkable_buckets:Dictionary={}
var _surface_route_buckets:Dictionary={}
var _river_junctions:Array[Vector2]=[]
var _waterfall_grade_breaks:Array[Dictionary]=[]
var _last_sampled_river_distance := -1.0
const RIVER_BUCKET_SIZE:=256.0


func _init() -> void:
    _base_noise = FastNoiseLite.new()
    _base_noise.seed = 1401
    _base_noise.frequency = 0.0048
    _base_noise.fractal_octaves = 4
    _base_noise.fractal_gain = 0.52

    _detail_noise = FastNoiseLite.new()
    _detail_noise.seed = 9041
    _detail_noise.frequency = 0.015
    _detail_noise.fractal_octaves = 3
    _detail_noise.fractal_gain = 0.45

    _ridge_noise = FastNoiseLite.new()
    _ridge_noise.seed = 2217
    _ridge_noise.frequency = 0.0082
    _ridge_noise.fractal_octaves = 4
    _ridge_noise.fractal_gain = 0.48

    _valley_noise = FastNoiseLite.new()
    _valley_noise.seed = 7783
    _valley_noise.frequency = 0.0048
    _valley_noise.fractal_octaves = 2
    _valley_noise.fractal_gain = 0.5

    _biome_noise = FastNoiseLite.new()
    _biome_noise.seed = 4419
    _biome_noise.frequency = 0.0036
    _biome_noise.fractal_octaves = 3
    _biome_noise.fractal_gain = 0.5

    _moisture_noise = FastNoiseLite.new()
    _moisture_noise.seed = 9821
    _moisture_noise.frequency = 0.0051
    _moisture_noise.fractal_octaves = 2
    _moisture_noise.fractal_gain = 0.52


func generate_world(terrain_root: Node3D, profile: Dictionary) -> Dictionary:
    var profile_start_usec:=Time.get_ticks_usec()
    _clear_children(terrain_root)

    var world_size: float = profile.get("world_size", 2200.0)
    var grid_resolution: int = profile.get("grid_resolution", 220)
    var water_level: float = profile.get("water_level", -18.0)
    _prepare_bridge_cache(profile)
    _prepare_river_segment_cache(profile)
    _prepare_engineered_route_cache(profile)

    var expected_height_count:=(grid_resolution+1)*(grid_resolution+1)
    var heights:PackedFloat32Array=PackedFloat32Array()
    var river_distances:PackedFloat32Array=PackedFloat32Array()
    var terrain_cache_path:=_terrain_cache_path(profile)
    var cached_heightfield:=_load_heightfield_cache(terrain_cache_path,expected_height_count)
    if not cached_heightfield.is_empty():
        heights=cached_heightfield.heights
        river_distances=cached_heightfield.river_distances
        _profile_generation_step("heightfield_cache",profile_start_usec)
    else:
        heights.resize(expected_height_count)
        river_distances.resize(expected_height_count)
        for z_idx in range(grid_resolution + 1):
            for x_idx in range(grid_resolution + 1):
                var x: float = _grid_to_world(x_idx, grid_resolution, world_size)
                var z: float = _grid_to_world(z_idx, grid_resolution, world_size)
                _last_sampled_river_distance = -1.0
                var h: float = _sample_height(x, z, profile, world_size, water_level)
                var grid_index := _grid_index(x_idx, z_idx, grid_resolution)
                heights[grid_index] = h
                river_distances[grid_index] = _last_sampled_river_distance
        heights=_stabilize_heightfield(heights,grid_resolution,world_size)
        # Global slope repair must never become the final authority inside a
        # water channel. Reassert the authored bed and shoreline support after
        # stabilization; otherwise a low neighbouring valley can drag the
        # river vertices metres below the liquid and make the ribbon float.
        heights=_restore_river_channel_integrity(heights,river_distances,grid_resolution,world_size,water_level,profile)
        # Stabilizing steep river and mountain cells can tug the final row of
        # a settlement pad away from its authored elevation. Restore the
        # genuinely usable town interior, then feather it over several grid
        # cells so buildings never straddle a warped or stepped foundation.
        heights=_restore_settlement_interiors(heights,grid_resolution,world_size,profile)
        heights=_stabilize_heightfield_around_locked_rivers(heights,river_distances,grid_resolution,world_size,profile)
        # Adjacent streamed regions own separate heightfields. Reassert their
        # shared outer row after slope stabilization so both collision meshes
        # meet vertex-for-vertex instead of opening a visible/fall-through seam.
        heights=_restore_streaming_seam_edges(heights,grid_resolution,world_size,water_level,profile)
        _store_heightfield_cache(terrain_cache_path,heights,river_distances)
        _profile_generation_step("heightfield",profile_start_usec)

    var spawn_position: Vector3 = Vector3.ZERO
    var spawn_site: Dictionary = profile.get("spawn_site", {})
    var spawn_point: Vector2 = spawn_site.get("position", Vector2.ZERO)
    spawn_position = Vector3(
        spawn_point.x,
        _sample_heightfield(spawn_point.x, spawn_point.y, heights, world_size, grid_resolution),
        spawn_point.y
    )

    # The general sampled terrain mesh is the last verified construction for
    # the winding river. Keep it until a replacement is proven in-engine.
    var terrain_mesh_path:=_terrain_mesh_cache_path(profile,"mesh")
    var terrain_mesh:ArrayMesh
    if ResourceLoader.exists(terrain_mesh_path):terrain_mesh=load(terrain_mesh_path) as ArrayMesh
    if terrain_mesh==null:
        terrain_mesh=_build_terrain_mesh(heights,river_distances,profile,world_size,grid_resolution,water_level)
        _ensure_world_cache_directory()
        ResourceSaver.save(terrain_mesh,terrain_mesh_path)
    _profile_generation_step("mesh",profile_start_usec)
    var terrain_instance: MeshInstance3D = MeshInstance3D.new()
    terrain_instance.name = "TerrainMesh"
    terrain_instance.mesh = terrain_mesh
    terrain_instance.material_override = _make_terrain_material(profile)
    # The 28 m gameplay heightfield is deliberately coarse. Let it receive
    # shadows from trees and buildings, but do not let its own huge triangles
    # cast block-shaped mountain shadows across towns and roads.
    terrain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    terrain_root.add_child(terrain_instance)
    var terrain_shape:Shape3D
    var terrain_collision_scale:=Vector3.ONE
    if profile.get("streamed_heightmap_collision",false):
        # A terrain heightfield is already a regular grid. Feeding its values
        # directly to the physics server avoids deserializing a huge duplicate
        # triangle soup on the travel frame when an adjacent region appears.
        var heightmap_shape:=HeightMapShape3D.new()
        heightmap_shape.map_width=grid_resolution+1
        heightmap_shape.map_depth=grid_resolution+1
        heightmap_shape.map_data=heights
        terrain_shape=heightmap_shape
        var terrain_cell_size:float=world_size/float(grid_resolution)
        terrain_collision_scale=Vector3(terrain_cell_size,1.0,terrain_cell_size)
    else:
        var collision_path:=_terrain_mesh_cache_path(profile,"collision")
        if ResourceLoader.exists(collision_path):terrain_shape=load(collision_path) as ConcavePolygonShape3D
        if terrain_shape==null:
            terrain_shape=terrain_mesh.create_trimesh_shape()
            _ensure_world_cache_directory()
            ResourceSaver.save(terrain_shape,collision_path)
    var terrain_body:=StaticBody3D.new()
    terrain_body.name="TerrainMesh_StaticBody"
    terrain_body.collision_layer=1
    var terrain_collision:=CollisionShape3D.new()
    terrain_collision.name="TerrainMeshCollision"
    terrain_collision.shape=terrain_shape
    terrain_collision.scale=terrain_collision_scale
    terrain_body.add_child(terrain_collision)
    terrain_instance.add_child(terrain_body)
    _profile_generation_step("collision",profile_start_usec)

    # No ocean plane in the controlled aqueduct test world.

    var road_junctions := _collect_road_junctions(profile.get("road_corridors", []))
    _prepare_surface_route_cache(profile, road_junctions)
    return {
        "spawn_position": spawn_position,
        "water_level": water_level,
        "height_sampler": func(x: float, z: float) -> Vector3:
            var sampled_height := _sample_heightfield(x, z, heights, world_size, grid_resolution)
            var bridge_info := _bridge_deck_info(Vector2(x, z), profile)
            if not bridge_info.is_empty():
                var terrain_blend: float = float(bridge_info.get("terrain_blend", 0.0))
                var bridge_height := lerpf(
                    float(bridge_info.get("height", sampled_height)),
                    sampled_height + float(bridge_info.get("bank_lift", 0.0)),
                    terrain_blend
                )
                sampled_height = bridge_height if terrain_blend <= 0.0 else maxf(sampled_height, bridge_height)
            else:
                # Roads are rendered above the terrain with a shallow crown.
                # Give movement the identical profile so feet rest on the
                # visible road instead of continuing to follow the grass below.
                var point := Vector2(x, z)
                sampled_height += _surface_route_offset(point)
            return Vector3(x, sampled_height, z),
        "terrain_height_sampler": func(x: float, z: float) -> Vector3:
            var sampled_height:=_sample_heightfield(x,z,heights,world_size,grid_resolution)
            return Vector3(x,sampled_height,z),
        "structure_height_sampler": func(x: float, z: float, current_y: float) -> float:
            return _castle_structure_height(Vector2(x, z), current_y, profile),
        "river_height_sampler": func(x: float, z: float) -> Vector3:
            var river_grade:=_river_centerline_grade(Vector2(x,z),profile)
            return Vector3(x, river_grade - 2.8, z),
        "walkable_sampler": func(x: float, z: float) -> bool:
            var inside_world := absf(x) < world_size * 0.49 and absf(z) < world_size * 0.49
            var point := Vector2(x, z)
            var inside_channel := false
            var local_river:=_nearest_cached_walkable_river_segment(point,profile)
            if not local_river.is_empty():
                # Only the deeper central channel is blocked. The outer bank
                # remains walkable so the hero can approach and wade through
                # the gently submerged shelf without crossing the whole river.
                var channel_limit: float = float(local_river.get("width", 84.0)) * 0.35
                # Bridge sites are intentional access points. Let the player
                # wade farther into the water beside a bridge while retaining
                # a blocked deep core, so this does not become an accidental
                # walk-across ford.
                for ford in profile.get("ford_sites", []):
                    var ford_center: Vector2 = ford.get("position", Vector2.ZERO)
                    var ford_radius: float = float(ford.get("radius", 62.0))
                    if point.distance_to(ford_center) <= ford_radius * 1.15:
                        channel_limit = float(local_river.get("width", 84.0)) * 0.24
                        break
                if float(local_river.get("distance", INF)) < channel_limit:
                    inside_channel = true
            var on_bridge := not _bridge_deck_info(point, profile).is_empty()
            var inside_ocean:=_point_inside_ocean_water(point,profile,12.0)
            return inside_world and not inside_ocean and (not inside_channel or on_bridge),
    }


func _profile_generation_step(label:String,start_usec:int)->void:
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")!="1":return
    print("TERRAIN_BUILD_PROFILE|%s|elapsed_ms=%.1f"%[
        label,
        float(Time.get_ticks_usec()-start_usec)/1000.0,
    ])


func _terrain_cache_path(profile:Dictionary)->String:
    var zone_id:=str(profile.get("zone_id","starting_realm")).validate_filename()
    # Most decorative data does not affect terrain. Named elevation landmarks
    # are an exception: overlooks and hill forts now author the ground beneath
    # them, so map and landmark sites belong in the heightfield signature.
    var terrain_profile:Dictionary={}
    for key in [
        "world_size","grid_resolution","water_level","controlled_aqueduct",
        "spawn_site","town_sites","mountain_chains","landform_regions",
        "pond_sites","ocean_basins","waterfall_sites","river_corridors","road_corridors","trail_corridors",
        "ford_sites","forest_regions","landmark_sites","map_sites",
        "region_origin","seam_edges",
    ]:
        terrain_profile[key]=profile.get(key)
    var profile_hash:=str(hash(terrain_profile)).replace("-","n")
    # TERRAIN_CACHE_VERSION is the explicit invalidation switch for height
    # formula changes. File timestamps invalidated the cache after harmless
    # shader, landmark or comment edits and caused needless long launches.
    return "user://terrain_%s_v%d_%s.cache"%[
        zone_id,TERRAIN_CACHE_VERSION,profile_hash
    ]


func _terrain_mesh_cache_path(profile:Dictionary,kind:String)->String:
    var signature_source:=_terrain_cache_path(profile).get_file().get_basename()
    # Palette edits change vertex colour but not height/collision. Keep that
    # distinction so an art pass refreshes only the render mesh.
    if kind=="mesh":signature_source+=var_to_str(profile.get("terrain_palette_regions",[]))
    var terrain_signature:=str(hash(signature_source)).replace("-","n")
    return "user://world_cache/%s_v%d_%s.res"%[kind,TERRAIN_MESH_CACHE_VERSION,terrain_signature]


func _ensure_world_cache_directory()->void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://world_cache"))


func _load_heightfield_cache(path:String,expected_count:int)->Dictionary:
    if not FileAccess.file_exists(path):return {}
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null:return {}
    var value:Variant=file.get_var(false)
    if not value is Dictionary:return {}
    var cache:Dictionary=value
    var heights:PackedFloat32Array=cache.get("heights",PackedFloat32Array())
    var river_distances:PackedFloat32Array=cache.get("river_distances",PackedFloat32Array())
    if heights.size()!=expected_count or river_distances.size()!=expected_count:return {}
    return {"heights":heights,"river_distances":river_distances}


func _store_heightfield_cache(path:String,heights:PackedFloat32Array,river_distances:PackedFloat32Array)->void:
    var file:=FileAccess.open(path,FileAccess.WRITE)
    if file==null:return
    file.store_var({"heights":heights,"river_distances":river_distances},false)


func _clear_children(root: Node) -> void:
    for child in root.get_children():
        # Zone replacement runs while the tree is paused. Free the old
        # heightfield immediately so its large mesh and collision do not
        # overlap the newly generated zone for an extra frame.
        child.free()


func _grid_to_world(idx: int, grid_resolution: int, world_size: float) -> float:
    return ((float(idx) / float(grid_resolution)) - 0.5) * world_size


func _grid_index(x_idx: int, z_idx: int, grid_resolution: int) -> int:
    return z_idx * (grid_resolution + 1) + x_idx


func _sample_heightfield(x: float, z: float, heights: PackedFloat32Array, world_size: float, grid_resolution: int) -> float:
    # Match the exact diagonal and linear interpolation used by
    # _build_terrain_mesh. This keeps the player on the rendered triangles,
    # rather than on the smoother source formula between grid vertices.
    var gx := clampf((x / world_size + 0.5) * float(grid_resolution), 0.0, float(grid_resolution) - 0.0001)
    var gz := clampf((z / world_size + 0.5) * float(grid_resolution), 0.0, float(grid_resolution) - 0.0001)
    var x0 := clampi(int(floor(gx)), 0, grid_resolution - 1)
    var z0 := clampi(int(floor(gz)), 0, grid_resolution - 1)
    var fx := gx - float(x0)
    var fz := gz - float(z0)
    var a := heights[_grid_index(x0, z0, grid_resolution)]
    var b := heights[_grid_index(x0 + 1, z0, grid_resolution)]
    var c := heights[_grid_index(x0, z0 + 1, grid_resolution)]
    var d := heights[_grid_index(x0 + 1, z0 + 1, grid_resolution)]
    if fx + fz <= 1.0:
        return a + (b - a) * fx + (c - a) * fz
    var weight_d := fx + fz - 1.0
    var weight_b := 1.0 - fz
    var weight_c := 1.0 - fx
    return d * weight_d + b * weight_b + c * weight_c


func _stabilize_heightfield(heights:PackedFloat32Array,grid_resolution:int,world_size:float)->PackedFloat32Array:
    # A heightfield cannot form an actual topological hole, but a very tall
    # single-cell face behaves like one in play: the player falls beside it and
    # sees the culled underside. Bound every shared grid edge to a steep but
    # traversable cliff grade. This final integrity pass covers river valleys,
    # route cuts, settlement pads and cave mountains with the same contract.
    var stride:=grid_resolution+1
    var maximum_delta:=world_size/maxf(1.0,float(grid_resolution))*MAX_TERRAIN_CELL_GRADE
    for iteration in range(12):
        var changed:=false
        for z_index in range(stride):
            for x_index in range(stride):
                var index:=z_index*stride+x_index
                if x_index<grid_resolution:
                    var right:=index+1
                    var difference:=float(heights[index])-float(heights[right])
                    if difference>maximum_delta:
                        heights[index]=float(heights[right])+maximum_delta;changed=true
                    elif difference < -maximum_delta:
                        heights[right]=float(heights[index])+maximum_delta;changed=true
                if z_index<grid_resolution:
                    var below:=index+stride
                    var difference:=float(heights[index])-float(heights[below])
                    if difference>maximum_delta:
                        heights[index]=float(heights[below])+maximum_delta;changed=true
                    elif difference < -maximum_delta:
                        heights[below]=float(heights[index])+maximum_delta;changed=true
        for z_index in range(grid_resolution,-1,-1):
            for x_index in range(grid_resolution,-1,-1):
                var index:=z_index*stride+x_index
                if x_index>0:
                    var left:=index-1
                    var difference:=float(heights[index])-float(heights[left])
                    if difference>maximum_delta:
                        heights[index]=float(heights[left])+maximum_delta;changed=true
                    elif difference < -maximum_delta:
                        heights[left]=float(heights[index])+maximum_delta;changed=true
                if z_index>0:
                    var above:=index-stride
                    var difference:=float(heights[index])-float(heights[above])
                    if difference>maximum_delta:
                        heights[index]=float(heights[above])+maximum_delta;changed=true
                    elif difference < -maximum_delta:
                        heights[above]=float(heights[index])+maximum_delta;changed=true
        if not changed:break
    return heights


func _restore_river_channel_integrity(heights:PackedFloat32Array,river_distances:PackedFloat32Array,grid_resolution:int,world_size:float,water_level:float,profile:Dictionary)->PackedFloat32Array:
    if profile.get("river_corridors",[]).is_empty():return heights
    var maximum_width:=0.0
    for river_value in profile.get("river_corridors",[]):
        if not river_value is Dictionary:continue
        var river:Dictionary=river_value
        maximum_width=maxf(maximum_width,float(river.get("width",44.0)))
        maximum_width=maxf(maximum_width,float(river.get("source_width",maximum_width)))
        maximum_width=maxf(maximum_width,float(river.get("mouth_width",maximum_width)))
    var grid_step:=world_size/maxf(1.0,float(grid_resolution))
    # Protect the complete triangle support beneath visible water. The outer
    # bank is then relaxed around these locked vertices in the next pass,
    # preserving both contact and the global single-cell grade contract.
    var restore_radius:=maximum_width*.42+grid_step*.55
    var stride:=grid_resolution+1
    for z_index in range(stride):
        for x_index in range(stride):
            var index:=z_index*stride+x_index
            var distance:=float(river_distances[index])
            if distance<0.0 or distance>restore_radius:continue
            var x:=_grid_to_world(x_index,grid_resolution,world_size)
            var z:=_grid_to_world(z_index,grid_resolution,world_size)
            heights[index]=_sample_height(x,z,profile,world_size,water_level)
    return heights


func _stabilize_heightfield_around_locked_rivers(heights:PackedFloat32Array,river_distances:PackedFloat32Array,grid_resolution:int,world_size:float,profile:Dictionary)->PackedFloat32Array:
    var maximum_width:=0.0
    for river_value in profile.get("river_corridors",[]):
        if not river_value is Dictionary:continue
        var river:Dictionary=river_value
        maximum_width=maxf(maximum_width,float(river.get("width",44.0)))
        maximum_width=maxf(maximum_width,float(river.get("source_width",maximum_width)))
        maximum_width=maxf(maximum_width,float(river.get("mouth_width",maximum_width)))
    var grid_step:=world_size/maxf(1.0,float(grid_resolution))
    var lock_radius:=maximum_width*.42+grid_step*.55+.01
    var locks:=PackedByteArray();locks.resize(heights.size())
    var stride:=grid_resolution+1
    var protected_sites:Array=[]
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty():protected_sites.append(spawn_site)
    protected_sites.append_array(profile.get("town_sites",[]))
    for map_site in profile.get("map_sites",[]):
        if map_site is Dictionary and map_site.get("usable_ground",false):protected_sites.append(map_site)
    for z_index in range(stride):
        for x_index in range(stride):
            var index:=z_index*stride+x_index
            var distance:=float(river_distances[index])
            var locked:=distance>=0.0 and distance<=lock_radius
            if not locked:
                var point:=Vector2(
                    _grid_to_world(x_index,grid_resolution,world_size),
                    _grid_to_world(z_index,grid_resolution,world_size)
                )
                for site_value in protected_sites:
                    if not site_value is Dictionary:continue
                    var site:Dictionary=site_value
                    var inner_radius:=float(site.get("radius",120.0))*minf(float(site.get("ground_inner_ratio",.78)),.78)
                    if point.distance_squared_to(Vector2(site.get("position",Vector2.ZERO)))<=inner_radius*inner_radius:
                        locked=true
                        break
            locks[index]=1 if locked else 0
    var maximum_delta:=grid_step*MAX_TERRAIN_CELL_GRADE
    for iteration in range(28):
        var changed:=false
        for z_index in range(stride):
            for x_index in range(stride):
                var index:=z_index*stride+x_index
                if x_index<grid_resolution:
                    changed=_constrain_height_pair(heights,locks,index,index+1,maximum_delta) or changed
                if z_index<grid_resolution:
                    changed=_constrain_height_pair(heights,locks,index,index+stride,maximum_delta) or changed
        for z_index in range(grid_resolution,-1,-1):
            for x_index in range(grid_resolution,-1,-1):
                var index:=z_index*stride+x_index
                if x_index>0:
                    changed=_constrain_height_pair(heights,locks,index,index-1,maximum_delta) or changed
                if z_index>0:
                    changed=_constrain_height_pair(heights,locks,index,index-stride,maximum_delta) or changed
        if not changed:break
    return heights


func _constrain_height_pair(heights:PackedFloat32Array,locks:PackedByteArray,index_a:int,index_b:int,maximum_delta:float)->bool:
    var height_a:=float(heights[index_a])
    var height_b:=float(heights[index_b])
    var difference:=height_a-height_b
    if absf(difference)<=maximum_delta:return false
    var a_locked:=locks[index_a]!=0
    var b_locked:=locks[index_b]!=0
    if a_locked and b_locked:
        # Authored water can contain a deliberate waterfall step. Both sides
        # still remain real terrain and are never separated from the liquid.
        return false
    if a_locked:
        heights[index_b]=height_a-signf(difference)*maximum_delta
    elif b_locked:
        heights[index_a]=height_b+signf(difference)*maximum_delta
    else:
        var midpoint:=(height_a+height_b)*.5
        var half_delta:=maximum_delta*.5*signf(difference)
        heights[index_a]=midpoint+half_delta
        heights[index_b]=midpoint-half_delta
    return true


func _restore_settlement_interiors(heights:PackedFloat32Array,grid_resolution:int,world_size:float,profile:Dictionary)->PackedFloat32Array:
    var sites:Array=[]
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty():sites.append(spawn_site)
    sites.append_array(profile.get("town_sites",[]))
    for map_site in profile.get("map_sites",[]):
        if map_site is Dictionary and map_site.get("usable_ground",false):sites.append(map_site)
    if sites.is_empty():return heights
    var cell_size:=world_size/maxf(1.0,float(grid_resolution))
    var repair_sites:Array=[]
    for site_value in sites:
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:=float(site.get("radius",120.0))
        var inner_radius:=radius*minf(float(site.get("ground_inner_ratio",.78)),.78)
        var minimum:=INF
        var maximum:=-INF
        for z_index in range(grid_resolution+1):
            var world_z:=_grid_to_world(z_index,grid_resolution,world_size)
            for x_index in range(grid_resolution+1):
                var world_x:=_grid_to_world(x_index,grid_resolution,world_size)
                if Vector2(world_x,world_z).distance_squared_to(center)>inner_radius*inner_radius:continue
                var value:=float(heights[_grid_index(x_index,z_index,grid_resolution)])
                minimum=minf(minimum,value);maximum=maxf(maximum,value)
        # Do not touch an already stable settlement. Rebuilding every pad
        # unnecessarily disturbed Crownspire's intentional high-ground blend.
        if maximum-minimum>1.25:repair_sites.append(site)
    if repair_sites.is_empty():return heights
    for z_index in range(grid_resolution+1):
        var world_z:=_grid_to_world(z_index,grid_resolution,world_size)
        for x_index in range(grid_resolution+1):
            var world_x:=_grid_to_world(x_index,grid_resolution,world_size)
            var point:=Vector2(world_x,world_z)
            var grid_index:=_grid_index(x_index,z_index,grid_resolution)
            for site_value in repair_sites:
                if not site_value is Dictionary:continue
                var site:Dictionary=site_value
                var center:Vector2=site.get("position",Vector2.ZERO)
                var radius:=float(site.get("radius",120.0))
                var authored_inner:=float(site.get("ground_inner_ratio",.78))
                # .78 is wide enough to keep every triangle sampled inside the
                # gameplay town core level, without flattening a whole region.
                var inner_radius:=radius*minf(authored_inner,.78)
                # Match the broad authored settlement transition. A short
                # repair ring around Crownspire reintroduced an eight-metre
                # single-cell ledge even though its interior became level.
                var outer_radius:=maxf(
                    radius*1.55,
                    maxf(radius*authored_inner+72.0,inner_radius+cell_size*5.0)
                )
                var distance:=point.distance_to(center)
                if distance>outer_radius:continue
                var target:=float(site.get("ground_height",heights[grid_index]))
                if distance<=inner_radius:
                    heights[grid_index]=target
                else:
                    var weight:=1.0-_smoothstep(inner_radius,outer_radius,distance)
                    heights[grid_index]=lerpf(float(heights[grid_index]),target,weight)
                break
    return heights


func _restore_streaming_seam_edges(heights:PackedFloat32Array,grid_resolution:int,world_size:float,water_level:float,profile:Dictionary)->PackedFloat32Array:
    var seam_edges:Array=profile.get("seam_edges",[])
    if seam_edges.is_empty():return heights
    var cell_size:=world_size/maxf(1.0,float(grid_resolution))
    var has_north_edge:=_profile_has_streaming_edge(profile,"north")
    var has_south_edge:=_profile_has_streaming_edge(profile,"south")
    var has_east_edge:=_profile_has_streaming_edge(profile,"east")
    var has_west_edge:=_profile_has_streaming_edge(profile,"west")
    for seam_value in seam_edges:
        if not seam_value is Dictionary:continue
        var edge:=str(seam_value.get("edge",""))
        # The final boundary row was already watertight, but the last global
        # slope-repair pass could leave the first one or two interior rows far
        # from that shared datum. Reassert a short section of the authored
        # 620 m approach after stabilization so walking/riding onto a streamed
        # neighbour cannot encounter a cliff in the final 45 m.
        var blend_width:=maxf(64.0,float(seam_value.get("blend_width",620.0)))
        var repair_depth:=minf(blend_width,maxf(120.0,cell_size*5.0))
        var repair_cells:=maxi(1,ceili(repair_depth/cell_size))
        if edge in ["north","south"]:
            for inward_cell in range(repair_cells+1):
                var z_index:=grid_resolution-inward_cell if edge=="north" else inward_cell
                var world_z:=_grid_to_world(z_index,grid_resolution,world_size)
                var inward_distance:=float(inward_cell)*cell_size
                var weight:=1.0 if inward_cell==0 else 1.0-_smoothstep(0.0,blend_width,inward_distance)
                for x_index in range(grid_resolution+1):
                    # A perpendicular seam owns its complete outer boundary
                    # column, including the several rows inside this corner
                    # blend. Do not overwrite that column with this edge's
                    # approach curve or adjacent terrain tiles diverge just
                    # before a four-region junction.
                    if x_index==0 and has_west_edge:continue
                    if x_index==grid_resolution and has_east_edge:continue
                    var world_x:=_grid_to_world(x_index,grid_resolution,world_size)
                    var point:=Vector2(world_x,world_z)
                    var crossing_height:=_authored_streaming_river_crossing_height(world_x,seam_value,profile)
                    var endpoint_influence:=_streaming_river_endpoint_influence(point,edge,profile)
                    if inward_cell>0 and (is_finite(crossing_height) or endpoint_influence):continue
                    var final_height:=_streaming_seam_curve(world_x,seam_value,profile)
                    if inward_cell==0 and is_finite(crossing_height):final_height=crossing_height
                    elif inward_cell==0 and endpoint_influence:final_height=_sample_height(world_x,world_z,profile,world_size,water_level)
                    var index:=_grid_index(x_index,z_index,grid_resolution)
                    heights[index]=lerpf(float(heights[index]),final_height,weight)
        elif edge in ["east","west"]:
            for inward_cell in range(repair_cells+1):
                var x_index:=grid_resolution-inward_cell if edge=="east" else inward_cell
                var world_x:=_grid_to_world(x_index,grid_resolution,world_size)
                var inward_distance:=float(inward_cell)*cell_size
                var weight:=1.0 if inward_cell==0 else 1.0-_smoothstep(0.0,blend_width,inward_distance)
                for z_index in range(grid_resolution+1):
                    if z_index==0 and has_south_edge:continue
                    if z_index==grid_resolution and has_north_edge:continue
                    var world_z:=_grid_to_world(z_index,grid_resolution,world_size)
                    var point:=Vector2(world_x,world_z)
                    var crossing_height:=_authored_streaming_river_crossing_height(world_z,seam_value,profile)
                    var endpoint_influence:=_streaming_river_endpoint_influence(point,edge,profile)
                    if inward_cell>0 and (is_finite(crossing_height) or endpoint_influence):continue
                    var final_height:=_streaming_seam_curve(world_z,seam_value,profile)
                    if inward_cell==0 and is_finite(crossing_height):final_height=crossing_height
                    elif inward_cell==0 and endpoint_influence:final_height=_sample_height(world_x,world_z,profile,world_size,water_level)
                    var index:=_grid_index(x_index,z_index,grid_resolution)
                    heights[index]=lerpf(float(heights[index]),final_height,weight)
    return heights


func _profile_has_streaming_edge(profile:Dictionary,edge_name:String)->bool:
    for seam_value in profile.get("seam_edges",[]):
        if seam_value is Dictionary and str(seam_value.get("edge",""))==edge_name:return true
    return false


func _authored_streaming_river_crossing_height(local_along:float,seam:Dictionary,profile:Dictionary)->float:
    var crossings:Array=seam.get("river_crossings",[])
    if crossings.is_empty():return INF
    var edge:=str(seam.get("edge",""))
    var origin:Vector2=profile.get("region_origin",Vector2.ZERO)
    var global_along:=local_along+(origin.y if edge in ["east","west"] else origin.x)
    var seam_height:=_streaming_seam_curve(local_along,seam,profile)
    var best_weight:=0.0
    var result:=seam_height
    for crossing_value in crossings:
        if not crossing_value is Dictionary:continue
        var crossing:Dictionary=crossing_value
        var width:=maxf(2.0,float(crossing.get("width",24.0)))
        var distance:=absf(global_along-float(crossing.get("along",global_along)))
        # A rendered channel is backed by a full coarse-grid triangle beyond
        # its nominal half-width. Hold the shared submerged bed across that
        # support envelope, then feather it into the pass outside the liquid.
        # The previous center-only falloff left a transverse terrain lip in
        # the water whenever a river crossed a streamed boundary.
        var weight:=1.0-_smoothstep(width*.96,width*1.55,distance)
        if weight<=best_weight:continue
        best_weight=weight
        result=lerpf(seam_height,float(crossing.get("bed_height",seam_height)),weight)
    return result if best_weight>0.0 else INF


func _sample_height(x: float, z: float, profile: Dictionary, world_size: float, water_level: float) -> float:
    if profile.get("controlled_aqueduct", false):
        return _sample_controlled_aqueduct_height(x, z, profile, water_level)
    var point := Vector2(x, z)
    # Controlled test world: a level plane with explicit aqueduct cuts only.
    var height := 3.0
    for river in profile.get("river_corridors", []):
        height = _carve_river_valley(height, point, river, water_level)
    return height


func _sample_controlled_aqueduct_height(x: float, z: float, profile: Dictionary, water_level: float) -> float:
    var point:=Vector2(x,z)
    var surface:=_land_surface_without_water(point,profile)
    var corridors: Array = profile.get("river_corridors", [])
    if corridors.is_empty():
        return surface
    var width := 84.0
    var dist := INF
    var grade_x:=x
    var grade_corridor_index:=-1
    var grade_progress:=0.0
    var nearby_segments:Array=_river_segment_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),
        []
    )
    for segment_data in nearby_segments:
        var segment:Vector2=segment_data.b-segment_data.a
        var segment_t:=0.0
        if segment.length_squared()>.0001:
            segment_t=clampf((point-segment_data.a).dot(segment)/segment.length_squared(),0.0,1.0)
        var closest_point:Vector2=segment_data.a+segment*segment_t
        var candidate_dist:=point.distance_to(closest_point)
        if candidate_dist < dist:
            dist = candidate_dist
            width = lerpf(float(segment_data.width_a),float(segment_data.width_b),segment_t)
            grade_x=closest_point.x
            grade_corridor_index=int(segment_data.get("corridor_index",-1))
            grade_progress=lerpf(float(segment_data.get("start_progress",0.0)),float(segment_data.get("end_progress",1.0)),segment_t)
    # Defensive fallback for direct unit calls made before generate_world().
    if _river_segment_buckets.is_empty():
        for candidate in corridors:
            var nearest_candidate := _nearest_road_segment(point, [candidate])
            if nearest_candidate.is_empty():
                continue
            var candidate_dist: float = float(nearest_candidate.get("distance", INF))
            if candidate_dist < dist:
                dist = candidate_dist
                width = float(nearest_candidate.get("width", width))
                grade_x=Vector2(nearest_candidate.get("closest_point",point)).x
    _last_sampled_river_distance = dist
    var half_channel := width * 0.5
    # Predictable east-to-west fall. Small undulation preserves a natural bed
    # without creating uphill water or disconnected pools.
    # A gentle world-scale fall keeps the full river close to the surrounding
    # watershed. The previous grade climbed far above low terrain downstream.
    var channel_surface:=_river_grade_for_corridor(grade_x,grade_corridor_index,grade_progress,profile)
    var bed := channel_surface - 2.8
    # This is the exact rendered water datum used by WorldPreviewBuilder.
    # Keeping a second, lower "support water" height made the real terrain sit
    # below the visible river and exposed a floating sheet wherever a bank
    # detail strip was absent or viewed edge-on.
    var water_lift:float=float(profile.get("river_water_lift",1.35))
    var bank_drop:float=float(profile.get("river_bank_drop",1.15))
    var water_surface:=bed+water_lift
    # The 22.5 m terrain grid cannot represent a narrow tributary's deep center
    # and its shoreline inside the same triangle. A deep heightfield vertex
    # pulled the visible bank metres below the water. Keep the physical terrain
    # bed shallow and continuous; the river traversal mask still blocks the
    # deep core, so this integrity fix does not create an accidental ford.
    var terrain_channel_bed:=water_surface-.24
    # Bridge approaches are where the coarse heightfield is most likely to
    # interpolate from a deep center-bed vertex to a bank vertex and expose a
    # vertical water gap. Make the terrain immediately around every crossing
    # meet the water exactly.
    for support_site in _bridge_sites_cache:
        var support_center: Vector2 = support_site.get("position", Vector2.ZERO)
        var support_distance := Vector2(x, z).distance_to(support_center)
        if support_distance < 132.0:
            var support_weight := 1.0 - _smoothstep(86.0, 132.0, support_distance)
            # Bridge banks are raised to meet their approaches. Give the
            # center channel enough depth that coarse triangles interpolating
            # toward those banks still remain below the visible water, rather
            # than poking dry wedges through the river beside a crossing.
            terrain_channel_bed=lerpf(terrain_channel_bed,water_surface-2.75,support_weight)
    # South Ford sits on a sharp authored bend. Coarse terrain triangles could
    # dip beside the bridge and expose water outside the channel, so reinforce
    # only the outer bank vertices around explicitly guarded crossings.
    for guarded_site in _bridge_sites_cache:
        if not guarded_site.get("bank_guard", false):
            continue
        var guard_center: Vector2 = guarded_site.get("position", Vector2.ZERO)
        var guard_radius: float = float(guarded_site.get("radius", 62.0)) * 1.75
        var guard_offset := Vector2(x, z) - guard_center
        if guard_offset.length_squared() < guard_radius * guard_radius and dist >= half_channel * 0.82:
            var guard_distance := guard_offset.length()
            var guard_weight := 1.0 - _smoothstep(guard_radius * 0.55, guard_radius, guard_distance)
            surface=maxf(surface,water_surface+bank_drop*guard_weight)
    # Grade only the road approaches beside a bridge. The river channel stays
    # carved and continuous, while both banks meet the crossing at a sensible
    # shared elevation instead of producing a giant ramp on the higher side.
    var bridge_approach_surface:=-INF
    for bridge_site in _bridge_sites_cache:
        var bridge_center: Vector2 = bridge_site.get("position", Vector2.ZERO)
        var bridge_direction: Vector2 = bridge_site.get("direction", Vector2(0.0, 1.0))
        var approach_width: float = bridge_site.get("approach_width", 12.0)
        var bridge_offset := Vector2(x, z) - bridge_center
        var bridge_along := absf(bridge_offset.dot(bridge_direction))
        var bridge_lateral := absf(bridge_offset.cross(bridge_direction))
        if bridge_lateral <= approach_width and bridge_along >= half_channel * 0.82 and bridge_along <= half_channel + 82.0:
            var approach_weight := 1.0 - _smoothstep(half_channel + 20.0, half_channel + 82.0, bridge_along)
            var approach_height := _river_centerline_grade(bridge_center,profile) + 0.48
            surface = lerpf(surface, approach_height, approach_weight)
            bridge_approach_surface=maxf(bridge_approach_surface,surface)
    # The world grid is about 22 metres between vertices. Every vertex whose
    # triangle can reach the liquid has to remain just beneath the water or a
    # distant hillside vertex can slice through the river. This support is part
    # of the real, collidable terrain--not a second bank surface.
    var grid_step: float = float(profile.get("world_size", 7200.0)) / maxf(1.0, float(profile.get("grid_resolution", 256)))
    var edge_guard := minf(half_channel * 0.70, grid_step * 0.88)
    var flat_bed_edge := half_channel - edge_guard
    # The rendered ribbon is 84% of the authored channel.
    var visible_water_half:=half_channel*.84
    # A water-edge sample can sit in a terrain triangle whose far vertex is a
    # full grid diagonal away. Lower that complete support envelope so steep
    # hills cannot interpolate through the visible water.
    var mesh_support_half:=visible_water_half+grid_step*1.65
    var waterline_shelf_start := minf(flat_bed_edge + edge_guard * 0.45, visible_water_half * 0.88)
    # This support remains safely submerged across every coarse triangle. The
    # narrow wet-bank mesh starts below the same liquid datum and meets the real
    # terrain on its outer row, so the visible shoreline has no air slit.
    var submerged_edge_surface:=water_surface-.24
    if dist <= flat_bed_edge:
        return _apply_pond_carve(terrain_channel_bed,point,profile)
    if dist <= waterline_shelf_start:
        var submerged_t := _smoothstep(flat_bed_edge, waterline_shelf_start, dist)
        return _apply_pond_carve(lerpf(terrain_channel_bed,submerged_edge_surface,submerged_t),point,profile)
    if dist <= mesh_support_half:
        # The channel floor reaches the liquid just inside the visible edge;
        # immediately outside it the actual heightfield rises a few centimetres
        # above the water. The river therefore meets real ground even if every
        # decorative bank mesh is hidden, culled or omitted at a confluence.
        var support_surface:=submerged_edge_surface
        if bridge_approach_surface>-INF and dist>visible_water_half:
            # River support vertices used to overwrite the bridge grading
            # above. That left every approach as a dark, steep wedge hanging
            # between the road and deck. Rise from the exact waterline to the
            # authored bank height only after leaving visible water.
            var bridge_bank_weight:=_smoothstep(visible_water_half,half_channel+6.0,dist)
            support_surface=maxf(
                support_surface,
                lerpf(water_surface-.035,bridge_approach_surface,bridge_bank_weight)
            )
        var settlement_target:=_settlement_route_target(point,surface,profile)
        if settlement_target.fixed and dist>visible_water_half+6.0:
            # Hidden diagonal support must not excavate a settlement that is
            # safely beyond the visible water. Restore its authored pad over
            # the remaining bank run, while leaving the river and wading shelf
            # untouched.
            var restoration:=_smoothstep(visible_water_half+6.0,mesh_support_half,dist)
            support_surface=lerpf(support_surface,maxf(support_surface,float(settlement_target.height)),restoration)
        return _apply_pond_carve(support_surface,point,profile)
    # Never jump directly from the hidden water support to a mountain vertex.
    # That former five-metre transition could produce 180m height differences
    # across a single gameplay cell, which read as a hole and exposed the
    # backface of the terrain when approached from below.  Cap the surrounding
    # land to a continuous valley grade until it naturally meets the authored
    # landform. Low meadows recover within a few metres; high gorge walls take
    # the broad run they need instead of becoming a vertical tear.
    if dist<INF:
        var bank_run:=maxf(0.0,dist-mesh_support_half)
        var maximum_bank_surface:=water_surface+.12+bank_run*MAX_RIVER_BANK_GRADE
        # Low natural noise is just as destructive as an over-steep bank: it
        # leaves dry ground below the water plane. Hold a broad real-terrain
        # shoulder above the waterline, then blend it back into the authored
        # valley so there is no wall or artificial shelf.
        var low_bank_reach:=mesh_support_half+maxf(56.0,grid_step*3.2)
        if dist<=low_bank_reach:
            var bank_rise_end:=mesh_support_half+grid_step*1.55
            var bank_floor:=lerpf(
                water_surface+.08,
                water_surface+bank_drop,
                _smoothstep(mesh_support_half,bank_rise_end,dist)
            )
            var low_bank_weight:=1.0-_smoothstep(bank_rise_end,low_bank_reach,dist)
            surface=maxf(surface,lerpf(surface,bank_floor,low_bank_weight))
        surface=minf(surface,maximum_bank_surface)
    # Water bodies are the final terrain authority. An engineered path may
    # approach a pond, but it must never lift isolated land triangles through
    # the water surface or create a fake causeway across the shoreline.
    surface=_apply_engineered_route_surface(point,surface)
    surface=_apply_ocean_basin_surface(surface,point,profile)
    return _apply_pond_carve(surface,point,profile)


func _apply_pond_carve(input_surface:float,point:Vector2,profile:Dictionary)->float:
    var surface:=input_surface
    for pond in profile.get("pond_sites", []):
        var pond_center: Vector2 = pond.get("position", Vector2.ZERO)
        var authored_radius: float = pond.get("radius", 70.0)
        var pond_water: float = pond.get("water_height", 1.2)
        var pond_offset := point - pond_center
        var pond_dist := pond_offset.length()
        var pond_angle := atan2(pond_offset.y, pond_offset.x)
        var irregularity := 1.0 + sin(pond_angle * 3.0 + pond_center.x * 0.0017) * 0.11 + sin(pond_angle * 7.0 + pond_center.y * 0.0011) * 0.055
        var visible_radius := authored_radius * 1.18 * irregularity
        var carve_radius := visible_radius + 22.0
        if pond_dist < carve_radius:
            var pond_bed := pond_water - 1.6
            if pond_dist <= visible_radius * 0.82:
                surface = minf(surface, pond_bed)
            elif pond_dist <= visible_radius:
                var underwater_edge := _smoothstep(visible_radius * 0.82, visible_radius, pond_dist)
                surface = minf(surface, lerpf(pond_bed, pond_water - 0.10, underwater_edge))
            else:
                var pond_edge := _smoothstep(visible_radius, carve_radius, pond_dist)
                surface = minf(surface, lerpf(pond_water - 0.10, surface, pond_edge))
    return surface


func _land_surface_without_water(point:Vector2,profile:Dictionary)->float:
    var surface:=_natural_world_surface(point,profile)+_cave_cliff_raise(point)
    surface=_apply_ocean_basin_surface(surface,point,profile)
    surface=_apply_streaming_seam_surface(point,surface,profile)
    # Settlements are authored spaces, not buildings dropped onto random
    # noise. Their inner districts are level, with a broad transition back to
    # the surrounding terrain so roads and city walls meet usable ground.
    # Riverwatch is intentionally kept out of town_sites so gameplay systems do
    # not create a duplicate vendor town at the spawn. It still needs the same
    # stable ground contract as every other settlement. Small authored
    # destinations can opt into that contract with usable_ground.
    var usable_sites:Array=[]
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty():usable_sites.append(spawn_site)
    usable_sites.append_array(profile.get("town_sites",[]))
    for map_site in profile.get("map_sites",[]):
        if map_site.get("usable_ground",false):usable_sites.append(map_site)
    for site_value in usable_sites:
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var site_center: Vector2 = site.get("position", Vector2.ZERO)
        var site_radius: float = float(site.get("radius", 120.0))
        var inner_ratio:float=float(site.get("ground_inner_ratio",.78))
        # Settlement pads must blend over several terrain cells. The former
        # short ring could transition from a flat town to natural terrain in
        # less than one coarse triangle, creating a town-edge cliff even when
        # the heightfield itself was complete.
        var site_outer:=maxf(site_radius*1.55,site_radius*inner_ratio+72.0)
        var site_offset := point - site_center
        if site_offset.length_squared() < site_outer * site_outer:
            var site_distance := site_offset.length()
            var site_height: float = float(site.get("ground_height", 7.0))
            var site_weight := 1.0 - _smoothstep(site_radius * inner_ratio, site_outer, site_distance)
            surface = lerpf(surface, site_height, site_weight)
    return _cave_access_surface(point,surface,profile)


func _apply_ocean_basin_surface(input_surface:float,point:Vector2,profile:Dictionary)->float:
    var surface:=input_surface
    for basin_value in profile.get("ocean_basins",[]):
        if not basin_value is Dictionary:continue
        var basin:Dictionary=basin_value
        if str(basin.get("kind",""))!="coast":
            surface-=_ocean_basin_depth(point,basin)
            continue
        var coast_points:Array=basin.get("coast_points",[])
        if coast_points.size()<2:continue
        var coast_x:=_coastline_x_at_z(point.y,coast_points)
        var water_height:=float(basin.get("water_height",-.6))
        var shelf_width:=maxf(80.0,float(basin.get("shelf_width",520.0)))
        var land_blend:=maxf(40.0,float(basin.get("land_blend",210.0)))
        var depth:=maxf(2.0,float(basin.get("depth",34.0)))
        if point.x<=coast_x:
            var seaward:=coast_x-point.x
            # Keep several complete terrain cells at wading depth before the
            # shelf descends. Otherwise a coarse offshore vertex can pull the
            # interpolated shoreline metres below the water even though the
            # authored coast sample itself is correct.
            var grid_step:=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",256)))
            # This headland reaches the atlas seam on a strong diagonal, so a
            # coastline can cross several east/west cells over one north/south
            # row. A broad natural shelf keeps every triangle touching shore
            # shallow before the ocean begins its real descent offshore.
            var shallow_run:=minf(shelf_width*.62,maxf(220.0,grid_step*8.0))
            var sea_floor:=water_height-.24-depth*_smoothstep(shallow_run,shelf_width,seaward)
            # The ocean owns its seabed on the wet side of the coastline.
            # Using minf() only cut high vertices and preserved naturally low
            # terrain, leaving submerged trenches directly beneath the water.
            surface=sea_floor
        elif point.x<coast_x+land_blend:
            # The real terrain rises continuously from the waterline. This is
            # a physical shore profile, not a decorative plane, so no air slit
            # or invisible ledge can exist between land and sea.
            var land_t:=_smoothstep(0.0,land_blend,point.x-coast_x)
            surface=lerpf(water_height+.10,maxf(surface,water_height+.10),land_t)
    return surface


func _coastline_x_at_z(z:float,coast_points:Array)->float:
    if coast_points.is_empty():return -INF
    var first:=Vector2(coast_points[0])
    if z<=first.y:return first.x
    for index in range(coast_points.size()-1):
        var a:=Vector2(coast_points[index]);var b:=Vector2(coast_points[index+1])
        if z>=minf(a.y,b.y) and z<=maxf(a.y,b.y):
            var span:=b.y-a.y
            var t:=0.0 if absf(span)<.001 else clampf((z-a.y)/span,0.0,1.0)
            return lerpf(a.x,b.x,t)
    return Vector2(coast_points[-1]).x


func _point_inside_ocean_water(point:Vector2,profile:Dictionary,wade_margin:float=0.0)->bool:
    for basin_value in profile.get("ocean_basins",[]):
        if not basin_value is Dictionary:continue
        var basin:Dictionary=basin_value
        if str(basin.get("kind",""))!="coast":continue
        var coast_points:Array=basin.get("coast_points",[])
        if coast_points.size()<2:continue
        if str(basin.get("edge","west"))=="west" and point.x<_coastline_x_at_z(point.y,coast_points)-wade_margin:return true
    return false


func _apply_streaming_seam_surface(point:Vector2,surface:float,profile:Dictionary)->float:
    # Both sides of a streamed boundary evaluate the same world-space curve.
    # The curve is deliberately a broad mountain-pass floor rather than a flat
    # strip, and it fades into each region far before the player sees the join.
    var world_size:float=float(profile.get("world_size",7200.0))
    var origin:Vector2=profile.get("region_origin",Vector2.ZERO)
    for seam_value in profile.get("seam_edges",[]):
        if not seam_value is Dictionary:continue
        var seam:Dictionary=seam_value
        var edge:=str(seam.get("edge",""))
        var inward_distance:=INF
        var along_coordinate:=point.x
        if edge=="north":inward_distance=world_size*.5-point.y
        elif edge=="south":inward_distance=point.y+world_size*.5
        elif edge=="east":
            inward_distance=world_size*.5-point.x
            along_coordinate=point.y
        elif edge=="west":
            inward_distance=point.x+world_size*.5
            along_coordinate=point.y
        else:continue
        var blend_width:=maxf(64.0,float(seam.get("blend_width",620.0)))
        if inward_distance>=blend_width:continue
        var seam_height:=_streaming_seam_curve(along_coordinate,seam,profile)
        var weight:=1.0-_smoothstep(0.0,blend_width,inward_distance)
        surface=lerpf(surface,seam_height,weight)
    return surface


func _streaming_seam_curve(along_coordinate:float,seam:Dictionary,profile:Dictionary)->float:
    var origin:Vector2=profile.get("region_origin",Vector2.ZERO)
    var edge:=str(seam.get("edge",""))
    var global_along:=along_coordinate+(origin.y if edge in ["east","west"] else origin.x)
    var seed:=float(abs(str(seam.get("key","world_seam")).hash())%10000)*.001
    var seam_height:=float(seam.get("base_height",13.5))
    seam_height+=sin(global_along*.00115+seed)*4.2
    seam_height+=sin(global_along*.0031+seed*.37)*1.6
    # At a four-region grid junction, pairwise seam curves alone are not
    # sufficient: whichever edge is restored last would otherwise own the
    # corner vertex and leave the diagonal neighbour at a different height.
    # Adjacent profiles author the same junction datum, and each pairwise seam
    # eases into it before the corner so the complete terrain mesh remains
    # watertight while retaining its distinctive pass grade away from the hub.
    var junctions:Array=[]
    if seam.has("junction_along"):
        junctions.append({
            "along":seam.get("junction_along",global_along),
            "height":seam.get("junction_height",seam_height),
            "blend":seam.get("junction_blend",620.0),
        })
    junctions.append_array(seam.get("junctions",[]))
    for junction_value in junctions:
        if not junction_value is Dictionary:continue
        var junction:Dictionary=junction_value
        var junction_along:=float(junction.get("along",global_along))
        var junction_blend:=maxf(80.0,float(junction.get("blend",620.0)))
        var junction_weight:=1.0-_smoothstep(0.0,junction_blend,absf(global_along-junction_along))
        seam_height=lerpf(seam_height,float(junction.get("height",seam_height)),junction_weight)
    return seam_height


func _streaming_river_endpoint_influence(point:Vector2,edge:String,profile:Dictionary)->bool:
    var world_size:float=float(profile.get("world_size",7200.0))
    var boundary:=world_size*.5 if edge in ["north","east"] else -world_size*.5
    for river_value in profile.get("river_corridors",[]):
        if not river_value is Dictionary:continue
        var river:Dictionary=river_value
        var points:Array=river.get("points",[])
        if points.is_empty():continue
        for endpoint_value in [points[0],points[-1]]:
            var endpoint:Vector2=endpoint_value
            var width:=float(river.get("width",44.0))
            if edge in ["north","south"]:
                if absf(endpoint.y-boundary)>.5:continue
                if absf(point.x-endpoint.x)<=width*.95:return true
            else:
                if absf(endpoint.x-boundary)>.5:continue
                if absf(point.y-endpoint.y)<=width*.95:return true
    return false


func _prepare_engineered_route_cache(profile:Dictionary)->void:
    _engineered_route_buckets.clear()
    if OS.get_environment("BROKEN_KNIGHT_REBUILD_ENGINEERED_ROUTES")!="1" and _load_engineered_route_bake(profile):return
    var grid_step:float=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",256)))
    var corridors:Array=[]
    corridors.append_array(profile.get("road_corridors",[]))
    for trail in profile.get("trail_corridors",[]):
        if trail.get("engineered_grade",false):corridors.append(trail)
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        if points.size()<2:continue
        var route_class:=str(corridor.get("route_class","local"))
        var default_grade_limit:=.14 if route_class=="major" else (.18 if route_class=="secondary" else .24)
        var grade_limit:=clampf(float(corridor.get("grade_limit",default_grade_limit)),.035,.30)
        var sample_spacing:=maxf(16.0,grid_step*.78)
        var sampled_points:Array=[]
        for index in range(points.size()-1):
            var a:Vector2=points[index];var b:Vector2=points[index+1]
            var steps:=maxi(1,int(ceil(a.distance_to(b)/sample_spacing)))
            for step in range(steps):sampled_points.append(a.lerp(b,float(step)/float(steps)))
        sampled_points.append(points[-1])
        var cumulative:Array[float]=[0.0]
        var target_heights:Array[float]=[]
        var fixed_heights:Dictionary={}
        for index in range(sampled_points.size()):
            var point:Vector2=sampled_points[index]
            if index>0:cumulative.append(cumulative[-1]+point.distance_to(sampled_points[index-1]))
            var target:=_land_surface_without_water(point,profile)
            var settlement_target:=_settlement_route_target(point,target,profile)
            target=float(settlement_target.height)
            if index==0 or index==sampled_points.size()-1:
                target=_route_endpoint_height(point,target,profile)
            var bridge_target:={"height":target,"fixed":false}
            if not settlement_target.fixed:bridge_target=_bridge_route_target(point,target,profile)
            target=float(bridge_target.height)
            if index==0 or index==sampled_points.size()-1 or settlement_target.fixed or bridge_target.fixed:
                fixed_heights[index]=target
            target_heights.append(target)
        _limit_route_grades(target_heights,cumulative,grade_limit,fixed_heights)
        # Include one heightfield sample beyond either shoulder so the coarse
        # terrain triangles cannot poke through the road ribbon.
        var inner:=grid_step*1.38+float(corridor.get("width",7.0))*.5
        # The authored terrain_width describes the full engineered shoulder,
        # not just the broad natural valley relief. Honour half of it here so
        # a raised bridge approach feathers into neighbouring land instead of
        # becoming a narrow embankment with a near-vertical side wall.
        var outer:=maxf(inner+18.0,float(corridor.get("terrain_width",0.0))*.5)
        for index in range(sampled_points.size()-1):
            _bucket_engineered_route_segment({
                "a":sampled_points[index],"b":sampled_points[index+1],
                "height_a":target_heights[index],"height_b":target_heights[index+1],
                "inner":inner,"outer":outer,
            })


func engineered_route_bake_path(profile:Dictionary)->String:
    var zone_id:=str(profile.get("zone_id","starting_realm")).validate_filename()
    return "%s/%s_engineered_routes_v%d.cache"%[ENGINEERED_ROUTE_BAKE_DIR,zone_id,ENGINEERED_ROUTE_CACHE_VERSION]


func engineered_route_bake_signature(profile:Dictionary)->String:
    # The terrain-cache key already covers every landform, settlement, river,
    # road, trail, bridge and seam input used by the grade solver.
    return str(hash([ENGINEERED_ROUTE_CACHE_VERSION,_terrain_cache_path(profile)]))


func save_engineered_route_bake(profile:Dictionary)->Error:
    var output_path:=engineered_route_bake_path(profile)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ENGINEERED_ROUTE_BAKE_DIR))
    var file:=FileAccess.open(output_path,FileAccess.WRITE)
    if file==null:return FileAccess.get_open_error()
    file.store_var({
        "version":ENGINEERED_ROUTE_CACHE_VERSION,
        "signature":engineered_route_bake_signature(profile),
        "buckets":_engineered_route_buckets,
    },false)
    return OK


func _load_engineered_route_bake(profile:Dictionary)->bool:
    var input_path:=engineered_route_bake_path(profile)
    if not FileAccess.file_exists(input_path):return false
    var file:=FileAccess.open(input_path,FileAccess.READ)
    if file==null:return false
    var value:Variant=file.get_var(false)
    if not value is Dictionary:return false
    var cache:Dictionary=value
    if int(cache.get("version",-1))!=ENGINEERED_ROUTE_CACHE_VERSION:return false
    if str(cache.get("signature",""))!=engineered_route_bake_signature(profile):return false
    var buckets:Variant=cache.get("buckets",{})
    if not buckets is Dictionary:return false
    _engineered_route_buckets=buckets
    return true


func _settlement_route_target(point:Vector2,fallback:float,profile:Dictionary)->Dictionary:
    var sites:Array=[]
    var spawn:Dictionary=profile.get("spawn_site",{})
    if not spawn.is_empty():sites.append(spawn)
    sites.append_array(profile.get("town_sites",[]))
    for site in sites:
        var center:Vector2=site.get("position",Vector2.ZERO)
        var inner_radius:float=float(site.get("radius",120.0))*1.08
        if point.distance_to(center)<=inner_radius:
            return {"height":float(site.get("ground_height",fallback)),"fixed":true}
    return {"height":fallback,"fixed":false}


func _route_endpoint_height(point:Vector2,fallback:float,profile:Dictionary)->float:
    for pond in profile.get("pond_sites",[]):
        var center:Vector2=pond.get("position",Vector2.ZERO)
        if point.distance_to(center)<=float(pond.get("radius",70.0))*1.55:
            return float(pond.get("water_height",1.2))+.28
    return fallback


func _bridge_route_target(point:Vector2,fallback:float,profile:Dictionary)->Dictionary:
    for site in _bridge_sites_cache:
        var center:Vector2=site.get("position",Vector2.ZERO)
        var road_width:=float(site.get("road_width",14.0))
        var river_width:=float(site.get("river_width",52.0))
        var deck_half:=maxf(river_width+10.0,road_width*2.15)*.5
        # Hold only the physical deck and its short engineered landing at deck
        # grade.  The old radius*1.55 rule flattened as much as 96 m around a
        # 30 m bridge, creating a blind crest before both approaches.  The
        # bounded road-grade solver now owns the longer, visible transition.
        var fixed_run:=deck_half+maxf(12.0,road_width*.82)
        if point.distance_to(center)<=fixed_run:
            return {"height":_river_centerline_grade(center,profile)+.62,"fixed":true}
    return {"height":fallback,"fixed":false}


func _limit_route_grades(heights:Array[float],cumulative:Array[float],grade_limit:float,fixed_heights:Dictionary)->void:
    if heights.size()<2:return
    # Project sampled terrain into a bounded-slope route profile. Repeated
    # local corrections retain broad landform changes while removing noise
    # spikes, settlement-pad cliffs, and direct climbs up mountain faces.
    for iteration in range(40):
        for fixed_index in fixed_heights:heights[int(fixed_index)]=float(fixed_heights[fixed_index])
        for index in range(heights.size()-1):
            var allowed:float=(float(cumulative[index+1])-float(cumulative[index]))*grade_limit
            var delta:float=float(heights[index+1])-float(heights[index])
            if absf(delta)<=allowed:continue
            var correction:float=(absf(delta)-allowed)*signf(delta)
            if fixed_heights.has(index):heights[index+1]=float(heights[index+1])-correction
            elif fixed_heights.has(index+1):heights[index]=float(heights[index])+correction
            else:
                heights[index]=float(heights[index])+correction*.5
                heights[index+1]=float(heights[index+1])-correction*.5
        for index in range(heights.size()-2,-1,-1):
            var allowed:float=(float(cumulative[index+1])-float(cumulative[index]))*grade_limit
            var delta:float=float(heights[index+1])-float(heights[index])
            if absf(delta)<=allowed:continue
            var correction:float=(absf(delta)-allowed)*signf(delta)
            if fixed_heights.has(index):heights[index+1]=float(heights[index+1])-correction
            elif fixed_heights.has(index+1):heights[index]=float(heights[index])+correction
            else:
                heights[index]=float(heights[index])+correction*.5
                heights[index+1]=float(heights[index+1])-correction*.5
    for fixed_index in fixed_heights:heights[int(fixed_index)]=float(fixed_heights[fixed_index])


func _bucket_engineered_route_segment(segment:Dictionary)->void:
    var a:Vector2=segment.a;var b:Vector2=segment.b;var outer:float=segment.outer
    var minimum:=Vector2i(floori((minf(a.x,b.x)-outer)/RIVER_BUCKET_SIZE),floori((minf(a.y,b.y)-outer)/RIVER_BUCKET_SIZE))
    var maximum:=Vector2i(floori((maxf(a.x,b.x)+outer)/RIVER_BUCKET_SIZE),floori((maxf(a.y,b.y)+outer)/RIVER_BUCKET_SIZE))
    for bucket_x in range(minimum.x,maximum.x+1):
        for bucket_y in range(minimum.y,maximum.y+1):
            var key:=Vector2i(bucket_x,bucket_y)
            if not _engineered_route_buckets.has(key):_engineered_route_buckets[key]=[]
            _engineered_route_buckets[key].append(segment)


func _prepare_river_segment_cache(profile:Dictionary)->void:
    _river_segment_buckets.clear()
    _river_walkable_buckets.clear()
    _river_junctions.clear()
    _waterfall_grade_breaks.clear()
    var grid_step:=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",256)))
    var profile_rivers:Array=profile.get("river_corridors",[])
    for corridor_index in range(profile_rivers.size()):
        var corridor:Dictionary=profile_rivers[corridor_index]
        var points:Array=corridor.get("points",[])
        var maximum_width:=maxf(
            float(corridor.get("source_width",corridor.get("width",84.0))),
            float(corridor.get("mouth_width",corridor.get("width",84.0)))
        )
        # River terrain changes end within roughly 72 m of the support shelf.
        # A generous 220 m segment envelope also covers guarded bridge banks.
        # The grade-limited river valley may need several hundred metres to
        # meet a mountain honestly. Keep those segments in the spatial cache
        # far enough out that the cap always reaches natural ground before the
        # query envelope ends.
        var influence:=maxf(RIVER_TERRAIN_INFLUENCE,maximum_width*.5+grid_step*1.45+84.0)
        for index in range(points.size()-1):
            var a:Vector2=points[index]
            var b:Vector2=points[index+1]
            var start_progress:float=float(index)/maxf(1.0,float(points.size()-1))
            var end_progress:float=float(index+1)/maxf(1.0,float(points.size()-1))
            var width_a:=_corridor_width_at(corridor,start_progress,84.0)
            var width_b:=_corridor_width_at(corridor,end_progress,84.0)
            var min_bucket:=Vector2i(
                floori((minf(a.x,b.x)-influence)/RIVER_BUCKET_SIZE),
                floori((minf(a.y,b.y)-influence)/RIVER_BUCKET_SIZE)
            )
            var max_bucket:=Vector2i(
                floori((maxf(a.x,b.x)+influence)/RIVER_BUCKET_SIZE),
                floori((maxf(a.y,b.y)+influence)/RIVER_BUCKET_SIZE)
            )
            var segment_data:={
                "a":a,"b":b,"width_a":width_a,"width_b":width_b,
                "corridor_index":corridor_index,
                "start_progress":start_progress,"end_progress":end_progress,
            }
            for bucket_x in range(min_bucket.x,max_bucket.x+1):
                for bucket_y in range(min_bucket.y,max_bucket.y+1):
                    var key:=Vector2i(bucket_x,bucket_y)
                    if not _river_segment_buckets.has(key):_river_segment_buckets[key]=[]
                    _river_segment_buckets[key].append(segment_data)
            var walkable_influence:=maxf(width_a,width_b)*.5+18.0
            var walkable_min:=Vector2i(
                floori((minf(a.x,b.x)-walkable_influence)/RIVER_BUCKET_SIZE),
                floori((minf(a.y,b.y)-walkable_influence)/RIVER_BUCKET_SIZE)
            )
            var walkable_max:=Vector2i(
                floori((maxf(a.x,b.x)+walkable_influence)/RIVER_BUCKET_SIZE),
                floori((maxf(a.y,b.y)+walkable_influence)/RIVER_BUCKET_SIZE)
            )
            for bucket_x in range(walkable_min.x,walkable_max.x+1):
                for bucket_y in range(walkable_min.y,walkable_max.y+1):
                    var key:=Vector2i(bucket_x,bucket_y)
                    if not _river_walkable_buckets.has(key):_river_walkable_buckets[key]=[]
                    _river_walkable_buckets[key].append(segment_data)
    var rivers:Array=profile_rivers
    for river_index in range(rivers.size()):
        var points:Array=rivers[river_index].get("points",[])
        if points.is_empty():continue
        for endpoint in [Vector2(points[0]),Vector2(points[-1])]:
            for other_index in range(rivers.size()):
                if other_index==river_index:continue
                var other:Dictionary=rivers[other_index]
                if _distance_to_polyline(endpoint,other.get("points",[]))<float(other.get("width",48.0))*.72:
                    _river_junctions.append(endpoint)
                    break
    # Bind each authored fall to its nearest river progress once. Height
    # queries can then preserve a level cross-section and apply the full drop
    # upstream without rescanning every spline segment.
    for site_value in profile.get("waterfall_sites",[]):
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var site_point:Vector2=site.get("position",Vector2.ZERO)
        var best_distance:=INF
        var best_corridor:=-1
        var best_progress:=0.0
        for corridor_index in range(rivers.size()):
            var points:Array=rivers[corridor_index].get("points",[])
            for segment_index in range(points.size()-1):
                var a:Vector2=points[segment_index];var b:Vector2=points[segment_index+1]
                var segment:=b-a
                if segment.length_squared()<=.0001:continue
                var t:=clampf((site_point-a).dot(segment)/segment.length_squared(),0.0,1.0)
                var distance:=site_point.distance_to(a+segment*t)
                if distance>=best_distance:continue
                best_distance=distance
                best_corridor=corridor_index
                best_progress=(float(segment_index)+t)/maxf(1.0,float(points.size()-1))
        if best_corridor>=0:
            _waterfall_grade_breaks.append({
                "corridor_index":best_corridor,
                "progress":best_progress,
                "drop":maxf(0.0,float(site.get("drop",0.0))),
            })


func _nearest_cached_river_segment(point:Vector2,profile:Dictionary)->Dictionary:
    return _nearest_river_segment_in_buckets(point,_river_segment_buckets,profile)


func _nearest_cached_walkable_river_segment(point:Vector2,profile:Dictionary)->Dictionary:
    return _nearest_river_segment_in_buckets(point,_river_walkable_buckets,profile)


func _nearest_river_segment_in_buckets(point:Vector2,buckets:Dictionary,profile:Dictionary)->Dictionary:
    var nearby_segments:Array=buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),[]
    )
    if nearby_segments.is_empty():
        # Retain the uncached path for direct diagnostic calls made before a
        # world has been generated. In a live world, an empty bucket means the
        # point is genuinely outside every relevant river envelope.
        return _nearest_road_segment(point,profile.get("river_corridors",[])) if buckets.is_empty() else {}
    var best:Dictionary={}
    var best_distance:=INF
    for segment_data in nearby_segments:
        var a:Vector2=segment_data.a
        var b:Vector2=segment_data.b
        var segment:=b-a
        var length_squared:=segment.length_squared()
        if length_squared<=.0001:continue
        var t:=clampf((point-a).dot(segment)/length_squared,0.0,1.0)
        var closest:=a+segment*t
        var distance:=point.distance_to(closest)
        if distance>=best_distance:continue
        best_distance=distance
        best={
            "distance":distance,
            "direction":segment.normalized(),
            "width":lerpf(float(segment_data.width_a),float(segment_data.width_b),t),
            "closest_point":closest,
        }
    return best


func _prepare_surface_route_cache(profile:Dictionary,road_junctions:Array[Vector2])->void:
    _surface_route_buckets.clear()
    for road_value in profile.get("road_corridors",[]):
        var road:Dictionary=road_value
        _bucket_surface_route(road.get("points",[]),float(road.get("width",26.0))*.48*.5)
    for trail_value in profile.get("trail_corridors",[]):
        var trail:Dictionary=trail_value
        _bucket_surface_route(trail.get("points",[]),maxf(2.4,float(trail.get("width",5.0))*.48)*.5)
    for junction in road_junctions:
        _bucket_surface_route_entry({"kind":"junction","point":junction,"half_width":7.5},junction-Vector2.ONE*7.5,junction+Vector2.ONE*7.5)


func _bucket_surface_route(points:Array,half_width:float)->void:
    if half_width<=.01:return
    for index in range(points.size()-1):
        var a:Vector2=points[index]
        var b:Vector2=points[index+1]
        _bucket_surface_route_entry(
            {"kind":"segment","a":a,"b":b,"half_width":half_width},
            Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2.ONE*half_width,
            Vector2(maxf(a.x,b.x),maxf(a.y,b.y))+Vector2.ONE*half_width
        )


func _bucket_surface_route_entry(entry:Dictionary,minimum:Vector2,maximum:Vector2)->void:
    var min_bucket:=Vector2i(floori(minimum.x/RIVER_BUCKET_SIZE),floori(minimum.y/RIVER_BUCKET_SIZE))
    var max_bucket:=Vector2i(floori(maximum.x/RIVER_BUCKET_SIZE),floori(maximum.y/RIVER_BUCKET_SIZE))
    for bucket_x in range(min_bucket.x,max_bucket.x+1):
        for bucket_y in range(min_bucket.y,max_bucket.y+1):
            var key:=Vector2i(bucket_x,bucket_y)
            if not _surface_route_buckets.has(key):_surface_route_buckets[key]=[]
            _surface_route_buckets[key].append(entry)


func _surface_route_offset(point:Vector2)->float:
    var entries:Array=_surface_route_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),[]
    )
    var best_offset:=0.0
    for entry_value in entries:
        var entry:Dictionary=entry_value
        if entry.kind=="junction":
            if point.distance_squared_to(entry.point)<=float(entry.half_width)*float(entry.half_width):
                best_offset=maxf(best_offset,.18)
            continue
        var a:Vector2=entry.a
        var b:Vector2=entry.b
        var segment:=b-a
        var t:=clampf((point-a).dot(segment)/maxf(.0001,segment.length_squared()),0.0,1.0)
        var distance:=point.distance_to(a+segment*t)
        var half_width:float=entry.half_width
        if distance<=half_width:
            best_offset=maxf(best_offset,lerpf(.18,.12,clampf(distance/half_width,0.0,1.0)))
    return best_offset


func _apply_engineered_route_surface(point:Vector2,surface:float)->float:
    var nearby_segments:Array=_engineered_route_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),[]
    )
    var best_distance:=INF;var best_target:=surface;var best_inner:=0.0;var best_outer:=0.0
    for route_segment in nearby_segments:
        var a:Vector2=route_segment.a;var b:Vector2=route_segment.b;var segment:=b-a
        var t:=clampf((point-a).dot(segment)/maxf(.001,segment.length_squared()),0.0,1.0)
        var distance:=point.distance_to(a+segment*t)
        if distance>=best_distance or distance>=float(route_segment.outer):continue
        best_distance=distance
        best_target=lerpf(float(route_segment.height_a),float(route_segment.height_b),t)
        best_inner=float(route_segment.inner);best_outer=float(route_segment.outer)
    if best_distance<INF:
        var weight:=1.0-_smoothstep(best_inner,best_outer,best_distance)
        surface=lerpf(surface,best_target,weight)
    return surface


func _natural_world_surface(point:Vector2,profile:Dictionary)->float:
    var surface:=3.0
    # Noise supplies surface character, not world structure. The former five
    # overlapping fields produced height everywhere but no readable landform;
    # named valleys, ridges and uplands now carry most of the regional relief.
    surface+=_base_noise.get_noise_2d(point.x*.34,point.y*.34)*5.2
    surface+=_ridge_noise.get_noise_2d(point.x*.22-70.0,point.y*.22+45.0)*2.2
    surface+=_detail_noise.get_noise_2d(point.x*.52+90.0,point.y*.52-40.0)*.72
    surface+=sin(point.x*.0042)*1.35
    surface+=sin(point.y*.0048+.7)*1.05
    for region in profile.get("landform_regions",[]):surface+=_authored_landform_height(point,region)
    for chain in profile.get("mountain_chains",[]):surface+=_mountain_chain_height(point,chain)
    surface+=_strategic_elevation_height(point,profile)
    surface=_apply_travel_landform_surface(point,surface,profile)
    return surface


func _strategic_elevation_height(point:Vector2,profile:Dictionary)->float:
    # Only explicitly authored landmarks shape high ground. This makes every
    # local crown answer a world question: overlook, boundary marker, ruin or
    # defensive position, rather than being another procedural bump.
    var lift:=0.0
    var sites:Array=[]
    sites.append_array(profile.get("landmark_sites",[]))
    sites.append_array(profile.get("map_sites",[]))
    for site_value in sites:
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var height_lift:float=float(site.get("elevation_lift",0.0))
        if height_lift<=0.0:continue
        var center:Vector2=site.get("position",Vector2.ZERO)
        var inner:float=maxf(4.0,float(site.get("elevation_inner",36.0)))
        var outer:float=maxf(inner+12.0,float(site.get("elevation_radius",150.0)))
        var distance:=point.distance_to(center)
        if distance>=outer:continue
        var weight:=1.0-_smoothstep(inner,outer,distance)
        lift=maxf(lift,height_lift*weight)
    return lift


func _apply_travel_landform_surface(point:Vector2,surface:float,profile:Dictionary)->float:
    # Important routes occupy broad shallow passes and valley floors. The road
    # mesh still receives precise grade engineering later; this wider shaping
    # explains why the route exists without making a visible man-made trench.
    for corridor_value in profile.get("road_corridors",[]):
        var corridor:Dictionary=corridor_value
        var relief:float=float(corridor.get("terrain_relief",0.0))
        var width:float=float(corridor.get("terrain_width",0.0))
        if relief<=0.0 or width<=0.0:continue
        var distance:=_distance_to_polyline(point,corridor.get("points",[]))
        if distance>=width:continue
        var weight:=1.0-_smoothstep(width*.22,width,distance)
        surface-=relief*weight
    return surface


func _cave_access_surface(point:Vector2,surface:float,profile:Dictionary)->float:
    for cave_data in [
        [Vector2(-2700.0,1700.0),Vector2(0.0,1.0)],
        [Vector2(2620.0,-1800.0),Vector2(0.0,-1.0)],
    ]:
        var entrance:Vector2=cave_data[0]
        var inward:Vector2=cave_data[1]
        var offset:=point-entrance
        var along:=offset.dot(inward)
        var lateral:=absf(offset.cross(inward))
        if along < -430.0 or along > 54.0 or lateral > 82.0:continue
        # Start grading far before the mountain. The former seventy-metre blend
        # compressed the full climb into a short ramp and visually tore the road.
        var along_weight:=_smoothstep(-430.0,-90.0,along)*(1.0-_smoothstep(40.0,54.0,along))
        var lateral_weight:=1.0-_smoothstep(46.0,82.0,lateral)
        var target:=_natural_world_surface(entrance,profile)
        surface=lerpf(surface,target,along_weight*lateral_weight)
    return surface


func _river_grade(x: float) -> float:
    var grade := 2.4 + x * 0.00042 + sin(x * 0.003) * 0.08
    grade += _smoothstep(-1195.0, -1125.0, x) * 3.2
    grade += _smoothstep(2005.0, 2075.0, x) * 2.6
    return grade


func _river_grade_for_corridor(grade_x:float,corridor_index:int,progress:float,profile:Dictionary)->float:
    var grade:=_river_grade(grade_x)
    var rivers:Array=profile.get("river_corridors",[])
    if corridor_index<0 or corridor_index>=rivers.size():return grade
    var corridor:Dictionary=rivers[corridor_index]
    if corridor.has("source_height") and corridor.has("mouth_height"):
        grade=lerpf(
            float(corridor.get("source_height",grade)),
            float(corridor.get("mouth_height",grade)),
            clampf(progress,0.0,1.0)
        )
    grade+=float(corridor.get("base_lift",0.0))
    for grade_break in _waterfall_grade_breaks:
        if int(grade_break.get("corridor_index",-1))==corridor_index and progress<=float(grade_break.get("progress",0.0))+.0001:
            grade+=float(grade_break.get("drop",0.0))
    return grade


func _river_centerline_grade(point:Vector2,profile:Dictionary)->float:
    # Water elevation is constant across each river cross-section. Sampling
    # world X directly tilted north-south rivers sideways and made one bank sit
    # below the liquid near waterfall grade breaks.
    var best_distance:=INF
    var grade_x:=point.x
    var best_corridor_index:=-1
    var best_progress:=0.0
    var nearby_segments:Array=_river_segment_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),[]
    )
    for segment_data in nearby_segments:
        var segment:Vector2=segment_data.b-segment_data.a
        var segment_t:=0.0
        if segment.length_squared()>.0001:
            segment_t=clampf((point-segment_data.a).dot(segment)/segment.length_squared(),0.0,1.0)
        var closest:Vector2=segment_data.a+segment*segment_t
        var distance:=point.distance_to(closest)
        if distance<best_distance:
            best_distance=distance
            grade_x=closest.x
            best_corridor_index=int(segment_data.get("corridor_index",-1))
            best_progress=lerpf(float(segment_data.get("start_progress",0.0)),float(segment_data.get("end_progress",1.0)),segment_t)
    if nearby_segments.is_empty():
        var nearest:=_nearest_road_segment(point,profile.get("river_corridors",[]))
        if not nearest.is_empty():grade_x=Vector2(nearest.get("closest_point",point)).x
    return _river_grade_for_corridor(grade_x,best_corridor_index,best_progress,profile)


func _cave_cliff_raise(point: Vector2) -> float:
    var raise_amount := 0.0
    for cave_data in [
        [Vector2(-2700.0, 1700.0), Vector2(0.0, 1.0)],
        [Vector2(2620.0, -1800.0), Vector2(0.0, -1.0)],
    ]:
        var entrance: Vector2 = cave_data[0]
        var inward: Vector2 = cave_data[1]
        var offset := point - entrance
        var along := offset.dot(inward)
        var lateral := absf(offset.cross(inward))
        if along < 0.0 or along > 145.0 or lateral > 90.0:
            continue
        var side_mask := 1.0 - _smoothstep(56.0, 90.0, lateral)
        # Leave a broad, walkable notch through the raised cliff mass. The
        # visual tunnel roof closes this notch overhead, so the entrance reads
        # as terrain carved away rather than a dark decal stuck to a slope.
        if along <= 42.0:
            side_mask *= _smoothstep(12.0, 24.0, lateral)
        var cliff_face := _smoothstep(0.0, 24.0, along) * 30.0
        var back_fade := 1.0 - _smoothstep(110.0, 145.0, along)
        raise_amount = maxf(raise_amount, cliff_face * side_mask * back_fade)
    return raise_amount


func _castle_structure_height(point: Vector2, current_y: float, profile: Dictionary) -> float:
    var capital: Dictionary = {}
    for town in profile.get("town_sites", []):
        if town.get("capital", false):
            capital = town
            break
    if capital.is_empty():
        return -INF
    var capital_center: Vector2 = capital.get("position", Vector2.ZERO)
    var keep := capital_center + Vector2(0.0, -100.0)
    var base: float = float(capital.get("ground_height", 12.0))
    var rel := point - keep
    var best := -INF
    var best_delta := INF

    # Select only a stair surface close to the hero's current storey. Flights
    # one and three overlap in plan view, so x/z alone cannot safely determine
    # which stacked ramp should carry the player.
    for floor_index in range(3):
        var reverse := floor_index % 2 == 1
        var stair_x := 10.0 if not reverse else 18.0
        if absf(rel.x - stair_x) > 2.35 or rel.y < -8.8 or rel.y > 16.8:
            continue
        var progress := (rel.y + 8.2) / 24.4 if reverse else (16.2 - rel.y) / 24.4
        progress = clampf(progress, 0.0, 1.0)
        var from_y := base + float(floor_index) * 8.0 + (0.21 if floor_index > 0 else 0.0)
        var to_y := base + float(floor_index + 1) * 8.0 + 0.21
        var candidate := lerpf(from_y, to_y, progress)
        var delta := absf(candidate - current_y)
        if candidate <= current_y + 2.6 and candidate >= current_y - 6.2 and delta < best_delta:
            best = candidate
            best_delta = delta

    # Once a flight reaches a storey, hold the hero on the real floor panels.
    if absf(rel.x) <= 28.1 and absf(rel.y) <= 21.1:
        for floor_index in range(1, 4):
            if _castle_floor_opening(rel,floor_index):
                continue
            var floor_y := base + float(floor_index) * 8.0 + 0.21
            var delta := absf(floor_y - current_y)
            if floor_y <= current_y + 2.6 and floor_y >= current_y - 6.2 and delta < best_delta:
                best = floor_y
                best_delta = delta
        # The roof is a real traversal surface except for its ladder hatch.
        if not (rel.x>=15.2 and rel.x<=20.8 and rel.y>=1.5 and rel.y<=12.0):
            # Surface sampling follows the top of the 1.2 m roof slab, not its
            # center. This keeps feet, the hatch mount and lookout floors on
            # the same physical plane.
            var roof_y:=base+33.08
            var roof_delta:=absf(roof_y-current_y)
            if roof_y<=current_y+2.6 and roof_y>=current_y-6.2 and roof_delta<best_delta:
                best=roof_y
                best_delta=roof_delta
    return best


func _castle_floor_opening(rel:Vector2,floor_index:int)->bool:
    if floor_index==1:
        return rel.x>=7.5 and rel.x<=12.5 and rel.y>=-8.8 and rel.y<=3.0
    if floor_index==2:
        return rel.x>=15.5 and rel.x<=20.5 and rel.y>=4.0 and rel.y<=16.8
    return rel.x>=7.5 and rel.x<=12.5 and rel.y>=-8.8 and rel.y<=3.0


func _prepare_bridge_cache(profile: Dictionary) -> void:
    _bridge_sites_cache.clear()
    var roads: Array = profile.get("road_corridors", [])
    var rivers: Array = profile.get("river_corridors", [])
    for source_site in profile.get("ford_sites", []):
        var site: Dictionary = source_site.duplicate()
        var center: Vector2 = site.get("position", Vector2.ZERO)
        var river_info := _nearest_road_segment(center, rivers)
        if river_info.is_empty() or float(river_info.get("distance", INF)) > 30.0:
            continue
        var direction := Vector2.ZERO
        var road_width := 14.0
        var approach_width := 12.0
        if site.get("standalone", false):
            var river_direction: Vector2 = river_info.get("direction", Vector2(1.0, 0.0))
            direction = Vector2(-river_direction.y, river_direction.x).normalized()
            road_width = float(site.get("bridge_width", 10.0))
            approach_width = maxf(10.0, road_width * 1.2)
        else:
            var road_info := _nearest_road_segment(center, roads)
            if road_info.is_empty() or float(road_info.get("distance", INF)) > 30.0:
                continue
            direction = road_info.get("direction", Vector2(0.0, 1.0))
            road_width = float(road_info.get("width", 14.0))
            approach_width = maxf(12.0, road_width * 1.15)
        site["direction"] = direction
        site["road_width"] = road_width
        site["approach_width"] = approach_width
        site["river_width"] = float(river_info.get("width", 52.0))
        _bridge_sites_cache.append(site)


func _bridge_deck_info(point: Vector2, profile: Dictionary) -> Dictionary:
    var sites: Array = _bridge_sites_cache if not _bridge_sites_cache.is_empty() else profile.get("ford_sites", [])
    for site in sites:
        var center: Vector2 = site.get("position", Vector2.ZERO)
        var radius: float = float(site.get("radius", 62.0))
        if point.distance_to(center) > radius * 1.30:
            continue
        var direction: Vector2 = site.get("direction", Vector2.ZERO)
        var road_width: float = float(site.get("road_width", 14.0))
        if direction.length_squared() <= 0.0001:
            var river_info := _nearest_road_segment(center, profile.get("river_corridors", []))
            if river_info.is_empty() or float(river_info.get("distance", INF)) > 30.0:
                continue
            if site.get("standalone", false):
                var river_direction: Vector2 = river_info.get("direction", Vector2(1.0, 0.0))
                direction = Vector2(-river_direction.y, river_direction.x).normalized()
                road_width = float(site.get("bridge_width", 10.0))
            else:
                var road_info := _nearest_road_segment(center, profile.get("road_corridors", []))
                if road_info.is_empty() or float(road_info.get("distance", INF)) > 30.0:
                    continue
                direction = road_info.get("direction", Vector2(0.0, 1.0))
                road_width = float(road_info.get("width", 14.0))
        var offset := point - center
        var along := absf(offset.dot(direction))
        var lateral := absf(offset.cross(direction))
        var river_width: float = float(site.get("river_width", 52.0))
        var deck_half := maxf(river_width + 10.0, road_width * 2.15) * 0.5
        var approach_run := 10.0
        # A small numeric margin keeps points calculated from the normalized
        # bridge direction inside the final approach sample. Without it, a
        # few standalone bridges lost their last plank to float rounding.
        if along <= deck_half + approach_run + 0.05 and lateral <= maxf(4.5, road_width * 0.42):
            var terrain_blend := 0.0
            if along > deck_half:
                terrain_blend = _smoothstep(deck_half, deck_half + approach_run, along)
            var deck_height := _river_centerline_grade(center,profile) + 0.62
            return {
                "height": deck_height,
                "terrain_blend": terrain_blend,
                # The rendered approach ends 0.16 above the raw bank. Carry
                # that same lift into movement so the hero never sinks through
                # the final plank immediately before the bridge.
                "bank_lift": 0.16 * terrain_blend,
            }
    return {}


func _road_surface_offset(point: Vector2, profile: Dictionary, road_junctions: Array[Vector2]) -> float:
    var best_offset := 0.0
    var roads: Array = profile.get("road_corridors", [])
    for road in roads:
        # WorldPreviewBuilder uses the same 0.48 visual-width conversion.
        var half_width := float(road.get("width", 26.0)) * 0.48 * 0.5
        if half_width <= 0.01:
            continue
        var distance := _distance_to_polyline(point, road.get("points", []))
        if distance > half_width:
            continue
        # A modest raised crown that tapers almost back to terrain at both
        # shoulders. This mirrors the road mesh cross-section exactly.
        var across := clampf(distance / half_width, 0.0, 1.0)
        best_offset = maxf(best_offset, lerpf(0.18, 0.12, across))

    # The preview builder caps shared road nodes with a small junction disk.
    # Include those caps in the movement surface as well.
    for junction in road_junctions:
        if point.distance_to(junction) <= 7.5:
            return maxf(best_offset, 0.18)
    return best_offset


func _trail_surface_offset(point: Vector2, profile: Dictionary) -> float:
    for trail in profile.get("trail_corridors", []):
        var visual_width := maxf(2.4, float(trail.get("width", 5.0)) * 0.48)
        var distance := _distance_to_polyline(point, trail.get("points", []))
        if distance <= visual_width * 0.5:
            var across := clampf(distance / (visual_width * 0.5), 0.0, 1.0)
            return lerpf(0.18, 0.12, across)
    return 0.0


func _collect_road_junctions(roads: Array) -> Array[Vector2]:
    var junctions: Array[Vector2] = []
    for road in roads:
        for candidate in road.get("points", []):
            var matches := 0
            for other in roads:
                for other_point in other.get("points", []):
                    if candidate.distance_to(other_point) < 9.0:
                        matches += 1
            if matches < 2:
                continue
            var duplicate := false
            for existing in junctions:
                if existing.distance_to(candidate) < 12.0:
                    duplicate = true
                    break
            if not duplicate:
                junctions.append(candidate)
    return junctions


func _nearest_road_segment(point: Vector2, roads: Array) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for road in roads:
        var points: Array = road.get("points", [])
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var segment := b - a
            var length_squared := segment.length_squared()
            if length_squared <= 0.0001:
                continue
            var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
            var closest_point:=a+segment*t
            var distance := point.distance_to(closest_point)
            if distance < best_distance:
                best_distance = distance
                var corridor_progress:float=(float(i)+t)/maxf(1.0,float(points.size()-1))
                best = {
                    "distance": distance,
                    "direction": segment.normalized(),
                    "width": _corridor_width_at(road,corridor_progress,14.0),
                    "closest_point":closest_point,
                }
    return best


func _corridor_width_at(corridor:Dictionary,progress:float,fallback:float)->float:
    var authored_width:=float(corridor.get("width",fallback))
    var source_width:=float(corridor.get("source_width",authored_width))
    var mouth_width:=float(corridor.get("mouth_width",authored_width))
    return lerpf(source_width,mouth_width,clampf(progress,0.0,1.0))


func _build_terrain_mesh(heights: PackedFloat32Array, river_distances: PackedFloat32Array, profile: Dictionary, world_size: float, grid_resolution: int, water_level: float) -> ArrayMesh:
    # Direct packed arrays avoid more than one hundred thousand interpreted
    # SurfaceTool calls at launch. This preserves the exact vertex/index data,
    # normals, colours and collision resolution while constructing the mesh in
    # the format ArrayMesh ultimately needs in the first place.
    var stride := grid_resolution + 1
    var vertex_count:=stride*stride
    var grid_step := world_size / float(grid_resolution)
    var vertices:=PackedVector3Array();vertices.resize(vertex_count)
    var normals:=PackedVector3Array();normals.resize(vertex_count)
    var colors:=PackedColorArray();colors.resize(vertex_count)
    for z_idx in range(stride):
        var z := _grid_to_world(z_idx, grid_resolution, world_size)
        for x_idx in range(stride):
            var x := _grid_to_world(x_idx, grid_resolution, world_size)
            var index := z_idx * stride + x_idx
            var height := heights[index]
            # Supply one continuous heightfield normal per shared vertex.
            # Generated face normals made each large gameplay triangle catch
            # the sun differently, which read as a checkerboard of terrain.
            var left_x:=maxi(0,x_idx-1);var right_x:=mini(grid_resolution,x_idx+1)
            var near_z:=maxi(0,z_idx-1);var far_z:=mini(grid_resolution,z_idx+1)
            var x_span:=maxf(grid_step,float(right_x-left_x)*grid_step)
            var z_span:=maxf(grid_step,float(far_z-near_z)*grid_step)
            var height_dx:=(heights[z_idx*stride+right_x]-heights[z_idx*stride+left_x])/x_span
            var height_dz:=(heights[far_z*stride+x_idx]-heights[near_z*stride+x_idx])/z_span
            vertices[index]=Vector3(x,height,z)
            normals[index]=Vector3(-height_dx,1.0,-height_dz).normalized()
            colors[index]=_terrain_color(height,Vector2(x,z),profile,water_level,river_distances[index])

    var indices:=PackedInt32Array();indices.resize(grid_resolution*grid_resolution*6)
    var write_index:=0
    for z_idx in range(grid_resolution):
        for x_idx in range(grid_resolution):
            var a := z_idx * stride + x_idx
            var b := a + 1
            var c := a + stride
            var d := c + 1
            indices[write_index]=a;indices[write_index+1]=b;indices[write_index+2]=c
            indices[write_index+3]=b;indices[write_index+4]=d;indices[write_index+5]=c
            write_index+=6
    var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    arrays[Mesh.ARRAY_NORMAL]=normals
    arrays[Mesh.ARRAY_COLOR]=colors
    arrays[Mesh.ARRAY_INDEX]=indices
    var mesh:=ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    return mesh


func _build_controlled_aqueduct_terrain(profile: Dictionary, world_size: float, water_level: float) -> ArrayMesh:
    var half_world := world_size * 0.5
    var corridors: Array = profile.get("river_corridors", [])
    var channel_width: float = 30.0
    if not corridors.is_empty():
        channel_width = corridors[0].get("width", channel_width)
    var half_channel := channel_width * 0.5
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var taper_width := 1.5
    var river_points: Array = corridors[0].get("points", []) if not corridors.is_empty() else []
    var side_segments := 56
    var segment_count := 160
    for x_idx in range(segment_count):
        var x0 := lerpf(-half_world, half_world, float(x_idx) / float(segment_count))
        var x1 := lerpf(-half_world, half_world, float(x_idx + 1) / float(segment_count))
        var center0 := _river_center_z_at_x(river_points, x0)
        var center1 := _river_center_z_at_x(river_points, x1)
        var lanes0: Array[float] = []
        var lanes1: Array[float] = []
        for side_idx in range(side_segments + 1):
            var frac := float(side_idx) / float(side_segments)
            lanes0.append(lerpf(-half_world, center0 - half_channel - taper_width, frac))
            lanes1.append(lerpf(-half_world, center1 - half_channel - taper_width, frac))
        for offset in [-half_channel, half_channel]:
            lanes0.append(center0 + offset)
            lanes1.append(center1 + offset)
        for side_idx in range(side_segments + 1):
            var frac := float(side_idx) / float(side_segments)
            lanes0.append(lerpf(center0 + half_channel + taper_width, half_world, frac))
            lanes1.append(lerpf(center1 + half_channel + taper_width, half_world, frac))
        for lane_idx in range(lanes0.size() - 1):
            var z00: float = lanes0[lane_idx]
            var z10: float = lanes1[lane_idx]
            var z01: float = lanes0[lane_idx + 1]
            var z11: float = lanes1[lane_idx + 1]
            var a := Vector3(x0, _sample_controlled_aqueduct_height(x0, z00, profile, water_level), z00)
            var b := Vector3(x1, _sample_controlled_aqueduct_height(x1, z10, profile, water_level), z10)
            var c := Vector3(x0, _sample_controlled_aqueduct_height(x0, z01, profile, water_level), z01)
            var d := Vector3(x1, _sample_controlled_aqueduct_height(x1, z11, profile, water_level), z11)
            var mid := Vector2((x0 + x1) * 0.5, (z00 + z10 + z01 + z11) * 0.25)
            var color := _terrain_color((a.y + b.y + c.y + d.y) * 0.25, mid, profile, water_level)
            _emit_colored_quad(st, a, b, c, d, color)
    st.generate_normals()
    return st.commit()


func _river_center_z_at_x(points: Array, x: float) -> float:
    if points.size() < 2:
        return 0.0
    for i in range(points.size() - 1):
        var a: Vector2 = points[i]
        var b: Vector2 = points[i + 1]
        if x >= minf(a.x, b.x) and x <= maxf(a.x, b.x):
            var span := b.x - a.x
            var t := 0.0 if absf(span) < 0.001 else (x - a.x) / span
            return lerpf(a.y, b.y, t)
    return points[0].y if x < points[0].x else points[points.size() - 1].y


func _emit_colored_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
    st.set_color(color)
    st.add_vertex(a)
    st.set_color(color)
    st.add_vertex(c)
    st.set_color(color)
    st.add_vertex(b)
    st.set_color(color)
    st.add_vertex(b)
    st.set_color(color)
    st.add_vertex(c)
    st.set_color(color)
    st.add_vertex(d)


func _vertex_at(heights: PackedFloat32Array, x_idx: int, z_idx: int, profile: Dictionary, world_size: float, grid_resolution: int, water_level: float) -> Dictionary:
    var x: float = _grid_to_world(x_idx, grid_resolution, world_size)
    var z: float = _grid_to_world(z_idx, grid_resolution, world_size)
    var h: float = heights[_grid_index(x_idx, z_idx, grid_resolution)]
    return {
        "position": Vector3(x, h, z),
        "color": _terrain_color(h, Vector2(x, z), profile, water_level),
    }


func _emit_triangle(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
    st.set_color(a.color)
    st.add_vertex(a.position)
    st.set_color(b.color)
    st.add_vertex(b.position)
    st.set_color(c.color)
    st.add_vertex(c.position)


func _terrain_color(height: float, point: Vector2, profile: Dictionary, water_level: float, cached_river_distance: float = -1.0) -> Color:
    if not profile.get("controlled_aqueduct", false) and height <= water_level + 0.5:
        return Color(0.045, 0.18, 0.28, 1.0)
    var macro_noise: float = (_base_noise.get_noise_2d(point.x * 0.6, point.y * 0.6) + 1.0) * 0.5
    var detail_noise: float = (_detail_noise.get_noise_2d(point.x * 1.4 + 120.0, point.y * 1.4 - 80.0) + 1.0) * 0.5
    var speckle_noise: float = (_ridge_noise.get_noise_2d(point.x * 2.4 - 70.0, point.y * 2.4 + 45.0) + 1.0) * 0.5
    var broad_bands: float = (_valley_noise.get_noise_2d(point.x * 0.32 + 240.0, point.y * 0.32 - 160.0) + 1.0) * 0.5
    var mix_value: float = clampf(macro_noise * 0.45 + detail_noise * 0.30 + broad_bands * 0.25, 0.0, 1.0)
    if profile.get("controlled_aqueduct", false):
        var river_distance := cached_river_distance if cached_river_distance >= 0.0 else INF
        var river_width := 84.0
        var rivers: Array = profile.get("river_corridors", [])
        if cached_river_distance < 0.0:
            for river in rivers:
                var candidate_distance := _distance_to_polyline(point, river.get("points", []))
                if candidate_distance < river_distance:
                    river_distance = candidate_distance
                    river_width = float(river.get("width", river_width))
        else:
            # All authored river branches currently share their physical
            # channel width. Avoid a second nearest-polyline scan just to
            # rediscover the same value during vertex coloring.
            for river in rivers:
                river_width = float(river.get("width", river_width))
                break
        # River soil now fades into the regional palette across an irregular
        # transition instead of returning two hard color bands. The visible
        # shoreline mesh handles close detail; this vertex blend keeps the
        # coarse terrain beneath it from drawing straight brown/green seams.
        var river_soil:=Color(0.20,0.16,0.095,1.0).lerp(Color(0.34,0.30,0.19,1.0),detail_noise*.62+broad_bands*.38)
        var shoreline_warp:=(_moisture_noise.get_noise_2d(point.x*1.7+31.0,point.y*1.7-47.0))*5.5
        var river_soil_weight:=1.0-_smoothstep(river_width*.42+shoreline_warp,river_width*.5+18.0+shoreline_warp,river_distance)
        var controlled_world_size: float = profile.get("world_size", 7200.0)
        var controlled_moisture: float = (_moisture_noise.get_noise_2d(point.x, point.y) + 1.0) * 0.5
        var biome := Color(0.12, 0.25, 0.10, 1.0).lerp(Color(0.26, 0.36, 0.18, 1.0), mix_value)
        # Biomes used to switch on exact X/Z thresholds, which exposed the
        # heightfield grid as large square color blocks. Noise-warped transition
        # bands make the same regions flow together as irregular ecotones.
        var boundary_warp:=_biome_noise.get_noise_2d(point.x*.37+91.0,point.y*.37-53.0)*controlled_world_size*.045
        var east_mix:=_smoothstep(controlled_world_size*.07+boundary_warp,controlled_world_size*.27+boundary_warp,point.x)
        var west_mix:=1.0-_smoothstep(-controlled_world_size*.31+boundary_warp,-controlled_world_size*.11+boundary_warp,point.x)
        var north_mix:=_smoothstep(controlled_world_size*.08-boundary_warp,controlled_world_size*.29-boundary_warp,point.y)
        var south_mix:=1.0-_smoothstep(-controlled_world_size*.29-boundary_warp,-controlled_world_size*.09-boundary_warp,point.y)
        var east_color:=Color(0.22,0.28,0.13,1.0).lerp(Color(0.35,0.36,0.20,1.0),detail_noise)
        var west_color:=Color(0.10,0.21,0.11,1.0).lerp(Color(0.22,0.30,0.18,1.0),controlled_moisture)
        biome=biome.lerp(east_color,east_mix*.82)
        biome=biome.lerp(west_color,west_mix*.82)
        biome=biome.lerp(Color(0.14,0.27,0.21,1.0),north_mix*.38)
        biome=biome.lerp(Color(0.36,0.29,0.17,1.0),south_mix*.36)
        var exposed_soil := clampf((speckle_noise - 0.70) * 2.2, 0.0, 0.32)
        biome = biome.lerp(Color(0.24, 0.17, 0.095, 1.0), exposed_soil)
        if height > 45.0:
            biome = biome.lerp(Color(0.34, 0.34, 0.31, 1.0), clampf((height - 45.0) / 90.0, 0.0, 0.88))
        var forest_mix:=_region_influence(point,profile.get("forest_regions",[]))
        biome=biome.lerp(Color(0.075,0.17,0.105,1.0),forest_mix*.62)
        biome=_apply_authored_terrain_palette(biome,point,height,profile.get("terrain_palette_regions",[]))
        return biome.lerp(river_soil,clampf(river_soil_weight,0.0,1.0))
    if height < water_level + 2.2:
        return Color(0.31, 0.25, 0.11, 1.0)
    if height > 25.0:
        return Color(0.20, 0.22, 0.21, 1.0).lerp(Color(0.46, 0.48, 0.47, 1.0), clampf((height - 25.0) / 18.0, 0.0, 1.0))
    if height > 15.0:
        return Color(0.12, 0.25, 0.10, 1.0).lerp(Color(0.29, 0.29, 0.22, 1.0), clampf((height - 15.0) / 10.0, 0.0, 1.0))
    var world_size: float = profile.get("world_size", 2400.0)
    var moisture: float = (_moisture_noise.get_noise_2d(point.x, point.y) + 1.0) * 0.5
    var in_forest: bool = _point_in_region(point, profile.get("forest_regions", []), 1.0)
    var eastern_dryland: bool = point.x > world_size * 0.12 and point.y > -world_size * 0.30
    var western_heath: bool = point.x < -world_size * 0.22 and point.y < world_size * 0.12
    var base_grass := Color(0.10, 0.30, 0.055, 1.0)
    var darker_grass := Color(0.055, 0.20, 0.035, 1.0)
    var lighter_grass := Color(0.18, 0.40, 0.075, 1.0)
    var moss_grass := Color(0.07, 0.25, 0.055, 1.0)
    var grass: Color = darker_grass.lerp(base_grass, mix_value)
    grass = grass.lerp(lighter_grass, clampf(detail_noise - 0.45, 0.0, 1.0) * 0.42)
    grass = grass.lerp(moss_grass, clampf(speckle_noise - 0.62, 0.0, 1.0) * 0.30)
    if speckle_noise > 0.82:
        grass = grass.lerp(Color(0.43, 0.56, 0.28, 1.0), 0.22)
    if in_forest:
        grass = Color(0.035, 0.13, 0.055, 1.0).lerp(Color(0.07, 0.23, 0.075, 1.0), moisture)
    elif eastern_dryland:
        grass = Color(0.25, 0.18, 0.055, 1.0).lerp(Color(0.40, 0.30, 0.085, 1.0), detail_noise)
    elif western_heath:
        grass = Color(0.14, 0.17, 0.055, 1.0).lerp(Color(0.24, 0.24, 0.075, 1.0), moisture)
    elif moisture > 0.64:
        grass = grass.lerp(Color(0.18, 0.43, 0.23, 1.0), 0.62)
    return grass


func _make_terrain_material(profile:Dictionary={}) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D soil_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float snow_line = 10000.0;
uniform float snow_strength = 0.0;
uniform vec2 region_origin = vec2(0.0);
uniform float glacial_biome = 0.0;
uniform vec2 glacier_center = vec2(0.0);
uniform float glacier_radius = 1.0;
uniform float marcher_biome = 0.0;
uniform vec2 volcanic_center = vec2(100000.0);
uniform float volcanic_radius = 1.0;

varying vec3 world_position;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;
    vec2 local_p = p - region_origin;
    // Four shared fields replace thirteen near-duplicate value-noise calls.
    // Their rotated inputs retain irregular boundaries without making the
    // full-screen terrain shader the dominant cost while moving.
    // Broad colour variation must not expose the square cells of value noise.
    // Blend a small rotated-noise contribution into two long, crossing waves;
    // the result stays organic but has no visible cell boundary from a hill or
    // bridge approach.
    float broad_cell = value_noise(vec2(p.x * 0.021 + p.y * 0.008, -p.x * 0.008 + p.y * 0.021) + vec2(11.0, 23.0));
    float broad = clamp(0.50
        + sin(p.x * 0.0107 + p.y * 0.0061) * 0.19
        + sin(-p.x * 0.0068 + p.y * 0.0093 + 1.73) * 0.14
        + (broad_cell - 0.5) * 0.22, 0.0, 1.0);
    float clumps = value_noise(vec2(p.x * 0.052 + p.y * 0.019, -p.x * 0.019 + p.y * 0.052) + vec2(19.0, 7.0));
    float grit = value_noise(p * 0.24 + vec2(3.0, 31.0));
    float macro_field = clamp(0.50
        + sin(p.x * 0.0024 + p.y * 0.0011 + 0.41) * 0.20
        + sin(-p.x * 0.00135 + p.y * 0.00205 + 2.07) * 0.15
        + (broad - 0.5) * 0.18, 0.0, 1.0);
    vec3 base = COLOR.rgb;
    float camera_distance = distance(world_position, CAMERA_POSITION_WORLD);
    float detail_fade = 1.0 - smoothstep(95.0, 420.0, camera_distance);
    vec3 dark_soil = vec3(0.135, 0.095, 0.052);
    vec3 dry_grass = vec3(0.285, 0.29, 0.16);
    vec3 moss = vec3(0.075, 0.17, 0.075);
    vec3 meadow = vec3(0.15, 0.285, 0.12);
    vec3 stone = vec3(0.26, 0.265, 0.255);
    vec3 color = base * mix(0.93, 1.065, broad);
    color = mix(color, moss, smoothstep(0.72, 0.94, clumps) * 0.22);
    color = mix(color, dry_grass, smoothstep(0.86, 0.98, broad) * 0.10);
    color = mix(color, dark_soil, smoothstep(0.88, 0.985, grit) * 0.12 * detail_fade);
    color *= mix(0.975, 1.025, grit * detail_fade);
    // Keep individual blades and pebbles near human scale. The generated
    // source contains larger photographic structures than the previous map.
    vec2 terrain_uv = p * 0.085;
    vec2 terrain_uv_rot = vec2(p.x * 0.057 + p.y * 0.063, -p.x * 0.063 + p.y * 0.057) + vec2(7.31, 2.17);
    float tile_blend = smoothstep(0.22, 0.78, clumps);
    vec3 grass_albedo = mix(texture(grass_texture, terrain_uv).rgb, texture(grass_texture, terrain_uv_rot).rgb, tile_blend);
    // Do not magnify the source photograph for macro variation. That exposed
    // its rectangular image border as huge square biome tiles. Procedural,
    // overlapping noise fields provide broad variation without any seam.
    grass_albedo *= mix(0.91, 1.075, smoothstep(0.12, 0.88, macro_field));
    grass_albedo *= vec3(1.035, 1.025, 0.96);
    float grass_luma = dot(grass_albedo, vec3(0.2126, 0.7152, 0.0722));
    grass_albedo = mix(vec3(grass_luma), grass_albedo, 0.94);
    vec3 soil_albedo = texture(soil_texture, terrain_uv * 0.82 + vec2(0.17, 0.31)).rgb * vec3(0.88, 0.93, 1.02);
    // A single repeated stone photograph exposed its image boundary as a
    // glaring checkerboard across snowfields and high ridges. Three
    // incommensurate rotations/scales ensure no rectangular edge can dominate
    // the ground, while a procedural mineral tint keeps the blend geological.
    vec3 stone_a = texture(stone_texture, terrain_uv * 0.68 + vec2(0.43, 0.11)).rgb;
    vec3 stone_b = texture(stone_texture, terrain_uv_rot * 0.79 + vec2(3.17, 5.29)).rgb;
    vec2 stone_uv_cross = vec2(p.x * 0.031 - p.y * 0.047, p.x * 0.047 + p.y * 0.031) + vec2(13.7, 2.9);
    vec3 stone_c = texture(stone_texture, stone_uv_cross).rgb;
    vec3 stone_albedo = stone_a * 0.43 + stone_b * 0.35 + stone_c * 0.22;
    vec3 mineral_stone = mix(vec3(0.245, 0.255, 0.25), vec3(0.39, 0.385, 0.35), broad * 0.58 + clumps * 0.42);
    stone_albedo = mix(stone_albedo, mineral_stone, 0.22 + glacial_biome * 0.18);
    // Soil speckles come from fine noise only. Thresholding interpolated
    // biome colour switched an entire coarse triangle to a different texture.
    float soil_marker = clamp(smoothstep(0.74, 0.95, grit) * 0.24 * detail_fade + smoothstep(0.78, 0.96, broad) * 0.16, 0.0, 0.38);
    float slope = 1.0 - smoothstep(0.48, 0.86, abs(NORMAL.y));
    float highland = smoothstep(28.0, 88.0, world_position.y);
    float stone_weight = clamp(max(slope * 0.62, highland), 0.0, 0.82);
    vec3 textured_ground = mix(grass_albedo, soil_albedo, soil_marker * 0.72);
    float dry_patch = smoothstep(0.56, 0.82, macro_field * 0.64 + broad * 0.36);
    textured_ground = mix(textured_ground, vec3(0.33, 0.29, 0.16), dry_patch * (1.0 - stone_weight) * 0.20);
    float meadow_patch = smoothstep(0.61, 0.87, clumps * 0.62 + (1.0 - macro_field) * 0.38);
    textured_ground = mix(textured_ground, vec3(0.13, 0.235, 0.095), meadow_patch * (1.0 - dry_patch) * (1.0 - stone_weight) * 0.24);
    textured_ground = mix(textured_ground, stone_albedo, stone_weight);
    // Alpine profiles opt into a continuous altitude-driven snow cap. Noise
    // softens the snow line and exposed steep faces retain some stone, so the
    // mountain reads as accumulated snow rather than a white painted band.
    float snow_noise = broad * 0.58 + clumps * 0.42;
    float snow_altitude = smoothstep(snow_line - 24.0 + (snow_noise - 0.5) * 28.0, snow_line + 44.0 + (snow_noise - 0.5) * 28.0, world_position.y);
    float snow_slope_hold = mix(0.28, 1.0, smoothstep(0.34, 0.91, abs(NORMAL.y)));
    float snow_weight = clamp(snow_altitude * snow_slope_hold * snow_strength, 0.0, 0.90);
    // Within the glacial tile, a strongly height-driven white/stone mix made
    // every coarse planar triangle legible. Preserve altitude as a secondary
    // influence, but let continuous rotated world fields carry most of the
    // snow mantle so neighboring triangles cannot alternate gray and white.
    float glacial_snow_mantle = clamp(0.57 + (macro_field - 0.5) * 0.14 + (broad - 0.5) * 0.10, 0.48, 0.70);
    snow_weight = mix(snow_weight, glacial_snow_mantle, glacial_biome * 0.74);
    vec3 packed_snow = mix(stone_albedo * vec3(0.92, 0.98, 1.03), vec3(0.82, 0.855, 0.86), clumps * 0.72 + broad * 0.18);
    vec3 snow_color = packed_snow * mix(0.92, 1.035, grit * detail_fade);
    textured_ground = mix(textured_ground, snow_color, snow_weight);
    // Continuous regional tint replaces coarse authored vertex patches. The
    // four broad blends keep western heath, northern moss, eastern grassland
    // and southern dry ground distinct without exposing triangle boundaries.
    float east_region = smoothstep(620.0, 2750.0, p.x + (macro_field - 0.5) * 310.0);
    float west_region = 1.0 - smoothstep(-2700.0, -620.0, p.x + (broad - 0.5) * 280.0);
    float north_region = smoothstep(760.0, 2860.0, p.y + (clumps - 0.5) * 260.0);
    float south_region = 1.0 - smoothstep(-2780.0, -720.0, p.y + (macro_field - 0.5) * 300.0);
    vec3 regional_tint = vec3(0.17, 0.275, 0.115);
    regional_tint = mix(regional_tint, vec3(0.29, 0.285, 0.145), east_region * 0.72);
    regional_tint = mix(regional_tint, vec3(0.115, 0.235, 0.115), west_region * 0.58);
    regional_tint = mix(regional_tint, vec3(0.12, 0.25, 0.17), north_region * 0.42);
    regional_tint = mix(regional_tint, vec3(0.34, 0.265, 0.12), south_region * 0.46);
    textured_ground = mix(textured_ground, regional_tint, (1.0 - stone_weight) * 0.18);
    // Resolve photographic micro-detail into stable regional colour before it
    // becomes sub-pixel noise. This complements mipmapping and removes the
    // glitter/crawl seen across distant slopes while the camera is moving.
    float distance_simplify = smoothstep(170.0, 760.0, camera_distance);
    vec3 stable_distance_ground = mix(regional_tint, stone, stone_weight);
    stable_distance_ground = mix(stable_distance_ground, vec3(0.72, 0.77, 0.78), snow_weight);
    textured_ground = mix(textured_ground, stable_distance_ground, distance_simplify * 0.76);
    // Preserve enough authored vertex colour for Westmere heath, Northwood
    // moss and Southbank ochre to remain distinct beneath the shared detail.
    // The near field keeps tactile surface detail. At distance it resolves to
    // authored biome colour plus macro variation, preventing the crawling
    // speckle and eye-strain that was visible while walking.
    // Coarse per-vertex biome colour must not reveal the heightfield's large
    // diagonal triangles. Retain it as a regional tint beneath continuous
    // world-space texture instead of letting it define visible patch edges.
    // The heightfield's biome COLOR is sampled only at coarse mesh vertices.
    // Even a two-percent contribution was enough to reveal long triangle edges
    // while moving. Regional identity is already reproduced continuously above,
    // so use the world-space result outright and eliminate those hard facets.
    color = textured_ground;
    // Strong, overlapping earth and meadow fields stay visible at walking
    // distance. Rotated coordinates prevent these patches reading as a grid.
    color = mix(color, vec3(0.34, 0.29, 0.16), smoothstep(0.55, 0.84, broad) * (1.0 - stone_weight) * 0.15);
    color = mix(color, vec3(0.15, 0.30, 0.115), smoothstep(0.61, 0.91, clumps) * (1.0 - dry_patch) * (1.0 - stone_weight) * 0.11);
    color = mix(color, color * vec3(0.90, 0.86, 0.76), (1.0 - smoothstep(0.16, 0.52, macro_field)) * (1.0 - stone_weight) * 0.09);
    color = mix(color, color * vec3(0.94, 1.025, 0.88), smoothstep(0.56, 0.90, macro_field) * (1.0 - stone_weight) * 0.075);
    // Streamed alpine regions need their regional identity evaluated in local
    // coordinates. Previously global Z made the entire range inherit the
    // starter map's far-south grass tint, even directly beneath the glacier.
    float final_glacial_snow_cover = 0.0;
    if (glacial_biome > 0.5) {
        // Glacial colour must be evaluated entirely in continuous world-space
        // fields. Height/slope masks are geometrically correct, but on the
        // 22.5 m gameplay mesh their strong white/gray contrast exposed each
        // planar triangle. These fields retain cold direction, glacier apron,
        // snow islands and moraine without consulting triangle orientation.
        float north_cold = 1.0 - smoothstep(-2500.0, 1500.0, local_p.y);
        float glacier_distance = distance(local_p, glacier_center);
        float forefield = 1.0 - smoothstep(glacier_radius * 0.48, glacier_radius, glacier_distance);
        // Long sinusoidal macro fields looked like parallel contour stripes
        // across shallow snow. Two differently rotated, incommensurate noise
        // fields overlap so neither one's square lattice can read on its own.
        vec2 glacier_uv_a = vec2(local_p.x * 0.0043 + local_p.y * 0.0027, -local_p.x * 0.0027 + local_p.y * 0.0043) + vec2(37.0, 11.0);
        vec2 glacier_uv_b = vec2(local_p.x * 0.0021 - local_p.y * 0.0058, local_p.x * 0.0058 + local_p.y * 0.0021) + vec2(9.0, 43.0);
        float glacier_macro_a = value_noise(glacier_uv_a);
        float glacier_macro_b = value_noise(glacier_uv_b);
        float glacier_detail = value_noise(vec2(local_p.x * 0.031 + local_p.y * 0.014, -local_p.x * 0.014 + local_p.y * 0.031) + vec2(53.0, 17.0));
        float glacier_field = glacier_macro_a * 0.52 + glacier_macro_b * 0.34 + glacier_detail * 0.14;
        float moraine_field = smoothstep(0.58, 0.82, glacier_macro_b * 0.62 + glacier_detail * 0.38);
        final_glacial_snow_cover = clamp(
            0.38 + north_cold * 0.24 + forefield * 0.15
            + (glacier_field - 0.5) * 0.20
            - moraine_field * 0.18,
            0.30, 0.78);
        // The source stone photograph still carried long light bands when it
        // showed through the snow at eye level. Keep a trace of that mineral
        // detail, but let non-repeating world fields define the exposed rock.
        vec3 glacial_rock = mix(vec3(0.21, 0.235, 0.24), vec3(0.34, 0.36, 0.35), glacier_field);
        glacial_rock = mix(glacial_rock, vec3(0.22, 0.255, 0.27), moraine_field * 0.30);
        // Snow stays below display white so its shallow relief remains legible
        // under the range's bright sky. Fine continuous fields add packed-snow
        // grain without a texture boundary, hard threshold, or square repeat.
        vec3 glacial_snow = mix(vec3(0.55, 0.60, 0.63), vec3(0.69, 0.73, 0.75), glacier_field);
        float snow_grain = (grit - 0.5) * 0.052 * detail_fade + (glacier_detail - 0.5) * 0.032;
        glacial_snow *= 1.0 + snow_grain;
        glacial_snow = mix(glacial_snow, vec3(0.56, 0.67, 0.72), forefield * 0.12);
        color = mix(glacial_rock, glacial_snow, final_glacial_snow_cover);
    }
    if (marcher_biome > 0.5) {
        // Continuous local-coordinate masks distinguish the Marches' loess,
        // alluvium, chalk and basalt without exposing coarse mesh triangles.
        vec2 march_p = local_p + vec2((broad - 0.5) * 210.0, (clumps - 0.5) * 180.0);
        float west_loess = 1.0 - smoothstep(-1650.0, -150.0, march_p.x);
        float amber_plain = 1.0 - smoothstep(-420.0, 1050.0, abs(march_p.x + 650.0));
        vec2 vale_normal = vec2(0.659, 0.752);
        float vale_distance = abs(dot(march_p - vec2(120.0, 260.0), vale_normal));
        float ember_alluvium = 1.0 - smoothstep(280.0, 930.0, vale_distance);
        float cinder_upland = smoothstep(920.0, 2400.0, march_p.x) * (1.0 - smoothstep(150.0, 1550.0, march_p.y));
        float glass_chalk = smoothstep(900.0, 2250.0, march_p.x) * smoothstep(1250.0, 2680.0, march_p.y);
        vec3 march_color = mix(color, vec3(0.31, 0.29, 0.13), west_loess * 0.38);
        march_color = mix(march_color, vec3(0.32, 0.30, 0.12), amber_plain * 0.28);
        march_color = mix(march_color, vec3(0.20, 0.27, 0.12), ember_alluvium * 0.34);
        march_color = mix(march_color, vec3(0.25, 0.23, 0.21), cinder_upland * 0.56);
        march_color = mix(march_color, vec3(0.34, 0.35, 0.23), glass_chalk * 0.48);
        // Embercrag needs a landform-scale volcanic apron rather than dark
        // props pasted onto ordinary grassland. Rotated macro noise warps two
        // broad radial fades, avoiding a circular decal or a hard biome band.
        vec2 volcanic_p = march_p + vec2((macro_field - 0.5) * 240.0, (broad - 0.5) * 190.0);
        float volcanic_distance = distance(volcanic_p, volcanic_center);
        float ash_apron = 1.0 - smoothstep(volcanic_radius * 0.48, volcanic_radius, volcanic_distance);
        float basalt_core = 1.0 - smoothstep(volcanic_radius * 0.18, volcanic_radius * 0.56, volcanic_distance);
        vec3 ash_ground = mix(stone_albedo * vec3(0.58, 0.55, 0.51), vec3(0.125, 0.118, 0.108), 0.54 + clumps * 0.20);
        ash_ground = mix(ash_ground, vec3(0.205, 0.125, 0.070), smoothstep(0.76, 0.95, grit) * detail_fade * 0.20);
        float volcanic_weight = ash_apron * (0.34 + basalt_core * 0.38) * mix(0.88, 1.0, stone_weight);
        march_color = mix(march_color, ash_ground, volcanic_weight);
        color = mix(color, march_color, 0.60);
    }
    // World-scale biome colour is already authored per vertex with warped
    // borders. Avoid large thresholded value-noise patches here: those reveal
    // the noise lattice as square or triangular fields from a distance.
    float final_luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(final_luma), color, 0.94);
    color *= vec3(1.015, 1.01, 0.965);
    // Bright snow made the coarse gameplay heightfield's otherwise subtle
    // lighting facets read as giant diagonal polygons. Snow physically rounds
    // small terrain breaks, so soften only its rendered normal toward world
    // up. Collision, vertex height and exposed-rock slope shading are intact.
    vec3 world_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    float snow_normal_smoothing = glacial_biome * (0.84 + final_glacial_snow_cover * 0.10);
    NORMAL = normalize(mix(NORMAL, world_up_view, snow_normal_smoothing));
    ALBEDO = color;
    // Snow receives the same world lighting as every other ground material.
    // A previous emissive lift hid facets in a diagnostic capture but washed
    // the playable range into a featureless white field.
    EMISSION = vec3(0.0);
    ROUGHNESS = 0.96;
    SPECULAR = 0.08;
}
"""
    material.shader = shader
    material.set_shader_parameter("grass_texture", load("res://assets/terrain/meadow_soil_realistic_v3.png"))
    material.set_shader_parameter("soil_texture", load("res://assets/terrain/woodland_soil_v1.png"))
    material.set_shader_parameter("stone_texture", load("res://assets/terrain/highland_stone_v1.png"))
    material.set_shader_parameter("snow_line",float(profile.get("snow_line",10000.0)))
    material.set_shader_parameter("snow_strength",float(profile.get("snow_strength",0.0)))
    material.set_shader_parameter("region_origin",profile.get("region_origin",Vector2.ZERO))
    var glacial_biome:=str(profile.get("biome_id",""))=="glacial_alpine"
    material.set_shader_parameter("glacial_biome",1.0 if glacial_biome else 0.0)
    material.set_shader_parameter("marcher_biome",1.0 if str(profile.get("biome_id",""))=="continental_marches" else 0.0)
    var volcanic_center:=Vector2(100000.0,100000.0)
    var volcanic_radius:=1.0
    if str(profile.get("biome_id",""))=="continental_marches":
        for site in profile.get("map_sites",[]):
            if str(site.get("kind",""))=="volcano":
                volcanic_center=site.get("position",Vector2(100000.0,100000.0))
                volcanic_radius=maxf(1200.0,float(site.get("radius",170.0))*8.2)
                break
    material.set_shader_parameter("volcanic_center",volcanic_center)
    material.set_shader_parameter("volcanic_radius",volcanic_radius)
    var glacier_center:=Vector2.ZERO
    var glacier_radius:=1.0
    if glacial_biome:
        for site in profile.get("map_sites",[]):
            if str(site.get("kind",""))=="glacier":
                glacier_center=site.get("position",Vector2.ZERO)
                glacier_radius=maxf(520.0,float(site.get("radius",170.0))*4.25)
                break
    material.set_shader_parameter("glacier_center",glacier_center)
    material.set_shader_parameter("glacier_radius",glacier_radius)
    return material


func _build_water_plane(world_size: float, water_level: float) -> MeshInstance3D:
    var water: MeshInstance3D = MeshInstance3D.new()
    water.name = "OceanPlane"

    var ocean_mesh: PlaneMesh = PlaneMesh.new()
    ocean_mesh.size = Vector2(world_size * 1.9, world_size * 1.9)
    water.mesh = ocean_mesh
    water.position.y = water_level

    var water_material: StandardMaterial3D = StandardMaterial3D.new()
    water_material.albedo_color = Color(0.10, 0.36, 0.52, 0.92)
    water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    water_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    water_material.roughness = 0.08
    water_material.metallic = 0.02
    water_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    water.material_override = water_material

    return water


func _flatten_world_region(height: float, point: Vector2, region: Dictionary) -> float:
    var center: Vector2 = region.get("center", Vector2.ZERO)
    var radius: float = region.get("radius", 120.0)
    var target_height: float = region.get("height", 10.0)
    var strength: float = region.get("strength", 0.82)
    var dist: float = point.distance_to(center)
    var blend: float = 1.0 - _smoothstep(radius * 0.45, radius, dist)
    if blend <= 0.0:
        return height
    return lerpf(height, target_height, blend * strength)


func _mountain_chain_height(point: Vector2, chain: Dictionary) -> float:
    var center: Vector2 = chain.get("center", Vector2.ZERO)
    var angle: float = chain.get("angle", 0.0)
    var length: float = chain.get("length", 1200.0)
    var width: float = chain.get("width", 240.0)
    var peak_height: float = chain.get("height", 42.0)
    var local: Vector2 = _rotate_point(point - center, -angle)
    var spine_half: float = maxf(1.0, length * 0.5)
    var x_dist: float = maxf(0.0, absf(local.x) - spine_half)
    var y_dist: float = absf(local.y)
    var dist: float = sqrt(x_dist * x_dist + y_dist * y_dist)
    var frac: float = 1.0 - _smoothstep(width * 0.28, width, dist)
    return peak_height * frac


func _authored_landform_height(point:Vector2,region:Dictionary)->float:
    var center:Vector2=region.get("center",Vector2.ZERO)
    var angle:float=float(region.get("angle",0.0))
    var local:Vector2=_rotate_point(point-center,-angle)
    var kind:String=str(region.get("kind","rolling"))
    var amplitude:float=float(region.get("amplitude",10.0))
    if kind=="knolls":
        var radius:float=maxf(1.0,float(region.get("radius",760.0)))
        var aspect:float=maxf(.18,float(region.get("aspect",.72)))
        var count:int=clampi(int(region.get("count",5)),3,9)
        var knoll_height:=0.0
        # A deliberately spaced chain of overlapping, asymmetric hills gives
        # the middle distance readable silhouettes without random spikes.
        for index in range(count):
            var t:float=-1.0+2.0*float(index)/float(maxi(1,count-1))
            var lobe_center:=Vector2(
                t*radius*.62,
                sin(float(index)*2.17+center.x*.001)*radius*aspect*.27
            )
            var lobe_radius:=radius*(.20+.035*float((index*5)%4))
            var lobe_aspect:=.68+.09*float((index*3)%4)
            var delta:=local-lobe_center
            var lobe_distance:=Vector2(delta.x/lobe_radius,delta.y/(lobe_radius*lobe_aspect)).length()
            if lobe_distance>=1.0:continue
            var crown:=1.0-_smoothstep(.10,1.0,lobe_distance)
            var weathering:=.88+_ridge_noise.get_noise_2d(point.x*.19+float(index)*41.0,point.y*.19-float(index)*29.0)*.12
            knoll_height+=amplitude*(.72+.08*float(index%3))*crown*weathering
        return knoll_height
    if kind=="ridge" or kind=="valley":
        var length:float=maxf(1.0,float(region.get("length",900.0)))
        var width:float=maxf(1.0,float(region.get("width",260.0)))
        var along_fade:=1.0-_smoothstep(length*.38,length*.55,absf(local.x))
        var cross_fade:=1.0-_smoothstep(width*.18,width,absf(local.y))
        var spine_texture:=.82+_ridge_noise.get_noise_2d(local.x*.18+31.0,local.y*.24-77.0)*.18
        var signed_amplitude:=amplitude if kind=="ridge" else -amplitude
        return signed_amplitude*along_fade*cross_fade*spine_texture
    var radius:float=maxf(1.0,float(region.get("radius",800.0)))
    var aspect:float=maxf(.18,float(region.get("aspect",1.0)))
    var normalized:=Vector2(local.x/radius,local.y/(radius*aspect))
    var distance:=normalized.length()
    if distance>=1.0:return 0.0
    var weight:=1.0-_smoothstep(.62,1.0,distance)
    if kind=="basin":
        var bowl:=1.0-_smoothstep(.08,.88,distance)
        var rim:=sin(clampf(distance,0.0,1.0)*PI)*amplitude*.18
        return (-amplitude*bowl+rim)*weight
    if kind=="upland":
        var crown:=1.0-_smoothstep(.18,.92,distance)
        var broken_surface:=_base_noise.get_noise_2d(point.x*.20+141.0,point.y*.20-93.0)*amplitude*.20
        return (amplitude*crown+broken_surface)*weight
    var wavelength:float=maxf(90.0,float(region.get("wavelength",320.0)))
    var broad_roll:=sin(local.x/wavelength*TAU)*.58+sin((local.y+local.x*.28)/(wavelength*.72)*TAU)*.31
    var soft_noise:=_valley_noise.get_noise_2d(point.x*.28-119.0,point.y*.28+84.0)*.36
    return (broad_roll+soft_noise)*amplitude*weight


func _ocean_basin_depth(point: Vector2, basin: Dictionary) -> float:
    var center: Vector2 = basin.get("center", Vector2.ZERO)
    var inner: float = basin.get("inner", 240.0)
    var outer: float = basin.get("outer", 620.0)
    var depth: float = basin.get("depth", 48.0)
    var dist: float = point.distance_to(center)
    return (1.0 - _smoothstep(inner, outer, dist)) * depth


func _carve_river_valley(height: float, point: Vector2, corridor: Dictionary, water_level: float) -> float:
    var width: float = corridor.get("width", 44.0)
    var dist: float = _distance_to_polyline(point, corridor.get("points", []))
    var channel_half_width := width * 0.5
    if dist <= channel_half_width:
        var bed_variation := _detail_noise.get_noise_2d(point.x * 0.45, point.y * 0.45) * 0.16
        return minf(height, water_level + 0.18 + bed_variation)
    return height


func _soften_road_corridor(height: float, point: Vector2, corridor: Dictionary) -> float:
    var width: float = corridor.get("width", 26.0)
    var dist: float = _distance_to_polyline(point, corridor.get("points", []))
    if dist >= width * 2.2:
        return height
    var frac: float = 1.0 - _smoothstep(width * 0.4, width * 2.2, dist)
    return lerpf(height, height - 2.0, frac * 0.35)


func _point_in_corridor(point: Vector2, corridors: Array, extra_width_scale: float) -> bool:
    for corridor in corridors:
        var width: float = corridor.get("width", 42.0) * extra_width_scale
        if _distance_to_polyline(point, corridor.get("points", [])) <= width:
            return true
    return false


func _point_in_region(point: Vector2, regions: Array, width_scale: float) -> bool:
    for region in regions:
        var center: Vector2 = region.get("center", Vector2.ZERO)
        var radius: float = region.get("radius", 120.0) * width_scale
        if point.distance_to(center) <= radius:
            return true
    return false


func _region_influence(point:Vector2,regions:Array)->float:
    var influence:=0.0
    for region in regions:
        var center:Vector2=region.get("center",Vector2.ZERO)
        var radius:float=region.get("radius",120.0)
        influence=maxf(influence,1.0-_smoothstep(radius*.68,radius*1.08,point.distance_to(center)))
    return influence


func _apply_authored_terrain_palette(base:Color,point:Vector2,height:float,regions:Array)->Color:
    if regions.is_empty():return base
    var result:=base
    var edge_warp:=_biome_noise.get_noise_2d(point.x*.31+317.0,point.y*.31-149.0)*.085
    var highland_protection:=1.0-_smoothstep(34.0,76.0,height)
    for region in regions:
        var center:Vector2=region.get("center",Vector2.ZERO)
        var radius:float=maxf(1.0,float(region.get("radius",900.0)))
        var aspect:float=maxf(.25,float(region.get("aspect",1.0)))
        var angle:float=float(region.get("angle",0.0))
        var local:=_rotate_point(point-center,-angle)
        var normalized:=Vector2(local.x/radius,local.y/(radius*aspect))
        var distance:=normalized.length()+edge_warp
        var weight:float=(1.0-_smoothstep(.58,1.04,distance))*float(region.get("strength",.25))*highland_protection
        if weight<=0.0:continue
        var raw_color:Array=region.get("color",[base.r,base.g,base.b])
        if raw_color.size()<3:continue
        var tint:=Color(float(raw_color[0]),float(raw_color[1]),float(raw_color[2]),1.0)
        var raw_secondary:Array=region.get("secondary_color",raw_color)
        if raw_secondary.size()>=3:
            var secondary:=Color(float(raw_secondary[0]),float(raw_secondary[1]),float(raw_secondary[2]),1.0)
            var mottle:=(_biome_noise.get_noise_2d(
                point.x*.72+center.x*.13,
                point.y*.72-center.y*.11
            )+1.0)*.5
            tint=tint.lerp(secondary,_smoothstep(.30,.76,mottle)*.62)
            weight*=.78+mottle*.28
        result=result.lerp(tint,clampf(weight*1.18,0.0,.56))
    return result


func _is_bridge_crossing(point: Vector2, profile: Dictionary) -> bool:
    for road in profile.get("road_corridors", []):
        var road_width: float = road.get("width", 16.0) * 0.72
        if _distance_to_polyline(point, road.get("points", [])) > road_width:
            continue
        for river in profile.get("river_corridors", []):
            var river_width: float = river.get("width", 36.0) * 0.78
            if _distance_to_polyline(point, river.get("points", [])) <= river_width:
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
    var q: Vector2 = a + ab * t
    return point.distance_to(q)


func _rotate_point(point: Vector2, angle: float) -> Vector2:
    var c: float = cos(angle)
    var s: float = sin(angle)
    return Vector2(point.x * c - point.y * s, point.x * s + point.y * c)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
    var t: float = clamp((value - edge0) / maxf(0.0001, edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
