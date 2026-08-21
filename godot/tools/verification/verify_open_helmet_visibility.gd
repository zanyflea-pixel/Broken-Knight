extends SceneTree


func _initialize()->void:
	call_deferred("_run")


func _collect(node:Node,result:Dictionary)->void:
	if node is GeometryInstance3D:
		var geometry:=node as GeometryInstance3D
		var node_name:=String(geometry.name)
		if node_name=="ConnectedBody":result["body"]=geometry.visible
		elif node_name=="ProfessionalHelmetFace":result["face"]=geometry.visible
		elif node_name.begins_with("HeroHair") and geometry.visible:result["visible_hair"]+=1
		elif node_name.begins_with("ProfessionalEyes") and geometry.visible:result["visible_eyes"]+=1
		elif node_name.begins_with("ProfessionalBrows") and geometry.visible:result["visible_brows"]+=1
	for child in node.get_children():_collect(child,result)


func _run()->void:
	var visual:=Node3D.new()
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	await process_frame
	await process_frame
	visual.call("set_equipment_pieces",{
		"head":{"id":"royal_helm"},"chest":{"id":"royal_plate"},
		"shoulders":{"id":"royal_shoulders"},"hands":{"id":"royal_gauntlets"},
		"feet":{"id":"royal_boots"},"pants":{"id":"royal_pants"},
	})
	await process_frame
	var state:={"body":true,"face":false,"visible_hair":0,"visible_eyes":0,"visible_brows":0}
	_collect(visual,state)
	var valid:bool=not state.body and not state.face and state.visible_hair==0 and state.visible_eyes==0 and state.visible_brows==0
	print("FULL_LOGO_HELMET_VISIBILITY|body=%s|face=%s|hair=%d|eyes=%d|brows=%d"%[state.body,state.face,state.visible_hair,state.visible_eyes,state.visible_brows])
	print("FULL_LOGO_HELMET_VISIBILITY|%s"%("PASS" if valid else "FAIL"))
	visual.free()
	quit(0 if valid else 3)
