extends SceneTree

class FakeCaster:
    extends CharacterBody3D
    var staff_equipped:=false
    var mana:=100.0
    func has_magic_staff_equipped()->bool:return staff_equipped

func _initialize()->void:
    var hero_script:=load("res://scripts/HeroController.gd")
    var director_script:=load("res://scripts/GameplayDirector.gd")
    if hero_script==null or director_script==null:
        push_error("STAFF_VERIFY|script_load_failed");quit(1);return
    var staff_scene:=load("res://assets/equipment/royal_vanguard_staff.glb") as PackedScene
    if staff_scene==null:push_error("STAFF_VERIFY|standalone_glb_missing");quit(7);return
    var staff_instance:=staff_scene.instantiate();var standalone_meshes:=_count_meshes(staff_instance)
    if standalone_meshes<60:push_error("STAFF_VERIFY|standalone_meshes=%d"%standalone_meshes);quit(8);return
    var hero=hero_script.new()
    hero.call("give_knight_armor")
    hero.call("give_royal_staff")
    var bag:Array=hero.get("bag_slots")
    var slots_initial:Dictionary=hero.get("equipment_slots")
    if not slots_initial.has("pants") or not bag.any(func(item):return item.get("id","")=="royal_pants" and item.get("slot","")=="pants"):
        push_error("STAFF_VERIFY|pants_slot_or_item_missing");quit(9);return
    if not bag.any(func(item):return item.get("id","")=="royal_vanguard_staff"):
        push_error("STAFF_VERIFY|staff_not_granted");quit(2);return
    if hero.call("has_magic_staff_equipped"):
        push_error("STAFF_VERIFY|staff_should_start_unequipped");quit(3);return
    var slots:Dictionary=hero.get("equipment_slots");slots.mainhand={"id":"royal_vanguard_staff"};hero.set("equipment_slots",slots)
    if not hero.call("has_magic_staff_equipped"):
        push_error("STAFF_VERIFY|equip_check_failed");quit(4);return

    var director=director_script.new();director.process_mode=Node.PROCESS_MODE_DISABLED
    var caster:=FakeCaster.new();director.set("player",caster)
    root.add_child(caster);root.add_child(director);await process_frame
    var mana_before:=caster.mana
    director.call("_cast_spark")
    if caster.mana!=mana_before or float(director.get("_magic_requirement_time"))<=0.0:
        push_error("STAFF_VERIFY|magic_was_not_blocked");quit(5);return
    caster.staff_equipped=true
    if not director.call("_require_magic_staff"):
        push_error("STAFF_VERIFY|equipped_staff_not_accepted");quit(6);return
    print("STAFF_VERIFY|PASS|standalone_meshes=%d|pants_slot=true|pants_item=true|bag=true|starts_unequipped=true|blocked_without_staff=true|accepted_with_staff=true"%standalone_meshes)
    staff_instance.free();hero.free();director.queue_free();caster.queue_free();await process_frame
    quit(0)

func _count_meshes(node:Node)->int:
    var total:=1 if node is MeshInstance3D else 0
    for child in node.get_children():total+=_count_meshes(child)
    return total
