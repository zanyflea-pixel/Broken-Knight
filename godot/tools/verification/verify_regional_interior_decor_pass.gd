extends SceneTree

const REQUIRED_DETAIL_KINDS:= [
    "FurnitureBookcaseFull",
    "FurnitureKitchenSet",
    "FurnitureWorkshopSet",
    "FurnitureTavernSet",
    "FurnitureGuardPost",
    "FurnitureReadingDesk",
]


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var kit_scene:=load("res://assets/architecture/architecture_detail_kit_v2.glb") as PackedScene
    if kit_scene==null:
        push_error("architecture detail kit v2 could not be loaded")
        quit(1)
        return
    var kit:=kit_scene.instantiate()
    root.add_child(kit)
    var kit_meshes:Dictionary={}
    var kit_stack:Array[Node]=[kit]
    while not kit_stack.is_empty():
        var kit_node:Node=kit_stack.pop_back()
        for child in kit_node.get_children():kit_stack.append(child)
        if kit_node is MeshInstance3D:kit_meshes[str(kit_node.name)]=true
    for kind in REQUIRED_DETAIL_KINDS:
        if not kit_meshes.has(kind):failures.append("Blender kit is missing %s"%kind)
    kit.queue_free()

    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var town_root:=main.get_node("WorldRoot/TownRoot")
    var counts:Dictionary={}
    for kind in REQUIRED_DETAIL_KINDS:counts[kind]=0
    var interior_roles:Dictionary={}
    var missing_meshes:=0
    var collision_aware:=0
    var solid_shapes:=0
    var stack:Array[Node]=[town_root]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node.has_meta("interior_role"):interior_roles[str(node.get_meta("interior_role"))]=true
        var detail_kind:=str(node.get_meta("architecture_detail_kind",""))
        if counts.has(detail_kind):
            counts[detail_kind]=int(counts[detail_kind])+1
            if node is MeshInstance3D and (node as MeshInstance3D).mesh==null:missing_meshes+=1
            if node.has_meta("interior_collision_size"):collision_aware+=1
        if node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:solid_shapes+=1

    if interior_roles.size()<6:failures.append("not all six house roles are authored: %s"%str(interior_roles.keys()))
    for kind in REQUIRED_DETAIL_KINDS:
        if int(counts[kind])<1:failures.append("world placement is missing %s"%kind)
    if int(counts.FurnitureKitchenSet)<5:failures.append("too few furnished kitchens: %d"%int(counts.FurnitureKitchenSet))
    if int(counts.FurnitureTavernSet)<5:failures.append("too few functioning tavern/inn interiors: %d"%int(counts.FurnitureTavernSet))
    if int(counts.FurnitureBookcaseFull)<8:failures.append("too few filled bookcases: %d"%int(counts.FurnitureBookcaseFull))
    if collision_aware<20:failures.append("collision-aware detail count is low: %d"%collision_aware)
    if solid_shapes<100:failures.append("interior/world solid collision population is unexpectedly low: %d"%solid_shapes)
    if missing_meshes>0:failures.append("placed interior sets with missing meshes: %d"%missing_meshes)

    print("REGIONAL_INTERIOR_DECOR|roles=%d|bookcases=%d|kitchens=%d|workshops=%d|taverns=%d|guard_posts=%d|reading_desks=%d|collision_aware=%d|solid_shapes=%d|missing_meshes=%d|failures=%d"%[
        interior_roles.size(),int(counts.FurnitureBookcaseFull),int(counts.FurnitureKitchenSet),int(counts.FurnitureWorkshopSet),
        int(counts.FurnitureTavernSet),int(counts.FurnitureGuardPost),int(counts.FurnitureReadingDesk),collision_aware,solid_shapes,missing_meshes,failures.size(),
    ])
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
