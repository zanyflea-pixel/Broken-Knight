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
	var packed:=load("res://assets/hero/hero_base_body.glb") as PackedScene
	var hero:=packed.instantiate()
	root.add_child(hero)
	var skeleton:=_find_skeleton(hero)
	var player:=_find_player(hero)
	player.play(&"SwordSlash")
	var bones:=[&"clavicle.R",&"upper_arm.R",&"forearm.R",&"hand.R"]
	var first:={}
	for time in [0.0,.125,.333,.667]:
		player.seek(time,true)
		skeleton.force_update_all_bone_transforms()
		var values:Array[String]=[]
		for bone_name in bones:
			var bone:=skeleton.find_bone(bone_name)
			var pose:=skeleton.get_bone_pose(bone)
			if not first.has(bone_name):
				first[bone_name]=pose
			var base:Transform3D=first[bone_name]
			var angle:=base.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())
			values.append("%s=%.4f"%[bone_name,angle])
		print("SWORD_ARM_IMPORTED|time=%.3f|%s|hand=%s"%[time,"|".join(values),skeleton.get_bone_global_pose(skeleton.find_bone(&"hand.R")).origin])
	hero.free()
	quit(0)
