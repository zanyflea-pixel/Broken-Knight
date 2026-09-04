extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _run()->void:
    var world:=Node3D.new();root.add_child(world)
    var terrain_root:=Node3D.new();terrain_root.name="TerrainRoot";world.add_child(terrain_root)
    var profile:Dictionary=WorldProfile.new().make_zone_profile("glacial_range")
    var terrain:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var sampler:Callable=terrain.terrain_height_sampler
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-51,-26,0);sun.light_energy=1.18;sun.shadow_enabled=true;world.add_child(sun)
    var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.39,.63,.78);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.66,.69,.71);environment.ambient_light_energy=.92
    var world_environment:=WorldEnvironment.new();world_environment.environment=environment;world.add_child(world_environment)
    var camera:=Camera3D.new();camera.current=true;camera.fov=63.0;world.add_child(camera)
    var glacier_center:=Vector2(0,-1950)
    for site_value in profile.get("map_sites",[]):
        if site_value is Dictionary and str((site_value as Dictionary).get("kind",""))=="glacier":
            glacier_center=(site_value as Dictionary).get("position",glacier_center);break
    var shots:=[
        {"point":glacier_center+Vector2(-320,720),"heading":Vector2(.26,-1).normalized(),"file":"glacial_terrain_walking_v1.png"},
        {"point":glacier_center+Vector2(720,340),"heading":Vector2(-.82,-.57).normalized(),"file":"glacial_moraine_walking_v1.png"},
    ]
    var failures:=0
    for shot in shots:
        var point:Vector2=shot.point
        var heading:Vector2=shot.heading
        var camera_ground:Vector3=sampler.call(point.x,point.y)
        var target_point:=point+heading*145.0
        var target_ground:Vector3=sampler.call(target_point.x,target_point.y)
        camera.global_position=camera_ground+Vector3.UP*2.15
        camera.look_at(target_ground+Vector3.UP*3.1,Vector3.UP)
        await _settle()
        if await _capture("res://artifacts/%s"%str(shot.file))!=OK:failures+=1
    print("GLACIAL_TERRAIN_BLEND_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    world.free();await process_frame;quit(0 if failures==0 else 1)
