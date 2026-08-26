extends SceneTree


func _initialize()->void:
	var main_scene:=load("res://scenes/Main.tscn") as PackedScene
	if main_scene==null:
		push_error("MOUNT_VALIDATION|failed_to_load_main")
		quit(1)
		return
	var main:=main_scene.instantiate()
	root.add_child(main)
	for frame in range(720):
		await process_frame
		if get_nodes_in_group("rideable_horse").size()>=3:break
	var horses:=get_nodes_in_group("rideable_horse")
	var stable:=root.find_child("Riverwatch Starter Stables",true,false)
	var player:=root.find_child("Player",true,false)
	if horses.size()!=3 or stable==null or player==null:
		push_error("MOUNT_VALIDATION|horses=%d|stable=%s|player=%s"%[horses.size(),stable!=null,player!=null])
		quit(2)
		return
	var horse:=horses[0] as Node3D
	var animations:=_animation_names(horse)
	var original_parent:=horse.get_parent()
	var mounted:bool=player.mount_horse(horse)
	await process_frame
	if horse.has_method("set_travel_speed"):horse.set_travel_speed(14.0)
	var walk_state_ok:=str(horse.get("_current_animation")).ends_with("Walk")
	if horse.has_method("set_travel_speed"):horse.set_travel_speed(21.0)
	var trot_state_ok:=str(horse.get("_current_animation")).ends_with("Trot")
	var mounted_parent_ok:=horse.get_parent()==player
	player.call("_start_jump")
	var mounted_jump_ok:=bool(player.get("_is_airborne")) and is_equal_approx(float(player.get("_vertical_velocity")),float(player.get("mounted_jump_velocity")))
	var jump_animation_ok:=str(horse.get("_current_animation")).ends_with("Jump")
	await process_frame
	if horse.has_method("play_land"):horse.play_land()
	player.set("_is_airborne",false)
	player.set("_vertical_velocity",0.0)
	var dismounted:bool=player.dismount_horse()
	await process_frame
	var restored_parent_ok:=horse.get_parent()==original_parent
	var interaction_radius:=_mount_interaction_radius(root,horse)
	var radius_ok:=interaction_radius>0.0 and interaction_radius<=1.8
	var okay:=mounted and dismounted and mounted_parent_ok and walk_state_ok and trot_state_ok and mounted_jump_ok and jump_animation_ok and restored_parent_ok and radius_ok and "Idle" in animations and "Walk" in animations and "Trot" in animations and "Jump" in animations
	print("MOUNT_VALIDATION|horses=%d|stable=true|animations=%s|mounted=%s|parented=%s|walk_state=%s|trot_state=%s|mounted_jump=%s|jump_animation=%s|dismounted=%s|restored=%s|interaction_radius=%.1f|walk_speed=%.1f|sprint_speed=%.1f"%[
		horses.size(),str(animations),mounted,mounted_parent_ok,walk_state_ok,trot_state_ok,mounted_jump_ok,jump_animation_ok,dismounted,restored_parent_ok,interaction_radius,
		float(player.get("mounted_walk_speed")),float(player.get("mounted_sprint_speed"))])
	quit(0 if okay else 3)


func _animation_names(node:Node)->Array[String]:
	if node is AnimationPlayer:
		var result:Array[String]=[]
		for animation_name in (node as AnimationPlayer).get_animation_list():
			var text:=str(animation_name)
			result.append(text.get_slice("/",text.get_slice_count("/")-1))
		return result
	for child in node.get_children():
		var child_result:=_animation_names(child)
		if not child_result.is_empty():return child_result
	return []


func _mount_interaction_radius(node:Node,horse:Node3D)->float:
	var director:=node.find_child("GameplayDirector",true,false)
	if director==null:return -1.0
	var interactions:Variant=director.get("_interactables")
	if not interactions is Array:return -1.0
	for interaction_value in interactions:
		if not interaction_value is Dictionary:continue
		var interaction:=interaction_value as Dictionary
		if str(interaction.get("action",""))=="mount_horse" and interaction.get("node")==horse:
			return float(interaction.get("radius",-1.0))
	return -1.0
