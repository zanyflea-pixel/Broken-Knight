extends SceneTree


func _initialize()->void:
	call_deferred("_run")


func _make_hero()->CharacterBody3D:
	var hero:=CharacterBody3D.new()
	hero.name="Player"
	var visual:=Node3D.new()
	visual.name="Visual"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	hero.add_child(visual)
	var pivot:=Node3D.new()
	pivot.name="CameraPivot"
	hero.add_child(pivot)
	var spring:=SpringArm3D.new()
	spring.name="SpringArm3D"
	pivot.add_child(spring)
	var camera:=Camera3D.new()
	camera.name="Camera3D"
	spring.add_child(camera)
	hero.set_script(load("res://scripts/HeroController.gd"))
	return hero


func _capture(path:String)->void:
	for index in range(6):await process_frame
	await create_timer(.20).timeout
	await RenderingServer.frame_post_draw
	var error:=root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("EQUIPMENT_INVENTORY_CAPTURE|%s|error=%s"%[path,error])


func _run()->void:
	var hero:=_make_hero()
	root.add_child(hero)
	await process_frame
	await process_frame
	hero.active_class="Warrior"
	hero.equip_royal_armor()
	var menu:=Control.new()
	menu.set_script(load("res://scripts/HeroMenu.gd"))
	root.add_child(menu)
	await process_frame
	menu.configure(hero,Node3D.new())
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _capture("res://artifacts/equipment_inventory_warrior.png")
	hero.switch_hero_class()
	menu.refresh()
	await _capture("res://artifacts/equipment_inventory_mage.png")
	quit(0)
