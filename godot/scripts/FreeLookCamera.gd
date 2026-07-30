extends Camera3D

@export var move_speed := 28.0
@export var sprint_speed := 65.0
@export var look_sensitivity := 0.0035

var _yaw := 0.0
var _pitch := -0.36
var _mouse_captured := true


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    _yaw = rotation.y
    _pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and _mouse_captured:
        _yaw -= event.relative.x * look_sensitivity
        _pitch -= event.relative.y * look_sensitivity
        _pitch = clamp(_pitch, -1.2, 0.35)
        rotation = Vector3(_pitch, _yaw, 0.0)
    elif event.is_action_pressed("ui_cancel"):
        _mouse_captured = not _mouse_captured
        Input.set_mouse_mode(
            Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
        )


func _process(delta: float) -> void:
    var input_dir := Vector3.ZERO

    if Input.is_key_pressed(KEY_W):
        input_dir -= transform.basis.z
    if Input.is_key_pressed(KEY_S):
        input_dir += transform.basis.z
    if Input.is_key_pressed(KEY_A):
        input_dir -= transform.basis.x
    if Input.is_key_pressed(KEY_D):
        input_dir += transform.basis.x
    if Input.is_key_pressed(KEY_Q):
        input_dir.y -= 1.0
    if Input.is_key_pressed(KEY_E):
        input_dir.y += 1.0

    if input_dir.length_squared() <= 0.0001:
        return

    input_dir = input_dir.normalized()
    var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
    global_position += input_dir * speed * delta
