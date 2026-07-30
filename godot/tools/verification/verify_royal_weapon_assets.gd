extends SceneTree

const SWORD:PackedScene=preload("res://assets/equipment/royal_vanguard_sword.glb")
const SHIELD:PackedScene=preload("res://assets/equipment/royal_vanguard_shield.glb")


func find_named(node:Node,target:String)->Node:
	if node.name==target:return node
	for child in node.get_children():
		var found:=find_named(child,target)
		if found:return found
	return null


func count_meshes(node:Node)->int:
	var total:=1 if node is MeshInstance3D else 0
	for child in node.get_children():total+=count_meshes(child)
	return total


func _initialize()->void:
	var sword:=SWORD.instantiate()
	var shield:=SHIELD.instantiate()
	root.add_child(sword)
	root.add_child(shield)
	await process_frame
	var blade:=find_named(sword,"RoyalSword_ForgedBlade")
	var guard:=find_named(sword,"RoyalSword_ContinuousCrossguard")
	var wrap:=find_named(sword,"RoyalSword_LeatherSpiralWrap")
	var shell:=find_named(shield,"RoyalShield_ContinuousHeaterShell")
	var crest:=find_named(shield,"FlushRealmCrest") as MeshInstance3D
	var forearm_strap:=find_named(shield,"RoyalShield_ForearmStrap")
	var hand_grip:=find_named(shield,"RoyalShield_HandGrip")
	var crest_thin:bool=is_instance_valid(crest) and crest.get_aabb().size.z<=.012
	var passed:=is_instance_valid(blade) and is_instance_valid(guard) and is_instance_valid(wrap) and count_meshes(sword)>=12 and is_instance_valid(shell) and is_instance_valid(crest) and is_instance_valid(forearm_strap) and is_instance_valid(hand_grip) and count_meshes(shield)>=12 and crest_thin
	print("ROYAL_WEAPONS|sword_meshes=%d|shield_meshes=%d|blade=%s|continuous_guard=%s|spiral_wrap=%s|heater_shell=%s|crest=%s|crest_thin=%s|back_hardware=%s"%[count_meshes(sword),count_meshes(shield),is_instance_valid(blade),is_instance_valid(guard),is_instance_valid(wrap),is_instance_valid(shell),is_instance_valid(crest),crest_thin,is_instance_valid(forearm_strap) and is_instance_valid(hand_grip)])
	print("ROYAL_WEAPONS_VERIFY|%s"%("PASS" if passed else "FAIL"))
	sword.queue_free()
	shield.queue_free()
	await process_frame
	quit(0 if passed else 1)
