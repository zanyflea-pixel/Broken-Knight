extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=18)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _find_detail(root_node:Node,kind:String)->MeshInstance3D:
    var stack:Array[Node]=[root_node]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node is MeshInstance3D and str(node.get_meta("architecture_detail_kind",""))==kind:
            return node as MeshInstance3D
    return null


func _frame_detail(camera:Camera3D,detail:MeshInstance3D,distance:float,target_height:float)->void:
    var inward:=detail.global_basis.z.normalized()
    camera.global_position=detail.global_position+inward*distance+Vector3.UP*1.75
    camera.look_at(detail.global_position+Vector3.UP*target_height,Vector3.UP)


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    player.visible=false
    main.get_node("UI").visible=false
    (main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D).current=false
    var camera:=Camera3D.new()
    camera.name="InteriorReviewCamera"
    camera.fov=64.0
    camera.current=true
    main.add_child(camera)
    var town_root:=main.get_node("WorldRoot/TownRoot")
    var shots:=[
        {"kind":"FurnitureKitchenSet","file":"interior_kitchen_v1.png","distance":3.0,"height":1.35},
        {"kind":"FurnitureTavernSet","file":"interior_tavern_v1.png","distance":3.1,"height":1.15},
        {"kind":"FurnitureWorkshopSet","file":"interior_workshop_v1.png","distance":3.2,"height":1.55},
        {"kind":"FurnitureReadingDesk","file":"interior_reading_v1.png","distance":2.8,"height":1.20},
        {"kind":"FurnitureGuardPost","file":"castle_guard_post_v1.png","distance":3.4,"height":1.95},
    ]
    var failures:=0
    for shot in shots:
        var detail:=_find_detail(town_root,str(shot.kind))
        if detail==null:
            failures+=1
            continue
        _frame_detail(camera,detail,float(shot.distance),float(shot.height))
        player.global_position=detail.global_position+Vector3.UP*.1
        await _settle(20)
        if await _capture("res://artifacts/%s"%str(shot.file))!=OK:failures+=1
    print("REGIONAL_INTERIOR_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    quit(0 if failures==0 else 1)
