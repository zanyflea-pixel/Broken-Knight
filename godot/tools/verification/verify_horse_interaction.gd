extends SceneTree


func _initialize()->void:call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    var director:=main.get_node("GameplayDirector")
    var horses:=get_nodes_in_group("rideable_horse")
    if horses.size()!=3:failures.append("expected three starter horses, found %d"%horses.size())
    var horse:=horses[0] as Node3D if not horses.is_empty() else null
    var prompt:=""
    if horse!=null:
        var approach:=horse.global_position+Vector3(0.0,0.0,3.2)
        approach.y=main._sample_global_height(approach.x,approach.z).y+.08
        player.global_position=approach
        director.call("_tick_vendor")
        var interaction:Dictionary=director.get("_nearby_interactable")
        prompt=str(director.get("nearby_vendor"))
        if str(interaction.get("action",""))!="mount_horse":failures.append("horse aisle approach did not resolve a mount interaction")
        else:director.call("_activate_interactable",interaction)
        if not player.is_mounted():failures.append("E interaction path did not mount the horse")
        else:
            player.dismount_horse()
            if player.is_mounted():failures.append("horse did not dismount cleanly")
    print("HORSE_INTERACTION|horses=%d|prompt=%s|mounted_then_dismounted=%s|failures=%d"%[
        horses.size(),prompt,str(horse!=null and not player.is_mounted()),failures.size(),
    ])
    for failure in failures:push_error("HORSE_INTERACTION_FAILURE|%s"%failure)
    main.free()
    for _cleanup in range(4):await process_frame
    quit(0 if failures.is_empty() else 1)
