extends SceneTree


func _initialize()->void:
	call_deferred("_run")


func _equipment(mainhand:String,offhand:String="")->Dictionary:
	var slots:={
		"head":{"id":"royal_helm"},
		"chest":{"id":"royal_plate"},
		"shoulders":{"id":"royal_shoulders"},
		"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},
		"pants":{"id":"royal_pants"},
		"mainhand":{},
		"offhand":{},
	}
	if not mainhand.is_empty():slots.mainhand={"id":mainhand}
	if not offhand.is_empty():slots.offhand={"id":offhand}
	return slots


func _run()->void:
	var failures:Array[String]=[]
	var visual:=Node3D.new()
	visual.name="AnimationFishingVerification"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	for index in range(8):await process_frame

	var player:AnimationPlayer=visual.get("_imported_animation_player")
	if not is_instance_valid(player):
		failures.append("imported animation player was not created")
	else:
		for animation_name in [&"SwordSlash",&"FishCast"]:
			if not player.has_animation(animation_name):
				failures.append("missing %s animation"%animation_name)
		if player.has_animation(&"SwordSlash"):
			var sword_length:=player.get_animation(&"SwordSlash").length
			if sword_length<.68 or sword_length>.73:
				failures.append("SwordSlash duration is outside the original 0.70-second swipe range")
		if player.has_animation(&"FishCast"):
			var fish_length:=player.get_animation(&"FishCast").length
			if fish_length<.95 or fish_length>1.25:
				failures.append("FishCast duration is outside the deliberate cast range")

	visual.call("set_equipment_pieces",_equipment("starter_fishing_pole"))
	for index in range(3):await process_frame
	var pole:Node3D=visual.get("_fishing_pole_root")
	var marker:Node3D=visual.get("_fishing_pole_tip")
	var hand:Node3D=visual.get("_sword_attachment")
	if not is_instance_valid(pole) or not pole.visible:
		failures.append("fishing pole is not visible when equipped")
	if not is_instance_valid(marker):
		failures.append("fishing pole has no authored tip marker")
	var tip:=visual.call("get_fishing_line_origin") as Vector3
	var hand_distance:=tip.distance_to(hand.global_position) if is_instance_valid(hand) else 0.0
	var old_chest_origin:=visual.global_position+Vector3.UP*1.15
	var chest_distance:=tip.distance_to(old_chest_origin)
	if hand_distance<.95:
		failures.append("line origin is still near the hand/chest instead of the rod tip")
	if chest_distance<.55:
		failures.append("line origin still resolves from the torso")
	if is_instance_valid(marker) and tip.distance_to(marker.global_position)>.001:
		failures.append("public fishing origin does not match the animated rod-tip marker")

	visual.call("play_action","fish")
	await process_frame
	var active_action:StringName=visual.get("_action_animation_state")
	if active_action!=&"FishCast":
		failures.append("fish action does not select FishCast")

	visual.call("set_equipment_pieces",_equipment("royal_vanguard_sword","royal_vanguard_shield"))
	for index in range(2):await process_frame
	visual.call("play_action","sword")
	await process_frame
	var sword_action:StringName=visual.get("_action_animation_state")
	var sword_kind:String=visual.get("_action_kind")
	var sword_time:float=visual.get("_action_time")
	var sword:Node3D=visual.get("_sword_root")
	# Sword combat deliberately preserves WarriorIdle/WarriorWalk and applies
	# its strike procedurally after the skeleton update. An imported
	# SwordSlash state here would fight that procedural grip correction.
	if sword_action!=&"" or sword_kind!="sword" or sword_time<=0.0:
		failures.append("sword action does not enter the procedural strike state")
	if not is_instance_valid(sword) or not sword.visible:
		failures.append("sword is not visible during slash")
	var expected_grip:=hand.to_global(Vector3(0.0,.072,0.0)) if is_instance_valid(hand) else Vector3.ZERO
	if is_instance_valid(sword) and is_instance_valid(hand) and sword.global_position.distance_to(expected_grip)>.01:
		failures.append("sword is not seated on the animated hand")

	var director_source:=FileAccess.get_file_as_string("res://scripts/GameplayDirector.gd")
	if not director_source.contains("player.get_fishing_line_origin()"):
		failures.append("gameplay fishing line does not request the rod-tip origin")
	if not director_source.contains("_fishing_visual.to_local(line_origin)"):
		failures.append("gameplay fishing line does not convert its rod-tip endpoint locally")

	var sword_length:=player.get_animation(&"SwordSlash").length if is_instance_valid(player) and player.has_animation(&"SwordSlash") else 0.0
	var fish_length:=player.get_animation(&"FishCast").length if is_instance_valid(player) and player.has_animation(&"FishCast") else 0.0
	print("ANIMATION_FISHING|sword_length=%.4f|fish_length=%.4f|line_to_hand=%.3f|line_to_old_chest=%.3f|fish_action=%s|sword_action=%s"%[
		sword_length,fish_length,hand_distance,chest_distance,active_action,sword_action,
	])
	if failures.is_empty():
		print("ANIMATION_FISHING_VERIFY|PASS")
		quit(0)
	else:
		for failure in failures:push_error(failure)
		print("ANIMATION_FISHING_VERIFY|FAIL|%s"%"; ".join(failures))
		quit(1)
