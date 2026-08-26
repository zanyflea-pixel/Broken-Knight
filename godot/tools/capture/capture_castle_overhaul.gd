extends SceneTree

func _init()->void:call_deferred("_run")

func _save(path:String)->void:
    await create_timer(.35).timeout;await RenderingServer.frame_post_draw
    var image:=root.get_viewport().get_texture().get_image();image.save_png(ProjectSettings.globalize_path(path));print("CASTLE_CAPTURE|%s"%path)

func _run()->void:
    var main:=(load("res://scenes/Main.tscn") as PackedScene).instantiate();main.set("auto_boot_enabled",false);root.add_child(main);await main.boot_world(Callable(),false,true)
    main.get_node("UI").visible=false
    var capital:Dictionary={}
    for site in main._active_profile.get("town_sites",[]):
        if site.get("capital",false):capital=site;break
    var center:Vector2=capital.get("position",Vector2.ZERO)+Vector2(0,-92)
    var ground:Vector3=main._world_result.height_sampler.call(center.x,center.y)
    var camera:=Camera3D.new();main.add_child(camera);camera.current=true;camera.fov=58
    var target:=ground+Vector3(0,22,-8);camera.global_position=ground+Vector3(96,48,118);camera.look_at(target,Vector3.UP)
    await _save("res://artifacts/castle_architecture_overhaul.png")
    var throne:=ground+Vector3(0,4.5,-25.0);camera.global_position=ground+Vector3(-13,5.0,8);camera.look_at(throne,Vector3.UP);camera.fov=50
    await _save("res://artifacts/castle_throne_room.png")
    var city_center:Vector2=capital.get("position",Vector2.ZERO)
    var city_ground:Vector3=main._world_result.height_sampler.call(city_center.x,city_center.y)
    camera.global_position=city_ground+Vector3(0,12,255);camera.look_at(city_ground+Vector3(0,4,184),Vector3.UP);camera.fov=58
    await _save("res://artifacts/castle_city_gate_road.png")
    var keep_center:=ground+Vector3(0,0,-8)
    camera.global_position=keep_center+Vector3(-4,5.4,20);camera.look_at(keep_center+Vector3(10,4.0,4),Vector3.UP);camera.fov=61
    await _save("res://artifacts/castle_internal_stairs.png")
    camera.global_position=keep_center+Vector3(-3,11.2,-17);camera.look_at(keep_center+Vector3(10,8.2,-8.6),Vector3.UP);camera.fov=55
    await _save("res://artifacts/castle_stair_landing.png")
    camera.global_position=keep_center+Vector3(6,28.5,16);camera.look_at(keep_center+Vector3(18,28.5,7),Vector3.UP);camera.fov=54
    await _save("res://artifacts/castle_roof_ladder.png")
    camera.global_position=keep_center+Vector3(48,48,58);camera.look_at(keep_center+Vector3(18,33,6),Vector3.UP);camera.fov=52
    await _save("res://artifacts/castle_roof_hatch.png")
    main.free();quit(0)
