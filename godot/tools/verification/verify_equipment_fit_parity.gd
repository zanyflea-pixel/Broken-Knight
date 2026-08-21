extends SceneTree


func _initialize()->void:
	call_deferred("_run")


func _make_hero()->CharacterBody3D:
	var hero:=CharacterBody3D.new()
	hero.name="Player"
	var visual:=Node3D.new()
	visual.name="Visual"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	hero.add_child(visual)
	var pivot:=Node3D.new()
	pivot.name="CameraPivot"
	hero.add_child(pivot)
	var spring:=SpringArm3D.new()
	spring.name="SpringArm3D"
	pivot.add_child(spring)
	var camera:=Camera3D.new()
	camera.name="Camera3D"
	spring.add_child(camera)
	hero.set_script(load("res://scripts/HeroController.gd"))
	return hero


func _first_visible(nodes:Array)->Node3D:
	for node in nodes:
		if is_instance_valid(node) and node.visible:
			return node as Node3D
	return null


func _bone_world_position(skeleton:Skeleton3D,bone_name:String)->Vector3:
	var index:=skeleton.find_bone(bone_name)
	if index<0:return Vector3.INF
	return skeleton.global_transform*skeleton.get_bone_global_pose(index).origin


func _find_named(node:Node,fragment:String)->Node3D:
	if fragment.to_lower() in String(node.name).to_lower():return node as Node3D
	for child in node.get_children():
		var found:=_find_named(child,fragment)
		if found:return found
	return null


func _visual_center(node:Node3D)->Vector3:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return node.global_transform*((node as MeshInstance3D).mesh.get_aabb().get_center())
	return node.global_position


func _shield_face_direction(shield:Node3D)->Vector3:
	var boss:=_find_named(shield,"RoyalShield_BossCabochon")
	var grip:=_find_named(shield,"RoyalShield_HandGrip")
	if boss==null or grip==null:return Vector3.ZERO
	return (_visual_center(boss)-_visual_center(grip)).normalized()


func _run()->void:
	var failures:Array[String]=[]
	var hero:=_make_hero()
	root.add_child(hero)
	await process_frame
	await process_frame
	hero.active_class="Warrior"
	hero.equip_royal_armor()
	for index in range(8):await process_frame
	var visual:Node3D=hero.get_node("Visual")
	var sword:Node3D=visual.get("_sword_root")
	var shield:Node3D=visual.get("_shield_root")
	var sword_attachment:Node3D=visual.get("_sword_attachment")
	var sword_grip_error:=sword.global_position.distance_to(sword_attachment.global_position)
	if absf(sword_grip_error-.072)>.006:failures.append("world sword grip offset changed")
	var shield_face:=_shield_face_direction(shield)
	var shield_forward_dot:=shield_face.dot(visual.global_basis.z.normalized())
	var shield_upright_dot:=shield.global_basis.y.normalized().dot(Vector3.UP)
	if shield_forward_dot<.65:failures.append("world shield decorated face points backward")
	if shield_upright_dot<.80:failures.append("world shield is not upright")
	visual.play_action("shield")
	for index in range(8):await process_frame
	var shield_bash_forward_dot:=_shield_face_direction(shield).dot(visual.global_basis.z.normalized())
	var shield_bash_upright_dot:=shield.global_basis.y.normalized().dot(Vector3.UP)
	if shield_bash_forward_dot<.60:failures.append("shield face turns backward during bash")
	if shield_bash_upright_dot<.70:failures.append("shield turns sideways during bash")

	var director:=Node3D.new()
	root.add_child(director)
	var menu:=Control.new()
	menu.set_script(load("res://scripts/HeroMenu.gd"))
	root.add_child(menu)
	await process_frame
	menu.configure(hero,director)
	await process_frame
	await process_frame
	var variants:Dictionary=menu.get("portrait_item_variants")
	var portrait_sword:=_first_visible(variants.get("royal_vanguard_sword",[]))
	var portrait_shield:=_first_visible(variants.get("royal_vanguard_shield",[]))
	var portrait_model:Node3D=menu.get("portrait_model")
	var skeleton:Skeleton3D=menu.get("portrait_skeleton")
	# Blender's mirrored rig naming is the established gameplay convention:
	# sword/anatomical right uses hand.L; shield/anatomical left uses hand.R.
	var sword_hand:=_bone_world_position(skeleton,"hand.L")
	var shield_hand:=_bone_world_position(skeleton,"hand.R")
	var portrait_sword_error:=portrait_sword.global_position.distance_to(sword_hand)
	var portrait_shield_error:=portrait_shield.global_position.distance_to(shield_hand)
	var portrait_shield_forward_dot:=_shield_face_direction(portrait_shield).dot(portrait_model.global_basis.z.normalized())
	var world_sword_scale:=sword.scale.x
	var world_shield_scale:=shield.scale.x
	var inventory_sword_scale:=portrait_sword.scale.x
	var inventory_shield_scale:=portrait_shield.scale.x
	if absf(inventory_sword_scale-world_sword_scale)>.001:failures.append("inventory sword scale differs from world")
	if absf(inventory_shield_scale-world_shield_scale)>.001:failures.append("inventory shield scale differs from world")
	if portrait_sword_error>.10:failures.append("inventory sword is not seated near hand")
	if portrait_shield_error>.20:failures.append("inventory shield is not mounted near hand")
	if portrait_shield_forward_dot<.65:failures.append("inventory shield decorated face points backward")
	var portrait_player:AnimationPlayer=menu.get("portrait_animation_player")
	if portrait_player.assigned_animation!="WarriorIdle":failures.append("inventory warrior pose is not active")

	hero.switch_hero_class()
	menu.refresh()
	await process_frame
	var staff:=_first_visible(variants.get("royal_vanguard_staff",[]))
	if staff==null:failures.append("inventory staff is not visible for mage")
	if portrait_player.assigned_animation!="StaffIdle":failures.append("inventory staff pose is not active")

	print("EQUIPMENT_FIT|world_sword_grip=%.4f|inventory_sword_grip=%.4f|inventory_shield_grip=%.4f|world_shield_forward=%.4f|world_shield_upright=%.4f|bash_shield_forward=%.4f|bash_shield_upright=%.4f|inventory_shield_forward=%.4f|world_sword_scale=%.2f|inventory_sword_scale=%.2f|world_shield_scale=%.2f|inventory_shield_scale=%.2f|pose=%s"%[
		sword_grip_error,portrait_sword_error,portrait_shield_error,
		shield_forward_dot,shield_upright_dot,shield_bash_forward_dot,shield_bash_upright_dot,portrait_shield_forward_dot,
		world_sword_scale,inventory_sword_scale,world_shield_scale,inventory_shield_scale,
		portrait_player.assigned_animation,
	])
	if failures.is_empty():
		print("EQUIPMENT_FIT_VERIFY|PASS")
		quit(0)
	else:
		for failure in failures:push_error(failure)
		print("EQUIPMENT_FIT_VERIFY|FAIL|%s"%"; ".join(failures))
		quit(1)
