extends Node3D

@export var horse_name := "Riverwatch Courser"

var _animation_player: AnimationPlayer
var _mounted := false
var _current_animation: StringName = &""


func _ready() -> void:
	_animation_player = _find_animation_player(self)
	_configure_animation_loops()
	_play_animation(&"Idle", 0.0)


func set_mounted_state(enabled: bool) -> void:
	_mounted = enabled
	set_meta("mounted", enabled)
	if not enabled:
		_play_animation(&"Idle", 0.16)


func set_travel_speed(speed: float) -> void:
	if not _mounted:
		return
	if speed > 0.35:
		_play_animation(&"Trot", 0.14)
		if is_instance_valid(_animation_player):
			_animation_player.speed_scale = clampf(speed / 8.0, 1.15, 2.35)
	else:
		_play_animation(&"Idle", 0.20)
		if is_instance_valid(_animation_player):
			_animation_player.speed_scale = 1.0


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
	for short_name in [&"Idle",&"Trot"]:
		var resolved:=_resolve_animation(short_name)
		if resolved!=&"":_animation_player.get_animation(resolved).loop_mode=Animation.LOOP_LINEAR


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
