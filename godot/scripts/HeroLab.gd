extends Node3D

const BUILD_ID := "face-pass-20260628-2025"
const MIN_PROMOTION_INTEGRITY_SCORE := 70.0
const MAX_PROMOTION_HOLES := 0
const MIN_PROMOTION_COMBINED_GAIN := 1.5
const MAX_PROMOTION_IMAGE_REGRESSION := 1.0
const MAX_PROMOTION_PROFILE_REGRESSION := 2.0
const MAX_PROMOTION_INTEGRITY_REGRESSION := 0.25
const MAX_CANDIDATE_DANGER_SCORE := 24.0
const SHORTLIST_MAX_SIZE := 8
const TRUST_REGION_SCALE := 0.72
const FACE_VARIANTS := [
	{"name": "baseline", "profile": {}},
	{"name": "softer", "profile": {"cheek_depth": 0.091, "mouth_depth": 0.097, "chin_depth": 0.081, "jaw_depth": 0.078}},
	{"name": "stronger_brow", "profile": {"brow_outer": 0.036, "eye_socket_depth": 0.108, "eye_depth": 0.115}},
	{"name": "narrow", "profile": {"eye_spacing": 0.028, "cheek_depth": 0.092, "jaw_depth": 0.078}},
	{"name": "wide", "profile": {"eye_spacing": 0.032, "brow_outer": 0.036, "cheek_depth": 0.096}},
	{"name": "human_try", "profile": {"eye_spacing": 0.029, "eye_depth": 0.114, "eye_socket_depth": 0.107, "nose_depth": 0.114, "philtrum_depth": 0.105, "mouth_depth": 0.100, "chin_depth": 0.084, "jaw_depth": 0.081, "cheek_depth": 0.095, "hair_side": 0.070, "hair_front": 0.040}}
]
const SCORABLE_PROFILE_KEYS := [
	"eye_spacing",
	"eye_y",
	"brow_outer",
	"nose_y",
	"mouth_y",
	"nose_depth",
	"philtrum_depth",
	"mouth_depth",
	"chin_depth",
	"chin_y",
	"jaw_depth",
	"jaw_width",
	"cheek_depth",
	"hair_side",
	"hair_front",
]
const TARGET_FACE_PROFILE := {
	"eye_spacing": 0.029,
	"eye_y": -0.003,
	"brow_outer": 0.032,
	"nose_y": -0.012,
	"mouth_y": -0.044,
	"nose_depth": 0.104,
	"philtrum_depth": 0.099,
	"mouth_depth": 0.094,
	"chin_depth": 0.082,
	"chin_y": -0.066,
	"jaw_depth": 0.078,
	"jaw_width": 0.021,
	"cheek_depth": 0.094,
	"hair_side": 0.076,
	"hair_front": 0.040,
}

var _menu_open := false
var _variant_index := 0
var _promoted_baseline_profile: Dictionary = {}
var _promoted_baseline_metrics: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_set_title("Hero Lab - %s" % BUILD_ID)
	_configure_environment()
	_wire_menu()
	_set_menu_open(false)
	_position_player()
	$UI/BuildLabel.text = BUILD_ID
	_load_promoted_baseline_profile()
	_load_promoted_baseline_metrics()
	_apply_variant(0)
	call_deferred("_handle_startup_capture_args")
	call_deferred("_restore_window_title")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		await _capture_hero_face_sheet()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		await _capture_face_review_pack()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		await _capture_face_variant_batch()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_cycle_variant(1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		await _capture_face_search_batch()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		await _capture_face_attachment_search_batch()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		await _capture_eye_fit_batch()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		await _capture_profile_lab_sheet()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		await _capture_face_optimizer_batch()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		await _capture_head_integrity_audit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_set_menu_open(not _menu_open)


func _position_player() -> void:
	var player: CharacterBody3D = $Player
	player.global_position = Vector3(0.0, 0.06, 0.0)
	player.rotation.y = PI


func _wire_menu() -> void:
	$UI/PauseMenu/MenuPanel/MenuButtons/ResumeButton.pressed.connect(_on_resume_pressed)
	$UI/PauseMenu/MenuPanel/MenuButtons/CloseGameButton.pressed.connect(_on_close_game_pressed)


func _set_menu_open(open: bool) -> void:
	_menu_open = open
	get_tree().paused = open
	$UI/PauseMenu.visible = open
	$Player.set_input_enabled(not open)


func _on_resume_pressed() -> void:
	_set_menu_open(false)


func _on_close_game_pressed() -> void:
	get_tree().quit()


func _configure_environment() -> void:
	var key_light: DirectionalLight3D = $KeyLight
	key_light.light_color = Color(1.0, 0.96, 0.92, 1.0)
	key_light.light_energy = 1.10
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 80.0

	var fill_light: DirectionalLight3D = $FillLight
	fill_light.light_color = Color(0.67, 0.76, 0.90, 1.0)
	fill_light.light_energy = 0.32
	fill_light.shadow_enabled = false

	var rim_light: DirectionalLight3D = $RimLight
	rim_light.light_color = Color(0.96, 0.92, 0.86, 1.0)
	rim_light.light_energy = 0.20
	rim_light.shadow_enabled = false

	var environment_node: WorldEnvironment = $Environment
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.44, 0.58, 0.76, 1.0)
	sky_material.sky_horizon_color = Color(0.62, 0.70, 0.82, 1.0)
	sky_material.ground_bottom_color = Color(0.34, 0.40, 0.40, 1.0)
	sky_material.ground_horizon_color = Color(0.48, 0.54, 0.54, 1.0)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.05
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.91, 0.96, 1.0)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.94
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 0.96
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	environment_node.environment = env


func _capture_hero_face_sheet() -> void:
	var output_path: String = await $Player.capture_face_inspection_sheet()
	if output_path.is_empty():
		push_warning("Hero face capture failed.")
		return
	print("Hero face capture saved to: %s" % output_path)


func _cycle_variant(direction: int) -> void:
	var next_index := posmod(_variant_index + direction, FACE_VARIANTS.size())
	_apply_variant(next_index)


func _apply_variant(index: int) -> void:
	_variant_index = clampi(index, 0, FACE_VARIANTS.size() - 1)
	var visual := $Player/Visual
	if visual.has_method("apply_face_profile"):
		visual.apply_face_profile(_get_variant_profile(_variant_index))
	$UI/BuildLabel.text = "%s | variant: %s | F3 audit | F4 optimize | F5 full-review | F6 cycle | F7 tight | F8 batch | F9 search | F10 attach | F11 eyes | F12 profile" % [BUILD_ID, FACE_VARIANTS[_variant_index]["name"]]


func _get_variant_profile(index: int) -> Dictionary:
	var profile: Dictionary = FACE_VARIANTS[index]["profile"].duplicate(true)
	if index == 0 and not _promoted_baseline_profile.is_empty():
		for key in _promoted_baseline_profile.keys():
			profile[key] = _promoted_baseline_profile[key]
	return profile


func _get_promoted_baseline_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_promoted_baseline.json")


func _load_promoted_baseline_profile() -> void:
	_promoted_baseline_profile = {}
	var baseline_path := _get_promoted_baseline_path()
	if not FileAccess.file_exists(baseline_path):
		return
	var file := FileAccess.open(baseline_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		_promoted_baseline_profile = parsed.duplicate(true)


func _save_promoted_baseline_profile(profile: Dictionary) -> void:
	_promoted_baseline_profile = profile.duplicate(true)
	var baseline_path := _get_promoted_baseline_path()
	_backup_promoted_baseline_file(baseline_path)
	var file := FileAccess.open(baseline_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_promoted_baseline_profile, "\t"))
	file.close()
	print("Hero face promoted baseline saved to: %s" % baseline_path)


func _backup_promoted_baseline_file(baseline_path: String) -> void:
	if not FileAccess.file_exists(baseline_path):
		return
	var backup_dir := ProjectSettings.globalize_path("user://captures/baseline_backups")
	DirAccess.make_dir_recursive_absolute(backup_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup_path := backup_dir.path_join("hero_face_promoted_baseline_%s.json" % stamp)
	DirAccess.copy_absolute(baseline_path, backup_path)
	print("Hero face baseline backup saved to: %s" % backup_path)


func _get_promoted_baseline_metrics_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_promoted_baseline_metrics.json")


func _load_promoted_baseline_metrics() -> void:
	_promoted_baseline_metrics = {}
	var metrics_path := _get_promoted_baseline_metrics_path()
	if not FileAccess.file_exists(metrics_path):
		return
	var file := FileAccess.open(metrics_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		_promoted_baseline_metrics = parsed.duplicate(true)


func _save_promoted_baseline_metrics(metrics: Dictionary) -> void:
	_promoted_baseline_metrics = metrics.duplicate(true)
	var metrics_path := _get_promoted_baseline_metrics_path()
	_backup_promoted_baseline_file(metrics_path)
	var file := FileAccess.open(metrics_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_promoted_baseline_metrics, "\t"))
	file.close()
	print("Hero face promoted baseline metrics saved to: %s" % metrics_path)


func _get_cached_face_sheet_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_sheet.png")


func _get_cached_profile_lab_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_profile_lab.png")


func _get_face_revision_log_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_revision_log.jsonl")


func _get_face_shortlist_path() -> String:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	return capture_dir.path_join("hero_face_shortlist.json")


func _append_face_revision_log(event_type: String, payload: Dictionary) -> void:
	var log_path := _get_face_revision_log_path()
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE_READ
	var file := FileAccess.open(log_path, mode)
	if file == null:
		return
	file.seek_end()
	var record := {
		"time": Time.get_datetime_string_from_system(),
		"build_id": BUILD_ID,
		"event": event_type,
		"payload": payload,
	}
	file.store_string(JSON.stringify(record) + "\n")
	file.close()


func _load_face_shortlist() -> Array:
	var shortlist_path := _get_face_shortlist_path()
	if not FileAccess.file_exists(shortlist_path):
		return []
	var file := FileAccess.open(shortlist_path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed.duplicate(true)


func _save_face_shortlist(entries: Array) -> void:
	var shortlist_path := _get_face_shortlist_path()
	var file := FileAccess.open(shortlist_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(entries, "\t"))
	file.close()


func _get_shortlist_profile_average(shortlist: Array) -> Dictionary:
	var average := TARGET_FACE_PROFILE.duplicate(true)
	if shortlist.is_empty():
		return average
	for key in SCORABLE_PROFILE_KEYS:
		var total := 0.0
		var count := 0.0
		for entry in shortlist:
			var profile: Dictionary = entry.get("profile", {})
			total += float(profile.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
			count += 1.0
		if count > 0.0:
			average[key] = total / count
	return average


func _get_shortlist_profile_spread(shortlist: Array) -> Dictionary:
	var spread := {}
	if shortlist.is_empty():
		for key in SCORABLE_PROFILE_KEYS:
			spread[key] = 0.0
		return spread
	var average := _get_shortlist_profile_average(shortlist)
	for key in SCORABLE_PROFILE_KEYS:
		var max_delta := 0.0
		var anchor := float(average.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
		for entry in shortlist:
			var profile: Dictionary = entry.get("profile", {})
			var value := float(profile.get(key, anchor))
			max_delta = maxf(max_delta, absf(value - anchor))
		spread[key] = max_delta
	return spread


func _update_face_shortlist(candidate: Dictionary, metrics: Dictionary) -> void:
	var shortlist := _load_face_shortlist()
	shortlist.append({
		"name": str(candidate.get("name", "candidate")),
		"profile": candidate.get("profile", {}).duplicate(true),
		"metrics": metrics.duplicate(true),
		"time": Time.get_datetime_string_from_system(),
		"build_id": BUILD_ID,
	})
	shortlist.sort_custom(func(a, b): return float(a.get("metrics", {}).get("combined_score", 0.0)) > float(b.get("metrics", {}).get("combined_score", 0.0)))
	var trimmed: Array = []
	var seen := {}
	for entry in shortlist:
		var key := JSON.stringify(entry.get("profile", {}))
		if seen.has(key):
			continue
		seen[key] = true
		trimmed.append(entry)
		if trimmed.size() >= SHORTLIST_MAX_SIZE:
			break
	_save_face_shortlist(trimmed)


func _is_candidate_safe_to_promote(integrity_metrics: Dictionary) -> bool:
	var integrity_score := float(integrity_metrics.get("integrity_score", 0.0))
	var front_holes := int(integrity_metrics.get("front_holes", 99))
	var profile_holes := int(integrity_metrics.get("profile_holes", 99))
	return integrity_score >= MIN_PROMOTION_INTEGRITY_SCORE and front_holes <= MAX_PROMOTION_HOLES and profile_holes <= MAX_PROMOTION_HOLES


func _get_candidate_metric_snapshot(candidate: Dictionary) -> Dictionary:
	return {
		"combined_score": float(candidate.get("combined_score", 0.0)),
		"profile_score": float(candidate.get("profile_score", 0.0)),
		"image_score": float(candidate.get("image_metrics", {}).get("image_score", 0.0)),
		"integrity_score": float(candidate.get("integrity_metrics", {}).get("integrity_score", 0.0)),
		"front_holes": int(candidate.get("integrity_metrics", {}).get("front_holes", 99)),
		"profile_holes": int(candidate.get("integrity_metrics", {}).get("profile_holes", 99)),
	}


func _compare_candidate_to_baseline(candidate: Dictionary) -> Dictionary:
	var candidate_metrics := _get_candidate_metric_snapshot(candidate)
	if _promoted_baseline_metrics.is_empty():
		return {
			"ok": true,
			"reasons": PackedStringArray(["No promoted baseline metrics yet."]),
			"candidate_metrics": candidate_metrics,
		}

	var reasons := PackedStringArray()
	var baseline_combined := float(_promoted_baseline_metrics.get("combined_score", 0.0))
	var baseline_profile := float(_promoted_baseline_metrics.get("profile_score", 0.0))
	var baseline_image := float(_promoted_baseline_metrics.get("image_score", 0.0))
	var baseline_integrity := float(_promoted_baseline_metrics.get("integrity_score", 0.0))
	var baseline_front_holes := int(_promoted_baseline_metrics.get("front_holes", 99))
	var baseline_profile_holes := int(_promoted_baseline_metrics.get("profile_holes", 99))

	if candidate_metrics["combined_score"] < baseline_combined + MIN_PROMOTION_COMBINED_GAIN:
		reasons.append("combined score did not beat approved baseline by %.2f" % MIN_PROMOTION_COMBINED_GAIN)
	if candidate_metrics["image_score"] < baseline_image - MAX_PROMOTION_IMAGE_REGRESSION:
		reasons.append("image score regressed more than %.2f" % MAX_PROMOTION_IMAGE_REGRESSION)
	if candidate_metrics["profile_score"] < baseline_profile - MAX_PROMOTION_PROFILE_REGRESSION:
		reasons.append("profile score regressed more than %.2f" % MAX_PROMOTION_PROFILE_REGRESSION)
	if candidate_metrics["integrity_score"] < baseline_integrity - MAX_PROMOTION_INTEGRITY_REGRESSION:
		reasons.append("integrity score regressed more than %.2f" % MAX_PROMOTION_INTEGRITY_REGRESSION)
	if int(candidate_metrics["front_holes"]) > baseline_front_holes:
		reasons.append("front holes worse than approved baseline")
	if int(candidate_metrics["profile_holes"]) > baseline_profile_holes:
		reasons.append("profile holes worse than approved baseline")

	return {
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"candidate_metrics": candidate_metrics,
	}


func _get_candidate_danger_report(profile: Dictionary) -> Dictionary:
	var danger_score := 0.0
	var reasons := PackedStringArray()
	var eye_y := float(profile.get("eye_y", TARGET_FACE_PROFILE["eye_y"]))
	var mouth_y := float(profile.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"]))
	var chin_y := float(profile.get("chin_y", TARGET_FACE_PROFILE["chin_y"]))
	var jaw_width := float(profile.get("jaw_width", TARGET_FACE_PROFILE["jaw_width"]))
	var nose_depth := float(profile.get("nose_depth", TARGET_FACE_PROFILE["nose_depth"]))
	var philtrum_depth := float(profile.get("philtrum_depth", TARGET_FACE_PROFILE["philtrum_depth"]))
	var hair_front := float(profile.get("hair_front", TARGET_FACE_PROFILE["hair_front"]))
	var hair_side := float(profile.get("hair_side", TARGET_FACE_PROFILE["hair_side"]))

	if eye_y > -0.0005:
		danger_score += 8.0
		reasons.append("eyes drifting too high")
	if mouth_y > -0.0415:
		danger_score += 6.0
		reasons.append("mouth drifting too high")
	if chin_y > -0.061:
		danger_score += 8.0
		reasons.append("chin too short")
	if chin_y < mouth_y - 0.024:
		danger_score += 4.0
		reasons.append("lower face stretched")
	if jaw_width < 0.0175 or jaw_width > 0.0215:
		danger_score += 6.0
		reasons.append("jaw width outside safe band")
	if nose_depth < 0.099 or nose_depth > 0.108:
		danger_score += 5.0
		reasons.append("nose depth outside safe band")
	if philtrum_depth < 0.095 or philtrum_depth > 0.103:
		danger_score += 4.0
		reasons.append("philtrum depth outside safe band")
	if hair_front < 0.042:
		danger_score += 8.0
		reasons.append("front hair too thin")
	if hair_side < 0.076:
		danger_score += 7.0
		reasons.append("side hair too thin")

	return {
		"danger_score": danger_score,
		"reasons": reasons,
		"ok": danger_score <= MAX_CANDIDATE_DANGER_SCORE,
	}


func _get_optimizer_focus_keys(base: Dictionary) -> Dictionary:
	var focus := {
		"structure": PackedStringArray(["eye_y", "nose_y", "mouth_y", "chin_y", "jaw_width"]),
		"depth": PackedStringArray(["nose_depth", "philtrum_depth", "mouth_depth", "chin_depth", "jaw_depth", "cheek_depth"]),
		"hair": PackedStringArray(["hair_side", "hair_front"]),
	}
	var target_delta := {}
	for key in SCORABLE_PROFILE_KEYS:
		var value := float(base.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
		var target := float(TARGET_FACE_PROFILE.get(key, value))
		target_delta[key] = absf(value - target)
	if float(target_delta.get("hair_front", 0.0)) < 0.004:
		focus["hair"] = PackedStringArray(["hair_side"])
	if float(target_delta.get("hair_side", 0.0)) < 0.004 and float(target_delta.get("hair_front", 0.0)) < 0.004:
		focus["hair"] = PackedStringArray()
	if float(target_delta.get("mouth_y", 0.0)) < 0.003 and float(target_delta.get("chin_y", 0.0)) < 0.003:
		focus["structure"] = PackedStringArray(["eye_y", "nose_y", "jaw_width"])
	if float(target_delta.get("nose_depth", 0.0)) < 0.003 and float(target_delta.get("philtrum_depth", 0.0)) < 0.003:
		focus["depth"] = PackedStringArray(["mouth_depth", "chin_depth", "jaw_depth", "cheek_depth"])
	return focus


func _get_feature_lock_map(base: Dictionary, shortlist: Array) -> Dictionary:
	var locks := {}
	var target_delta := {}
	for key in SCORABLE_PROFILE_KEYS:
		var value := float(base.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
		var target := float(TARGET_FACE_PROFILE.get(key, value))
		target_delta[key] = absf(value - target)
	var shortlist_spread := _get_shortlist_profile_spread(shortlist)
	for key in SCORABLE_PROFILE_KEYS:
		var locked := false
		if float(target_delta.get(key, 0.0)) < _profile_key_range(key) * 0.25:
			locked = true
		if float(shortlist_spread.get(key, 0.0)) < _profile_key_range(key) * 0.12:
			locked = true
		locks[key] = locked
	return locks


func _get_adaptive_mutation_scale(seed_profile: Dictionary, key: String, shortlist: Array) -> float:
	var value := float(seed_profile.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
	var target := float(TARGET_FACE_PROFILE.get(key, value))
	var delta_to_target := absf(value - target)
	var range := _profile_key_range(key)
	var shortlist_spread := _get_shortlist_profile_spread(shortlist)
	var local_spread := float(shortlist_spread.get(key, 0.0))
	var scale := TRUST_REGION_SCALE
	if delta_to_target > range * 0.55:
		scale *= 1.35
	elif delta_to_target < range * 0.20:
		scale *= 0.60
	if local_spread < range * 0.10:
		scale *= 0.72
	elif local_spread > range * 0.35:
		scale *= 1.10
	return clampf(scale, 0.35, 1.25)


func _capture_face_variant_batch() -> void:
	var visual := $Player/Visual
	if not visual.has_method("apply_face_profile"):
		return
	var original_index := _variant_index
	var original_profile = {}
	if visual.has_method("get_face_profile"):
		original_profile = visual.get_face_profile()
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var paths: Array[String] = []
	for index in range(FACE_VARIANTS.size()):
		_apply_variant(index)
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var output_path: String = await $Player.capture_face_inspection_sheet()
		if output_path.is_empty():
			continue
		var variant_path := capture_dir.path_join("hero_face_variant_%02d_%s.png" % [index, FACE_VARIANTS[index]["name"]])
		DirAccess.copy_absolute(output_path, variant_path)
		paths.append(variant_path)
	visual.apply_face_profile(original_profile)
	_apply_variant(original_index)
	if paths.is_empty():
		push_warning("Hero face batch capture failed.")
		return
	var images: Array[Image] = []
	for path in paths:
		var image := Image.load_from_file(path)
		if image.is_empty():
			continue
		images.append(image)
	if images.is_empty():
		return
	var frame_width := images[0].get_width()
	var frame_height := images[0].get_height()
	var columns := 3
	var rows := int(ceil(float(images.size()) / float(columns)))
	var sheet := Image.create(frame_width * columns, frame_height * rows, false, images[0].get_format())
	for index in range(images.size()):
		var col := index % columns
		var row := index / columns
		sheet.blit_rect(images[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))
	var batch_path := capture_dir.path_join("hero_face_variant_batch.png")
	var err := sheet.save_png(batch_path)
	if err == OK:
		print("Hero face variant batch saved to: %s" % batch_path)


func _build_face_search_variants() -> Array:
	var variants: Array = []
	var base: Dictionary = FACE_VARIANTS[_variant_index]["profile"].duplicate(true)
	var pushes := [
		{"name": "keeper", "profile": {}},
		{"name": "lower_eyes", "profile": {"eye_y": -0.004, "brow_outer": 0.035}},
		{"name": "higher_eyes", "profile": {"eye_y": 0.008, "brow_outer": 0.033}},
		{"name": "shorter_face", "profile": {"mouth_y": -0.042, "chin_y": -0.062, "head_anchor_y": 1.58}},
		{"name": "longer_face", "profile": {"mouth_y": -0.054, "chin_y": -0.078, "head_anchor_y": 1.54}},
		{"name": "stronger_jaw", "profile": {"jaw_width": 0.024, "chin_depth": 0.086, "chin_y": -0.072}},
		{"name": "softer_jaw", "profile": {"jaw_width": 0.016, "chin_depth": 0.080, "chin_y": -0.068}},
		{"name": "forward_nose", "profile": {"nose_depth": 0.118, "philtrum_depth": 0.107}},
		{"name": "back_nose", "profile": {"nose_depth": 0.108, "philtrum_depth": 0.101}},
		{"name": "hair_wrap", "profile": {"hair_side": 0.078, "hair_front": 0.046}},
		{"name": "hair_tighter", "profile": {"hair_side": 0.066, "hair_front": 0.036}},
		{"name": "humanized_a", "profile": {"eye_y": -0.002, "nose_y": -0.010, "mouth_y": -0.046, "chin_y": -0.068, "jaw_width": 0.018, "hair_side": 0.074}},
		{"name": "humanized_b", "profile": {"eye_y": 0.000, "nose_y": -0.012, "mouth_y": -0.050, "chin_y": -0.072, "jaw_width": 0.021, "hair_front": 0.044}},
	]
	for push in pushes:
		var merged: Dictionary = base.duplicate(true)
		for key in push["profile"].keys():
			merged[key] = push["profile"][key]
		variants.append({"name": push["name"], "profile": merged})
	return variants


func _build_optimizer_variants() -> Array:
	var visual := $Player/Visual
	var base: Dictionary = {}
	if visual.has_method("get_face_profile"):
		base = visual.get_face_profile()
	var variants: Array = []
	var seen := {}
	var seed_profiles := _build_optimizer_seed_profiles(base)
	for seed in seed_profiles:
		_add_optimizer_variant(variants, seen, str(seed.get("name", "seed")), seed.get("profile", {}))
	var top_seed_variants := variants.duplicate(true)
	top_seed_variants.sort_custom(func(a, b): return a["score"] > b["score"])
	var refinement_seeds := top_seed_variants.slice(0, min(4, top_seed_variants.size()))
	for seed in refinement_seeds:
		var refined := _build_refinement_profiles(seed["profile"], str(seed["name"]))
		for candidate in refined:
			_add_optimizer_variant(variants, seen, str(candidate.get("name", "refine")), candidate.get("profile", {}))
	variants.sort_custom(func(a, b): return a["score"] > b["score"])
	return _select_diverse_variants(variants, min(14, variants.size()))


func _build_optimizer_seed_profiles(base: Dictionary) -> Array:
	var seeds: Array = []
	var baseline_profile := _promoted_baseline_profile if not _promoted_baseline_profile.is_empty() else base
	var target_profile := TARGET_FACE_PROFILE.duplicate(true)
	var shortlist := _load_face_shortlist()
	var shortlist_average := _get_shortlist_profile_average(shortlist)
	var families := [
		{
			"name": "rounder_head",
			"profile": {
				"eye_y": -0.002,
				"brow_outer": 0.031,
				"nose_y": -0.012,
				"mouth_y": -0.046,
				"nose_depth": 0.102,
				"philtrum_depth": 0.098,
				"chin_depth": 0.080,
				"chin_y": -0.066,
				"jaw_depth": 0.076,
				"jaw_width": 0.019,
				"cheek_depth": 0.090,
				"hair_side": 0.082,
				"hair_front": 0.048,
			},
		},
		{
			"name": "shorter_midface",
			"profile": {
				"eye_y": -0.001,
				"nose_y": -0.010,
				"mouth_y": -0.041,
				"chin_y": -0.061,
				"nose_depth": 0.102,
				"philtrum_depth": 0.096,
				"mouth_depth": 0.090,
				"chin_depth": 0.078,
				"jaw_depth": 0.074,
				"jaw_width": 0.018,
				"hair_side": 0.080,
				"hair_front": 0.046,
			},
		},
		{
			"name": "stronger_face_plane",
			"profile": {
				"eye_y": -0.003,
				"brow_outer": 0.033,
				"nose_depth": 0.108,
				"philtrum_depth": 0.101,
				"mouth_depth": 0.095,
				"chin_depth": 0.084,
				"jaw_depth": 0.079,
				"jaw_width": 0.020,
				"cheek_depth": 0.094,
				"hair_side": 0.080,
				"hair_front": 0.044,
			},
		},
		{
			"name": "hair_fuller",
			"profile": {
				"hair_side": 0.090,
				"hair_front": 0.056,
				"eye_y": -0.002,
				"jaw_width": 0.019,
				"nose_depth": 0.101,
				"chin_depth": 0.080,
			},
		},
	]
	var anchors := [
		{"name": "current", "profile": base},
		{"name": "approved", "profile": baseline_profile},
		{"name": "target", "profile": target_profile},
	]
	for entry in shortlist:
		seeds.append({
			"name": "shortlist_%s" % str(entry.get("name", "saved")),
			"profile": entry.get("profile", {}).duplicate(true),
		})
	if not shortlist.is_empty():
		seeds.append({
			"name": "shortlist_average",
			"profile": shortlist_average,
		})
	for anchor in anchors:
		seeds.append({"name": anchor["name"], "profile": _clamp_face_profile(anchor["profile"])})
	for family in families:
		for anchor in anchors:
			for weight in [0.35, 0.65, 1.0]:
				var blended := _blend_profiles(anchor["profile"], family["profile"], weight)
				seeds.append({
					"name": "%s_%s_%02d" % [anchor["name"], family["name"], int(weight * 100.0)],
					"profile": _clamp_face_profile(blended),
				})
	if not shortlist.is_empty():
		for family in families:
			for weight in [0.35, 0.65]:
				var shortlist_blended := _blend_profiles(shortlist_average, family["profile"], weight)
				seeds.append({
					"name": "shortavg_%s_%02d" % [family["name"], int(weight * 100.0)],
					"profile": _clamp_face_profile(shortlist_blended),
				})
	return seeds


func _build_refinement_profiles(seed_profile: Dictionary, seed_name: String) -> Array:
	var refined: Array = []
	var focus_keys := _get_optimizer_focus_keys(seed_profile)
	var shortlist := _load_face_shortlist()
	var lock_map := _get_feature_lock_map(seed_profile, shortlist)
	var passes := [
		{
			"name": "structure",
			"deltas": {
				"eye_y": [-0.0015, 0.0015],
				"nose_y": [-0.0015, 0.0015],
				"mouth_y": [-0.0030, 0.0030],
				"chin_y": [-0.0030, 0.0030],
				"jaw_width": [-0.0018, 0.0018],
			},
		},
		{
			"name": "depth",
			"deltas": {
				"nose_depth": [-0.004, 0.004],
				"philtrum_depth": [-0.004, 0.004],
				"mouth_depth": [-0.003, 0.003],
				"chin_depth": [-0.003, 0.003],
				"jaw_depth": [-0.003, 0.003],
				"cheek_depth": [-0.003, 0.003],
			},
		},
		{
			"name": "hair",
			"deltas": {
				"hair_side": [-0.006, 0.006],
				"hair_front": [-0.006, 0.006],
			},
		},
	]
	for refinement_pass in passes:
		refined.append({"name": "%s_%s_keep" % [seed_name, refinement_pass["name"]], "profile": _clamp_face_profile(seed_profile)})
		var active_keys: PackedStringArray = focus_keys.get(refinement_pass["name"], PackedStringArray())
		if active_keys.is_empty():
			continue
		for key in active_keys:
			if not refinement_pass["deltas"].has(key):
				continue
			if bool(lock_map.get(key, false)):
				continue
			for raw_delta in refinement_pass["deltas"][key]:
				var delta := float(raw_delta) * _get_adaptive_mutation_scale(seed_profile, key, shortlist)
				var candidate := seed_profile.duplicate(true)
				candidate[key] = float(candidate.get(key, TARGET_FACE_PROFILE.get(key, 0.0))) + delta
				if key == "mouth_y":
					candidate["chin_y"] = float(candidate["mouth_y"]) - 0.020
				if key == "chin_y":
					candidate["mouth_y"] = clampf(float(candidate["chin_y"]) + 0.020, -0.050, -0.040)
				if key == "philtrum_depth":
					candidate["mouth_depth"] = clampf(float(candidate["philtrum_depth"]) - 0.004, 0.078, 0.112)
				if key == "mouth_depth":
					candidate["philtrum_depth"] = clampf(float(candidate["mouth_depth"]) + 0.004, 0.094, 0.104)
				refined.append({
					"name": "%s_%s_%s_%s" % [seed_name, refinement_pass["name"], key, "plus" if delta > 0.0 else "minus"],
					"profile": _clamp_face_profile(candidate),
				})
	return refined


func _blend_profiles(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var merged := a.duplicate(true)
	for key in SCORABLE_PROFILE_KEYS:
		var av: float = float(a.get(key, TARGET_FACE_PROFILE.get(key, 0.0)))
		var bv: float = float(b.get(key, av))
		merged[key] = lerpf(av, bv, clampf(weight, 0.0, 1.0))
	merged["mouth_depth"] = clampf(float(merged.get("philtrum_depth", TARGET_FACE_PROFILE["philtrum_depth"])) - 0.004, 0.078, 0.112)
	merged["chin_y"] = float(merged.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"])) - 0.020
	return merged


func _clamp_face_profile(profile: Dictionary) -> Dictionary:
	var clamped := TARGET_FACE_PROFILE.duplicate(true)
	for key in profile.keys():
		clamped[key] = profile[key]
	clamped["eye_spacing"] = clampf(float(clamped.get("eye_spacing", TARGET_FACE_PROFILE["eye_spacing"])), 0.026, 0.032)
	clamped["eye_y"] = clampf(float(clamped.get("eye_y", TARGET_FACE_PROFILE["eye_y"])), -0.006, 0.001)
	clamped["brow_outer"] = clampf(float(clamped.get("brow_outer", TARGET_FACE_PROFILE["brow_outer"])), 0.028, 0.036)
	clamped["nose_y"] = clampf(float(clamped.get("nose_y", TARGET_FACE_PROFILE["nose_y"])), -0.016, -0.008)
	clamped["mouth_y"] = clampf(float(clamped.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"])), -0.050, -0.040)
	clamped["nose_depth"] = clampf(float(clamped.get("nose_depth", TARGET_FACE_PROFILE["nose_depth"])), 0.098, 0.110)
	clamped["philtrum_depth"] = clampf(float(clamped.get("philtrum_depth", TARGET_FACE_PROFILE["philtrum_depth"])), 0.094, 0.104)
	clamped["mouth_depth"] = clampf(float(clamped.get("mouth_depth", TARGET_FACE_PROFILE["mouth_depth"])), 0.088, 0.100)
	clamped["chin_depth"] = clampf(float(clamped.get("chin_depth", TARGET_FACE_PROFILE["chin_depth"])), 0.076, 0.086)
	clamped["chin_y"] = clampf(float(clamped.get("chin_y", TARGET_FACE_PROFILE["chin_y"])), -0.070, -0.060)
	clamped["jaw_depth"] = clampf(float(clamped.get("jaw_depth", TARGET_FACE_PROFILE["jaw_depth"])), 0.072, 0.082)
	clamped["jaw_width"] = clampf(float(clamped.get("jaw_width", TARGET_FACE_PROFILE["jaw_width"])), 0.017, 0.022)
	clamped["cheek_depth"] = clampf(float(clamped.get("cheek_depth", TARGET_FACE_PROFILE["cheek_depth"])), 0.088, 0.096)
	clamped["hair_side"] = clampf(float(clamped.get("hair_side", TARGET_FACE_PROFILE["hair_side"])), 0.074, 0.092)
	clamped["hair_front"] = clampf(float(clamped.get("hair_front", TARGET_FACE_PROFILE["hair_front"])), 0.040, 0.058)
	clamped["mouth_depth"] = clampf(float(clamped.get("philtrum_depth", TARGET_FACE_PROFILE["philtrum_depth"])) - 0.004, 0.078, 0.112)
	clamped["chin_y"] = float(clamped.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"])) - 0.020
	return clamped


func _add_optimizer_variant(variants: Array, seen: Dictionary, name: String, profile: Dictionary) -> void:
	var clamped := _clamp_face_profile(profile)
	var key := JSON.stringify(clamped)
	if seen.has(key):
		return
	var danger_report := _get_candidate_danger_report(clamped)
	if not bool(danger_report.get("ok", true)):
		return
	seen[key] = true
	variants.append({
		"name": name,
		"profile": clamped,
		"score": _score_face_profile(clamped),
		"danger_report": danger_report,
	})


func _score_face_profile(profile: Dictionary) -> float:
	var score := 100.0
	for key in SCORABLE_PROFILE_KEYS:
		var target: float = TARGET_FACE_PROFILE.get(key, 0.0)
		var value: float = profile.get(key, target)
		var delta := absf(value - target)
		match key:
			"eye_spacing":
				score -= delta * 2400.0
			"eye_y":
				score -= delta * 3200.0
			"brow_outer":
				score -= delta * 2200.0
			"nose_y":
				score -= delta * 2400.0
			"mouth_y":
				score -= delta * 1800.0
			"nose_depth":
				score -= delta * 1400.0
			"philtrum_depth":
				score -= delta * 1500.0
			"mouth_depth":
				score -= delta * 1300.0
			"chin_depth":
				score -= delta * 1200.0
			"chin_y":
				score -= delta * 1500.0
			"jaw_depth":
				score -= delta * 1200.0
			"jaw_width":
				score -= delta * 2200.0
			"cheek_depth":
				score -= delta * 1000.0
			"hair_side":
				score -= delta * 1200.0
			"hair_front":
				score -= delta * 1400.0
	if profile.get("eye_y", 0.0) > 0.001:
		score -= 8.0
	if profile.get("eye_y", 0.0) < -0.0055:
		score -= 5.0
	if profile.get("hair_front", 0.0) < 0.034:
		score -= 10.0
	if profile.get("hair_front", 0.0) < 0.042:
		score -= 12.0
	if profile.get("hair_side", 0.0) < 0.070:
		score -= 6.0
	if profile.get("hair_side", 0.0) < 0.076:
		score -= 10.0
	if profile.get("jaw_width", TARGET_FACE_PROFILE["jaw_width"]) > 0.024:
		score -= 6.0
	if profile.get("jaw_width", TARGET_FACE_PROFILE["jaw_width"]) < 0.0175:
		score -= 10.0
	if profile.get("nose_depth", TARGET_FACE_PROFILE["nose_depth"]) < 0.096:
		score -= 4.0
	if profile.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"]) > -0.0415:
		score -= 7.0
	if profile.get("chin_y", TARGET_FACE_PROFILE["chin_y"]) > -0.061:
		score -= 9.0
	if profile.get("chin_y", TARGET_FACE_PROFILE["chin_y"]) < profile.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"]) - 0.024:
		score -= 7.0
	return maxf(score, 0.0)


func _select_diverse_variants(sorted_variants: Array, desired_count: int) -> Array:
	var candidate_pool := sorted_variants.slice(0, min(sorted_variants.size(), 320))
	var selected: Array = []
	if candidate_pool.is_empty():
		return selected
	selected.append(candidate_pool[0])
	while selected.size() < desired_count and selected.size() < candidate_pool.size():
		var best_candidate: Dictionary = {}
		var best_value := -INF
		for candidate in candidate_pool:
			var already_kept := false
			for kept in selected:
				if kept["name"] == candidate["name"]:
					already_kept = true
					break
			if already_kept:
				continue
			var min_distance := INF
			for kept in selected:
				min_distance = minf(min_distance, _profile_distance(candidate["profile"], kept["profile"]))
			var structure_alignment := _structure_alignment_score(candidate["profile"])
			var novelty_bonus := clampf(min_distance, 0.0, 6.0) * 3.2
			var total_value := float(candidate["score"]) + novelty_bonus
			total_value += structure_alignment * 10.0
			if min_distance < 1.8:
				total_value -= (1.8 - min_distance) * 18.0
			if total_value > best_value:
				best_value = total_value
				best_candidate = candidate
		if best_candidate.is_empty():
			break
		selected.append(best_candidate)
	if selected.size() < desired_count:
		for candidate in candidate_pool:
			var already_kept := false
			for kept in selected:
				if kept["name"] == candidate["name"]:
					already_kept = true
					break
			if already_kept:
				continue
			selected.append(candidate)
			if selected.size() >= desired_count:
				break
	return selected


func _structure_alignment_score(profile: Dictionary) -> float:
	var eye_y := float(profile.get("eye_y", TARGET_FACE_PROFILE["eye_y"]))
	var mouth_y := float(profile.get("mouth_y", TARGET_FACE_PROFILE["mouth_y"]))
	var chin_y := float(profile.get("chin_y", TARGET_FACE_PROFILE["chin_y"]))
	var jaw_width := float(profile.get("jaw_width", TARGET_FACE_PROFILE["jaw_width"]))
	var hair_front := float(profile.get("hair_front", TARGET_FACE_PROFILE["hair_front"]))
	var hair_side := float(profile.get("hair_side", TARGET_FACE_PROFILE["hair_side"]))
	var score := 0.0
	if eye_y >= -0.0055 and eye_y <= -0.0010:
		score += 0.22
	if mouth_y >= -0.049 and mouth_y <= -0.042:
		score += 0.18
	if chin_y >= -0.069 and chin_y <= -0.061:
		score += 0.20
	if jaw_width >= 0.018 and jaw_width <= 0.021:
		score += 0.16
	if hair_front >= 0.044:
		score += 0.12
	if hair_side >= 0.078:
		score += 0.12
	return score


func _profile_distance(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for key in SCORABLE_PROFILE_KEYS:
		var av: float = a.get(key, TARGET_FACE_PROFILE.get(key, 0.0))
		var bv: float = b.get(key, TARGET_FACE_PROFILE.get(key, 0.0))
		var range := _profile_key_range(key)
		total += pow((av - bv) / maxf(range, 0.0001), 2.0)
	return sqrt(total)


func _profile_key_range(key: String) -> float:
	match key:
		"eye_spacing":
			return 0.004
		"eye_y":
			return 0.006
		"brow_outer":
			return 0.006
		"nose_y":
			return 0.004
		"mouth_y":
			return 0.008
		"nose_depth":
			return 0.012
		"philtrum_depth":
			return 0.012
		"mouth_depth":
			return 0.012
		"chin_depth":
			return 0.012
		"chin_y":
			return 0.010
		"jaw_depth":
			return 0.010
		"jaw_width":
			return 0.006
		"cheek_depth":
			return 0.010
		"hair_side":
			return 0.010
		"hair_front":
			return 0.010
	return 0.01


func _capture_face_search_batch() -> void:
	var visual := $Player/Visual
	if not visual.has_method("apply_face_profile"):
		return
	var original_index := _variant_index
	var original_profile = {}
	if visual.has_method("get_face_profile"):
		original_profile = visual.get_face_profile()
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var search_variants := _build_face_search_variants()
	var paths: Array[String] = []
	for index in range(search_variants.size()):
		visual.apply_face_profile(search_variants[index]["profile"])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var output_path: String = await $Player.capture_face_inspection_sheet()
		if output_path.is_empty():
			continue
		var variant_path := capture_dir.path_join("hero_face_search_%02d_%s.png" % [index, search_variants[index]["name"]])
		DirAccess.copy_absolute(output_path, variant_path)
		paths.append(variant_path)
	visual.apply_face_profile(original_profile)
	_apply_variant(original_index)
	if paths.is_empty():
		push_warning("Hero face search capture failed.")
		return
	var images: Array[Image] = []
	for path in paths:
		var image := Image.load_from_file(path)
		if image.is_empty():
			continue
		images.append(image)
	if images.is_empty():
		return
	var frame_width := images[0].get_width()
	var frame_height := images[0].get_height()
	var columns := 2
	var rows := int(ceil(float(images.size()) / float(columns)))
	var sheet := Image.create(frame_width * columns, frame_height * rows, false, images[0].get_format())
	for index in range(images.size()):
		var col := index % columns
		var row := index / columns
		sheet.blit_rect(images[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))
	var batch_path := capture_dir.path_join("hero_face_search_grid.png")
	var err := sheet.save_png(batch_path)
	if err == OK:
		print("Hero face search grid saved to: %s" % batch_path)


func _build_attachment_search_variants() -> Array:
	var variants: Array = []
	var base: Dictionary = {}
	var visual := $Player/Visual
	if visual.has_method("get_face_profile"):
		base = visual.get_face_profile()
	var pushes := [
		{"name": "attach_baseline", "profile": {}},
		{"name": "attach_compact", "profile": {"eye_spacing": 0.028, "brow_outer": 0.031, "nose_depth": 0.102, "philtrum_depth": 0.098, "mouth_depth": 0.092, "chin_depth": 0.080, "jaw_width": 0.018}},
		{"name": "attach_soft", "profile": {"cheek_depth": 0.092, "mouth_depth": 0.094, "chin_depth": 0.080, "jaw_depth": 0.076, "jaw_width": 0.020}},
		{"name": "attach_forward_mid", "profile": {"nose_depth": 0.106, "philtrum_depth": 0.101, "mouth_depth": 0.095, "mouth_y": -0.043}},
		{"name": "attach_back_mid", "profile": {"nose_depth": 0.100, "philtrum_depth": 0.096, "mouth_depth": 0.091, "mouth_y": -0.046}},
		{"name": "attach_lower_short", "profile": {"mouth_y": -0.042, "chin_y": -0.062, "chin_depth": 0.079, "jaw_depth": 0.075}},
		{"name": "attach_lower_long", "profile": {"mouth_y": -0.046, "chin_y": -0.070, "chin_depth": 0.084, "jaw_depth": 0.080}},
		{"name": "attach_narrow", "profile": {"eye_spacing": 0.028, "jaw_width": 0.018, "cheek_depth": 0.092}},
		{"name": "attach_wide", "profile": {"eye_spacing": 0.030, "jaw_width": 0.023, "cheek_depth": 0.096}},
		{"name": "attach_eye_lower", "profile": {"eye_y": -0.004, "nose_y": -0.013, "brow_outer": 0.031}},
	]
	for push in pushes:
		var merged: Dictionary = base.duplicate(true)
		for key in push["profile"].keys():
			merged[key] = push["profile"][key]
		variants.append({"name": push["name"], "profile": merged})
	return variants


func _capture_face_attachment_search_batch() -> void:
	var visual := $Player/Visual
	if not visual.has_method("apply_face_profile"):
		return
	var original_index := _variant_index
	var original_profile = {}
	if visual.has_method("get_face_profile"):
		original_profile = visual.get_face_profile()
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var search_variants := _build_attachment_search_variants()
	var paths: Array[String] = []
	for index in range(search_variants.size()):
		visual.apply_face_profile(search_variants[index]["profile"])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var output_path: String = await $Player.capture_face_inspection_sheet()
		if output_path.is_empty():
			continue
		var variant_path := capture_dir.path_join("hero_face_attach_%02d_%s.png" % [index, search_variants[index]["name"]])
		DirAccess.copy_absolute(output_path, variant_path)
		paths.append(variant_path)
	visual.apply_face_profile(original_profile)
	_apply_variant(original_index)
	if paths.is_empty():
		push_warning("Hero face attachment search failed.")
		return
	var images: Array[Image] = []
	for path in paths:
		var image := Image.load_from_file(path)
		if image.is_empty():
			continue
		images.append(image)
	if images.is_empty():
		return
	var frame_width := images[0].get_width()
	var frame_height := images[0].get_height()
	var columns := 2
	var rows := int(ceil(float(images.size()) / float(columns)))
	var sheet := Image.create(frame_width * columns, frame_height * rows, false, images[0].get_format())
	for index in range(images.size()):
		var col := index % columns
		var row := index / columns
		sheet.blit_rect(images[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))
	var batch_path := capture_dir.path_join("hero_face_attachment_grid.png")
	var err := sheet.save_png(batch_path)
	if err == OK:
		print("Hero face attachment grid saved to: %s" % batch_path)


func _build_eye_fit_variants() -> Array:
	var variants: Array = []
	var base: Dictionary = {}
	var visual := $Player/Visual
	if visual.has_method("get_face_profile"):
		base = visual.get_face_profile()
	var pushes := [
		{"name": "eye_baseline", "profile": {}},
		{"name": "eyes_back_1", "profile": {"eye_depth": 0.092, "eye_socket_depth": 0.089}},
		{"name": "eyes_back_2", "profile": {"eye_depth": 0.090, "eye_socket_depth": 0.087}},
		{"name": "eyes_down_back", "profile": {"eye_depth": 0.090, "eye_socket_depth": 0.087, "eye_y": -0.004}},
		{"name": "eyes_narrow_back", "profile": {"eye_depth": 0.090, "eye_socket_depth": 0.087, "eye_spacing": 0.028}},
		{"name": "brow_soft_back", "profile": {"eye_depth": 0.090, "eye_socket_depth": 0.087, "brow_outer": 0.031}},
		{"name": "deep_socket_soft", "profile": {"eye_depth": 0.091, "eye_socket_depth": 0.084, "brow_outer": 0.030}},
	]
	for push in pushes:
		var merged: Dictionary = base.duplicate(true)
		for key in push["profile"].keys():
			merged[key] = push["profile"][key]
		variants.append({"name": push["name"], "profile": merged})
	return variants


func _capture_eye_fit_batch() -> void:
	var visual := $Player/Visual
	if not visual.has_method("apply_face_profile"):
		return
	var original_index := _variant_index
	var original_profile = {}
	if visual.has_method("get_face_profile"):
		original_profile = visual.get_face_profile()
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var search_variants := _build_eye_fit_variants()
	var paths: Array[String] = []
	for index in range(search_variants.size()):
		visual.apply_face_profile(search_variants[index]["profile"])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var output_path: String = await $Player.capture_face_focus_sheet()
		if output_path.is_empty():
			continue
		var variant_path := capture_dir.path_join("hero_face_eye_%02d_%s.png" % [index, search_variants[index]["name"]])
		DirAccess.copy_absolute(output_path, variant_path)
		paths.append(variant_path)
	visual.apply_face_profile(original_profile)
	_apply_variant(original_index)
	if paths.is_empty():
		push_warning("Hero eye-fit batch capture failed.")
		return
	var images: Array[Image] = []
	for path in paths:
		var image := Image.load_from_file(path)
		if image.is_empty():
			continue
		images.append(image)
	if images.is_empty():
		return
	var frame_width := images[0].get_width()
	var frame_height := images[0].get_height()
	var columns := 2
	var rows := int(ceil(float(images.size()) / float(columns)))
	var sheet := Image.create(frame_width * columns, frame_height * rows, false, images[0].get_format())
	for index in range(images.size()):
		var col := index % columns
		var row := index / columns
		sheet.blit_rect(images[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))
	var batch_path := capture_dir.path_join("hero_face_eye_fit_grid.png")
	var err := sheet.save_png(batch_path)
	if err == OK:
		print("Hero eye-fit grid saved to: %s" % batch_path)


func _capture_profile_lab_sheet() -> void:
	var output_path: String = await $Player.capture_face_profile_lab_sheet()
	if output_path.is_empty():
		push_warning("Hero profile lab capture failed.")
		return
	print("Hero profile lab capture saved to: %s" % output_path)


func _capture_face_optimizer_batch() -> void:
	var visual := $Player/Visual
	if not visual.has_method("apply_face_profile"):
		return
	var original_index := _variant_index
	var original_profile = {}
	if visual.has_method("get_face_profile"):
		original_profile = visual.get_face_profile()
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var search_variants := _build_optimizer_variants()
	var captured_variants: Array = []
	for index in range(search_variants.size()):
		visual.apply_face_profile(search_variants[index]["profile"])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var output_path: String = await $Player.capture_face_inspection_sheet()
		if output_path.is_empty():
			continue
		var variant_path := capture_dir.path_join("hero_face_opt_%02d_%s.png" % [index, search_variants[index]["name"]])
		DirAccess.copy_absolute(output_path, variant_path)
		var profile_lab_source: String = await $Player.capture_face_profile_lab_sheet()
		var profile_lab_path := ""
		if not profile_lab_source.is_empty():
			profile_lab_path = capture_dir.path_join("hero_face_opt_%02d_%s_profile.png" % [index, search_variants[index]["name"]])
			DirAccess.copy_absolute(profile_lab_source, profile_lab_path)
		var image_metrics := _analyze_best_candidate_images(variant_path, profile_lab_path)
		var integrity_metrics := _analyze_head_integrity(variant_path, profile_lab_path)
		var combined_score := _blend_optimizer_scores(search_variants[index]["score"], image_metrics.get("image_score", 0.0), integrity_metrics)
		captured_variants.append({
			"name": search_variants[index]["name"],
			"profile": search_variants[index]["profile"],
			"profile_score": search_variants[index]["score"],
			"image_metrics": image_metrics,
			"integrity_metrics": integrity_metrics,
			"combined_score": combined_score,
			"danger_report": search_variants[index].get("danger_report", _get_candidate_danger_report(search_variants[index]["profile"])),
			"path": variant_path,
			"profile_lab_path": profile_lab_path,
		})
	if captured_variants.is_empty():
		visual.apply_face_profile(original_profile)
		_apply_variant(original_index)
		push_warning("Hero face optimizer batch failed.")
		return
	captured_variants.sort_custom(func(a, b): return a["combined_score"] > b["combined_score"])
	var summary_lines := PackedStringArray([
		"Hero Face Optimizer",
		"Build: %s" % BUILD_ID,
		"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
		"",
		"Top candidates:",
	])
	for index in range(captured_variants.size()):
		var integrity: Dictionary = captured_variants[index]["integrity_metrics"]
		summary_lines.append(
			"%02d | combined %.2f | profile %.2f | image %.2f | integrity %.2f | danger %.1f | holes f/p %d/%d | %s" % [
				index,
				captured_variants[index]["combined_score"],
				captured_variants[index]["profile_score"],
				captured_variants[index]["image_metrics"].get("image_score", 0.0),
				integrity.get("integrity_score", 0.0),
				captured_variants[index].get("danger_report", {}).get("danger_score", 0.0),
				integrity.get("front_holes", 0),
				integrity.get("profile_holes", 0),
				JSON.stringify(captured_variants[index]["profile"])
			]
		)
	var images: Array[Image] = []
	for candidate in captured_variants:
		var path: String = candidate["path"]
		var image := Image.load_from_file(path)
		if image.is_empty():
			continue
		images.append(image)
	if images.is_empty():
		return
	var frame_width := images[0].get_width()
	var frame_height := images[0].get_height()
	var columns := 2
	var rows := int(ceil(float(images.size()) / float(columns)))
	var sheet := Image.create(frame_width * columns, frame_height * rows, false, images[0].get_format())
	for index in range(images.size()):
		var col := index % columns
		var row := index / columns
		sheet.blit_rect(images[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))
	var batch_path := capture_dir.path_join("hero_face_optimizer_grid.png")
	var err := sheet.save_png(batch_path)
	if err == OK:
		print("Hero face optimizer grid saved to: %s" % batch_path)
	var summary_path := capture_dir.path_join("hero_face_optimizer_summary.txt")
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(summary_lines))
		file.close()
		print("Hero face optimizer summary saved to: %s" % summary_path)
	var safe_candidates: Array = []
	for candidate in captured_variants:
		if _is_candidate_safe_to_promote(candidate["integrity_metrics"]):
			safe_candidates.append(candidate)
	if not safe_candidates.is_empty():
		var promotable_candidates: Array = []
		for candidate in safe_candidates:
			var comparison := _compare_candidate_to_baseline(candidate)
			candidate["baseline_comparison"] = comparison
			if bool(comparison.get("ok", false)):
				promotable_candidates.append(candidate)
		if promotable_candidates.is_empty():
			var reject_vs_baseline_path := capture_dir.path_join("hero_face_optimizer_rejected_vs_baseline.txt")
			var reject_vs_baseline_lines := PackedStringArray([
				"Hero Face Optimizer Promotion Rejected Against Approved Baseline",
				"Build: %s" % BUILD_ID,
				"",
				"Approved baseline metrics:",
				JSON.stringify(_promoted_baseline_metrics, "\t"),
				"",
				"Candidates rejected after baseline comparison:",
			])
			for candidate in safe_candidates:
				var comparison: Dictionary = candidate.get("baseline_comparison", {})
				reject_vs_baseline_lines.append("%s" % candidate.get("name", "candidate"))
				reject_vs_baseline_lines.append(JSON.stringify(comparison.get("candidate_metrics", {}), "\t"))
				var reasons: PackedStringArray = comparison.get("reasons", PackedStringArray())
				for reason in reasons:
					reject_vs_baseline_lines.append("- %s" % reason)
				reject_vs_baseline_lines.append("")
			var reject_vs_baseline_file := FileAccess.open(reject_vs_baseline_path, FileAccess.WRITE)
			if reject_vs_baseline_file != null:
				reject_vs_baseline_file.store_string("\n".join(reject_vs_baseline_lines))
				reject_vs_baseline_file.close()
				print("Hero face optimizer baseline rejection saved to: %s" % reject_vs_baseline_path)
			_append_face_revision_log("optimizer_rejected_vs_baseline", {
				"approved_baseline_metrics": _promoted_baseline_metrics,
				"candidate_count": safe_candidates.size(),
				"reject_report": reject_vs_baseline_path,
			})
			visual.apply_face_profile(original_profile)
			_apply_variant(original_index)
			return
		promotable_candidates.sort_custom(func(a, b): return a["combined_score"] > b["combined_score"])
		var best_candidate: Dictionary = promotable_candidates[0]
		var best_path := capture_dir.path_join("hero_face_optimizer_best.json")
		var best_file := FileAccess.open(best_path, FileAccess.WRITE)
		if best_file != null:
			best_file.store_string(JSON.stringify(best_candidate["profile"], "\t"))
			best_file.close()
			print("Hero face optimizer best profile saved to: %s" % best_path)
		visual.apply_face_profile(best_candidate["profile"])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var best_sheet_path: String = await $Player.capture_face_inspection_sheet()
		if not best_sheet_path.is_empty():
			var best_sheet_target := capture_dir.path_join("hero_face_optimizer_best_sheet.png")
			DirAccess.copy_absolute(best_sheet_path, best_sheet_target)
			print("Hero face optimizer best sheet saved to: %s" % best_sheet_target)
		var best_profile_path: String = await $Player.capture_face_profile_lab_sheet()
		if not best_profile_path.is_empty():
			var best_profile_target := capture_dir.path_join("hero_face_optimizer_best_profile.png")
			DirAccess.copy_absolute(best_profile_path, best_profile_target)
			print("Hero face optimizer best profile saved to: %s" % best_profile_target)
		var image_metrics := _analyze_best_candidate_images(
			capture_dir.path_join("hero_face_optimizer_best_sheet.png"),
			capture_dir.path_join("hero_face_optimizer_best_profile.png")
		)
		var integrity_metrics := _analyze_head_integrity(
			capture_dir.path_join("hero_face_optimizer_best_sheet.png"),
			capture_dir.path_join("hero_face_optimizer_best_profile.png")
		)
		var promoted_metrics := {
			"combined_score": float(best_candidate.get("combined_score", 0.0)),
			"profile_score": float(best_candidate.get("profile_score", 0.0)),
			"image_score": float(image_metrics.get("image_score", 0.0)),
			"integrity_score": float(integrity_metrics.get("integrity_score", 0.0)),
			"front_holes": int(integrity_metrics.get("front_holes", 99)),
			"profile_holes": int(integrity_metrics.get("profile_holes", 99)),
			"name": str(best_candidate.get("name", "candidate")),
			"saved_at": Time.get_datetime_string_from_system(),
			"build_id": BUILD_ID,
		}
		var post_validation_candidate := {
			"combined_score": promoted_metrics["combined_score"],
			"profile_score": promoted_metrics["profile_score"],
			"image_metrics": image_metrics,
			"integrity_metrics": integrity_metrics,
			"profile": best_candidate["profile"],
			"name": best_candidate.get("name", "candidate"),
		}
		var post_integrity_safe := _is_candidate_safe_to_promote(integrity_metrics)
		var post_baseline_comparison := _compare_candidate_to_baseline(post_validation_candidate)
		if not post_integrity_safe or not bool(post_baseline_comparison.get("ok", false)):
			var post_reject_path := capture_dir.path_join("hero_face_optimizer_post_validation_rejected.txt")
			var post_reject_lines := PackedStringArray([
				"Hero Face Optimizer Post Validation Rejected",
				"Build: %s" % BUILD_ID,
				"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
				"",
				"Candidate name: %s" % str(best_candidate.get("name", "candidate")),
				"Integrity safe: %s" % str(post_integrity_safe),
				"",
				"Post validation metrics:",
				JSON.stringify(promoted_metrics, "\t"),
				"",
				"Baseline comparison:",
				JSON.stringify(post_baseline_comparison.get("candidate_metrics", {}), "\t"),
			])
			for reason in post_baseline_comparison.get("reasons", PackedStringArray()):
				post_reject_lines.append("- %s" % reason)
			var post_reject_file := FileAccess.open(post_reject_path, FileAccess.WRITE)
			if post_reject_file != null:
				post_reject_file.store_string("\n".join(post_reject_lines))
				post_reject_file.close()
				print("Hero face optimizer post validation rejection saved to: %s" % post_reject_path)
			_append_face_revision_log("optimizer_post_validation_rejected", {
				"candidate": str(best_candidate.get("name", "candidate")),
				"post_validation_metrics": promoted_metrics,
				"comparison": post_baseline_comparison,
				"reject_report": post_reject_path,
			})
			visual.apply_face_profile(original_profile)
			_apply_variant(original_index)
			return
		var previous_baseline_profile := _promoted_baseline_profile.duplicate(true)
		var previous_baseline_metrics := _promoted_baseline_metrics.duplicate(true)
		_save_promoted_baseline_profile(best_candidate["profile"])
		_save_promoted_baseline_metrics(promoted_metrics)
		_update_face_shortlist(best_candidate, promoted_metrics)
		_append_face_revision_log("optimizer_promoted", {
			"candidate": str(best_candidate.get("name", "candidate")),
			"previous_baseline_metrics": previous_baseline_metrics,
			"new_baseline_metrics": promoted_metrics,
			"previous_profile": previous_baseline_profile,
			"new_profile": best_candidate["profile"],
			"danger_report": best_candidate.get("danger_report", {}),
		})
		var best_summary_path := capture_dir.path_join("hero_face_optimizer_best_summary.txt")
		var best_summary_lines := PackedStringArray([
			"Hero Face Optimizer Best Candidate",
			"Build: %s" % BUILD_ID,
			"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
			"Combined score: %.2f" % best_candidate["combined_score"],
			"Profile score: %.2f" % best_candidate["profile_score"],
			"Image score: %.2f" % image_metrics.get("image_score", 0.0),
			"Integrity score: %.2f" % integrity_metrics.get("integrity_score", 0.0),
			"",
			"Profile JSON:",
			JSON.stringify(best_candidate["profile"], "\t"),
			"",
			"Image metrics:",
			JSON.stringify(image_metrics, "\t"),
			"",
			"Integrity metrics:",
			JSON.stringify(integrity_metrics, "\t"),
			"",
			"Promoted baseline metrics:",
			JSON.stringify(promoted_metrics, "\t"),
			"",
			"Best sheet:",
			capture_dir.path_join("hero_face_optimizer_best_sheet.png"),
			"",
			"Best profile lab:",
			capture_dir.path_join("hero_face_optimizer_best_profile.png"),
		])
		var best_summary_file := FileAccess.open(best_summary_path, FileAccess.WRITE)
		if best_summary_file != null:
			best_summary_file.store_string("\n".join(best_summary_lines))
			best_summary_file.close()
			print("Hero face optimizer best summary saved to: %s" % best_summary_path)
	else:
		var reject_path := capture_dir.path_join("hero_face_optimizer_rejected.txt")
		var reject_lines := PackedStringArray([
			"Hero Face Optimizer Promotion Rejected",
			"Build: %s" % BUILD_ID,
			"Reason: no candidate met integrity thresholds",
			"Threshold integrity >= %.2f and holes <= %d" % [MIN_PROMOTION_INTEGRITY_SCORE, MAX_PROMOTION_HOLES],
		])
		var reject_file := FileAccess.open(reject_path, FileAccess.WRITE)
		if reject_file != null:
			reject_file.store_string("\n".join(reject_lines))
			reject_file.close()
			print("Hero face optimizer rejected promotion saved to: %s" % reject_path)
		_append_face_revision_log("optimizer_rejected_thresholds", {
			"candidate_count": captured_variants.size(),
			"reject_report": reject_path,
		})
	visual.apply_face_profile(original_profile)
	_apply_variant(original_index)


func _blend_optimizer_scores(profile_score: float, image_score: float, integrity_metrics: Dictionary = {}) -> float:
	var integrity_score := float(integrity_metrics.get("integrity_score", 100.0))
	var front_holes := int(integrity_metrics.get("front_holes", 0))
	var profile_holes := int(integrity_metrics.get("profile_holes", 0))
	var face_fill := float(integrity_metrics.get("face_fill", 0.0))
	var total := profile_score * 0.46 + image_score * 0.34 + integrity_score * 0.20
	if front_holes > 0 or profile_holes > 0:
		total -= 60.0
	if face_fill < 0.002:
		total -= 20.0
	return total


func _analyze_optimizer_sheet(sheet_path: String) -> Dictionary:
	var metrics := {
		"image_score": 0.0,
		"front_fill": 0.0,
		"front_symmetry": 0.0,
		"profile_projection": 0.0,
	}
	var sheet := Image.load_from_file(sheet_path)
	if sheet.is_empty():
		return metrics
	var front_rect := Rect2i(340, 0, 340, 340)
	var profile_rect := Rect2i(680, 340, 340, 340)
	var front_crop := Image.create(front_rect.size.x, front_rect.size.y, false, sheet.get_format())
	front_crop.blit_rect(sheet, front_rect, Vector2i.ZERO)
	var profile_crop := Image.create(profile_rect.size.x, profile_rect.size.y, false, sheet.get_format())
	profile_crop.blit_rect(sheet, profile_rect, Vector2i.ZERO)
	var front_bg := front_crop.get_pixel(0, 0)
	var profile_bg := profile_crop.get_pixel(0, 0)
	var front_bounds := _find_foreground_bounds(front_crop, front_bg, 0.045)
	var profile_bounds := _find_foreground_bounds(profile_crop, profile_bg, 0.045)
	if front_bounds.size.x > 0 and front_bounds.size.y > 0:
		var front_area := float(front_bounds.size.x * front_bounds.size.y)
		metrics["front_fill"] = front_area / float(front_crop.get_width() * front_crop.get_height())
		metrics["front_symmetry"] = _estimate_horizontal_symmetry(front_crop, front_bounds, front_bg, 0.045)
	if profile_bounds.size.x > 0 and profile_bounds.size.y > 0:
		var profile_center_y := profile_bounds.position.y + profile_bounds.size.y / 2
		var mid_x := profile_bounds.position.x + profile_bounds.size.x / 2
		metrics["profile_projection"] = _estimate_profile_projection(profile_crop, profile_bg, profile_center_y, mid_x, 0.045)
	metrics["image_score"] = (
		float(metrics["front_fill"]) * 28.0 +
		float(metrics["front_symmetry"]) * 36.0 +
		float(metrics["profile_projection"]) * 36.0
	)
	return metrics


func _analyze_best_candidate_images(sheet_path: String, profile_path: String) -> Dictionary:
	var metrics := {
		"image_score": 0.0,
		"front_fill": 0.0,
		"front_symmetry": 0.0,
		"profile_projection": 0.0,
		"profile_roundness": 0.0,
	}
	var sheet := Image.load_from_file(sheet_path)
	var profile := Image.load_from_file(profile_path)
	if sheet.is_empty() or profile.is_empty():
		return metrics

	var front_rect := Rect2i(340, 0, 340, 340)
	var front_crop := Image.create(front_rect.size.x, front_rect.size.y, false, sheet.get_format())
	front_crop.blit_rect(sheet, front_rect, Vector2i.ZERO)
	var side_rect := Rect2i(260, 0, 260, 260)
	var side_crop := Image.create(side_rect.size.x, side_rect.size.y, false, profile.get_format())
	side_crop.blit_rect(profile, side_rect, Vector2i.ZERO)

	var front_bg := front_crop.get_pixel(0, 0)
	var side_bg := side_crop.get_pixel(0, 0)
	var front_bounds := _find_foreground_bounds(front_crop, front_bg, 0.045)
	var side_bounds := _find_foreground_bounds(side_crop, side_bg, 0.045)

	if front_bounds.size.x > 0 and front_bounds.size.y > 0:
		var front_area := float(front_bounds.size.x * front_bounds.size.y)
		metrics["front_fill"] = front_area / float(front_crop.get_width() * front_crop.get_height())
		metrics["front_symmetry"] = _estimate_horizontal_symmetry(front_crop, front_bounds, front_bg, 0.045)

	if side_bounds.size.x > 0 and side_bounds.size.y > 0:
		var side_center_y := side_bounds.position.y + side_bounds.size.y / 2
		var mid_x := side_bounds.position.x + side_bounds.size.x / 2
		metrics["profile_projection"] = _estimate_profile_projection(side_crop, side_bg, side_center_y, mid_x, 0.045)
		metrics["profile_roundness"] = _estimate_profile_roundness(side_crop, side_bounds, side_bg, 0.045)

	metrics["image_score"] = (
		float(metrics["front_fill"]) * 20.0 +
		float(metrics["front_symmetry"]) * 30.0 +
		float(metrics["profile_projection"]) * 25.0 +
		float(metrics["profile_roundness"]) * 25.0
	)
	return metrics


func _analyze_head_integrity(sheet_path: String, profile_path: String) -> Dictionary:
	var metrics := {
		"integrity_score": 0.0,
		"front_holes": 0,
		"profile_holes": 0,
		"front_fill": 0.0,
		"profile_fill": 0.0,
		"face_fill": 0.0,
	}
	var sheet := Image.load_from_file(sheet_path)
	var profile := Image.load_from_file(profile_path)
	if sheet.is_empty() or profile.is_empty():
		return metrics

	var front_rect := Rect2i(340, 0, 340, 340)
	var front_crop := Image.create(front_rect.size.x, front_rect.size.y, false, sheet.get_format())
	front_crop.blit_rect(sheet, front_rect, Vector2i.ZERO)
	var side_rect := Rect2i(260, 0, 260, 260)
	var side_crop := Image.create(side_rect.size.x, side_rect.size.y, false, profile.get_format())
	side_crop.blit_rect(profile, side_rect, Vector2i.ZERO)

	var front_bg := front_crop.get_pixel(0, 0)
	var side_bg := side_crop.get_pixel(0, 0)
	var front_bounds := _find_foreground_bounds(front_crop, front_bg, 0.045)
	var side_bounds := _find_foreground_bounds(side_crop, side_bg, 0.045)
	if front_bounds.size.x > 0 and front_bounds.size.y > 0:
		metrics["front_fill"] = float(front_bounds.size.x * front_bounds.size.y) / float(front_crop.get_width() * front_crop.get_height())
		metrics["front_holes"] = _count_enclosed_background_regions(front_crop, front_bounds, front_bg, 0.045, 120)
		metrics["face_fill"] = _estimate_feature_presence(front_crop, front_bg, 0.045)
	if side_bounds.size.x > 0 and side_bounds.size.y > 0:
		metrics["profile_fill"] = float(side_bounds.size.x * side_bounds.size.y) / float(side_crop.get_width() * side_crop.get_height())
		metrics["profile_holes"] = _count_enclosed_background_regions(side_crop, side_bounds, side_bg, 0.045, 80)
	var score := 100.0
	score -= float(metrics["front_holes"]) * 35.0
	score -= float(metrics["profile_holes"]) * 25.0
	if float(metrics["front_fill"]) < 0.10:
		score -= 18.0
	if float(metrics["profile_fill"]) < 0.18:
		score -= 12.0
	if float(metrics["face_fill"]) < 0.012:
		score -= 24.0
	metrics["integrity_score"] = maxf(score, 0.0)
	return metrics


func _count_enclosed_background_regions(image: Image, bounds: Rect2i, bg: Color, threshold: float, min_area: int) -> int:
	if bounds.size.x <= 8 or bounds.size.y <= 8:
		return 0
	var rows_with_gaps := 0
	var min_gap_width := maxi(4, int(sqrt(float(min_area)) * 0.45))
	for y in range(bounds.position.y + 2, bounds.position.y + bounds.size.y - 2):
		var left_fg := -1
		var right_fg := -1
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			if _color_distance(image.get_pixel(x, y), bg) > threshold:
				left_fg = x
				break
		for x in range(bounds.position.x + bounds.size.x - 1, bounds.position.x - 1, -1):
			if _color_distance(image.get_pixel(x, y), bg) > threshold:
				right_fg = x
				break
		if left_fg == -1 or right_fg == -1 or right_fg - left_fg < min_gap_width * 2:
			continue
		var gap_len := 0
		var found_gap := false
		for x in range(left_fg + 1, right_fg):
			var fg := _color_distance(image.get_pixel(x, y), bg) > threshold
			if not fg:
				gap_len += 1
			elif gap_len >= min_gap_width:
				found_gap = true
				break
			else:
				gap_len = 0
		if gap_len >= min_gap_width:
			found_gap = true
		if found_gap:
			rows_with_gaps += 1
	return 1 if rows_with_gaps >= 6 else 0


func _estimate_feature_presence(image: Image, bg: Color, threshold: float) -> float:
	var center_x := image.get_width() / 2
	var center_y := image.get_height() / 2
	var rect := Rect2i(center_x - 42, center_y - 18, 84, 96)
	var hits := 0
	var total := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		if y < 0 or y >= image.get_height():
			continue
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or x >= image.get_width():
				continue
			total += 1
			var px := image.get_pixel(x, y)
			if _color_distance(px, bg) > threshold and px.get_luminance() < 0.72:
				hits += 1
	if total == 0:
		return 0.0
	return float(hits) / float(total)


func _capture_head_integrity_audit() -> void:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var audit_path := capture_dir.path_join("hero_head_integrity_audit.txt")
	var breadcrumb_file := FileAccess.open(audit_path, FileAccess.WRITE)
	if breadcrumb_file != null:
		breadcrumb_file.store_string("\n".join([
			"Hero Head Integrity Audit",
			"Build: %s" % BUILD_ID,
			"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
			"Started: %s" % Time.get_datetime_string_from_system(),
			"Status: resolving capture sources",
		]))
		breadcrumb_file.close()
	var sheet_path := _get_cached_face_sheet_path()
	var profile_path := _get_cached_profile_lab_path()
	var using_cached_sheet := FileAccess.file_exists(sheet_path)
	var using_cached_profile := FileAccess.file_exists(profile_path)
	if not using_cached_sheet:
		sheet_path = await $Player.capture_face_inspection_sheet()
	breadcrumb_file = FileAccess.open(audit_path, FileAccess.WRITE)
	if breadcrumb_file != null:
		breadcrumb_file.store_string("\n".join([
			"Hero Head Integrity Audit",
			"Build: %s" % BUILD_ID,
			"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
			"Started: %s" % Time.get_datetime_string_from_system(),
			"Status: resolving profile source",
			"Sheet source: %s" % ("cached" if using_cached_sheet else "fresh"),
			"Sheet capture: %s" % sheet_path,
		]))
		breadcrumb_file.close()
	if not using_cached_profile:
		profile_path = await $Player.capture_face_profile_lab_sheet()
	if sheet_path.is_empty() or profile_path.is_empty():
		push_warning("Head integrity audit failed.")
		return
	var metrics := _analyze_head_integrity(sheet_path, profile_path)
	var lines := PackedStringArray([
		"Hero Head Integrity Audit",
		"Build: %s" % BUILD_ID,
		"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
		"Finished: %s" % Time.get_datetime_string_from_system(),
		"Status: complete",
		"Sheet source: %s" % ("cached" if using_cached_sheet else "fresh"),
		"Profile source: %s" % ("cached" if using_cached_profile else "fresh"),
		"",
		JSON.stringify(metrics, "\t"),
		"",
		"Sheet:",
		sheet_path,
		"",
		"Profile:",
		profile_path,
	])
	var file := FileAccess.open(audit_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()
	print("Hero head integrity audit saved to: %s" % audit_path)


func _find_foreground_bounds(image: Image, bg: Color, threshold: float) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if _color_distance(image.get_pixel(x, y), bg) > threshold:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _estimate_horizontal_symmetry(image: Image, bounds: Rect2i, bg: Color, threshold: float) -> float:
	var samples := 0
	var matches := 0
	var center_x := bounds.position.x + bounds.size.x / 2
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for offset in range(bounds.size.x / 2):
			var left_x := center_x - offset - 1
			var right_x := center_x + offset
			if left_x < bounds.position.x or right_x >= bounds.position.x + bounds.size.x:
				continue
			var left_fg := _color_distance(image.get_pixel(left_x, y), bg) > threshold
			var right_fg := _color_distance(image.get_pixel(right_x, y), bg) > threshold
			samples += 1
			if left_fg == right_fg:
				matches += 1
	if samples == 0:
		return 0.0
	return float(matches) / float(samples)


func _estimate_profile_projection(image: Image, bg: Color, row_y: int, mid_x: int, threshold: float) -> float:
	var front_x := -1
	var back_x := -1
	var y := clampi(row_y, 0, image.get_height() - 1)
	for x in range(image.get_width()):
		if _color_distance(image.get_pixel(x, y), bg) > threshold:
			back_x = x
			break
	for x in range(image.get_width() - 1, -1, -1):
		if _color_distance(image.get_pixel(x, y), bg) > threshold:
			front_x = x
			break
	if front_x == -1 or back_x == -1 or front_x <= back_x:
		return 0.0
	var full_span := float(front_x - back_x)
	var front_span := float(front_x - mid_x)
	return clampf(front_span / maxf(full_span, 1.0), 0.0, 1.0)


func _estimate_profile_roundness(image: Image, bounds: Rect2i, bg: Color, threshold: float) -> float:
	var rows := [
		bounds.position.y + int(bounds.size.y * 0.18),
		bounds.position.y + int(bounds.size.y * 0.32),
		bounds.position.y + int(bounds.size.y * 0.46),
	]
	var xs: Array[float] = []
	for row in rows:
		var x_hit := -1
		for x in range(bounds.position.x + bounds.size.x - 1, bounds.position.x - 1, -1):
			if _color_distance(image.get_pixel(x, row), bg) > threshold:
				x_hit = x
				break
		if x_hit != -1:
			xs.append(float(x_hit))
	if xs.size() < 3:
		return 0.0
	var delta_a := absf(xs[0] - xs[1])
	var delta_b := absf(xs[1] - xs[2])
	return 1.0 - clampf((delta_a + delta_b) / 36.0, 0.0, 1.0)


func _color_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _capture_face_review_pack() -> void:
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var review_paths: Array[String] = []

	await _capture_hero_face_sheet()
	review_paths.append(capture_dir.path_join("hero_face_sheet.png"))

	await _capture_profile_lab_sheet()
	review_paths.append(capture_dir.path_join("hero_face_profile_lab.png"))

	await _capture_eye_fit_batch()
	review_paths.append(capture_dir.path_join("hero_face_eye_fit_grid.png"))

	await _capture_face_attachment_search_batch()
	review_paths.append(capture_dir.path_join("hero_face_attachment_grid.png"))

	await _capture_face_search_batch()
	review_paths.append(capture_dir.path_join("hero_face_search_grid.png"))

	await _capture_face_optimizer_batch()
	review_paths.append(capture_dir.path_join("hero_face_optimizer_grid.png"))

	var summary_path := capture_dir.path_join("hero_face_review_pack.txt")
	var summary_lines := PackedStringArray([
		"Hero Face Review Pack",
		"Build: %s" % BUILD_ID,
		"Variant: %s" % FACE_VARIANTS[_variant_index]["name"],
		"",
		"Tight sheet:",
		review_paths[0],
		"",
		"Profile lab:",
		review_paths[1],
		"",
		"Eye fit grid:",
		review_paths[2],
		"",
		"Attachment grid:",
		review_paths[3],
		"",
		"Search grid:",
		review_paths[4],
		"",
		"Optimizer grid:",
		review_paths[5],
	])
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(summary_lines))
		file.close()
	print("Hero face review pack saved to: %s" % summary_path)


func _restore_window_title() -> void:
	DisplayServer.window_set_title("Hero Lab - %s" % BUILD_ID)


func _handle_startup_capture_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return

	var should_capture_sheet := args.has("--capture-face-sheet")
	var should_capture_batch := args.has("--capture-face-batch")
	var should_capture_search := args.has("--capture-face-search")
	var should_capture_attachment := args.has("--capture-face-attachment")
	var should_capture_eye_fit := args.has("--capture-eye-fit")
	var should_capture_profile_lab := args.has("--capture-profile-lab")
	var should_capture_review_pack := args.has("--capture-face-review-pack")
	var should_capture_optimizer := args.has("--capture-face-optimize")
	var should_capture_head_audit := args.has("--capture-head-audit")
	var should_quit := args.has("--quit-after-capture")
	var requested_variant := ""

	for arg in args:
		if arg.begins_with("--variant="):
			requested_variant = arg.trim_prefix("--variant=")
			break

	if not requested_variant.is_empty():
		for index in range(FACE_VARIANTS.size()):
			if FACE_VARIANTS[index]["name"] == requested_variant:
				_apply_variant(index)
				break

	if not should_capture_sheet and not should_capture_batch and not should_capture_search and not should_capture_attachment and not should_capture_eye_fit and not should_capture_profile_lab and not should_capture_review_pack and not should_capture_optimizer and not should_capture_head_audit:
		return

	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if should_capture_review_pack:
		await _capture_face_review_pack()
	elif should_capture_head_audit:
		await _capture_head_integrity_audit()
	elif should_capture_optimizer:
		await _capture_face_optimizer_batch()
	elif should_capture_profile_lab:
		await _capture_profile_lab_sheet()
	elif should_capture_eye_fit:
		await _capture_eye_fit_batch()
	elif should_capture_attachment:
		await _capture_face_attachment_search_batch()
	elif should_capture_search:
		await _capture_face_search_batch()
	elif should_capture_batch:
		await _capture_face_variant_batch()
	elif should_capture_sheet:
		await _capture_hero_face_sheet()

	if should_quit:
		get_tree().quit()
