extends SceneTree


func _initialize()->void:
    call_deferred("_verify")


func _verify()->void:
    var failures:Array[String]=[]
    var asset:=load("res://assets/vegetation/highland_outcrop_v1.glb") as PackedScene
    if asset==null:
        failures.append("highland outcrop GLB is missing")
    else:
        var instance:=asset.instantiate()
        var mesh:=_first_mesh(instance)
        if mesh==null or mesh.get_surface_count()<5:
            failures.append("outcrop asset does not retain five detail-material surfaces")
        instance.free()
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var props:=main.get_node("WorldRoot/PropsRoot")
    var outcrop_count:=int(props.get_meta("highland_outcrop_count",0))
    var bracken_count:=int(props.get_meta("outcrop_bracken_count",0))
    var collision_body:=props.get_node_or_null("HighlandOutcropCollision") as StaticBody3D
    var collision_count:=0 if collision_body==null else collision_body.get_child_count()
    if outcrop_count<20:failures.append("fewer than 20 composed outcrop landmarks were accepted")
    if bracken_count<100:failures.append("outcrop vegetation apron is unexpectedly sparse")
    if collision_count!=outcrop_count:failures.append("outcrop collision count does not match visible formation count")
    print("HIGHLAND_OUTCROP_PASS|outcrops=%d|bracken=%d|collisions=%d|failures=%d"%[
        outcrop_count,bracken_count,collision_count,failures.size(),
    ])
    for failure in failures:push_error("HIGHLAND_OUTCROP_FAILURE|%s"%failure)
    main.free()
    quit(0 if failures.is_empty() else 1)


func _first_mesh(node:Node)->Mesh:
    if node is MeshInstance3D:return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var mesh:=_first_mesh(child)
        if mesh!=null:return mesh
    return null
