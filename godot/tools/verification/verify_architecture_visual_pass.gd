extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var town_root:=main.get_node("WorldRoot/TownRoot")
    var stack:Array[Node]=[town_root]
    var houses:=0
    var house_families:Dictionary={}
    var doors:=0
    var upper_floors:=0
    var house_stairs:=0
    var stair_collision:=0
    var sign_brackets:=0
    var sign_boards:=0
    var missing_detail_meshes:=0
    var chandeliers:=0
    var weapon_racks:=0
    var bookshelves:=0
    var barrels:=0
    var furnished_interiors:=0
    var castle_courtyard_zones:=0
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        var node_name:=str(node.name)
        var detail_kind:=str(node.get_meta("architecture_detail_kind",""))
        if node_name.begins_with("House_"):
            houses+=1
            var family_marker:String=node_name.rsplit("_")[-1]
            house_families[family_marker]=true
            if node.has_meta("upper_floor_y"):upper_floors+=1
        elif node_name=="WorkingHouseDoor":doors+=1
        elif node_name=="HouseInteriorStairRamp":
            house_stairs+=1
            for child in node.get_children():
                if child is StaticBody3D:stair_collision+=1
        elif node_name=="HouseSignBracket":sign_brackets+=1
        elif node_name=="HouseSignBoard":sign_boards+=1
        elif detail_kind=="CastleChandelier":chandeliers+=1
        elif detail_kind=="CastleWeaponRack":weapon_racks+=1
        elif detail_kind in ["FurnitureBookshelf","FurnitureBookcaseFull"]:bookshelves+=1
        elif detail_kind=="FurnitureBarrel":barrels+=1
        elif node_name.begins_with("FurnishedInterior_"):furnished_interiors+=1
        elif node_name=="Castle Courtyard Workshops And Training Yard":castle_courtyard_zones+=1
        if node is MeshInstance3D and not detail_kind.is_empty():
            if (node as MeshInstance3D).mesh==null:missing_detail_meshes+=1
    var failures:Array[String]=[]
    if houses<40:failures.append("too few enterable houses: %d"%houses)
    if house_families.size()<6:failures.append("house family variety missing: %s"%str(house_families.keys()))
    if doors<houses:failures.append("not every house has a working door: %d/%d"%[doors,houses])
    if furnished_interiors<houses:failures.append("not every house is furnished: %d/%d"%[furnished_interiors,houses])
    if upper_floors<12 or house_stairs!=upper_floors:failures.append("multi-storey access mismatch: floors=%d stairs=%d"%[upper_floors,house_stairs])
    if stair_collision!=house_stairs:failures.append("house stair ramps lack collision: %d/%d"%[stair_collision,house_stairs])
    if sign_brackets<10 or sign_brackets!=sign_boards:failures.append("attached sign pairs invalid: brackets=%d boards=%d"%[sign_brackets,sign_boards])
    if missing_detail_meshes>0:failures.append("architecture kit meshes missing: %d"%missing_detail_meshes)
    if castle_courtyard_zones!=1:failures.append("castle courtyard useful zone missing")
    if chandeliers<5 or weapon_racks<8 or bookshelves<8 or barrels<8:failures.append("castle/town furnishing density below target")
    print("ARCHITECTURE_VISUAL_PASS|houses=%d|families=%d|doors=%d|furnished=%d|upper_floors=%d|stairs=%d|stair_collision=%d|signs=%d|chandeliers=%d|weapon_racks=%d|bookshelves=%d|barrels=%d|missing_meshes=%d|failures=%d"%[
        houses,house_families.size(),doors,furnished_interiors,upper_floors,house_stairs,stair_collision,sign_brackets,chandeliers,weapon_racks,bookshelves,barrels,missing_detail_meshes,failures.size()
    ])
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
