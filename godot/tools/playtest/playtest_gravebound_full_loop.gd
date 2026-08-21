extends SceneTree

## Rendered, end-to-end acceptance playthrough for The Bell Beneath Barrowfen.
## This deliberately drives the real Main scene, real interaction input, real
## Warrior abilities and manual E pickups. It fast-forwards long road travel so
## the authored 30–45 minute route can be regression-tested in under a minute.

var failures:Array[String]=[]
var frame_samples:Array[float]=[]
var fought_variants:Dictionary={}
var ability_hits:=0
var manual_pickups:=0
var main:Node3D
var player:CharacterBody3D
var director:Node
var campaign:Node


func _initialize()->void:
    call_deferred("_run")


func _check(condition:bool,label:String)->void:
    if condition:return
    failures.append(label)
    push_error("GRAVEBOUND_DESKTOP_FAIL|%s"%label)


func _story(story_id:String,index:=-1)->Dictionary:
    for interaction in campaign.get("_story_interactions"):
        if str(interaction.get("story_id",""))==story_id and (index<0 or int(interaction.get("index",-1))==index):
            return interaction
    return {}


func _render_frame()->void:
    var started:=Time.get_ticks_usec()
    await process_frame
    await RenderingServer.frame_post_draw
    frame_samples.append(float(Time.get_ticks_usec()-started)/1000.0)


func _settle(frames:=3)->void:
    for _index in range(frames):await _render_frame()


func _tap_key(keycode:Key)->void:
    var event:=InputEventKey.new()
    event.keycode=keycode;event.physical_keycode=keycode;event.pressed=true
    Input.parse_input_event(event)
    await _render_frame()
    event=InputEventKey.new()
    event.keycode=keycode;event.physical_keycode=keycode;event.pressed=false
    Input.parse_input_event(event)
    await _render_frame()


func _place_at(position:Vector3,interior:=false)->void:
    player.set_interior_mode(interior)
    player.global_position=position+Vector3.UP*.08
    player.velocity=Vector3.ZERO
    await _settle(3)


func _travel_surface(target:Vector2,steps:=18)->void:
    player.set_interior_mode(false)
    var start:=Vector2(player.global_position.x,player.global_position.z)
    for index in range(1,steps+1):
        var point:=start.lerp(target,float(index)/float(steps))
        player.global_position=director._ground(Vector3(point.x,0,point.y))+Vector3.UP*.08
        player.velocity=Vector3.ZERO
        await _render_frame()


func _interact_story(story_id:String,index:=-1)->void:
    var interaction:=_story(story_id,index)
    _check(not interaction.is_empty(),"interaction_%s_%d_exists"%[story_id,index])
    if interaction.is_empty():return
    var position:Vector3=interaction.get("position",Vector3.ZERO)
    if position.x<8600.0:await _travel_surface(Vector2(position.x,position.z),8)
    else:await _place_at(position,true)
    director._tick_vendor()
    await _tap_key(KEY_E)
    await _settle(3)


func _living(encounter_id:String)->Array[Dictionary]:
    var result:Array[Dictionary]=[]
    for enemy in director.minions:
        if not is_instance_valid(enemy.get("node")) or bool(enemy.get("dead",false)):continue
        if encounter_id.is_empty() or str(enemy.get("encounter_id",""))==encounter_id:result.append(enemy)
    return result


func _aim_at(enemy:Dictionary)->void:
    var enemy_position:Vector3=enemy.node.global_position
    var direction:=Vector3(enemy_position.x-player.global_position.x,0,enemy_position.z-player.global_position.z).normalized()
    var visual:=player.get_node("Visual") as Node3D
    visual.rotation.y=atan2(direction.x,direction.z)


func _fight_encounter(encounter_id:String,max_attacks:=120)->void:
    var attacks:=0
    var used_support_abilities:=false
    while not _living(encounter_id).is_empty() and attacks<max_attacks:
        var enemy:Dictionary=_living(encounter_id)[0]
        var enemy_position:Vector3=enemy.node.global_position
        var offset:=Vector3(0,0,2.55)
        var combat_position:=enemy_position+offset
        if bool(enemy.get("dungeon",false)):
            combat_position.y=float(enemy.get("floor_y",enemy_position.y))
            await _place_at(combat_position,true)
        else:
            await _place_at(director._ground(combat_position),false)
        _aim_at(enemy)
        player.hp=player.max_hp;player.stamina=player.max_stamina
        director.set("cooldowns",[0.0,0.0,0.0,0.0])
        var hp_before:float=float(enemy.get("hp",0.0))
        if not used_support_abilities:
            await _tap_key(KEY_2)
            await _settle(3)
            used_support_abilities=true
        else:
            await _tap_key(KEY_1)
            await _settle(15)
        var hp_after:float=float(enemy.get("hp",0.0))
        if hp_after<hp_before:
            ability_hits+=1
            fought_variants[str(enemy.get("zombie_variant","unknown"))]=true
        else:
            _check(false,"real_ability_hit_%s"%str(enemy.get("zombie_variant","unknown")))
            # Keep the playthrough moving so later systems still get exercised.
            director._damage(enemy,48.0,Vector3.FORWARD)
        attacks+=1
    _check(_living(encounter_id).is_empty(),"encounter_%s_cleared"%encounter_id)
    await _settle(4)


func _fight_champion()->void:
    var attacks:=0
    while not _living("ossuary_champion").is_empty() and attacks<80:
        var enemy:Dictionary=_living("ossuary_champion")[0]
        var enemy_position:Vector3=enemy.node.global_position
        await _place_at(Vector3(enemy_position.x,enemy_position.y,enemy_position.z+2.65),true)
        _aim_at(enemy)
        player.hp=player.max_hp;player.stamina=player.max_stamina
        director.set("cooldowns",[0.0,0.0,0.0,0.0])
        var hp_before:float=float(enemy.hp)
        await _tap_key(KEY_1 if attacks%5 else KEY_4)
        await _settle(16)
        if float(enemy.hp)<hp_before:
            ability_hits+=1;fought_variants["champion"]=true
        else:
            _check(false,"champion_ability_hit_%d"%attacks)
            director._damage(enemy,48.0,Vector3.FORWARD)
        attacks+=1
    _check(_living("ossuary_champion").is_empty(),"champion_defeated")
    if not _living("champion_reinforcements").is_empty():await _fight_encounter("champion_reinforcements",60)


func _collect_all_visible_loot()->void:
    var safety:=0
    while not director.loot.is_empty() and safety<180:
        var dropped:Dictionary=director.loot[0]
        var node:=dropped.get("node") as Node3D
        if not is_instance_valid(node):
            director.loot.remove_at(0);continue
        var interior:=node.global_position.x>8600.0
        await _place_at(node.global_position,interior)
        director._tick_vendor()
        var before:int=director.loot.size()
        await _tap_key(KEY_E)
        if director.loot.size()<before:manual_pickups+=1
        else:
            _check(false,"manual_loot_pickup_%d"%safety)
            director._collect_nearby_loot()
        safety+=1
    _check(director.loot.is_empty(),"all_visible_loot_collected")


func _test_map_and_menu()->void:
    _check(main.get_node("UI/Minimap").visible,"minimap_visible_during_play")
    await _tap_key(KEY_M)
    _check(main.get_node("UI/WorldMap").visible and paused,"world_map_opens_and_pauses")
    _check(director.get_story_map_markers().size()>=3,"story_markers_on_map")
    await _tap_key(KEY_ESCAPE)
    _check(not main.get_node("UI/WorldMap").visible and not paused,"escape_closes_map_and_resumes")


func _test_vendor()->void:
    var vendors:Array=director.get("_vendors")
    _check(not vendors.is_empty(),"town_vendors_exist")
    if vendors.is_empty():return
    var vendor:=vendors[0] as Node3D
    await _travel_surface(Vector2(vendor.global_position.x,vendor.global_position.z),8)
    director._tick_vendor()
    await _tap_key(KEY_E)
    _check(main.get_node("UI/VendorMenu").visible and paused,"vendor_menu_opens_and_pauses")
    var vendor_data:Dictionary=vendor.get_meta("vendor_data")
    var gold_before:int=player.hero_gold
    var result:String=director.purchase_vendor_item(vendor_data,0)
    _check(not result.begins_with("Need") and player.hero_gold<gold_before,"earned_gold_buys_town_goods")
    await _tap_key(KEY_ESCAPE)
    _check(not paused,"vendor_menu_escape_resumes")


func _save_screenshot()->void:
    await _settle(5)
    var path:=ProjectSettings.globalize_path("res://artifacts/gravebound_full_playthrough.png")
    var error:=root.get_texture().get_image().save_png(path)
    print("GRAVEBOUND_DESKTOP_CAPTURE|path=%s|error=%d"%[path,error])


func _run()->void:
    OS.set_environment("BROKEN_KNIGHT_TEST_MODE","1")
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    DisplayServer.window_set_title("Broken Knight — Gravebound Acceptance Playthrough")
    Engine.max_fps=60
    main=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    player=main.get_node("Player") as CharacterBody3D
    director=main.get_node("GameplayDirector")
    campaign=director.get("_gravebound_campaign")
    player.equip_royal_armor()
    _check(is_instance_valid(campaign),"campaign_runtime_created")
    _check(player.is_warrior() and player.has_warrior_weapons_equipped(),"warrior_loadout_ready")
    _check(int(campaign.get("stage"))==0,"fresh_story_opening")
    _check(str(director.get_gameplay_state().get("quest",""))=="The Bell Beneath Barrowfen","opening_quest_tracker")
    await _test_map_and_menu()

    # First minute: Captain, bridge road and the lost courier.
    await _interact_story("captain")
    _check(int(campaign.stage)==1,"captain_starts_story")
    await _interact_story("wagon")
    _check(int(campaign.stage)==2 and _living("courier_ambush").size()==5,"courier_ambush_authored")
    await _fight_encounter("courier_ambush")
    await _collect_all_visible_loot()
    _check(int(campaign.stage)==3,"ambush_advances_to_farm")

    # Farm rescue and useful optional cache.
    await _travel_surface(Vector2(-90,-493),20)
    await _settle(5)
    if not _living("farm_dead").is_empty():await _fight_encounter("farm_dead")
    await _collect_all_visible_loot()
    await _interact_story("scout")
    _check(int(campaign.stage)==4 and bool(campaign.side_progress.scout),"scout_rescued")
    await _interact_story("hidden_cache")
    _check(bool(campaign.side_progress.cache),"courier_cache_found")

    # Graveyard patrol, gathering, pyres and all three ward seals.
    await _travel_surface(Vector2(252,-624),22)
    await _settle(5)
    if not _living("grave_patrol").is_empty():await _fight_encounter("grave_patrol")
    await _collect_all_visible_loot()
    for index in range(5):await _interact_story("gravebloom",index)
    for index in range(3):await _interact_story("cleansing_pyre",index)
    for index in range(3):
        await _interact_story("grave_seal",index)
        await _fight_encounter("seal_%d"%index)
        await _collect_all_visible_loot()
    _check(int(campaign.stage)==5 and int(campaign.seals_cleansed)==3,"graveyard_fully_cleansed")
    _check(int(campaign.side_progress.pyres)==3 and int(campaign.side_progress.gravebloom)==5,"all_graveyard_side_activities")

    # Multi-room ossuary, three wing objectives and the phased Champion.
    await _interact_story("ossuary_enter")
    _check(player.is_interior_mode() and player.global_position.x>8600.0,"ossuary_entered")
    await _fight_encounter("ossuary_wings",100)
    await _collect_all_visible_loot()
    for index in range(3):await _interact_story("ward_sigil",index)
    _check(int(campaign.stage)==6 and int(campaign.sigils_recovered)==3,"all_dungeon_sigils")
    await _fight_champion()
    await _collect_all_visible_loot()
    _check(int(campaign.stage)==7,"boss_unlocks_reward_choice")
    await _interact_story("ossuary_cache")
    _check(bool(campaign.side_progress.get("ossuary_cache",false)),"champion_reward_chest_opened")
    await _interact_story("reward_blade")
    _check(int(campaign.stage)==8 and str(campaign.reward_choice)=="blade","meaningful_reward_claimed")
    await _interact_story("ossuary_exit")
    _check(not player.is_interior_mode(),"ossuary_exit_works")
    await _interact_story("captain")
    _check(int(campaign.stage)==9 and bool(campaign.get_active_state().complete),"full_story_return_complete")

    # The complete loop feeds the postgame economy without test-only materials.
    var craft_result:String=director.craft_recipe("graveward_tonic")
    _check(craft_result.begins_with("Crafted"),"earned_materials_craft_graveward_tonic")
    await _interact_story("contract_board")
    var contract_id:="contract_%s"%str(campaign.contract_active)
    _check(not str(campaign.contract_active).is_empty(),"repeatable_contract_accepted")
    await _fight_encounter(contract_id,100)
    await _collect_all_visible_loot()
    _check(str(campaign.contract_active).is_empty(),"repeatable_contract_rewarded")
    await _test_vendor()
    await _test_map_and_menu()

    # Save data is round-tripped without touching the player's user:// file.
    var persisted:Dictionary=campaign.get_save_state()
    campaign.stage=0;campaign.reward_choice=""
    campaign.load_save_state(persisted)
    _check(int(campaign.stage)==9 and str(campaign.reward_choice)=="blade","campaign_save_state_roundtrip")
    for variant in ["shambler","runner","graveguard","carrier","champion"]:
        _check(bool(fought_variants.get(variant,false)),"personally_fought_%s"%variant)
    _check(manual_pickups>=20,"manual_loot_pickup_loop")
    _check(player.bag_slots.any(func(item:Dictionary):return item.get("id","")=="barrowfen_vigil_blade"),"reward_visible_in_bag")
    await _save_screenshot()

    frame_samples.sort()
    var average:=0.0
    for sample in frame_samples:average+=sample
    average/=maxf(1.0,float(frame_samples.size()))
    var p95:=frame_samples[roundi(float(frame_samples.size()-1)*.95)] if not frame_samples.is_empty() else 0.0
    var p99:=frame_samples[roundi(float(frame_samples.size()-1)*.99)] if not frame_samples.is_empty() else 0.0
    print("GRAVEBOUND_DESKTOP_PLAYTHROUGH|%s|stage=%d|variants=%d|ability_hits=%d|pickups=%d|bag=%d|gold=%d|level=%d|avg_ms=%.2f|p95_ms=%.2f|p99_ms=%.2f|failures=%d"%[
        "PASS" if failures.is_empty() else "FAIL",campaign.stage,fought_variants.size(),ability_hits,manual_pickups,player.bag_slots.size(),player.hero_gold,player.hero_level,average,p95,p99,failures.size()])
    main.free()
    quit(0 if failures.is_empty() else 31)
