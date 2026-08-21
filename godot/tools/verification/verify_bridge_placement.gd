extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var rivers:Array=profile.get("river_corridors",[])
    var routes:Array=[]
    routes.append_array(profile.get("road_corridors",[]))
    routes.append_array(profile.get("trail_corridors",[]))
    var builder:=TerrainBuilder.new()
    builder.call("_prepare_bridge_cache",profile)
    builder.call("_prepare_river_segment_cache",profile)
    builder.call("_prepare_engineered_route_cache",profile)
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=builder.generate_world(terrain_root,profile)
    var walkable:Callable=terrain.get("walkable_sampler",Callable())
    var height_sampler:Callable=terrain.get("height_sampler",Callable())
    var bridge_cache:Array=builder.get("_bridge_sites_cache")
    if bridge_cache.size()!=profile.get("ford_sites",[]).size():
        failures.append("one or more authored bridge sites could not resolve onto a river")

    var worst_route_gap:=0.0
    var worst_crossing_dot:=0.0
    var worst_grade:=0.0
    var worst_deck_step:=0.0
    for site_value in bridge_cache:
        var site:Dictionary=site_value
        var bridge_name:=str(site.get("name","Bridge"))
        var center:Vector2=site.get("position",Vector2.ZERO)
        if str(site.get("purpose","")).is_empty():failures.append("%s has no travel purpose"%bridge_name)
        var river_info:Dictionary=builder.call("_nearest_road_segment",center,rivers)
        var river_miss:=float(river_info.get("distance",INF))
        var river_width:=float(river_info.get("width",52.0))
        var direction:Vector2=site.get("direction",Vector2.ZERO)
        var river_direction:Vector2=river_info.get("direction",Vector2.RIGHT)
        var crossing_dot:=absf(direction.normalized().dot(river_direction.normalized()))
        worst_crossing_dot=maxf(worst_crossing_dot,crossing_dot)
        if river_miss>5.0:failures.append("%s misses its river centerline by %.1fm"%[bridge_name,river_miss])
        if crossing_dot>.34:failures.append("%s crosses at an awkward angle"%bridge_name)
        var road_width:=float(site.get("road_width",site.get("bridge_width",10.0)))
        var span:=maxf(river_width+10.0,road_width*2.15)
        var landing_offset:=span*.5+8.0
        for side in [-1.0,1.0]:
            var deck_end:=center+direction*span*.5*float(side)
            var deck_end_river:Dictionary=builder.call("_nearest_road_segment",deck_end,rivers)
            var visible_half:=float(deck_end_river.get("width",river_width))*.42
            if float(deck_end_river.get("distance",0.0))<visible_half-1.5:
                failures.append("%s does not fully span visible water on side %.0f"%[bridge_name,float(side)])
        var previous_deck_y:=0.0
        for sample_index in range(13):
            var sample_progress:=float(sample_index)/12.0
            var sample_point:=center+direction*lerpf(-landing_offset,landing_offset,sample_progress)
            if walkable.is_valid() and not walkable.call(sample_point.x,sample_point.y):
                failures.append("%s has a blocked traversal sample"%bridge_name);break
            if height_sampler.is_valid():
                var sample_y:float=(height_sampler.call(sample_point.x,sample_point.y) as Vector3).y
                if sample_index>0:worst_deck_step=maxf(worst_deck_step,absf(sample_y-previous_deck_y))
                previous_deck_y=sample_y
        var route_gaps:Array[float]=[]
        var landing_points:Array[Vector2]=[]
        for side in [-1.0,1.0]:
            var landing:=center+direction*landing_offset*float(side)
            landing_points.append(landing)
            var route_gap:=_distance_to_corridors(landing,routes)
            route_gaps.append(route_gap)
            worst_route_gap=maxf(worst_route_gap,route_gap)
            if route_gap>18.0:failures.append("%s has no route at landing %.0f (gap %.1fm)"%[bridge_name,float(side),route_gap])
            if walkable.is_valid() and not walkable.call(landing.x,landing.y):failures.append("%s landing %.0f is not walkable"%[bridge_name,float(side)])
            var outward:=center+direction*(landing_offset+28.0)*float(side)
            if height_sampler.is_valid():
                var landing_y:float=(height_sampler.call(landing.x,landing.y) as Vector3).y
                var outward_y:float=(height_sampler.call(outward.x,outward.y) as Vector3).y
                var grade:=absf(outward_y-landing_y)/28.0
                worst_grade=maxf(worst_grade,grade)
                if grade>.34:failures.append("%s landing %.0f exceeds a 34%% approach grade"%[bridge_name,float(side)])
        for pond in profile.get("pond_sites",[]):
            var pond_center:Vector2=pond.get("position",Vector2.ZERO)
            if center.distance_to(pond_center)<float(pond.get("radius",70.0))*1.18:
                failures.append("%s sits inside %s"%[bridge_name,str(pond.get("name","open water"))])
        print("BRIDGE_PLACEMENT|%s|river=%s|miss=%.2f|span=%.1f|dir=%.3f,%.3f|landings=%.1f,%.1f;%.1f,%.1f|cross_dot=%.3f|routes=%.1f,%.1f|purpose=%s"%[
            bridge_name,str(river_info.get("name","river")),river_miss,span,
            direction.x,direction.y,
            landing_points[0].x,landing_points[0].y,landing_points[1].x,landing_points[1].y,
            crossing_dot,route_gaps[0],route_gaps[1],str(site.get("purpose","missing")),
        ])

    for first_index in range(bridge_cache.size()):
        for second_index in range(first_index+1,bridge_cache.size()):
            var first:Vector2=bridge_cache[first_index].get("position",Vector2.ZERO)
            var second:Vector2=bridge_cache[second_index].get("position",Vector2.ZERO)
            if first.distance_to(second)<300.0:failures.append("two bridge sites are needlessly duplicated within 300m")

    var bridge_root:=Node3D.new();root.add_child(bridge_root)
    WorldPreviewBuilder.new().call("_build_bridges",bridge_root,profile,terrain)
    if bridge_root.get_child_count()!=bridge_cache.size():failures.append("rendered bridge count does not match authored crossings")
    print("BRIDGE_NETWORK|bridges=%d|rendered=%d|worst_route_gap=%.2f|worst_cross_dot=%.3f|worst_grade=%.3f|worst_deck_step=%.3f|failures=%d"%[
        bridge_cache.size(),bridge_root.get_child_count(),worst_route_gap,worst_crossing_dot,worst_grade,worst_deck_step,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _distance_to_corridors(point:Vector2,corridors:Array)->float:
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best
