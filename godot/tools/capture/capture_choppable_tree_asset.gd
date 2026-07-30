extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("#86afcd")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("#d8e8ee")
	environment_resource.ambient_light_energy = 0.8
	environment.environment = environment_resource
	stage.add_child(environment)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(18.0, 18.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#71834c")
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	stage.add_child(ground)

	var tree_scene := load("res://assets/items/choppable_tree.glb") as PackedScene
	var tree := tree_scene.instantiate()
	stage.add_child(tree)

	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sunlight.light_energy = 1.1
	sunlight.shadow_enabled = true
	stage.add_child(sunlight)

	var camera := Camera3D.new()
	camera.position = Vector3(10.0, 6.0, 12.0)
	camera.fov = 48.0
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 3.4, 0.0), Vector3.UP)
	camera.current = true

	for frame in range(8):
		await process_frame
	var output := "res://artifacts/choppable_tree_asset.png"
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("TREE_ASSET_CAPTURE|%s" % output)
	stage.free()
	quit()
