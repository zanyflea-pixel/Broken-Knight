extends SceneTree

var failures:Array[String]=[]


func _init()->void:
    call_deferred("_run")


func _check(condition:bool,label:String)->void:
    if condition:return
    failures.append(label)
    push_error("RPG_EXPANSION_FAIL|%s"%label)


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var player:Node=main.get_node("Player")
    var director:Node=main.get_node("GameplayDirector")

    main._set_admin_menu(true)
    _check(paused,"g_menu_pauses")
    main._open_collection_menu(main.get_node("UI/QuestMenu"))
    main._set_admin_menu(false)
    _check(paused,"overlapping_menu_stays_paused")
    main._close_collection_menu()
    _check(not paused,"last_menu_close_unpauses")
    main._open_crafting_menu({"name":"Verifier Forge","type":"forge"})
    _check(paused and main.get_node("UI/CraftingMenu").visible,"crafting_pauses")
    main._close_crafting_menu()

    var recipes:Array=director.get_recipes()
    _check(recipes.size()>=24,"recipe_catalog_is_large")
    for material_kind in ["herbs","logs","ore","scrap","leather","cloth","stone","resin","mushrooms","crystal","essence"]:
        player.add_material(material_kind,100)
    var bag_before:int=player.bag_slots.size()
    var craft_result:String=director.craft_recipe("oak_shield")
    _check(not craft_result.contains("Missing"),"craft_succeeds")
    _check(player.bag_slots.size()==bag_before+1,"crafted_item_enters_bag")

    var interactions:Array=director.get("_interactables")
    var interaction_counts:={"craft":0,"gather":0,"chop":0}
    for interaction in interactions:
        var action:String=str(interaction.get("action",""))
        if interaction_counts.has(action):interaction_counts[action]=int(interaction_counts[action])+1
    _check(interaction_counts.craft>=5,"town_crafting_stations_exist")
    _check(interaction_counts.gather>=80,"world_material_nodes_exist")
    var world_tree_count:int=director.get("_forest_trees").size()
    _check(interaction_counts.chop==0,"duplicate_harvest_tree_layer_removed")
    _check(world_tree_count>=1000,"choppable_world_trees_exist")

    var portals:Array=director.get("_portals")
    var key_count:=0
    var gate_count:=0
    var chest_count:=0
    for portal in portals:
        match str(portal.get("action","")):
            "dungeon_key":key_count+=1
            "dungeon_door":gate_count+=1
            "chest":chest_count+=1
    _check(key_count>=3,"dungeon_keys_exist")
    _check(gate_count>=3,"locked_dungeon_gates_exist")
    _check(chest_count>=2,"dungeon_reward_chests_exist")
    _check(director.get_quest_state().size()>=6,"quest_lines_exist")

    var torch_count:=main.find_children("*Torch*","Node3D",true,false).size()+main.find_children("*Torch*","OmniLight3D",true,false).size()
    _check(torch_count>=8,"dark_spaces_have_torches")
    var crest_count:=main.find_children("*Crest*","Node3D",true,false).size()+main.find_children("*Crest*","MeshInstance3D",true,false).size()
    _check(crest_count>=3,"world_crests_exist")

    print("RPG_EXPANSION_PASS|recipes=%d|craft=%d|gather=%d|trees=%d|keys=%d|gates=%d|chests=%d|torches=%d|crests=%d|failures=%d"%[
        recipes.size(),interaction_counts.craft,interaction_counts.gather,world_tree_count,key_count,gate_count,chest_count,torch_count,crest_count,failures.size()
    ])
    main.free()
    quit(0 if failures.is_empty() else 14)
