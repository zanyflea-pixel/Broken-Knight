extends Node3D

const TerrainBuilder = preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile = preload("res://scripts/world/WorldProfile.gd")
const WorldPreviewBuilder = preload("res://scripts/world/WorldPreviewBuilder.gd")
const LoreReaderScript=preload("res://scripts/LoreReader.gd")

signal boot_completed

var auto_boot_enabled := true
var _terrain_builder: TerrainBuilder
var _world_profile: WorldProfile
var _preview_builder: WorldPreviewBuilder
var _world_result: Dictionary
var _active_profile: Dictionary = {}
var _menu_open := false
var _map_open := false
var _admin_view := false
var _admin_marker: MeshInstance3D
var _admin_menu_open := false
var _night_mode := false
var _hero_menu_open := false
var _collection_menu: Control
var _vendor_menu_open := false
var _crafting_menu_open:=false
var _lore_reader:Control
var _lore_menu_open:=false
var _world_streaming := false
var _day_cycle_seconds := 3600.0
var _day_clock := 900.0
var _town_torches: Array[Node] = []
var _day_sky_material: Material
var _night_sky_material: Material
var _sky_rotation_accumulator:=0.0
var _active_zone_id:="starting_realm"
var _dungeon_visual_mode:=false
var _build_profile_start_usec:=0
const NORTH_REGION_OFFSET:=Vector2(0.0,-7200.0)
const NORTH_REGION_SEAM_Z:=-3600.0
const GLACIAL_REGION_OFFSET:=Vector2(0.0,-14400.0)
const GLACIAL_REGION_SEAM_Z:=-10800.0
const WESTERN_REGION_OFFSET:=Vector2(-7200.0,0.0)
const WESTERN_REGION_SEAM_X:=-3600.0
const EAST_REGION_OFFSET:=Vector2(7200.0,0.0)
const EAST_REGION_SEAM_X:=3600.0
const STORMBREAK_REGION_OFFSET:=Vector2(-7200.0,-7200.0)
const SKELD_REGION_OFFSET:=Vector2(-7200.0,-14400.0)
const REGION_PRELOAD_Z:=-1800.0
const GLACIAL_PRELOAD_Z:=-7600.0
const WESTERN_PRELOAD_X:=-1800.0
const EAST_PRELOAD_X:=1800.0
const REGION_ACTIVATE_NORTH_Z:=-3300.0
const REGION_ACTIVATE_START_Z:=-3180.0
const REGION_ACTIVATE_GLACIAL_Z:=-10500.0
const REGION_ACTIVATE_FRONTIER_Z:=-10320.0
const REGION_ACTIVATE_WESTERN_X:=-3300.0
const REGION_ACTIVATE_START_FROM_WEST_X:=-3180.0
const REGION_ACTIVATE_EAST_X:=3300.0
const REGION_ACTIVATE_START_FROM_EAST_X:=3180.0
var _region_contexts:Dictionary={}
var _north_region_loading:=false
var _north_region_ready:=false
var _glacial_region_loading:=false
var _glacial_region_ready:=false
var _western_region_loading:=false
var _western_region_ready:=false
var _east_region_loading:=false
var _east_region_ready:=false
var _stormbreak_region_loading:=false
var _stormbreak_region_ready:=false
var _skeld_region_loading:=false
var _skeld_region_ready:=false
var _region_stream_tick:=0.0
var _region_gameplay_transition_busy:=false
var _persistent_region_state:Dictionary={}
var _world_atlas_profile:Dictionary={}
var _planned_north_global_profile:Dictionary={}
var _planned_glacial_global_profile:Dictionary={}
var _planned_western_global_profile:Dictionary={}
var _planned_east_global_profile:Dictionary={}
var _planned_stormbreak_global_profile:Dictionary={}
var _planned_skeld_global_profile:Dictionary={}
var _geographic_region_id:="starting_realm"


func _ready() -> void:
    if auto_boot_enabled:
        call_deferred("_bootstrap_world")


func _bootstrap_world() -> void:
    await boot_world(Callable(), true, false)


func boot_world(progress_callback: Callable = Callable(), show_internal_overlay: bool = true, finish_world_before_enter: bool = false) -> void:
    if not show_internal_overlay:
        $UI.visible = false
    $UI/BootOverlay.visible = show_internal_overlay
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
        _build_profile_start_usec=Time.get_ticks_usec()
    process_mode=Node.PROCESS_MODE_ALWAYS
    get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_size(Vector2i(1280, 720))
    var screen_size := DisplayServer.screen_get_size()
    DisplayServer.window_set_position((screen_size - Vector2i(1280, 720)) / 2)
    DisplayServer.window_set_title("Broken Knight")
    _report_boot_status("Preparing world systems...", 10.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    _report_boot_status("Configuring world lighting...", 14.0, progress_callback, show_internal_overlay)
    _configure_world_lighting()
    _report_boot_status("Creating world builders...", 18.0, progress_callback, show_internal_overlay)
    _world_profile = WorldProfile.new()
    _terrain_builder = TerrainBuilder.new()
    _preview_builder = WorldPreviewBuilder.new()

    _report_boot_status("Generating world profile...", 24.0, progress_callback, show_internal_overlay)
    var profile: Dictionary = _world_profile.make_zone_profile(_active_zone_id)
    _active_profile = profile
    var profile_world_size: float = profile.get("world_size", 600.0)
    $AdminCamera.size = profile_world_size * 1.08
    $AdminCamera.position.y = maxf(700.0, profile_world_size * 0.78)
    _report_boot_status("Building terrain...", 34.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    _world_result = _terrain_builder.generate_world($WorldRoot/TerrainRoot, profile)
    _register_region_context("starting_realm",$WorldRoot,Vector2.ZERO,profile,_world_result,_terrain_builder,_preview_builder)
    var planned_north_profile:Dictionary=_world_profile.make_zone_profile("north_frontier")
    _planned_north_global_profile=_world_profile.offset_profile(planned_north_profile,planned_north_profile.get("region_origin",NORTH_REGION_OFFSET))
    var planned_glacial_profile:Dictionary=_world_profile.make_zone_profile("glacial_range")
    _planned_glacial_global_profile=_world_profile.offset_profile(planned_glacial_profile,planned_glacial_profile.get("region_origin",GLACIAL_REGION_OFFSET))
    var planned_western_profile:Dictionary=_world_profile.make_zone_profile("western_reaches")
    _planned_western_global_profile=_world_profile.offset_profile(planned_western_profile,planned_western_profile.get("region_origin",WESTERN_REGION_OFFSET))
    var planned_east_profile:Dictionary=_world_profile.make_zone_profile("east_marches")
    _planned_east_global_profile=_world_profile.offset_profile(planned_east_profile,planned_east_profile.get("region_origin",EAST_REGION_OFFSET))
    var planned_stormbreak_profile:Dictionary=_world_profile.make_zone_profile("stormbreak_highlands")
    _planned_stormbreak_global_profile=_world_profile.offset_profile(planned_stormbreak_profile,planned_stormbreak_profile.get("region_origin",STORMBREAK_REGION_OFFSET))
    var planned_skeld_profile:Dictionary=_world_profile.make_zone_profile("skeld_coast")
    _planned_skeld_global_profile=_world_profile.offset_profile(planned_skeld_profile,planned_skeld_profile.get("region_origin",SKELD_REGION_OFFSET))
    _profile_build_checkpoint("terrain")
    _report_boot_status("Starting gameplay systems...", 58.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    _position_player(_world_result.spawn_position)
    var global_start_profile:Dictionary=_region_contexts["starting_realm"].global_profile
    _active_profile=global_start_profile
    $GameplayDirector.configure($Player, Callable(self,"_sample_global_height"), Callable(self,"_sample_global_walkable"), global_start_profile)
    if not $Player.environment_damage_requested.is_connected($GameplayDirector.apply_environment_damage):
        $Player.environment_damage_requested.connect($GameplayDirector.apply_environment_damage)
    _profile_build_checkpoint("gameplay")
    _create_admin_marker()
    _report_boot_status("Preparing maps and interface...", 76.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    # Maps shade terrain only; roads, trails and bridges are drawn as their own
    # layers. Sampling the raw cached heightfield avoids tens of thousands of
    # unnecessary road/bridge corridor checks at startup and while travelling.
    _refresh_world_atlas()
    $UI/WorldMap.teleport_requested.connect(_teleport_from_world_map)
    $UI/WorldMap.visible = false
    $UI/AdminHint.visible = false
    _wire_menu()
    $UI/AdminMenu.configure(self, $GameplayDirector)
    $UI/AdminMenu.close_requested.connect(_set_admin_menu.bind(false))
    $UI/HeroMenu.configure($Player, $GameplayDirector)
    $UI/HeroMenu.close_requested.connect(_set_hero_menu.bind(false))
    for menu in [$UI/BagMenu,$UI/SkillsMenu,$UI/QuestMenu]: menu.configure($Player,$GameplayDirector);menu.close_requested.connect(_close_collection_menu)
    $UI/VendorMenu.configure($Player,$GameplayDirector)
    $UI/VendorMenu.close_requested.connect(_close_vendor_menu)
    $GameplayDirector.vendor_requested.connect(_open_vendor_menu)
    $UI/CraftingMenu.configure($Player,$GameplayDirector)
    $UI/CraftingMenu.close_requested.connect(_close_crafting_menu)
    $GameplayDirector.crafting_requested.connect(_open_crafting_menu)
    $GameplayDirector.notification_requested.connect($UI/OldHud.show_notification)
    $GameplayDirector.lore_requested.connect(_open_lore_reader)
    $GameplayDirector.zone_travel_requested.connect(_load_zone)
    _apply_ui_theme()
    _set_menu_open(false)
    _profile_build_checkpoint("ready")
    if finish_world_before_enter:
        _report_boot_status("Finishing world details...", 86.0, progress_callback, show_internal_overlay)
        await get_tree().process_frame
        await _stream_world_preview(profile, progress_callback, show_internal_overlay)
        await get_tree().process_frame
        await get_tree().process_frame
        $UI/BootOverlay.visible = false
    else:
        _report_boot_status("Entering world...", 88.0, progress_callback, show_internal_overlay)
        await get_tree().process_frame
        $UI/BootOverlay.visible = false
        await get_tree().process_frame
        await _stream_world_preview(profile, progress_callback, show_internal_overlay)
    $UI.visible = true
    boot_completed.emit()


func _stream_world_preview(profile: Dictionary, progress_callback: Callable = Callable(), show_internal_overlay: bool = false) -> void:
    _world_streaming = true
    if _active_zone_id == "starting_realm" and await _try_install_starting_visual_bake(progress_callback, show_internal_overlay):
        $GameplayDirector.refresh_populated_world_registries()
        _town_torches = get_tree().get_nodes_in_group("town_torches")
        _profile_build_checkpoint("world_visuals_baked")
        DisplayServer.window_set_title("Broken Knight")
        _report_boot_status("Ready.", 100.0, progress_callback, show_internal_overlay)
        _world_streaming = false
        return
    _preview_builder.begin_population($WorldRoot, profile)
    var stage_count: int = _preview_builder.get_population_stage_count()
    DisplayServer.window_set_title("Broken Knight")
    for stage_idx in range(stage_count):
        var stage_label: String = _preview_builder.get_population_stage_label(stage_idx)
        var player_facing_label := _boot_stage_label(stage_label)
        _report_boot_status(player_facing_label, 88.0 + (10.0 * float(stage_idx) / maxf(1.0, float(stage_count))), progress_callback, show_internal_overlay)
        await get_tree().process_frame
        _preview_builder.run_population_stage(stage_idx, $WorldRoot, profile, _world_result, _build_profile_start_usec)
        await get_tree().process_frame
    $GameplayDirector.refresh_populated_world_registries()
    # The stage loop grows to tens of thousands of nodes. Scanning the complete
    # tree after every stage made each later loading step progressively slower;
    # the torch registry is only consumed after population is complete.
    _town_torches = get_tree().get_nodes_in_group("town_torches")
    _profile_build_checkpoint("world_visuals")
    DisplayServer.window_set_title("Broken Knight")
    _report_boot_status("Ready.", 100.0, progress_callback, show_internal_overlay)
    _world_streaming = false


func _try_install_starting_visual_bake(progress_callback:Callable,show_internal_overlay:bool)->bool:
    if OS.get_environment("BROKEN_KNIGHT_DISABLE_VISUAL_BAKE")=="1":return false
    var bake_path: String = WorldPreviewBuilder.STARTING_VISUAL_BAKE_PATH
    if not ResourceLoader.exists(bake_path):return false
    _report_boot_status("Loading the settled realm...", 90.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    var packed := load(bake_path) as PackedScene
    if packed==null:return false
    var baked_root := packed.instantiate() as Node3D
    if baked_root==null:return false
    var expected_signature:=WorldPreviewBuilder.starting_visual_bake_signature()
    if int(baked_root.get_meta("world_visual_bake_version",-1))!=WorldPreviewBuilder.STARTING_VISUAL_BAKE_VERSION or str(baked_root.get_meta("world_visual_bake_signature",""))!=expected_signature:
        baked_root.free()
        print("STARTING_WORLD_VISUAL_BAKE|status=stale|fallback=procedural")
        return false
    var root_names:Array=baked_root.get_meta("population_root_names",[])
    for root_name_value in root_names:
        var root_name:=str(root_name_value)
        var baked_population_root:=baked_root.get_node_or_null(root_name) as Node3D
        var current_population_root:Node=$WorldRoot.get_node_or_null(root_name)
        if baked_population_root==null:
            baked_root.free()
            return false
        baked_root.remove_child(baked_population_root)
        _clear_runtime_scene_owners(baked_population_root)
        if current_population_root!=null:
            $WorldRoot.remove_child(current_population_root)
            current_population_root.free()
        $WorldRoot.add_child(baked_population_root)
        baked_population_root.name=root_name
    baked_root.free()
    for root_name_value in root_names:
        var population_root:Node=$WorldRoot.get_node(str(root_name_value))
        for meta_name in population_root.get_meta_list():
            population_root.set_meta(meta_name,_resolve_baked_node_references(population_root.get_meta(meta_name),$WorldRoot))
    print("STARTING_WORLD_VISUAL_BAKE|status=loaded|signature=%s"%expected_signature.left(12))
    return true


func _try_install_streamed_visual_bake(zone_id:String,region_root:Node3D)->bool:
    if OS.get_environment("BROKEN_KNIGHT_DISABLE_VISUAL_BAKE")=="1":return false
    var bake_path:=WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
    if not ResourceLoader.exists(bake_path):return false
    var started_usec:=Time.get_ticks_usec()
    var request_error:=ResourceLoader.load_threaded_request(bake_path,"PackedScene",true)
    if request_error!=OK:return false
    var load_status:=ResourceLoader.load_threaded_get_status(bake_path)
    while load_status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        await get_tree().process_frame
        load_status=ResourceLoader.load_threaded_get_status(bake_path)
    if load_status!=ResourceLoader.THREAD_LOAD_LOADED:return false
    var packed:=ResourceLoader.load_threaded_get(bake_path) as PackedScene
    if packed==null:return false
    var instantiate_started_usec:=Time.get_ticks_usec()
    var baked_root:=packed.instantiate() as Node3D
    var instantiate_usec:=Time.get_ticks_usec()-instantiate_started_usec
    if baked_root==null:return false
    var expected_signature:=WorldPreviewBuilder.streamed_visual_bake_signature(zone_id)
    if int(baked_root.get_meta("world_visual_bake_version",-1))!=WorldPreviewBuilder.STREAMED_VISUAL_BAKE_VERSION or str(baked_root.get_meta("world_visual_bake_signature",""))!=expected_signature:
        baked_root.free()
        print("STREAMED_WORLD_VISUAL_BAKE|zone=%s|status=stale|fallback=procedural"%zone_id)
        return false
    var root_names:Array=baked_root.get_meta("population_root_names",[])
    for root_name_value in root_names:
        var root_name:=str(root_name_value)
        var baked_population_root:=baked_root.get_node_or_null(root_name) as Node3D
        var current_population_root:=region_root.get_node_or_null(root_name)
        if baked_population_root==null:
            baked_root.free();return false
        baked_root.remove_child(baked_population_root)
        _clear_runtime_scene_owners(baked_population_root)
        if current_population_root!=null:
            region_root.remove_child(current_population_root);current_population_root.free()
        region_root.add_child(baked_population_root);baked_population_root.name=root_name
    baked_root.free()
    for root_name_value in root_names:
        var population_root:=region_root.get_node(str(root_name_value))
        for meta_name in population_root.get_meta_list():
            population_root.set_meta(meta_name,_resolve_baked_node_references(population_root.get_meta(meta_name),region_root))
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
        print("STREAMED_WORLD_VISUAL_BAKE|zone=%s|status=loaded|instantiate_ms=%.1f|total_ms=%.1f|signature=%s"%[
            zone_id,float(instantiate_usec)/1000.0,float(Time.get_ticks_usec()-started_usec)/1000.0,expected_signature.left(12),
        ])
    return true


func _clear_runtime_scene_owners(node:Node)->void:
    node.owner=null
    for child in node.get_children():_clear_runtime_scene_owners(child)


func _resolve_baked_node_references(value:Variant,bake_root:Node)->Variant:
    if value is NodePath:
        return bake_root.get_node_or_null(value as NodePath)
    if value is Dictionary:
        var resolved:Dictionary={}
        for key in value:resolved[key]=_resolve_baked_node_references(value[key],bake_root)
        return resolved
    if value is Array:
        var resolved_array:Array=[];resolved_array.resize(value.size())
        for index in range(value.size()):resolved_array[index]=_resolve_baked_node_references(value[index],bake_root)
        return resolved_array
    return value


func _register_region_context(zone_id:String,region_root:Node3D,offset:Vector2,local_profile:Dictionary,result:Dictionary,terrain_builder:Object,preview_builder:Object)->void:
    _region_contexts[zone_id]={
        "id":zone_id,"root":region_root,"offset":offset,
        "local_profile":local_profile,
        "global_profile":_world_profile.offset_profile(local_profile,offset),
        "result":result,"terrain_builder":terrain_builder,"preview_builder":preview_builder,
    }


func _make_streamed_region_root(zone_id:String,offset:Vector2)->Node3D:
    var streamed_root:Node3D=$WorldRoot.get_node_or_null("StreamedRegions")
    if streamed_root==null:
        streamed_root=Node3D.new();streamed_root.name="StreamedRegions";$WorldRoot.add_child(streamed_root)
    var region_root:=Node3D.new()
    region_root.name=zone_id.to_pascal_case()
    region_root.position=Vector3(offset.x,0.0,offset.y)
    streamed_root.add_child(region_root)
    for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var child:=Node3D.new();child.name=child_name;region_root.add_child(child)
    return region_root


func _ensure_north_region_loaded()->void:
    await _ensure_streamed_region_loaded("north_frontier")


func _ensure_glacial_region_loaded()->void:
    # Terrain queries between Riverwatch and the range pass through the
    # frontier, so retain a contiguous three-region chain even for map travel.
    await _ensure_streamed_region_loaded("north_frontier")
    await _ensure_streamed_region_loaded("glacial_range")


func _ensure_western_region_loaded()->void:
    await _ensure_streamed_region_loaded("western_reaches")


func _ensure_east_region_loaded()->void:
    await _ensure_streamed_region_loaded("east_marches")


func _ensure_stormbreak_region_loaded()->void:
    await _ensure_streamed_region_loaded("stormbreak_highlands")


func _ensure_skeld_region_loaded()->void:
    await _ensure_streamed_region_loaded("skeld_coast")


func _stream_region_ready(zone_id:String)->bool:
    if zone_id=="north_frontier":return _north_region_ready
    if zone_id=="glacial_range":return _glacial_region_ready
    if zone_id=="western_reaches":return _western_region_ready
    if zone_id=="east_marches":return _east_region_ready
    if zone_id=="stormbreak_highlands":return _stormbreak_region_ready
    if zone_id=="skeld_coast":return _skeld_region_ready
    return _region_contexts.has(zone_id)


func _stream_region_loading(zone_id:String)->bool:
    if zone_id=="north_frontier":return _north_region_loading
    if zone_id=="glacial_range":return _glacial_region_loading
    if zone_id=="western_reaches":return _western_region_loading
    if zone_id=="east_marches":return _east_region_loading
    if zone_id=="stormbreak_highlands":return _stormbreak_region_loading
    if zone_id=="skeld_coast":return _skeld_region_loading
    return false


func _set_stream_region_loading(zone_id:String,value:bool)->void:
    if zone_id=="north_frontier":_north_region_loading=value
    elif zone_id=="glacial_range":_glacial_region_loading=value
    elif zone_id=="western_reaches":_western_region_loading=value
    elif zone_id=="east_marches":_east_region_loading=value
    elif zone_id=="stormbreak_highlands":_stormbreak_region_loading=value
    elif zone_id=="skeld_coast":_skeld_region_loading=value


func _set_stream_region_ready(zone_id:String,value:bool)->void:
    if zone_id=="north_frontier":_north_region_ready=value
    elif zone_id=="glacial_range":_glacial_region_ready=value
    elif zone_id=="western_reaches":_western_region_ready=value
    elif zone_id=="east_marches":_east_region_ready=value
    elif zone_id=="stormbreak_highlands":_stormbreak_region_ready=value
    elif zone_id=="skeld_coast":_skeld_region_ready=value


func _ensure_streamed_region_loaded(zone_id:String)->void:
    if _stream_region_ready(zone_id):return
    if _stream_region_loading(zone_id):
        while _stream_region_loading(zone_id):await get_tree().process_frame
        return
    _set_stream_region_loading(zone_id,true)
    var local_profile:Dictionary=_world_profile.make_zone_profile(zone_id)
    var fallback_offset:=NORTH_REGION_OFFSET
    if zone_id=="glacial_range":fallback_offset=GLACIAL_REGION_OFFSET
    elif zone_id=="western_reaches":fallback_offset=WESTERN_REGION_OFFSET
    elif zone_id=="east_marches":fallback_offset=EAST_REGION_OFFSET
    elif zone_id=="stormbreak_highlands":fallback_offset=STORMBREAK_REGION_OFFSET
    elif zone_id=="skeld_coast":fallback_offset=SKELD_REGION_OFFSET
    var offset:Vector2=local_profile.get("region_origin",fallback_offset)
    var region_root:=_make_streamed_region_root(zone_id,offset)
    var terrain_builder:=TerrainBuilder.new()
    var preview_builder:=WorldPreviewBuilder.new()
    var stream_started_usec:int=Time.get_ticks_usec()
    var terrain_started_usec:int=0
    var terrain_elapsed_usec:int=0
    var slowest_job_usec:int=0
    var slowest_job_label:=""
    # Terrain creation is cache-backed and happens while the player is still
    # more than a kilometre inside Northwood. Visual population is then spread
    # across frames so the crossing itself remains hitch-free.
    await get_tree().process_frame
    terrain_started_usec=Time.get_ticks_usec()
    var result:Dictionary=terrain_builder.generate_world(region_root.get_node("TerrainRoot"),local_profile)
    terrain_elapsed_usec=Time.get_ticks_usec()-terrain_started_usec
    _register_region_context(zone_id,region_root,offset,local_profile,result,terrain_builder,preview_builder)
    var visual_bake_loaded:=await _try_install_streamed_visual_bake(zone_id,region_root)
    if not visual_bake_loaded:
        preview_builder.begin_population(region_root,local_profile)
        # A population stage can contain several costly scatter passes. Yield for
        # each real job, not merely once for the whole stage, so riding north never
        # asks a single frame to grow forests, grass and settlements together.
        for stage_index in range(preview_builder.get_population_stage_count()):
            for job_index in range(preview_builder.get_population_stage_job_count(stage_index,local_profile)):
                await get_tree().process_frame
                var job_started_usec:int=Time.get_ticks_usec()
                preview_builder.run_population_stage_job(stage_index,job_index,region_root,local_profile,result)
                var job_elapsed_usec:int=Time.get_ticks_usec()-job_started_usec
                if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
                    print("REGION_STREAM_JOB|zone=%s|stage=%d|job=%d|label=%s|elapsed_ms=%.1f"%[
                        zone_id,stage_index,job_index,preview_builder.get_population_stage_label(stage_index),
                        float(job_elapsed_usec)/1000.0,
                    ])
                if job_elapsed_usec>slowest_job_usec:
                    slowest_job_usec=job_elapsed_usec
                    slowest_job_label="%s/%d"%[preview_builder.get_population_stage_label(stage_index),job_index]
    # The region is loaded several kilometres before its seam. Exercise its
    # terrain and landmark materials in a tiny offscreen viewport now, while
    # the normal incremental preload is already running. This prevents shader
    # and visibility pipelines from compiling on the first player-visible turn
    # toward a distant settlement, without moving or dismounting the hero.
    await _warm_streamed_region_render(zone_id,local_profile,offset)
    _set_stream_region_ready(zone_id,true)
    _set_stream_region_loading(zone_id,false)
    _refresh_world_atlas()
    $GameplayDirector.refresh_populated_world_registries()
    _town_torches=get_tree().get_nodes_in_group("town_torches")
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
        print("REGION_STREAM_PROFILE|zone=%s|terrain_ms=%.1f|visual_bake=%s|slowest_job=%s|slowest_job_ms=%.1f|total_ms=%.1f"%[
            zone_id,float(terrain_elapsed_usec)/1000.0,str(visual_bake_loaded),slowest_job_label,float(slowest_job_usec)/1000.0,
            float(Time.get_ticks_usec()-stream_started_usec)/1000.0,
        ])
    var opened_name:=str(local_profile.get("zone_name",zone_id))
    $UI/OldHud.show_notification("%s is ready"%opened_name,Color(.66,.86,1.0))


func _warm_streamed_region_render(zone_id:String,profile:Dictionary,offset:Vector2)->void:
    if DisplayServer.get_name().to_lower()=="headless":return
    if OS.get_environment("BROKEN_KNIGHT_DISABLE_REGION_PREWARM").strip_edges()=="1":return
    var candidates:Array[Vector2]=[]
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty():
        candidates.append(Vector2(spawn_site.get("position",Vector2.ZERO))+offset)
    for site_key in ["town_sites","map_sites","landmark_sites"]:
        for site_value in profile.get(site_key,[]):
            if not site_value is Dictionary:continue
            var candidate:=Vector2(site_value.get("position",Vector2.ZERO))+offset
            if candidates.all(func(existing:Vector2)->bool:return existing.distance_to(candidate)>180.0):
                candidates.append(candidate)
    if candidates.is_empty():return
    # Greedy farthest-point selection covers the region's distinct horizons
    # with no more than five low-resolution frames.
    var warm_points:Array[Vector2]=[candidates.pop_front()]
    while not candidates.is_empty() and warm_points.size()<5:
        var best_index:=0
        var best_distance:=-1.0
        for index in range(candidates.size()):
            var nearest:=INF
            for selected in warm_points:
                nearest=minf(nearest,candidates[index].distance_squared_to(selected))
            if nearest>best_distance:
                best_distance=nearest
                best_index=index
        warm_points.append(candidates.pop_at(best_index))
    var warm_viewport:=SubViewport.new()
    warm_viewport.name="%sRenderWarmup"%zone_id.to_pascal_case()
    warm_viewport.size=Vector2i(192,108)
    warm_viewport.disable_3d=false
    warm_viewport.gui_disable_input=true
    warm_viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
    warm_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
    add_child(warm_viewport)
    warm_viewport.world_3d=get_viewport().world_3d
    var warm_camera:=Camera3D.new()
    warm_camera.name="WarmCamera"
    warm_camera.near=.15
    warm_camera.far=950.0
    warm_camera.fov=75.0
    warm_viewport.add_child(warm_camera)
    warm_camera.current=true
    for point in warm_points:
        var ground:=_sample_global_terrain_height(point.x,point.y)
        warm_camera.global_position=ground+Vector3(52.0,32.0,58.0)
        warm_camera.look_at(ground+Vector3.UP*6.0,Vector3.UP)
        warm_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
    warm_viewport.queue_free()
    await get_tree().process_frame
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
        print("REGION_RENDER_PREWARM|zone=%s|points=%d"%[zone_id,warm_points.size()])


func _refresh_world_atlas()->void:
    if not _region_contexts.has("starting_realm"):return
    var profiles:Array=[_region_contexts["starting_realm"].global_profile]
    if _region_contexts.has("north_frontier"):profiles.append(_region_contexts["north_frontier"].global_profile)
    elif not _planned_north_global_profile.is_empty():profiles.append(_planned_north_global_profile)
    if _region_contexts.has("glacial_range"):profiles.append(_region_contexts["glacial_range"].global_profile)
    elif not _planned_glacial_global_profile.is_empty():profiles.append(_planned_glacial_global_profile)
    if _region_contexts.has("western_reaches"):profiles.append(_region_contexts["western_reaches"].global_profile)
    elif not _planned_western_global_profile.is_empty():profiles.append(_planned_western_global_profile)
    if _region_contexts.has("east_marches"):profiles.append(_region_contexts["east_marches"].global_profile)
    elif not _planned_east_global_profile.is_empty():profiles.append(_planned_east_global_profile)
    if _region_contexts.has("stormbreak_highlands"):profiles.append(_region_contexts["stormbreak_highlands"].global_profile)
    elif not _planned_stormbreak_global_profile.is_empty():profiles.append(_planned_stormbreak_global_profile)
    if _region_contexts.has("skeld_coast"):profiles.append(_region_contexts["skeld_coast"].global_profile)
    elif not _planned_skeld_global_profile.is_empty():profiles.append(_planned_skeld_global_profile)
    _world_atlas_profile=_world_profile.make_world_atlas(profiles)
    _world_atlas_profile["stream_revision"]=(1 if _north_region_ready else 0)+(2 if _glacial_region_ready else 0)+(4 if _western_region_ready else 0)+(8 if _stormbreak_region_ready else 0)+(16 if _skeld_region_ready else 0)+(32 if _east_region_ready else 0)
    $UI/WorldMap.configure(_world_atlas_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
    $UI/Minimap.configure(_world_atlas_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
    var extent:Vector2=_world_atlas_profile.get("map_extent",Vector2.ONE*7200.0)
    var center:Vector2=_world_atlas_profile.get("map_center",Vector2.ZERO)
    $AdminCamera.size=maxf(extent.x,extent.y)*1.04
    $AdminCamera.position.x=center.x;$AdminCamera.position.z=center.y
    $AdminCamera.position.y=maxf(700.0,maxf(extent.x,extent.y)*.78)


func _region_context_for_point(x:float,z:float)->Dictionary:
    var world_point:=Vector2(x,z)
    var best_context:Dictionary={}
    var best_distance:=INF
    for context_value in _region_contexts.values():
        if not context_value is Dictionary:continue
        var context:Dictionary=context_value
        var offset:Vector2=context.get("offset",Vector2.ZERO)
        var local:=world_point-offset
        var half_size:=float(context.get("local_profile",{}).get("world_size",7200.0))*.5001
        if absf(local.x)>half_size or absf(local.y)>half_size:continue
        var distance:=local.length_squared()
        if distance<best_distance:
            best_distance=distance
            best_context=context
    return best_context


func _sample_global_height(x:float,z:float)->Vector3:
    var context:=_region_context_for_point(x,z)
    if context.is_empty():return Vector3(x,0.0,z)
    var offset:Vector2=context.offset
    var local_point:=Vector2(x,z)-offset
    var sampled:Vector3=context.result.height_sampler.call(local_point.x,local_point.y)
    return Vector3(x,sampled.y,z)


func _sample_global_terrain_height(x:float,z:float)->Vector3:
    var context:=_region_context_for_point(x,z)
    if context.is_empty():return Vector3(x,0.0,z)
    var offset:Vector2=context.offset
    var local_point:=Vector2(x,z)-offset
    var sampled:Vector3=context.result.terrain_height_sampler.call(local_point.x,local_point.y)
    return Vector3(x,sampled.y,z)


func _sample_global_structure_height(x:float,z:float,current_y:float)->float:
    var context:=_region_context_for_point(x,z)
    if context.is_empty():return current_y
    var offset:Vector2=context.offset
    var local_point:=Vector2(x,z)-offset
    return float(context.result.structure_height_sampler.call(local_point.x,local_point.y,current_y))


func _sample_global_walkable(x:float,z:float)->bool:
    var context:=_region_context_for_point(x,z)
    if context.is_empty():return false
    var offset:Vector2=context.offset
    var local_point:=Vector2(x,z)-offset
    var world_size:float=float(context.local_profile.get("world_size",7200.0))
    var near_loaded_seam:=_near_loaded_streaming_seam(context,local_point,world_size)
    if not near_loaded_seam and (absf(local_point.x)>=world_size*.49 or absf(local_point.y)>=world_size*.49):return false
    if near_loaded_seam:
        # Local zone samplers intentionally guard their outer 2%. At the one
        # authored seamless edge, sample the matching inner row so that guard
        # cannot become an invisible wall across the pass.
        local_point.x=clampf(local_point.x,-world_size*.485,world_size*.485)
        local_point.y=clampf(local_point.y,-world_size*.485,world_size*.485)
    return bool(context.result.walkable_sampler.call(local_point.x,local_point.y))


func _near_loaded_streaming_seam(context:Dictionary,local_point:Vector2,world_size:float)->bool:
    var context_id:=str(context.get("id",""))
    for seam_value in context.get("local_profile",{}).get("seam_edges",[]):
        if not seam_value is Dictionary:continue
        var seam:Dictionary=seam_value
        var seam_key:=str(seam.get("key",""))
        var partner_loaded:=false
        for other_value in _region_contexts.values():
            if not other_value is Dictionary:continue
            var other:Dictionary=other_value
            if str(other.get("id",""))==context_id:continue
            for other_seam_value in other.get("local_profile",{}).get("seam_edges",[]):
                if other_seam_value is Dictionary and str(other_seam_value.get("key",""))==seam_key:
                    partner_loaded=true
                    break
            if partner_loaded:break
        if not partner_loaded:continue
        var edge:=str(seam.get("edge",""))
        var distance:=INF
        if edge=="north":distance=absf(world_size*.5-local_point.y)
        elif edge=="south":distance=absf(local_point.y+world_size*.5)
        elif edge=="east":distance=absf(world_size*.5-local_point.x)
        elif edge=="west":distance=absf(local_point.x+world_size*.5)
        if distance<125.0:return true
    return false


func _update_region_streaming(delta:float)->void:
    if not is_instance_valid($Player) or (_dungeon_visual_mode and $Player.is_interior_mode()):return
    if _active_zone_id not in ["starting_realm","north_frontier","glacial_range","western_reaches","east_marches","stormbreak_highlands","skeld_coast"]:return
    _region_stream_tick+=delta
    if _region_stream_tick<.22:return
    _region_stream_tick=0.0
    var player_z:float=$Player.global_position.z
    var player_x:float=$Player.global_position.x
    # Only preload a cardinal neighbor while the player is actually travelling
    # through that neighbor's approach corridor. The previous sign-only checks
    # loaded Northwood from far-eastern Cinderwatch (and the Western Reaches at
    # the starter spawn), causing unrelated multi-second construction spikes.
    var in_central_north_corridor:=absf(player_x)<4200.0
    var in_central_west_east_corridor:=absf(player_z)<4200.0
    if player_z<REGION_PRELOAD_Z and in_central_north_corridor and not _north_region_ready and not _north_region_loading:
        _ensure_north_region_loaded()
    if player_z<GLACIAL_PRELOAD_Z and in_central_north_corridor and not _glacial_region_ready and not _glacial_region_loading:
        _ensure_glacial_region_loaded()
    if player_x<WESTERN_PRELOAD_X and in_central_west_east_corridor and not _western_region_ready and not _western_region_loading:
        _ensure_western_region_loaded()
    if player_x>EAST_PRELOAD_X and in_central_west_east_corridor and not _east_region_ready and not _east_region_loading:
        _ensure_east_region_loaded()
    var nearing_stormbreak:=\
        (player_x<-3600.0 and player_z<-400.0) or \
        (player_z<-3600.0 and player_x<-400.0) or \
        (player_x<-2000.0 and player_z<-2000.0)
    if nearing_stormbreak and not _stormbreak_region_ready and not _stormbreak_region_loading:
        _ensure_stormbreak_region_loaded()
    var nearing_skeld:=\
        (player_x<-3600.0 and player_z<-7600.0) or \
        (player_z<-10800.0 and player_x<-400.0) or \
        (player_x<-2200.0 and player_z<-9200.0)
    if nearing_skeld and not _skeld_region_ready and not _skeld_region_loading:
        _ensure_skeld_region_loaded()
    _prepare_gameplay_region_for_position(player_z,player_x)
    var geographic_context:=_region_context_for_point(player_x,player_z)
    var geographic_id:=str(geographic_context.get("id",_geographic_region_id))
    if geographic_id!=_geographic_region_id and not geographic_context.is_empty():
        _geographic_region_id=geographic_id
        var region_name:=str(geographic_context.get("global_profile",{}).get("zone_name",geographic_id.capitalize()))
        _apply_region_atmosphere(geographic_id)
        $UI/OldHud.show_notification(region_name,Color(1.0,.78,.30))


func _prepare_gameplay_region_for_position(player_z:float,player_x:float=INF)->void:
    if _region_gameplay_transition_busy:return
    if not is_finite(player_x):player_x=$Player.global_position.x
    var target_zone:=_active_zone_id
    if _east_region_ready and player_x>REGION_ACTIVATE_EAST_X and absf(player_z)<3600.0:
        target_zone="east_marches"
    elif _active_zone_id=="east_marches" and player_x<REGION_ACTIVATE_START_FROM_EAST_X:
        target_zone="starting_realm"
    elif _skeld_region_ready and player_x<REGION_ACTIVATE_WESTERN_X and player_z<REGION_ACTIVATE_GLACIAL_Z:
        target_zone="skeld_coast"
    elif _active_zone_id=="skeld_coast" and player_z>REGION_ACTIVATE_FRONTIER_Z and player_x<WESTERN_REGION_SEAM_X:
        target_zone="stormbreak_highlands"
    elif _active_zone_id=="skeld_coast" and player_x>REGION_ACTIVATE_START_FROM_WEST_X and player_z<GLACIAL_REGION_SEAM_Z:
        target_zone="glacial_range"
    elif _stormbreak_region_ready and player_x<REGION_ACTIVATE_WESTERN_X and player_z<REGION_ACTIVATE_NORTH_Z and player_z>GLACIAL_REGION_SEAM_Z:
        target_zone="stormbreak_highlands"
    elif _active_zone_id=="stormbreak_highlands" and player_z>REGION_ACTIVATE_START_Z and player_x<WESTERN_REGION_SEAM_X:
        target_zone="western_reaches"
    elif _active_zone_id=="stormbreak_highlands" and player_x>REGION_ACTIVATE_START_FROM_WEST_X and player_z<NORTH_REGION_SEAM_Z:
        target_zone="north_frontier"
    elif _western_region_ready and player_x<REGION_ACTIVATE_WESTERN_X and absf(player_z)<3600.0:
        target_zone="western_reaches"
    elif _active_zone_id=="western_reaches" and player_x>REGION_ACTIVATE_START_FROM_WEST_X:
        target_zone="starting_realm"
    elif _glacial_region_ready and player_z<REGION_ACTIVATE_GLACIAL_Z:
        target_zone="glacial_range"
    elif _north_region_ready and player_z<REGION_ACTIVATE_NORTH_Z:
        target_zone="north_frontier"
    elif player_z>REGION_ACTIVATE_START_Z:
        target_zone="starting_realm"
    elif _active_zone_id=="glacial_range" and player_z>REGION_ACTIVATE_FRONTIER_Z:
        target_zone="north_frontier"
    if target_zone!=_active_zone_id:_activate_streamed_gameplay_region(target_zone)


func _activate_streamed_gameplay_region(zone_id:String)->void:
    if zone_id==_active_zone_id or not _region_contexts.has(zone_id):return
    var transition_started_usec:int=Time.get_ticks_usec()
    _region_gameplay_transition_busy=true
    _persistent_region_state=$GameplayDirector.get_zone_transition_state()
    $GameplayDirector.clear_for_zone_reload(true)
    _active_zone_id=zone_id
    var context:Dictionary=_region_contexts[zone_id]
    _active_profile=context.global_profile
    await $GameplayDirector.configure_streamed(
        $Player,Callable(self,"_sample_global_height"),
        Callable(self,"_sample_global_walkable"),_active_profile
    )
    $GameplayDirector.load_zone_transition_state(_persistent_region_state)
    if not _world_atlas_profile.is_empty():
        $UI/WorldMap.configure(_world_atlas_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
        $UI/Minimap.configure(_world_atlas_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
    _town_torches=get_tree().get_nodes_in_group("town_torches")
    _region_gameplay_transition_busy=false
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")=="1":
        print("STREAMED_GAMEPLAY_PROFILE|zone=%s|elapsed_ms=%.1f|mounted=%s"%[
            zone_id,float(Time.get_ticks_usec()-transition_started_usec)/1000.0,str($Player.is_mounted()),
        ])


func _boot_stage_label(stage_label: String) -> String:
    match stage_label:
        "Water, roads, and bridges":
            return "Laying rivers, roads, and bridges"
        "Forests and biome vegetation":
            return "Growing forests and wildlands"
        "Rocks and ground cover":
            return "Scattering rocks and ground cover"
        "Traversal cover and meadow detail":
            return "Refining paths and meadows"
        "Bushes and ecology detail":
            return "Filling the living world"
        "Landmarks and formations":
            return "Raising landmarks"
        "Towns and destinations":
            return "Building towns and destinations"
        "Town collision and batching":
            return "Finalizing the world"
        _:
            return "Finishing world details"


func _set_boot_status(text:String, progress:float)->void:
    if not has_node("UI/BootOverlay"):
        return
    $UI/BootOverlay/Panel/Status.text = text
    $UI/BootOverlay/Panel/ProgressBar.value = progress


func _report_boot_status(text:String, progress:float, progress_callback:Callable = Callable(), show_internal_overlay:bool = true)->void:
    if show_internal_overlay:
        _set_boot_status(text, progress)
    if progress_callback.is_valid():
        progress_callback.call(text, progress)


func _profile_build_checkpoint(label:String)->void:
    if _build_profile_start_usec<=0:return
    print("WORLD_BUILD_PROFILE|%s|elapsed_ms=%.1f"%[
        label,
        float(Time.get_ticks_usec()-_build_profile_start_usec)/1000.0,
    ])


func _load_zone(zone_id:String,entry_edge:String)->void:
    # The north frontier is an outdoor streaming seam, not a portal reload.
    # Retain this method for the older east/west zones until each receives its
    # own authored neighbouring region.
    var seamless_regions:=["starting_realm","north_frontier","glacial_range","western_reaches","east_marches","stormbreak_highlands","skeld_coast"]
    if zone_id in seamless_regions and (_active_zone_id in seamless_regions):
        if zone_id=="glacial_range":await _ensure_glacial_region_loaded()
        elif zone_id=="north_frontier":await _ensure_north_region_loaded()
        elif zone_id=="western_reaches":await _ensure_western_region_loaded()
        elif zone_id=="east_marches":await _ensure_east_region_loaded()
        elif zone_id=="stormbreak_highlands":await _ensure_stormbreak_region_loaded()
        elif zone_id=="skeld_coast":await _ensure_skeld_region_loaded()
        return
    if zone_id==_active_zone_id:return
    get_tree().paused=true
    var gameplay_progress:Dictionary=$GameplayDirector.get_zone_transition_state()
    $GameplayDirector.clear_for_zone_reload()
    var streamed_regions:Node=$WorldRoot.get_node_or_null("StreamedRegions")
    if streamed_regions!=null:streamed_regions.free()
    _region_contexts.clear()
    _north_region_ready=false;_north_region_loading=false
    _glacial_region_ready=false;_glacial_region_loading=false
    _western_region_ready=false;_western_region_loading=false
    _east_region_ready=false;_east_region_loading=false
    _stormbreak_region_ready=false;_stormbreak_region_loading=false
    _skeld_region_ready=false;_skeld_region_loading=false
    _world_atlas_profile={}
    _active_zone_id=zone_id
    var profile:Dictionary=_world_profile.make_zone_profile(zone_id)
    _active_profile=profile
    var world_size:float=profile.get("world_size",7200.0)
    $AdminCamera.size=world_size*1.08;$AdminCamera.position.y=maxf(700.0,world_size*.78)
    _world_result=_terrain_builder.generate_world($WorldRoot/TerrainRoot,profile)
    _preview_builder.populate($WorldRoot,profile,_world_result)
    _register_region_context(zone_id,$WorldRoot,Vector2.ZERO,profile,_world_result,_terrain_builder,_preview_builder)
    var global_profile:Dictionary=_region_contexts[zone_id].global_profile
    _active_profile=global_profile
    var margin:=world_size*.425
    var entry_point:=Vector2.ZERO
    if entry_edge=="north":entry_point=Vector2(0,margin)
    elif entry_edge=="south":entry_point=Vector2(0,-margin)
    elif entry_edge=="east":entry_point=Vector2(margin,0)
    elif entry_edge=="west":entry_point=Vector2(-margin,0)
    var spawn_position:Vector3=_world_result.height_sampler.call(entry_point.x,entry_point.y)
    $Player.configure_world(Callable(self,"_sample_global_height"),spawn_position+Vector3.UP*.08,Callable(self,"_sample_global_walkable"),Callable(self,"_sample_global_structure_height"))
    $Player.set_interior_mode(false)
    $GameplayDirector.configure($Player,Callable(self,"_sample_global_height"),Callable(self,"_sample_global_walkable"),global_profile)
    $GameplayDirector.load_zone_transition_state(gameplay_progress)
    $UI/WorldMap.configure(global_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
    $UI/Minimap.configure(global_profile,$Player,$GameplayDirector,Callable(self,"_sample_global_terrain_height"))
    _town_torches=get_tree().get_nodes_in_group("town_torches")
    $UI/OldHud.show_notification("Entered %s"%profile.get("zone_name",zone_id),Color(1.0,.78,.30))
    get_tree().paused=false


func _process(delta: float) -> void:
    _update_region_streaming(delta)
    var inside_dungeon:bool=$Player.has_method("is_interior_mode") and $Player.is_interior_mode()
    if inside_dungeon!=_dungeon_visual_mode and $Environment.environment:
        _dungeon_visual_mode=inside_dungeon
        var env:Environment=$Environment.environment
        env.fog_enabled=not inside_dungeon and not _admin_view
        # A sky-sourced ambient term was nearly black below the sealed dungeon
        # ceiling. Interiors use neutral local fill so corridors remain readable
        # while torches still provide the warm directional accents.
        env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR if inside_dungeon else Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_color=Color(.66,.71,.78) if inside_dungeon else Color(.72,.76,.80)
        env.ambient_light_energy=1.35 if inside_dungeon else .42
        env.background_energy_multiplier=1.0
        env.tonemap_exposure=1.35 if inside_dungeon else 1.0
    if _admin_view and is_instance_valid(_admin_marker):
        _admin_marker.position = Vector3($Player.global_position.x, 180.0, $Player.global_position.z)
    _sky_rotation_accumulator+=delta
    if _sky_rotation_accumulator>=.125 and $Environment.environment:
        var sky_rotation: Vector3 = $Environment.environment.sky_rotation
        sky_rotation.y = fmod(sky_rotation.y + _sky_rotation_accumulator * 0.0026, TAU)
        $Environment.environment.sky_rotation = sky_rotation
        _sky_rotation_accumulator=0.0
    # A full cycle lasts one real hour. Dungeons keep their authored interior
    # fill, while outdoor time advances slowly enough that daylight never feels
    # like a rapidly flashing showcase. Town and camp lights respond at dusk.
    if not inside_dungeon:
        _update_day_night(delta)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
        await _capture_hero_face_sheet()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
        _set_admin_menu(not _admin_menu_open)
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
        _set_admin_menu(not _admin_menu_open)
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_I, KEY_B]:
        _set_hero_menu(not _hero_menu_open)
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
        _open_collection_menu($UI/SkillsMenu);get_viewport().set_input_as_handled();return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
        _open_collection_menu($UI/QuestMenu);get_viewport().set_input_as_handled();return
    if event.is_action_pressed("ui_cancel"):
        if _lore_menu_open:
            _close_lore_reader()
            return
        if _vendor_menu_open:
            _close_vendor_menu()
            return
        if _crafting_menu_open:
            _close_crafting_menu()
            return
        if _admin_menu_open:
            _set_admin_menu(false)
            return
        if _map_open:
            _set_map_open(false)
            return
        if _hero_menu_open:
            _set_hero_menu(false)
            return
        if _collection_menu:
            _close_collection_menu()
            return
        if _menu_open:
            _set_menu_open(false)
            return
        _set_menu_open(not _menu_open)
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
        _set_map_open(not _map_open)
        get_viewport().set_input_as_handled()
        return


func _position_player(spawn_position: Vector3) -> void:
    var player: CharacterBody3D = $Player
    player.configure_world(
        Callable(self,"_sample_global_height"),spawn_position,
        Callable(self,"_sample_global_walkable"),Callable(self,"_sample_global_structure_height")
    )


func _create_admin_marker() -> void:
    _admin_marker = MeshInstance3D.new()
    _admin_marker.name = "AdminPlayerMarker"
    var marker_mesh := CylinderMesh.new()
    marker_mesh.top_radius = 58.0
    marker_mesh.bottom_radius = 58.0
    marker_mesh.height = 24.0
    _admin_marker.mesh = marker_mesh
    var marker_material := StandardMaterial3D.new()
    marker_material.albedo_color = Color(1.0, 0.08, 0.03, 1.0)
    marker_material.emission_enabled = true
    marker_material.emission = Color(1.0, 0.03, 0.01, 1.0)
    marker_material.emission_energy_multiplier = 2.0
    _admin_marker.material_override = marker_material
    _admin_marker.visible = false
    add_child(_admin_marker)


func _create_cloud_layer(world_size: float, spawn2: Vector2) -> void:
    var cloud_layer := MultiMeshInstance3D.new()
    cloud_layer.name = "CloudLayer"
    var cloud_mesh := SphereMesh.new()
    cloud_mesh.radius = 1.0
    cloud_mesh.height = 2.0
    cloud_mesh.radial_segments = 12
    cloud_mesh.rings = 6
    var transforms: Array[Transform3D] = []
    for i in range(42):
        var angle := float(i) * 2.39996323
        var radius := 190.0 + float((i * 83) % 720)
        var center := spawn2 + Vector2(cos(angle), sin(angle)) * radius
        var altitude := 125.0 + float((i * 37) % 115)
        for lobe in range(3):
            var offset := Vector2(float(lobe - 1) * 12.0, sin(float(i + lobe)) * 8.0)
            var scale := Vector3(30.0 + float(i % 5) * 6.0, 11.0 + float(lobe) * 2.2, 20.0 + float((i + lobe) % 4) * 4.0)
            transforms.append(Transform3D(Basis(Vector3.UP, angle * 0.35).scaled(scale), Vector3(center.x + offset.x, altitude + float(lobe) * 3.0, center.y + offset.y)))
    for i in range(110):
        var x := world_size * (fmod(float(i * 173), 109.0) / 109.0 - 0.5) * 0.92
        var z := world_size * (fmod(float(i * 251), 113.0) / 113.0 - 0.5) * 0.92
        var altitude := 150.0 + float((i * 47) % 150)
        var scale := Vector3(38.0 + float(i % 6) * 7.0, 12.0 + float(i % 3) * 2.5, 24.0 + float(i % 5) * 5.0)
        transforms.append(Transform3D(Basis(Vector3.UP, float(i) * 0.63).scaled(scale), Vector3(x, altitude, z)))
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = transforms.size()
    multimesh.mesh = cloud_mesh
    for i in range(transforms.size()):
        multimesh.set_instance_transform(i, transforms[i])
    cloud_layer.multimesh = multimesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.91, 0.94, 0.95, 0.78)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    cloud_layer.material_override = material
    add_child(cloud_layer)


func _wire_menu() -> void:
    $UI/PauseMenu/MenuPanel/MenuButtons/ResumeButton.pressed.connect(_on_resume_pressed)
    $UI/PauseMenu/MenuPanel/MenuButtons/CloseGameButton.pressed.connect(_on_close_game_pressed)


func _set_menu_open(open: bool) -> void:
    _menu_open = open
    $UI/PauseMenu.visible = open
    _sync_pause_state()


func _set_map_open(open: bool) -> void:
    _map_open = open
    $UI/WorldMap.visible = open
    _sync_hud_visibility()
    _sync_pause_state()
    if not open:
        $UI/WorldMap.set_teleport_mode(false)


func _teleport_from_world_map(world_point: Vector2) -> void:
    # The opaque map remains on screen as a transition cover, but once a
    # destination is chosen its hero marker no longer needs to follow the
    # offscreen teleport. Suppressing that redundant redraw saves a complete
    # second rendering of the detailed atlas during every map teleport.
    $UI/WorldMap.set_process(false)
    if world_point.x<WESTERN_REGION_SEAM_X+160.0 and world_point.y<GLACIAL_REGION_SEAM_Z+160.0:
        await _ensure_skeld_region_loaded()
    elif world_point.x<WESTERN_REGION_SEAM_X+160.0 and world_point.y<NORTH_REGION_SEAM_Z+160.0 and world_point.y>GLACIAL_REGION_SEAM_Z-160.0:
        await _ensure_stormbreak_region_loaded()
    elif world_point.x<WESTERN_REGION_SEAM_X+160.0 and absf(world_point.y)<3760.0:
        await _ensure_western_region_loaded()
    elif world_point.x>EAST_REGION_SEAM_X-160.0 and absf(world_point.y)<3760.0:
        await _ensure_east_region_loaded()
    elif world_point.y<GLACIAL_REGION_SEAM_Z+160.0:
        await _ensure_glacial_region_loaded()
    elif world_point.y<NORTH_REGION_SEAM_Z+160.0:
        await _ensure_north_region_loaded()
    var map_profile:Dictionary=_world_atlas_profile if not _world_atlas_profile.is_empty() else _active_profile
    var extent:Vector2=map_profile.get("map_extent",Vector2.ONE*float(map_profile.get("world_size",7200.0)))
    var center:Vector2=map_profile.get("map_center",Vector2.ZERO)
    var half_safe:=extent*.485
    var safe_point:=Vector2(
        clampf(world_point.x,center.x-half_safe.x,center.x+half_safe.x),
        clampf(world_point.y,center.y-half_safe.y,center.y+half_safe.y)
    )
    var destination:Vector3=_sample_global_height(safe_point.x,safe_point.y)
    $Player.teleport_to_surface(destination + Vector3.UP * 0.08)
    _prepare_gameplay_region_for_position(safe_point.y,safe_point.x)
    # A long atlas teleport can cross more than one streamed region. Finish the
    # destination gameplay profile while the opaque, paused map still covers
    # the scene; otherwise the first controllable frame can inherit AI/service
    # construction from the asynchronous profile handoff.
    while _region_gameplay_transition_busy:
        await get_tree().process_frame
    # Refresh local pooled collisions while the map still covers the world, and
    # give visibility-range chunks a frame to settle before unpausing gameplay.
    # This moves the former post-teleport hitch out of the first walking frame.
    if $GameplayDirector.has_method("prepare_after_surface_teleport"):
        $GameplayDirector.prepare_after_surface_teleport()
    # Let the renderer consume the new camera position under the paused map,
    # then advance two frames with the map still covering the world and player
    # input still disabled. This moves the unavoidable scene-stream transition
    # away from the first frame in which the player can walk.
    await get_tree().process_frame
    get_tree().paused=false
    # Let visibility, shadow and local collision queues settle at the new
    # horizon before input returns. These are real destination frames, merely
    # presented beneath the still-open map.
    for _warm_frame in range(4):
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
    # Swap the large map for the local HUD while input is still withheld. The
    # minimap has its own destination texture/canvas warm-up; exposing it and
    # restoring movement in the same frame was the remaining teleport hitch.
    $UI/WorldMap.visible=false
    _map_open=false
    $UI/WorldMap.set_teleport_mode(false)
    _sync_hud_visibility()
    $Player.set_input_enabled(false)
    for _hud_warm_frame in range(2):
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
    _sync_pause_state()


func _set_admin_view(enabled: bool) -> void:
    _admin_view = enabled
    $AdminCamera.current = enabled
    $Player/CameraPivot/SpringArm3D/Camera3D.current = not enabled
    $UI/AdminHint.visible = enabled
    _sync_hud_visibility()
    _admin_marker.visible = enabled
    if $Environment.environment:
        $Environment.environment.fog_enabled = not enabled
    _sync_pause_state()


func _set_admin_menu(open: bool) -> void:
    _admin_menu_open = open
    $UI/AdminMenu.visible = open
    _sync_pause_state()


func _set_hero_menu(open: bool) -> void:
    _hero_menu_open=open
    $UI/HeroMenu.visible=open
    if open: $UI/HeroMenu.refresh()
    _sync_pause_state()

func _open_collection_menu(menu:Control)->void:
    if is_instance_valid(_collection_menu) and _collection_menu != menu:_collection_menu.visible=false
    _collection_menu=menu;menu.visible=true;menu.refresh();_sync_pause_state()
func _close_collection_menu()->void:
    if _collection_menu:_collection_menu.visible=false
    _collection_menu=null;_sync_pause_state()

func _open_vendor_menu(vendor_data:Dictionary)->void:
    _vendor_menu_open=true
    $UI/VendorMenu.visible=true
    $UI/VendorMenu.show_vendor(vendor_data)
    _sync_pause_state()

func _close_vendor_menu()->void:
    _vendor_menu_open=false
    $UI/VendorMenu.visible=false
    _sync_pause_state()


func _open_crafting_menu(station_data:Dictionary)->void:
    _crafting_menu_open=true
    $UI/CraftingMenu.visible=true
    $UI/CraftingMenu.show_station(station_data)
    _sync_pause_state()


func _close_crafting_menu()->void:
    _crafting_menu_open=false
    $UI/CraftingMenu.visible=false
    _sync_pause_state()


func _open_lore_reader(title:String,body:String)->void:
    if not is_instance_valid(_lore_reader):
        _lore_reader=LoreReaderScript.new()
        _lore_reader.name="LoreReader"
        $UI.add_child(_lore_reader)
        _lore_reader.close_requested.connect(_close_lore_reader)
        if $UI/PauseMenu.theme:_lore_reader.theme=$UI/PauseMenu.theme
    _lore_menu_open=true
    _lore_reader.show_entry(title,body)
    _sync_pause_state()


func _close_lore_reader()->void:
    _lore_menu_open=false
    if is_instance_valid(_lore_reader):_lore_reader.visible=false
    _sync_pause_state()


func _sync_pause_state()->void:
    var collection_open:=is_instance_valid(_collection_menu) and _collection_menu.visible
    # Derive pause from both state flags and actual visibility. This prevents a
    # stale close callback from unpausing while another menu (especially G) is
    # still open.
    var menu_nodes:=[ $UI/PauseMenu,$UI/WorldMap,$UI/AdminMenu,$UI/HeroMenu,$UI/BagMenu,$UI/SkillsMenu,$UI/QuestMenu,$UI/VendorMenu,$UI/CraftingMenu ]
    var visible_menu:=false
    for menu in menu_nodes:
        if menu.visible:visible_menu=true;break
    var any_menu_open:=visible_menu or _lore_menu_open or _menu_open or _map_open or _admin_menu_open or _hero_menu_open or _vendor_menu_open or _crafting_menu_open or collection_open
    get_tree().paused=any_menu_open
    $Player.set_input_enabled(not any_menu_open and not _admin_view)


func _sync_hud_visibility()->void:
    var show_hud:=not _map_open and not _admin_view
    $UI/OldHud.visible=show_hud
    $UI/Minimap.visible=show_hud


func admin_toggle_overview() -> void:
    _set_admin_menu(false)
    _set_admin_view(not _admin_view)


func admin_toggle_day_night() -> void:
    _night_mode = not _night_mode
    _day_clock = _day_cycle_seconds * (0.75 if _night_mode else 0.25)
    _update_day_night(0.0)


func _update_day_night(delta: float) -> void:
    _day_clock = fmod(_day_clock + delta, _day_cycle_seconds)
    var phase := _day_clock / _day_cycle_seconds
    var sun_height := sin(phase * TAU)
    var daylight := smoothstep(-0.18, 0.30, sun_height)
    _night_mode = daylight < 0.32
    $Sun.rotation.x = phase * TAU - PI
    $Sun.light_energy = lerpf(0.06, 0.64, daylight)
    $Sun.light_color = Color(0.34, 0.42, 0.68).lerp(Color(1.0, 0.965, 0.90), daylight)
    if $Environment.environment:
        var env: Environment = $Environment.environment
        env.ambient_light_energy = lerpf(0.20, 0.42, daylight)
        env.background_energy_multiplier = lerpf(0.28, 1.0, daylight)
        env.fog_light_energy = lerpf(0.08, 0.22, daylight)
        if env.sky:
            env.sky.sky_material = _night_sky_material if daylight < 0.32 else _day_sky_material
    for torch in _town_torches:
        if not is_instance_valid(torch):
            continue
        torch.visible = daylight < 0.58
        torch.light_energy = (1.0 - daylight) * 2.1

func _apply_ui_theme()->void:
    var theme:=Theme.new();theme.default_font_size=14
    var panel:=StyleBoxFlat.new();panel.bg_color=Color(.025,.035,.055,.97);panel.border_color=Color(.38,.31,.20,.95);panel.set_border_width_all(2);panel.set_corner_radius_all(10);panel.shadow_color=Color(0,0,0,.55);panel.shadow_size=14
    var button:=StyleBoxFlat.new();button.bg_color=Color(.09,.12,.18,.96);button.border_color=Color(.30,.36,.46,.9);button.set_border_width_all(1);button.set_corner_radius_all(6);button.content_margin_left=10;button.content_margin_right=10;button.content_margin_top=7;button.content_margin_bottom=7
    var hover:=button.duplicate();hover.bg_color=Color(.17,.22,.32,.98);hover.border_color=Color(.85,.67,.28,1)
    theme.set_stylebox("panel","Panel",panel);theme.set_stylebox("panel","PanelContainer",panel);theme.set_stylebox("normal","Button",button);theme.set_stylebox("hover","Button",hover);theme.set_stylebox("pressed","Button",hover)
    theme.set_color("font_color","Button",Color(.88,.91,.96));theme.set_color("font_hover_color","Button",Color(1,.85,.43));theme.set_font_size("font_size","Button",14)
    theme.set_color("font_color","Label",Color(.87,.90,.95));theme.set_font_size("normal_font_size","RichTextLabel",14)
    for menu in [$UI/AdminMenu,$UI/HeroMenu,$UI/BagMenu,$UI/SkillsMenu,$UI/QuestMenu,$UI/VendorMenu,$UI/CraftingMenu,$UI/PauseMenu]:menu.theme=theme


func _on_resume_pressed() -> void:
    _set_menu_open(false)


func _on_close_game_pressed() -> void:
    get_tree().quit()


func _configure_world_lighting() -> void:
    var sun: DirectionalLight3D = $Sun
    sun.light_color = Color(1.0, 0.965, 0.90, 1.0)
    sun.light_energy = 0.78
    sun.shadow_enabled = true
    sun.shadow_opacity = 0.58
    sun.shadow_blur = 1.55
    sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    sun.directional_shadow_max_distance = 210.0
    # Fade the last cascade over a broad band. The old abrupt 180 m cutoff
    # painted a camera-centred light/dark polygon across otherwise continuous
    # ground and looked like square terrain chunks while walking.
    sun.directional_shadow_fade_start = 0.54
    sun.directional_shadow_blend_splits = true

    var environment_node: WorldEnvironment = $Environment
    var env := Environment.new()
    var sky := Sky.new()
    # Preserve the fine edges of the animated cloud layers in wide views.
    sky.radiance_size = Sky.RADIANCE_SIZE_512
    var sky_material := ShaderMaterial.new()
    var sky_shader := Shader.new()
    sky_shader.code = """
shader_type sky;

uniform float weather_cloud_bias : hint_range(-0.10, 0.12) = 0.0;
uniform float weather_tint_strength : hint_range(0.0, 0.55) = 0.0;
uniform vec3 weather_cloud_tint : source_color = vec3(0.82, 0.87, 0.90);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int i = 0; i < 5; i++) {
        value += noise2(p) * amplitude;
        p = p * 2.03 + vec2(17.1, 9.2);
        amplitude *= 0.48;
    }
    return value;
}

float hash31(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
    float value = 0.0;
    float amplitude = 0.56;
    for (int i = 0; i < 4; i++) {
        value += noise3(p) * amplitude;
        p = p * 2.07 + vec3(7.1, 13.7, 5.3);
        amplitude *= 0.47;
    }
    return value;
}

void sky() {
    vec3 dir = normalize(EYEDIR);
    float height = clamp(dir.y * 0.72 + 0.28, 0.0, 1.0);
    vec3 horizon = vec3(0.34, 0.57, 0.75);
    vec3 zenith = vec3(0.075, 0.27, 0.56);
    vec3 lower = vec3(0.16, 0.31, 0.45);
    // One continuous gradient crosses the horizon. Separate upper/lower
    // branches created a camera-level stripe even when their endpoint colors
    // happened to match.
    float atmosphere_height = smoothstep(-0.34, 0.82, dir.y);
    vec3 color = mix(lower, zenith, atmosphere_height);
    color = mix(color, horizon, exp(-abs(dir.y) * 4.8) * 0.34);

    float horizon_glow = exp(-abs(dir.y) * 6.5);
    color = mix(color, vec3(0.70, 0.61, 0.49), horizon_glow * 0.045);

    vec3 sun_dir = normalize(vec3(-0.48, 0.62, 0.28));
    float sun_dot = max(dot(dir, sun_dir), 0.0);
    float sun_disc = smoothstep(0.99935, 0.99975, sun_dot);
    float sun_glow = pow(sun_dot, 34.0);
    color += vec3(1.0, 0.76, 0.42) * sun_glow * 0.38;
    color = mix(color, vec3(1.0, 0.94, 0.76), sun_disc);

    float sky_altitude = max(dir.y, 0.0);
    if (dir.y > -0.045) {
        // Sphere-space noise stays continuous across every view direction.
        // The former longitude/latitude value-noise cells became visible as
        // rectangular cloud tiles on the cubemap faces.
        float cloud_a = fbm3(dir * 4.8 + vec3(1.7, 7.4, 3.1));
        float cloud_b = fbm3(dir * 10.5 + vec3(11.0, 2.0, 17.0));
        float weather = noise3(dir * 1.65 + vec3(8.0, 14.0, 4.0));
        float cloud_field = cloud_a * 0.64 + cloud_b * 0.18 + weather * 0.27;
        float clouds = smoothstep(0.55 - weather_cloud_bias, 0.70 - weather_cloud_bias, cloud_field);
        // Fade continuously through the horizon instead of suppressing a
        // narrow latitude strip. The old absolute-altitude threshold created
        // a pale band that was especially obvious while facing north.
        float altitude_mask = smoothstep(-0.045, 0.085, dir.y) * (1.0 - smoothstep(0.82, 0.995, sky_altitude));
        clouds *= altitude_mask;
        vec3 cloud_shadow = vec3(0.48, 0.56, 0.64);
        vec3 cloud_light = vec3(0.985, 0.985, 0.965);
        float lit_edge = smoothstep(0.40, 0.77, cloud_b * 0.42 + cloud_a * 0.72);
        vec3 cloud_color = mix(cloud_shadow, cloud_light, lit_edge);
        cloud_color = mix(cloud_color, weather_cloud_tint, weather_tint_strength);
        color = mix(color, cloud_color, clouds * 0.82);

        // A faint high cirrus layer breaks up the silhouette without creating
        // the large round cloud cutouts of the former panorama.
        float cirrus_field = fbm3(dir * 18.0 + vec3(31.0, 9.0, 21.0));
        float cirrus = smoothstep(0.68, 0.82, cirrus_field) * smoothstep(0.18, 0.42, sky_altitude);
        color = mix(color, vec3(0.88, 0.92, 0.95), cirrus * 0.20);
    }
    COLOR = color;
}
"""
    sky_material.shader = sky_shader
    # Use the procedural atmosphere above. The old panorama had visible
    # seams and large painted cloud circles that made the sky feel pasted on.
    _day_sky_material = sky_material
    var night_material := ShaderMaterial.new()
    var night_shader := Shader.new()
    night_shader.code = """
shader_type sky;
float star_hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
void sky() {
    vec3 d = normalize(EYEDIR);
    float horizon = clamp(d.y * 0.55 + 0.35, 0.0, 1.0);
    vec3 color = mix(vec3(0.035, 0.055, 0.11), vec3(0.006, 0.012, 0.038), horizon);
    vec3 cell = floor(d * 920.0);
    float stars = step(0.9968, star_hash(cell)) * smoothstep(-0.08, 0.18, d.y);
    float brightness = 0.55 + star_hash(cell + 17.0) * 1.8;
    COLOR = color + vec3(0.72, 0.82, 1.0) * stars * brightness;
}
"""
    night_material.shader = night_shader
    _night_sky_material = night_material
    sky.sky_material = _day_sky_material
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.ambient_light_color = Color(0.74, 0.79, 0.84, 1.0)
    env.ambient_light_energy = 0.49
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.adjustment_enabled = true
    env.adjustment_saturation = 1.03
    env.adjustment_contrast = 1.015
    env.adjustment_brightness = 0.94
    env.fog_enabled = true
    env.fog_light_color = Color(0.69, 0.76, 0.81, 1.0)
    env.fog_light_energy = 0.11
    env.fog_density = 0.000075
    env.fog_sky_affect = 0.0
    env.fog_height = 18.0
    env.fog_height_density = 0.0014
    env.volumetric_fog_enabled = false
    environment_node.environment = env
    _apply_region_atmosphere(_geographic_region_id)


func _apply_region_atmosphere(zone_id:String)->void:
    if not $Environment.environment:return
    var env:Environment=$Environment.environment
    var cloud_bias:=0.0
    var cloud_tint_strength:=0.0
    var cloud_tint:=Color(.82,.87,.90)
    match zone_id:
        "western_reaches":
            # The rain country reads cooler and more humid, but avoids the
            # heavy grey wash that previously made the whole world look dirty.
            env.fog_density=.000115
            env.fog_light_color=Color(.66,.73,.75)
            env.fog_height=24.0
            env.fog_height_density=.0018
            env.adjustment_saturation=1.0
            env.adjustment_contrast=1.02
            env.adjustment_brightness=.94
            cloud_bias=.040
            cloud_tint_strength=.24
            cloud_tint=Color(.76,.82,.84)
        "stormbreak_highlands":
            env.fog_density=.000125
            env.fog_light_color=Color(.66,.74,.77)
            env.fog_height=32.0
            env.fog_height_density=.0019
            env.adjustment_saturation=1.0
            env.adjustment_contrast=1.025
            env.adjustment_brightness=.94
            cloud_bias=.052
            cloud_tint_strength=.28
            cloud_tint=Color(.73,.80,.83)
        "skeld_coast":
            env.fog_density=.000145
            env.fog_light_color=Color(.65,.75,.80)
            env.fog_height=20.0
            env.fog_height_density=.0021
            env.adjustment_saturation=.99
            env.adjustment_contrast=1.025
            env.adjustment_brightness=.95
            cloud_bias=.060
            cloud_tint_strength=.31
            cloud_tint=Color(.70,.79,.83)
        "east_marches":
            env.fog_density=.000060
            env.fog_light_color=Color(.78,.76,.66)
            env.fog_height=15.0
            env.fog_height_density=.00115
            env.adjustment_saturation=1.045
            env.adjustment_contrast=1.025
            env.adjustment_brightness=.94
            cloud_bias=-.020
            cloud_tint_strength=.12
            cloud_tint=Color(.91,.85,.72)
        "north_frontier":
            env.fog_density=.000095
            env.fog_light_color=Color(.67,.75,.80)
            env.fog_height=28.0
            env.fog_height_density=.0017
            env.adjustment_saturation=1.01
            env.adjustment_contrast=1.02
            env.adjustment_brightness=.94
            cloud_bias=.018
            cloud_tint_strength=.12
            cloud_tint=Color(.82,.87,.90)
        "glacial_range":
            env.fog_density=.000130
            env.fog_light_color=Color(.72,.82,.88)
            env.fog_height=38.0
            env.fog_height_density=.0020
            env.adjustment_saturation=.98
            env.adjustment_contrast=1.025
            env.adjustment_brightness=.95
            cloud_bias=.030
            cloud_tint_strength=.20
            cloud_tint=Color(.86,.91,.94)
        _:
            env.fog_density=.000075
            env.fog_light_color=Color(.69,.76,.81)
            env.fog_height=18.0
            env.fog_height_density=.0014
            env.adjustment_saturation=1.03
            env.adjustment_contrast=1.015
            env.adjustment_brightness=.94
    var day_material:=_day_sky_material as ShaderMaterial
    if day_material:
        day_material.set_shader_parameter("weather_cloud_bias",cloud_bias)
        day_material.set_shader_parameter("weather_tint_strength",cloud_tint_strength)
        day_material.set_shader_parameter("weather_cloud_tint",Vector3(cloud_tint.r,cloud_tint.g,cloud_tint.b))


func _capture_hero_face_sheet() -> void:
    var output_path: String = await $Player.capture_face_inspection_sheet()
    if output_path.is_empty():
        push_warning("Hero face capture failed.")
        return
    print("Hero face capture saved to: %s" % output_path)
