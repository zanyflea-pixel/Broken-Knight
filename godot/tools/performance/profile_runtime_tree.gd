extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled", false)
    root.add_child(main)
    await main.boot_world(Callable(), false, true)
    await process_frame

    var totals: Dictionary = {}
    var branches: Array[Dictionary] = []
    _count_tree(main, totals)
    for child in main.get_children():
        var branch_totals: Dictionary = {}
        _count_tree(child, branch_totals)
        branches.append({"name": str(child.name), "nodes": int(branch_totals.get("Node", 0)), "types": branch_totals})
    branches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.nodes) > int(b.nodes))

    var types: Array[Dictionary] = []
    for type_name in totals:
        if type_name == "Node":
            continue
        types.append({"name": str(type_name), "count": int(totals[type_name])})
    types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
    print("RUNTIME_TREE_TOTAL|nodes=%d|objects=%d|static_memory_mb=%.1f" % [
        int(totals.get("Node", 0)),
        int(Performance.get_monitor(Performance.OBJECT_COUNT)),
        float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
    ])
    for entry in types.slice(0, mini(18, types.size())):
        print("RUNTIME_TREE_TYPE|name=%s|count=%d" % [entry.name, entry.count])
    for branch in branches:
        print("RUNTIME_TREE_BRANCH|name=%s|nodes=%d|collisions=%d|meshes=%d|multimeshes=%d|lights=%d" % [
            branch.name,
            branch.nodes,
            int(branch.types.get("CollisionShape3D", 0)),
            int(branch.types.get("MeshInstance3D", 0)),
            int(branch.types.get("MultiMeshInstance3D", 0)),
            int(branch.types.get("Light3D", 0)),
        ])
    _print_child_branches(main.get_node("WorldRoot"), "WorldRoot")
    _print_child_branches(main.get_node("WorldRoot/PropsRoot"), "PropsRoot")
    _print_child_branches(main.get_node("WorldRoot/TownRoot"), "TownRoot")
    _print_child_branches(main.get_node("GameplayDirector"), "GameplayDirector")
    _print_multimesh_occupancy(main.get_node("WorldRoot/PropsRoot"))
    _print_collision_state(main.get_node("WorldRoot"))
    main.free()
    await process_frame
    quit()


func _count_tree(node: Node, totals: Dictionary) -> void:
    totals["Node"] = int(totals.get("Node", 0)) + 1
    var type_name := node.get_class()
    totals[type_name] = int(totals.get(type_name, 0)) + 1
    if node is Light3D:
        totals["Light3D"] = int(totals.get("Light3D", 0)) + 1
    for child in node.get_children():
        _count_tree(child, totals)


func _print_child_branches(parent: Node, prefix: String) -> void:
    var entries: Array[Dictionary] = []
    for child in parent.get_children():
        var child_totals: Dictionary = {}
        _count_tree(child, child_totals)
        entries.append({"name": str(child.name), "types": child_totals})
    entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a.types.get("Node", 0)) > int(b.types.get("Node", 0))
    )
    for entry in entries.slice(0, mini(24, entries.size())):
        print("RUNTIME_TREE_SUBBRANCH|parent=%s|name=%s|nodes=%d|collisions=%d|meshes=%d|multimeshes=%d" % [
            prefix,
            entry.name,
            int(entry.types.get("Node", 0)),
            int(entry.types.get("CollisionShape3D", 0)),
            int(entry.types.get("MeshInstance3D", 0)),
            int(entry.types.get("MultiMeshInstance3D", 0)),
        ])


func _print_multimesh_occupancy(parent: Node) -> void:
    var groups:Dictionary={}
    _collect_multimeshes(parent,groups)
    var entries:Array[Dictionary]=[]
    for signature in groups:
        var group:Dictionary=groups[signature]
        entries.append({"signature":signature,"nodes":group.nodes,"instances":group.instances})
    entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.nodes)>int(b.nodes))
    for entry in entries.slice(0,mini(24,entries.size())):
        print("RUNTIME_MULTIMESH_GROUP|nodes=%d|instances=%d|avg=%.2f|mesh=%s"%[
            entry.nodes,entry.instances,float(entry.instances)/maxf(1.0,float(entry.nodes)),entry.signature,
        ])


func _collect_multimeshes(node:Node,groups:Dictionary)->void:
    if node is MultiMeshInstance3D:
        var instance:=node as MultiMeshInstance3D
        var multimesh:=instance.multimesh
        if multimesh!=null and multimesh.mesh!=null:
            var mesh:=multimesh.mesh
            var path:=mesh.resource_path
            if path.is_empty():
                var aabb:=mesh.get_aabb()
                path="%s:%.1fx%.1fx%.1f:s%d"%[mesh.get_class(),aabb.size.x,aabb.size.y,aabb.size.z,mesh.get_surface_count()]
            var group:Dictionary=groups.get(path,{"nodes":0,"instances":0})
            group.nodes=int(group.nodes)+1
            group.instances=int(group.instances)+multimesh.instance_count
            groups[path]=group
    for child in node.get_children():
        _collect_multimeshes(child,groups)


func _print_collision_state(parent:Node)->void:
    var state:={"enabled":0,"disabled":0}
    _collect_collision_state(parent,state)
    print("RUNTIME_COLLISION_STATE|enabled=%d|disabled=%d"%[state.enabled,state.disabled])


func _collect_collision_state(node:Node,state:Dictionary)->void:
    if node is CollisionShape3D:
        if (node as CollisionShape3D).disabled:state.disabled=int(state.disabled)+1
        else:state.enabled=int(state.enabled)+1
    for child in node.get_children():
        _collect_collision_state(child,state)
