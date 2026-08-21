extends SceneTree

const CANDIDATE := preload("res://assets/hero/hero_full_continuous_correction_candidate.glb")


func _initialize() -> void:
	var hero := CANDIDATE.instantiate()
	root.add_child(hero)
	var skeleton := find_skeleton(hero)
	var player := find_animation_player(hero)
	if skeleton == null or player == null:
		push_error("Correction candidate is missing its skeleton or AnimationPlayer")
		quit(2)
		return
	var required := [&"Idle", &"Walk", &"Jump", &"Land", &"Roll"]
	for animation_name in required:
		if not player.has_animation(animation_name):
			push_error("Correction candidate missing %s" % animation_name)
			quit(3)
			return
	var walk := player.get_animation(&"Walk")
	var moving_tracks := 0
	for track in range(walk.get_track_count()):
		if walk.track_get_key_count(track) < 2:
			continue
		var first = walk.track_get_key_value(track, 0)
		for key in range(1, walk.track_get_key_count(track)):
			if walk.track_get_key_value(track, key) != first:
				moving_tracks += 1
				break
	if moving_tracks < 10:
		push_error("Walk imported but is effectively static: %d moving tracks" % moving_tracks)
		quit(4)
		return
	print("CORRECTION_CANDIDATE_PASS|bones=%d|animations=%d|walk_tracks=%d|moving_tracks=%d" % [skeleton.get_bone_count(), player.get_animation_list().size(), walk.get_track_count(), moving_tracks])
	quit(0)


func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null
