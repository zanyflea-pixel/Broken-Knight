extends SceneTree


func _initialize()->void:
    call_deferred("_verify")


func _verify()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var terrain:=main.get_node("WorldRoot/TerrainRoot/TerrainMesh") as MeshInstance3D
    var profile:Dictionary=main.get("_active_profile")
    var expected_stride:=int(profile.get("grid_resolution",320))+1
    var vertex_count:=0
    if terrain.mesh!=null:
        var arrays:=terrain.mesh.surface_get_arrays(0)
        vertex_count=(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    if vertex_count!=expected_stride*expected_stride:failures.append("terrain vertex resolution changed")
    var collision:=terrain.get_node_or_null("TerrainMesh_StaticBody/TerrainMeshCollision") as CollisionShape3D
    if collision==null or collision.shape==null:failures.append("cached terrain collision is missing")
    var props:=main.get_node("WorldRoot/PropsRoot")
    var meadow_count:=int(props.get_meta("meadow_grass_count",0))
    if meadow_count<10000:failures.append("meadow content was reduced during optimization")
    var msaa:=int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d",0))
    if msaa<1:failures.append("3D edge antialiasing is disabled")
    print("WORLD_OPTIMIZATION_PASS|vertices=%d|meadow=%d|meadow_cache=%s|msaa=%d|failures=%d"%[
        vertex_count,meadow_count,str(props.get_meta("meadow_grass_cache_hit",false)),msaa,failures.size(),
    ])
    for failure in failures:push_error("WORLD_OPTIMIZATION_FAILURE|%s"%failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
