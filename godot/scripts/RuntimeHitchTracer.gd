extends Node


const HITCH_MS := 40.0
const SUMMARY_SECONDS := 5.0

var _enabled := false
var _elapsed := 0.0
var _moving_elapsed := 0.0
var _moving_frames := 0
var _moving_hitches := 0
var _worst_ms := 0.0
var _player: CharacterBody3D
var _last_tick_usec := 0
var _last_player_position := Vector3.ZERO


func _ready() -> void:
    _enabled = OS.get_environment("BROKEN_KNIGHT_HITCH_TRACE") == "1"
    if not _enabled:
        process_mode = Node.PROCESS_MODE_DISABLED
        return
    process_priority = 10000
    _player = get_parent().get_node_or_null("Player") as CharacterBody3D
    _last_tick_usec = Time.get_ticks_usec()
    if is_instance_valid(_player):
        _last_player_position = _player.global_position
    print("RUNTIME_TRACE|started|hero_mode=%s" % OS.get_environment("BROKEN_KNIGHT_HERO_DIAGNOSTIC"))


func _process(delta: float) -> void:
    var now_usec := Time.get_ticks_usec()
    var frame_ms := float(now_usec - _last_tick_usec) / 1000.0
    _last_tick_usec = now_usec
    var position := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
    var distance_moved := Vector2(position.x - _last_player_position.x, position.z - _last_player_position.z).length()
    var moving := distance_moved > 0.001
    _last_player_position = position
    _elapsed += frame_ms / 1000.0
    if moving:
        _moving_elapsed += frame_ms / 1000.0
        _moving_frames += 1
        _worst_ms = maxf(_worst_ms, frame_ms)
        if frame_ms >= HITCH_MS:
            _moving_hitches += 1
            print("RUNTIME_HITCH|ms=%.2f|x=%.2f|y=%.2f|z=%.2f|speed=%.2f|nodes=%d|objects=%d|draw_calls=%d|memory_mb=%.1f" % [
                frame_ms,
                _player.global_position.x,
                _player.global_position.y,
                _player.global_position.z,
                distance_moved / maxf(frame_ms / 1000.0, 0.0001),
                int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
                int(Performance.get_monitor(Performance.OBJECT_COUNT)),
                int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
                float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
            ])
    if _elapsed >= SUMMARY_SECONDS:
        print("RUNTIME_TRACE|seconds=%.1f|moving_frames=%d|moving_hitches=%d|worst_ms=%.2f|x=%.2f|y=%.2f|z=%.2f|fps=%.1f|nodes=%d|draw_calls=%d|up=%s|w=%s|input=%s|velocity=%.2f" % [
            _moving_elapsed,
            _moving_frames,
            _moving_hitches,
            _worst_ms,
            position.x,
            position.y,
            position.z,
            Engine.get_frames_per_second(),
            int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
            int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
            Input.is_key_pressed(KEY_UP),
            Input.is_key_pressed(KEY_W),
            bool(_player.get("_input_enabled")) if is_instance_valid(_player) else false,
            Vector2(_player.velocity.x,_player.velocity.z).length() if is_instance_valid(_player) else 0.0,
        ])
        _elapsed = 0.0
        _moving_elapsed = 0.0
        _moving_frames = 0
        _moving_hitches = 0
        _worst_ms = 0.0
