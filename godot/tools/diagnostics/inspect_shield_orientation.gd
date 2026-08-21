extends SceneTree


func _find_named(node:Node, fragment:String)->Node3D:
	if fragment.to_lower() in String(node.name).to_lower():
		return node as Node3D
	for child in node.get_children():
		var found:=_find_named(child,fragment)
		if found:return found
	return null


func _visual_center(node:Node3D)->Vector3:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return node.global_transform*((node as MeshInstance3D).mesh.get_aabb().get_center())
	return node.global_position


func _initialize()->void:
	var visual:=Node3D.new()
	visual.name="ShieldOrientationInspection"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	for index in range(8):await process_frame
	visual.call("set_equipment_pieces",{
		"mainhand":{"id":"royal_vanguard_sword"},
		"offhand":{"id":"royal_vanguard_shield"},
	})
	for index in range(8):await process_frame
	var shield:Node3D=visual.get("_shield_root")
	var crest:=_find_named(shield,"RoyalShield_BossCabochon")
	var grip:=_find_named(shield,"RoyalShield_HandGrip")
	var shell:=_find_named(shield,"RoyalShield_ContinuousHeaterShell")
	var crest_center:=_visual_center(crest)
	var grip_center:=_visual_center(grip)
	var shell_center:=_visual_center(shell)
	var face_direction:=(crest_center-grip_center).normalized()
	var body_reference:=visual.global_position+Vector3.UP*1.20
	var away_from_body:=(shell_center-body_reference).normalized()
	var hero_forward:=visual.global_basis.z.normalized()
	print("SHIELD_ORIENTATION|shield=%s|shell=%s|crest=%s|grip=%s"%[shield.global_position,shell_center,crest_center,grip_center])
	print("SHIELD_DIRECTIONS|face=%s|away=%s|forward=%s|face_away_dot=%.4f|face_forward_dot=%.4f"%[
		face_direction,away_from_body,hero_forward,face_direction.dot(away_from_body),face_direction.dot(hero_forward)
	])
	print("SHIELD_AXES|x=%s|y=%s|z=%s"%[shield.global_basis.x.normalized(),shield.global_basis.y.normalized(),shield.global_basis.z.normalized()])
	var passed:=face_direction.dot(hero_forward)>.65 and face_direction.dot(away_from_body)>.15 and shield.global_basis.y.normalized().dot(Vector3.UP)>.80
	print("SHIELD_ORIENTATION_VERIFY|%s"%("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
