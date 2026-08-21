extends SceneTree

const CANDIDATE_PATH := "res://assets/hero/hero_anatomical_glute_rebuild_candidate.glb"


func collect(node: Node, skeletons: Array, players: Array, meshes: Array) -> void:
	if node is Skeleton3D: skeletons.append(node)
	if node is AnimationPlayer: players.append(node)
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): collect(child, skeletons, players, meshes)


func _initialize() -> void:
	var scene := load(CANDIDATE_PATH) as PackedScene
	if scene == null:
		push_error("HERO_LAYER_REFINEMENT|candidate_load_failed")
		quit(2)
		return
	var hero := scene.instantiate()
	var skeletons: Array = []
	var players: Array = []
	var meshes: Array = []
	collect(hero, skeletons, players, meshes)
	if skeletons.size() != 1 or players.size() != 1:
		push_error("HERO_LAYER_REFINEMENT|rig_or_player_count")
		quit(3)
		return
	var player := players[0] as AnimationPlayer
	var required := [&"Idle", &"Walk", &"TorchWalk", &"StaffWalk", &"WarriorWalk"]
	var missing := required.filter(func(name): return not player.has_animation(name))
	var hair := meshes.filter(func(mesh): return String(mesh.name).begins_with("HeroHair"))
	var brows := meshes.filter(func(mesh): return String(mesh.name).begins_with("ProfessionalBrows"))
	var loin := meshes.filter(func(mesh): return String(mesh.name).begins_with("Loincloth"))
	var textured_hair := 0
	var textured_loin := 0
	for mesh_node in hair:
		var mesh := (mesh_node as MeshInstance3D).mesh
		if mesh.get_surface_count() > 0:
			var material := mesh.surface_get_material(0) as BaseMaterial3D
			if material != null and (material.albedo_texture != null or material.normal_texture != null):
				textured_hair += 1
	for mesh_node in loin:
		var mesh := (mesh_node as MeshInstance3D).mesh
		if mesh.get_surface_count() > 0:
			var material := mesh.surface_get_material(0) as BaseMaterial3D
			if material != null and (material.albedo_texture != null or material.normal_texture != null):
				textured_loin += 1
	var walk := player.get_animation(&"Walk")
	var thigh_tracks := 0
	for track in walk.get_track_count():
		if String(walk.track_get_path(track)).contains("thigh."):
			thigh_tracks += 1
	print("HERO_LAYER_REFINEMENT|animations=%d|hair=%d,%d|brows=%d|loin=%d,%d|walk=%.3f,%d" % [player.get_animation_list().size(), hair.size(), textured_hair, brows.size(), loin.size(), textured_loin, walk.length, thigh_tracks])
	if not missing.is_empty() or player.get_animation_list().size() != 23 or hair.size() < 3 or textured_hair < 1 or brows.size() < 2 or loin.size() < 3 or textured_loin < 2 or walk.length < 0.75 or thigh_tracks < 2:
		push_error("HERO_LAYER_REFINEMENT|content_failed|missing=%s" % [missing])
		quit(4)
		return
	print("HERO_LAYER_REFINEMENT|PASS")
	hero.free()
	quit(0)
