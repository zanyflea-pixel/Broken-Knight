extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var director:Node=main.get_node("GameplayDirector")
    var player:CharacterBody3D=main.get_node("Player")
    var legacy_trees:Array=[]
    for interaction in director._interactables:
        if interaction.get("action","")=="chop":legacy_trees.append(interaction)
    if not legacy_trees.is_empty():failures.append("duplicate dedicated harvest trees still exist: %d"%legacy_trees.size())
    var duplicate_nodes:=director.find_children("ChoppableTree_*","Node3D",true,false)
    if not duplicate_nodes.is_empty():failures.append("duplicate harvest tree nodes still exist: %d"%duplicate_nodes.size())
    var trees:Array=director._forest_trees
    if trees.size()<1000:
        failures.append("too few registered world trees: %d"%trees.size())
    if trees.is_empty():
        failures.append("no choppable world tree")
    else:
        var tree_data:Dictionary=trees[0]
        player.equip_item_id("starter_wood_axe")
        if not player.has_axe_equipped():failures.append("axe did not equip")
        player.global_position=tree_data.position+Vector3(0,.1,2.0)
        var loot_before:int=director.loot.size()
        director._activate_world_tree(tree_data)
        director._activate_world_tree(tree_data)
        director._activate_world_tree(tree_data)
        await create_timer(1.05).timeout
        if tree_data.get("active",true):failures.append("tree remained active after three chops")
        if director.loot.size()<loot_before+3:failures.append("three visible logs were not dropped")
        var fallen_tree:=director.get_node_or_null("FallingHarvestTree")
        if fallen_tree==null:failures.append("felled tree vanished before its short linger")
        var grounded_log_states:Array[Dictionary]=[]
        for drop in director.loot:
            if drop.get("reward",{}).get("material","")!="logs":continue
            var log_node:=drop.get("node") as Node3D
            if not drop.get("grounded",false):failures.append("log pickup was not marked grounded")
            if log_node and log_node.get_node_or_null("BlenderPickup")==null:failures.append("log pickup has no authored log visual")
            if log_node and log_node.get_node_or_null("Label3D")!=null:failures.append("log pickup still has floating text")
            if log_node:grounded_log_states.append({"node":log_node,"position":log_node.global_position,"rotation":log_node.global_rotation})
        director._tick_loot(1.0)
        for state in grounded_log_states:
            var log_node:=state.node as Node3D
            if log_node.global_position.distance_to(state.position)>.001 or log_node.global_rotation.distance_to(state.rotation)>.001:
                failures.append("grounded log moved or spun")
                break
        await create_timer(4.15).timeout
        await process_frame
        if director.get_node_or_null("FallingHarvestTree")!=null:failures.append("felled tree did not despawn")
    print("WOODCUTTING_PASS|trees=%d|legacy_duplicates=%d|axe=%s|logs=%d|failures=%d"%[trees.size(),legacy_trees.size(),player.has_axe_equipped(),director.loot.size(),failures.size()])
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
