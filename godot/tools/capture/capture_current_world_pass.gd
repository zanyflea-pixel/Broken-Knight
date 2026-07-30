extends SceneTree


func _init()->void:
    call_deferred("_run")


func _save(path:String)->void:
    await RenderingServer.frame_post_draw
    var absolute:=ProjectSettings.globalize_path(path)
    var error:=root.get_viewport().get_texture().get_image().save_png(absolute)
    print("CURRENT_WORLD_CAPTURE|%s|error=%s"%[absolute,error])


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(2.8).timeout

    main.call("_set_map_open",true)
    await create_timer(.35).timeout
    await _save("res://artifacts/current_world_map.png")
    main.call("_set_map_open",false)

    var hero:Node3D=main.get_node("Player")
    var director:Node=main.get_node("GameplayDirector")
    hero.call("equip_item_id","starter_fishing_pole")
    var fish_spot:Dictionary={}
    for interaction in director.get("_interactables"):
        if interaction.get("action","")=="fish":
            fish_spot=interaction
            break
    var camera:=Camera3D.new()
    camera.fov=50
    main.add_child(camera)
    camera.current=true
    main.get_node("UI").visible=false
    if not fish_spot.is_empty():
        hero.global_position=fish_spot.position
        director.call("_start_fishing",fish_spot)
        director.set("_fishing_timer",0.0)
        director.call("_tick_fishing",.12)
        director.set("_fishing_elapsed",.82)
        director.call("_animate_fishing_visual")
        var target:Vector3=fish_spot.get("water_position",hero.global_position+Vector3(0,0,7))
        camera.global_position=target+Vector3(8,3.8,9)
        camera.look_at(target+Vector3.UP*.25,Vector3.UP)
        await create_timer(.18).timeout
        await _save("res://artifacts/current_fishing_bite.png")
        director.call("_finish_fishing",false,"Capture complete")

    var trees:Array=main.get_node("WorldRoot/PropsRoot").get_meta("harvestable_tree_registry",[])
    if not trees.is_empty():
        var tree:Dictionary=trees[mini(12,trees.size()-1)]
        var tree_position:Vector3=tree.position
        camera.global_position=tree_position+Vector3(10,5.4,12)
        camera.look_at(tree_position+Vector3.UP*4.4,Vector3.UP)
        await create_timer(.3).timeout
        await _save("res://artifacts/current_tree_bark_branches.png")

    main.free()
    quit(0)
