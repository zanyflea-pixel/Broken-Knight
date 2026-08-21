extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const PLAYABLE_WARMUP_FRAMES := 120
const PLAYABLE_WARMUP_LIMIT := 180

var _main: Node3D
var _last_logged_progress := -1
var _last_logged_status := ""

@onready var _background: ColorRect = $Overlay/Background
@onready var _splash: TextureRect = $Overlay/Splash
@onready var _panel: Panel = $Overlay/Panel
@onready var _status: Label = $Overlay/Panel/VBox/StatusRow/Status
@onready var _percent: Label = $Overlay/Panel/VBox/StatusRow/Percent
@onready var _details: Label = $Overlay/Panel/VBox/Details
@onready var _progress_bar: ProgressBar = $Overlay/Panel/VBox/ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Windows' default VSync path turns a narrowly missed 16.7 ms deadline into
	# a visibly doubled frame. A 120 Hz game cap leaves ample render headroom on
	# a 60 Hz display while avoiding that walking hitch amplification.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	DisplayServer.window_set_title("Broken Knight")
	_set_progress("Opening Broken Knight...", "Starting the loading scene.", 2.0)
	call_deferred("_begin_boot")


func _process(_delta: float) -> void:
	if _panel.visible:
		DisplayServer.window_set_title("Broken Knight")


func _begin_boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_set_progress("Loading game scene", "Reading the player, camera, interface, and world roots.", 4.0)
	var load_error := ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)
	if load_error != OK:
		_set_progress("Unable to load the game", "Godot could not start the main scene loader.", 4.0)
		return
	var load_progress: Array = []
	while true:
		var load_status := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, load_progress)
		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if load_status == ResourceLoader.THREAD_LOAD_FAILED or load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_set_progress("Unable to load the game", "The main scene failed to load. Check the Godot log for details.", 4.0)
			return
		var scene_progress := float(load_progress[0]) if not load_progress.is_empty() else 0.0
		_set_progress("Loading game scene", "Reading the player, camera, interface, and world roots.", lerpf(4.0, 7.0, scene_progress))
		await get_tree().process_frame
	var main_scene := ResourceLoader.load_threaded_get(MAIN_SCENE_PATH) as PackedScene
	_main = main_scene.instantiate() as Node3D if main_scene != null else null
	if _main == null:
		_set_progress("Unable to load the game", "The main scene could not be created. Check the Godot log for details.", 7.0)
		return
	_main.set("auto_boot_enabled", false)
	# Render the world behind the opaque splash as it is assembled. This lets
	# Godot upload meshes and compile materials before the first playable frame.
	_main.visible = true
	var main_ui := _main.get_node_or_null("UI") as CanvasLayer
	if main_ui != null:
		main_ui.visible = false
	add_child(_main)
	_set_progress("Preparing world systems", "The game scene is ready. Starting world generation.", 8.0)
	await get_tree().process_frame
	await _main.boot_world(Callable(self, "_update_progress"), false, true)
	_set_progress("Smoothing first movement", "Compiling nearby materials and finishing the local map.", 98.0)
	await _warm_first_playable_frames()
	_set_progress("Ready", "Entering the world.", 100.0)
	var reveal := create_tween().set_parallel(true)
	reveal.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.tween_property(_background, "modulate:a", 0.0, 0.28)
	reveal.tween_property(_splash, "modulate:a", 0.0, 0.28)
	reveal.tween_property(_panel, "modulate:a", 0.0, 0.28)
	await reveal.finished
	_background.visible = false
	_splash.visible = false
	_panel.visible = false


func _update_progress(text: String, progress: float) -> void:
	# Main finishes world generation at 100%, but the desktop boot still owns a
	# short render/minimap warmup. Reserve the last two percent for that work.
	var displayed_progress := minf(progress, 97.0) if progress >= 97.0 else progress
	_set_progress(text, _detail_for_status(text), displayed_progress)


func _warm_first_playable_frames() -> void:
	if not is_instance_valid(_main):
		return
	# Headless verification has no presented render frames to warm. Waiting on
	# frame_post_draw there can never exercise the desktop GPU path and only
	# stalls the Boot contract at 98 percent.
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var player := _main.get_node_or_null("Player") as CharacterBody3D
	var camera_pivot := _main.get_node_or_null("Player/CameraPivot") as Node3D
	var hero_visual := _main.get_node_or_null("Player/Visual") as Node3D
	var minimap := _main.get_node_or_null("UI/Minimap")
	var director := _main.get_node_or_null("GameplayDirector")
	var original_yaw := float(player.get("_yaw")) if is_instance_valid(player) else 0.0
	var original_pivot_yaw := camera_pivot.rotation.y if is_instance_valid(camera_pivot) else 0.0
	var original_player_position := player.global_position if is_instance_valid(player) else Vector3.ZERO
	var height_sampler: Callable = player.get("_height_sampler") if is_instance_valid(player) else Callable()
	var warmup_offsets: Array[Vector2] = [Vector2.ZERO, Vector2(0.0, 42.0), Vector2(42.0, 0.0), Vector2(0.0, -42.0), Vector2(-42.0, 0.0)]
	var regional_points: Array[Vector2] = []
	var profile: Dictionary = _main.get("_active_profile")
	for site_value in profile.get("town_sites", []):
		if site_value is Dictionary:
			regional_points.append(Vector2(site_value.get("position", Vector2.ZERO)) + Vector2(0.0, 42.0))
	if is_instance_valid(player):
		player.set_input_enabled(false)
	if is_instance_valid(hero_visual):
		if hero_visual.has_method("set_move_blend"):
			hero_visual.set_move_blend(1.0)
		if hero_visual.has_method("set_movement_speed"):
			hero_visual.set_movement_speed(float(player.get("walk_speed")) if is_instance_valid(player) else 5.2)
	if is_instance_valid(player):
		# Exercise the real movement, collision and ground-query path while hidden.
		# Merely posing the animated mesh leaves PhysicsServer's first contact work
		# for the first player-controlled frame.
		player.set_input_enabled(true)
		_send_warmup_key(KEY_W, true)
		_send_warmup_key(KEY_SHIFT, true)
	# First complete real movement/physics initialization around Riverwatch and
	# let its incremental minimap texture reach a finished state.
	for frame_index in range(PLAYABLE_WARMUP_LIMIT):
		if frame_index < PLAYABLE_WARMUP_FRAMES:
			var warmup_index := mini(warmup_offsets.size() - 1, floori(float(frame_index) / 24.0))
			if is_instance_valid(player) and height_sampler.is_valid():
				var point: Vector2 = Vector2(original_player_position.x, original_player_position.z) + warmup_offsets[warmup_index]
				var ground: Vector3 = height_sampler.call(point.x, point.y)
				player.global_position = ground + Vector3.UP * float(player.get("hover_height"))
			if is_instance_valid(camera_pivot):
				camera_pivot.rotation.y = original_pivot_yaw + float(warmup_index) * PI * 0.5
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame_index + 1 >= PLAYABLE_WARMUP_FRAMES and _minimap_is_ready(minimap):
			break
	_send_warmup_key(KEY_W, false)
	_send_warmup_key(KEY_SHIFT, false)
	if is_instance_valid(player):
		player.set_input_enabled(false)
	# Distant towns share most materials but still create unique first-visible
	# culling and pipeline combinations. Warm one approach to each town without
	# making the minimap rebuild for temporary diagnostic positions.
	var minimap_process_mode := minimap.process_mode if is_instance_valid(minimap) else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(minimap):
		minimap.process_mode = Node.PROCESS_MODE_DISABLED
	for regional_index in range(regional_points.size()):
		var point := regional_points[regional_index]
		if is_instance_valid(player) and height_sampler.is_valid():
			var regional_ground: Vector3 = height_sampler.call(point.x, point.y)
			player.global_position = regional_ground + Vector3.UP * float(player.get("hover_height"))
		if is_instance_valid(director) and director.has_method("_stream_local_gameplay"):
			director.call("_stream_local_gameplay", true)
		for frame_index in range(24):
			if is_instance_valid(camera_pivot):
				camera_pivot.rotation.y = original_pivot_yaw + float(regional_index % 4) * PI * 0.5
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	if is_instance_valid(camera_pivot):
		camera_pivot.rotation.y = original_pivot_yaw
	if is_instance_valid(player):
		player.global_position = original_player_position
		player.set("_yaw", original_yaw)
		player.set("_current_move_speed", 0.0)
	if is_instance_valid(minimap):
		minimap.process_mode = minimap_process_mode
	if is_instance_valid(director) and director.has_method("_stream_local_gameplay"):
		director.call("_stream_local_gameplay", true)
	if is_instance_valid(hero_visual):
		if hero_visual.has_method("set_move_blend"):
			hero_visual.set_move_blend(0.0)
		if hero_visual.has_method("set_movement_speed"):
			hero_visual.set_movement_speed(0.0)
	if is_instance_valid(player):
		player.set_input_enabled(true)
	# Present the restored spawn state under the splash as well. This prevents
	# the first visible frame from paying for the transition back from warmup.
	for frame_index in range(12):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _send_warmup_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _minimap_is_ready(minimap: Node) -> bool:
	if not is_instance_valid(minimap):
		return true
	return int(minimap.get("_pending_row")) < 0 and int(minimap.get("_pending_color_row")) < 0


func _set_progress(status_text: String, detail_text: String, progress: float) -> void:
	var display_progress := int(round(progress))
	_status.text = status_text.trim_suffix("...")
	_percent.text = "%d%%" % display_progress
	_details.text = detail_text
	_progress_bar.value = progress
	if display_progress != _last_logged_progress or status_text != _last_logged_status:
		print("BOOT_PROGRESS|%d|%s" % [display_progress, status_text])
		_last_logged_progress = display_progress
		_last_logged_status = status_text


func _detail_for_status(status_text: String) -> String:
	if status_text.begins_with("Laying rivers"):
		return "Connecting waterways, crossings, and travel routes."
	if status_text.begins_with("Growing forests"):
		return "Planting biome-specific trees and undergrowth."
	if status_text.begins_with("Scattering rocks"):
		return "Adding natural formations and terrain detail."
	if status_text.begins_with("Refining paths"):
		return "Clearing readable routes through the landscape."
	if status_text.begins_with("Filling the living world"):
		return "Adding shrubs, habitat detail, and local variation."
	if status_text.begins_with("Raising landmarks"):
		return "Placing recognizable sites across the realm."
	if status_text.begins_with("Building towns"):
		return "Assembling settlements and points of interest."
	if status_text.begins_with("Finalizing the world"):
		return "Optimizing the finished world for smooth play."
	match status_text:
		"Preparing world systems...":
			return "Loading startup services and world configuration."
		"Configuring world lighting...":
			return "Setting the sky, sunlight, shadows, and atmosphere."
		"Creating world builders...":
			return "Starting terrain and environment generators."
		"Generating world profile...":
			return "Planning terrain, rivers, roads, towns, and travel routes."
		"Building terrain...":
			return "Creating terrain mesh, collision, and walkable surfaces."
		"Starting gameplay systems...":
			return "Placing the hero and enabling core gameplay."
		"Preparing maps and interface...":
			return "Building maps, menus, HUD, and interaction systems."
		"Finishing world details...":
			return "Placing roads, bridges, towns, props, and world details."
		"Ready.":
			return "Entering the world."
		_:
			return "Loading the next part of the world."
