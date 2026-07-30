extends SceneTree


func _init()->void:call_deferred("_run")


func _run()->void:
    var profile:Dictionary=(load("res://scripts/world/WorldProfile.gd") as Script).new().make_zone_profile("starting_realm")
    var crossings:=0
    var unbridged:=0
    for road in profile.get("road_corridors",[]):
        var road_points:Array=road.get("points",[])
        for river in profile.get("river_corridors",[]):
            var river_points:Array=river.get("points",[])
            for ri in range(road_points.size()-1):
                for wi in range(river_points.size()-1):
                    var point:Variant=_intersection(road_points[ri],road_points[ri+1],river_points[wi],river_points[wi+1])
                    if point==null:continue
                    crossings+=1
                    var nearest:=INF
                    var bridge_name:=""
                    for ford in profile.get("ford_sites",[]):
                        var distance:float=Vector2(point).distance_to(ford.get("position",Vector2.ZERO))
                        if distance<nearest:nearest=distance;bridge_name=str(ford.get("name","Bridge"))
                    var covered:=nearest<95.0
                    if not covered:unbridged+=1
                    print("ROAD_WATER_CROSSING|road=%s|river=%s|point=(%.1f,%.1f)|bridge=%s|distance=%.1f|covered=%s"%[road.get("name","Road"),river.get("name","River"),Vector2(point).x,Vector2(point).y,bridge_name,nearest,covered])
            var nearest_clearance:=INF
            for ri in range(road_points.size()-1):
                for wi in range(river_points.size()-1):
                    nearest_clearance=minf(nearest_clearance,_segment_distance(road_points[ri],road_points[ri+1],river_points[wi],river_points[wi+1]))
            print("ROAD_WATER_CLEARANCE|road=%s|river=%s|centerline_distance=%.1f|required=%.1f"%[road.get("name","Road"),river.get("name","River"),nearest_clearance,float(road.get("width",16.0))*.5+float(river.get("width",48.0))*.33])
    print("ROAD_WATER_SUMMARY|crossings=%d|unbridged=%d"%[crossings,unbridged])
    quit(1 if unbridged>0 else 0)


func _intersection(a1:Vector2,a2:Vector2,b1:Vector2,b2:Vector2)->Variant:
    var r:=a2-a1
    var s:=b2-b1
    var denominator:=r.cross(s)
    if absf(denominator)<.0001:return null
    var delta:=b1-a1
    var t:=delta.cross(s)/denominator
    var u:=delta.cross(r)/denominator
    if t<0.0 or t>1.0 or u<0.0 or u>1.0:return null
    return a1+r*t


func _segment_distance(a1:Vector2,a2:Vector2,b1:Vector2,b2:Vector2)->float:
    if _intersection(a1,a2,b1,b2)!=null:return 0.0
    return minf(minf(_point_segment(a1,b1,b2),_point_segment(a2,b1,b2)),minf(_point_segment(b1,a1,a2),_point_segment(b2,a1,a2)))


func _point_segment(point:Vector2,a:Vector2,b:Vector2)->float:
    var delta:=b-a
    if delta.length_squared()<.0001:return point.distance_to(a)
    return point.distance_to(a+delta*clampf((point-a).dot(delta)/delta.length_squared(),0.0,1.0))
