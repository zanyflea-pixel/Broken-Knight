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
	await process_frame
	var mounted_parent_ok:=horse.get_parent()==player
	var dismounted:bool=player.dismount_horse()
	await process_frame
	var restored_parent_ok:=horse.get_parent()==original_parent
	var okay:=mounted and dismounted and mounted_parent_ok and restored_parent_ok and "Idle" in animations and "Trot" in animations
	print("MOUNT_VALIDATION|horses=%d|stable=true|animations=%s|mounted=%s|parented=%s|dismounted=%s|restored=%s|walk_speed=%.1f|sprint_speed=%.1f"%[
		horses.size(),str(animations),mounted,mounted_parent_ok,dismounted,restored_parent_ok,
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
