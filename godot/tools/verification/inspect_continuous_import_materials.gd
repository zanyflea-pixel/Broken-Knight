extends SceneTree

const LIVE := preload("res://assets/hero/hero_full_continuous_body.glb")
const CANDIDATE := preload("res://assets/hero/hero_full_continuous_correction_candidate.glb")


func _initialize() -> void:
	inspect_scene("LIVE", LIVE.instantiate())
	inspect_scene("CANDIDATE", CANDIDATE.instantiate())
	quit(0)


func inspect_scene(label: String, scene: Node) -> void:
	root.add_child(scene)
	print("IMPORT_INSPECT|%s|BEGIN" % label)
	inspect_node(label, scene)
	print("IMPORT_INSPECT|%s|END" % label)
	scene.queue_free()


func inspect_node(label: String, node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		var surfaces := mesh.get_surface_count() if mesh != null else 0
		print("IMPORT_MESH|%s|%s|surfaces=%d|aabb=%s" % [label, mesh_node.name, surfaces, str(mesh_node.get_aabb())])
		for surface in range(surfaces):
			var material := mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var base := material as BaseMaterial3D
				print("IMPORT_MAT|%s|%s|%d|name=%s|color=%s|cull=%d|transparency=%d" % [label, mesh_node.name, surface, material.resource_name, str(base.albedo_color), base.cull_mode, base.transparency])
			else:
				print("IMPORT_MAT|%s|%s|%d|%s" % [label, mesh_node.name, surface, str(material)])
	for child in node.get_children():
		inspect_node(label, child)
