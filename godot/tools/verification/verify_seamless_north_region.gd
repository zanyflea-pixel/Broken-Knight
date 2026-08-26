extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var starting:Dictionary=profiles.make_zone_profile("starting_realm")
    var north:Dictionary=profiles.make_zone_profile("north_frontier")
    var starting_root:=Node3D.new();root.add_child(starting_root)
    var north_root:=Node3D.new();root.add_child(north_root)
    var starting_result:Dictionary=TerrainBuilder.new().generate_world(starting_root,starting)
    var north_result:Dictionary=TerrainBuilder.new().generate_world(north_root,north)
    var half_size:=float(starting.get("world_size",7200.0))*.5
    var maximum_gap:=0.0
    var maximum_gap_x:=0.0
    for sample_index in range(65):
        var x:=lerpf(-half_size,half_size,float(sample_index)/64.0)
        var starting_y:float=starting_result.terrain_height_sampler.call(x,-half_size).y
        var north_y:float=north_result.terrain_height_sampler.call(x,half_size).y
        var gap:=absf(starting_y-north_y)
        if gap>maximum_gap:maximum_gap=gap;maximum_gap_x=x
    if maximum_gap>.015:failures.append("terrain boundary has a %.3fm vertical crack"%maximum_gap)

    var starting_road:Array=starting.road_corridors[-1].points
    var north_road:Array=north.road_corridors[0].points
    var north_offset:Vector2=north.get("region_origin",Vector2.ZERO)
    var road_gap:float=Vector2(starting_road[-1]).distance_to(Vector2(north_road[0])+north_offset)
    if road_gap>.01:failures.append("north road does not meet the starter road (%.2fm gap)"%road_gap)
    var starting_river:Array=starting.river_corridors[-1].points
    var north_river:Array=north.river_corridors[0].points
    var river_gap:float=Vector2(starting_river[0]).distance_to(Vector2(north_river[-1])+north_offset)
    if river_gap>.01:failures.append("headwater does not meet the starter river (%.2fm gap)"%river_gap)
    if north.get("ford_sites",[]).is_empty():
        failures.append("the frontier road/river crossing has no bridge")
    else:
        var bridge_point:Vector2=north.ford_sites[0].position
        var bridge_road_gap:=_corridor_distance(bridge_point,north.road_corridors)
        var bridge_river_gap:=_corridor_distance(bridge_point,north.river_corridors)
        if bridge_road_gap>12.0 or bridge_river_gap>12.0:
            failures.append("frontier bridge is not aligned to both road and river (road %.1f, river %.1f)"%[bridge_road_gap,bridge_river_gap])

    var global_start:=profiles.offset_profile(starting,Vector2.ZERO)
    var global_north:=profiles.offset_profile(north,north_offset)
    var atlas:=profiles.make_world_atlas([global_start,global_north])
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(7200,14400))>.1:failures.append("atlas extent is not 7200 x 14400")
    if center.distance_to(Vector2(0,-3600))>.1:failures.append("atlas is not centred over both regions")
    if not bool(starting.zone_exits[0].get("seamless",false)):failures.append("starter north exit is still a hard portal")
    if not bool(north.zone_exits[0].get("seamless",false)):failures.append("north return exit is still a hard portal")

    print("SEAMLESS_NORTH|edge_gap=%.4f|edge_x=%.1f|road_gap=%.3f|river_gap=%.3f|atlas=%sx%s|failures=%d"%[
        maximum_gap,maximum_gap_x,road_gap,river_gap,roundi(extent.x),roundi(extent.y),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _corridor_distance(point:Vector2,corridors:Array)->float:
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best

