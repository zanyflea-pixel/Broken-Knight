extends SceneTree


const SWORD_SCENE:=preload("res://assets/equipment/royal_vanguard_sword.glb")


func _initialize()->void:
	var holder:=Node3D.new()
	root.add_child(holder)
	var sword:=SWORD_SCENE.instantiate() as Node3D
	holder.add_child(sword)
	await process_frame
	var minimum:=Vector3(INF,INF,INF)
	var maximum:=Vector3(-INF,-INF,-INF)
	var stack:Array[Node]=[sword]
	while not stack.is_empty():
		var node:Node=stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node:=node as MeshInstance3D
			var box:=mesh_node.get_aabb()
			for corner_index in range(8):
				var corner:=Vector3(
					box.position.x+box.size.x*(corner_index&1),
					box.position.y+box.size.y*((corner_index>>1)&1),
					box.position.z+box.size.z*((corner_index>>2)&1)
				)
				var point:=sword.to_local(mesh_node.to_global(corner))
				minimum=minimum.min(point)
				maximum=maximum.max(point)
		for child in node.get_children():
			stack.append(child)
	print("SWORD_LOCAL_BOUNDS|min=%s|max=%s|size=%s"%[minimum,maximum,maximum-minimum])
	print("SWORD_ROOT_TRANSFORM|%s"%sword.transform)
	quit(0)
