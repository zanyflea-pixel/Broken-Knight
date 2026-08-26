extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_skeld_region_loaded()
    var player:=main.get_node("Player")
    player.global_position=main._sample_global_height(-7920,-13980)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-13980,-7920)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    for _frame in range(30):await process_frame
    var context:Dictionary=main.get("_region_contexts").get("skeld_coast",{})
    var region_root:Node=context.get("root")
    for branch_name in ["TerrainRoot","RoadRoot","RiverRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var branch:=region_root.get_node_or_null(branch_name)
        print("SKELD_GEOMETRY_BRANCH|%s|%s"%[branch_name,JSON.stringify(_count_geometry(branch))])
    var town_root:=region_root.get_node_or_null("TownRoot")
    if town_root:
        for town in town_root.get_children():
            print("SKELD_GEOMETRY_TOWN|%s|%s"%[town.name,JSON.stringify(_count_geometry(town))])
    print("SKELD_GEOMETRY_GAMEPLAY|%s"%JSON.stringify(_count_geometry(main.get_node("GameplayDirector"))))
    quit()


func _count_geometry(root_node:Node)->Dictionary:
    var counts:={"nodes":0,"meshes":0,"multimeshes":0,"surfaces":0,"collisions":0,"bodies":0,"labels":0}
    if root_node==null:return counts
    var stack:Array[Node]=[root_node]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        counts.nodes+=1
        for child in node.get_children():stack.append(child)
        if node is MultiMeshInstance3D:counts.multimeshes+=1
        elif node is MeshInstance3D:
            counts.meshes+=1
            var mesh:Mesh=node.mesh
            if mesh:counts.surfaces+=mesh.get_surface_count()
        elif node is CollisionShape3D:counts.collisions+=1
        elif node is CollisionObject3D:counts.bodies+=1
        elif node is Label3D:counts.labels+=1
    return counts
