extends SceneTree


func _initialize()->void:
	call_deferred("_run")


func _run()->void:
	# Load the exact runtime HeroVisual and imported gameplay GLB, but avoid
	# instantiating Main.tscn and the entire world for a character close-up.
	var stage:=Node3D.new()
	root.add_child(stage)
	var environment:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(.010,.014,.024)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(.43,.49,.62)
	env.ambient_light_energy=.76
	environment.environment=env
	stage.add_child(environment)
	var key:=DirectionalLight3D.new()
	key.rotation=Vector3(-.72,-.58,0)
	key.light_color=Color(1.0,.82,.66)
	key.light_energy=1.55
	key.shadow_enabled=true
	stage.add_child(key)
	var rim:=OmniLight3D.new()
	rim.position=Vector3(-2.0,2.7,-1.8)
	rim.light_color=Color(.30,.44,1.0)
	rim.light_energy=2.7
	rim.omni_range=6.0
	stage.add_child(rim)
	var visual:=Node3D.new()
	visual.name="ActualGameplayArmorInspection"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	stage.add_child(visual)
	for index in range(12):await process_frame
	visual.call("set_equipment_pieces",{
		"head":{"id":"royal_helmet"},
		"chest":{"id":"royal_chestplate"},
		"shoulders":{"id":"royal_shoulders"},
		"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},
		"pants":{"id":"royal_legguards"},
		"mainhand":{},"offhand":{}
	})
	visual.call("set_move_blend",0.0)
	visual.call("set_movement_speed",0.0)
	for index in range(10):await process_frame
	var camera:=Camera3D.new()
	camera.current=true
	camera.fov=38.0
	stage.add_child(camera)
	camera.position=Vector3(.48,1.56,1.72)
	camera.look_at(Vector3(0,1.38,0),Vector3.UP)
	for index in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var output:=ProjectSettings.globalize_path("res://artifacts/actual_armor_closeup.png")
	var error:=root.get_texture().get_image().save_png(output)
	print("ACTUAL_ARMOR_CLOSEUP|%s|error=%s"%[output,error])
	camera.position=Vector3(-.48,1.56,-1.72)
	camera.look_at(Vector3(0,1.38,0),Vector3.UP)
	for index in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var opposite:=ProjectSettings.globalize_path("res://artifacts/actual_armor_opposite.png")
	var opposite_error:=root.get_texture().get_image().save_png(opposite)
	print("ACTUAL_ARMOR_OPPOSITE|%s|error=%s"%[opposite,opposite_error])
	quit(0 if error==OK and opposite_error==OK else 2)
