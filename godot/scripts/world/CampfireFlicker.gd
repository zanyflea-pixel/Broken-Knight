extends OmniLight3D

@export var base_energy:float=1.4
var _time:float=0.0
var _phase:float=0.0
var _tick_accumulator:=0.0


func _ready()->void:
    _phase=absf(global_position.x*.073+global_position.z*.119)


func _process(delta:float)->void:
    _tick_accumulator+=delta
    if _tick_accumulator<.05:return
    _time+=_tick_accumulator
    _tick_accumulator=0.0
    var flicker:=sin(_time*7.1+_phase)*.13+sin(_time*12.7+_phase*.7)*.07
    light_energy=base_energy+flicker
