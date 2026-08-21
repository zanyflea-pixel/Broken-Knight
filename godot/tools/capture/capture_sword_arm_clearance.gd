extends SceneTree


var stage:Node3D
var visual:Node3D
var camera:Camera3D
var player:AnimationPlayer


func _initialize()->void:
	call_deferred("_run")


func _setup_stage()->void:
	stage=Node3D.new()
	root.add_child(stage)
	var world_environment:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(.010,.014,.024)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color(.44,.50,.62)
	environment.ambient_light_energy=.90
	world_environment.environment=environment
	stage.add_child(world_environment)
	var key:=DirectionalLight3D.new()
	key.rotation=Vector3(-.70,.55,0)
	key.light_color=Color(1.0,.84,.70)
	key.light_energy=1.75
	stage.add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation=Vector3(-.25,-.80,0)
	fill.light_color=Color(.34,.50,1.0)
	fill.light_energy=.72
	stage.add_child(fill)
	camera=Camera3D.new()
	camera.current=true
	camera.fov=42
	camera.position=Vector3(-1.35,1.38,2.15)
	stage.add_child(camera)
	camera.look_at(Vector3(-.36,1.14,0),Vector3.UP)


func _armor()->Dictionary:
	return {
		"head":{"id":"royal_helm"},
		"chest":{"id":"royal_plate"},
		"shoulders":{"id":"royal_shoulders"},
		"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},
		"pants":{"id":"royal_pants"},
		"mainhand":{"id":"royal_vanguard_sword"},
		"offhand":{},
	}


func _capture(name:String)->void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://artifacts/%s.png"%name
	var error:=root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SWORD_ARM_CAPTURE|%s|error=%s"%[path,error])


func _pose_sword(time:float)->void:
	var duration:=player.get_animation(&"SwordSlash").length
	player.play(&"SwordSlash")
	player.seek(time,true)
	player.speed_scale=0.0
	visual.set("_action_animation_state",&"SwordSlash")
	visual.set("_current_imported_animation",&"SwordSlash")
	visual.set("_action_kind","sword")
	visual.set("_action_time",maxf(.001,duration-time))
	visual.call("_apply_leg_proportion_correction")
	visual.call("_update_warrior_weapon_action")
	await process_frame


func _run()->void:
	_setup_stage()
	visual=Node3D.new()
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	stage.add_child(visual)
	for index in range(10):
		await process_frame
	player=visual.get("_imported_animation_player")
	visual.call("set_equipment_pieces",_armor())
	visual.call("set_move_blend",0.0)
	visual.call("set_movement_speed",0.0)
	for index in range(8):
		await process_frame
	await _capture("sword_arm_idle_clearance")
	await _pose_sword(.30)
	await _capture("sword_arm_attack_clearance")
	quit(0)
