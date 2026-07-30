extends Node3D

@export var turn_speed: float = 0.12


func _process(delta: float) -> void:
    rotation.z = fmod(rotation.z + turn_speed * delta, TAU)
