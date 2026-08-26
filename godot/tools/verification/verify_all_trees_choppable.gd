extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    var director:Node=main.get_node("GameplayDirector")
    var player:CharacterBody3D=main.get_node("Player")
    var boot_deadline:=Time.get_ticks_msec()+20000
    while director._forest_trees.is_empty() and Time.get_ticks_msec()<boot_deadline:
        await process_frame
    var trees:Array=director._forest_trees
    if trees.size()<1000:failures.append("world tree registry too small: %d"%trees.size())
    if trees.is_empty():
        failures.append("no world trees registered")
    else:
        var target:Dictionary=trees[0]
        player.equip_item_id("starter_wood_axe")
        if not player.has_axe_equipped():failures.append("axe did not equip")
        player.global_position=target.position+Vector3(0,.1,2.0)
        var found:Dictionary=director._find_nearby_world_tree()
        if found.is_empty():failures.append("nearby ordinary tree was not targetable")
        var neighbor_part:Dictionary={}
        var target_first_part:Dictionary=target.get("batched_parts",[])[0] if not target.get("batched_parts",[]).is_empty() else {}
        var target_instance:=target_first_part.get("instance") as MultiMeshInstance3D
        for neighbor in trees:
            if neighbor==target:continue
            for candidate_part in neighbor.get("batched_parts",[]):
                if candidate_part.get("instance") as MultiMeshInstance3D==target_instance:
                    neighbor_part=candidate_part
                    break
            if not neighbor_part.is_empty():break
        var neighbor_buffer_before:=PackedFloat32Array()
        if not neighbor_part.is_empty():
            neighbor_buffer_before=(neighbor_part.instance as MultiMeshInstance3D).multimesh.buffer.duplicate()
        var loot_before:int=director.loot.size()
        director._activate_world_tree(target)
        director._activate_world_tree(target)
        director._activate_world_tree(target)
        if target.get("active",true):failures.append("ordinary tree remained active after three chops")
        for part_value in target.get("batched_parts",[]):
            var part:Dictionary=part_value
            if part.is_empty():continue
            var instance:=part.get("instance") as MultiMeshInstance3D
            var stride:=12+(4 if instance.multimesh.use_colors else 0)+(4 if instance.multimesh.use_custom_data else 0)
            var buffer:=instance.multimesh.buffer
            var offset:=int(part.index)*stride
            var hidden_scale:=Vector3(buffer[offset+0],buffer[offset+5],buffer[offset+10]).length()
            if offset+10>=buffer.size() or hidden_scale>.001:
                failures.append("batched tree component did not shrink")
                break
            var original:Transform3D=part.get("transform",Transform3D.IDENTITY)
            if Vector3(buffer[offset+3],buffer[offset+7],buffer[offset+11]).distance_to(original.origin)>.001:
                failures.append("hidden tree moved and could invalidate its forest chunk bounds")
                break
        if not neighbor_part.is_empty():
            var neighbor_instance:=neighbor_part.instance as MultiMeshInstance3D
            var neighbor_buffer_after:=neighbor_instance.multimesh.buffer
            var neighbor_stride:=12+(4 if neighbor_instance.multimesh.use_colors else 0)+(4 if neighbor_instance.multimesh.use_custom_data else 0)
            var neighbor_offset:=int(neighbor_part.index)*neighbor_stride
            for component in range(12):
                if not is_equal_approx(neighbor_buffer_after[neighbor_offset+component],neighbor_buffer_before[neighbor_offset+component]):
                    failures.append("chopping one tree changed a neighboring tree")
                    break
        await create_timer(1.05).timeout
        if director.loot.size()<loot_before+3:failures.append("ordinary tree did not drop three logs")
        director._set_world_tree_visible(target,true)
        for part_value in target.get("batched_parts",[]):
            var part:Dictionary=part_value
            if part.is_empty():continue
            var instance:=part.get("instance") as MultiMeshInstance3D
            var stride:=12+(4 if instance.multimesh.use_colors else 0)+(4 if instance.multimesh.use_custom_data else 0)
            var buffer:=instance.multimesh.buffer
            var offset:=int(part.index)*stride
            var restored:Transform3D=part.get("transform",Transform3D.IDENTITY)
            if offset+11>=buffer.size() or Vector3(buffer[offset+3],buffer[offset+7],buffer[offset+11]).distance_to(restored.origin)>.001 or Vector3(buffer[offset+0],buffer[offset+5],buffer[offset+10]).length()<.01:
                failures.append("ordinary tree could not be restored")
                break
    print("ALL_TREES_CHOPPABLE|registered=%d|logs=%d|failures=%d"%[trees.size(),director.loot.size(),failures.size()])
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
