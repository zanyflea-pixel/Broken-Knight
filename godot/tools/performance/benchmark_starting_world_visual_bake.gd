extends SceneTree

const BAKE_PATH := "res://assets/world/generated/starting_realm_visuals_v1.scn"


func _initialize() -> void:
    call_deferred("_run_benchmark")


func _run_benchmark() -> void:
    var load_started := Time.get_ticks_usec()
    var packed := load(BAKE_PATH) as PackedScene
    var load_ms := float(Time.get_ticks_usec() - load_started) / 1000.0
    if packed == null:
        push_error("Starter visual bake did not load")
        quit(1)
        return
    var instance_started := Time.get_ticks_usec()
    var instance := packed.instantiate()
    root.add_child(instance)
    var instance_ms := float(Time.get_ticks_usec() - instance_started) / 1000.0
    await process_frame
    await process_frame
    var tree_registry: Array = instance.get_node("PropsRoot").get_meta("harvestable_tree_registry", [])
    var rock_registry: Array = instance.get_node("PropsRoot").get_meta("mineable_rock_registry", [])
    var unresolved_parts := 0
    for registry in [tree_registry, rock_registry]:
        for item in registry:
            for part in item.get("batched_parts", [item.get("batched_part", {})]):
                if part is Dictionary and part.has("instance") and not part.instance is NodePath:
                    unresolved_parts += 1
    print("STARTING_WORLD_VISUAL_BAKE_BENCHMARK|load_ms=%.1f|instance_ms=%.1f|nodes=%d|trees=%d|rocks=%d|bad_encoded_refs=%d" % [load_ms, instance_ms, _count_nodes(instance), tree_registry.size(), rock_registry.size(), unresolved_parts])
    quit()


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count
