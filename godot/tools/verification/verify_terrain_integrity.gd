extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var builder:=TerrainBuilder.new()
    builder.generate_world(terrain_root,profile)
    var terrain:=terrain_root.get_node_or_null("TerrainMesh") as MeshInstance3D
    if terrain==null or terrain.mesh==null:
        push_error("terrain mesh is missing");quit(1);return
    var arrays:Array=terrain.mesh.surface_get_arrays(0)
    var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
    var resolution:=int(profile.get("grid_resolution",0))
    var stride:=resolution+1
    var expected_vertices:=stride*stride
    var expected_indices:=resolution*resolution*6
    var grid_step:=float(profile.get("world_size",7200.0))/maxf(1.0,float(resolution))
    var maximum_allowed_delta:=grid_step*.305
    if vertices.size()!=expected_vertices:failures.append("terrain vertex grid is incomplete")
    if indices.size()!=expected_indices:failures.append("terrain triangle grid is incomplete")

    var steep_edges:Array[Dictionary]=[]
    var maximum_delta:=0.0
    var invalid_vertices:=0
    for z_index in range(stride):
        for x_index in range(stride):
            var index:=z_index*stride+x_index
            if index>=vertices.size():continue
            var vertex:=vertices[index]
            if not is_finite(vertex.y):invalid_vertices+=1;continue
            if x_index<resolution:_record_edge(vertex,vertices[index+1],steep_edges)
            if z_index<resolution:_record_edge(vertex,vertices[index+stride],steep_edges)
    if invalid_vertices>0:failures.append("terrain contains %d invalid height vertices"%invalid_vertices)
    steep_edges.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.delta)>float(b.delta))
    if not steep_edges.is_empty():maximum_delta=float(steep_edges[0].delta)
    if maximum_delta>maximum_allowed_delta+.02:
        failures.append("terrain contains a %.2fm single-cell cliff (limit %.2fm)"%[maximum_delta,maximum_allowed_delta])
    for index in range(mini(8,steep_edges.size())):
        var edge:Dictionary=steep_edges[index]
        var point:Vector2=edge.point
        var road_distance:=_distance_to_corridors(point,profile.get("road_corridors",[]))
        var trail_distance:=_distance_to_corridors(point,profile.get("trail_corridors",[]))
        var river_distance:=_distance_to_corridors(point,profile.get("river_corridors",[]))
        print("TERRAIN_EDGE|x=%.1f|z=%.1f|delta=%.2f|road=%.1f|trail=%.1f|river=%.1f"%[
            point.x,point.y,float(edge.delta),road_distance,trail_distance,river_distance,
        ])
    print("TERRAIN_INTEGRITY|vertices=%d/%d|indices=%d/%d|max_edge_delta=%.2f|steep_edges=%d|invalid=%d|failures=%d"%[
        vertices.size(),expected_vertices,indices.size(),expected_indices,maximum_delta,steep_edges.size(),invalid_vertices,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _record_edge(a:Vector3,b:Vector3,results:Array[Dictionary])->void:
    var delta:=absf(a.y-b.y)
    if delta<4.0:return
    results.append({"point":Vector2((a.x+b.x)*.5,(a.z+b.z)*.5),"delta":delta,"a":a,"b":b})


func _distance_to_corridors(point:Vector2,corridors:Array)->float:
    var best:=INF
    for corridor_value in corridors:
        var points:Array=corridor_value.get("points",[])
        for index in range(points.size()-1):
            best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best
