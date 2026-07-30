extends SceneTree

func _init()->void:call_deferred("_run")

func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate();root.add_child(main)
    await process_frame;await process_frame
    main.get_node("UI").visible=false
    var camera:=Camera3D.new();main.add_child(camera);camera.current=true;camera.fov=62.0
    var reviews:=[
        ["dungeon_gate_key",Vector3(8200,-89,80),Vector3(8200,-93,50)],
        ["dungeon_second_hall",Vector3(8224,-89,39),Vector3(8200,-93,10)],
        ["house_facade",Vector3(-2490,9,-900),Vector3(-2500,3,-950)],
        ["river_margin",Vector3(-1200,15,330),Vector3(-1200,0,250)],
    ]
    var output_dir:=ProjectSettings.globalize_path("res://artifacts")
    for review in reviews:
        if str(review[0]).begins_with("dungeon"):
            main.get_node("Player").set_interior_mode(true);main.get_node("Player").global_position=review[2]
            await process_frame
        camera.global_position=review[1];camera.look_at(review[2],Vector3.UP)
        await create_timer(.45).timeout;await RenderingServer.frame_post_draw
        var path:=output_dir.path_join("correction_%s.png"%review[0]);var error:=root.get_viewport().get_texture().get_image().save_png(path)
        print("CORRECTION_CAPTURE|%s|error=%s|fps=%d"%[path,error,Engine.get_frames_per_second()])
    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    main.get_node("UI/WorldMap").visible=true
    await create_timer(.75).timeout;await RenderingServer.frame_post_draw
    var map_path:=output_dir.path_join("correction_world_map.png")
    var map_error:=root.get_viewport().get_texture().get_image().save_png(map_path)
    print("CORRECTION_CAPTURE|%s|error=%s"%[map_path,map_error])
    main.free();quit()
