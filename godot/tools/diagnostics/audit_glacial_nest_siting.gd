extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var profile:Dictionary=WorldProfile.new().make_zone_profile("glacial_range")
    var holder:=Node3D.new();root.add_child(holder)
    var result:Dictionary=TerrainBuilder.new().generate_world(holder,profile)
    var height_sampler:Callable=result.terrain_height_sampler
    var walkable_sampler:Callable=result.walkable_sampler
    var target:=Vector2(980,-2350)
    var travel_corridors:Array=profile.road_corridors+profile.trail_corridors
    print("GLACIAL_NEST_CURRENT|point=%.0f,%.0f|relief=%.2f|travel=%.1f|river=%.1f"%[
        target.x,target.y,_site_relief(target,11.0,height_sampler),
        _corridor_distance(target,travel_corridors),_corridor_distance(target,profile.river_corridors),
    ])
    var candidates:Array[Dictionary]=[]
    for ix in range(-25,26):
        for iz in range(-25,26):
            var point:=target+Vector2(ix*20.0,iz*20.0)
            if not bool(walkable_sampler.call(point.x,point.y)):continue
            var road_distance:=_corridor_distance(point,travel_corridors)
            var river_distance:=_corridor_distance(point,profile.river_corridors)
            if road_distance<34.0 or road_distance>450.0 or river_distance<45.0:continue
            var relief:=_site_relief(point,11.0,height_sampler)
            if relief>4.5:continue
            var score:=relief*8.0+absf(road_distance-70.0)*.025+point.distance_to(target)*.001
            candidates.append({"point":point,"relief":relief,"road":road_distance,"river":river_distance,"score":score})
    candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.score)<float(b.score))
    for index in range(mini(12,candidates.size())):
        var candidate:Dictionary=candidates[index]
        print("GLACIAL_NEST_CANDIDATE|point=%.0f,%.0f|relief=%.2f|road=%.1f|river=%.1f|score=%.2f"%[
            candidate.point.x,candidate.point.y,candidate.relief,candidate.road,candidate.river,candidate.score,
        ])
    quit(0 if not candidates.is_empty() else 1)


func _site_relief(point:Vector2,radius:float,height_sampler:Callable)->float:
    var minimum:=INF
    var maximum:=-INF
    for index in range(12):
        var sample_point:=point+Vector2.from_angle(TAU*float(index)/12.0)*radius
        var height:float=height_sampler.call(sample_point.x,sample_point.y).y
        minimum=minf(minimum,height);maximum=maxf(maximum,height)
    return maximum-minimum


func _corridor_distance(point:Vector2,corridors:Array)->float:
    var nearest:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            nearest=minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,Vector2(points[index]),Vector2(points[index+1]))))
    return nearest
