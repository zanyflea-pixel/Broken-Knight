extends SceneTree

const FISHING_MAX_CAST_TEST_DISTANCE:=30.0

func _init()->void:call_deferred("_run")

func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate();root.add_child(main)
    await process_frame;await process_frame;await physics_frame
    var hero:Node=main.get_node("Player");var director:Node=main.get_node("GameplayDirector")
    var axe_found:=false;var pole_found:=false
    for item in hero.bag_slots:
        if item.get("id","")=="starter_wood_axe":axe_found=item.get("name","")=="Axe"
        if item.get("id","")=="starter_fishing_pole":pole_found=item.get("name","")=="Fishing Pole"
    if not axe_found:failures.append("starter axe missing or incorrectly named")
    if not pole_found:failures.append("fishing pole missing or incorrectly named")
    var interactions:Array=director.get("_interactables")
    var fish_spots:=interactions.filter(func(data):return data.get("action","")=="fish")
    var berry_spots:=interactions.filter(func(data):return data.get("action","")=="forage_food")
    var secrets:=interactions.filter(func(data):return data.get("action","")=="secret_wall")
    if fish_spots.size()<3:failures.append("fishing spots missing")
    if berry_spots.size()<12:failures.append("berry patches missing")
    if secrets.size()<3:failures.append("dungeon secrets missing")
    hero.equip_item_id("starter_fishing_pole")
    if not hero.has_fishing_pole_equipped():failures.append("fishing pole failed to equip")
    var river:Dictionary=main.get("_active_profile").get("river_corridors",[])[0]
    var river_points:Array=river.points
    var bank_index:=river_points.size()/2
    var bank_tangent:=(Vector2(river_points[bank_index+1])-Vector2(river_points[bank_index-1])).normalized()
    var bank_normal:=Vector2(-bank_tangent.y,bank_tangent.x)
    var bank_point:Vector2=river_points[bank_index]+bank_normal*float(river.width)*.42
    hero.global_position=main.get("_world_result").height_sampler.call(bank_point.x,bank_point.y)
    director.call("_tick_vendor")
    var natural_fish:Dictionary=director.get("_nearby_interactable")
    if natural_fish.get("action","")!="fish" or not str(director.nearby_vendor).contains("Cast into river"):failures.append("natural river fishing prompt missing")
    var pond:Dictionary=main.get("_active_profile").get("pond_sites",[])[0]
    var pond_center:=Vector2(pond.position)
    var pond_angle:=0.0
    var pond_base_radius:=float(pond.radius)*1.18
    var pond_irregularity:=1.0+sin(pond_angle*3.0+pond_center.x*.0017)*.11+sin(pond_angle*7.0+pond_center.y*.0011)*.055
    var pond_point:Vector2=pond_center+Vector2.RIGHT*pond_base_radius*pond_irregularity
    hero.global_position=main.get("_world_result").height_sampler.call(pond_point.x,pond_point.y)
    director.call("_tick_vendor")
    var pond_fish:Dictionary=director.get("_nearby_interactable")
    if pond_fish.get("action","")!="fish" or not str(director.nearby_vendor).contains("Cast into pond"):failures.append("natural pond fishing prompt missing")
    var explicit_spot:Dictionary=fish_spots[0]
    hero.global_position=explicit_spot.get("position",Vector3.ZERO)
    if not director.call("_can_cast_fishing",explicit_spot):failures.append("fishing rejected at the authored shoreline")
    hero.global_position+=Vector3(FISHING_MAX_CAST_TEST_DISTANCE,0,0)
    if director.call("_can_cast_fishing",explicit_spot):failures.append("fishing remained available too far from water")
    hero.global_position=explicit_spot.get("position",Vector3.ZERO)
    director.call("_activate_interactable",explicit_spot)
    director.set("_fishing_timer",0.0)
    director.call("_tick_fishing",.1)
    if director.get("_fishing_phase")!="bite":failures.append("fishing bite phase did not begin")
    director.call("_reel_fishing")
    var raw_fish_found:=false
    for item in hero.bag_slots:
        if item.get("stack_key","")=="item:raw_fish":raw_fish_found=true
    if not raw_fish_found:failures.append("reeling did not add raw fish to bag")
    if not director.can_craft_recipe(director.get_recipes()[-1]):failures.append("raw fish not accepted by cooking")
    var craft_result:String=director.craft_recipe("cooked_fish")
    if not craft_result.begins_with("Crafted"):failures.append("cooked fish recipe failed")
    var cooked_id:=""
    for item in hero.bag_slots:
        if str(item.get("id","")).begins_with("cooked_fish"):cooked_id=item.id;break
    if cooked_id.is_empty():failures.append("cooked fish missing from bag")
    else:
        hero.use_bag_item_id(cooked_id)
        if hero.food_power_bonus<8:failures.append("cooked food buff not applied")
    hero.set_interior_mode(true);hero.global_position=Vector3(8000,-82,54)
    director.call("_stream_local_gameplay");await physics_frame
    var test_minion:={"bounds":Rect2(Vector2(7960,-64),Vector2(80,128))}
    var blocked:bool=not director.call("_dungeon_step_allowed",test_minion,Vector3(8000,-82,54),Vector3(8006,-82,54))
    if not blocked:failures.append("dungeon wall movement probe was not blocked")
    print("SYSTEM_PASS|fish_spots=%d|river_prompt=%s|pond_prompt=%s|berries=%d|secrets=%d|wall_blocked=%s|buff=%d|failures=%d"%[fish_spots.size(),natural_fish.get("action","")=="fish",pond_fish.get("action","")=="fish",berry_spots.size(),secrets.size(),blocked,hero.food_power_bonus,failures.size()])
    for failure in failures:push_error("SYSTEM_PASS_FAILURE|%s"%failure)
    main.free();quit(1 if not failures.is_empty() else 0)
