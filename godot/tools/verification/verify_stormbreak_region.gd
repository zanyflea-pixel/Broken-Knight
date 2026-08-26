extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var start:Dictionary=profiles.make_zone_profile("starting_realm")
    var north:Dictionary=profiles.make_zone_profile("north_frontier")
    var western:Dictionary=profiles.make_zone_profile("western_reaches")
    var glacial:Dictionary=profiles.make_zone_profile("glacial_range")
    var storm:Dictionary=profiles.make_zone_profile("stormbreak_highlands")
    if str(storm.get("biome_id",""))!="windswept_highlands":failures.append("Stormbreak biome identity is missing")
    if int(storm.get("danger_tier",0))!=3:failures.append("Stormbreak does not provide the intended tier-three progression")
    if storm.get("town_sites",[]).size()!=2:failures.append("Stormbreak needs exactly two supporting towns around its hold")
    if storm.get("road_corridors",[]).size()!=4:failures.append("Stormbreak road hierarchy is incomplete")
    if storm.get("river_corridors",[]).size()!=1:failures.append("Stormbreak should expose one coherent headwater river")
    if storm.get("ford_sites",[]).size()!=1:failures.append("Stormbreak should expose one necessary main-road crossing")

    var north_root:=Node3D.new();root.add_child(north_root)
    var west_root:=Node3D.new();root.add_child(west_root)
    var storm_root:=Node3D.new();root.add_child(storm_root)
    var north_result:Dictionary=TerrainBuilder.new().generate_world(north_root,north)
    var west_result:Dictionary=TerrainBuilder.new().generate_world(west_root,western)
    var storm_result:Dictionary=TerrainBuilder.new().generate_world(storm_root,storm)
    var half_size:=float(storm.get("world_size",7200.0))*.5
    var south_gap:=0.0
    var east_gap:=0.0
    var south_gap_at:=0.0
    var south_gap_heights:=Vector2.ZERO
    for sample_index in range(129):
        var along:=lerpf(-half_size,half_size,float(sample_index)/128.0)
        var storm_south_height:float=storm_result.terrain_height_sampler.call(along,half_size).y
        var west_north_height:float=west_result.terrain_height_sampler.call(along,-half_size).y
        var sample_south_gap:=absf(storm_south_height-west_north_height)
        if sample_south_gap>south_gap:
            south_gap=sample_south_gap
            south_gap_at=along
            south_gap_heights=Vector2(storm_south_height,west_north_height)
        east_gap=maxf(east_gap,absf(
            storm_result.terrain_height_sampler.call(half_size,along).y-
            north_result.terrain_height_sampler.call(-half_size,along).y
        ))
    if south_gap>.02:failures.append("Stormbreak/Western terrain seam has a %.4fm crack"%south_gap)
    if east_gap>.02:failures.append("Stormbreak/Greyfen terrain seam has a %.4fm crack"%east_gap)

    var storm_river:Dictionary=storm.river_corridors[0]
    var west_river:Dictionary=western.river_corridors[0]
    var storm_offset:Vector2=storm.get("region_origin",Vector2.ZERO)
    var west_offset:Vector2=western.get("region_origin",Vector2.ZERO)
    var north_offset:Vector2=north.get("region_origin",Vector2.ZERO)
    var river_gap:=(Vector2(storm_river.points[-1])+storm_offset).distance_to(Vector2(west_river.points[0])+west_offset)
    if river_gap>.01:failures.append("Galehorn Run and Rainfall River have a %.2fm boundary gap"%river_gap)
    if float(storm_river.get("source_height",0.0))<=float(storm_river.get("mouth_height",0.0)):
        failures.append("Galehorn Run does not descend from Blacktarn")
    var water_lift:float=float(storm.get("river_water_lift",1.35))
    var floating_depth:=0.0
    var buried_depth:=0.0
    for sample_index in range(1,storm_river.points.size()-1,9):
        var point:Vector2=storm_river.points[sample_index]
        var water_top:float=storm_result.river_height_sampler.call(point.x,point.y).y+water_lift
        var terrain_y:float=storm_result.terrain_height_sampler.call(point.x,point.y).y
        floating_depth=maxf(floating_depth,water_top-terrain_y)
        buried_depth=maxf(buried_depth,terrain_y-water_top)
    if floating_depth>3.2:failures.append("Galehorn water floats %.2fm above its bed"%floating_depth)
    if buried_depth>.08:failures.append("Galehorn terrain protrudes %.2fm through its water"%buried_depth)

    var south_road:Dictionary=storm.road_corridors[0]
    var west_watchroad:Dictionary={}
    for road in western.road_corridors:
        if str(road.get("name",""))=="Galehorn Watchroad":west_watchroad=road;break
    var south_road_gap:=INF
    if not west_watchroad.is_empty():south_road_gap=(Vector2(south_road.points[0])+storm_offset).distance_to(Vector2(west_watchroad.points[-1])+west_offset)
    if south_road_gap>.01:failures.append("Galehorn high road has a %.2fm boundary gap"%south_road_gap)
    var east_road:Dictionary=storm.road_corridors[1]
    var north_highland_road:Dictionary={}
    for road in north.road_corridors:
        if str(road.get("name",""))=="Greyfen Highland Road":north_highland_road=road;break
    var east_road_gap:=INF
    if not north_highland_road.is_empty():east_road_gap=(Vector2(east_road.points[-1])+storm_offset).distance_to(Vector2(north_highland_road.points[-1])+north_offset)
    if east_road_gap>.01:failures.append("Greyfen high road has a %.2fm boundary gap"%east_road_gap)

    var bridge_point:Vector2=storm.ford_sites[0].position
    var bridge_road:=_nearest_corridor(bridge_point,storm.road_corridors)
    var bridge_river:=_nearest_corridor(bridge_point,storm.river_corridors)
    if float(bridge_road.get("distance",INF))>.25 or float(bridge_river.get("distance",INF))>.25:
        failures.append("Galehorn Crossing is not centered on road and river")
    elif absf(Vector2(bridge_road.direction).dot(Vector2(bridge_river.direction)))>.38:
        failures.append("Galehorn Crossing meets the river at an unsafe shallow angle")

    var atlas:=profiles.make_world_atlas([
        profiles.offset_profile(start,start.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(north,north.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(glacial,glacial.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(western,western.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(storm,storm.get("region_origin",Vector2.ZERO)),
    ])
    var summaries:Array=atlas.get("region_summaries",[])
    var region_ids:Array=[]
    for summary in summaries:region_ids.append(str(summary.get("zone_id","")))
    if "stormbreak_highlands" not in region_ids:failures.append("Stormbreak is absent from the atlas")
    if Vector2(atlas.get("map_extent",Vector2.ZERO)).distance_to(Vector2(14400,21600))>.1:
        failures.append("Five-region atlas footprint is incorrect")

    var kit:=load("res://assets/world/stormbreak_environment_kit_v1.glb") as PackedScene
    if kit==null:failures.append("Stormbreak Blender environment kit failed to import")
    else:
        var instance:=kit.instantiate()
        for mesh_name in ["StormbreakBeacon","StormbreakShelter","ShatteredChoir"]:
            if instance.find_child(mesh_name,true,false)==null:failures.append("Stormbreak kit is missing %s"%mesh_name)
        instance.free()

    print("STORMBREAK_REGION|south_gap=%.5f@%.1f(%.2f/%.2f)|east_gap=%.5f|river_gap=%.3f|roads=%.3f/%.3f|water_float=%.2f|atlas_regions=%d|failures=%d"%[
        south_gap,south_gap_at,south_gap_heights.x,south_gap_heights.y,east_gap,river_gap,south_road_gap,east_road_gap,floating_depth,summaries.size(),failures.size(),
    ])
    for failure in failures:push_error("STORMBREAK_REGION_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _nearest_corridor(point:Vector2,corridors:Array)->Dictionary:
    var result:Dictionary={}
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            var a:Vector2=points[index]
            var b:Vector2=points[index+1]
            var segment:=b-a
            if segment.length_squared()<.0001:continue
            var closest:=Geometry2D.get_closest_point_to_segment(point,a,b)
            var distance:=point.distance_to(closest)
            if distance<best:
                best=distance
                result={"distance":distance,"direction":segment.normalized(),"closest":closest}
    return result
