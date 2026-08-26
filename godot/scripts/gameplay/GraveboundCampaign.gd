extends Node3D

## A self-contained 30–45 minute quest slice layered onto the existing world.
## Terrain and the hero remain owned by the established world systems.

const CAMPAIGN_TITLE := "The Bell Beneath Barrowfen"
const CAPTAIN_POINT := Vector2(-396.0, 53.0)
const WAGON_POINT := Vector2(-332.0, -246.0)
const FARM_POINT := Vector2(-90.0, -493.0)
const GRAVEYARD_POINT := Vector2(252.0, -624.0)
const OSSUARY_POINT := Vector2(344.0, -716.0)
const OSSUARY_BASE := Vector3(8700.0, -108.0, 0.0)
const OSSUARY_BOUNDS := Rect2(Vector2(8646.0, -88.0), Vector2(108.0, 176.0))

var director
var player
var profile:Dictionary={}
var stage:=0
var seals_cleansed:=0
var sigils_recovered:=0
var completed_seals:Array[int]=[]
var completed_sigils:Array[int]=[]
var reward_choice:=""
var side_progress:Dictionary={"pyres":0,"gravebloom":0,"cache":false,"scout":false,"ossuary_cache":false}
var cleared_encounters:Dictionary={}
var discovered:Dictionary={"riverwatch":true}
var _spawned_encounters:Dictionary={}
var _story_interactions:Array[Dictionary]=[]
var _captain_marker:Label3D
var _dungeon_root:Node3D
var _surface_root:Node3D
var _event_cooldown:=420.0
var _champion_spawned:=false
var contract_active:=""
var contract_goal:=0
var contract_kills:=0
var contract_round:=0


func configure(gameplay_director,hero,world_profile:Dictionary)->void:
    director=gameplay_director
    player=hero
    profile=world_profile
    name="GraveboundCampaign"
    set_meta("always_streamed",true)
    _surface_root=Node3D.new();_surface_root.name="BarrowfenSurfaceStory";add_child(_surface_root)
    _build_captain()
    _build_broken_wagon()
    _build_ruined_farm()
    _build_graveyard()
    _build_ossuary_entrance()
    _build_ossuary_dungeon()
    _build_side_activities()
    _register_interactions()
    _spawn_authored_population()
    _sync_interaction_states()
    director._notify("Captain Mera is waiting beside Riverwatch's south road",Color(1.0,.78,.32))


func _process(delta:float)->void:
    if not is_instance_valid(player):return
    var inside:bool=float(player.global_position.x)>8600.0
    if is_instance_valid(_dungeon_root):_dungeon_root.visible=inside
    if not inside:
        var point:=Vector2(player.global_position.x,player.global_position.z)
        if point.distance_to(FARM_POINT)<70.0:discovered["mirecroft_farm"]=true
        if point.distance_to(GRAVEYARD_POINT)<85.0:discovered["barrowfen_graves"]=true
        if point.distance_to(OSSUARY_POINT)<85.0:discovered["ossuary"]=true
        if stage>=3 and not _spawned_encounters.get("farm_dead",false) and not _encounter_recently_cleared("farm_dead") and point.distance_to(FARM_POINT)<52.0:
            _spawned_encounters["farm_dead"]=true
            _spawn_group("farm_dead",FARM_POINT+Vector2(13,-5),["shambler","shambler","runner","carrier"])
            director._notify("The Mirecroft dead rise from the ruined fields",Color(.72,1.0,.38))
        if stage>=4 and not _spawned_encounters.get("grave_patrol",false) and not _encounter_recently_cleared("grave_patrol") and point.distance_to(GRAVEYARD_POINT)<68.0:
            _spawned_encounters["grave_patrol"]=true
            _spawn_group("grave_patrol",GRAVEYARD_POINT+Vector2(-16,8),["shambler","shambler","runner","graveguard"])
    if stage>=9:
        _event_cooldown=maxf(0.0,_event_cooldown-delta)
        if _event_cooldown<=0.0 and not _has_living_encounter("road_event") and Vector2(player.global_position.x,player.global_position.z).distance_to(WAGON_POINT)<75.0:
            _event_cooldown=900.0
            _spawn_group("road_event",WAGON_POINT+Vector2(18,-4),["runner","runner","shambler","carrier","graveguard"])
            director._notify("WORLD EVENT — Gravebound are attacking the south road",Color(1.0,.38,.16))


func activate(data:Dictionary)->void:
    var story_id:=str(data.get("story_id",""))
    match story_id:
        "captain":
            if stage==0:
                stage=1
                director._notify("Captain Mera: Find the royal courier's wagon beyond Riverwatch Bridge.",Color(1.0,.84,.46))
            elif stage==8:
                stage=9
                player.hero_gold+=90
                player.give_xp(180)
                player.add_material("grave_tokens",4)
                director._notify("QUEST COMPLETE — Barrowfen's bell is silent. Repeatable hunts and gravecraft unlocked.",Color(1.0,.75,.20))
                _save_checkpoint()
            elif stage>=9:
                director._notify("Captain Mera: Gravebound stragglers still gather beyond the bridge. Their tokens buy gravecraft.",Color(.86,.88,.72))
            else:
                director._notify("Captain Mera: Stay on the south road. The dead signs lead toward Barrowfen.",Color(.86,.88,.72))
        "contract_board":
            if stage<9:
                director._notify("The board is reserved for proven wardens",Color(.78,.72,.58));return
            if not contract_active.is_empty():
                director._notify("Active contract: %s  %d / %d"%[contract_active.capitalize(),contract_kills,contract_goal],Color(.86,.82,.62));return
            contract_round+=1
            var sites=[{"id":"mirecroft_sweep","point":FARM_POINT+Vector2(24,-12),"variants":["shambler","shambler","runner","carrier"]},
                       {"id":"barrowfen_watch","point":GRAVEYARD_POINT+Vector2(-18,44),"variants":["runner","shambler","graveguard","carrier","runner"]},
                       {"id":"battlefield_guard","point":Vector2(420,-790),"variants":["shambler","shambler","graveguard","graveguard","carrier","runner"]}]
            var contract:Dictionary=sites[(contract_round-1)%sites.size()]
            contract_active=str(contract.id);contract_goal=contract.variants.size();contract_kills=0
            _spawn_group("contract_%s"%contract_active,contract.point,contract.variants)
            director._notify("NEW CONTRACT — %s. Follow the gold objective marker."%contract_active.replace("_"," ").capitalize(),Color(1.0,.72,.20))
        "wagon":
            if stage!=1:return
            stage=2
            data.active=false
            _spawn_group("courier_ambush",WAGON_POINT+Vector2(8,-6),["shambler","shambler","shambler","runner","runner"])
            director._notify("The courier carried a Barrowfen seal — and the road erupts with dead.",Color(1.0,.42,.18))
        "scout":
            if stage<3:return
            if not side_progress.scout:
                side_progress.scout=true
                player.health_potions+=2
                player.give_xp(24)
                director._notify("Scout Lysa: The grave bell woke them. Three ward seals open the ossuary.",Color(.72,1.0,.72))
            if stage==3:stage=4
        "grave_seal":
            if stage!=4:return
            var seal_index:=int(data.get("index",0))
            if seal_index in completed_seals:return
            completed_seals.append(seal_index)
            seals_cleansed=completed_seals.size()
            data.active=false;data["completed"]=true
            var position:Vector3=data.get("position",Vector3.ZERO)
            director._burst(position,Color(.46,.78,1.0),3.0)
            _spawn_group("seal_%d"%seal_index,Vector2(position.x,position.z)+Vector2(5,3),["shambler","runner"] if seal_index<2 else ["graveguard","shambler"])
            director._notify("Ward seal restored  %d / 3"%seals_cleansed,Color(.58,.86,1.0))
            if seals_cleansed>=3:
                stage=5
                _spawn_ossuary_population()
                director._notify("The ossuary door answers the three restored seals",Color(1.0,.74,.28))
        "ossuary_enter":
            if stage<5:
                director._notify("Three Barrowfen ward seals bind this door",Color(1.0,.48,.26));return
            player.set_interior_mode(true);player.global_position=OSSUARY_BASE+Vector3(0,.18,78);player.velocity=Vector3.ZERO
            discovered["ossuary"]=true
            director._notify("BARROWFEN OSSUARY — Recover the three ward sigils",Color(.74,.86,1.0))
        "ossuary_exit":
            player.set_interior_mode(false);player.global_position=director._ground(Vector3(OSSUARY_POINT.x,0,OSSUARY_POINT.y+14));player.velocity=Vector3.ZERO
        "ward_sigil":
            if stage!=5:return
            var sigil_index:=int(data.get("index",0))
            if sigil_index in completed_sigils:return
            completed_sigils.append(sigil_index)
            sigils_recovered=completed_sigils.size()
            data.active=false;data["completed"]=true
            director._burst(data.get("position",Vector3.ZERO),Color(.35,.82,1.0),3.2)
            director._notify("Ossuary ward sigil  %d / 3"%sigils_recovered,Color(.55,.86,1.0))
            if sigils_recovered>=3:
                stage=6
                _spawn_champion()
                director._notify("The Gravebound Champion breaks its final chain",Color(1.0,.30,.10))
        "reward_blade":
            if stage!=7:return
            if not player.add_bag_item({"id":"barrowfen_vigil_blade","name":"Barrowfen Vigil Blade","slot":"mainhand","visual":"sword","icon":8,"power":25,"armor":0,"hp":8,"mana":0,"description":"An anti-undead sword tempered with graveglass. Power +25, HP +8."}):
                director._notify("Your bag is full — make room before claiming the Vigil Blade",Color(1.0,.45,.24));return
            reward_choice="blade";stage=8
            player.add_material("grave_tokens",8)
            _disable_reward_interactions()
            director._notify("Claimed Barrowfen Vigil Blade — return to Captain Mera",Color(1.0,.72,.22))
        "reward_bulwark":
            if stage!=7:return
            if not player.add_bag_item({"id":"barrowfen_ward_bulwark","name":"Barrowfen Ward Bulwark","slot":"offhand","visual":"shield","icon":9,"power":7,"armor":21,"hp":28,"mana":0,"description":"A graveward shield. Armor +21, HP +28, Power +7."}):
                director._notify("Your bag is full — make room before claiming the Ward Bulwark",Color(1.0,.45,.24));return
            reward_choice="bulwark";stage=8
            player.add_material("grave_tokens",8)
            _disable_reward_interactions()
            director._notify("Claimed Barrowfen Ward Bulwark — return to Captain Mera",Color(1.0,.72,.22))
        "ossuary_cache":
            if stage<7:
                director._notify("The Champion's grave-chain still seals this coffer",Color(.74,.70,.62));return
            if bool(side_progress.get("ossuary_cache",false)):return
            if not player.add_bag_item({"id":"corrupted_bell_fragment","name":"Corrupted Bell Fragment","slot":"relic","icon":10,"power":3,"armor":0,"hp":6,"mana":4,"description":"A cracked piece of the stolen Barrowfen bell. Useful proof, and a potent future gravecraft reagent."}):
                director._notify("Your bag is full — make room before opening the Champion's coffer",Color(1.0,.45,.24));return
            side_progress["ossuary_cache"]=true;data.active=false
            player.hero_gold+=55;player.add_material("grave_tokens",4);player.add_material("essence",2)
            director._notify("CHAMPION COFFER — Corrupted Bell Fragment, Grave Tokens, essence and 55 gold",Color(1.0,.72,.22))
        "hidden_cache":
            if side_progress.cache:return
            side_progress.cache=true;data.active=false
            player.hero_gold+=24;player.add_material("scrap",4);player.health_potions+=1
            director._notify("Hidden courier cache: 24 gold, scrap and a health potion",Color(.78,1.0,.54))
        "cleansing_pyre":
            if not data.active:return
            data.active=false;side_progress.pyres=int(side_progress.pyres)+1
            player.hero_gold+=5;player.give_xp(8)
            director._burst(data.get("position",Vector3.ZERO),Color(1.0,.38,.08),2.4)
            director._notify("Burial pyre lit  %d / 3"%int(side_progress.pyres),Color(1.0,.64,.28))
        "gravebloom":
            if not data.active:return
            data.active=false;side_progress.gravebloom=int(side_progress.gravebloom)+1
            player.add_material("herbs",1);player.add_material("plague_samples",1)
            director._notify("Gathered Gravebloom and a plague sample",Color(.64,1.0,.52))
    _sync_interaction_states()
    if story_id in ["captain","wagon","scout","grave_seal","ossuary_enter","ward_sigil","reward_blade","reward_bulwark","ossuary_cache","contract_board"]:
        _save_checkpoint()


func enemy_defeated(enemy:Dictionary)->void:
    var kind:=str(enemy.get("kind",""))
    if not kind.begins_with("zombie_"):return
    var encounter_id:=str(enemy.get("encounter_id",""))
    if kind=="zombie_champion" and stage==6:
        stage=7
        cleared_encounters["ossuary_champion"]=-1
        director._notify("The Gravebound Champion falls — choose one relic from the two ward pedestals",Color(1.0,.72,.18))
        _sync_interaction_states()
    if encounter_id.is_empty():return
    if encounter_id.begins_with("contract_") and encounter_id=="contract_%s"%contract_active:
        contract_kills+=1
    call_deferred("_check_encounter_cleared",encounter_id)


func _check_encounter_cleared(encounter_id:String)->void:
    if _has_living_encounter(encounter_id):return
    cleared_encounters[encounter_id]=-1 if encounter_id in ["courier_ambush","farm_dead","grave_patrol"] else Time.get_unix_time_from_system()
    if encounter_id=="courier_ambush" and stage==2:
        stage=3
        # The scout interaction was disabled while the ambush was active.
        # Refresh it at the same moment the kill objective advances so the
        # player's next E press at Mirecroft can continue the story.
        _sync_interaction_states()
        director._notify("Ambush cleared — the courier's trail continues to Mirecroft Farm",Color(.72,1.0,.58))
    elif encounter_id.begins_with("contract_") and encounter_id=="contract_%s"%contract_active:
        player.hero_gold+=35+contract_goal*4;player.add_material("grave_tokens",3);player.give_xp(35+contract_goal*3)
        director._notify("CONTRACT COMPLETE — gold, experience, and three Grave Tokens awarded",Color(1.0,.76,.24))
        contract_active="";contract_goal=0;contract_kills=0
    _save_checkpoint()


func _save_checkpoint()->void:
    if OS.get_environment("BROKEN_KNIGHT_TEST_MODE")!="1":director._save_game()


func _has_living_encounter(encounter_id:String)->bool:
    for enemy in director.minions:
        if str(enemy.get("encounter_id",""))==encounter_id and is_instance_valid(enemy.get("node")) and not bool(enemy.get("dead",false)):return true
    return false


func _encounter_recently_cleared(encounter_id:String)->bool:
    if not cleared_encounters.has(encounter_id):return false
    var stamp:float=float(cleared_encounters[encounter_id])
    return stamp<0.0 or Time.get_unix_time_from_system()-stamp<900.0


func _spawn_group(encounter_id:String,center:Vector2,variants:Array)->void:
    for i in range(variants.size()):
        var angle:=float(i)*TAU/maxf(1.0,float(variants.size()))+.35
        var point:=center+Vector2(cos(angle),sin(angle))*(4.5+float(i%2)*2.2)
        director._spawn_zombie(point,str(variants[i]),encounter_id,false)


func _spawn_authored_population()->void:
    # Authored pockets, never an even carpet and never inside Riverwatch.
    if not _encounter_recently_cleared("corrupted_road_patrol"):
        _spawn_group("corrupted_road_patrol",Vector2(-215,-385),["shambler","shambler","runner"])
    if not _encounter_recently_cleared("old_battlefield"):
        _spawn_group("old_battlefield",Vector2(420,-790),["shambler","shambler","shambler","graveguard","carrier"])
    if stage>=5:
        _spawn_ossuary_population()


func _spawn_ossuary_population()->void:
    if _spawned_encounters.get("ossuary_wings",false) or _has_living_encounter("ossuary_wings"):
        _spawned_encounters["ossuary_wings"]=true
        return
    _spawned_encounters["ossuary_wings"]=true
    var positions=[Vector3(-32,.18,48),Vector3(30,.18,31),Vector3(-33,.18,2),Vector3(33,.18,-22),Vector3(-28,.18,-43)]
    var variants=["shambler","runner","graveguard","carrier","graveguard"]
    for i in range(positions.size()):director._spawn_zombie(Vector2.ZERO,variants[i],"ossuary_wings",true,OSSUARY_BASE+positions[i],OSSUARY_BOUNDS)


func _spawn_champion()->void:
    if _champion_spawned or _has_living_encounter("ossuary_champion") or _encounter_recently_cleared("ossuary_champion"):return
    _champion_spawned=true
    director._spawn_zombie(Vector2.ZERO,"champion","ossuary_champion",true,OSSUARY_BASE+Vector3(0,.18,-70),OSSUARY_BOUNDS)


func get_active_state()->Dictionary:
    if stage>=9 and not contract_active.is_empty():
        return {"id":"gravebound_contract","chapter":"CONTRACT","giver":"Riverwatch Warden Board","title":contract_active.replace("_"," ").capitalize(),"story":"The Gravebound remain dangerous even with Barrowfen's bell silenced.","description":"Clear the marked Gravebound pocket, then return to the board for another contract.","current":contract_kills,"goal":contract_goal,"available":true,"complete":false,"claimed":false,"objective_position":_contract_position()}
    var descriptions=[
        "Speak with Captain Mera beside Riverwatch's south road.",
        "Follow the south road across Riverwatch Bridge and inspect the courier wagon.",
        "Survive the Gravebound road ambush.",
        "Continue south to Mirecroft Farm and find the missing scout.",
        "Restore the three blue ward seals in Barrowfen Graveyard.",
        "Enter Barrowfen Ossuary and recover its three ward sigils.",
        "Defeat the Gravebound Champion in the final burial hall.",
        "Choose the Vigil Blade or Ward Bulwark from the reward pedestals.",
        "Return to Captain Mera in Riverwatch.",
        "Barrowfen is secured. Hunt stragglers, gather tokens, and use unlocked gravecraft.",
    ]
    var goals=[1,1,5,1,3,3,1,1,1,1]
    var currents=[0,0,0,0,seals_cleansed,sigils_recovered,0,0,0,1]
    if stage==0:currents[0]=0
    elif stage==1:currents[1]=0
    elif stage==2:
        var living:=0
        for enemy in director.minions:
            if str(enemy.get("encounter_id",""))=="courier_ambush" and not bool(enemy.get("dead",false)):living+=1
        currents[2]=5-living
    var index:=clampi(stage,0,descriptions.size()-1)
    return {"id":"gravebound_campaign","chapter":"STORY","giver":"Captain Mera, Riverwatch","title":CAMPAIGN_TITLE,"story":"A stolen burial bell is waking the war dead beneath Barrowfen.","description":descriptions[index],"current":currents[index],"goal":goals[index],"available":true,"complete":stage>=9,"claimed":stage>=9,"objective_position":_objective_position()}


func get_map_markers()->Array[Dictionary]:
    var markers:Array[Dictionary]=[
        {"kind":"story_site","name":"Mirecroft Farm","position":Vector3(FARM_POINT.x,0,FARM_POINT.y),"discovered":discovered.get("mirecroft_farm",false)},
        {"kind":"graveyard","name":"Barrowfen Graveyard","position":Vector3(GRAVEYARD_POINT.x,0,GRAVEYARD_POINT.y),"discovered":discovered.get("barrowfen_graves",false)},
        {"kind":"dungeon","name":"Barrowfen Ossuary","position":Vector3(OSSUARY_POINT.x,0,OSSUARY_POINT.y),"discovered":discovered.get("ossuary",false)},
    ]
    if stage<9:markers.append({"kind":"story_objective","name":get_active_state().description,"position":Vector3(_objective_position().x,0,_objective_position().y),"discovered":true})
    return markers


func _objective_position()->Vector2:
    if not contract_active.is_empty():return _contract_position()
    match stage:
        0,8:return CAPTAIN_POINT
        1,2:return WAGON_POINT
        3:return FARM_POINT
        4:return GRAVEYARD_POINT
        5,6,7:return OSSUARY_POINT if player.global_position.x<8600.0 else Vector2(player.global_position.x,player.global_position.z)
        _:return CAPTAIN_POINT


func get_save_state()->Dictionary:
    return {"stage":stage,"seals":seals_cleansed,"sigils":sigils_recovered,"completed_seals":completed_seals.duplicate(),"completed_sigils":completed_sigils.duplicate(),"reward":reward_choice,"side":side_progress.duplicate(true),"cleared":cleared_encounters.duplicate(true),"discovered":discovered.duplicate(true),"event_cooldown":_event_cooldown,"contract_active":contract_active,"contract_goal":contract_goal,"contract_kills":contract_kills,"contract_round":contract_round}


func load_save_state(data:Dictionary)->void:
    stage=clampi(int(data.get("stage",0)),0,9)
    var legacy_seals:=clampi(int(data.get("seals",0)),0,3)
    var legacy_sigils:=clampi(int(data.get("sigils",0)),0,3)
    completed_seals=_validated_objective_ids(data.get("completed_seals",range(legacy_seals)))
    completed_sigils=_validated_objective_ids(data.get("completed_sigils",range(legacy_sigils)))
    seals_cleansed=completed_seals.size()
    sigils_recovered=completed_sigils.size()
    reward_choice=str(data.get("reward",""))
    side_progress={"pyres":0,"gravebloom":0,"cache":false,"scout":false,"ossuary_cache":false}
    side_progress.merge(data.get("side",{}),true)
    cleared_encounters={}
    cleared_encounters.merge(data.get("cleared",{}),true)
    discovered={"riverwatch":true}
    discovered.merge(data.get("discovered",{}),true)
    _event_cooldown=float(data.get("event_cooldown",420.0))
    contract_active=str(data.get("contract_active",""));contract_goal=int(data.get("contract_goal",0));contract_kills=int(data.get("contract_kills",0));contract_round=int(data.get("contract_round",0))
    _spawned_encounters.clear()
    _champion_spawned=false
    for interaction in _story_interactions:
        if str(interaction.get("story_id",""))=="grave_seal":interaction["completed"]=int(interaction.get("index",0)) in completed_seals
        if str(interaction.get("story_id",""))=="ward_sigil":interaction["completed"]=int(interaction.get("index",0)) in completed_sigils
    for enemy_index in range(director.minions.size()-1,-1,-1):
        var enemy:Dictionary=director.minions[enemy_index]
        var encounter_id:=str(enemy.get("encounter_id",""))
        if encounter_id.is_empty() or not _encounter_recently_cleared(encounter_id):continue
        var enemy_node:=enemy.get("node") as Node
        if is_instance_valid(enemy_node):enemy_node.queue_free()
        director.minions.remove_at(enemy_index)
    if stage>=5:_spawn_ossuary_population()
    if stage==6:_spawn_champion()
    if stage==2 and not _has_living_encounter("courier_ambush"):
        # Active enemies are not serialized. Rebuild the entire encounter and
        # its 0/5 counter together so loading during the ambush cannot strand
        # the campaign at a completed-looking but non-advancing objective.
        cleared_encounters.erase("courier_ambush")
        _spawn_group("courier_ambush",WAGON_POINT+Vector2(8,-6),["shambler","shambler","shambler","runner","runner"])
    if not contract_active.is_empty() and not _has_living_encounter("contract_%s"%contract_active):
        contract_kills=0
        _spawn_group("contract_%s"%contract_active,_contract_position(),_contract_variants(contract_active))
    _sync_interaction_states()


func _validated_objective_ids(value:Variant)->Array[int]:
    var result:Array[int]=[]
    if not value is Array:return result
    for raw_id in value:
        var objective_id:=int(raw_id)
        if objective_id>=0 and objective_id<3 and objective_id not in result:result.append(objective_id)
    result.sort()
    return result


func _contract_position()->Vector2:
    match contract_active:
        "mirecroft_sweep":return FARM_POINT+Vector2(24,-12)
        "barrowfen_watch":return GRAVEYARD_POINT+Vector2(-18,44)
        "battlefield_guard":return Vector2(420,-790)
        _:return CAPTAIN_POINT


func _contract_variants(contract_id:String)->Array:
    match contract_id:
        "mirecroft_sweep":return ["shambler","shambler","runner","carrier"]
        "barrowfen_watch":return ["runner","shambler","graveguard","carrier","runner"]
        "battlefield_guard":return ["shambler","shambler","graveguard","graveguard","carrier","runner"]
        _:return ["shambler","runner"]


func _register_story(action_id:String,position:Vector3,radius:float,label:String,node:Node3D=null,extra:Dictionary={})->Dictionary:
    var interaction:Dictionary={"action":"gravebound_story","story_id":action_id,"position":position,"radius":radius,"label":label,"node":node,"active":true}
    interaction.merge(extra,true)
    _story_interactions.append(interaction)
    director._interactables.append(interaction)
    return interaction


func _register_interactions()->void:
    _register_story("captain",_ground(CAPTAIN_POINT),4.2,"Speak with Captain Mera")
    _register_story("contract_board",_ground(CAPTAIN_POINT+Vector2(10,3)),3.8,"Read the warden contract board")
    _register_story("wagon",_ground(WAGON_POINT),4.5,"Inspect the royal courier wagon")
    _register_story("scout",_ground(FARM_POINT+Vector2(6,-8)),4.5,"Help Scout Lysa")
    for i in range(3):
        var angle:=float(i)*TAU/3.0+.25
        var point:=GRAVEYARD_POINT+Vector2(cos(angle),sin(angle))*25.0
        _register_story("grave_seal",_ground(point),4.0,"Restore ward seal",null,{"index":i})
    _register_story("ossuary_enter",_ground(OSSUARY_POINT),7.0,"Enter Barrowfen Ossuary")
    _register_story("ossuary_exit",OSSUARY_BASE+Vector3(0,.18,82),5.0,"Leave Barrowfen Ossuary")
    for sigil_data in [[Vector3(-37,.55,36),0],[Vector3(38,.55,-1),1],[Vector3(-36,.55,-38),2]]:
        _register_story("ward_sigil",OSSUARY_BASE+sigil_data[0],4.0,"Recover ward sigil",null,{"index":sigil_data[1]})
    _register_story("reward_blade",OSSUARY_BASE+Vector3(-7,.2,-78),4.0,"Claim Vigil Blade")
    _register_story("reward_bulwark",OSSUARY_BASE+Vector3(7,.2,-78),4.0,"Claim Ward Bulwark")
    _register_story("ossuary_cache",OSSUARY_BASE+Vector3(42,.2,-70),4.0,"Open Champion's reward coffer")


func _sync_interaction_states()->void:
    for interaction in _story_interactions:
        match str(interaction.story_id):
            "wagon":interaction.active=stage==1
            "scout":interaction.active=stage>=3 and stage<=4
            "grave_seal":interaction.active=stage==4 and int(interaction.get("index",0)) not in completed_seals
            "ossuary_enter":interaction.active=stage>=5
            "ward_sigil":interaction.active=stage==5 and int(interaction.get("index",0)) not in completed_sigils
            "reward_blade","reward_bulwark":interaction.active=stage==7
            "ossuary_cache":interaction.active=stage>=7 and not bool(side_progress.get("ossuary_cache",false))
            _:pass
    if is_instance_valid(_captain_marker):
        _captain_marker.text="CAPTAIN MERA\nE — REPORT" if stage==8 else ("CAPTAIN MERA\nE — STORY QUEST" if stage==0 else "CAPTAIN MERA")


func _disable_reward_interactions()->void:
    for interaction in _story_interactions:
        if str(interaction.story_id) in ["reward_blade","reward_bulwark"]:interaction.active=false


func _ground(point:Vector2)->Vector3:return director._ground(Vector3(point.x,0,point.y))


func _label(root:Node3D,text_value:String,position:Vector3,color:Color,range_end:=80.0)->Label3D:
    var label:=Label3D.new();label.text=text_value;label.position=position;label.font_size=28;label.pixel_size=.010;label.modulate=color;label.outline_size=7;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.visibility_range_end=range_end;root.add_child(label);return label


func _new_surface_root(name_value:String,point:Vector2)->Node3D:
    # Surface story sites are siblings under GameplayDirector so the existing
    # local streamer evaluates their real world positions independently.
    # Grouping them beneath the campaign origin kept distant graveyard and farm
    # branches resident beside Riverwatch and caused needless traversal spikes.
    var root:=Node3D.new();root.name=name_value;director.add_child(root);root.global_position=_ground(point);return root


func _build_captain()->void:
    var captain:=_new_surface_root("CaptainMera",CAPTAIN_POINT)
    director._add_service_person(captain,Color(.15,.27,.44),false)
    director._service_box(captain,Vector3(0,1.27,.27),Vector3(.34,.48,.04),Color(.64,.47,.14))
    _captain_marker=_label(captain,"CAPTAIN MERA\nE — STORY QUEST",Vector3(0,2.65,0),Color(1.0,.78,.30),90.0)
    var board:=_new_surface_root("RiverwatchWardenBoard",CAPTAIN_POINT+Vector2(10,3))
    director._service_solid_box(board,Vector3(0,1.25,0),Vector3(3.2,1.9,.25),Color(.30,.16,.06))
    for x in [-1.25,1.25]:director._service_solid_box(board,Vector3(x,.55,.08),Vector3(.18,1.1,.18),Color(.19,.10,.04))
    _label(board,"WARDEN CONTRACTS\nE — READ",Vector3(0,2.55,0),Color(.92,.72,.28),55.0)


func _build_broken_wagon()->void:
    var wagon:=_new_surface_root("BrokenCourierWagon",WAGON_POINT)
    wagon.rotation.y=-.55
    var wood:=Color(.25,.12,.045);var iron:=Color(.16,.17,.16)
    director._service_solid_box(wagon,Vector3(0,.75,0),Vector3(4.4,.38,2.4),wood)
    director._service_box(wagon,Vector3(-1.6,1.55,.95),Vector3(.22,1.7,.16),wood)
    director._service_box(wagon,Vector3(1.7,1.15,-.95),Vector3(.20,1.0,.16),wood)
    for side in [-1.0,1.0]:
        var wheel:=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=.64;ring.outer_radius=.82;ring.rings=14;ring.ring_segments=8;wheel.mesh=ring;wheel.position=Vector3(side*1.48,.72,1.20);wheel.rotation.x=PI*.5;wheel.material_override=director._service_material(iron);wagon.add_child(wheel)
    director._service_box(wagon,Vector3(3.0,.48,-.35),Vector3(3.8,.15,.14),wood).rotation.y=.30
    _label(wagon,"ROYAL COURIER WRECK\nE — INSPECT",Vector3(0,3.0,0),Color(1.0,.66,.24),70.0)


func _build_ruined_farm()->void:
    var farm:=_new_surface_root("MirecroftFarm",FARM_POINT)
    var stone:=Color(.39,.36,.29);var timber:=Color(.23,.12,.05)
    director._service_solid_box(farm,Vector3(-10,1.6,-7),Vector3(18,3.2,1.0),stone)
    director._service_solid_box(farm,Vector3(-18,1.6,0),Vector3(1.0,3.2,15.0),stone)
    director._service_solid_box(farm,Vector3(-5,1.2,7),Vector3(9,2.4,1.0),stone)
    for i in range(4):
        var beam:MeshInstance3D=director._service_box(farm,Vector3(-16+float(i)*5.0,2.6,-1.0+float(i%2)*2.0),Vector3(.38,5.5,.38),timber);beam.rotation.z=.20*float(i-1)
    director._service_box(farm,Vector3(-7,.18,1),Vector3(13,.20,9),Color(.30,.24,.14))
    _label(farm,"MIRECROFT FARM",Vector3(-8,4.3,0),Color(.84,.72,.46),95.0)
    var scout:=Node3D.new();scout.name="WoundedScoutLysa";farm.add_child(scout);scout.position=Vector3(6,0,-8);director._add_service_person(scout,Color(.24,.34,.17),false);scout.rotation.z=1.05


func _build_graveyard()->void:
    var graves:=_new_surface_root("BarrowfenGraveyard",GRAVEYARD_POINT)
    var stone:=Color(.34,.35,.31);var dark:=Color(.18,.19,.17)
    for i in range(18):
        var x:=-28.0+float(i%6)*10.5;var z:=-18.0+float(i/6)*14.0+float(i%2)*2.0
        director._service_solid_box(graves,Vector3(x,.65,z),Vector3(2.1,1.3,.55),stone.darkened(float(i%3)*.035))
        director._service_box(graves,Vector3(x,1.55,z),Vector3(1.4,.65,.42),stone)
    for x in [-34.0,34.0]:director._service_solid_box(graves,Vector3(x,1.1,0),Vector3(.65,2.2,54),dark)
    director._service_solid_box(graves,Vector3(0,1.1,-27),Vector3(68,2.2,.65),dark)
    director._service_solid_box(graves,Vector3(-21,1.1,27),Vector3(25,2.2,.65),dark)
    director._service_solid_box(graves,Vector3(21,1.1,27),Vector3(25,2.2,.65),dark)
    _label(graves,"BARROWFEN GRAVEYARD",Vector3(0,4.0,26),Color(.72,.78,.59),120.0)
    for i in range(3):
        var angle:=float(i)*TAU/3.0+.25;var point:=Vector3(cos(angle)*25,.12,sin(angle)*25)
        var seal:=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=1.0;ring.outer_radius=1.23;ring.rings=18;ring.ring_segments=8;seal.mesh=ring;seal.position=point;seal.material_override=director._service_material(Color(.18,.56,.88));graves.add_child(seal)


func _build_ossuary_entrance()->void:
    var entrance:=_new_surface_root("BarrowfenOssuaryEntrance",OSSUARY_POINT)
    var stone:=Color(.27,.28,.26)
    director._service_solid_box(entrance,Vector3(-5,3.4,0),Vector3(3.2,6.8,3.0),stone)
    director._service_solid_box(entrance,Vector3(5,3.4,0),Vector3(3.2,6.8,3.0),stone)
    director._service_solid_box(entrance,Vector3(0,7.0,0),Vector3(13.2,2.0,3.0),stone)
    director._service_box(entrance,Vector3(0,3.3,.12),Vector3(6.8,6.6,.30),Color(.004,.006,.006))
    for x in [-4.8,0.0,4.8]:director._service_box(entrance,Vector3(x,8.2,0),Vector3(.45,1.1,.45),Color(.52,.49,.38))
    _label(entrance,"BARROWFEN OSSUARY\nE — ENTER",Vector3(0,9.2,0),Color(.62,.80,1.0),130.0)


func _build_ossuary_dungeon()->void:
    _dungeon_root=Node3D.new();_dungeon_root.name="BarrowfenOssuaryDungeon";_dungeon_root.position=OSSUARY_BASE;add_child(_dungeon_root)
    director._build_dungeon_shell(_dungeon_root,108.0,176.0,Color(.19,.185,.17),Color(.115,.12,.11),8.5)
    var wall:=Color(.18,.18,.165)
    # Alternating doorways create a winding crawl with three side chambers.
    for segment in [[Vector3(-32,3.4,50),Vector3(44,6.8,1.2)],[Vector3(38,3.4,50),Vector3(32,6.8,1.2)],
                    [Vector3(-42,3.4,15),Vector3(24,6.8,1.2)],[Vector3(18,3.4,15),Vector3(72,6.8,1.2)],
                    [Vector3(-18,3.4,-22),Vector3(72,6.8,1.2)],[Vector3(42,3.4,-22),Vector3(24,6.8,1.2)],
                    [Vector3(-38,3.4,-58),Vector3(32,6.8,1.2)],[Vector3(32,3.4,-58),Vector3(44,6.8,1.2)]]:
        director._service_solid_box(_dungeon_root,segment[0],segment[1],wall)
    director._service_solid_box(_dungeon_root,Vector3(-22,3.4,33),Vector3(1.2,6.8,34),wall)
    director._service_solid_box(_dungeon_root,Vector3(22,3.4,-3),Vector3(1.2,6.8,36),wall)
    director._service_solid_box(_dungeon_root,Vector3(-22,3.4,-40),Vector3(1.2,6.8,35),wall)
    for z in [74.0,49.0,31.0,12.0,-10.0,-33.0,-55.0,-76.0]:
        director._add_dungeon_ceiling_light(_dungeon_root,Vector3(0,7.7,z))
        director._service_box(_dungeon_root,Vector3(0,.035,z),Vector3(7.0,.05,9.0),Color(.24,.215,.17) if z>-30.0 else Color(.12,.20,.24))
    for torch in [Vector3(-51,3,67),Vector3(51,3,42),Vector3(-51,3,4),Vector3(51,3,-34),Vector3(-51,3,-70),Vector3(51,3,-70)]:director._add_dungeon_torch(_dungeon_root,torch,1.0 if torch.x<0 else -1.0)
    for glow_point in [Vector3(0,3.8,55),Vector3(-34,3.2,34),Vector3(34,3.2,-3),Vector3(-34,3.2,-40),Vector3(0,4.2,-72)]:
        var glow:=OmniLight3D.new();glow.position=glow_point;glow.light_color=Color(.52,.72,1.0) if glow_point.z>-55 else Color(1.0,.34,.12);glow.light_energy=3.2;glow.omni_range=29.0;glow.shadow_enabled=false;_dungeon_root.add_child(glow)
    # Carved arch frames make each transition readable from the preceding room.
    for arch in [[0.0,50.0],[-30.0,15.0],[30.0,-22.0],[0.0,-58.0]]:
        var ax:float=arch[0];var az:float=arch[1]
        for side in [-1.0,1.0]:director._service_box(_dungeon_root,Vector3(ax+side*5.2,2.7,az),Vector3(1.1,5.4,1.45),Color(.31,.30,.27))
        director._service_box(_dungeon_root,Vector3(ax,5.3,az),Vector3(11.4,1.1,1.45),Color(.31,.30,.27))
    # Burial niches, sarcophagi and bone piles reward looking into side rooms.
    for niche in [Vector3(-45,.55,34),Vector3(45,.55,-3),Vector3(-45,.55,-40),Vector3(44,.55,31),Vector3(-43,.55,-72)]:
        director._service_solid_box(_dungeon_root,niche,Vector3(5.8,1.1,2.8),Color(.25,.24,.215))
        director._service_box(_dungeon_root,niche+Vector3(0,.82,0),Vector3(5.2,.48,2.45),Color(.34,.32,.27))
        director._service_box(_dungeon_root,niche+Vector3(0,1.18,-1.25),Vector3(1.8,.28,.16),Color(.55,.51,.38))
    for pile in [Vector3(-13,.15,28),Vector3(15,.15,-12),Vector3(-15,.15,-48),Vector3(18,.15,-70)]:
        for piece in range(5):
            var offset:=Vector3((float(piece%3)-1.0)*.30,.08+float(piece/3)*.12,(float(piece%2)-.5)*.32)
            director._service_rock(_dungeon_root,pile+offset,Vector3(.30,.18,.22),Color(.59,.55,.42))
    # Three readable blue sigil pedestals.
    for point in [Vector3(-37,.4,36),Vector3(38,.4,-1),Vector3(-36,.4,-38)]:
        director._service_solid_box(_dungeon_root,point,Vector3(2.6,.8,2.6),Color(.24,.25,.23))
        var sigil:=MeshInstance3D.new();var mesh:=TorusMesh.new();mesh.inner_radius=.45;mesh.outer_radius=.63;mesh.rings=16;mesh.ring_segments=8;sigil.mesh=mesh;sigil.position=point+Vector3(0,1.2,0);sigil.rotation.x=PI*.5;var mat:StandardMaterial3D=director._service_material(Color(.16,.62,1.0)).duplicate() as StandardMaterial3D;mat.emission_enabled=true;mat.emission=Color(.08,.42,1.0);mat.emission_energy_multiplier=2.5;sigil.material_override=mat;_dungeon_root.add_child(sigil)
    # Relic pedestals are present from the start but only become interactive
    # after the boss falls.
    for data in [[-7.0,Color(.42,.62,1.0)],[7.0,Color(.70,.32,.12)]]:
        director._service_solid_box(_dungeon_root,Vector3(data[0],.55,-78),Vector3(3.6,1.1,3.6),Color(.31,.28,.20))
        director._service_box(_dungeon_root,Vector3(data[0],1.45,-78),Vector3(1.1,.75,1.1),data[1])
    _label(_dungeon_root,"VIGIL BLADE",Vector3(-7,2.9,-78),Color(.60,.78,1.0),30.0)
    _label(_dungeon_root,"WARD BULWARK",Vector3(7,2.9,-78),Color(1.0,.62,.25),30.0)
    # A literal guarded reward chest complements the mutually-exclusive relic
    # choice and rewards players who search the boss hall's side recess.
    director._service_solid_box(_dungeon_root,Vector3(42,.62,-70),Vector3(4.4,1.24,2.9),Color(.24,.105,.035))
    var coffer_lid:StaticBody3D=director._service_solid_box(_dungeon_root,Vector3(42,1.45,-70.18),Vector3(4.5,.72,2.95),Color(.32,.15,.045));coffer_lid.rotation.x=-.16
    for x in [40.7,43.3]:director._service_box(_dungeon_root,Vector3(x,1.0,-68.49),Vector3(.24,1.7,.12),Color(.36,.32,.23))
    director._service_box(_dungeon_root,Vector3(42,1.0,-68.42),Vector3(.55,.58,.18),Color(.56,.45,.18))
    _label(_dungeon_root,"CHAMPION'S REWARD COFFER\nE — OPEN",Vector3(42,3.0,-70),Color(1.0,.72,.24),34.0)
    # The stolen bell gives the story a physical centerpiece over the boss dais.
    var bell:=MeshInstance3D.new();var bell_mesh:=CylinderMesh.new();bell_mesh.top_radius=.42;bell_mesh.bottom_radius=1.18;bell_mesh.height=2.4;bell_mesh.radial_segments=18;bell.mesh=bell_mesh;bell.position=Vector3(0,5.4,-72);bell.material_override=director._service_material(Color(.42,.25,.07));_dungeon_root.add_child(bell)
    director._service_box(_dungeon_root,Vector3(0,7.3,-72),Vector3(.16,2.0,.16),Color(.14,.12,.09))
    for side in [-1.0,1.0]:
        var chain:MeshInstance3D=director._service_box(_dungeon_root,Vector3(side*2.7,4.6,-72),Vector3(.12,5.6,.12),Color(.12,.13,.13));chain.rotation.z=side*.58
    _label(_dungeon_root,"THE STOLEN BARROW BELL",Vector3(0,7.8,-72),Color(.92,.62,.20),42.0)
    _dungeon_root.visible=false


func _build_side_activities()->void:
    # Hidden cache under the farm's collapsed west wall.
    var cache:=_new_surface_root("CourierHiddenCache",FARM_POINT+Vector2(-19,10))
    director._service_solid_box(cache,Vector3(0,.42,0),Vector3(2.8,.84,1.9),Color(.30,.15,.055))
    _label(cache,"SCUFFED CACHE\nE — OPEN",Vector3(0,1.8,0),Color(.86,.74,.38),22.0)
    _register_story("hidden_cache",cache.global_position,3.4,"Open hidden courier cache",cache)
    for i in range(3):
        var point:=GRAVEYARD_POINT+Vector2(-42+float(i)*42,34+float(i%2)*10)
        var pyre:=_new_surface_root("CleansingPyre_%d"%i,point)
        for offset in [-.45,.45]:director._service_box(pyre,Vector3(offset,.22,0),Vector3(.28,.28,2.0),Color(.28,.13,.045)).rotation.y=.55*(-1.0 if offset<0 else 1.0)
        _register_story("cleansing_pyre",pyre.global_position,3.2,"Light cleansing pyre",pyre,{"index":i})
    for i in range(5):
        var angle:=float(i)*2.17
        var point:=GRAVEYARD_POINT+Vector2(cos(angle),sin(angle))*(42.0+float(i%2)*8.0)
        var bloom:=_new_surface_root("Gravebloom_%d"%i,point)
        for stem in range(4):
            director._service_box(bloom,Vector3((float(stem)-1.5)*.13,.28,0),Vector3(.035,.56,.035),Color(.12,.30,.08))
            director._service_rock(bloom,Vector3((float(stem)-1.5)*.13,.58,0),Vector3(.22,.16,.22),Color(.44,.20,.62))
        _register_story("gravebloom",bloom.global_position,2.8,"Gather Gravebloom",bloom,{"index":i})
