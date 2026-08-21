extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var world_root:=Node3D.new();root.add_child(world_root)
    for node_name in ["RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var child:=Node3D.new();child.name=node_name;world_root.add_child(child)
    var preview:=WorldPreviewBuilder.new()
    preview.call("_prepare_corridor_spatial_cache",profile)
    preview.run_population_stage(6,world_root,profile,terrain)
    preview.run_population_stage(7,world_root,profile,terrain)
    await process_frame
    await physics_frame

    var houses:=0
    var multistorey:=0
    var house_ramps:=0
    var castle_ramps:=0
    var solid_slopes:=0
    var detail_counts:Dictionary={
        "HouseWindowSurround":0,
        "HouseDoorCanopy":0,
        "HouseWallLantern":0,
        "HouseFlowerBox":0,
        "FurnitureTable":0,
        "FurnitureBed":0,
        "FurnitureChest":0,
    }
    var stack:Array[Node]=[world_root.get_node("TownRoot")]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        var node_name:=str(node.name)
        if node_name.begins_with("House_"):
            houses+=1
            if int(node.get_meta("architecture_storeys",1))==2:multistorey+=1
        if detail_counts.has(node_name):detail_counts[node_name]=int(detail_counts[node_name])+1
        if node_name=="HouseInteriorStairRamp":house_ramps+=1
        elif node_name=="SmoothCastleStairRamp":castle_ramps+=1
        if node_name!="WalkableStairSlopeCollision":continue
        var body:=node as StaticBody3D
        var collision:=body.get_node_or_null("ContinuousStairSlope") as CollisionShape3D
        if collision==null or not collision.shape is BoxShape3D:
            failures.append("stair slope is missing solid box collision")
            continue
        solid_slopes+=1

    if houses<40:failures.append("house population unexpectedly low: %d"%houses)
    if multistorey<12:failures.append("not enough multi-storey houses: %d"%multistorey)
    if house_ramps!=multistorey:failures.append("house stair count mismatch: %d/%d"%[house_ramps,multistorey])
    if castle_ramps<1:failures.append("castle stair visual assembly is missing")
    # Castle flights are batched into one visual MultiMesh, while each of its
    # three slopes remains a separate collision body.
    var expected_slopes:=house_ramps+3
    if solid_slopes!=expected_slopes:failures.append("solid stair slopes missing: %d/%d"%[solid_slopes,expected_slopes])
    for detail_name in detail_counts:
        if int(detail_counts[detail_name])==0:failures.append("%s was not generated"%detail_name)

    print("BUILDING_STAIR_VISUAL|houses=%d|multistorey=%d|house_ramps=%d|castle_ramp_visuals=%d|solid_slopes=%d|windows=%d|canopies=%d|lanterns=%d|flower_boxes=%d|tables=%d|beds=%d|chests=%d|failures=%d"%[
        houses,multistorey,house_ramps,castle_ramps,solid_slopes,
        detail_counts.HouseWindowSurround,detail_counts.HouseDoorCanopy,detail_counts.HouseWallLantern,
        detail_counts.HouseFlowerBox,detail_counts.FurnitureTable,detail_counts.FurnitureBed,
        detail_counts.FurnitureChest,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
