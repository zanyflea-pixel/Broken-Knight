extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    root.size=Vector2i(1280,720)
    var output_dir:=ProjectSettings.globalize_path("res://artifacts")
    DirAccess.make_dir_recursive_absolute(output_dir)
    var background:=ColorRect.new()
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.color=Color(.10,.14,.18,1)
    root.add_child(background)
    var packed:=load("res://scenes/Main.tscn") as PackedScene
    await _capture_menu(packed,"UI/PauseMenu",output_dir.path_join("branding_pause.png"))
    await _capture_menu(packed,"UI/HeroMenu",output_dir.path_join("branding_inventory.png"))
    await _capture_menu(packed,"UI/AdminMenu",output_dir.path_join("branding_admin.png"))
    quit()


func _capture_menu(packed:PackedScene,node_path:String,output_path:String)->void:
    var main:Node3D=packed.instantiate()
    main.call("_apply_ui_theme")
    var menu:=main.get_node(node_path) as Control
    menu.get_parent().remove_child(menu)
    main.free()
    menu.visible=true
    root.add_child(menu)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    _save(output_path)
    root.remove_child(menu)
    menu.free()


func _save(path:String)->void:
    var error:=root.get_viewport().get_texture().get_image().save_png(path)
    print("BRANDING_CAPTURE|%s|error=%s"%[path,error])
