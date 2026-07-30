extends SceneTree

func _initialize()->void:
    call_deferred("run_test")

func find_player(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node
    for child in node.get_children():
        var found:=find_player(child)
        if found!=null:return found
    return null

func run_test()->void:
    var hero_script:=load("res://scripts/HeroController.gd")
    var visual_script:=load("res://scripts/HeroVisual.gd")
    if hero_script==null or visual_script==null:push_error("ROLL_GAMEPLAY|scripts_missing");quit(1);return
    var hero:=CharacterBody3D.new();hero.name="Player"
    var visual:=Node3D.new();visual.name="Visual";visual.set_script(visual_script);hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot)
    var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring)
    var camera:=Camera3D.new();camera.name="Camera3D";spring.add_child(camera)
    hero.set_script(hero_script);root.add_child(hero)
    await process_frame;await process_frame
    hero.call("set_input_enabled",false)
    hero.call("_start_roll",Vector3.RIGHT)
    var player:=find_player(hero)
    var direction:Vector3=hero.get("_roll_dir")
    var duration:float=hero.get("_roll_time")
    var cooldown:float=hero.get("_roll_cooldown")
    var animation:=String(player.current_animation) if player!=null else ""
    print("ROLL_GAMEPLAY|direction=%s|duration=%.3f|cooldown=%.3f|animation=%s"%[direction,duration,cooldown,animation])
    if direction.distance_to(Vector3.RIGHT)>.001 or duration<.70 or cooldown<=duration or animation!="Roll":
        push_error("ROLL_GAMEPLAY|state_failed");quit(2);return
    hero.queue_free();await process_frame
    print("ROLL_GAMEPLAY|PASS")
    quit(0)
