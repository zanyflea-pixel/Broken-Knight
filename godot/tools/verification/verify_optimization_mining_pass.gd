extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await physics_frame
    var hero:Node=main.get_node("Player")
    var director:Node=main.get_node("GameplayDirector")
    var profile:Dictionary=main.get("_active_profile")
    var props:Node=main.get_node("WorldRoot/PropsRoot")

    # The three local paths that previously began near roads now share exact
    # authored junctions with those roads.
    var expected_connections:={
        "Riverwatch Trail":Vector2(-420,70),
        "North Meadow Trail":Vector2(-435,150),
        "South Heath Trail":Vector2(650,-460),
    }
    for trail in profile.get("trail_corridors",[]):
        var name:=str(trail.get("name",""))
        if expected_connections.has(name) and Vector2(trail.points[0]).distance_to(expected_connections[name])>.01:
            failures.append("%s is not tied into its road"%name)

    # Exercise multiple irregular pond lobes, not only the old circular east
    # test point.
    hero.equip_item_id("starter_fishing_pole")
    var pond:Dictionary=profile.get("pond_sites",[])[0]
    var pond_center:Vector2=pond.position
    for angle in [0.0,1.4,3.1,4.8]:
        var irregularity:=1.0+sin(angle*3.0+pond_center.x*.0017)*.11+sin(angle*7.0+pond_center.y*.0011)*.055
        var edge:=float(pond.radius)*1.18*irregularity
        var point:=pond_center+Vector2(cos(angle),sin(angle))*(edge+5.0)
        hero.global_position=main.get("_world_result").height_sampler.call(point.x,point.y)
        var fish:Dictionary=director.call("_natural_fishing_interaction")
        if fish.get("action","")!="fish" or not str(fish.get("label","")).contains("Cast into pond"):
            failures.append("pond prompt missing at angle %.1f"%angle)

    # I-menu hand equipment must use the equipped item, including a true torch
    # instead of leaving the staff visible.
    hero.equip_item_id("royal_vanguard_sword")
    hero.equip_item_id("royal_vanguard_shield")
    var menu:Control=main.get_node("UI/HeroMenu")
    menu.refresh()
    var sword_visible:=_variant_visible(menu,"royal_vanguard_sword")
    var shield_visible:=_variant_visible(menu,"royal_vanguard_shield")
    if not sword_visible:failures.append("I-menu sword preview missing")
    if not shield_visible:failures.append("I-menu shield preview missing")
    hero.equip_item_id("traveler_torch")
    menu.refresh()
    var torch_visible:=_variant_visible(menu,"traveler_torch")
    var staff_visible:=_variant_visible(menu,"royal_vanguard_staff")
    if not torch_visible:failures.append("I-menu torch preview missing")
    if staff_visible:failures.append("staff remained visible while torch equipped")

    # New leaf tufts must have meaningful vertical volume.
    var preview_builder:RefCounted=load("res://scripts/world/WorldPreviewBuilder.gd").new()
    var grass_mesh:ArrayMesh=preview_builder.call("_make_ground_cover_mesh")
    if grass_mesh.get_aabb().size.y<.26:failures.append("grass remained flat")
    var meadow_count:int=props.get_meta("meadow_grass_count",0)
    var leaf_litter_count:int=props.get_meta("leaf_litter_count",0)
    if meadow_count<40000:failures.append("green-biome grass coverage is too sparse")
    if leaf_litter_count<1000:failures.append("forest leaf litter is missing")
    var clustered_tree_found:=false
    for tree in props.get_meta("harvestable_tree_registry",[]):
        if tree.get("kind","")=="broadleaf" and tree.get("batched_parts",[]).size()>=3:
            clustered_tree_found=true
            break
    if not clustered_tree_found:failures.append("irregular broadleaf crown clusters are missing")
    var bush_count:=0
    for prop in props.get_meta("collision_prop_registry",[]):
        if prop.get("kind","")=="bush":bush_count+=1
    if bush_count<1000:failures.append("built-up bush population missing")

    # Fence visuals now have matching continuous collision segments.
    var fence_collision:StaticBody3D=main.get_node_or_null("WorldRoot/TownRoot/DetailCollision")
    var fence_collision_count:=fence_collision.get_child_count() if fence_collision else 0
    if fence_collision_count<120:failures.append("field fence collision segments missing")

    # Prop collision lookup is spatially bucketed instead of rescanning every
    # bush and rock each streaming tick.
    var registry:Array=director.get("_rock_collision_registry")
    var bucket_count:int=director.get("_prop_collision_buckets").size()
    if bucket_count<=0 or bucket_count>=registry.size():failures.append("prop collision spatial buckets missing")

    # Mine a real batched world rock, verify it disappears and produces manual
    # ore/stone pickups.
    var pickaxe_found:=false
    for item in hero.bag_slots:
        if item.get("id","")=="starter_pickaxe":pickaxe_found=true
    if not pickaxe_found:failures.append("starter Pickaxe missing")
    hero.equip_item_id("starter_pickaxe")
    menu.refresh()
    if not _variant_visible(menu,"starter_pickaxe"):failures.append("I-menu Pickaxe preview missing")
    var rocks:Array=director.get("_mineable_rocks")
    if rocks.is_empty():
        failures.append("mineable rock registry missing")
    else:
        var rock:Dictionary=rocks[0]
        var loot_before:int=director.loot.size()
        director.call("_activate_world_rock",rock)
        director.call("_activate_world_rock",rock)
        director.call("_activate_world_rock",rock)
        if rock.get("active",true):failures.append("mined rock did not break")
        if director.loot.size()<loot_before+2:failures.append("mined rock did not drop ore and stone")

    var controller_source:=FileAccess.get_file_as_string("res://scripts/HeroController.gd")
    if controller_source.contains("translated(Vector3.UP * 0.72)"):failures.append("unconditional prop-climbing step remains")

    print("OPTIMIZATION_MINING|paths=%d|pond_angles=4|sword=%s|shield=%s|torch=%s|grass_height=%.2f|meadow_grass=%d|leaf_litter=%d|clustered_tree=%s|bushes=%d|fence_shapes=%d|prop_buckets=%d|rocks=%d|failures=%d"%[
        expected_connections.size(),sword_visible,shield_visible,torch_visible,grass_mesh.get_aabb().size.y,meadow_count,leaf_litter_count,clustered_tree_found,bush_count,fence_collision_count,bucket_count,rocks.size(),failures.size()
    ])
    for failure in failures:push_error("OPTIMIZATION_MINING_FAILURE|%s"%failure)
    main.free()
    quit(1 if not failures.is_empty() else 0)


func _variant_visible(menu:Control,item_id:String)->bool:
    for node_value in menu.portrait_item_variants.get(item_id,[]):
        var node:=node_value as Node3D
        if is_instance_valid(node) and node.visible:return true
    return false
