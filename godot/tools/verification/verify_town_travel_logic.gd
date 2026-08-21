extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var roads:Array=profile.get("road_corridors",[])
    var settlements:Array=[profile.get("spawn_site",{})]
    settlements.append_array(profile.get("town_sites",[]))
    var settlement_by_name:Dictionary={}
    for site_value in settlements:
        var site:Dictionary=site_value
        var site_name:=str(site.get("name",""))
        settlement_by_name[site_name]=site
        if str(site.get("role","")).is_empty():failures.append("%s has no authored regional role"%site_name)
        if str(site.get("siting_reason","")).is_empty():failures.append("%s has no authored siting reason"%site_name)
        var connections:Array=site.get("connections",[])
        if connections.is_empty():failures.append("%s has no stated settlement connections"%site_name)
        var road_gap:=_distance_to_corridors(site.get("position",Vector2.ZERO),roads)
        if road_gap>3.0:failures.append("%s misses the regional road network by %.1fm"%[site_name,road_gap])

    for site_value in settlements:
        var site:Dictionary=site_value
        var site_name:=str(site.get("name",""))
        for target_value in site.get("connections",[]):
            var target_name:=str(target_value)
            if not settlement_by_name.has(target_name):
                failures.append("%s names an unknown settlement connection: %s"%[site_name,target_name])
                continue
            var target:Dictionary=settlement_by_name[target_name]
            if not target.get("connections",[]).has(site_name):
                failures.append("%s -> %s is not reciprocal"%[site_name,target_name])

    var graph:=_build_route_graph(roads)
    var hub:Dictionary=settlement_by_name.get("Riverwatch",{})
    var hub_position:Vector2=hub.get("position",Vector2.ZERO)
    var reachable:=0
    for site_value in settlements:
        var site:Dictionary=site_value
        var site_name:=str(site.get("name",""))
        if site_name=="Riverwatch":continue
        var site_position:Vector2=site.get("position",Vector2.ZERO)
        var route_distance:=_shortest_distance(graph,hub_position,site_position)
        var direct_distance:=hub_position.distance_to(site_position)
        var ratio:=route_distance/maxf(1.0,direct_distance)
        if is_inf(route_distance):failures.append("%s is unreachable from Riverwatch"%site_name)
        else:reachable+=1
        if ratio>2.35:failures.append("the main route from Riverwatch to %s is an excessive %.2fx detour"%[site_name,ratio])
        print("TOWN_ROUTE|Riverwatch|%s|direct=%.1f|network=%.1f|ratio=%.2f|role=%s"%[
            site_name,direct_distance,route_distance,ratio,str(site.get("role","missing")),
        ])

    for first_index in range(settlements.size()):
        for second_index in range(first_index+1,settlements.size()):
            var first:Dictionary=settlements[first_index]
            var second:Dictionary=settlements[second_index]
            var separation:float=(first.get("position",Vector2.ZERO) as Vector2).distance_to(second.get("position",Vector2.ZERO))
            if separation<850.0:failures.append("%s and %s are too close to feel like purposeful separate towns"%[str(first.get("name","Town")),str(second.get("name","Town"))])

    var south_ford_road:=_named(roads,"South Ford Road")
    var market_road:=_named(roads,"Crownspire Market Road")
    if south_ford_road.is_empty():failures.append("Eastreach and Southbank lack a regional South Ford connector")
    elif str(south_ford_road.get("route_class",""))!="secondary":failures.append("South Ford Road must read as a secondary regional connector")
    if market_road.is_empty():failures.append("Southbank and Crownspire lack a direct market route")
    elif market_road.get("destinations",[])!=["Southbank","Crownspire"]:failures.append("Crownspire Market Road does not connect its intended towns")

    var south_ford:=_named(profile.get("ford_sites",[]),"South Ford")
    if south_ford.is_empty():
        failures.append("South Ford crossing is missing")
    else:
        var bridge_position:Vector2=south_ford.get("position",Vector2.ZERO)
        if _distance_to_corridors(bridge_position,[south_ford_road])>1.0:failures.append("South Ford Road misses its bridge")
        if _distance_to_corridors(bridge_position,profile.get("river_corridors",[]))>5.0:failures.append("South Ford bridge misses the Kingsflow")

    var map_source:=FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
    var minimap_source:=FileAccess.get_file_as_string("res://scripts/Minimap.gd")
    for source_info in [{"name":"world map","source":map_source},{"name":"minimap","source":minimap_source}]:
        var source:String=source_info.source
        if source.find("road_corridors")<0 or source.find("town_sites")<0 or source.find("route_class")<0:
            failures.append("%s does not communicate the authored settlement travel network"%str(source_info.name))

    print("TOWN_TRAVEL_LOGIC|settlements=%d|roads=%d|reachable_from_hub=%d/%d|south_ford=%s|market_link=%s|failures=%d"%[
        settlements.size(),roads.size(),reachable,maxi(0,settlements.size()-1),
        str(not south_ford_road.is_empty()),str(not market_road.is_empty()),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _build_route_graph(roads:Array)->Dictionary:
    var graph:Dictionary={}
    for road_value in roads:
        var road:Dictionary=road_value
        var points:Array=road.get("points",[])
        for index in range(points.size()-1):
            _link(graph,points[index],points[index+1])
    return graph


func _link(graph:Dictionary,a:Vector2,b:Vector2)->void:
    var a_key:=_point_key(a);var b_key:=_point_key(b)
    if not graph.has(a_key):graph[a_key]={"position":a,"edges":{}}
    if not graph.has(b_key):graph[b_key]={"position":b,"edges":{}}
    var length:=a.distance_to(b)
    graph[a_key].edges[b_key]=length
    graph[b_key].edges[a_key]=length


func _shortest_distance(graph:Dictionary,start:Vector2,target:Vector2)->float:
    var start_key:=_point_key(start);var target_key:=_point_key(target)
    if not graph.has(start_key) or not graph.has(target_key):return INF
    var distances:Dictionary={start_key:0.0}
    var open:Array[String]=[start_key]
    while not open.is_empty():
        var best_index:=0
        for index in range(1,open.size()):
            if float(distances[open[index]])<float(distances[open[best_index]]):best_index=index
        var current:String=open.pop_at(best_index)
        if current==target_key:return float(distances[current])
        var edges:Dictionary=graph[current].edges
        for neighbor_value in edges.keys():
            var neighbor:=str(neighbor_value)
            var candidate:=float(distances[current])+float(edges[neighbor])
            if candidate<float(distances.get(neighbor,INF)):
                distances[neighbor]=candidate
                if not open.has(neighbor):open.append(neighbor)
    return INF


func _point_key(point:Vector2)->String:
    return "%.2f,%.2f"%[point.x,point.y]


func _distance_to_corridors(point:Vector2,corridors:Array)->float:
    var best:=INF
    for corridor_value in corridors:
        var corridor:Dictionary=corridor_value
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best


func _named(entries:Array,wanted:String)->Dictionary:
    for value in entries:
        if value is Dictionary and str(value.get("name",""))==wanted:return value
    return {}
