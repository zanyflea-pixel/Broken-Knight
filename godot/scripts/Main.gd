extends Node3D

const TerrainBuilder = preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile = preload("res://scripts/world/WorldProfile.gd")
const WorldPreviewBuilder = preload("res://scripts/world/WorldPreviewBuilder.gd")

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
    _profile_build_checkpoint("terrain")
    _report_boot_status("Starting gameplay systems...", 58.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    _position_player(_world_result.spawn_position)
    $GameplayDirector.configure($Player, _world_result.height_sampler, _world_result.walkable_sampler, profile)
    if not $Player.environment_damage_requested.is_connected($GameplayDirector.apply_environment_damage):
        $Player.environment_damage_requested.connect($GameplayDirector.apply_environment_damage)
    _profile_build_checkpoint("gameplay")
    _create_admin_marker()
    _report_boot_status("Preparing maps and interface...", 76.0, progress_callback, show_internal_overlay)
    await get_tree().process_frame
    # Maps shade terrain only; roads, trails and bridges are drawn as their own
    # layers. Sampling the raw cached heightfield avoids tens of thousands of
    # unnecessary road/bridge corridor checks at startup and while travelling.
    $UI/WorldMap.configure(profile, $Player, $GameplayDirector, _world_result.terrain_height_sampler)
    $UI/WorldMap.teleport_requested.connect(_teleport_from_world_map)
    $UI/Minimap.configure(profile, $Player, $GameplayDirector, _world_result.terrain_height_sampler)
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
    if zone_id==_active_zone_id:return
    get_tree().paused=true
    $GameplayDirector.clear_for_zone_reload()
    _active_zone_id=zone_id
    var profile:Dictionary=_world_profile.make_zone_profile(zone_id)
    _active_profile=profile
    var world_size:float=profile.get("world_size",7200.0)
    $AdminCamera.size=world_size*1.08;$AdminCamera.position.y=maxf(700.0,world_size*.78)
    _world_result=_terrain_builder.generate_world($WorldRoot/TerrainRoot,profile)
    _preview_builder.populate($WorldRoot,profile,_world_result)
    var margin:=world_size*.425
    var entry_point:=Vector2.ZERO
    if entry_edge=="north":entry_point=Vector2(0,margin)
    elif entry_edge=="south":entry_point=Vector2(0,-margin)
    elif entry_edge=="east":entry_point=Vector2(margin,0)
    elif entry_edge=="west":entry_point=Vector2(-margin,0)
    var spawn_position:Vector3=_world_result.height_sampler.call(entry_point.x,entry_point.y)
    $Player.configure_world(_world_result.height_sampler,spawn_position+Vector3.UP*.08,_world_result.walkable_sampler,_world_result.structure_height_sampler)
    $Player.set_interior_mode(false)
    $GameplayDirector.configure($Player,_world_result.height_sampler,_world_result.walkable_sampler,profile)
    $UI/WorldMap.configure(profile,$Player,$GameplayDirector,_world_result.terrain_height_sampler)
    $UI/Minimap.configure(profile,$Player,$GameplayDirector,_world_result.terrain_height_sampler)
    _town_torches=get_tree().get_nodes_in_group("town_torches")
    $UI/OldHud.show_notification("Entered %s"%profile.get("zone_name",zone_id),Color(1.0,.78,.30))
    get_tree().paused=false


func _process(delta: float) -> void:
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
    # Automatic day/night progression is intentionally disabled while world
    # readability is being authored. The admin toggle remains available for
    # testing night lighting without forcing darkness during normal play.


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
    player.configure_world(_world_result.height_sampler, spawn_position, _world_result.walkable_sampler, _world_result.structure_height_sampler)


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
    var world_size: float = _active_profile.get("world_size", 7200.0)
    var margin := world_size * 0.485
    var safe_point := Vector2(clampf(world_point.x, -margin, margin), clampf(world_point.y, -margin, margin))
    var destination: Vector3 = _world_result.height_sampler.call(safe_point.x, safe_point.y)
    $Player.set_interior_mode(false)
    $Player.global_position = destination + Vector3.UP * 0.08
    $Player.velocity = Vector3.ZERO
    _set_map_open(false)


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


func _sync_pause_state()->void:
    var collection_open:=is_instance_valid(_collection_menu) and _collection_menu.visible
    # Derive pause from both state flags and actual visibility. This prevents a
    # stale close callback from unpausing while another menu (especially G) is
    # still open.
    var menu_nodes:=[ $UI/PauseMenu,$UI/WorldMap,$UI/AdminMenu,$UI/HeroMenu,$UI/BagMenu,$UI/SkillsMenu,$UI/QuestMenu,$UI/VendorMenu,$UI/CraftingMenu ]
    var visible_menu:=false
    for menu in menu_nodes:
        if menu.visible:visible_menu=true;break
    var any_menu_open:=visible_menu or _menu_open or _map_open or _admin_menu_open or _hero_menu_open or _vendor_menu_open or _crafting_menu_open or collection_open
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
    vec3 horizon = vec3(0.54, 0.72, 0.86);
    vec3 zenith = vec3(0.075, 0.27, 0.56);
    vec3 lower = vec3(0.28, 0.43, 0.55);
    vec3 color = dir.y >= 0.0
        ? mix(horizon, zenith, pow(height, 0.62))
        : mix(horizon, lower, clamp(-dir.y * 2.0, 0.0, 1.0));

    float horizon_glow = exp(-abs(dir.y) * 11.0);
    color = mix(color, vec3(0.90, 0.74, 0.57), horizon_glow * 0.14);

    vec3 sun_dir = normalize(vec3(-0.48, 0.62, 0.28));
    float sun_dot = max(dot(dir, sun_dir), 0.0);
    float sun_disc = smoothstep(0.99935, 0.99975, sun_dot);
    float sun_glow = pow(sun_dot, 34.0);
    color += vec3(1.0, 0.76, 0.42) * sun_glow * 0.38;
    color = mix(color, vec3(1.0, 0.94, 0.76), sun_disc);

    float sky_altitude = abs(dir.y);
    if (sky_altitude > 0.015) {
        // Sphere-space noise stays continuous across every view direction.
        // The former longitude/latitude value-noise cells became visible as
        // rectangular cloud tiles on the cubemap faces.
        float cloud_a = fbm3(dir * 4.8 + vec3(1.7, 7.4, 3.1));
        float cloud_b = fbm3(dir * 10.5 + vec3(11.0, 2.0, 17.0));
        float weather = noise3(dir * 1.65 + vec3(8.0, 14.0, 4.0));
        float cloud_field = cloud_a * 0.64 + cloud_b * 0.18 + weather * 0.27;
        float clouds = smoothstep(0.55, 0.70, cloud_field);
        float altitude_mask = smoothstep(0.025, 0.09, sky_altitude) * (1.0 - smoothstep(0.82, 0.995, sky_altitude));
        clouds *= altitude_mask;
        vec3 cloud_shadow = vec3(0.48, 0.56, 0.64);
        vec3 cloud_light = vec3(0.985, 0.985, 0.965);
        float lit_edge = smoothstep(0.40, 0.77, cloud_b * 0.42 + cloud_a * 0.72);
        vec3 cloud_color = mix(cloud_shadow, cloud_light, lit_edge);
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
    env.fog_light_energy = 0.20
    env.fog_density = 0.00011
    env.fog_sky_affect = 0.12
    env.fog_height = 18.0
    env.fog_height_density = 0.0035
    env.volumetric_fog_enabled = false
    environment_node.environment = env


func _capture_hero_face_sheet() -> void:
    var output_path: String = await $Player.capture_face_inspection_sheet()
    if output_path.is_empty():
        push_warning("Hero face capture failed.")
        return
    print("Hero face capture saved to: %s" % output_path)
