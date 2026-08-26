extends SceneTree

const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var zone_id:=OS.get_environment("BROKEN_KNIGHT_BAKE_ZONE").strip_edges()
    if zone_id.is_empty():zone_id="east_marches"
    var path:=WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
    var load_started:=Time.get_ticks_usec()
    var packed:=load(path) as PackedScene
    var load_ms:=float(Time.get_ticks_usec()-load_started)/1000.0
    if packed==null:
        push_error("Missing streamed bake: %s"%path);quit(1);return
    var instantiate_started:=Time.get_ticks_usec()
    var instance:=packed.instantiate()
    var instantiate_ms:=float(Time.get_ticks_usec()-instantiate_started)/1000.0
    root.add_child(instance)
    var counts:Dictionary={}
    for root_name in ["RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var child:=instance.get_node_or_null(root_name)
        counts[root_name]=_count_nodes(child) if child else 0
    print("STREAMED_VISUAL_BAKE_BENCHMARK|zone=%s|load_ms=%.2f|instantiate_ms=%.2f|total_nodes=%d|roots=%s"%[
        zone_id,load_ms,instantiate_ms,_count_nodes(instance),str(counts),
    ])
    for root_name in ["TownRoot","PropsRoot"]:
        var population_root:=instance.get_node_or_null(root_name)
        var child_counts:Array=[]
        if population_root:
            for child in population_root.get_children():child_counts.append({"name":child.name,"nodes":_count_nodes(child)})
        child_counts.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.nodes)>int(b.nodes))
        print("STREAMED_VISUAL_BAKE_CHILDREN|root=%s|largest=%s"%[root_name,str(child_counts.slice(0,mini(16,child_counts.size())))])
    instance.free();quit()


func _count_nodes(node:Node)->int:
    if node==null:return 0
    var count:=1
    for child in node.get_children():count+=_count_nodes(child)
    return count
