extends SceneTree


func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null


func find_named(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := find_named(child, target_name)
		if found != null:
			return found
	return null


func count_armor(node:Node,visible_only:=false)->int:
	var total:=0
	if String(node.name).begins_with("RoyalArmor_") and (not visible_only or node.visible):total+=1
	for child in node.get_children():total+=count_armor(child,visible_only)
	return total

func count_prefix(node:Node,prefix:String,visible_only:=false)->int:
	var total:=0
	if String(node.name).begins_with(prefix) and (not visible_only or node.visible):total+=1
	for child in node.get_children():total+=count_prefix(child,prefix,visible_only)
	return total


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var visual_script := load("res://scripts/HeroVisual.gd")
	if visual_script == null:
		push_error("HERO_VISUAL_ANIM|script_load_failed")
		quit(2)
		return
	var visual := Node3D.new()
	visual.set_script(visual_script)
	root.add_child(visual)
	await process_frame
	await process_frame
	var player := find_animation_player(visual)
	if player == null:
		push_error("HERO_VISUAL_ANIM|animation_player_missing")
		quit(3)
		return
	var initial := player.current_animation
	visual.call("set_move_blend", 1.0)
	visual.call("set_movement_speed", 5.2)
	await process_frame
	var moving := player.current_animation
	var walk_speed_scale := player.speed_scale
	var walk_clip:=player.get_animation(&"Walk")
	var walk_loop_mode:=walk_clip.loop_mode
	var walk_length:=walk_clip.length
	player.advance(walk_length*2.35)
	await process_frame
	var walk_still_playing:=player.is_playing() and player.current_animation=="Walk"
	var walk_wrapped_position:=player.current_animation_position
	visual.call("set_move_blend", 0.0)
	await process_frame
	var stopped := player.current_animation
	visual.call("play_jump")
	await process_frame
	var jumping := player.current_animation
	visual.call("play_land")
	await process_frame
	var landing := player.current_animation
	await create_timer(0.7).timeout
	await process_frame
	var after_land := player.current_animation
	visual.call("play_roll")
	await process_frame
	var rolling:=player.current_animation
	player.advance(player.current_animation_length+.05);await process_frame
	var skill_results: Array[String] = []
	for skill in ["spark", "nova", "blink", "orb"]:
		visual.call("play_action", skill)
		await process_frame
		skill_results.append(player.current_animation)
		player.advance(player.current_animation_length + 0.05)
		await process_frame
	var after_skills := player.current_animation
	# Teleports must clear a half-finished action or airborne state before the
	# next movement frame. This was the intermittent "walk stopped" failure.
	visual.call("play_jump")
	visual.call("reset_traversal_animation")
	visual.call("set_move_blend",1.0)
	visual.call("set_movement_speed",5.2)
	await process_frame
	var after_teleport_reset:=player.current_animation
	visual.call("set_move_blend",0.0)
	await process_frame
	var armor_total:=count_armor(visual)
	var armor_head_total:=count_prefix(visual,"RoyalArmor_head_")
	var armor_initial_visible:=count_armor(visual,true)
	visual.call("set_equipment_pieces",{"head":{"id":"royal_helm"},"chest":{"id":"royal_plate"},"shoulders":{"id":"royal_shoulders"},"hands":{"id":"royal_gauntlets"},"feet":{"id":"royal_boots"},"pants":{"id":"royal_pants"}})
	await process_frame
	var armor_all_visible:=count_armor(visual,true)
	var pants_visible:=count_prefix(visual,"RoyalArmor_pants_",true)
	visual.call("set_equipment_pieces",{"head":{"id":"royal_helm"}})
	await process_frame
	var armor_head_visible:=count_armor(visual,true)
	visual.call("set_equipment_pieces", {"offhand":{"id":"traveler_torch"}})
	await process_frame
	var torch_idle := player.current_animation
	visual.call("set_move_blend", 1.0)
	visual.call("set_movement_speed", 5.2)
	await process_frame
	var torch_walk := player.current_animation
	var torch_root := find_named(visual, "EquippedTravelerTorch")
	var torch_light := find_named(visual, "TorchLight")
	visual.call("set_move_blend", 0.0)
	visual.call("set_equipment_pieces", {"offhand":{}})
	await process_frame
	var after_torch := player.current_animation
	visual.call("set_equipment_pieces",{"mainhand":{"id":"royal_vanguard_staff"}})
	await process_frame
	var staff_idle:=player.current_animation
	var staff_total:=count_prefix(visual,"RoyalStaff_")
	var staff_visible:=count_prefix(visual,"RoyalStaff_",true)
	visual.call("set_move_blend",1.0);visual.call("set_movement_speed",5.2);await process_frame
	var staff_walk:=player.current_animation
	visual.call("set_move_blend",0.0);visual.call("play_action","spark");await process_frame
	var staff_spark:=player.current_animation
	var staff_focus:=find_named(visual,"RoyalStaffFocus")
	var staff_light:=find_named(visual,"RoyalStaffLight") as OmniLight3D
	print("HERO_VISUAL_ANIM|initial=%s|moving=%s|walk_loop=%d,%s,%.3f|stopped=%s|jumping=%s|landing=%s|after_land=%s|skills=%s|after_skills=%s|after_teleport_reset=%s|armor=%d,%d,%d,%d/%d|torch_idle=%s|torch_walk=%s|after_torch=%s|staff=%s,%s,%s,%d,%d|torch_visible=%s|torch_light=%s|walk_speed_scale=%.4f|playing=%s" % [initial, moving, walk_loop_mode, walk_still_playing, walk_wrapped_position, stopped, jumping, landing, after_land, skill_results, after_skills, after_teleport_reset, armor_total, armor_initial_visible, armor_all_visible, armor_head_visible, armor_head_total, torch_idle, torch_walk, after_torch,staff_idle,staff_walk,staff_spark,staff_total,staff_visible,torch_root != null, torch_light != null, walk_speed_scale, player.is_playing()])
	# The consolidated armor intentionally uses structural shells instead of
	# dozens of freestanding decorative meshes.
	if initial != "Idle" or moving != "Walk" or walk_loop_mode!=Animation.LOOP_LINEAR or not walk_still_playing or walk_wrapped_position>=walk_length or stopped != "Idle" or jumping != "Jump" or landing != "Land" or after_land != "Idle" or rolling!="Roll" or skill_results != ["Spark", "Nova", "Blink", "Orb"] or after_skills != "Idle" or after_teleport_reset!="Walk" or armor_total < 6 or armor_total > 12 or armor_initial_visible != 0 or armor_all_visible != armor_total or pants_visible<1 or armor_head_total < 1 or armor_head_visible < 1 or torch_idle != "TorchIdle" or torch_walk != "TorchWalk" or after_torch != "Idle" or staff_idle!="StaffIdle" or staff_walk!="StaffWalk" or staff_spark!="StaffSpark" or staff_total<1 or staff_visible!=staff_total or staff_focus==null or staff_light==null or staff_light.light_energy>.5 or staff_light.omni_range>2.0 or torch_root == null or torch_light == null or not player.is_playing() or absf(walk_speed_scale - 5.2 / 3.6) > 0.01:
		push_error("HERO_VISUAL_ANIM|state_switch_failed")
		quit(4)
		return
	visual.queue_free()
	await process_frame
	print("HERO_VISUAL_ANIM|PASS")
	quit(0)
