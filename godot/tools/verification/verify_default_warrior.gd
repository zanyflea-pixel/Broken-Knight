extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hero := CharacterBody3D.new()
	hero.name = "Player"

	var visual := Node3D.new()
	visual.name = "Visual"
	visual.set_script(load("res://scripts/HeroVisual.gd"))
	hero.add_child(visual)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	hero.add_child(pivot)
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	pivot.add_child(spring)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	spring.add_child(camera)

	hero.set_script(load("res://scripts/HeroController.gd"))
	root.add_child(hero)
	for frame in range(4):
		await process_frame

	var mainhand: Dictionary = hero.equipment_slots.get("mainhand", {})
	var offhand: Dictionary = hero.equipment_slots.get("offhand", {})
	var passed: bool = (
		hero.active_class == "Warrior"
		and mainhand.get("id", "") == "royal_vanguard_sword"
		and offhand.get("id", "") == "royal_vanguard_shield"
		and hero.has_warrior_weapons_equipped()
	)
	print(
		"DEFAULT_WARRIOR|class=%s|mainhand=%s|offhand=%s|ready=%s"
		% [hero.active_class, mainhand.get("id", ""), offhand.get("id", ""), passed]
	)
	quit(0 if passed else 1)
