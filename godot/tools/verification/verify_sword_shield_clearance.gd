extends SceneTree


func _find_skeleton(node:Node)->Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found:=_find_skeleton(child)
		if found:
			return found
	return null


func _mesh_world_aabb(node:Node)->AABB:
	var result:=AABB()
	var found:=false
	if node is MeshInstance3D:
		var mesh_instance:=node as MeshInstance3D
		if mesh_instance.mesh:
			var local_box:=mesh_instance.mesh.get_aabb()
			var low:=Vector3(INF,INF,INF)
			var high:=Vector3(-INF,-INF,-INF)
			for x in [local_box.position.x,local_box.end.x]:
				for y in [local_box.position.y,local_box.end.y]:
					for z in [local_box.position.z,local_box.end.z]:
						var point:=mesh_instance.global_transform*Vector3(x,y,z)
						low=low.min(point)
						high=high.max(point)
			result=AABB(low,high-low)
			found=true
	for child in node.get_children():
		var child_box:=_mesh_world_aabb(child)
		if child_box.size.length_squared()<=0.0:
			continue
		if found:
			result=result.merge(child_box)
		else:
			result=child_box
			found=true
	return result if found else AABB()


func _aabb_gap(a:AABB,b:AABB)->float:
	var separation:=Vector3(
		maxf(0.0,maxf(a.position.x-b.end.x,b.position.x-a.end.x)),
		maxf(0.0,maxf(a.position.y-b.end.y,b.position.y-a.end.y)),
		maxf(0.0,maxf(a.position.z-b.end.z,b.position.z-a.end.z))
	)
	return separation.length()


func _point_aabb_distance(point:Vector3,box:AABB)->float:
	var closest:=Vector3(
		clampf(point.x,box.position.x,box.end.x),
		clampf(point.y,box.position.y,box.end.y),
		clampf(point.z,box.position.z,box.end.z)
	)
	return point.distance_to(closest)


func _initialize()->void:
	call_deferred("_run")


func _run()->void:
	var visual:=Node3D.new()
	visual.name="SwordShieldClearanceVerification"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	root.add_child(visual)
	for _index in range(12):
		await process_frame
	visual.call("set_equipment_pieces",{
		"mainhand":{"id":"royal_vanguard_sword"},
		"offhand":{"id":"royal_vanguard_shield"},
	})
	for _index in range(8):
		await process_frame
	visual.call("play_action","sword")
	var skeleton:=_find_skeleton(visual)
	var head_bone:=skeleton.find_bone(&"head")
	var minimum_gap:=INF
	var minimum_head_gap:=INF
	var failed:=false
	for sample in range(21):
		var phase:=float(sample)/20.0
		visual.set("_action_kind","sword")
		visual.set("_action_time",maxf(.0001,.62*(1.0-phase)))
		visual.call("_update_warrior_weapon_action")
		await process_frame
		var sword:Node3D=visual.get("_sword_root")
		var shield:Node3D=visual.get("_shield_root")
		var sword_box:=_mesh_world_aabb(sword)
		var shield_box:=_mesh_world_aabb(shield)
		var gap:=_aabb_gap(sword_box,shield_box)
		var head_center:=skeleton.to_global(skeleton.get_bone_global_pose(head_bone).origin)+Vector3.UP*.085
		var head_gap:=_point_aabb_distance(head_center,sword_box)-.105
		minimum_gap=minf(minimum_gap,gap)
		minimum_head_gap=minf(minimum_head_gap,head_gap)
		var overlap:=sword_box.intersects(shield_box)
		var head_overlap:=head_gap<0.0
		failed=failed or overlap or head_overlap
		print("SWORD_SHIELD_SAMPLE|phase=%.2f|gap=%.4f|overlap=%s|head_gap=%.4f|head_overlap=%s|sword=%s|shield=%s|blade=%s|grip=%s"%[
			phase,gap,overlap,head_gap,head_overlap,sword_box.get_center(),shield_box.get_center(),sword.global_basis.y.normalized(),sword.global_position,
		])
	print("SWORD_SHIELD_CLEARANCE|%s|min_gap=%.4f|min_head_gap=%.4f"%[
		"FAIL" if failed else "PASS",minimum_gap,minimum_head_gap,
	])
	visual.free()
	quit(1 if failed else 0)
