extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var roads:Array=profile.get("road_corridors",[])
    var trails:Array=profile.get("trail_corridors",[])
    var class_counts:={"major":0,"secondary":0,"local":0}

    for corridor_value in roads+trails:
        var corridor:Dictionary=corridor_value
        var route_name:=str(corridor.get("name","Unnamed route"))
        var route_class:=str(corridor.get("route_class",""))
        var width:=float(corridor.get("width",0.0))
        if not class_counts.has(route_class):
            failures.append("%s has unsupported route class '%s'"%[route_name,route_class])
            continue
        class_counts[route_class]+=1
        if str(corridor.get("purpose","")).is_empty():failures.append("%s has no authored travel purpose"%route_name)
        if route_class=="major" and width<19.0:failures.append("%s is too narrow to read as a major road"%route_name)
        if route_class=="secondary" and (width<11.0 or width>17.0):failures.append("%s does not read at secondary-road scale"%route_name)
        if route_class=="local" and width>7.0:failures.append("%s visually competes with the road network"%route_name)
        if corridor.get("points",[]).size()<2:failures.append("%s has no usable route"%route_name)

    if class_counts.major!=3:failures.append("expected three major realm roads")
    if class_counts.secondary!=4:failures.append("expected four secondary settlement and regional connector roads")
    if class_counts.local!=trails.size():failures.append("every trail must be classified as local")

    var known_destinations:Dictionary=_known_destinations(profile,roads)
    for road_value in roads:
        var road:Dictionary=road_value
        var destinations:Array=road.get("destinations",[])
        if destinations.size()!=2:
            failures.append("%s needs exactly two stated destinations"%str(road.get("name","Road")))
            continue
        var points:Array=road.get("points",[])
        for destination_index in range(2):
            var destination_name:=str(destinations[destination_index])
            if not known_destinations.has(destination_name):
                failures.append("%s names an unknown destination: %s"%[str(road.get("name","Road")),destination_name])
                continue
            var endpoint:Vector2=points[0] if destination_index==0 else points[-1]
            var destination:Dictionary=known_destinations[destination_name]
            var gap:=_distance_to_destination(endpoint,destination)
            if gap>3.0:failures.append("%s misses %s by %.1fm"%[str(road.get("name","Road")),destination_name,gap])

    var connected:=_connected_road_indices(roads)
    if connected.size()!=roads.size():failures.append("the major and secondary road network is not fully connected")

    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var height_sampler:Callable=terrain.get("height_sampler",Callable())
    var worst_grade:={"major":0.0,"secondary":0.0,"local":0.0}
    var worst_turn:={"major":0.0,"secondary":0.0,"local":0.0}
    for corridor_value in roads+trails:
        var corridor:Dictionary=corridor_value
        var route_class:=str(corridor.get("route_class","local"))
        var grade_info:=_max_grade_info(corridor.get("points",[]),height_sampler)
        var max_grade:float=grade_info.grade
        var max_turn:=_max_turn(corridor.get("points",[]))
        worst_grade[route_class]=maxf(float(worst_grade[route_class]),max_grade)
        worst_turn[route_class]=maxf(float(worst_turn[route_class]),max_turn)
        var grade_limit:=.30 if route_class=="major" else (.36 if route_class=="secondary" else .40)
        if max_grade>grade_limit:
            failures.append("%s reaches an abrupt %.1f%% grade"%[str(corridor.get("name","Route")),max_grade*100.0])
        if max_turn>112.0:
            failures.append("%s contains an unnecessary %.1f degree reversal"%[str(corridor.get("name","Route")),max_turn])
        print("ROAD_ROUTE|%s|class=%s|width=%.1f|max_grade=%.3f|grade_at=%.1f,%.1f|max_turn=%.1f"%[
            str(corridor.get("name","Route")),route_class,float(corridor.get("width",0.0)),max_grade,
            float(grade_info.point.x),float(grade_info.point.y),max_turn,
        ])

    var road_root:=Node3D.new();root.add_child(road_root)
    WorldPreviewBuilder.new().call("_build_road_ribbons",road_root,roads,terrain,profile)
    var rendered_routes:=0
    for road_value in roads:
        var road:Dictionary=road_value
        if road_root.get_node_or_null(str(road.get("name","Road")))!=null:rendered_routes+=1
    if rendered_routes!=roads.size():failures.append("not every road produced a continuous in-world ribbon")
    var major_color:=Color.TRANSPARENT
    var secondary_color:=Color.TRANSPARENT
    for child in road_root.get_children():
        var road_name:=str(child.name)
        var road_data:=_named(roads,road_name)
        var material:StandardMaterial3D=child.material_override
        if material==null:continue
        if str(road_data.get("route_class","secondary"))=="major":major_color=material.albedo_color
        else:secondary_color=material.albedo_color
    if major_color==Color.TRANSPARENT or secondary_color==Color.TRANSPARENT:
        failures.append("road hierarchy materials did not build")
    elif major_color.is_equal_approx(secondary_color):
        failures.append("major and secondary roads are not visually distinct in-world")

    var map_source:=FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
    var minimap_source:=FileAccess.get_file_as_string("res://scripts/Minimap.gd")
    if map_source.find("route_class")<0 or map_source.find("secondary\",\"major")<0:
        failures.append("world map does not draw road hierarchy")
    if minimap_source.find("route_class")<0 or minimap_source.find("secondary\",\"major")<0:
        failures.append("minimap does not draw road hierarchy")

    print("ROAD_HIERARCHY|major=%d|secondary=%d|local=%d|connected=%d/%d|grade_major=%.3f|grade_secondary=%.3f|grade_local=%.3f|turn_major=%.1f|turn_secondary=%.1f|turn_local=%.1f|rendered=%d|failures=%d"%[
        class_counts.major,class_counts.secondary,class_counts.local,connected.size(),roads.size(),
        worst_grade.major,worst_grade.secondary,worst_grade.local,
        worst_turn.major,worst_turn.secondary,worst_turn.local,
        rendered_routes,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _known_destinations(profile:Dictionary,roads:Array)->Dictionary:
    var destinations:Dictionary={}
    var spawn:Dictionary=profile.get("spawn_site",{})
    destinations[str(spawn.get("name","Spawn"))]={"kind":"site","position":spawn.get("position",Vector2.ZERO)}
    for site_value in profile.get("town_sites",[]):
        var site:Dictionary=site_value
        destinations[str(site.get("name","Town"))]={"kind":"site","position":site.get("position",Vector2.ZERO)}
    for road_value in roads:
        var road:Dictionary=road_value
        destinations[str(road.get("name","Road"))]={"kind":"corridor","points":road.get("points",[])}
    return destinations


func _distance_to_destination(point:Vector2,destination:Dictionary)->float:
    if str(destination.get("kind","site"))=="corridor":return _distance_to_polyline(point,destination.get("points",[]))
    return point.distance_to(destination.get("position",Vector2.ZERO))


func _connected_road_indices(roads:Array)->Array[int]:
    if roads.is_empty():return []
    var connected:Array[int]=[0]
    var changed:=true
    while changed:
        changed=false
        for index in range(roads.size()):
            if connected.has(index):continue
            for connected_index in connected:
                if _polyline_gap(roads[index].get("points",[]),roads[connected_index].get("points",[]))<=3.0:
                    connected.append(index);changed=true;break
    return connected


func _polyline_gap(first:Array,second:Array)->float:
    var best:=INF
    for point in first:best=minf(best,_distance_to_polyline(point,second))
    for point in second:best=minf(best,_distance_to_polyline(point,first))
    return best


func _max_grade_info(points:Array,height_sampler:Callable)->Dictionary:
    if not height_sampler.is_valid():return {"grade":INF,"point":Vector2.ZERO}
    var worst:=0.0
    var worst_point:=Vector2.ZERO
    for index in range(points.size()-1):
        var a:Vector2=points[index];var b:Vector2=points[index+1]
        var steps:=maxi(1,int(ceil(a.distance_to(b)/10.0)))
        var previous:=a
        var previous_height:float=(height_sampler.call(a.x,a.y) as Vector3).y
        for step in range(1,steps+1):
            var point:=a.lerp(b,float(step)/float(steps))
            var height:float=(height_sampler.call(point.x,point.y) as Vector3).y
            var grade:=absf(height-previous_height)/maxf(.01,point.distance_to(previous))
            if grade>worst:worst=grade;worst_point=point
            previous=point;previous_height=height
    return {"grade":worst,"point":worst_point}


func _max_turn(points:Array)->float:
    var worst:=0.0
    for index in range(1,points.size()-1):
        var incoming:Vector2=(points[index]-points[index-1]).normalized()
        var outgoing:Vector2=(points[index+1]-points[index]).normalized()
        worst=maxf(worst,rad_to_deg(acos(clampf(incoming.dot(outgoing),-1.0,1.0))))
    return worst


func _distance_to_polyline(point:Vector2,points:Array)->float:
    var best:=INF
    for index in range(points.size()-1):
        best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best


func _named(entries:Array,wanted:String)->Dictionary:
    for value in entries:
        if value is Dictionary and str(value.get("name",""))==wanted:return value
    return {}
