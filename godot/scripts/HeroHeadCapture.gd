extends Node3D

const OUTPUT_FILE := "user://captures/hero_head_pass.png"

var _camera: Camera3D
var _hero_root: Node3D


func _ready() -> void:
	DisplayServer.window_set_title("Hero Head Capture")
	print("HeroHeadCapture: ready")
	_build_environment()
	_build_stage()
	_build_hero()
	call_deferred("_capture")


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.44, 0.58, 0.76, 1.0)
	sky_material.sky_horizon_color = Color(0.62, 0.70, 0.82, 1.0)
	sky_material.ground_bottom_color = Color(0.34, 0.40, 0.40, 1.0)
	sky_material.ground_horizon_color = Color(0.48, 0.54, 0.54, 1.0)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 0.96, 1.0)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = environment
	add_child(env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -46.0, 0.0)
	key_light.light_color = Color(1.0, 0.96, 0.92, 1.0)
	key_light.light_energy = 1.10
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 80.0
	add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-24.0, 54.0, 0.0)
	fill_light.light_color = Color(0.67, 0.76, 0.90, 1.0)
	fill_light.light_energy = 0.32
	add_child(fill_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-28.0, 138.0, 0.0)
	rim_light.light_color = Color(0.96, 0.92, 0.86, 1.0)
	rim_light.light_energy = 0.20
	add_child(rim_light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.72, 2.34, 1.34)
	_camera.look_at(Vector3(0.0, 2.44, 0.06), Vector3.UP)
	_camera.fov = 30.0
	_camera.current = true
	add_child(_camera)


func _build_stage() -> void:
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.72, 0.88, 0.66, 1.0)
	floor_mat.roughness = 0.96
	floor.material_override = floor_mat
	add_child(floor)


func _build_hero() -> void:
	_hero_root = Node3D.new()
	_hero_root.position = Vector3(0.0, 0.0, 0.0)
	_hero_root.rotation.y = PI
	add_child(_hero_root)

	var visual := load("res://scripts/HeroVisual.gd").new()
	visual.name = "Visual"
	visual.position = Vector3(0.0, 0.95, 0.0)
	_hero_root.add_child(visual)
	print("HeroHeadCapture: hero built")


func _capture() -> void:
	print("HeroHeadCapture: capture start")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		push_error("Hero head capture failed: empty image.")
		get_tree().quit(1)
		return
	var capture_dir := ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var output_path := ProjectSettings.globalize_path(OUTPUT_FILE)
	var err := image.save_png(output_path)
	if err != OK:
		push_error("Hero head capture save failed: %s" % err)
		get_tree().quit(1)
		return
	print("Hero head capture saved to: %s" % output_path)
	get_tree().quit()
