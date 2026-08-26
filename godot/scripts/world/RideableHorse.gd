extends Node3D

@export var horse_name := "Riverwatch Courser"

var _animation_player: AnimationPlayer
var _mounted := false
var _current_animation: StringName = &""
var _jumping := false
var _last_speed := 0.0


func _ready() -> void:
	_animation_player = _find_animation_player(self)
	_configure_animation_loops()
	_play_animation(&"Idle", 0.0)


func set_mounted_state(enabled: bool) -> void:
	_mounted = enabled
	set_meta("mounted", enabled)
	if not enabled:
		_jumping = false
		_last_speed = 0.0
		_play_animation(&"Idle", 0.16)


func set_travel_speed(speed: float) -> void:
	_last_speed = speed
	if not _mounted:
		return
	if _jumping:
		return
	if speed >= 17.0:
		_play_animation(&"Trot", 0.14)
		if is_instance_valid(_animation_player):
			_animation_player.speed_scale = clampf(speed / 15.5, 1.0, 1.65)
	elif speed > 0.35:
		_play_animation(&"Walk", 0.16)
		if is_instance_valid(_animation_player):
			_animation_player.speed_scale = clampf(speed / 10.5, 0.85, 1.50)
	else:
		_play_animation(&"Idle", 0.20)
		if is_instance_valid(_animation_player):
			_animation_player.speed_scale = 1.0


func play_jump() -> void:
	if not _mounted:
		return
	_jumping = true
	_play_animation(&"Jump", 0.08)
	if is_instance_valid(_animation_player):
		_animation_player.speed_scale = 1.0


func play_land() -> void:
	if not _jumping:
		return
	_jumping = false
	_current_animation = &""
	set_travel_speed(_last_speed)


func _play_animation(short_name: StringName, blend: float) -> void:
	if not is_instance_valid(_animation_player):
		return
	var resolved := _resolve_animation(short_name)
	if resolved == &"" or (resolved == _current_animation and _animation_player.is_playing()):
		return
	_animation_player.play(resolved, blend)
	_current_animation = resolved


func _configure_animation_loops()->void:
	if not is_instance_valid(_animation_player):return
	for short_name in [&"Idle",&"Walk",&"Trot"]:
		var resolved:=_resolve_animation(short_name)
		if resolved!=&"":_animation_player.get_animation(resolved).loop_mode=Animation.LOOP_LINEAR
	var jump_resolved:=_resolve_animation(&"Jump")
	if jump_resolved!=&"":_animation_player.get_animation(jump_resolved).loop_mode=Animation.LOOP_NONE


func _resolve_animation(short_name: StringName) -> StringName:
	if not is_instance_valid(_animation_player):
		return &""
	if _animation_player.has_animation(short_name):
		return short_name
	for candidate in _animation_player.get_animation_list():
		var text := str(candidate)
		if text.get_slice("/", text.get_slice_count("/") - 1) == str(short_name):
			return candidate
		if text.ends_with("|" + str(short_name)):
			return candidate
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
