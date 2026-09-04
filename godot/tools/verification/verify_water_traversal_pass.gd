extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:CharacterBody3D=main.get_node("Player")
    var profile:Dictionary=main.get("_active_profile")

    var river:Dictionary=profile.get("river_corridors",[])[0]
    var river_points:Array=river.get("points",[])
    var river_point:=Vector2(river_points[river_points.size()/2])
    var river_state:Dictionary=main._sample_global_water_state(river_point.x,river_point.y)
    if str(river_state.get("kind",""))!="river":failures.append("starter river does not return river traversal state")
    if float(river_state.get("depth",0.0))<.92:failures.append("starter river is not deep enough to swim at its center")
    if Vector2(river_state.get("flow_direction",Vector2.ZERO)).length()<.9:failures.append("river current has no downstream direction")

    var pond:Dictionary=profile.get("pond_sites",[])[0]
    var pond_point:Vector2=pond.get("position",Vector2.ZERO)
    var pond_state:Dictionary=main._sample_global_water_state(pond_point.x,pond_point.y)
    if str(pond_state.get("kind",""))!="pond":failures.append("starter pond does not return pond traversal state")
    if float(pond_state.get("flow_strength",-1.0))!=0.0:failures.append("still pond incorrectly applies a current")

    player.global_position=Vector3(river_point.x,float(river_state.get("surface_y",0.0))-float(river_state.get("depth",0.0))+.06,river_point.y)
    if not bool(player.call("_water_state_is_swimmable",river_state)):failures.append("deep river center does not enter swim locomotion")
    player.global_position.y=float(river_state.get("surface_y",0.0))+2.0
    if bool(player.call("_water_state_is_swimmable",river_state)):failures.append("bridge-height player incorrectly swims above the river")

    player.global_position=Vector3(river_point.x,float(river_state.get("surface_y",0.0))-.78,river_point.y)
    player.stamina=100.0
    player.call("_set_swimming",true,river_state)
    player.call("_process_swimming",1.0,Vector2.ZERO,river_state)
    var inland_drain:float=100.0-float(player.stamina)
    if not player.is_swimming():failures.append("river swim state did not engage")
    if inland_drain<1.5 or inland_drain>4.0:failures.append("inland swim stamina drain is outside target: %.2f"%inland_drain)
    player.call("_set_swimming",false)

    await main._ensure_skeld_region_loaded()
    var skeld_context:Dictionary=main.get("_region_contexts").get("skeld_coast",{})
    var skeld_profile:Dictionary=skeld_context.get("local_profile",{})
    var basin:Dictionary=skeld_profile.get("ocean_basins",[])[0]
    var local_z:=600.0
    var coast_x:float=main._coast_x_at_z(local_z,basin.get("coast_points",[]))
    var offset:Vector2=skeld_context.get("offset",Vector2.ZERO)
    var ocean_point:=offset+Vector2(coast_x-380.0,local_z)
    var ocean_state:Dictionary=main._sample_global_water_state(ocean_point.x,ocean_point.y)
    if str(ocean_state.get("kind",""))!="ocean":failures.append("Grey Sea does not return ocean traversal state")
    if not bool(ocean_state.get("hazard",false)):failures.append("Grey Sea is not marked hazardous")
    if float(ocean_state.get("flow_strength",0.0))<=float(river_state.get("flow_strength",0.0)):failures.append("offshore sea current is not stronger than inland current")

    player.global_position=Vector3(ocean_point.x,float(ocean_state.get("surface_y",0.0))-.78,ocean_point.y)
    player.stamina=100.0
    player.call("_set_swimming",true,ocean_state)
    player.call("_process_swimming",1.0,Vector2.ZERO,ocean_state)
    var ocean_drain:float=100.0-float(player.stamina)
    if ocean_drain<=inland_drain*2.5:failures.append("ocean drain is not meaningfully more dangerous: inland=%.2f ocean=%.2f"%[inland_drain,ocean_drain])
    player.stamina=0.0
    var hp_before:float=player.hp
    player.call("_process_swimming",1.05,Vector2.ZERO,ocean_state)
    if player.hp>=hp_before:failures.append("exhausted ocean swimmer takes no damage")
    player.call("_set_swimming",false)

    print("WATER_TRAVERSAL_PASS|river=%s|river_depth=%.2f|pond=%s|ocean=%s|inland_drain=%.2f|ocean_drain=%.2f|exhaustion_damage=%.1f|failures=%d"%[
        str(river_state.get("name","")),float(river_state.get("depth",0.0)),str(pond_state.get("name","")),str(ocean_state.get("name","")),
        inland_drain,ocean_drain,hp_before-player.hp,failures.size(),
    ])
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
