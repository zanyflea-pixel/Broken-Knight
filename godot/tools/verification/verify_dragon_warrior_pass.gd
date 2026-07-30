extends SceneTree

func _initialize()->void:
    call_deferred("run_test")

func find_named(node:Node,target:String)->Node:
    if node.name==target:return node
    for child in node.get_children():
        var found:=find_named(child,target)
        if found:return found
    return null

func find_animator(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node
    for child in node.get_children():
        var found:=find_animator(child)
        if found:return found
    return null

func crest_is_front_and_flush(shield:Node)->bool:
    var crest:=find_named(shield,"FlushRealmCrest")
    if crest is not MeshInstance3D:return false
    var bounds: AABB=(crest as MeshInstance3D).get_aabb()
    # The Blender crest is one 6 mm repoussé mesh on the outward (+Z) face.
    return bounds.size.z<=.012 and bounds.get_center().z>.070

func run_test()->void:
    var hero:=CharacterBody3D.new();hero.name="Player"
    var visual:=Node3D.new();visual.name="Visual";visual.set_script(load("res://scripts/HeroVisual.gd"));hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot)
    var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring)
    var camera:=Camera3D.new();camera.name="Camera3D";spring.add_child(camera)
    hero.set_script(load("res://scripts/HeroController.gd"));root.add_child(hero)
    var director:=Node3D.new();director.name="GameplayDirector";director.set_script(load("res://scripts/GameplayDirector.gd"));root.add_child(director)
    director.player=hero;director.height_sampler=func(x:float,z:float):return Vector3(x,0,z);director.walkable_sampler=func(_x:float,_z:float):return true
    director._build_cavern_dungeon(Vector3(8200,-96,0),3,"WEST CAVERN")
    director._build_cavern_dungeon(Vector3(8420,-112,0),4,"EAST CAVERN")
    var admin:=Control.new();admin.set_script(load("res://scripts/AdminMenu.gd"));root.add_child(admin);admin.configure(Node.new(),director)
    for i in range(4):await process_frame
    var dragons:=0
    var imps_in_dungeons:=0
    for enemy in director.minions:
        if enemy.get("kind","")=="dragon":dragons+=1
        elif enemy.get("dungeon",false):imps_in_dungeons+=1
    var class_before:String=hero.active_class
    if hero.active_class!="Warrior":
        director.admin_switch_class()
    await process_frame
    var warrior_ok:bool=hero.active_class=="Warrior" and hero.has_warrior_weapons_equipped()
    var sword=find_named(hero,"RoyalVanguardSword")
    var shield=find_named(hero,"RoyalVanguardShield")
    var visible_ok:bool=is_instance_valid(sword) and sword.visible and is_instance_valid(shield) and shield.visible
    visual._update_warrior_weapon_action()
    var shield_upright:bool=is_instance_valid(shield) and shield.global_basis.y.normalized().dot(Vector3.UP)>.97
    var sword_upright:bool=is_instance_valid(sword) and sword.global_basis.y.normalized().dot(Vector3.UP)>.96
    var crest_ok:=is_instance_valid(shield) and crest_is_front_and_flush(shield)
    var animator:=find_animator(hero);var warrior_clips_ok:=is_instance_valid(animator) and animator.has_animation("WarriorIdle") and animator.has_animation("WarriorWalk") and animator.has_animation("SwordSlash") and animator.has_animation("ShieldBash") and animator.has_animation("Death")
    visual.play_action("sword");await process_frame
    var sword_clip_ok:bool=is_instance_valid(animator) and animator.current_animation=="SwordSlash"
    visual.play_action("shield");await process_frame
    var shield_clip_ok:bool=is_instance_valid(animator) and animator.current_animation=="ShieldBash"
    var boss_chests:=0
    var first_boss_chest:Dictionary={}
    for portal in director._portals:
        if portal.get("action","")=="chest" and not String(portal.get("boss_gate","")).is_empty():
            boss_chests+=1
            if first_boss_chest.is_empty():first_boss_chest=portal
    director._loot_dungeon_chest(first_boss_chest)
    var locked_ok:bool=not first_boss_chest.get("looted",false)
    var gate_id:String=first_boss_chest.get("boss_gate","")
    for enemy in director.minions:
        if enemy.get("boss_id","")==gate_id:director._damage(enemy,999999.0);break
    director._loot_dungeon_chest(first_boss_chest)
    var unlock_ok:bool=first_boss_chest.get("looted",false)
    var caves_ok:bool=director.has_node("WestCavern") and director.has_node("EastCavern")
    print("DRAGON_WARRIOR|class_before=%s|class_after=%s|warrior=%s|weapons_visible=%s|shield_upright=%s|sword_upright=%s|crest_front_flush=%s|warrior_clips=%s|sword_clip=%s|shield_clip=%s|dragons=%d|dungeon_imps=%d|boss_chests=%d|locked=%s|unlocked=%s|caves=%s|admin=%s"%[class_before,hero.active_class,warrior_ok,visible_ok,shield_upright,sword_upright,crest_ok,warrior_clips_ok,sword_clip_ok,shield_clip_ok,dragons,imps_in_dungeons,boss_chests,locked_ok,unlock_ok,caves_ok,is_instance_valid(admin)])
    if warrior_ok and visible_ok and shield_upright and sword_upright and crest_ok and warrior_clips_ok and sword_clip_ok and shield_clip_ok and dragons==2 and imps_in_dungeons>=20 and boss_chests==2 and locked_ok and unlock_ok and caves_ok and is_instance_valid(admin):
        print("DRAGON_WARRIOR_VERIFY|PASS")
        quit(0)
    else:
        print("DRAGON_WARRIOR_VERIFY|FAIL")
        quit(1)
