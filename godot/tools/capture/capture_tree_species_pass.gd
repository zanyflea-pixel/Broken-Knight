extends SceneTree


func _init()->void:
    call_deferred("_run")


func _save(path:String)->void:
    await create_timer(.25).timeout
    await RenderingServer.frame_post_draw
    var absolute:=ProjectSettings.globalize_path(path)
    var error:=root.get_viewport().get_texture().get_image().save_png(absolute)
    print("TREE_SPECIES_CAPTURE|%s|error=%s"%[absolute,error])


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(2.0).timeout
    main.get_node("UI").visible=false
    var camera:=Camera3D.new()
    camera.fov=48
    main.add_child(camera)
    camera.current=true

    var trees:Array=main.get_node("WorldRoot/PropsRoot").get_meta("harvestable_tree_registry",[])
    var representatives:Dictionary={}
    var representative_scores:Dictionary={}
    var terrain_sampler:Callable=main._world_result.terrain_height_sampler
    for tree in trees:
        var species:String=tree.get("species","")
        if species=="":
            continue
        var position:Vector3=tree.position
        var x_sample:Vector3=terrain_sampler.call(position.x+5.0,position.z)
        var z_sample:Vector3=terrain_sampler.call(position.x,position.z+5.0)
        var slope_score:=absf(x_sample.y-position.y)+absf(z_sample.y-position.y)
        if not representative_scores.has(species) or slope_score<float(representative_scores[species]):
            representatives[species]=tree
            representative_scores[species]=slope_score
    for species in ["oak","birch","maple","pine"]:
        if not representatives.has(species):
            push_error("TREE_SPECIES_CAPTURE_MISSING|%s"%species)
            continue
        var position:Vector3=representatives[species].position
        camera.global_position=position+Vector3(10.5,6.2,13.0)
        camera.look_at(position+Vector3.UP*4.8,Vector3.UP)
        await _save("res://artifacts/tree_species_%s.png"%species)

    main.free()
    quit(0)
