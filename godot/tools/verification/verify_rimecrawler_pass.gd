extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const RIMECRAWLER_SCENE:PackedScene=preload("res://assets/enemies/rimecrawler_v1.glb")
const RIME_CHITIN_SCENE:PackedScene=preload("res://assets/items/rime_chitin_pickup_v1.glb")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]

    var crawler:=RIMECRAWLER_SCENE.instantiate() as Node3D
    if crawler==null:
        failures.append("Rimecrawler Blender scene failed to instantiate")
    else:
        for side in ["L","R"]:
            for leg_index in range(3):
                if crawler.find_child("LegPivot_%s%d"%[side,leg_index],true,false)==null:
                    failures.append("Rimecrawler is missing LegPivot_%s%d"%[side,leg_index])
        if crawler.find_child("Thorax",true,false)==null:failures.append("Rimecrawler thorax animation pivot is missing")
        if crawler.find_child("Mandible_L",true,false)==null or crawler.find_child("Mandible_R",true,false)==null:
            failures.append("Rimecrawler mandible animation pivots are missing")
        crawler.free()

    var chitin_pickup:=RIME_CHITIN_SCENE.instantiate() as Node3D
    if chitin_pickup==null:
        failures.append("Rime Chitin pickup scene failed to instantiate")
    else:
        if chitin_pickup.find_child("BroadCarapacePlate",true,false)==null or chitin_pickup.find_child("FrostVein",true,false)==null:
            failures.append("Rime Chitin pickup does not use its authored carapace visual")
        chitin_pickup.free()

    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_glacial_region_loaded()
    main._prepare_gameplay_region_for_position(-15000.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame

    var gameplay:=main.get_node("GameplayDirector")
    var player:=main.get_node("Player")
    var context:Dictionary=main.get("_region_contexts").get("glacial_range",{})
    var region_root:Node3D=context.get("root")
    var props_root:Node=region_root.get_node_or_null("PropsRoot") if is_instance_valid(region_root) else null
    var nest_nodes:Array=props_root.find_children("RimecrawlerNest*","MeshInstance3D",true,false) if is_instance_valid(props_root) else []
    if nest_nodes.size()<2:failures.append("Only %d of 2 authored Rimecrawler nesting grounds were built"%nest_nodes.size())
    var collidable_nests:=0
    for nest in nest_nodes:
        if not nest.find_children("*","StaticBody3D",true,false).is_empty():collidable_nests+=1
    if collidable_nests<nest_nodes.size():failures.append("A Rimecrawler nest lacks physical collision")
    var crawler_count:=0
    var collision_count:=0
    for enemy in gameplay.get("minions"):
        if str(enemy.get("kind",""))!="rimecrawler":continue
        crawler_count+=1
        var enemy_node:Node3D=enemy.get("node")
        if is_instance_valid(enemy_node) and enemy_node.find_child("RimecrawlerCollision",true,false)!=null:collision_count+=1
        gameplay._animate_rimecrawler(enemy,true)
    if crawler_count<7:failures.append("Only %d of 7 authored Rimecrawlers spawned"%crawler_count)
    if collision_count!=crawler_count:failures.append("%d Rimecrawlers lack physical collision"%(crawler_count-collision_count))

    var claimed:Dictionary=gameplay.get("_quest_claimed")
    claimed["elite_hunt"]=true
    gameplay.set("_quest_claimed",claimed)
    gameplay.get_quest_state()
    var counters:Dictionary=gameplay.get("_gathered_counts")
    counters["rimecrawlers"]=5
    gameplay.set("_gathered_counts",counters)
    gameplay._check_quest_rewards()
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("rimecrawler_hunt",false)):failures.append("Icewatch Rimecrawler hunt did not complete at five kills")
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("id",""))=="icewatch_signet"):
        failures.append("Icewatch hunt did not award its unique signet")

    var starting_chitin:int=player.get_material_amount("chitin")
    player.add_material("chitin",4)
    if player.get_material_amount("chitin")!=starting_chitin+4:failures.append("Rime Chitin material count did not increase")
    var chitin_stacks:=0
    for item in player.bag_slots:
        if str(item.get("material",""))=="chitin":
            chitin_stacks+=1
            if int(item.get("quantity",0))!=starting_chitin+4:failures.append("Rime Chitin bag quantity did not synchronize")
    if chitin_stacks!=1:failures.append("Rime Chitin should occupy one stacking bag slot, found %d"%chitin_stacks)

    player.add_material("crystal",2)
    player.add_material("leather",2)
    var craft_result:String=gameplay.craft_recipe("rimecrawler_bracers")
    if not craft_result.begins_with("Crafted "):failures.append("Rimecrawler Bracers recipe failed: %s"%craft_result)
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("name",""))=="Rimecrawler Bracers"):
        failures.append("Crafted Rimecrawler Bracers were not placed in the bag")
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("last_light_armor",false)):failures.append("Last Light armor quest did not complete from the regional recipe")

    gameplay._spawn_world_drop(player.global_position+Vector3(2,0,0),{"kind":"material","material":"chitin","amount":1,"name":"Verifier Rime Chitin"},false)
    var loot_entries:Array=gameplay.get("loot")
    var last_drop:Dictionary=loot_entries[-1] if not loot_entries.is_empty() else {}
    var drop_node:Node3D=last_drop.get("node")
    if not is_instance_valid(drop_node) or drop_node.find_child("RimeChitinPickup",true,false)==null:
        failures.append("Dropped Rime Chitin did not use the grounded Blender pickup")
    if not bool(last_drop.get("grounded",false)):failures.append("Rime Chitin pickup is still configured to spin or bob")

    print("RIMECRAWLER_PASS|spawned=%d|colliders=%d|nests=%d|chitin_stacks=%d|crafted=%s|quests=%s|failures=%d"%[
        crawler_count,collision_count,nest_nodes.size(),chitin_stacks,str(craft_result.begins_with("Crafted ")).to_lower(),
        str(bool(claimed.get("rimecrawler_hunt",false)) and bool(claimed.get("last_light_armor",false))).to_lower(),failures.size(),
    ])
    for failure in failures:push_error("RIMECRAWLER_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
