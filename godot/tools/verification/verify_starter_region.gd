extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var spawn:Dictionary=profile.get("spawn_site",{})
    if not spawn.get("starter",false):failures.append("Riverwatch is not marked as the authored starter town")

    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var terrain_sampler:Callable=terrain.get("terrain_height_sampler",terrain.height_sampler)
    var walkable_sampler:Callable=terrain.get("walkable_sampler",Callable())
    var center:Vector2=spawn.get("position",Vector2.ZERO)

    # The occupied starter-town pad must be stable enough for real buildings.
    var pad_heights:Array[float]=[]
    for offset in [Vector2.ZERO,Vector2(-58,-42),Vector2(58,-42),Vector2(-58,66),Vector2(58,66)]:
        pad_heights.append((terrain_sampler.call(center.x+offset.x,center.y+offset.y) as Vector3).y)
    var pad_min:float=pad_heights.min();var pad_max:float=pad_heights.max()
    if pad_max-pad_min>1.05:failures.append("starter town pad varies by %.2fm"%(pad_max-pad_min))

    var south_road:Dictionary=_named(profile.get("road_corridors",[]),"Southbank Road")
    var river:Dictionary=_named(profile.get("river_corridors",[]),"Kingsflow River")
    var bridge:Dictionary=_named(profile.get("ford_sites",[]),"Riverwatch Bridge")
    if south_road.is_empty():failures.append("Southbank Road missing")
    if river.is_empty():failures.append("Kingsflow River missing")
    if bridge.is_empty():failures.append("Riverwatch Bridge missing")
    var bridge_point:Vector2=bridge.get("position",Vector2.ZERO)
    var road_distance:=_distance_to_polyline(bridge_point,south_road.get("points",[]))
    var river_distance:=_distance_to_polyline(bridge_point,river.get("points",[]))
    if road_distance>3.0:failures.append("starter road misses bridge by %.2fm"%road_distance)
    if river_distance>8.0:failures.append("starter river misses bridge by %.2fm"%river_distance)
    if center.distance_to(bridge_point)>190.0:failures.append("first bridge is too far from the starter town")

    # Both banks immediately beside the crossing remain approachable. The deep
    # center channel can stay blocked because the deck is the intended route.
    var river_info:=_nearest_segment(bridge_point,river.get("points",[]))
    var river_direction:Vector2=river_info.get("direction",Vector2(1,0))
    var bank_normal:=Vector2(-river_direction.y,river_direction.x).normalized()
    for side in [-1.0,1.0]:
        var bank_point:=bridge_point+bank_normal*58.0*float(side)
        if walkable_sampler.is_valid() and not walkable_sampler.call(bank_point.x,bank_point.y):
            failures.append("starter bridge bank is not walkable on side %.0f"%float(side))

    # Follow the authored main street from town to the first destination and
    # reject abrupt terrain steps outside the actual bridge deck.
    var destination_point:=Vector2(-300,-285)
    var destination_road_info:=_nearest_segment(destination_point,south_road.get("points",[]))
    var route_samples:Array=[]
    var destination_segment_index:=int(destination_road_info.get("index",0))
    for route_index in range(destination_segment_index+1):
        route_samples.append(south_road.get("points",[])[route_index])
    route_samples.append(destination_road_info.get("nearest",destination_point))
    route_samples.append(destination_point)
    var max_route_grade:=0.0
    var max_route_grade_point:=Vector2.ZERO
    for segment_index in range(route_samples.size()-1):
        var a:Vector2=route_samples[segment_index];var b:Vector2=route_samples[segment_index+1]
        var steps:=maxi(1,int(ceil(a.distance_to(b)/8.0)))
        var previous_point:=a
        var previous_height:float=(terrain.height_sampler.call(a.x,a.y) as Vector3).y
        for step in range(1,steps+1):
            var point:=a.lerp(b,float(step)/float(steps))
            var height:float=(terrain.height_sampler.call(point.x,point.y) as Vector3).y
            var grade:=absf(height-previous_height)/maxf(.01,point.distance_to(previous_point))
            if grade>max_route_grade:max_route_grade=grade;max_route_grade_point=point
            previous_point=point;previous_height=height
    if max_route_grade>.42:failures.append("main route reaches an abrupt %.1f%% grade"%(max_route_grade*100.0))

    # Build only the authored starter content and bridge visuals. This exercises
    # the real in-engine builders without paying for unrelated world decoration.
    var town_root:=Node3D.new();root.add_child(town_root)
    var preview:=WorldPreviewBuilder.new()
    preview.call("_build_enterable_towns",town_root,profile,terrain)
    preview.call("_build_starter_region_destination",town_root,profile,terrain)
    var bridge_root:=Node3D.new();root.add_child(bridge_root)
    preview.call("_build_bridges",bridge_root,profile,terrain)
    var riverwatch:=town_root.get_node_or_null("Riverwatch")
    var destination:=town_root.get_node_or_null("Ferrywatch Post")
    if riverwatch==null:failures.append("authored Riverwatch town did not build")
    elif _count_type(riverwatch,"MeshInstance3D")<45:failures.append("Riverwatch town content is incomplete")
    if destination==null:failures.append("Ferrywatch Post did not build")
    elif _count_type(destination,"MeshInstance3D")<28:failures.append("Ferrywatch Post landmark is incomplete")
    if bridge_root.get_child_count()<7:failures.append("not all bridge visuals built")

    print("STARTER_REGION|pad_delta=%.3f|pad=%s|road_to_bridge=%.3f|river_to_bridge=%.3f|max_route_grade=%.3f|grade_at=%.1f,%.1f|town_meshes=%d|destination_meshes=%d|bridges=%d|failures=%d"%[
        pad_max-pad_min,str(pad_heights),road_distance,river_distance,max_route_grade,max_route_grade_point.x,max_route_grade_point.y,
        _count_type(riverwatch,"MeshInstance3D") if riverwatch else 0,
        _count_type(destination,"MeshInstance3D") if destination else 0,
        bridge_root.get_child_count(),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _named(entries:Array,wanted:String)->Dictionary:
    for value in entries:
        if value is Dictionary and str(value.get("name",""))==wanted:return value
    return {}


func _nearest_segment(point:Vector2,points:Array)->Dictionary:
    var best:Dictionary={};var best_distance:=INF
    for i in range(points.size()-1):
        var a:Vector2=points[i];var b:Vector2=points[i+1]
        var nearest:=Geometry2D.get_closest_point_to_segment(point,a,b)
        var distance:=point.distance_to(nearest)
        if distance<best_distance:
            best_distance=distance;best={"distance":distance,"direction":(b-a).normalized(),"index":i,"nearest":nearest}
    return best


func _distance_to_polyline(point:Vector2,points:Array)->float:
    return float(_nearest_segment(point,points).get("distance",INF))


func _count_type(node:Node,class_name_value:String)->int:
    if node==null:return 0
    var count:=1 if node.is_class(class_name_value) else 0
    for child in node.get_children():count+=_count_type(child,class_name_value)
    return count
