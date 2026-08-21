extends SceneTree

const HERO_PATH := "res://assets/hero/hero_full_continuous_body.glb"

func collect(node: Node, skeletons: Array, players: Array, meshes: Array) -> void:
	if node is Skeleton3D: skeletons.append(node)
	if node is AnimationPlayer: players.append(node)
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): collect(child, skeletons, players, meshes)

func _initialize() -> void:
	var packed := load(HERO_PATH) as PackedScene
	if packed == null:
		push_error("FULL_HERO_CANDIDATE|load_failed")
		quit(2)
		return
	var hero := packed.instantiate()
	var skeletons: Array = []
	var players: Array = []
	var meshes: Array = []
	collect(hero, skeletons, players, meshes)
	if skeletons.size() != 1 or players.is_empty():
		push_error("FULL_HERO_CANDIDATE|rig_or_player_missing")
		quit(3)
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	var required := ["Idle", "Walk", "Jump", "Land", "Roll", "SwordSlash", "Death"]
	var missing := required.filter(func(name): return not player.has_animation(name))
	var body_meshes := meshes.filter(func(mesh): return String(mesh.name).begins_with("ConnectedBody"))
	var hair_meshes := meshes.filter(func(mesh): return String(mesh.name).begins_with("HeroHair"))
	var loin_meshes := meshes.filter(func(mesh): return String(mesh.name).begins_with("Loincloth"))
	if not missing.is_empty() or body_meshes.size() != 1 or hair_meshes.size() < 2 or loin_meshes.size() < 3:
		push_error("FULL_HERO_CANDIDATE|content_missing|%s" % [missing])
		quit(4)
		return
	var thigh := skeleton.find_bone("thigh.L")
	var head := skeleton.find_bone("head")
	if thigh < 0 or head < 0:
		push_error("FULL_HERO_CANDIDATE|required_bones_missing")
		quit(5)
		return
	var walk := player.get_animation("Walk")
	print("FULL_HERO_CANDIDATE|walk_tracks=%d|length=%.4f|names=%s" % [walk.get_track_count(), walk.length, player.get_animation_list()])
	for index in mini(8, walk.get_track_count()): print("FULL_HERO_TRACK|%d|%s" % [index, walk.track_get_path(index)])
	var thigh_track := -1
	for index in walk.get_track_count():
		if String(walk.track_get_path(index)).ends_with(":thigh.L"): thigh_track = index
	if thigh_track < 0:
		push_error("FULL_HERO_CANDIDATE|walk_thigh_track_missing")
		quit(6)
		return
	var key_count := walk.track_get_key_count(thigh_track)
	if key_count < 1:
		push_error("FULL_HERO_CANDIDATE|walk_thigh_keys_missing")
		quit(7)
		return
	var delta := float(key_count)
	print("FULL_HERO_CANDIDATE|PASS|bones=%d|meshes=%d|animations=%d|walk_delta=%.5f|hair=%d|loin=%d" % [skeleton.get_bone_count(), meshes.size(), player.get_animation_list().size(), delta, hair_meshes.size(), loin_meshes.size()])
	hero.free()
	quit(0)
