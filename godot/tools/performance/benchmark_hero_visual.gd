extends SceneTree

const WARMUP:=60
const SAMPLES:=300

func _initialize()->void:call_deferred("_run")

func _run()->void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var visual:=Node3D.new()
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	await process_frame;await process_frame
	visual.call("set_equipment_pieces",{"head":{"id":"royal_helm"},"chest":{"id":"royal_plate"},"shoulders":{"id":"royal_shoulders"},"hands":{"id":"royal_gauntlets"},"feet":{"id":"royal_boots"},"pants":{"id":"royal_pants"},"mainhand":{"id":"royal_vanguard_sword"},"offhand":{"id":"royal_vanguard_shield"}})
	visual.call("set_move_blend",1.0);visual.call("set_movement_speed",5.2)
	for index in WARMUP:await process_frame
	var samples:Array[float]=[]
	for index in SAMPLES:
		var start:=Time.get_ticks_usec();await process_frame
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	samples.sort()
	var average:float=float(samples.reduce(func(total,value):return total+value,0.0))/float(samples.size())
	var p95:float=samples[roundi((samples.size()-1)*.95)]
	var p99:float=samples[roundi((samples.size()-1)*.99)]
	print("HERO_RUNTIME_BENCHMARK|frames=%d|average_ms=%.3f|p95_ms=%.3f|p99_ms=%.3f|nodes=%d|objects=%d"%[SAMPLES,average,p95,p99,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	visual.free();quit()
