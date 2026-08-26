extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var main:=MAIN_SCENE.instantiate();main.auto_boot_enabled=false;root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_north_region_loaded()
    main._prepare_gameplay_region_for_position(-9200.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    main.get_node("UI").visible=false
    main.get_node("Player/CameraPivot/SpringArm3D/Camera3D").current=false
    var target:Vector3=main._sample_global_terrain_height(430.0,-9750.0)+Vector3.UP*55.0
    var camera:=Camera3D.new();camera.name="NorthExpansionCaptureCamera";camera.position=target+Vector3(680,210,840);camera.fov=50;camera.current=true;main.add_child(camera);camera.look_at(target,Vector3.UP)
    for frame in range(16):await process_frame
    await RenderingServer.frame_post_draw
    var output:="res://artifacts/north_expansion_v1.png"
    root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
    print("NORTH_EXPANSION_CAPTURE|%s"%output)
    quit(0)
