extends SceneTree

func find_animator(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node
    for child in node.get_children():
        var found:=find_animator(child)
        if found:return found
    return null

func find_skeleton(node:Node)->Skeleton3D:
    if node is Skeleton3D:return node as Skeleton3D
    for child in node.get_children():
        var found:=find_skeleton(child)
        if found:return found
    return null

func run_test()->void:
    var hero:=CharacterBody3D.new();hero.name="DeathTestHero"
    var visual:=Node3D.new();visual.name="Visual";visual.set_script(load("res://scripts/HeroVisual.gd"));hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot)
    var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring)
    var camera:=Camera3D.new();camera.name="Camera3D";spring.add_child(camera)
    hero.set_script(load("res://scripts/HeroController.gd"));root.add_child(hero)
    var director:=Node3D.new();director.name="DeathDirector";director.set_script(load("res://scripts/GameplayDirector.gd"));director.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(director)
    for i in range(4):await process_frame
    director.player=hero;director.height_sampler=func(x:float,z:float):return Vector3(x,0,z);director.walkable_sampler=func(_x:float,_z:float):return true;director.safe_zone_center=Vector2(9999,9999)
    visual.play_death();await process_frame
    var hero_anim:=find_animator(hero)
    var hero_ok:=is_instance_valid(hero_anim) and hero_anim.current_animation=="Death" and hero_anim.get_animation("Death").loop_mode==Animation.LOOP_NONE
    director._spawn_minion(10.0,0.0,Vector3(10,0,0),1,Rect2())
    director._spawn_bramble_wraith(14.0,.4)
    director._spawn_dragon(Vector3(22,0,0),2,Rect2(Vector2(-100,-100),Vector2(200,200)),"DEATH_TEST")
    var imp:Dictionary={};var wraith:Dictionary={};var dragon:Dictionary={}
    for enemy in director.minions:
        if enemy.get("kind","")=="dragon":dragon=enemy
        elif enemy.get("kind","")=="bramble_wraith":wraith=enemy
        elif imp.is_empty():imp=enemy
    director._tick_dragon(dragon,.5,false)
    var dragon_visual:=dragon.node.get_node("DragonVisual") as Node3D
    var dragon_anim:=dragon.get("animation") as AnimationPlayer
    var dragon_skeleton:=find_skeleton(dragon_visual)
    var gait_bone:=dragon_skeleton.find_bone("thigh.L") if dragon_skeleton else -1
    var gait_clip:String=dragon_anim.current_animation if dragon_anim else "none"
    var gait_angle:=0.0
    var dragon_gait_ok:=is_instance_valid(dragon_anim) and dragon_anim.current_animation=="Walk" and gait_bone>=0
    if dragon_gait_ok:
        dragon_anim.play("Walk",0.0)
        dragon_anim.seek(0.0,true)
        await process_frame
        var gait_start:=dragon_skeleton.get_bone_pose(gait_bone)
        dragon_anim.seek(.50,true)
        await process_frame
        var gait_mid:=dragon_skeleton.get_bone_pose(gait_bone)
        gait_angle=gait_start.basis.get_rotation_quaternion().angle_to(gait_mid.basis.get_rotation_quaternion())
        dragon_gait_ok=gait_angle>.08
    director._damage(imp,99999.0);director._damage(wraith,99999.0);director._damage(dragon,99999.0)
    var imp_anim:=imp.get("animation") as AnimationPlayer
    var imp_ok:=is_instance_valid(imp_anim) and imp_anim.current_animation=="Death"
    director._tick_enemy_death(wraith,.8);director._tick_enemy_death(dragon,1.0)
    var wraith_visual:=wraith.node.get_node("WraithVisual") as Node3D
    var wraith_ok:=absf(wraith_visual.rotation.z)>.05 and wraith_visual.scale.y<.95
    var dragon_ok:=is_instance_valid(dragon_anim) and dragon_anim.current_animation=="Death" and dragon_anim.get_animation("Death").loop_mode==Animation.LOOP_NONE
    print("DEATH_COVERAGE|hero=%s|imp=%s|wraith=%s|dragon=%s|dragon_gait=%s|gait_clip=%s|gait_bone=%s|gait_angle=%.3f|hero_clip=%s|imp_clip=%s|dragon_clip=%s"%[hero_ok,imp_ok,wraith_ok,dragon_ok,dragon_gait_ok,gait_clip,dragon_skeleton.get_bone_name(gait_bone) if gait_bone>=0 else "none",gait_angle,hero_anim.current_animation if hero_anim else "none",imp_anim.current_animation if imp_anim else "none",dragon_anim.current_animation if dragon_anim else "none"])
    quit(0 if hero_ok and imp_ok and wraith_ok and dragon_ok and dragon_gait_ok else 1)

func _initialize()->void:
    call_deferred("run_test")
