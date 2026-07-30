extends SceneTree

const REQUIRED_ANIMATIONS := ["Idle", "Run", "Attack", "Hit", "Death"]

class FakeHero:
    extends CharacterBody3D
    var hp := 500.0
    var max_hp := 500.0
    var mana := 100.0
    var max_mana := 100.0
    var hero_gold := 0
    var health_potions := 0
    var enemies_defeated := 0
    var elites_defeated := 0
    var relic_shards := 0
    var bag_slots: Array = []
    var materials := {"leather": 0, "crystal": 0, "ore": 0, "essence": 0}

    func get_equipment_state() -> Dictionary:
        return {"armor": 0}

    func give_xp(_amount: int) -> void:
        pass

    func add_material(kind: String, amount: int) -> void:
        materials[kind] = int(materials.get(kind, 0)) + amount

    func add_bag_item(item: Dictionary) -> void:
        bag_slots.append(item)


func _find_animator(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animator(child)
        if found:
            return found
    return null


func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null


func _count_meshes(node: Node) -> int:
    var count := 1 if node is MeshInstance3D else 0
    for child in node.get_children():
        count += _count_meshes(child)
    return count


func run_test() -> void:
    var scene := load("res://assets/enemies/ashfang_hound.glb") as PackedScene
    if scene == null:
        push_error("ASHFANG_VERIFY|asset_missing")
        quit(1)
        return
    var asset := scene.instantiate()
    root.add_child(asset)
    var animator := _find_animator(asset)
    var skeleton := _find_skeleton(asset)
    var missing: Array[String] = []
    if animator:
        for clip in REQUIRED_ANIMATIONS:
            if not animator.has_animation(clip):
                missing.append(clip)
    else:
        missing.assign(REQUIRED_ANIMATIONS)
    var asset_ok := skeleton != null and skeleton.get_bone_count() >= 18 and _count_meshes(asset) >= 1 and missing.is_empty()

    var hero := FakeHero.new()
    hero.name = "AshfangTestHero"
    root.add_child(hero)
    var director := Node3D.new()
    director.name = "AshfangTestDirector"
    director.set_script(load("res://scripts/GameplayDirector.gd"))
    director.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(director)
    await process_frame
    director.player = hero
    director.height_sampler = func(x: float, z: float): return Vector3(x, 0.0, z)
    director.walkable_sampler = func(_x: float, _z: float): return true
    director.safe_zone_center = Vector2(9999.0, 9999.0)
    director._spawn_ashfang(12.0, 0.0, false)
    director._spawn_ashfang(15.0, -0.08, true)
    director._spawn_ashfang(17.0, 0.10, true)
    var leaders := 0
    var runts := 0
    var leader: Dictionary = {}
    for enemy in director.minions:
        if enemy.get("kind", "") == "ashfang":
            leaders += 1
            leader = enemy
        elif enemy.get("kind", "") == "ashfang_runt":
            runts += 1
    var spawn_ok := leaders == 1 and runts == 2 and not leader.is_empty()

    var run_ok := false
    var attack_ok := false
    if spawn_ok:
        var leader_node := leader.get("node") as Node3D
        var start_distance: float = leader_node.global_position.distance_to(hero.global_position)
        director._tick_minions(0.20)
        var leader_anim := leader.get("animation") as AnimationPlayer
        run_ok = is_instance_valid(leader_anim) and leader_anim.current_animation == "Run" and leader_node.global_position.distance_to(hero.global_position) < start_distance
        leader_node.global_position = Vector3(1.8, 0.0, 0.0)
        leader.attack = 0.0
        leader.windup = 0.0
        leader.anim_lock = 0.0
        director._tick_minions(0.10)
        attack_ok = leader_anim.current_animation == "Attack" and float(leader.get("windup", 0.0)) > 0.0

    director._quest_claimed["road_imps"] = true
    director._gathered_counts["ashfangs"] = 10
    director._check_quest_rewards()
    var quest_ok := bool(director._quest_claimed.get("ashfang_packs", false)) and hero.hero_gold == 80 and int(hero.materials.get("leather", 0)) == 6
    var passed := asset_ok and spawn_ok and run_ok and attack_ok and quest_ok
    print("ASHFANG_VERIFY|%s|bones=%d|meshes=%d|missing=%s|leaders=%d|runts=%d|run=%s|attack=%s|quest=%s" % [
        "PASS" if passed else "FAIL",
        skeleton.get_bone_count() if skeleton else 0,
        _count_meshes(asset),
        ",".join(missing),
        leaders,
        runts,
        run_ok,
        attack_ok,
        quest_ok,
    ])
    quit(0 if passed else 2)


func _initialize() -> void:
    call_deferred("run_test")
