extends SceneTree

class FakeHero:
    extends CharacterBody3D
    var interior:=false
    func set_interior_mode(enabled:bool)->void:interior=enabled

func _initialize()->void:
    var director_script:=load("res://scripts/GameplayDirector.gd")
    if director_script==null:push_error("CAVE_ENTRY|script_missing");quit(1);return
    var director:=Node3D.new();director.set_script(director_script);director.process_mode=Node.PROCESS_MODE_DISABLED
    var hero:=FakeHero.new();root.add_child(hero);root.add_child(director);await process_frame
    director.set("player",hero)
    var surface:=Vector3(100.0,4.0,200.0);var destination:=Vector3(8200.0,-95.88,50.0)
    director.call("_register_portal",surface,destination,"Enter Cave",true,10.5,true,true,8.0)
    hero.global_position=surface+Vector3(0,20.0,7.5)
    director.call("_tick_auto_portal")
    print("CAVE_ENTRY|position=%s|interior=%s|cooldown=%.2f"%[hero.global_position,hero.interior,float(director.get("_portal_cooldown"))])
    if hero.global_position.distance_to(destination)>.01 or not hero.interior or float(director.get("_portal_cooldown"))<.9:
        push_error("CAVE_ENTRY|auto_transition_failed");quit(2);return
    hero.queue_free();director.queue_free();await process_frame
    print("CAVE_ENTRY|PASS")
    quit(0)
