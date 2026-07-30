extends SceneTree


func _find_skeleton(node:Node)->Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found:=_find_skeleton(child)
		if found!=null:
			return found
	return null


func _find_player(node:Node)->AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found:=_find_player(child)
		if found!=null:
			return found
	return null


func _initialize()->void:
	call_deferred("_run")


func _sample(label:String,visual:Node3D,skeleton:Skeleton3D,player:AnimationPlayer,first:Dictionary)->void:
	skeleton.force_update_all_bone_transforms()
	var values:Array[String]=[]
	for bone_name in [&"clavicle.R",&"upper_arm.R",&"forearm.R",&"hand.R"]:
		var bone:=skeleton.find_bone(bone_name)
		var pose:=skeleton.get_bone_pose(bone)
		if not first.has(bone_name):
			first[bone_name]=pose
		var base:Transform3D=first[bone_name]
		var angle:=base.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())
		values.append("%s=%.4f"%[bone_name,angle])
	print("LIVE_SWORD_ARM|%s|animation=%s|position=%.3f|remaining=%.3f|%s|hand=%s"%[
		label,player.current_animation,player.current_animation_position,
		float(visual.get("_action_time")),"|".join(values),
		skeleton.get_bone_global_pose(skeleton.find_bone(&"hand.R")).origin,
	])


func _run()->void:
	var visual:=Node3D.new()
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	for index in range(10):
		await process_frame
	visual.call("set_equipment_pieces",{
		"mainhand":{"id":"royal_vanguard_sword"},
		"offhand":{"id":"royal_vanguard_shield"},
	})
	await create_timer(.25).timeout
	var skeleton:=_find_skeleton(visual)
	var player:=_find_player(visual)
	var first:={}
	_sample("before",visual,skeleton,player,first)
	visual.call("play_action","sword")
	await create_timer(.13).timeout
	_sample("load",visual,skeleton,player,first)
	await create_timer(.22).timeout
	_sample("impact",visual,skeleton,player,first)
	await create_timer(.30).timeout
	_sample("recover",visual,skeleton,player,first)
	visual.free()
	quit(0)
