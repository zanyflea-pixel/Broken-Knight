extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const EXPECTED_MESHES:=["LayeredCliffFace","BasaltColumnEscarpment","GlacialCrownCrag","CoastalSeaStack"]
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
    var mesh_names:Dictionary={}
    var kit_stack:Array[Node]=[kit]
    while not kit_stack.is_empty():
        var node:Node=kit_stack.pop_back()
        for child in node.get_children():kit_stack.append(child)
        if node is MeshInstance3D:mesh_names[str(node.name)]=true
    for mesh_name in EXPECTED_MESHES:
        if not mesh_names.has(mesh_name):failures.append("source kit missing %s"%mesh_name)
    kit.free()

    var total:=0
    var zone_counts:Dictionary={}
    var global_kind_counts:Dictionary={}
    for mesh_name in EXPECTED_MESHES:global_kind_counts[mesh_name]=0
    for zone_id in ZONES:
        var world:=Node3D.new();root.add_child(world)
        for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
            var child:=Node3D.new();child.name=child_name;world.add_child(child)
        var profile:Dictionary=WorldProfile.new().make_zone_profile(zone_id)
        var terrain:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
        var preview:=WorldPreviewBuilder.new();preview.begin_population(world,profile)
        preview.call("_build_regional_geology",world.get_node("PropsRoot"),profile,terrain)
        var props:=world.get_node("PropsRoot")
        var count:=int(props.get_meta("regional_geology_count",0))
        var kind_counts:Dictionary=props.get_meta("regional_geology_kind_counts",{})
        zone_counts[zone_id]=count;total+=count
        if count<1:failures.append("%s has no accepted regional formations"%zone_id)
        for mesh_name in EXPECTED_MESHES:global_kind_counts[mesh_name]=int(global_kind_counts[mesh_name])+int(kind_counts.get(mesh_name,0))
        var collision_body:=props.get_node_or_null("RegionalGeologyCollision")
        if collision_body==null or collision_body.get_child_count()!=count:failures.append("%s geology collision count mismatch"%zone_id)
        world.free()
    if int(global_kind_counts.BasaltColumnEscarpment)<1:failures.append("Eastern basalt escarpments were not placed")
    if int(global_kind_counts.GlacialCrownCrag)<2:failures.append("northern glacial crags were not placed")
    if int(global_kind_counts.CoastalSeaStack)<1:failures.append("Skeld coastal stacks were not placed")
    if int(global_kind_counts.LayeredCliffFace)<4:failures.append("layered cliffs are underrepresented")
    print("REGIONAL_GEOLOGY_PASS|total=%d|zones=%s|layered=%d|basalt=%d|glacial=%d|coastal=%d|source_meshes=%d|failures=%d"%[
        total,str(zone_counts),int(global_kind_counts.LayeredCliffFace),int(global_kind_counts.BasaltColumnEscarpment),
        int(global_kind_counts.GlacialCrownCrag),int(global_kind_counts.CoastalSeaStack),mesh_names.size(),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
