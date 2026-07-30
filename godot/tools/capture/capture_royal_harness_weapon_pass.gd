extends SceneTree


func _initialize()->void:
	call_deferred("run_capture")


func run_capture()->void:
	var stage:=Node3D.new()
	root.add_child(stage)
	var environment:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(.012,.016,.026)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(.40,.46,.58)
	env.ambient_light_energy=.72
	environment.environment=env
	stage.add_child(environment)
	var key:=DirectionalLight3D.new()
	key.rotation=Vector3(-.72,-.58,0)
	key.light_color=Color(1.0,.82,.66)
	key.light_energy=1.55
	key.shadow_enabled=true
	stage.add_child(key)
	var rim:=OmniLight3D.new()
	rim.position=Vector3(-2.2,2.8,-1.8)
	rim.light_color=Color(.28,.42,1.0)
	rim.light_energy=3.0
	rim.omni_range=6.0
	stage.add_child(rim)
	var floor:=MeshInstance3D.new()
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size=Vector2(7,7)
	floor.mesh=floor_mesh
	var floor_material:=StandardMaterial3D.new()
	floor_material.albedo_color=Color(.045,.052,.066)
	floor_material.roughness=.82
	floor.material_override=floor_material
	stage.add_child(floor)
	var visual:=Node3D.new()
	visual.name="RoyalHarnessInspection"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	stage.add_child(visual)
	for index in range(8):
		await process_frame
	visual.call("set_equipment_pieces",{
		"head":{"id":"royal_helm"},
		"chest":{"id":"royal_plate"},
		"shoulders":{"id":"royal_shoulders"},
		"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},
		"pants":{"id":"royal_pants"},
		"mainhand":{"id":"royal_vanguard_sword"},
		"offhand":{"id":"royal_vanguard_shield"},
	})
	visual.call("set_move_blend",0.0)
	visual.call("set_movement_speed",0.0)
	for index in range(12):
		await process_frame
	var camera:=Camera3D.new()
	camera.current=true
	camera.fov=48
	camera.position=Vector3(2.25,1.80,3.25)
	stage.add_child(camera)
	camera.look_at(Vector3(0,1.08,0),Vector3.UP)
	for index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var path:="res://artifacts/royal_harness_weapon_pass.png"
	image.save_png(ProjectSettings.globalize_path(path))
	print("ROYAL_HARNESS_CAPTURE|%s"%path)
	quit(0)
