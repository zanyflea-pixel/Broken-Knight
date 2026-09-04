extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var director:=main.get_node("GameplayDirector")
    var primary:Dictionary=director.get_primary_story_objective()
    if primary.is_empty():failures.append("no primary story objective was selected")
    if str(primary.get("quest_title","")).is_empty():failures.append("primary objective omits its quest title")
    var primary_count:=0
    var objective_count:=0
    for marker_value in director.get_story_map_markers():
        var marker:Dictionary=marker_value
        if str(marker.get("kind",""))!="story_objective":continue
        objective_count+=1
        if bool(marker.get("primary",false)):primary_count+=1
    if primary_count!=1:failures.append("expected exactly one strong objective marker, found %d"%primary_count)
    if objective_count<2:failures.append("side-story objectives disappeared instead of becoming secondary")
    var minimap:=main.get_node("UI/Minimap")
    var live_overlay:=minimap.get_node_or_null("LiveOverlay")
    var has_edge_guidance:=live_overlay!=null and live_overlay.has_method("_draw_primary_objective")
    if not has_edge_guidance:failures.append("minimap live overlay has no offscreen objective guidance")
    print("OBJECTIVE_GUIDANCE_PASS|objectives=%d|primary=%d|quest=%s|edge_guidance=%s|failures=%d"%[
        objective_count,primary_count,str(primary.get("quest_title","none")),
        has_edge_guidance,failures.size(),
    ])
    for failure in failures:push_error("OBJECTIVE_GUIDANCE_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
