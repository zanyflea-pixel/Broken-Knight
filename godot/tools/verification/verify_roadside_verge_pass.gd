extends SceneTree


func _initialize()->void:
    call_deferred("_verify")


func _verify()->void:
    var failures:Array[String]=[]
    var asset:=load("res://assets/vegetation/roadside_verge_cluster_v1.glb") as PackedScene
    var surface_count:=0
    if asset==null:
        failures.append("roadside verge GLB is missing")
    else:
        var instance:=asset.instantiate()
        var mesh:=_first_mesh(instance)
        if mesh!=null:surface_count=mesh.get_surface_count()
        if surface_count<6:failures.append("verge asset does not retain six authored material surfaces")
        instance.free()
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    var props:=main.get_node("WorldRoot/PropsRoot")
    var cluster_count:=int(props.get_meta("roadside_verge_cluster_count",0))
    if cluster_count<80:failures.append("fewer than 80 rural road-verge clusters were accepted")
    if main.get_node("WorldRoot/RoadRoot").get_meta("roadside_verge_cluster_count",-1)>=0:
        failures.append("verge clusters were attached to road geometry instead of the culled props layer")
    print("ROADSIDE_VERGE_PASS|clusters=%d|surfaces=%d|failures=%d"%[
        cluster_count,surface_count,failures.size(),
    ])
    for failure in failures:push_error("ROADSIDE_VERGE_FAILURE|%s"%failure)
    main.free()
    quit(0 if failures.is_empty() else 1)


func _first_mesh(node:Node)->Mesh:
    if node is MeshInstance3D:return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var mesh:=_first_mesh(child)
        if mesh!=null:return mesh
    return null
