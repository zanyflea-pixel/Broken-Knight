extends SceneTree

const KIT := preload("res://assets/world/mineable_geology_kit_v1.glb")
const WorldPreviewBuilder := preload("res://scripts/world/WorldPreviewBuilder.gd")
const ZONES := [
    "starting_realm", "north_frontier", "glacial_range", "western_reaches",
    "stormbreak_highlands", "skeld_coast", "east_marches",
]
const EXPECTED := [
    "IronOutcropIntact", "CopperOutcropIntact", "SilverOutcropIntact", "GoldOutcropIntact",
    "IronOutcropDepleted", "CopperOutcropDepleted", "SilverOutcropDepleted", "GoldOutcropDepleted",
]


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var failures: Array[String] = []
    var source := KIT.instantiate()
    var surface_total := 0
    var intact_extents: Array[Vector3] = []
    for mesh_name in EXPECTED:
        var mesh := _find_mesh(source, mesh_name)
        if mesh == null:
            failures.append("mineable kit missing %s" % mesh_name)
            continue
        surface_total += mesh.get_surface_count()
        if mesh_name.ends_with("Intact"):
            intact_extents.append(mesh.get_aabb().size)
    source.free()
    if intact_extents.size() != 4:
        failures.append("intact ore-family silhouettes are incomplete")
    elif intact_extents[0].distance_to(intact_extents[1]) < 0.08 and intact_extents[1].distance_to(intact_extents[2]) < 0.08:
        failures.append("ore families reverted to one duplicated silhouette")

    var atlas_rocks := 0
    var zone_counts: Dictionary = {}
    for zone_id in ZONES:
        var bake_path := WorldPreviewBuilder.STARTING_VISUAL_BAKE_PATH if zone_id == "starting_realm" else WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
        var packed := load(bake_path) as PackedScene
        if packed == null:
            failures.append("%s visual bake is missing" % zone_id)
            continue
        var bake := packed.instantiate()
        root.add_child(bake)
        var props := bake.get_node_or_null("PropsRoot")
        var registry: Array = props.get_meta("mineable_rock_registry", []) if props != null else []
        zone_counts[zone_id] = registry.size()
        atlas_rocks += registry.size()
        if registry.is_empty():
            failures.append("%s bake has no mineable geology" % zone_id)
        for rock_value in registry:
            if not rock_value is Dictionary:
                continue
            if not (rock_value.get("depleted_mesh") is Mesh and rock_value.get("depleted_transform") is Transform3D):
                failures.append("%s bake contains a rock without a break state" % zone_id)
                break
        bake.free()

    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.auto_boot_enabled = false
    root.add_child(main)
    await main.boot_world(Callable(), false, true)
    var hero: Node = main.get_node("Player")
    var director: Node = main.get_node("GameplayDirector")
    var rocks: Array = director.get("_mineable_rocks")
    var ore_families: Dictionary = {}
    var break_ready := 0
    for rock_value in rocks:
        if not rock_value is Dictionary:
            continue
        var rock: Dictionary = rock_value
        ore_families[str(rock.get("ore_id", ""))] = true
        if rock.get("depleted_mesh") is Mesh and rock.get("depleted_transform") is Transform3D:
            break_ready += 1
    if ore_families.size() != 4:
        failures.append("world does not contain all four ore families")
    if break_ready != rocks.size():
        failures.append("not every mineable rock carries its authored break state")
    if rocks.size() < 2:
        failures.append("not enough rocks to test isolated break behavior")
    else:
        hero.equip_item_id("starter_pickaxe")
        var target: Dictionary = rocks[0]
        var neighbor: Dictionary = rocks[1]
        var loot_before: int = director.get("loot").size()
        director.call("_activate_world_rock", target)
        director.call("_activate_world_rock", target)
        director.call("_activate_world_rock", target)
        if target.get("active", true):
            failures.append("mined target remained active")
        var remnant := target.get("depleted_node") as MeshInstance3D
        if not is_instance_valid(remnant) or not remnant.get_meta("mineable_depleted_state", false):
            failures.append("authored depleted remnant did not replace the intact rock")
        elif remnant.mesh != target.get("depleted_mesh"):
            failures.append("depleted remnant uses the wrong ore-family mesh")
        var target_part: Dictionary = target.get("batched_part", {})
        if not _part_is_hidden(target_part):
            failures.append("intact target remained visible beneath its broken state")
        if not neighbor.get("active", true) or _part_is_hidden(neighbor.get("batched_part", {})):
            failures.append("mining one rock hid a neighboring rock")
        if director.get("loot").size() < loot_before + 2:
            failures.append("authored break state lost ore/stone ground drops")
        director.call("_remove_authored_depleted_rock", target)
        target.active = true
        target.hits = 0
        director.call("_set_world_rock_visible", target, true)

    print("MINEABLE_GEOLOGY_BREAK_STATES|kit_meshes=%d|surfaces=%d|atlas_rocks=%d|zones=%s|active_rocks=%d|break_ready=%d|ore_families=%s|failures=%d" % [
        EXPECTED.size(), surface_total, atlas_rocks, str(zone_counts), rocks.size(), break_ready, str(ore_families.keys()), failures.size(),
    ])
    for failure in failures:
        push_error("MINEABLE_GEOLOGY_FAILURE|%s" % failure)
    main.free()
    await process_frame
    quit(0 if failures.is_empty() else 1)


func _part_is_hidden(part: Dictionary) -> bool:
    var instance := part.get("instance") as MultiMeshInstance3D
    var index := int(part.get("index", -1))
    if not is_instance_valid(instance) or instance.multimesh == null or index < 0:
        return true
    # The runtime intentionally writes the packed MultiMesh buffer because
    # some render backends defer get_instance_transform() after direct edits.
    var multimesh := instance.multimesh
    var stride := 12 + (4 if multimesh.use_colors else 0) + (4 if multimesh.use_custom_data else 0)
    var offset := index * stride
    var buffer := multimesh.buffer
    if offset + 10 >= buffer.size():
        return true
    var basis := Basis(
        Vector3(buffer[offset + 0], buffer[offset + 4], buffer[offset + 8]),
        Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
        Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])
    )
    return absf(basis.determinant()) < 0.000001


func _find_mesh(node: Node, target: String) -> Mesh:
    if node is MeshInstance3D and str(node.name) == target:
        return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var found := _find_mesh(child, target)
        if found != null:
            return found
    return null
