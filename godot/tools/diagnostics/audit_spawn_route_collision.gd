extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await physics_frame
    var player:=main.get_node("Player") as CharacterBody3D
    var world:World3D=main.get_world_3d()
    var sampler:Callable=main.get("_world_result").height_sampler
    var capsule:=CapsuleShape3D.new()
    capsule.radius=.42
    capsule.height=1.8
    for z in range(70,-51,-1):
        var ground:Vector3=sampler.call(-420.58,float(z))
        var query:=PhysicsShapeQueryParameters3D.new()
        query.shape=capsule
        query.transform=Transform3D(Basis.IDENTITY,ground+Vector3.UP*.90)
        query.collision_mask=1
        query.exclude=[player.get_rid()]
        var hits:=world.direct_space_state.intersect_shape(query,16)
        var labels:=PackedStringArray()
        for hit in hits:
            var collider:=hit.get("collider") as Node
            if is_instance_valid(collider):labels.append("%s/%s"%[collider.name,collider.get_parent().name if collider.get_parent() else ""])
        if not labels.is_empty():print("SPAWN_ROUTE_HIT|z=%d|ground=%.2f|colliders=%s"%[z,ground.y,",".join(labels)])
    main.free()
    quit()
