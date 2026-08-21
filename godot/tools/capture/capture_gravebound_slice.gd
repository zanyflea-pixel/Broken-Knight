extends SceneTree


func _initialize()->void:call_deferred("_run")


func _save(path:String)->void:
    for _frame in range(4):await process_frame;await RenderingServer.frame_post_draw
    var absolute:=ProjectSettings.globalize_path(path)
    var error:=root.get_texture().get_image().save_png(absolute)
    print("GRAVEBOUND_CAPTURE|path=%s|error=%d"%[absolute,error])


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate();root.add_child(main)
    for _frame in range(8):await process_frame
    await create_timer(2.0).timeout
    var hero:=main.get_node("Player") as CharacterBody3D
    var director:=main.get_node("GameplayDirector")
    var world_result:Dictionary=main.get("_world_result")
    var height_sampler:Callable=world_result.get("height_sampler",Callable())
    var camera:=Camera3D.new();camera.fov=48.0;main.add_child(camera);camera.current=true
    main.get_node("UI").visible=false

    # Runtime family lineup, including every variant's actual Godot equipment.
    director.process_mode=Node.PROCESS_MODE_DISABLED
    var lineup_center:=Vector2(-405,42)
    var variants=["runner","shambler","graveguard","carrier","champion"]
    for i in range(variants.size()):
        var point:=lineup_center+Vector2((float(i)-2.0)*3.1,-6.0)
        director._spawn_zombie(point,variants[i],"capture")
    var center_ground:Vector3=height_sampler.call(lineup_center.x,lineup_center.y-6.0)
    camera.global_position=center_ground+Vector3(11,4.2,-13)
    camera.look_at(center_ground+Vector3(0,1.4,0),Vector3.UP)
    await _save("res://artifacts/gravebound_family_runtime.png")

    # The authored surface route: wagon, ruined farm, graveyard and entrance.
    var grave_center:Vector3=height_sampler.call(252.0,-624.0)
    camera.global_position=grave_center+Vector3(72,54,86)
    camera.look_at(grave_center+Vector3(0,2,0),Vector3.UP)
    await _save("res://artifacts/barrowfen_route_runtime.png")

    # Interior structure and objective pedestals.
    hero.set_interior_mode(true);hero.global_position=Vector3(8700,-107.8,56)
    var campaign:Node3D=director.get("_gravebound_campaign") as Node3D
    campaign._process(0.0)
    camera.global_position=Vector3(8700,-103.6,81);camera.look_at(Vector3(8700,-105.7,18),Vector3.UP)
    await _save("res://artifacts/barrowfen_ossuary_runtime.png")
    main.free();quit(0)
