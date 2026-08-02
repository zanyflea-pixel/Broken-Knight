extends SceneTree

const HERO_PATH := "res://assets/hero/hero_base_body.glb"

func collect(node: Node, skeletons: Array, players: Array, meshes: Array) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		collect(child, skeletons, players, meshes)

func _initialize() -> void:
	var resource := load(HERO_PATH)
	if resource == null or not resource is PackedScene:
		push_error("HERO_VERIFY|failed_to_load")
		quit(2)
		return
	var hero := (resource as PackedScene).instantiate()
	var skeletons: Array = []
	var players: Array = []
	var meshes: Array = []
	collect(hero, skeletons, players, meshes)
	var names: Array[String] = []
	var armor_names: Array[String] = []
	var staff_names: Array[String] = []
	var pants_names: Array[String] = []
	var skinned_armor := 0
	for mesh in meshes:
		if String(mesh.name).begins_with("RoyalArmor_"):
			armor_names.append(String(mesh.name))
			if String(mesh.name).begins_with("RoyalArmor_pants_"):
				pants_names.append(String(mesh.name))
			if (mesh as MeshInstance3D).skin != null:
				skinned_armor += 1
		elif String(mesh.name).begins_with("RoyalStaff_"):
			staff_names.append(String(mesh.name))
	for player in players:
		for animation_name in player.get_animation_list():
			if animation_name != "RESET":
				names.append(String(animation_name))
	names.sort()
	var bone_count := 0
	if not skeletons.is_empty():
		bone_count = (skeletons[0] as Skeleton3D).get_bone_count()
	print("HERO_IMPORT|skeletons=%d|bones=%d|meshes=%d|armor_meshes=%d|skinned_armor=%d|pants_meshes=%d|staff_meshes=%d|animations=%s" % [skeletons.size(), bone_count, meshes.size(), armor_names.size(), skinned_armor, pants_names.size(), staff_names.size(), names])
	var required := ["Idle", "Walk", "TorchIdle", "TorchWalk", "StaffIdle", "StaffWalk", "Jump", "Land", "Roll", "Spark", "Nova", "Blink", "Orb", "StaffSpark", "StaffNova", "StaffBlink", "StaffOrb", "WarriorIdle", "WarriorWalk", "SwordSlash", "ShieldBash", "FishCast", "Death"]
	var missing: Array = required.filter(func(name): return not names.has(name))
	# The consolidated harness deliberately replaces dozens of floating accent
	# meshes with fewer connected shells. Validate complete slot coverage and
	# skinning instead of rewarding a large detached-object count.
	if skeletons.size() != 1 or bone_count < 20 or not missing.is_empty() or armor_names.size() < 50 or skinned_armor != armor_names.size() or pants_names.size()<5 or staff_names.size()<60:
		push_error("HERO_VERIFY|missing_required_rig_or_animation")
		quit(3)
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	var test_bone := skeleton.find_bone("thigh.L")
	var before := skeleton.get_bone_pose(test_bone)
	player.play("Walk")
	player.advance(0.50)
	var after := skeleton.get_bone_pose(test_bone)
	var walk_delta := before.origin.distance_to(after.origin) + before.basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion())
	player.play("Idle")
	player.advance(1.0)
	var idle_mid := skeleton.get_bone_pose(skeleton.find_bone("chest"))
	player.advance(1.0)
	var idle_end := skeleton.get_bone_pose(skeleton.find_bone("chest"))
	var idle_delta := idle_mid.basis.get_rotation_quaternion().angle_to(idle_end.basis.get_rotation_quaternion())
	print("HERO_PLAYBACK|walk_delta=%.6f|idle_delta=%.6f|walk_length=%.4f|idle_length=%.4f|walk_loop=%d|idle_loop=%d" % [walk_delta, idle_delta, player.get_animation("Walk").length, player.get_animation("Idle").length, player.get_animation("Walk").loop_mode, player.get_animation("Idle").loop_mode])
	if walk_delta <= 0.001:
		push_error("HERO_VERIFY|walk_did_not_move_skeleton")
		quit(4)
		return
	if player.get_animation("Walk").loop_mode == Animation.LOOP_NONE or player.get_animation("Idle").loop_mode == Animation.LOOP_NONE:
		push_error("HERO_VERIFY|animations_not_looping")
		hero.free()
		quit(5)
		return
	if player.get_animation("Jump").loop_mode != Animation.LOOP_NONE or player.get_animation("Land").loop_mode != Animation.LOOP_NONE:
		push_error("HERO_VERIFY|jump_or_land_should_not_loop")
		hero.free()
		quit(6)
		return
	if player.get_animation("Roll").loop_mode != Animation.LOOP_NONE:
		push_error("HERO_VERIFY|roll_should_not_loop");hero.free();quit(10);return
	if player.get_animation("Death").loop_mode != Animation.LOOP_NONE:
		push_error("HERO_VERIFY|death_should_not_loop");hero.free();quit(11);return
	if player.get_animation("TorchIdle").loop_mode == Animation.LOOP_NONE or player.get_animation("TorchWalk").loop_mode == Animation.LOOP_NONE:
		push_error("HERO_VERIFY|torch_animations_not_looping")
		hero.free()
		quit(8)
		return
	if player.get_animation("StaffIdle").loop_mode==Animation.LOOP_NONE or player.get_animation("StaffWalk").loop_mode==Animation.LOOP_NONE:
		push_error("HERO_VERIFY|staff_animations_not_looping");hero.free();quit(9);return
	for skill_name in ["Spark", "Nova", "Blink", "Orb"]:
		if player.get_animation(skill_name).loop_mode != Animation.LOOP_NONE:
			push_error("HERO_VERIFY|skill_animation_should_not_loop|%s" % skill_name)
			hero.free()
			quit(7)
			return
	for skill_name in ["StaffSpark","StaffNova","StaffBlink","StaffOrb"]:
		if player.get_animation(skill_name).loop_mode!=Animation.LOOP_NONE:
			push_error("HERO_VERIFY|staff_skill_should_not_loop|%s"%skill_name);hero.free();quit(10);return
	var root_bone:=skeleton.find_bone("root")
	var death_before:=skeleton.get_bone_pose(root_bone)
	player.play("Death");player.advance(.90)
	var death_after:=skeleton.get_bone_pose(root_bone)
	var death_delta:=death_before.origin.distance_to(death_after.origin)+death_before.basis.get_rotation_quaternion().angle_to(death_after.basis.get_rotation_quaternion())
	print("HERO_DEATH_PLAYBACK|delta=%.4f|current=%s"%[death_delta,player.current_animation])
	if death_delta<.10:
		push_error("HERO_VERIFY|death_did_not_move_skeleton");hero.free();quit(12);return
	print("HERO_VERIFY|PASS")
	hero.free()
	quit(0)
