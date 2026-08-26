extends SceneTree

func _init()->void:call_deferred("_run")

func _run()->void:
    var hero:=CharacterBody3D.new();hero.name="Player"
    var visual:=Node3D.new();visual.name="Visual";visual.set_script(load("res://scripts/HeroVisual.gd"));hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot);var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring);var camera:=Camera3D.new();camera.name="Camera3D";spring.add_child(camera)
    hero.set_script(load("res://scripts/HeroController.gd"));root.add_child(hero)
    var director:=Node3D.new();director.set_script(load("res://scripts/GameplayDirector.gd"));root.add_child(director);director.player=hero;director.height_sampler=func(x:float,z:float):return Vector3(x,0,z);director.walkable_sampler=func(_x:float,_z:float):return true
    var menu:=Control.new();menu.set_script(load("res://scripts/HeroMenu.gd"));root.add_child(menu);await process_frame;menu.configure(hero,director);await process_frame
    var bag_ok:bool=menu.bag_root.get_child_count()==80 and menu.bag_root.columns==4
    # Eight armor/weapon slots plus two ring slots must all remain visible
    # without turning the equipment column into a scrolling list.
    var equipment_ok:bool=menu.slots_root.get_child_count()==10 and not menu.slots_root.get_parent() is ScrollContainer
    var no_crafting:bool=not FileAccess.get_file_as_string("res://scripts/HeroMenu.gd").contains("Field Supplies")
    var rotation_before:float=menu.portrait_model.rotation.y
    var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;menu._portrait_input(press)
    var drag:=InputEventMouseMotion.new();drag.relative=Vector2(40,0);menu._portrait_input(drag)
    var rotate_ok:bool=absf(menu.portrait_model.rotation.y-rotation_before)>.25
    for i in range(7):director._spawn_bramble_wraith(20.0+float(i)*3.0,float(i))
    var wraiths:=0
    for enemy in director.minions:
        if enemy.get("kind","")=="bramble_wraith":wraiths+=1
    var map_source:=FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
    var marker_section:=map_source.get_slice("func _draw_live_markers",1).get_slice("func _player_map_heading",0)
    var large_map_clean:bool=not marker_section.contains("get_minion_positions")
    var mini_source:=FileAccess.get_file_as_string("res://scripts/Minimap.gd")
    var minimap_enemies:bool=mini_source.contains("get_minion_positions")
    hero.add_bag_item({"id":"test_fish","name":"Raw Fish","slot":"consumable","stackable":true,"stack_key":"item:raw_fish","quantity":1})
    hero.add_bag_item({"id":"test_fish_2","name":"Raw Fish","slot":"consumable","stackable":true,"stack_key":"item:raw_fish","quantity":2})
    var stack_ok:=false
    for item in hero.bag_slots:
        if item.get("stack_key","")=="item:raw_fish":stack_ok=int(item.get("quantity",1))==3
    print("INVENTORY_CREATURE|bag_slots=%d|columns=%d|equipment=%d|rotate=%s|stack=%s|crafting_removed=%s|wraiths=%d|large_map_clean=%s|minimap_enemies=%s"%[menu.bag_root.get_child_count(),menu.bag_root.columns,menu.slots_root.get_child_count(),rotate_ok,stack_ok,no_crafting,wraiths,large_map_clean,minimap_enemies])
    hero.free();director.free();menu.free();quit(0 if bag_ok and equipment_ok and rotate_ok and stack_ok and no_crafting and wraiths==7 and large_map_clean and minimap_enemies else 1)
