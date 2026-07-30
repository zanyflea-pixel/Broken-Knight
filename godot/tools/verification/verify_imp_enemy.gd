extends SceneTree

const REQUIRED_ANIMATIONS := ["Idle", "Run", "Attack", "Hit", "Death"]

func _initialize() -> void:
    var gameplay_script := load("res://scripts/GameplayDirector.gd")
    if gameplay_script == null:
        push_error("IMP_VERIFY|GameplayDirector failed to compile")
        quit(1)
        return
    var scene := load("res://assets/enemies/imp_enemy.glb") as PackedScene
    if scene == null:
        push_error("IMP_VERIFY|GLB did not import")
        quit(1)
        return
    var instance := scene.instantiate()
    root.add_child(instance)
    var animation_player := _find_animation_player(instance)
    var skeleton := _find_skeleton(instance)
    var mesh_count := _count_meshes(instance)
    if animation_player == null or skeleton == null or mesh_count != 1:
        push_error("IMP_VERIFY|structure missing|animation=%s|skeleton=%s|meshes=%d" % [animation_player != null, skeleton != null, mesh_count])
        quit(1)
        return
    var names := Array(animation_player.get_animation_list())
    for clip in REQUIRED_ANIMATIONS:
        if not animation_player.has_animation(clip):
            push_error("IMP_VERIFY|missing animation=%s|found=%s" % [clip, names])
            quit(1)
            return
    var thigh:=skeleton.find_bone("thigh.L")
    animation_player.play("Idle");animation_player.advance(0.0)
    var run_before:=skeleton.get_bone_pose(thigh)
    animation_player.play("Run");animation_player.advance(.22)
    var run_after:=skeleton.get_bone_pose(thigh)
    var run_delta:=run_before.basis.get_rotation_quaternion().angle_to(run_after.basis.get_rotation_quaternion())
    var root_bone:=skeleton.find_bone("root")
    var death_before:=skeleton.get_bone_pose(root_bone)
    animation_player.play("Death");animation_player.advance(.75)
    var death_after:=skeleton.get_bone_pose(root_bone)
    var death_delta:=death_before.origin.distance_to(death_after.origin)+death_before.basis.get_rotation_quaternion().angle_to(death_after.basis.get_rotation_quaternion())
    if run_delta<.05 or death_delta<.15:
        push_error("IMP_VERIFY|animation did not deform rig|run=%.3f|death=%.3f"%[run_delta,death_delta])
        quit(1)
        return
    var gameplay := gameplay_script.new() as Node3D
    var fake_player := CharacterBody3D.new()
    gameplay.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(fake_player)
    root.add_child(gameplay)
    await process_frame
    gameplay.set("player", fake_player)
    gameplay.set("safe_zone_center", Vector2(9999.0,9999.0))
    gameplay.call("_spawn_minion", 10.0, 0.0)
    var spawned: Array = gameplay.get("minions")
    if spawned.size() != 1 or spawned[0].node.name != "Imp":
        push_error("IMP_VERIFY|Gameplay spawn replacement failed")
        quit(1)
        return
    var spawned_root := spawned[0].node as Node3D
    var spawned_visual := spawned_root.get_node("ImpVisual") as Node3D
    if not is_equal_approx(spawned_root.scale.x, .62) or not is_equal_approx(absf(spawned_visual.rotation.y), PI):
        push_error("IMP_VERIFY|scale/orientation failed|scale=%s|yaw=%s" % [spawned_root.scale, spawned_visual.rotation.y])
        quit(1)
        return
    gameplay.call("_tick_minions", .016)
    var spawned_player := spawned[0].get("animation") as AnimationPlayer
    if spawned_player == null or spawned_player.current_animation != "Run":
        push_error("IMP_VERIFY|Run state was not connected|current=%s" % (spawned_player.current_animation if spawned_player else "none"))
        quit(1)
        return
    if spawned_player.get_animation("Idle").loop_mode==Animation.LOOP_NONE or spawned_player.get_animation("Run").loop_mode==Animation.LOOP_NONE or spawned_player.get_animation("Death").loop_mode!=Animation.LOOP_NONE:
        push_error("IMP_VERIFY|animation loop modes incorrect")
        quit(1)
        return
    gameplay.call("_damage", spawned[0], 1.0, Vector3.FORWARD)
    if spawned_player.current_animation != "Hit":
        push_error("IMP_VERIFY|Hit state was not connected|current=%s" % spawned_player.current_animation)
        quit(1)
        return
    gameplay.call("_play_minion_animation",spawned[0],"Death",true)
    if spawned_player.current_animation!="Death":
        push_error("IMP_VERIFY|Death state was not connected|current=%s"%spawned_player.current_animation)
        quit(1)
        return
    print("IMP_VERIFY|PASS|bones=%d|consolidated_meshes=%d|animations=%s|run_delta=%.3f|death_delta=%.3f|gameplay=Run,Hit,Death|scale=.62|yaw=PI" % [skeleton.get_bone_count(), mesh_count, names,run_delta,death_delta])
    quit(0)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _count_meshes(node: Node) -> int:
    var total := 1 if node is MeshInstance3D else 0
    for child in node.get_children():
        total += _count_meshes(child)
    return total
