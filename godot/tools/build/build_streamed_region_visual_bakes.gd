extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const POPULATION_ROOT_NAMES:=["RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]


func _initialize()->void:
    call_deferred("_build_requested_bakes")


func _build_requested_bakes()->void:
    var selector:=OS.get_environment("BROKEN_KNIGHT_BAKE_ZONE").strip_edges()
    var zones:Array=WorldPreviewBuilder.STREAMED_VISUAL_BAKE_ZONES.duplicate()
    if not selector.is_empty() and selector.to_lower()!="all":zones=[selector]
    var failures:=0
    for zone_value in zones:
        var zone_id:=str(zone_value)
        if zone_id not in WorldPreviewBuilder.STREAMED_VISUAL_BAKE_ZONES:
            push_error("Unknown streamed visual bake zone: %s"%zone_id);failures+=1;continue
        if not await _build_zone(zone_id):failures+=1
        await process_frame
    quit(0 if failures==0 else 1)


func _build_zone(zone_id:String)->bool:
    var started_usec:=Time.get_ticks_usec()
    var world:=Node3D.new();world.name="%sVisualBake"%zone_id.to_pascal_case();root.add_child(world)
    for child_name in ["TerrainRoot"]+POPULATION_ROOT_NAMES:
        var child:=Node3D.new();child.name=child_name;world.add_child(child)
    var profile:Dictionary=WorldProfile.new().make_zone_profile(zone_id)
    var terrain_result:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
    WorldPreviewBuilder.new().populate(world,profile,terrain_result)
    var terrain_root:=world.get_node("TerrainRoot");world.remove_child(terrain_root);terrain_root.free()
    world.set_meta("world_visual_bake_version",WorldPreviewBuilder.STREAMED_VISUAL_BAKE_VERSION)
    world.set_meta("world_visual_bake_signature",WorldPreviewBuilder.streamed_visual_bake_signature(zone_id))
    world.set_meta("zone_id",zone_id)
    world.set_meta("population_root_names",POPULATION_ROOT_NAMES)
    world.set_meta("baked_utc",Time.get_datetime_string_from_system(true))
    for root_name in POPULATION_ROOT_NAMES:
        var population_root:=world.get_node(root_name)
        for meta_name in population_root.get_meta_list():
            population_root.set_meta(meta_name,_encode_node_references(population_root.get_meta(meta_name),world))
    _assign_owner_recursive(world,world)
    var packed:=PackedScene.new()
    var pack_error:=packed.pack(world)
    if pack_error!=OK:
        push_error("Unable to pack %s visual bake: %s"%[zone_id,error_string(pack_error)])
        world.free();return false
    var output_path:=WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
    var absolute_output:=ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    var save_error:=ResourceSaver.save(packed,output_path,ResourceSaver.FLAG_COMPRESS)
    if save_error!=OK:
        push_error("Unable to save %s visual bake: %s"%[zone_id,error_string(save_error)])
        world.free();return false
    var file_size:=FileAccess.get_file_as_bytes(output_path).size()
    print("STREAMED_WORLD_VISUAL_BAKE|zone=%s|path=%s|size_mb=%.2f|build_ms=%.1f|nodes=%d"%[
        zone_id,output_path,float(file_size)/1048576.0,float(Time.get_ticks_usec()-started_usec)/1000.0,_count_nodes(world),
    ])
    world.free()
    return true


func _encode_node_references(value:Variant,bake_root:Node)->Variant:
    if value is Node:return bake_root.get_path_to(value as Node)
    if value is Dictionary:
        var encoded:Dictionary={}
        for key in value:encoded[key]=_encode_node_references(value[key],bake_root)
        return encoded
    if value is Array:
        var encoded_array:Array=[];encoded_array.resize(value.size())
        for index in range(value.size()):encoded_array[index]=_encode_node_references(value[index],bake_root)
        return encoded_array
    return value


func _assign_owner_recursive(node:Node,scene_owner:Node)->void:
    for child in node.get_children():
        child.owner=scene_owner
        _assign_owner_recursive(child,scene_owner)


func _count_nodes(node:Node)->int:
    var count:=1
    for child in node.get_children():count+=_count_nodes(child)
    return count
