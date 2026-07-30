extends SceneTree


var stage:Node3D
var visual:Node3D
var animation_player:AnimationPlayer
var line_preview:MeshInstance3D
var capture_suffix:=""


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
	environment.ambient_light_color=Color(.42,.48,.60)
	environment.ambient_light_energy=.82
	world_environment.environment=environment
	stage.add_child(world_environment)
	var key:=DirectionalLight3D.new()
	key.rotation=Vector3(-.68,-.62,0)
	key.light_color=Color(1.0,.82,.66)
	key.light_energy=1.65
	key.shadow_enabled=true
	stage.add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation=Vector3(-.20,.80,0)
	fill.light_color=Color(.36,.52,1.0)
	fill.light_energy=.62
	stage.add_child(fill)
	var floor:=MeshInstance3D.new()
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size=Vector2(7,7)
	floor.mesh=floor_mesh
	var floor_material:=StandardMaterial3D.new()
	floor_material.albedo_color=Color(.045,.052,.068)
	floor_material.roughness=.86
	floor.material_override=floor_material
	stage.add_child(floor)
	var camera:=Camera3D.new()
	camera.current=true
	camera.fov=46
	if OS.get_environment("SWORD_CAPTURE_ANGLE")=="back":
		camera.position=Vector3(-2.35,1.72,-3.20)
		capture_suffix="_back"
	else:
		camera.position=Vector3(2.35,1.72,3.20)
	stage.add_child(camera)
	camera.look_at(Vector3(0,1.10,0),Vector3.UP)


func _armor(mainhand:String,offhand:String)->Dictionary:
	return {
		"head":{"id":"royal_helm"},
		"chest":{"id":"royal_plate"},
		"shoulders":{"id":"royal_shoulders"},
		"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},
		"pants":{"id":"royal_pants"},
		"mainhand":{"id":mainhand},
		"offhand":{"id":offhand} if not offhand.is_empty() else {},
	}


func _pose_action(action:StringName,time:float,duration:float,kind:String)->void:
	if animation_player.current_animation!=action:
		animation_player.play(action)
	animation_player.seek(time,true)
	animation_player.speed_scale=0.0
	visual.set("_action_animation_state",action)
	visual.set("_current_imported_animation",action)
	visual.set("_action_kind",kind)
	visual.set("_action_time",maxf(.001,duration-time))
	visual.call("_apply_leg_proportion_correction")
	visual.call("_update_warrior_weapon_action")
	await process_frame
	if kind=="sword":
		var sword:Node3D=visual.get("_sword_root")
		var hand:BoneAttachment3D=visual.get("_sword_attachment")
		print("SWORD_CAPTURE_POSE|time=%.3f|blade_axis=%s|grip=%s|hand=%s|local=%s"%[
			time,sword.global_basis.y,sword.global_position,hand.global_position,sword.position,
		])


func _capture(name:String)->void:
	for index in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://artifacts/%s%s.png"%[name,capture_suffix]
	var error:=root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("UNIFICATION_CAPTURE|%s|error=%s"%[path,error])


func _show_fishing_line()->void:
	if is_instance_valid(line_preview):line_preview.queue_free()
	line_preview=MeshInstance3D.new()
	line_preview.name="VerifiedRodTipLine"
	var immediate:=ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var origin:Vector3=visual.call("get_fishing_line_origin")
	immediate.surface_add_vertex(origin)
	# Keep the endpoint well off the hero so the full line, including its exact
	# connection at the rod tip, remains readable in the verification image.
	immediate.surface_add_vertex(Vector3(-1.35,.42,1.45))
	immediate.surface_end()
	line_preview.mesh=immediate
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(1.0,.86,.18)
	material.emission_enabled=true
	material.emission=Color(1.0,.45,.04)
	material.emission_energy_multiplier=3.0
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	line_preview.material_override=material
	stage.add_child(line_preview)
	var tip_marker:=MeshInstance3D.new()
	tip_marker.name="VerifiedRodTipMarker"
	var marker_mesh:=SphereMesh.new()
	marker_mesh.radius=.045
	marker_mesh.height=.09
	marker_mesh.radial_segments=16
	marker_mesh.rings=8
	tip_marker.mesh=marker_mesh
	tip_marker.material_override=material
	stage.add_child(tip_marker)
	tip_marker.global_position=origin


func _run()->void:
	_setup_stage()
	visual=Node3D.new()
	visual.name="AnimationInspection"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	stage.add_child(visual)
	for index in range(10):await process_frame
	animation_player=visual.get("_imported_animation_player")
	visual.call("set_equipment_pieces",_armor("royal_vanguard_sword","royal_vanguard_shield"))
	for index in range(5):await process_frame
	var slash_duration:=animation_player.get_animation(&"SwordSlash").length
	# Capture the recovered original 0.70-second sine swipe at rest, maximum
	# arc, and reset. The arm stays in guard; the weapon pivots at the palm.
	visual.call("play_action","sword")
	animation_player.play(&"SwordSlash",0.0)
	animation_player.speed_scale=0.0
	await process_frame
	for sample in [
		["sword_original_ready",.020],
		["sword_original_swipe",.358],
		["sword_original_reset",.700],
	]:
		await _pose_action(&"SwordSlash",float(sample[1]),slash_duration,"sword")
		await _capture(str(sample[0]))

	visual.call("set_equipment_pieces",_armor("starter_fishing_pole",""))
	for index in range(4):await process_frame
	var fish_duration:=animation_player.get_animation(&"FishCast").length
	await _pose_action(&"FishCast",.333,fish_duration,"fish")
	await _capture("fishing_cast_loaded")
	await _pose_action(&"FishCast",.583,fish_duration,"fish")
	_show_fishing_line()
	await _capture("fishing_cast_release_from_rod_tip")
	quit(0)
