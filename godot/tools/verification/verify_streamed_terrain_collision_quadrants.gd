extends SceneTree


func _initialize()->void:call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_streamed_region_loaded("north_frontier")
    var body:=main.get_node_or_null("WorldRoot/StreamedRegions/NorthFrontier/TerrainRoot/TerrainMesh/TerrainMesh_StaticBody") as StaticBody3D
    var quadrants:Array[CollisionShape3D]=[]
    if body==null:failures.append("north terrain collision body is missing")
    else:
        for child in body.get_children():
            if child is CollisionShape3D and child.shape is HeightMapShape3D:quadrants.append(child)
    if quadrants.size()!=4:failures.append("expected four streamed heightmap quadrants, found %d"%quadrants.size())
    quadrants.sort_custom(func(a:CollisionShape3D,b:CollisionShape3D)->bool:
        return a.position.z<b.position.z or (is_equal_approx(a.position.z,b.position.z) and a.position.x<b.position.x)
    )
    var worst_shared_sample:=0.0
    var horizontal_gap:=INF
    var vertical_gap:=INF
    if quadrants.size()==4:
        var nw:=quadrants[0];var ne:=quadrants[1];var sw:=quadrants[2];var se:=quadrants[3]
        for collision in quadrants:
            var shape:=collision.shape as HeightMapShape3D
            if shape.map_width!=161 or shape.map_depth!=161:
                failures.append("%s is %dx%d instead of 161x161"%[collision.name,shape.map_width,shape.map_depth])
        horizontal_gap=absf((nw.position.x+1800.0)-(ne.position.x-1800.0))
        vertical_gap=absf((nw.position.z+1800.0)-(sw.position.z-1800.0))
        for row in range(161):
            worst_shared_sample=maxf(worst_shared_sample,absf(
                (nw.shape as HeightMapShape3D).map_data[row*161+160]-(ne.shape as HeightMapShape3D).map_data[row*161]
            ))
            worst_shared_sample=maxf(worst_shared_sample,absf(
                (sw.shape as HeightMapShape3D).map_data[row*161+160]-(se.shape as HeightMapShape3D).map_data[row*161]
            ))
        for column in range(161):
            worst_shared_sample=maxf(worst_shared_sample,absf(
                (nw.shape as HeightMapShape3D).map_data[160*161+column]-(sw.shape as HeightMapShape3D).map_data[column]
            ))
            worst_shared_sample=maxf(worst_shared_sample,absf(
                (ne.shape as HeightMapShape3D).map_data[160*161+column]-(se.shape as HeightMapShape3D).map_data[column]
            ))
        if horizontal_gap>.001 or vertical_gap>.001:failures.append("quadrant extents do not meet exactly")
        if worst_shared_sample>.0001:failures.append("quadrant shared height rows differ by %.5f m"%worst_shared_sample)
    print("STREAMED_TERRAIN_COLLISION|quadrants=%d|horizontal_gap=%.5f|vertical_gap=%.5f|shared_height_gap=%.5f|failures=%d"%[
        quadrants.size(),horizontal_gap,vertical_gap,worst_shared_sample,failures.size(),
    ])
    for failure in failures:push_error("STREAMED_TERRAIN_COLLISION_FAILURE|%s"%failure)
    main.free()
    for _cleanup in range(4):await process_frame
    quit(0 if failures.is_empty() else 1)
