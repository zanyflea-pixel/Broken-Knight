extends SceneTree

func find_named(node:Node,target:String)->Node:
	if node.name==target:return node
	for child in node.get_children():
		var found:=find_named(child,target)
		if found!=null:return found
	return null

func _initialize()->void:call_deferred("_run")

func _run()->void:
	var visual:=Node3D.new();visual.set_script(load("res://scripts/HeroVisual.gd"));root.add_child(visual)
	await process_frame;await process_frame
	visual.call("set_equipment_pieces",{"mainhand":{"id":"royal_vanguard_sword"},"offhand":{"id":"royal_vanguard_shield"}})
	visual.call("set_move_blend",0.0);await process_frame;await process_frame
	var sword:=find_named(visual,"RoyalVanguardSword") as Node3D
	var shield:=find_named(visual,"RoyalVanguardShield") as Node3D
	var skeleton:=find_named(visual,"Skeleton3D") as Skeleton3D
	if skeleton==null:
		# glTF skeleton naming is not guaranteed; find by type.
		skeleton=_find_skeleton(visual)
	var chest_position:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("chest")).origin
	var hero_forward:=visual.global_basis.z.normalized()
	var sword_front:=(sword.global_position-chest_position).dot(hero_forward)
	var shield_front:=(shield.global_position-chest_position).dot(hero_forward)
	print("WARRIOR_CARRY|sword_front=%.4f|shield_front=%.4f|sword=%s|shield=%s"%[sword_front,shield_front,sword.global_position,shield.global_position])
	if sword_front<=0.0 or shield_front<=0.0:
		push_error("WARRIOR_CARRY|weapon_behind_torso");quit(2);return
	print("WARRIOR_CARRY|PASS");visual.free();quit()

func _find_skeleton(node:Node)->Skeleton3D:
	if node is Skeleton3D:return node
	for child in node.get_children():
		var found:=_find_skeleton(child)
		if found!=null:return found
	return null
