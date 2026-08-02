extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _init()->void:
    call_deferred("_run")


func _run()->void:
    # Terrain-only construction keeps this audit independent of towns,
    # enemies and inventory services. The former full Main scene made a
    # simple grade check take several minutes in headless mode.
    var terrain_root:=Node3D.new()
    root.add_child(terrain_root)
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var world:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var terrain:Callable=world.terrain_height_sampler
    var road_result:=_audit_corridors(profile.get("road_corridors",[]),terrain,10.0,profile.get("ford_sites",[]))
    var trail_result:=_audit_corridors(profile.get("trail_corridors",[]),terrain,8.0,profile.get("ford_sites",[]))
    var town_variance:=0.0
    var worst_town:=""
    for town in profile.get("town_sites",[]):
        var center:Vector2=town.get("position",Vector2.ZERO)
        var radius:float=float(town.get("radius",120.0))*.55
        var minimum:=INF
        var maximum:=-INF
        for ring in [0.0,.48,1.0]:
            for index in range(16):
                var angle:=float(index)/16.0*TAU
                var point:=center+Vector2(cos(angle),sin(angle))*radius*float(ring)
                var height:float=(terrain.call(point.x,point.y) as Vector3).y
                minimum=minf(minimum,height);maximum=maxf(maximum,height)
        if maximum-minimum>town_variance:
            town_variance=maximum-minimum
            worst_town=str(town.get("name","Town"))
    print("LANDFORM_TRAVERSAL|road_max_grade=%.3f|road=%s|road_severe=%d|trail_max_grade=%.3f|trail=%s|trail_severe=%d|town_variance=%.3f|town=%s"%[
        road_result.max_grade,road_result.name,road_result.severe,
        trail_result.max_grade,trail_result.name,trail_result.severe,
        town_variance,worst_town,
    ])
    var failures:=0
    if float(road_result.max_grade)>.52:failures+=1
    if float(trail_result.max_grade)>.68:failures+=1
    if town_variance>1.25:failures+=1
    terrain_root.free()
    quit(0 if failures==0 else 1)


func _audit_corridors(corridors:Array,sampler:Callable,spacing:float,ford_sites:Array)->Dictionary:
    var result:={"max_grade":0.0,"name":"","severe":0}
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for segment_index in range(points.size()-1):
            var a:Vector2=points[segment_index]
            var b:Vector2=points[segment_index+1]
            var length:=a.distance_to(b)
            var steps:=maxi(1,ceili(length/spacing))
            var previous:Vector3=sampler.call(a.x,a.y)
            for step in range(1,steps+1):
                var point:=a.lerp(b,float(step)/float(steps))
                var current:Vector3=sampler.call(point.x,point.y)
                if _near_ford(point,ford_sites):
                    previous=current
                    continue
                var grade:=absf(current.y-previous.y)/maxf(.001,Vector2(current.x,current.z).distance_to(Vector2(previous.x,previous.z)))
                if grade>float(result.max_grade):
                    result.max_grade=grade
                    result.name=str(corridor.get("name","Corridor"))
                if grade>.38:result.severe=int(result.severe)+1
                previous=current
    return result


func _near_ford(point:Vector2,ford_sites:Array)->bool:
    for site in ford_sites:
        var radius:float=float(site.get("radius",60.0))+85.0
        if point.distance_squared_to(site.get("position",Vector2.ZERO))<radius*radius:return true
    return false
