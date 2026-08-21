extends SceneTree

## Repeatable before/after visual review for the major world-art categories.


func _initialize()->void:
    call_deferred("_run")


func _capture(camera:Camera3D,label:String)->void:
    for _frame in range(5):
        await process_frame
        await RenderingServer.frame_post_draw
    var pass_label:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_LABEL")
    if pass_label.is_empty():pass_label="review"
    var path:=ProjectSettings.globalize_path("res://artifacts/world_overhaul_%s_%s.png"%[pass_label,label])
    var error:=root.get_texture().get_image().save_png(path)
    print("WORLD_OVERHAUL_CAPTURE|label=%s|path=%s|error=%d|draw_calls=%d|objects=%d"%[
        label,path,error,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])


func _review(camera:Camera3D,sampler:Callable,label:String,target:Vector2,offset:Vector3,look_offset:=Vector3(0,3,0))->void:
    var ground:Vector3=sampler.call(target.x,target.y)
    camera.global_position=ground+offset
    camera.look_at(ground+look_offset,Vector3.UP)
    await _capture(camera,label)


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=60
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    main.get_node("UI").visible=false
    var result:Dictionary=main.get("_world_result")
    var sampler:Callable=result.get("terrain_height_sampler",result.height_sampler)
    var camera:=Camera3D.new();camera.fov=55.0;camera.near=.16;camera.far=5200.0;main.add_child(camera);camera.current=true
    var requested:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_VIEW")
    var views:Array[Dictionary]=[
        {"label":"riverwatch_street","target":Vector2(-420,70),"offset":Vector3(48,12,58),"look":Vector3(0,3,-16)},
        {"label":"river_bridge","target":Vector2(-420,-98),"offset":Vector3(-74,12,-56),"look":Vector3(0,2,0)},
        {"label":"old_oak_wood","target":Vector2(-690,310),"offset":Vector3(42,12,66),"look":Vector3(0,5,0)},
        {"label":"south_road","target":Vector2(-210,-410),"offset":Vector3(-34,10,54),"look":Vector3(0,2,-24)},
        {"label":"crownspire","target":Vector2(250,-2405),"offset":Vector3(115,62,180),"look":Vector3(0,20,-80)},
    ]
    for view in views:
        if not requested.is_empty() and requested!=str(view.label):continue
        await _review(camera,sampler,str(view.label),view.target,view.offset,view.look)
    main.queue_free();await process_frame;quit(0)
