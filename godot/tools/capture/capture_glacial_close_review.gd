extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const WORLD_PROFILE_SCRIPT:Script=preload("res://scripts/world/WorldProfile.gd")
const TERRAIN_BUILDER_SCRIPT:Script=preload("res://scripts/world/TerrainBuilder.gd")
const WORLD_PREVIEW_BUILDER_SCRIPT:Script=preload("res://scripts/world/WorldPreviewBuilder.gd")
const GLACIAL_OFFSET:=Vector2(0.0,-14400.0)


func _initialize()->void:
    call_deferred("_run")


func _capture(path:String)->int:
    # A manually assembled review scene has no boot overlay to keep requesting
    # redraws, so frame_post_draw can wait forever under the headless renderer.
    # Explicitly draw the current camera after its settling frames instead.
    RenderingServer.force_draw(false)
    await process_frame
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _place_camera(camera:Camera3D,height_sampler:Callable,target_xz:Vector2,offset:Vector3,look_lift:float=3.0)->void:
    var local_xz:=target_xz-GLACIAL_OFFSET
    var sampled:Vector3=height_sampler.call(local_xz.x,local_xz.y)
    var target:=Vector3(target_xz.x,sampled.y,target_xz.y)
    camera.global_position=target+offset
    camera.look_at(target+Vector3.UP*look_lift,Vector3.UP)
    for _frame in range(18):
        await process_frame


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    paused=false
    main.process_mode=Node.PROCESS_MODE_ALWAYS
    main._configure_world_lighting()
    main.get_node("UI").visible=false
    var world_profile:RefCounted=WORLD_PROFILE_SCRIPT.new()
    var profile:Dictionary=world_profile.make_zone_profile("glacial_range")
    var terrain_builder:RefCounted=TERRAIN_BUILDER_SCRIPT.new()
    var preview_builder:RefCounted=WORLD_PREVIEW_BUILDER_SCRIPT.new()
    var world_root:Node3D=main.get_node("WorldRoot")
    world_root.position=Vector3(GLACIAL_OFFSET.x,0.0,GLACIAL_OFFSET.y)
    print("GLACIAL_CLOSE_STAGE|terrain_begin")
    var terrain_result:Dictionary=terrain_builder.generate_world(world_root.get_node("TerrainRoot"),profile)
    print("GLACIAL_CLOSE_STAGE|terrain_ready")
    # This review intentionally builds only the layers under inspection. The
    # runtime benchmark still exercises the complete population path, while a
    # river/architecture visual iteration no longer waits for every grass and
    # forest scatter job in three regions.
    preview_builder.begin_population(world_root,profile)
    for stage_index in [0,5]:
        print("GLACIAL_CLOSE_STAGE|population_%d_begin"%stage_index)
        preview_builder.run_population_stage(stage_index,world_root,profile,terrain_result)
        print("GLACIAL_CLOSE_STAGE|population_%d_ready"%stage_index)

    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="GlacialCloseReviewCamera"
    camera.fov=58.0
    camera.current=true
    main.add_child(camera)
    var focus:=OS.get_environment("BROKEN_KNIGHT_GLACIAL_CAPTURE_FOCUS").to_lower()

    await _place_camera(camera,terrain_result.height_sampler,Vector2(-435.0,-13060.0),Vector3(38.0,13.0,44.0),3.2)
    var refuge_error:=await _capture("res://artifacts/glacial_frostline_refuge_v1.png")
    await _place_camera(camera,terrain_result.height_sampler,Vector2(-692.0,-15920.0),Vector3(31.0,11.0,38.0),2.8)
    var survey_shelter_error:=await _capture("res://artifacts/glacial_survey_shelter_v1.png")
    if focus=="nests":
        await _place_camera(camera,terrain_result.height_sampler,Vector2(1260.0,-14220.0),Vector3(-34.0,10.0,38.0),1.8)
        var lower_nest_error:=await _capture("res://artifacts/glacial_lower_rimecrawler_nest_v1.png")
        await _place_camera(camera,terrain_result.height_sampler,Vector2(1460.0,-16250.0),Vector3(-36.0,11.0,40.0),2.0)
        var rimefall_nest_error:=await _capture("res://artifacts/glacial_blue_maw_crawler_nest_v1.png")
        print("GLACIAL_NEST_REVIEW|lower=%d|rimefall=%d"%[lower_nest_error,rimefall_nest_error])
        quit(0 if lower_nest_error==OK and rimefall_nest_error==OK else 1)
        return
    if focus=="shelters":
        var survey_local:=Vector2(-692.0,-15920.0)-GLACIAL_OFFSET
        var survey_sample:Vector3=terrain_result.height_sampler.call(survey_local.x,survey_local.y)
        var survey_ground:=Vector3(-692.0,survey_sample.y,-15920.0)
        camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=520.0
        camera.global_position=survey_ground+Vector3.UP*360.0;camera.look_at(survey_ground,Vector3.FORWARD)
        for _frame in range(10):await process_frame
        var survey_top_error:=await _capture("res://artifacts/glacial_survey_road_top_v1.png")
        print("GLACIAL_CLOSE_REVIEW|refuge=%d|survey_shelter=%d|survey_top=%d"%[refuge_error,survey_shelter_error,survey_top_error])
        quit(0 if refuge_error==OK and survey_shelter_error==OK and survey_top_error==OK else 1)
        return
    await _place_camera(camera,terrain_result.height_sampler,Vector2(-1050.0,-16280.0),Vector3(74.0,23.0,88.0),5.8)
    var observatory_error:=await _capture("res://artifacts/glacial_observatory_v1.png")
    await _place_camera(camera,terrain_result.height_sampler,Vector2(720.0,-17080.0),Vector3(-82.0,27.0,98.0),4.8)
    var rimefall_error:=await _capture("res://artifacts/glacial_rimefall_v1.png")
    await _place_camera(camera,terrain_result.height_sampler,Vector2(850.0,-17470.0),Vector3(-105.0,34.0,120.0),8.0)
    var source_error:=await _capture("res://artifacts/glacial_source_close_before.png")
    var source_local:=Vector2(850.0,-17470.0)-GLACIAL_OFFSET
    var sampled_source:Vector3=terrain_result.height_sampler.call(source_local.x,source_local.y)
    var source_ground:=Vector3(850.0,sampled_source.y,-17470.0)
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=260.0
    camera.global_position=source_ground+Vector3.UP*230.0
    camera.look_at(source_ground,Vector3.FORWARD)
    for _frame in range(12):await process_frame
    var alignment_error:=await _capture("res://artifacts/glacial_source_alignment.png")

    print("GLACIAL_CLOSE_REVIEW|refuge=%d|survey_shelter=%d|observatory=%d|rimefall=%d|source=%d|alignment=%d"%[
        refuge_error,survey_shelter_error,observatory_error,rimefall_error,source_error,alignment_error,
    ])
    quit(0 if refuge_error==OK and survey_shelter_error==OK and observatory_error==OK and rimefall_error==OK and source_error==OK and alignment_error==OK else 1)
