extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await physics_frame
    var hero:CharacterBody3D=main.get_node("Player")
    var director:Node=main.get_node("GameplayDirector")
    var profile:Dictionary=main.get("_active_profile")
    var sampler:Callable=main.get("_world_result").height_sampler

    # Raised town paving must be part of the surface resolution, rather than
    # being a visual disc that swallows the hero's feet.
    var town:Dictionary=profile.get("town_sites",[])[0]
    var center:Vector2=town.get("position",Vector2.ZERO)
    var terrain:Vector3=sampler.call(center.x,center.y)
    hero.global_position=terrain+Vector3.UP*.42
    await physics_frame
    var resolved:Vector3=hero.call("_resolve_ground_position",hero.global_position)
    var paving_ok:=resolved.y>=terrain.y+.18
    if not paving_ok:failures.append("town paving was not resolved as walkable surface")

    # Town cargo now has physical collision instead of being visual-only.
    var cargo2:=center+Vector2(cos(.25),sin(.25))*20.5*1.15
    var cargo_ground:Vector3=sampler.call(cargo2.x,cargo2.y)
    var query:=PhysicsRayQueryParameters3D.create(cargo_ground+Vector3.UP*3.0,cargo_ground-Vector3.UP,1,[hero.get_rid()])
    var cargo_hit:=main.get_world_3d().direct_space_state.intersect_ray(query)
    var cargo_ok:=not cargo_hit.is_empty() and float(cargo_hit.position.y)>cargo_ground.y+.35
    if not cargo_ok:failures.append("town cargo collision missing")

    # Bushes share the streamed prop pool so collision remains local and cheap.
    var registry:Array=director.get("_rock_collision_registry")
    var bush:Dictionary={}
    for candidate in registry:
        if candidate.get("kind","")=="bush":
            bush=candidate
            break
    if bush.is_empty():
        failures.append("bush collision registry missing")
    else:
        hero.global_position=bush.position
        director.call("_refresh_local_prop_collisions")
        var active_bush_collision:=false
        for shape in director.get("_local_prop_collision_shapes"):
            if not shape.disabled and shape.position.distance_to(Vector3(bush.position))<.2:
                active_bush_collision=true
                break
        if not active_bush_collision:failures.append("local bush collision did not activate")

    print("SURFACE_COLLISION|paving=%s|cargo=%s|bush_registry=%s|failures=%d"%[paving_ok,cargo_ok,not bush.is_empty(),failures.size()])
    for failure in failures:push_error("SURFACE_COLLISION_FAILURE|%s"%failure)
    main.free()
    quit(1 if not failures.is_empty() else 0)
