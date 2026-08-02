extends RefCounted

const TERRAIN_MATERIAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const TERRAIN_CACHE_VERSION:=6
const TERRAIN_MESH_CACHE_VERSION:=2
const TERRAIN_PROFILE_PATH:="res://data/world/profile.json"

var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _valley_noise: FastNoiseLite
var _biome_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _bridge_sites_cache: Array[Dictionary] = []
var _engineered_trails_cache: Array[Dictionary] = []
var _river_segment_buckets:Dictionary={}
var _river_junctions:Array[Vector2]=[]
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
    _prepare_engineered_trail_cache(profile)

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
    terrain_instance.material_override = _make_terrain_material()
    # The 28 m gameplay heightfield is deliberately coarse. Let it receive
    # shadows from trees and buildings, but do not let its own huge triangles
    # cast block-shaped mountain shadows across towns and roads.
    terrain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    terrain_root.add_child(terrain_instance)
    var collision_path:=_terrain_mesh_cache_path(profile,"collision")
    var terrain_shape:ConcavePolygonShape3D
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
    terrain_body.add_child(terrain_collision)
    terrain_instance.add_child(terrain_body)
    _profile_generation_step("collision",profile_start_usec)

    # No ocean plane in the controlled aqueduct test world.

    var road_junctions := _collect_road_junctions(profile.get("road_corridors", []))
    return {
        "spawn_position": spawn_position,
        "water_level": water_level,
        "height_sampler": func(x: float, z: float) -> Vector3:
            var sampled_height := _sample_heightfield(x, z, heights, world_size, grid_resolution)
            var bank_height:=_river_bank_surface_height(Vector2(x,z),profile,world_size,grid_resolution)
            if bank_height>-INF:sampled_height=maxf(sampled_height,bank_height)
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
                sampled_height += maxf(_road_surface_offset(point, profile, road_junctions), _trail_surface_offset(point, profile))
            return Vector3(x, sampled_height, z),
        "terrain_height_sampler": func(x: float, z: float) -> Vector3:
            var sampled_height:=_sample_heightfield(x,z,heights,world_size,grid_resolution)
            var bank_height:=_river_bank_surface_height(Vector2(x,z),profile,world_size,grid_resolution)
            if bank_height>-INF:sampled_height=maxf(sampled_height,bank_height)
            return Vector3(x,sampled_height,z),
        # Uncarved authored land is used to reconstruct visible river-bank
        # slopes over the widened hidden channel support. Those slope meshes
        # carry collision, so their visual and walkable surfaces agree.
        "land_surface_sampler": func(x:float,z:float)->Vector3:
            return Vector3(x,_land_surface_without_water(Vector2(x,z),profile),z),
        "structure_height_sampler": func(x: float, z: float, current_y: float) -> float:
            return _castle_structure_height(Vector2(x, z), current_y, profile),
        "river_height_sampler": func(x: float, z: float) -> Vector3:
            var river_grade := _river_grade(x)
            return Vector3(x, river_grade - 2.8, z),
        "walkable_sampler": func(x: float, z: float) -> bool:
            var inside_world := absf(x) < world_size * 0.49 and absf(z) < world_size * 0.49
            var point := Vector2(x, z)
            var inside_channel := false
            for river in profile.get("river_corridors", []):
                # Only the deeper central channel is blocked. The outer bank
                # remains walkable so the hero can approach and wade through
                # the gently submerged shelf without crossing the whole river.
                var channel_limit: float = float(river.get("width", 84.0)) * 0.35
                # Bridge sites are intentional access points. Let the player
                # wade farther into the water beside a bridge while retaining
                # a blocked deep core, so this does not become an accidental
                # walk-across ford.
                for ford in profile.get("ford_sites", []):
                    var ford_center: Vector2 = ford.get("position", Vector2.ZERO)
                    var ford_radius: float = float(ford.get("radius", 62.0))
                    if point.distance_to(ford_center) <= ford_radius * 1.15:
                        channel_limit = float(river.get("width", 84.0)) * 0.24
                        break
                if _distance_to_polyline(point, river.get("points", [])) < channel_limit:
                    inside_channel = true
                    break
            var on_bridge := not _bridge_deck_info(point, profile).is_empty()
            return inside_world and (not inside_channel or on_bridge),
    }


func _profile_generation_step(label:String,start_usec:int)->void:
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")!="1":return
    print("TERRAIN_BUILD_PROFILE|%s|elapsed_ms=%.1f"%[
        label,
        float(Time.get_ticks_usec()-start_usec)/1000.0,
    ])


func _terrain_cache_path(profile:Dictionary)->String:
    var zone_id:=str(profile.get("zone_id","starting_realm")).validate_filename()
    # Decorative landmarks, camps and encounter data do not affect terrain.
    # Keep them out of the signature so an ecology pass does not trigger an
    # expensive heightfield rebuild on the player's next launch.
    var terrain_profile:Dictionary={}
    for key in [
        "world_size","grid_resolution","water_level","controlled_aqueduct",
        "spawn_site","town_sites","mountain_chains","landform_regions",
        "pond_sites","river_corridors","road_corridors","trail_corridors",
        "ford_sites","forest_regions",
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
    var nearby_segments:Array=_river_segment_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),
        []
    )
    for segment_data in nearby_segments:
        var candidate_dist:=_distance_to_segment(point,segment_data.a,segment_data.b)
        if candidate_dist < dist:
            dist = candidate_dist
            width = float(segment_data.width)
    # Defensive fallback for direct unit calls made before generate_world().
    if _river_segment_buckets.is_empty():
        for candidate in corridors:
            var candidate_dist := _distance_to_polyline(point, candidate.get("points", []))
            if candidate_dist < dist:
                dist = candidate_dist
                width = float(candidate.get("width", width))
    _last_sampled_river_distance = dist
    var half_channel := width * 0.5
    # Keep the land-water seam tight: the bank rises immediately outside the
    # flat bed instead of leaving a broad recessed coastal strip.
    var taper_width := 5.0
    # Predictable east-to-west fall. Small undulation preserves a natural bed
    # without creating uphill water or disconnected pools.
    # A gentle world-scale fall keeps the full river close to the surrounding
    # watershed. The previous grade climbed far above low terrain downstream.
    var channel_surface := _river_grade(x)
    var bed := channel_surface - 2.8
    var water_surface := bed + 2.2
    var bank_floor := channel_surface + 0.45
    # Bridge approaches are where the coarse heightfield is most likely to
    # interpolate from a deep center-bed vertex to a bank vertex and expose a
    # vertical water gap. Make the terrain immediately around every crossing a
    # shallow ford beneath the water; the river remains deep away from bridges.
    for support_site in _bridge_sites_cache:
        var support_center: Vector2 = support_site.get("position", Vector2.ZERO)
        var support_distance := Vector2(x, z).distance_to(support_center)
        if support_distance < 132.0:
            var support_weight := 1.0 - _smoothstep(86.0, 132.0, support_distance)
            bed = lerpf(bed, water_surface, support_weight)
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
            surface = maxf(surface, water_surface + 0.55 * guard_weight)
    # Grade only the road approaches beside a bridge. The river channel stays
    # carved and continuous, while both banks meet the crossing at a sensible
    # shared elevation instead of producing a giant ramp on the higher side.
    for bridge_site in _bridge_sites_cache:
        var bridge_center: Vector2 = bridge_site.get("position", Vector2.ZERO)
        var bridge_direction: Vector2 = bridge_site.get("direction", Vector2(0.0, 1.0))
        var approach_width: float = bridge_site.get("approach_width", 12.0)
        var bridge_offset := Vector2(x, z) - bridge_center
        var bridge_along := absf(bridge_offset.dot(bridge_direction))
        var bridge_lateral := absf(bridge_offset.cross(bridge_direction))
        if bridge_lateral <= approach_width and bridge_along >= half_channel * 0.82 and bridge_along <= half_channel + 82.0:
            var approach_weight := 1.0 - _smoothstep(half_channel + 20.0, half_channel + 82.0, bridge_along)
            var approach_height := _river_grade(bridge_center.x) + 0.48
            surface = lerpf(surface, approach_height, approach_weight)
    # The world grid is about 28 units between vertices. A narrow underwater
    # rise can fall entirely between samples, making one large triangle stretch
    # from the deep bed to dry land and leaving a visible trench beside the
    # water. Reserve a broad, flat waterline shelf inside the authored channel
    # so every bank cell has terrain supporting the water edge.
    var grid_step: float = float(profile.get("world_size", 7200.0)) / maxf(1.0, float(profile.get("grid_resolution", 256)))
    var edge_guard := minf(half_channel * 0.70, grid_step * 0.88)
    var flat_bed_edge := half_channel - edge_guard
    # The rendered ribbon is 84% of the authored channel. Keep the hidden
    # support only beneath that water and the compact authored bank. The old
    # grid-diagonal expansion continued forty metres beyond the shoreline and
    # exposed a flat green shelf that appeared to climb surrounding hills.
    var visible_water_half:=half_channel*.84
    # A water-edge sample can sit in a terrain triangle whose far vertex is a
    # full grid diagonal away. Lower that complete support envelope so steep
    # hills cannot interpolate through the visible water. WorldPreviewBuilder
    # reconstructs the natural turf bank over this hidden support.
    var mesh_support_half:=visible_water_half+grid_step*1.65
    var waterline_shelf_start := minf(flat_bed_edge + edge_guard * 0.45, visible_water_half * 0.88)
    if dist <= flat_bed_edge:
        return bed
    if dist <= waterline_shelf_start:
        var submerged_t := _smoothstep(flat_bed_edge, waterline_shelf_start, dist)
        return lerpf(bed, water_surface, submerged_t)
    if dist <= mesh_support_half:
        return water_surface
    if dist < mesh_support_half + taper_width:
        var taper := _smoothstep(mesh_support_half, mesh_support_half + taper_width, dist)
        # Continue upward from the waterline. Restarting this strip at `bed`
        # opened a low seam immediately outside the river mesh.
        return lerpf(water_surface, maxf(surface, bank_floor), taper)
    if dist < mesh_support_half + taper_width + 72.0:
        var bank_blend := 1.0 - _smoothstep(mesh_support_half + taper_width, mesh_support_half + taper_width + 72.0, dist)
        surface = maxf(surface, lerpf(surface, bank_floor, bank_blend))
    for pond in profile.get("pond_sites", []):
        var pond_center: Vector2 = pond.get("position", Vector2.ZERO)
        var authored_radius: float = pond.get("radius", 70.0)
        var pond_water: float = pond.get("water_height", 1.2)
        var pond_offset := Vector2(x, z) - pond_center
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
    return _apply_engineered_trail_surface(point,surface)


func _land_surface_without_water(point:Vector2,profile:Dictionary)->float:
    var surface:=_natural_world_surface(point,profile)+_cave_cliff_raise(point)
    # Settlements are authored spaces, not buildings dropped onto random
    # noise. Their inner districts are level, with a broad transition back to
    # the surrounding terrain so roads and city walls meet usable ground.
    for town in profile.get("town_sites", []):
        var town_center: Vector2 = town.get("position", Vector2.ZERO)
        var town_radius: float = float(town.get("radius", 120.0))
        var town_outer := town_radius * 1.30
        var town_offset := point - town_center
        if town_offset.length_squared() < town_outer * town_outer:
            var town_distance := town_offset.length()
            var town_height: float = float(town.get("ground_height", 7.0))
            var town_weight := 1.0 - _smoothstep(town_radius * 0.78, town_outer, town_distance)
            surface = lerpf(surface, town_height, town_weight)
    return _cave_access_surface(point,surface,profile)


func _prepare_engineered_trail_cache(profile:Dictionary)->void:
    _engineered_trails_cache.clear()
    var grid_step:float=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",256)))
    for corridor in profile.get("trail_corridors",[]):
        if not corridor.get("engineered_grade",false):continue
        var points:Array=corridor.get("points",[])
        if points.size()<2:continue
        var cumulative:Array[float]=[0.0]
        for i in range(points.size()-1):cumulative.append(cumulative[-1]+Vector2(points[i]).distance_to(Vector2(points[i+1])))
        var start:Vector2=points[0];var finish:Vector2=points[-1]
        _engineered_trails_cache.append({
            "points":points,
            "cumulative":cumulative,
            "length":maxf(1.0,cumulative[-1]),
            "start_y":_land_surface_without_water(start,profile),
            "end_y":_land_surface_without_water(finish,profile),
            # Grade only the tread and a compact shoulder. The previous
            # grid-step multiplier flattened bands nearly eighty metres wide.
            "inner":grid_step*.72+float(corridor.get("width",7.0))*.5,
            "outer":grid_step*.72+float(corridor.get("width",7.0))*.5+26.0,
        })


func _prepare_river_segment_cache(profile:Dictionary)->void:
    _river_segment_buckets.clear()
    _river_junctions.clear()
    var grid_step:=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",256)))
    for corridor in profile.get("river_corridors",[]):
        var points:Array=corridor.get("points",[])
        var width:=float(corridor.get("width",84.0))
        # River terrain changes end within roughly 72 m of the support shelf.
        # A generous 220 m segment envelope also covers guarded bridge banks.
        var influence:=maxf(220.0,width*.5+grid_step*1.45+84.0)
        for index in range(points.size()-1):
            var a:Vector2=points[index]
            var b:Vector2=points[index+1]
            var min_bucket:=Vector2i(
                floori((minf(a.x,b.x)-influence)/RIVER_BUCKET_SIZE),
                floori((minf(a.y,b.y)-influence)/RIVER_BUCKET_SIZE)
            )
            var max_bucket:=Vector2i(
                floori((maxf(a.x,b.x)+influence)/RIVER_BUCKET_SIZE),
                floori((maxf(a.y,b.y)+influence)/RIVER_BUCKET_SIZE)
            )
            var segment_data:={"a":a,"b":b,"width":width}
            for bucket_x in range(min_bucket.x,max_bucket.x+1):
                for bucket_y in range(min_bucket.y,max_bucket.y+1):
                    var key:=Vector2i(bucket_x,bucket_y)
                    if not _river_segment_buckets.has(key):_river_segment_buckets[key]=[]
                    _river_segment_buckets[key].append(segment_data)
    var rivers:Array=profile.get("river_corridors",[])
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


func _river_bank_surface_height(point:Vector2,profile:Dictionary,world_size:float,grid_resolution:int)->float:
    if _river_segment_buckets.is_empty():return -INF
    for junction in _river_junctions:
        if point.distance_squared_to(junction)<110.0*110.0:return -INF
    var nearby_segments:Array=_river_segment_buckets.get(
        Vector2i(floori(point.x/RIVER_BUCKET_SIZE),floori(point.y/RIVER_BUCKET_SIZE)),[]
    )
    var best_distance:=INF
    var best_segment:Dictionary={}
    var best_projection:=Vector2.ZERO
    for segment in nearby_segments:
        var a:Vector2=segment.a;var b:Vector2=segment.b;var delta:=b-a
        var t:=clampf((point-a).dot(delta)/maxf(.001,delta.length_squared()),0.0,1.0)
        var projection:=a+delta*t
        var distance:=point.distance_to(projection)
        if distance<best_distance:
            best_distance=distance;best_segment=segment;best_projection=projection
    if best_segment.is_empty():return -INF
    var width:float=float(best_segment.width)
    var half_water:=width*.84*.5
    var mesh_inner_distance:=half_water+.12
    # Averaged curve normals produce a small miter at bends. Begin the sampled
    # walkable bank beyond that miter so it can never lift terrain through the
    # last row of water vertices. The visual strip between these distances is
    # a shallow submerged shelf.
    var inner_distance:=half_water+1.5
    var shore_distance:=half_water+8.0
    var grid_step:=world_size/maxf(1.0,float(grid_resolution))
    var outer_distance:=half_water+grid_step*1.65+10.0
    if best_distance<inner_distance or best_distance>outer_distance:return -INF
    var delta:Vector2=best_segment.b-best_segment.a
    if delta.length_squared()<.001:return -INF
    var tangent:=delta.normalized()
    var normal:=Vector2(-tangent.y,tangent.x)
    if (point-best_projection).dot(normal)<0.0:normal=-normal
    var outer_point:=best_projection+normal*outer_distance
    var water_y:=_river_grade(best_projection.x)-.45
    var inner_y:=water_y-.08
    var shore_y:=water_y+.14
    if best_distance<=shore_distance:
        return lerpf(inner_y,shore_y,_smoothstep(mesh_inner_distance,shore_distance,best_distance))
    var natural_outer:=_land_surface_without_water(outer_point,profile)+.06
    var max_bank_rise:=maxf(2.0,(outer_distance-shore_distance)*.48)
    var outer_y:=clampf(natural_outer,shore_y+.06,shore_y+max_bank_rise)
    return lerpf(shore_y,outer_y,_smoothstep(shore_distance,outer_distance,best_distance))


func _apply_engineered_trail_surface(point:Vector2,surface:float)->float:
    for trail in _engineered_trails_cache:
        var points:Array=trail.points;var cumulative:Array=trail.cumulative
        var best_distance:=INF;var best_along:=0.0
        for i in range(points.size()-1):
            var a:Vector2=points[i];var b:Vector2=points[i+1];var segment:=b-a
            var t:=clampf((point-a).dot(segment)/maxf(.001,segment.length_squared()),0.0,1.0)
            var distance:=point.distance_to(a+segment*t)
            if distance<best_distance:best_distance=distance;best_along=float(cumulative[i])+segment.length()*t
        var outer:float=trail.outer
        if best_distance>=outer:continue
        var target:=lerpf(float(trail.start_y),float(trail.end_y),clampf(best_along/float(trail.length),0.0,1.0))
        var weight:=1.0-_smoothstep(float(trail.inner),outer,best_distance)
        surface=lerpf(surface,target,weight)
    return surface


func _natural_world_surface(point:Vector2,profile:Dictionary)->float:
    var surface:=3.0
    surface+=_base_noise.get_noise_2d(point.x*.34,point.y*.34)*9.0
    surface+=_ridge_noise.get_noise_2d(point.x*.22-70.0,point.y*.22+45.0)*4.0
    surface+=_detail_noise.get_noise_2d(point.x*.52+90.0,point.y*.52-40.0)*1.8
    surface+=sin(point.x*.0042)*2.8
    surface+=sin(point.y*.0048+.7)*2.2
    for region in profile.get("landform_regions",[]):surface+=_authored_landform_height(point,region)
    for chain in profile.get("mountain_chains",[]):surface+=_mountain_chain_height(point,chain)
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
            var deck_height := _river_grade(center.x) + 0.62
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
        best_offset = maxf(best_offset, lerpf(0.14, 0.08, across))

    # The preview builder caps shared road nodes with a small junction disk.
    # Include those caps in the movement surface as well.
    for junction in road_junctions:
        if point.distance_to(junction) <= 7.5:
            return maxf(best_offset, 0.14)
    return best_offset


func _trail_surface_offset(point: Vector2, profile: Dictionary) -> float:
    for trail in profile.get("trail_corridors", []):
        var visual_width := maxf(2.4, float(trail.get("width", 5.0)) * 0.48)
        var distance := _distance_to_polyline(point, trail.get("points", []))
        if distance <= visual_width * 0.5:
            var across := clampf(distance / (visual_width * 0.5), 0.0, 1.0)
            return lerpf(0.14, 0.08, across)
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
            var distance := point.distance_to(a + segment * t)
            if distance < best_distance:
                best_distance = distance
                best = {
                    "distance": distance,
                    "direction": segment.normalized(),
                    "width": float(road.get("width", 14.0)),
                }
    return best


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
        if river_distance <= river_width * 0.5:
            return Color(0.20, 0.16, 0.095, 1.0).lerp(Color(0.30, 0.25, 0.16, 1.0), detail_noise)
        if river_distance <= river_width * 0.5 + 6.0:
            return Color(0.28, 0.25, 0.16, 1.0).lerp(Color(0.40, 0.36, 0.22, 1.0), broad_bands)
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
        return biome
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


func _make_terrain_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D soil_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;

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
    // Four shared fields replace thirteen near-duplicate value-noise calls.
    // Their rotated inputs retain irregular boundaries without making the
    // full-screen terrain shader the dominant cost while moving.
    float broad = value_noise(p * 0.014);
    float clumps = value_noise(vec2(p.x * 0.052 + p.y * 0.019, -p.x * 0.019 + p.y * 0.052) + vec2(19.0, 7.0));
    float grit = value_noise(p * 0.24 + vec2(3.0, 31.0));
    float macro_field = value_noise(vec2(p.x * 0.0038 + p.y * 0.0014, -p.x * 0.0014 + p.y * 0.0038) + vec2(37.0, 19.0));
    vec3 base = COLOR.rgb;
    vec3 dark_soil = vec3(0.105, 0.075, 0.038);
    vec3 dry_grass = vec3(0.24, 0.25, 0.13);
    vec3 moss = vec3(0.055, 0.14, 0.07);
    vec3 meadow = vec3(0.13, 0.25, 0.11);
    vec3 stone = vec3(0.225, 0.23, 0.22);
    vec3 color = base * mix(0.86, 1.08, broad);
    color = mix(color, moss, smoothstep(0.72, 0.94, clumps) * 0.22);
    color = mix(color, dry_grass, smoothstep(0.86, 0.98, broad) * 0.10);
    color = mix(color, dark_soil, smoothstep(0.88, 0.985, grit) * 0.15);
    color *= mix(0.95, 1.035, grit);
    // Keep individual blades and pebbles near human scale. The generated
    // source contains larger photographic structures than the previous map.
    vec2 terrain_uv = p * 0.085;
    vec2 terrain_uv_rot = vec2(p.x * 0.057 + p.y * 0.063, -p.x * 0.063 + p.y * 0.057) + vec2(7.31, 2.17);
    float tile_blend = smoothstep(0.22, 0.78, clumps);
    vec3 grass_albedo = mix(texture(grass_texture, terrain_uv).rgb, texture(grass_texture, terrain_uv_rot).rgb, tile_blend);
    // Do not magnify the source photograph for macro variation. That exposed
    // its rectangular image border as huge square biome tiles. Procedural,
    // overlapping noise fields provide broad variation without any seam.
    grass_albedo *= mix(0.88, 1.10, smoothstep(0.12, 0.88, macro_field));
    grass_albedo *= vec3(1.04, 1.00, 0.91);
    float grass_luma = dot(grass_albedo, vec3(0.2126, 0.7152, 0.0722));
    grass_albedo = mix(vec3(grass_luma), grass_albedo, 0.94);
    vec3 soil_albedo = texture(soil_texture, terrain_uv * 0.82 + vec2(0.17, 0.31)).rgb * vec3(0.88, 0.93, 1.02);
    vec3 stone_albedo = texture(stone_texture, terrain_uv * 0.68 + vec2(0.43, 0.11)).rgb;
    // Soil speckles come from fine noise only. Thresholding interpolated
    // biome colour switched an entire coarse triangle to a different texture.
    float soil_marker = clamp(smoothstep(0.74, 0.95, grit) * 0.36 + smoothstep(0.78, 0.96, broad) * 0.18, 0.0, 0.48);
    float slope = 1.0 - smoothstep(0.48, 0.86, abs(NORMAL.y));
    float highland = smoothstep(28.0, 88.0, world_position.y);
    float stone_weight = clamp(max(slope * 0.62, highland), 0.0, 0.82);
    vec3 textured_ground = mix(grass_albedo, soil_albedo, soil_marker * 0.72);
    float dry_patch = smoothstep(0.56, 0.82, macro_field * 0.64 + broad * 0.36);
    textured_ground = mix(textured_ground, vec3(0.31, 0.265, 0.125), dry_patch * (1.0 - stone_weight) * 0.43);
    float meadow_patch = smoothstep(0.61, 0.87, clumps * 0.62 + (1.0 - macro_field) * 0.38);
    textured_ground = mix(textured_ground, vec3(0.13, 0.235, 0.095), meadow_patch * (1.0 - dry_patch) * (1.0 - stone_weight) * 0.24);
    textured_ground = mix(textured_ground, stone_albedo, stone_weight);
    // Preserve enough authored vertex colour for Westmere heath, Northwood
    // moss and Southbank ochre to remain distinct beneath the shared detail.
    color = mix(color, textured_ground, 0.52);
    // Strong, overlapping earth and meadow fields stay visible at walking
    // distance. Rotated coordinates prevent these patches reading as a grid.
    color = mix(color, vec3(0.33, 0.27, 0.12), smoothstep(0.58, 0.80, broad) * (1.0 - stone_weight) * 0.40);
    color = mix(color, vec3(0.14, 0.29, 0.10), smoothstep(0.66, 0.88, clumps) * (1.0 - dry_patch) * (1.0 - stone_weight) * 0.20);
    color = mix(color, color * vec3(0.82, 0.73, 0.56), (1.0 - smoothstep(0.22, 0.48, macro_field)) * (1.0 - stone_weight) * 0.23);
    color = mix(color, color * vec3(0.92, 1.04, 0.82), smoothstep(0.61, 0.86, macro_field) * (1.0 - stone_weight) * 0.12);
    // World-scale biome colour is already authored per vertex with warped
    // borders. Avoid large thresholded value-noise patches here: those reveal
    // the noise lattice as square or triangular fields from a distance.
    float final_luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(final_luma), color, 0.88);
    color *= vec3(0.98, 0.94, 0.87);
    ALBEDO = color;
    ROUGHNESS = 0.96;
    SPECULAR = 0.08;
}
"""
    material.shader = shader
    material.set_shader_parameter("grass_texture", load("res://assets/terrain/meadow_soil_realistic_v3.png"))
    material.set_shader_parameter("soil_texture", load("res://assets/terrain/woodland_soil_v1.png"))
    material.set_shader_parameter("stone_texture", load("res://assets/terrain/highland_stone_v1.png"))
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
