extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var director:Node=main.get_node("GameplayDirector")
    var player:CharacterBody3D=main.get_node("Player")

    if not director.admin_toggle_one_hit_kill():
        failures.append("one-hit toggle did not enable")
    var target:Dictionary={}
    for enemy in director.minions:
        if not enemy.get("dead",false):
            target=enemy
            break
    if target.is_empty():
        failures.append("no enemy available")
    else:
        director._damage(target,1.0)
        if not target.get("dead",false):
            failures.append("one-hit mode did not kill")
    if director.admin_toggle_one_hit_kill():
        failures.append("one-hit toggle did not disable")

    player.hp=50.0
    if not director.admin_toggle_god_mode():
        failures.append("god-mode toggle did not enable")
    var protected_hp:float=player.hp
    director._damage_player(25.0)
    if not is_equal_approx(player.hp,protected_hp):
        failures.append("god mode allowed damage")
    if director.admin_toggle_god_mode():
        failures.append("god-mode toggle did not disable")
    director._damage_player(5.0)
    if not player.hp<protected_hp:
        failures.append("damage remained blocked after disabling god mode")

    var status:Dictionary=director.get_admin_status()
    if status.get("one_hit_kill",true) or status.get("god_mode",true):
        failures.append("admin status did not report disabled modes")
    print("ADMIN_COMBAT_MODES|one_hit=ok|god_mode=ok|failures=%d"%failures.size())
    for failure in failures:push_error(failure)
    main.free()
    quit(0 if failures.is_empty() else 1)
