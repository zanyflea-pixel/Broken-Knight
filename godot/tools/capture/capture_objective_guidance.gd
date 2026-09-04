extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    var failures:=0

    main._set_map_open(true)
    await _settle(24)
    if await _capture("res://artifacts/objective_world_map_v1.png")!=OK:failures+=1
    print("OBJECTIVE_CAPTURE_STAGE|world_map_saved")
    main._set_map_open(false)
    paused=false
    await process_frame
    print("OBJECTIVE_CAPTURE_STAGE|map_closed")

    player.global_position=main._sample_global_height(250,-2300)+Vector3.UP*.08
    var ui:=main.get_node("UI") as CanvasLayer
    ui.visible=true
    for child_value in main.get_node("UI").get_children():
        if child_value is CanvasItem:
            (child_value as CanvasItem).visible=str(child_value.name)=="Minimap"
    var minimap:=main.get_node("UI/Minimap") as Control
    minimap.visible=true
    minimap.configure(main.get("_active_profile"),player,main.get_node("GameplayDirector"),Callable(main,"_sample_global_height"))
    print("OBJECTIVE_CAPTURE_STAGE|minimap_configured")
    await _settle(40)
    print("OBJECTIVE_CAPTURE_STAGE|minimap_settled")
    if await _capture("res://artifacts/objective_minimap_edge_v1.png")!=OK:failures+=1
    print("OBJECTIVE_GUIDANCE_CAPTURE|shots=2|failures=%d"%failures)
    quit(0 if failures==0 else 1)
