extends SceneTree

func _initialize() -> void: call_deferred("run_capture")

func run_capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.018, .022, .032)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.54, .57, .66)
	env.ambient_light_energy = .72
	environment.environment = env
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-.72, -.58, 0)
	key.light_color = Color(1.0, .84, .72)
	key.light_energy = 1.65
	stage.add_child(key)
	var visual := Node3D.new()
	visual.name = "FullContinuousHeroInspection"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	stage.add_child(visual)
	for index in range(12): await process_frame
	visual.call("set_equipment_pieces", {})
	visual.call("set_move_blend", 0.0)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 42
	camera.position = Vector3(2.25, 1.58, 3.40)
	stage.add_child(camera)
	camera.look_at(Vector3(0, .98, 0), Vector3.UP)
	for index in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/full_continuous_hero_ingame.png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("FULL_CONTINUOUS_HERO_CAPTURE|%s" % path)
	camera.position = Vector3(.62, 1.72, 1.05)
	camera.fov = 34
	camera.look_at(Vector3(0, 1.66, 0), Vector3.UP)
	for index in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var face_path := "res://artifacts/full_continuous_hero_face_ingame.png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(face_path))
	print("FULL_CONTINUOUS_HERO_CAPTURE|%s" % face_path)
	visual.call("set_move_blend", 1.0)
	visual.call("set_movement_speed", 5.2)
	for index in range(3): await process_frame
	var player := find_animation_player(visual)
	if player != null:
		player.seek(.24, true)
	camera.position = Vector3(2.25, 1.58, 3.40)
	camera.fov = 42
	camera.look_at(Vector3(0, .98, 0), Vector3.UP)
	for index in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var walk_path := "res://artifacts/full_continuous_hero_walk_ingame.png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(walk_path))
	print("FULL_CONTINUOUS_HERO_CAPTURE|%s" % walk_path)
	quit(0)


func find_animation_player(node:Node)->AnimationPlayer:
	if node is AnimationPlayer:return node as AnimationPlayer
	for child in node.get_children():
		var found:=find_animation_player(child)
		if found!=null:return found
	return null
