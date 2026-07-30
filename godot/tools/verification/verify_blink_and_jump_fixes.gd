extends SceneTree

func _initialize()->void:call_deferred("run_test")

func _make_hero()->CharacterBody3D:
    var hero:=CharacterBody3D.new();hero.name="Player"
    var visual:=Node3D.new();visual.name="Visual";visual.set_script(load("res://scripts/HeroVisual.gd"));hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot)
    var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring)
    var camera:=Camera3D.new();camera.name="Camera3D";spring.add_child(camera)
    hero.set_script(load("res://scripts/HeroController.gd"));return hero

func run_test()->void:
    var hero:=_make_hero();root.add_child(hero);await process_frame;await process_frame
    hero.equip_royal_armor()
    var director:=Node3D.new();director.set_script(load("res://scripts/GameplayDirector.gd"));root.add_child(director);director.player=hero;director.height_sampler=func(x:float,z:float):return Vector3(x,0,z);director.walkable_sampler=func(_x:float,_z:float):return true
    hero.global_position=Vector3.ZERO;hero.get_node("Visual").rotation.y=0.0
    var start:=hero.global_position;director._cast_blink();var traveled:=Vector2(hero.global_position.x-start.x,hero.global_position.z-start.z).length()
    var sparkles:=0
    for child in director.get_children():
        if child is MeshInstance3D:sparkles+=1
    # A bridge/arch top two metres overhead must not become the hero's ground.
    var overhead:=StaticBody3D.new();overhead.position=Vector3(0,2.0,0);root.add_child(overhead)
    var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(5,.25,5);collision.shape=shape;overhead.add_child(collision)
    await physics_frame
    hero.configure_world(func(x:float,z:float):return Vector3(x,0,z),Vector3.ZERO,func(_x:float,_z:float):return true)
    var resolved:Vector3=hero._resolve_ground_position(Vector3.ZERO)
    var jump_safe:=resolved.y<.90
    print("BLINK_JUMP|travel=%.2f|sparkles=%d|resolved_y=%.2f|jump_safe=%s"%[traveled,sparkles,resolved.y,jump_safe])
    if traveled>=17.5 and sparkles>=18 and jump_safe:print("BLINK_JUMP_VERIFY|PASS");quit(0)
    else:print("BLINK_JUMP_VERIFY|FAIL");quit(1)
