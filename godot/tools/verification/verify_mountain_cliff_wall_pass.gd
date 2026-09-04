extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const EXPECTED_MESHES:=["StratifiedMountainWall","GlacialCirqueWall"]
const ZONES:=["starting_realm","north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches"]


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var kit_scene:=load("res://assets/world/regional_geology_kit_v1.glb") as PackedScene
    if kit_scene==null:
        push_error("regional geology kit could not be loaded")
        quit(1)
        return
    var kit:=kit_scene.instantiate();root.add_child(kit)
    var source_meshes:Dictionary={}
    var stack:Array[Node]=[kit]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node is MeshInstance3D:
            var mesh_instance:=node as MeshInstance3D
            source_meshes[str(node.name)]=mesh_instance.mesh.get_surface_count() if mesh_instance.mesh!=null else 0
    for mesh_name in EXPECTED_MESHES:
        if not source_meshes.has(mesh_name):failures.append("source kit missing %s"%mesh_name)
        elif int(source_meshes[mesh_name])<3:failures.append("%s lost authored material surfaces"%mesh_name)
    kit.free()

    var total:=0
    var out_of_bounds:=0
    var clearance_failures:=0
    var zone_counts:Dictionary={}
    var kind_counts:={"StratifiedMountainWall":0,"GlacialCirqueWall":0}
    for zone_id in ZONES:
        var world:=Node3D.new();root.add_child(world)
        for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
            var child:=Node3D.new();child.name=child_name;world.add_child(child)
        var profile:Dictionary=WorldProfile.new().make_zone_profile(zone_id)
        var terrain:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
        var preview:=WorldPreviewBuilder.new();preview.begin_population(world,profile)
        preview.call("_build_mountain_cliff_walls",world.get_node("PropsRoot"),profile,terrain)
        var props:=world.get_node("PropsRoot")
        var count:=int(props.get_meta("mountain_cliff_wall_count",0))
        var records:Array=props.get_meta("mountain_cliff_wall_records",[])
        var local_kind_counts:Dictionary=props.get_meta("mountain_cliff_wall_kind_counts",{})
        zone_counts[zone_id]=count;total+=count
        if count<1:failures.append("%s has no accepted landform-scale cliff wall"%zone_id)
        if count>profile.get("mountain_chains",[]).size():failures.append("%s placed more than one wall per mountain chain"%zone_id)
        if records.size()!=count:failures.append("%s cliff record count mismatch"%zone_id)
        var collision_body:=props.get_node_or_null("MountainCliffWallCollision")
        if collision_body==null or collision_body.get_child_count()!=count*4:failures.append("%s cliff collision count mismatch"%zone_id)
        for kind in EXPECTED_MESHES:kind_counts[kind]=int(kind_counts[kind])+int(local_kind_counts.get(kind,0))
        var half_extent:=float(profile.get("world_size",7200.0))*.5-120.0
        for record_value in records:
            var record:Dictionary=record_value
            var point:Vector2=record.get("position",Vector2.ZERO)
            var edge_guard:=float(record.get("edge_guard",160.0))
            if absf(point.x)>half_extent-edge_guard or absf(point.y)>half_extent-edge_guard:out_of_bounds+=1
            if preview.call("_is_too_close_to_corridors",point,profile.get("river_corridors",[]),float(record.get("river_clearance",120.0))):clearance_failures+=1
            if preview.call("_is_too_close_to_corridors",point,profile.get("road_corridors",[]),float(record.get("road_clearance",150.0))):clearance_failures+=1
            if preview.call("_is_near_bridge_site",point,profile.get("ford_sites",[]),float(record.get("bridge_clearance",250.0))):clearance_failures+=1
            if preview.call("_is_too_close_to_sites",point,profile.get("town_sites",[]),float(record.get("town_clearance",300.0))):clearance_failures+=1
        world.free()
    if out_of_bounds>0:failures.append("%d cliff walls exceed playable terrain bounds"%out_of_bounds)
    if clearance_failures>0:failures.append("%d cliff walls violate protected travel clearances"%clearance_failures)
    if int(kind_counts.StratifiedMountainWall)<4:failures.append("stratified mountain walls are underrepresented")
    if int(kind_counts.GlacialCirqueWall)<2:failures.append("glacial cirque walls are underrepresented")
    print("MOUNTAIN_CLIFF_WALL_PASS|total=%d|zones=%s|stratified=%d|glacial=%d|out_of_bounds=%d|clearance_failures=%d|source_meshes=%d|failures=%d"%[
        total,str(zone_counts),int(kind_counts.StratifiedMountainWall),int(kind_counts.GlacialCirqueWall),
        out_of_bounds,clearance_failures,source_meshes.size(),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
