extends SceneTree

const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:call_deferred("_run")


func _run()->void:
    var zone_id:=OS.get_environment("BROKEN_KNIGHT_BAKE_ZONE").strip_edges()
    if zone_id.is_empty():zone_id="north_frontier"
    var packed:=load(WorldPreviewBuilder.streamed_visual_bake_path(zone_id)) as PackedScene
    var instance:=packed.instantiate() if packed else null
    if instance==null:quit(1);return
    for root_name in instance.get_meta("population_root_names",[]):
        var population_root:=instance.get_node_or_null(str(root_name))
        if population_root==null:continue
        for meta_name in population_root.get_meta_list():
            var value:Variant=population_root.get_meta(meta_name)
            var metrics:=_metrics(value)
            print("STREAMED_BAKE_META|root=%s|name=%s|containers=%d|values=%d|node_paths=%d"%[
                root_name,meta_name,metrics.containers,metrics.values,metrics.node_paths,
            ])
    instance.free();quit()


func _metrics(value:Variant)->Dictionary:
    var result:={"containers":0,"values":0,"node_paths":0}
    var pending:Array=[value]
    while not pending.is_empty():
        var current:Variant=pending.pop_back()
        result.values+=1
        if current is NodePath:result.node_paths+=1
        elif current is Dictionary:
            result.containers+=1
            for key in current:pending.append(current[key])
        elif current is Array:
            result.containers+=1
            pending.append_array(current)
    return result
