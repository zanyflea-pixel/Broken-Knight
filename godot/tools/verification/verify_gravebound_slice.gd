extends SceneTree

const REQUIRED_ANIMATIONS := ["Idle","Walk","Run","Attack","Hit","Stagger","Knockdown","Death"]
var failures:Array[String]=[]


class FakeHero:
    extends CharacterBody3D
    var hp:=600.0;var max_hp:=600.0;var mana:=100.0;var max_mana:=100.0;var stamina:=100.0
    var hero_gold:=0;var health_potions:=2;var mana_potions:=1;var enemies_defeated:=0;var elites_defeated:=0;var relic_shards:=0
    var hero_level:=1;var hero_xp:=0;var next_xp:=25;var active_class:="Warrior";var bag_slots:Array=[];var equipment_slots:Dictionary={}
    var herbs:=0;var scrap:=0;var ore:=0;var essence:=0;var logs:=0;var leather:=0;var cloth:=0;var stone:=0;var resin:=0;var mushrooms:=0;var crystal:=0;var grave_tokens:=0;var plague_samples:=0
    var _interior_mode:=false
    func get_equipment_state()->Dictionary:return {"armor":0,"power":8}
    func give_xp(amount:int)->void:
        hero_xp+=amount
        while hero_xp>=next_xp:hero_xp-=next_xp;hero_level+=1;next_xp=25+hero_level*18
    func add_material(kind:String,amount:int)->void:
        if kind in ["herbs","scrap","ore","essence","logs","leather","cloth","stone","resin","mushrooms","crystal","grave_tokens","plague_samples"]:set(kind,maxi(0,int(get(kind))+amount))
    func add_bag_item(item:Dictionary)->bool:bag_slots.append(item.duplicate(true));return true
    func set_interior_mode(value:bool)->void:_interior_mode=value
    func is_warrior()->bool:return true
    func has_warrior_weapons_equipped()->bool:return true


func _find_animator(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node as AnimationPlayer
    for child in node.get_children():
        var found:=_find_animator(child)
        if found:return found
    return null


func _find_skeleton(node:Node)->Skeleton3D:
    if node is Skeleton3D:return node as Skeleton3D
    for child in node.get_children():
        var found:=_find_skeleton(child)
        if found:return found
    return null


func _mesh_count(node:Node)->int:
    var result:=1 if node is MeshInstance3D else 0
    for child in node.get_children():result+=_mesh_count(child)
    return result


func _check(condition:bool,label:String)->void:
    if condition:return
    failures.append(label);push_error("GRAVEBOUND_FAIL|%s"%label)


func _story_interaction(campaign:Node,story_id:String,index:=-1)->Dictionary:
    for interaction in campaign.get("_story_interactions"):
        if str(interaction.get("story_id",""))==story_id and (index<0 or int(interaction.get("index",-1))==index):return interaction
    return {}


func _kill_encounter(director:Node,encounter_id:String)->void:
    for enemy in director.minions.duplicate():
        if str(enemy.get("encounter_id",""))==encounter_id and not bool(enemy.get("dead",false)):director._damage(enemy,99999.0,Vector3.FORWARD)
    await process_frame
    await process_frame


func _run()->void:
    var scene:=load("res://assets/enemies/gravebound_zombie.glb") as PackedScene
    _check(scene!=null,"asset_exists")
    if scene==null:quit(2);return
    var asset:=scene.instantiate();root.add_child(asset)
    var animator:=_find_animator(asset);var skeleton:=_find_skeleton(asset);var missing:Array[String]=[]
    if animator:
        for clip in REQUIRED_ANIMATIONS:
            if not animator.has_animation(clip):missing.append(clip)
    else:missing.assign(REQUIRED_ANIMATIONS)
    var authored_bone_count:=skeleton.get_bone_count() if skeleton else 0
    _check(authored_bone_count>=19,"complete_rig")
    var authored_mesh_count:=_mesh_count(asset)
    _check(authored_mesh_count==1,"consolidated_skinned_mesh")
    _check(missing.is_empty(),"all_required_animations")
    asset.queue_free()

    var hero:=FakeHero.new();hero.name="GraveboundTestHero";root.add_child(hero)
    var director:=Node3D.new();director.name="GraveboundTestDirector";director.set_script(load("res://scripts/GameplayDirector.gd"));director.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(director)
    await process_frame
    director.set("player",hero);director.set("height_sampler",func(x:float,z:float):return Vector3(x,0,z));director.set("walkable_sampler",func(_x:float,_z:float):return true);director.set("safe_zone_center",Vector2(9999,9999))
    var variants=["shambler","runner","graveguard","carrier","champion"]
    for i in range(variants.size()):director._spawn_zombie(Vector2(float(i)*6+12,0),variants[i],"variant_test_%s"%variants[i])
    for variant in variants:
        var found:Dictionary={}
        for enemy in director.minions:
            if str(enemy.get("zombie_variant",""))==variant:found=enemy;break
        _check(not found.is_empty(),"variant_%s_spawns"%variant)
        if not found.is_empty():
            _check(is_instance_valid(found.get("animation") as AnimationPlayer),"variant_%s_animated"%variant)
            _check((found.node as Node).find_child("VariantEquipment",true,false)!=null,"variant_%s_equipment_root"%variant)
    var runner:Dictionary={}
    for enemy in director.minions:
        if enemy.get("zombie_variant","")=="runner":runner=enemy;break
    if not runner.is_empty():
        var start_distance:float=runner.node.global_position.distance_to(hero.global_position)
        director._tick_minions(.20)
        _check(runner.node.global_position.distance_to(hero.global_position)<start_distance,"runner_chases")
        _check((runner.animation as AnimationPlayer).current_animation=="Run","runner_uses_run_clip")
    for enemy in director.minions.duplicate():
        if str(enemy.get("kind","")).begins_with("zombie_"):director._damage(enemy,99999.0,Vector3.FORWARD)
    _check(director.loot.size()>=10,"zombie_loot_is_visible_and_manual")
    _check(hero.enemies_defeated>=5,"all_variants_fought")

    # Fresh director for a deterministic full story-path simulation.
    director.free();await process_frame
    director=Node3D.new();director.name="GraveboundStoryDirector";director.set_script(load("res://scripts/GameplayDirector.gd"));director.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(director);await process_frame
    director.set("player",hero);director.set("height_sampler",func(x:float,z:float):return Vector3(x,0,z));director.set("walkable_sampler",func(_x:float,_z:float):return true);director.set("safe_zone_center",Vector2(-420,70));director.set("profile",{})
    var campaign:Node3D=load("res://scripts/gameplay/GraveboundCampaign.gd").new() as Node3D;director.add_child(campaign);director._gravebound_campaign=campaign;campaign.configure(director,hero,{})
    campaign.activate(_story_interaction(campaign,"captain"));_check(campaign.stage==1,"opening_quest_starts")
    campaign.activate(_story_interaction(campaign,"wagon"));_check(campaign.stage==2,"road_ambush_starts")
    await _kill_encounter(director,"courier_ambush");_check(campaign.stage==3,"road_ambush_advances")
    campaign.activate(_story_interaction(campaign,"scout"));_check(campaign.stage==4 and campaign.side_progress.scout,"scout_rescue")
    for i in range(3):campaign.activate(_story_interaction(campaign,"grave_seal",i))
    _check(campaign.stage==5 and campaign.seals_cleansed==3,"three_seals_open_ossuary")
    campaign.activate(_story_interaction(campaign,"ossuary_enter"));_check(hero._interior_mode and hero.global_position.x>8600,"dungeon_entry")
    for i in range(3):campaign.activate(_story_interaction(campaign,"ward_sigil",i))
    _check(campaign.stage==6 and campaign.sigils_recovered==3,"dungeon_sigils_summon_boss")
    var champion:Dictionary={}
    for enemy in director.minions:
        if enemy.get("zombie_variant","")=="champion" and not enemy.get("dead",false):champion=enemy;break
    _check(not champion.is_empty(),"champion_exists")
    if not champion.is_empty():director._damage(champion,99999.0,Vector3.FORWARD)
    await process_frame;_check(campaign.stage==7,"champion_defeat_unlocks_choice")
    campaign.activate(_story_interaction(campaign,"reward_blade"));_check(campaign.stage==8 and campaign.reward_choice=="blade","reward_choice")
    campaign.activate(_story_interaction(campaign,"captain"));_check(campaign.stage==9,"return_to_town_completion")
    _check(hero.bag_slots.any(func(item:Dictionary):return item.get("id","")=="barrowfen_vigil_blade"),"chosen_reward_in_inventory")
    _check(campaign.get_map_markers().size()>=3,"map_story_markers")
    _check(director.get_recipes().any(func(recipe:Dictionary):return recipe.get("id","")=="graveglass_sword"),"gravecraft_unlock")
    var story_state:Dictionary=campaign.get_active_state();_check(story_state.complete,"campaign_reports_complete")
    var saved_campaign:Dictionary=campaign.get_save_state();campaign.stage=0;campaign.reward_choice="";campaign.load_save_state(saved_campaign)
    _check(campaign.stage==9 and campaign.reward_choice=="blade","campaign_state_round_trip")
    print("GRAVEBOUND_SLICE|%s|bones=%d|meshes=%d|animations=%d|variants=%d|stage=%d|loot=%d|failures=%d"%[
        "PASS" if failures.is_empty() else "FAIL",authored_bone_count,authored_mesh_count,REQUIRED_ANIMATIONS.size(),variants.size(),campaign.stage,director.loot.size(),failures.size()])
    quit(0 if failures.is_empty() else 21)


func _initialize()->void:call_deferred("_run")
